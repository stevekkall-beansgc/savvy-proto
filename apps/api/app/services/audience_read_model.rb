# Scoped read-only projections over retained evidence. No financial calculation.
class AudienceReadModel
  def initialize(workbench)
    @w = workbench
    @m = workbench.medallion
  end

  def authorize!(case_id, internal: false)
    @m.case!(case_id)
    if internal
      @w.guard!(*MedallionWorkbench::INTERNAL)
    elsif %w[advisor ria].include?(@w.role)
      @m.error('FORBIDDEN') unless @w.role == case_id
    else
      @w.guard!(*MedallionWorkbench::INTERNAL)
    end
  end

  def summary(case_id)
    authorize!(case_id)
    row = projection(case_id)
    return {'case_id'=>case_id, 'run'=>nil, 'terms'=>[], 'publication_status'=>'not_published'} unless row
    # Select only the published summary in PostgreSQL, never deserialize the book.
    body = decode(row.pick(Arel.sql("payload->'summary'")))
    body.merge('terms'=>dated_terms(case_id, body.fetch('terms', []), body.dig('run','period_start')))
  end

  def decode(value) = value.is_a?(String) ? JSON.parse(value) : value

  def projection(case_id)
    rows = @m.source(case_id, 'baseline', 'publication').where("payload->>'projection_type' = ?", 'audience/v1').order(id: :desc)
    rows.exists? ? rows : nil
  end

  # A publication is produced on writes or explicit refresh, never by a page read.
  # It reuses assessed results and the existing statement projector; it cannot price.
  def refresh!(case_id)
    authorize!(case_id, internal: true)
    DemoScope.transaction do
      DemoScope.where(**@w.scope).lock.first!
      run = @m.source(case_id, 'baseline', 'run').order(:id).last
      return nil unless run
      view = @m.view(workspace: case_id, case_id: case_id)
      details = (Array(view.dig('run','summary')) + Array(view.dig('run','detail'))).index_by { |item| item['output_id'] }
      raw_details = Array(run.payload.dig('result','details')).index_by { |item| item['id'] }
      statement = view.delete('statement') || {'status'=>'unavailable','lines'=>[],'pending_items'=>[]}
      statement['source_record_id'] = run.id.to_s
      statement['terms'] = view.fetch('terms', []).select { |term| term['status']=='applied' }
      statement['lines'] = statement.fetch('lines', []).each_with_index.map do |line,index|
        basis = details[line['output_id']]
        if basis
          dependencies = Array(raw_details.dig(line['output_id'],'dependency_refs'))
          components = dependencies.filter_map do |id|
            item = details[id]
            raw = raw_details[id]
            next unless raw && raw['unit']=='USD_minor' && raw['assessed_minor'].is_a?(Integer)
            item || {'label'=>MedallionPresenter::LABELS.fetch(id,id.tr('_',' ').capitalize),'minor'=>raw['assessed_minor'].to_s,'currency'=>'USD'}
          end
          basis = basis.merge('components'=>components)
        end
        clients = Array(basis && basis['client_ids'])
        interval = raw_details.dig(line['output_id'],'interval') || {}
        service_start = interval['start'] || statement['service_start']
        service_end = interval['end_exclusive'] || statement['service_end_exclusive']
        # Canonical invoice-shaped lines ease downstream mapping without inventing
        # a quantity or unit price for percentage fees, caps or compensation.
        invoice_line = {'id'=>"#{run.external_id}:#{line['economic_key'] || line['application_ref'] || index+1}",
          'line_number'=>index+1,'description'=>line['label'],
          'service_period_start'=>service_start,'service_period_end_exclusive'=>service_end,
          'quantity'=>nil,'unit_amount_minor'=>nil,'amount_minor'=>line['minor'],
          'currency'=>statement['currency'] || 'USD','commercial_result_id'=>line['output_id'],
          'source_run_id'=>run.external_id}
        line.merge('source_record_id'=>run.id.to_s,'client_ids'=>clients,
          'basis'=>basis,'governing_terms'=>statement['terms'],'invoice_line'=>invoice_line)
      end
      clients = details.values.each_with_object({}) do |item,out|
        ids = Array(item['client_ids'])
        # Book-wide totals must never be copied into every underlying account.
        next unless ids.one?
        (out[ids.first] ||= []) << item
      end
      view['run']&.delete('detail')
      body = {'projection_type'=>'audience/v1','source_run_id'=>run.external_id,
        'source_run_hash'=>run.payload_hash,'source_run_revision'=>run.revision,
        'summary'=>view,'statement'=>statement,'client_results'=>clients}
      # as_of is a read clock, not new economic evidence; identical refreshes reuse
      # one publication instead of creating additional earnings or invoices.
      fingerprint = Economics::Canonical.hash(body.deep_dup.tap { |b| b['statement'].delete('as_of') })
      existing = projection(case_id)&.first
      next existing if existing && existing.payload['view_fingerprint']==fingerprint
      body['view_fingerprint']=fingerprint
      @m.store!(case_id,'baseline','publication',id:"audience-#{SecureRandom.uuid}",status:'published',payload:body,parent:run)
    end
  end

  def dated_terms(case_id, terms, anchor)
    return terms unless anchor
    assignments = @m.source(case_id,'baseline','assignment').order(:id).to_a
    latest = assignments.map(&:schedule_version).max
    terms.map do |term|
      linked = assignments.select { |a| a.payload['policy_id']==term['policy_id'] }
      active = linked.select { |a| a.schedule_version==latest }
      applicable = active.find { |a| a.starts_on && a.starts_on.iso8601<=anchor && (!a.ends_on || anchor<a.ends_on.iso8601) }
      scheduled = active.find { |a| a.starts_on && anchor<a.starts_on.iso8601 }
      status = if applicable then 'current'
      elsif scheduled then 'scheduled'
      elsif linked.any? then 'historical'
      else 'available' end
      assignment = applicable || scheduled || linked.last
      term.merge('status'=>status,'applied_for_result'=>term['status']=='applied',
        'assignment_ref'=>assignment&.external_id,
        'period_start'=>assignment&.starts_on&.iso8601 || term['period_start'],
        'period_end'=>assignment&.ends_on&.iso8601 || term['period_end'])
    end
  end

  def statement(case_id, limit: nil, offset: nil)
    authorize!(case_id)
    limit, offset, = page(limit, offset, '')
    row = projection(case_id)
    return {'status'=>'unavailable','lines'=>[],'pending_items'=>[],'total'=>0,'limit'=>limit,'offset'=>offset} unless row
    header = decode(row.pick(Arel.sql("(payload->'statement') - 'lines' - 'component_values' - 'pending_items'")))
    items = decode(row.pick(Arel.sql("COALESCE((SELECT jsonb_agg(line ORDER BY ord) FROM jsonb_array_elements(payload->'statement'->'lines') WITH ORDINALITY AS p(line,ord) WHERE ord > #{offset} AND ord <= #{offset+limit}), '[]'::jsonb)")))
    pending = decode(row.pick(Arel.sql("COALESCE((SELECT jsonb_agg(item ORDER BY ord) FROM jsonb_array_elements(payload->'statement'->'pending_items') WITH ORDINALITY AS p(item,ord) WHERE ord <= 100), '[]'::jsonb)")))
    total = row.pick(Arel.sql("jsonb_array_length(payload->'statement'->'lines')"))
    header.merge('lines'=>items, 'pending_items'=>pending, 'total'=>total, 'limit'=>limit, 'offset'=>offset)
  end

  def page(limit, offset, search)
    limit ||= 20; offset ||= 0; search ||= ''
    @m.error('VALIDATION_ERROR') unless limit.is_a?(Integer) && (1..100).cover?(limit) && offset.is_a?(Integer) && offset >= 0 && search.is_a?(String) && search.length <= 100
    [limit, offset, search]
  end

  def client_relation(case_id, search)
    rows = @m.source(case_id, 'baseline', 'fact')
    if case_id == 'advisor'
      rows.where("payload->'value'->>'subject_id' IS NOT NULL").where("payload->'value'->>'subject_id' ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(search)}%")
    else
      # The roster is retained as original bytes. PostgreSQL expands it, filters and
      # pages before returning any accounts to the application.
      artifact = @m.source(case_id, 'baseline', 'artifact').where(external_id: 'baseline-account-roster-artifact')
      ids = artifact.select(:id)
      MedallionEvidence.from("medallion_evidence CROSS JOIN LATERAL jsonb_array_elements(convert_from(medallion_evidence.original_bytes, 'UTF8')::jsonb->'accounts') AS account")
        .where(id: ids).where("account->>'id' ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(search)}%")
    end
  end

  def clients(case_id, search: nil, limit: nil, offset: nil)
    authorize!(case_id)
    limit, offset, search = page(limit, offset, search)
    rows = client_relation(case_id, search)
    expr = case_id == 'advisor' ? "payload->'value'->>'subject_id'" : "account->>'id'"
    ids = rows.distinct.order(Arel.sql(expr)).offset(offset).limit(limit).pluck(Arel.sql(expr))
    { 'items'=>ids.map { |id| {'id'=>id, 'name'=>id.tr('-', ' ').capitalize} }, 'total'=>rows.distinct.count(Arel.sql(expr)), 'limit'=>limit, 'offset'=>offset }
  end

  def client(case_id, client_id, limit: nil, offset: nil)
    authorize!(case_id); @m.id!(client_id)
    limit, offset, = page(limit, offset, '')
    rows = client_relation(case_id, client_id)
    expr = case_id == 'advisor' ? "payload->'value'->>'subject_id'" : "account->>'id'"
    @m.error('NOT_FOUND') unless rows.where("#{expr} = ?", client_id).exists?
    observations = if case_id == 'advisor'
      latest = rows.where("#{expr} = ?", client_id).select('DISTINCT ON (external_id) medallion_evidence.*').order(:external_id,revision: :desc,id: :desc)
      latest.offset(offset).limit(limit).map do |row|
        value = row.payload['value']
        {'id'=>row.external_id, 'date'=>value['date'], 'minor'=>value['value']}
      end
    else [] end
    published = projection(case_id)
    results = published ? decode(published.pick(Arel.sql("payload->'client_results'->#{ActiveRecord::Base.connection.quote(client_id)}"))) || [] : []
    account = case_id == 'ria' ? rows.where("#{expr} = ?", client_id).pick(Arel.sql('account')) : nil
    {'id'=>client_id,'name'=>client_id.tr('-', ' ').capitalize,'observations'=>observations,
      'observation_total'=>case_id=='advisor' ? rows.where("#{expr} = ?",client_id).distinct.count(:external_id) : 0,
      'limit'=>limit,'offset'=>offset,'results'=>results,'account'=>account}
  end

  NATIVE = {'obligation'=>BillingObligation,'invoice'=>BillingInvoice,
    'invoice_line'=>BillingInvoiceLine,'instruction'=>BillingInstruction,
    'accounting'=>BillingAccountingFact,'rate'=>CommercialRate}.freeze

  def native_relations(case_id)
    brokers = case_id=='advisor' ? %w[advisor-demo broker-alex broker-jordan] : ['ria-harbor']
    obligations = BillingObligation.where(**@w.scope,broker_id:brokers)
    lines = BillingInvoiceLine.where(**@w.scope,billing_obligation_id:obligations.select(:id))
    items = BillingInstructionItem.where(billing_obligation_id:obligations.select(:id))
    invoices = BillingInvoice.where(**@w.scope,id:lines.select(:billing_invoice_id))
    instructions = BillingInstruction.where(**@w.scope,id:items.select(:billing_instruction_id))
    accounting = BillingAccountingFact.where(**@w.scope,billing_invoice_id:invoices.select(:id))
      .or(BillingAccountingFact.where(**@w.scope,billing_instruction_id:instructions.select(:id)))
    policies = MedallionEvidence.where(**@w.scope,case_id:case_id,kind:'policy').select(:external_id)
    rates = CommercialRate.where(**@w.scope,configuration_id:policies)
    {'obligation'=>obligations,'invoice'=>invoices,'invoice_line'=>lines,'instruction'=>instructions,'accounting'=>accounting,'rate'=>rates}
  end

  def native_record(kind, row)
    {'id'=>"#{kind}:#{row.id}",'kind'=>kind,'external_id'=>row.external_id,
      'revision'=>row.respond_to?(:revision) ? row.revision : 1,
      'status'=>row.respond_to?(:status) ? row.status : (kind=='accounting' ? row.reported_status : 'retained'),
      'recorded_at'=>(row.respond_to?(:observed_at) ? row.observed_at : (row.respond_to?(:recorded_at) ? row.recorded_at : nil))&.iso8601(6),
      'contract_version'=>"savvy-billing/#{kind}/v1"}
  end

  def lineage_records(case_id, search: nil, limit: nil, offset: nil)
    authorize!(case_id, internal: true)
    limit, offset, search = page(limit, offset, search)
    connection = ActiveRecord::Base.connection
    sources = [MedallionEvidence.where(**@w.scope,case_id:case_id).select("id AS sort_id, 0 AS source_order, id::text AS record_id, kind, external_id, revision, status, scenario_id, recorded_at").to_sql]
    native_relations(case_id).each_with_index do |(kind,relation),index|
      status = NATIVE.fetch(kind).column_names.include?('status') ? 'status' : (kind=='accounting' ? 'reported_status' : "'retained'")
      revision = NATIVE.fetch(kind).column_names.include?('revision') ? 'revision' : '1'
      clock = kind=='accounting' ? 'observed_at' : (kind=='rate' ? 'recorded_at' : 'NULL::timestamp')
      sources << relation.select("id AS sort_id, #{index+1} AS source_order, '#{kind}:' || id AS record_id, '#{kind}' AS kind, external_id, #{revision} AS revision, #{status} AS status, 'commercial' AS scenario_id, #{clock} AS recorded_at").to_sql
    end
    union = sources.join(' UNION ALL ')
    filter = search.empty? ? '' : " WHERE external_id ILIKE #{connection.quote('%'+ActiveRecord::Base.sanitize_sql_like(search)+'%')} OR kind ILIKE #{connection.quote('%'+ActiveRecord::Base.sanitize_sql_like(search)+'%')}"
    total = connection.select_value("SELECT count(*) FROM (#{union}) records#{filter}").to_i
    rows = connection.exec_query("SELECT * FROM (#{union}) records#{filter} ORDER BY source_order, sort_id LIMIT #{limit} OFFSET #{offset}").to_a
    items = rows.map { |r| r.except('sort_id','source_order').merge('id'=>r['record_id']).except('record_id') }
    {'items'=>items, 'total'=>total, 'limit'=>limit, 'offset'=>offset}
  end

  def record(row)
    {'id'=>row.id.to_s,'kind'=>row.kind,'external_id'=>row.external_id,'revision'=>row.revision,'status'=>row.status,'scenario_id'=>row.scenario_id,'recorded_at'=>row.recorded_at.iso8601(6),'contract_version'=>'savvy-medallion/evidence/v1'}
  end

  SERVICES = {'artifact'=>'Source adapter and immutable intake','delivery'=>'Intake validation',
    'fact'=>'Normalization and validation','policy'=>'Commercial policy API',
    'assignment'=>'Policy binding service','run'=>'Shared billing interpreter',
    'publication'=>'Publication and reporting service','statement'=>'Statement projection',
    'payment'=>'Payment evidence adapter','application'=>'Cash allocation service',
    'application_reversal'=>'Allocation reversal service','event'=>'One-time item API',
    'review'=>'Policy review service','event_review'=>'One-time item review service'}.freeze

  def edge(input, output, service, proof, status: 'recorded_link')
    {'input'=>input,'output'=>output,'service'=>service,'execution_status'=>status,
      'contract_version'=>'savvy-lineage/edge/v1','validation'=>output['status'],
      'completeness'=>status=='missing_evidence' ? 'missing' : 'linked', 'evidence'=>proof}
  end

  def native_detail(case_id, record_id, limit:, offset:)
    kind,id = record_id.split(':',2)
    @m.error('NOT_FOUND') unless NATIVE.key?(kind) && id.to_s.match?(/\A\d{1,18}\z/)
    relations = native_relations(case_id)
    row = relations.fetch(kind).find_by(id:id) || @m.error('NOT_FOUND')
    meta = native_record(kind,row)
    edges = []
    if kind=='invoice'
      relations['invoice_line'].where(billing_invoice_id:row.id).each do |line|
        edges << edge(native_record('invoice_line',line),meta,'Savvy commercial billing API','Persisted invoice/line foreign key')
      end
    elsif kind=='invoice_line'
      obligation=relations['obligation'].find_by(id:row.billing_obligation_id)
      invoice=relations['invoice'].find_by(id:row.billing_invoice_id)
      edges << edge(native_record('obligation',obligation),meta,'Savvy commercial billing API','Persisted obligation/line foreign key') if obligation
      edges << edge(meta,native_record('invoice',invoice),'Savvy commercial billing API','Persisted line/invoice foreign key') if invoice
    elsif kind=='obligation'
      sources=MedallionEvidence.where(**@w.scope,case_id:case_id,kind:'run',external_id:row.source_id,revision:row.source_revision)
      source=sources.first
      edges << edge(source ? record(source) : {'external_id'=>row.source_id,'revision'=>row.source_revision},meta,'Savvy commercial billing API','Obligation source identity/revision',status:source ? 'recorded_link' : 'missing_evidence')
      relations['invoice_line'].where(billing_obligation_id:row.id).each { |line| edges << edge(meta,native_record('invoice_line',line),'Savvy commercial billing API','Persisted obligation/line foreign key') }
    elsif kind=='accounting'
      parent_kind=row.billing_invoice_id ? 'invoice' : 'instruction'
      parent=relations.fetch(parent_kind).find_by(id:row.billing_invoice_id || row.billing_instruction_id)
      edges << edge(native_record(parent_kind,parent),meta,'Mock accounting adapter','Supplied observation linked to commercial foreign key',status:'mock_handoff') if parent
    elsif kind=='instruction'
      items=BillingInstructionItem.where(billing_instruction_id:row.id,billing_obligation_id:relations['obligation'].select(:id))
      relations['obligation'].where(id:items.select(:billing_obligation_id)).each do |obligation|
        edges << edge(native_record('obligation',obligation),meta,'Savvy custodial instruction API','Persisted instruction-item/obligation allocation')
      end
    elsif kind=='rate'
      policy=MedallionEvidence.where(**@w.scope,case_id:case_id,kind:'policy',external_id:row.configuration_id).first
      edges << edge(meta,record(policy),'Commercial policy API','Rate configuration identity retained in the shared rate table') if policy
    end
    candidates=MedallionEvidence.where(**@w.scope,case_id:case_id).where("payload @> ?::jsonb", {"#{kind}_id"=>row.external_id}.to_json)
    candidates.each { |r| edges << edge(meta,record(r),'Savvy evidence association','Explicit commercial object identity in retained evidence') }
    {'record'=>meta.merge('payload'=>row.attributes.except('id'),'payload_hash'=>Economics::Canonical.hash(row.attributes.except('id'))),
      'edges'=>edges.slice(offset,limit) || [],'edge_total'=>edges.length,'edge_limit'=>limit,'edge_offset'=>offset}
  end

  # A manifest can contain facts that the graph never consumed. An execution
  # edge requires the same manifest key in a recorded interpreter binding and
  # the matching source reference on that binding's evaluated node. Normalized
  # facts resolve through their exact retained evidence identities, not names or
  # matching amounts.
  def executed_input_refs(run)
    facts=run.payload.dig('input_manifest','facts')
    result=run.payload['result']
    return [] unless facts.is_a?(Hash) && result.is_a?(Hash)
    bindings=Hash.new { |hash,key| hash[key]=[] }
    Array(result['bindings']).each do |binding|
      next unless binding.is_a?(Hash)
      ([binding['fact']] + Array(binding['facts'])).compact.uniq.each { |key| bindings[key] << binding }
    end
    details=Array(result['details']).select { |detail| detail.is_a?(Hash) }.index_by { |detail| detail['id'] }
    refs=[]
    facts.each do |key,fact|
      next unless fact.is_a?(Hash) && fact['id'].is_a?(String) && fact['revision'].is_a?(Integer)
      bindings[key].each do |binding|
        detail=details[binding['node']]; sources=detail.is_a?(Hash) ? Array(detail['source_refs']) : []
        next unless sources.any? { |source| source.is_a?(Hash) && source['key']==key && source['id']==fact['id'] && source['revision']==fact['revision'] }
        linked=Array(fact['evidence_refs']).select do |ref|
          ref.is_a?(Hash) && ref['external_id'].is_a?(String) && ref['revision'].is_a?(Integer) && ref['hash'].is_a?(String) &&
            sources.any? { |source| source.is_a?(Hash) && source['external_id']==ref['external_id'] && source['revision']==ref['revision'] && source['hash']==ref['hash'] && (!ref['id'] || source['id'].to_s==ref['id'].to_s) }
        end
        if linked.any?
          refs.concat(linked.map { |ref| {'id'=>ref['external_id'],'revision'=>ref['revision'],'hash'=>ref['hash'],'record_id'=>ref['id']} })
        elsif Array(fact['evidence_refs']).empty? && fact['hash'].is_a?(String)
          refs << {'id'=>fact['id'],'revision'=>fact['revision'],'hash'=>fact['hash']}
        end
      end
    end
    refs.uniq { |ref| [ref['id'],ref['revision'],ref['hash'],ref['record_id']] }
  end

  def lineage_record(case_id, record_id, limit: nil, offset: nil)
    authorize!(case_id, internal: true)
    limit,offset, = page(limit,offset,'')
    return native_detail(case_id,record_id,limit:limit,offset:offset) if record_id.to_s.include?(':')
    @m.error('NOT_FOUND') unless record_id.to_s.match?(/\A\d{1,18}\z/)
    rows = MedallionEvidence.where(**@w.scope, case_id: case_id)
    row = rows.find_by(id: record_id) || @m.error('NOT_FOUND')
    rows = rows.where(scenario_id: row.scenario_id)
    related = rows.where(id: row.parent_id).or(rows.where(parent_id: row.id)).order(:id)
    edges = related.map do |other|
      parent, child = other.id == row.parent_id ? [other,row] : [row,other]
      mocked = child.payload['source']=='mock_accounting'
      service = mocked ? 'Mock Campfire accounting adapter' : SERVICES.fetch(child.kind,'Savvy evidence service')
      edge(record(parent),record(child),service,'Persisted parent reference; detailed service execution is not recorded',status:mocked ? 'mock_handoff' : 'recorded_link')
    end
    # Source artifacts and selected run inputs can have more than one downstream
    # record. Match exact retained IDs/revisions, not labels or equal amounts.
    rows.where("payload->>'source_artifact_id' = ?",row.external_id).each do |child|
      edges << edge(record(row),record(child),'Normalization and validation','Explicit original artifact identity')
    end
    rows.where(kind:'run').where("payload->'input_manifest'->'source_evidence' @> ?::jsonb",[{'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}].to_json).each do |run|
      edges << edge(record(row),record(run),'Selected source evidence','Exact source revision/hash retained in run manifest',status:'recorded_link')
    end
    if row.kind=='fact'
      rows.where(kind:'run').order(:id).each do |run|
        consumed=executed_input_refs(run).any? do |ref|
          ref['id']==row.external_id && ref['revision']==row.revision && ref['hash']==row.payload_hash && (!ref['record_id'] || ref['record_id'].to_s==row.id.to_s)
        end
        edges << edge(record(row),record(run),'Shared billing interpreter','Exact source revision/hash consumed by a recorded graph binding',status:'recorded_execution') if consumed
      end
    end
    native_relations(case_id).each do |kind,relation|
      key=kind=='invoice_line' ? 'invoice_line_id' : "#{kind}_id"
      reference=row.payload[key]
      reference ||= row.payload.dig('commercial_refs',key) if row.payload['commercial_refs'].is_a?(Hash)
      next unless reference.is_a?(String)
      native=relation.find_by(external_id:reference)
      edges << edge(native ? native_record(kind,native) : {'external_id'=>reference,'kind'=>kind},record(row),kind=='accounting' ? 'Mock accounting adapter' : 'Savvy billing evidence association','Explicit commercial identity in retained record',status:native ? 'recorded_link' : 'missing_evidence')
    end
    if row.kind == 'run'
      manifest = row.payload.fetch('input_manifest', {})
      executed=executed_input_refs(row)
      refs = executed + Array(manifest['source_evidence']) + [manifest['assignment']].compact
      refs.select { |ref| ref.is_a?(Hash) && ref['id'] }.uniq { |ref| [ref['id'], ref['revision'], ref['hash']] }.each do |ref|
        candidates = rows.where(external_id: ref['id'])
        candidates = candidates.where(revision: ref['revision']) if ref['revision']
        candidates = candidates.where(payload_hash: ref['hash']) if ref['hash']
        input = candidates.first
        used=executed.any? { |item| item['id']==ref['id'] && item['revision']==ref['revision'] && item['hash']==ref['hash'] && (!item['record_id'] || input && input.id.to_s==item['record_id'].to_s) }
        status=input ? (used ? 'recorded_execution' : 'recorded_link') : 'missing_evidence'
        edges << edge(input ? record(input) : ref,record(row),used ? 'Shared billing interpreter' : 'Selected source evidence',used ? 'Consumed input referenced by an exact recorded binding' : 'Evidence selected in the retained run manifest',status:status)
      end
      Array(row.payload.dig('result','details')).each do |detail|
        edges << edge(record(row),{'id'=>detail['id'],'kind'=>'calculation_detail','run_id'=>row.external_id,'revision'=>row.revision,'status'=>detail['status']},'Shared billing interpreter',detail.slice('unit','basis','value','assessed_minor','source_refs','dependency_refs','binding_refs','interval'),status:'recorded_execution')
      end
      selected_rates = Array(row.payload.dig('result','details')).flat_map { |d| d.fetch('source_refs',[]) }.select { |r| r['kind']=='policy_rate' }.uniq { |r| r['id'] }
      selected_rates.each do |reference|
        rate=native_relations(case_id)['rate'].find_by(configuration_id:row.payload['policy_id'],external_id:reference['id'])
        edges << edge(rate ? native_record('rate',rate) : reference,record(row),'Policy binding in the shared billing interpreter','Exact selected rate configuration and source reference',status:rate ? 'recorded_execution' : 'missing_evidence')
      end
    end
    edges = edges.uniq { |e| [e['input']['id'],e['output']['id'],e['service'],e['execution_status']] }
    {'record'=>record(row).merge('payload'=>row.payload,'payload_hash'=>row.payload_hash,
      'original_bytes'=>row.original_bytes&.force_encoding('UTF-8')&.scrub, 'parent_id'=>row.parent_id&.to_s),
      'edges'=>edges.slice(offset,limit) || [],'edge_total'=>edges.length,'edge_limit'=>limit,'edge_offset'=>offset}
  end
end
