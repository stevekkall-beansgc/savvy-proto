class CashBook
  def initialize(workbench)
    @workbench=workbench
  end
  attr_reader :workbench

  def active_matches(cutoff: nil)
    matches=DemoAllocation.where(**workbench.scope,kind:'operational_match')
    reversals=DemoMatchReversal.where(**workbench.scope)
    if cutoff
      time=Economics::Engine.new.time!(cutoff)
      matches=matches.where('created_at <= ?',time)
      reversals=reversals.where('created_at <= ?',time)
    end
    matches.where.not(id:reversals.select(:allocation_id))
  end

  def current_receipts(cutoff: nil)
    return workbench.current_records('receipt') unless cutoff
    time=Economics::Engine.new.time!(cutoff)
    workbench.records('receipt').where('recorded_at <= ?',time)
      .where("COALESCE((payload->>'recorded_at')::timestamptz,recorded_at) <= ?",time)
      .select('DISTINCT ON (external_id) demo_records.*').order(:external_id,revision: :desc,id: :desc)
  end

  def history(charge_id,cutoff: nil)
    rows=DemoAllocation.where(**workbench.scope,kind:'operational_match',target_id:charge_id)
    rows=rows.where('created_at <= ?',Economics::Engine.new.time!(cutoff)) if cutoff
    rows.order(:id).map do |m|
      reversal=DemoMatchReversal.find_by(**workbench.scope,allocation_id:m.id)
      reversal=nil if cutoff && reversal && reversal.created_at>Economics::Engine.new.time!(cutoff)
      { 'id'=>m.id.to_s,'receipt_id'=>m.source_id,'minor_units'=>m.minor_units,'recorded_at'=>m.created_at.iso8601(6),
        'status'=>reversal ? 'reversed' : 'active','reversal_reason'=>reversal&.reason,'reversal_actor'=>reversal&.actor_id }
    end
  end

  def reverse_match(input,key)
    workbench.guard!('finance')
    workbench.operate('reverse_match',input,key) do
      original=DemoAllocation.find_by(**workbench.scope,kind:'operational_match',id:input.fetch('allocation_id'))
      raise Economics::Error.new('NOT_FOUND') unless original
      raise Economics::Error.new('ALREADY_REVERSED') if DemoMatchReversal.exists?(**workbench.scope,allocation_id:original.id)
      reason=workbench.settlement_book.reason!(input['reason'])
      reversal=DemoMatchReversal.create!(**workbench.scope,allocation_id:original.id,actor_id:workbench.role,reason:reason,created_at:Time.current)
      { 'id'=>reversal.id.to_s,'allocation_id'=>original.id.to_s,'released_minor'=>original.minor_units,'cash_reversed'=>false,'accounting_posted'=>false }
    end
  end

  def reverse_receipt(input,key)
    workbench.guard!('finance')
    workbench.operate('reverse_receipt',input,key) do
      receipt=workbench.record!('receipt',input.fetch('receipt_id'))
      Economics::Engine.new.scope!(receipt,workbench.policy)
      expected=Economics::Engine.integer!(input['expected_revision'],'expected_revision',min:1)
      raise Economics::Error.new('REVISION_CONFLICT','Receipt evidence changed; reload before acting') unless receipt['revision']==expected
      raise Economics::Error.new('ALREADY_REVERSED') unless receipt['status']=='verified_cash'
      reason=workbench.settlement_book.reason!(input['reason'])
      matches=active_matches.where(source_id:receipt['id']).order(:id).to_a
      now=Time.at(Rational((Time.current.to_r*1_000_000).floor,1_000_000)).utc
      previous_record=workbench.records('receipt').where(external_id:receipt['id']).maximum(:recorded_at)
      previous_match=matches.map(&:created_at).max
      [previous_record,previous_match].compact.each { |time| now=time+Rational(1,1_000_000) if now<=time }

      reversed=receipt.merge('revision'=>receipt['revision']+1,'status'=>'reversed','synthetic'=>true,
        'recorded_at'=>now.iso8601(6),'reversal_of_revision'=>receipt['revision'],'reversal_reason'=>reason,
        'previous_view_cutoff'=>(now-Rational(1,1_000_000)).iso8601(6),'bank_refund_verified'=>false)
      workbench.write!('receipt',reversed,revision:reversed['revision'],recorded_at:now)
      matches.each do |m|
        DemoMatchReversal.create!(**workbench.scope,allocation_id:m.id,actor_id:workbench.role,reason:"Receipt reversal: #{reason}",created_at:now)
      end
      { 'receipt_id'=>receipt['id'],'revision'=>reversed['revision'],'status'=>'reversed',
        'released_match_minor'=>matches.sum(&:minor_units),'previous_view_cutoff'=>reversed['previous_view_cutoff'],
        'bank_refund_verified'=>false,'accounting_posted'=>false }
    end
  end
end
