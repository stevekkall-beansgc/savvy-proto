class SettlementBook
  def initialize(workbench)
    @workbench = workbench
  end
  attr_reader :workbench

  def entries(cutoff: nil)
    rows = DemoEntitlementEntry.where(**workbench.scope)
    cutoff ? rows.where('created_at <= ?', Economics::Engine.new.time!(cutoff)) : rows
  end

  def net_minor(rows)
    rows.sum { |r| r.kind == 'consume' ? r.minor_units : -r.minor_units }
  end

  def reason!(value)
    unless value.is_a?(String) && value.strip.length.between?(3,300)
      raise Economics::Error.new('VALIDATION_ERROR','A reason of 3–300 characters is required')
    end
    value.strip
  end

  def visible_broker?(id)
    workbench.role != 'advisor' || id == 'broker-alex'
  end

  def balance(grant, cutoff: nil)
    grant.fetch('opening_minor') - net_minor(entries(cutoff: cutoff).where(grant_id: grant.fetch('id')))
  end

  def view(broker_id = nil)
    allowed = workbench.directory['brokers'].map { |b| b['id'] }
    if broker_id && (!allowed.include?(broker_id) || !visible_broker?(broker_id))
      raise Economics::Error.new('NOT_FOUND')
    end
    grants = workbench.current_records('grant').map(&:payload).select do |g|
      allowed.any? { |b| visible_broker?(b) && [g['payer'],g['payee']].include?(b) && (!broker_id || b == broker_id) }
    end
    obligations = workbench.current_records('obligation').map(&:payload).select do |o|
      visible_broker?(o['broker_id']) && (!broker_id || o['broker_id'] == broker_id)
    end
    grant_rows = grants.map do |g|
      g.merge('applied_minor'=>net_minor(entries.where(grant_id:g['id'])), 'remaining_minor'=>balance(g))
    end
    obligation_rows = obligations.map do |o|
      applied = net_minor(entries.where(obligation_id:o['id']))
      candidates = grant_rows.select { |g| eligible?(g,o) }.sort_by { |g| [g.fetch('priority'),g['id']] }
      selected = candidates.find { |g| g['remaining_minor'] > 0 }
      o.merge('applied_minor'=>applied,'uncovered_minor'=>o['amount_minor']-applied,
        'suggested_grant_id'=>selected&.fetch('id'),
        'suggested_minor'=>selected ? [o['amount_minor']-applied,selected['remaining_minor']].min : 0)
    end
    visible_ids=grants.map { |g| g['id'] }
    history=entries.where(grant_id:visible_ids).order(:id).map do |e|
      { 'id'=>e.id.to_s,'grant_id'=>e.grant_id,'obligation_id'=>e.obligation_id,'kind'=>e.kind,
        'minor_units'=>e.minor_units,'original_entry_id'=>e.original_entry_id&.to_s,
        'reason'=>e.reason,'actor'=>e.actor_id,'recorded_at'=>e.created_at.iso8601(6),
        'reversed'=>entries.exists?(original_entry_id:e.id,kind:'reversal') }
    end
    { 'synthetic'=>true,'grants'=>grant_rows,'obligations'=>obligation_rows,'entries'=>history,
      'payment_executed'=>false,'accounting_posted'=>false,
      'note'=>'Recorded fictional coverage only. Opposite directions remain separate. Projections use a copied as-known balance.' }
  end

  def eligible?(grant, obligation)
    engine = Economics::Engine.new
    engine.scope!(grant,obligation)
    grant['payer']==obligation['payer'] && grant['payee']==obligation['payee'] &&
      grant['component']==obligation['component'] &&
      (grant['customer_id'].nil? || grant['customer_id']==obligation['customer_id']) &&
      engine.date!(grant['valid_from']) <= engine.date!(obligation['business_date']) &&
      engine.date!(obligation['business_date']) < engine.date!(grant['valid_to']) && grant['approved']==true &&
      obligation['status']=='approved_for_demo'
  end

  def consume(input,key)
    workbench.guard!('finance')
    workbench.operate('consume_entitlement',input,key) do
      g=workbench.record!('grant',input.fetch('grant_id'))
      o=workbench.record!('obligation',input.fetch('obligation_id'))
      raise Economics::Error.new('DIRECTION_MISMATCH','Grant and obligation must have the same scope, parties, component and eligibility period') unless eligible?(g,o)
      amount=Economics::Engine.integer!(input['minor_units'],'minor_units',min:1)
      remaining_obligation=o['amount_minor']-net_minor(entries.where(obligation_id:o['id']))
      if amount>balance(g) || amount>remaining_obligation
        raise Economics::Error.new('ALLOCATION_EXCEEDED','Recorded applications cannot exceed grant or obligation remaining')
      end
      e=DemoEntitlementEntry.create!(**workbench.scope,grant_id:g['id'],obligation_id:o['id'],kind:'consume',minor_units:amount,currency:'USD',
        actor_id:workbench.role,reason:reason!(input['reason']),business_date:Workbench::DATE,created_at:Time.current)
      { 'entry_id'=>e.id.to_s,'kind'=>'consume','minor_units'=>amount,'remaining_grant_minor'=>balance(g),'payment_executed'=>false }
    end
  end

  def reverse(input,key)
    workbench.guard!('finance')
    workbench.operate('reverse_entitlement',input,key) do
      original=entries.find_by(id:input.fetch('entry_id'))
      raise Economics::Error.new('NOT_FOUND') unless original
      raise Economics::Error.new('INVALID_REVERSAL','Only an original consumption may be reversed') unless original.kind=='consume'
      raise Economics::Error.new('ALREADY_REVERSED') if entries.exists?(original_entry_id:original.id)
      e=DemoEntitlementEntry.create!(**workbench.scope,grant_id:original.grant_id,obligation_id:original.obligation_id,kind:'reversal',
        minor_units:original.minor_units,currency:original.currency,original_entry_id:original.id,actor_id:workbench.role,
        reason:reason!(input['reason']),business_date:Workbench::DATE,created_at:Time.current)
      { 'entry_id'=>e.id.to_s,'original_entry_id'=>original.id.to_s,'kind'=>'reversal','restored_minor'=>original.minor_units,'payment_executed'=>false }
    end
  end

  def projection_snapshot(source,cutoff:)
    snapshot=Economics::Canonical.copy(source)
    opening=snapshot.fetch('grants',[])
    selected_entries=[]
    opening.each do |g|
      grant=workbench.current_records('grant',cutoff:cutoff).find_by(external_id:g['id'])&.payload
      next unless grant
      Economics::Engine.new.scope!(grant,snapshot)
      raise Economics::Error.new('SOURCE_CONFLICT','An import cannot reset an established grant opening balance') unless g['remaining_minor']==grant['opening_minor']
      relevant=entries(cutoff:cutoff).where(grant_id:g['id']).where('business_date <= ?',source['business_date'])
      g['remaining_minor']=grant['opening_minor']-net_minor(relevant)
      selected_entries.concat(relevant.order(:id).map { |e| {'id'=>e.id.to_s,'kind'=>e.kind,'grant_id'=>e.grant_id,'minor_units'=>e.minor_units,'recorded_at'=>e.created_at.iso8601(6)} })
    end
    snapshot['grant_balance_manifest']={'basis'=>'source_opening_less_recorded_entries_at_cutoff','entries'=>selected_entries}
    snapshot
  end
end
