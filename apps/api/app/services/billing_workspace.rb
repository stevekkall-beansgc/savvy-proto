# Scoped read projections. Reads never seed, price, normalize or issue documents.
class BillingWorkspace
  def initialize(workbench,case_id)
    @p=BillingPlatform.new(workbench,case_id); @w=workbench
  end
  def view(audience:,section:'overview',subject_id:nil,record_id:nil,service_start:nil,service_end_exclusive:nil,limit:20,offset:0,search:nil)
    @p.error('VALIDATION_ERROR') unless %w[client product finance].include?(audience) && %w[overview clients statements terms pipeline queue calculations].include?(section)
    if audience=='client'
      @p.error('FORBIDDEN') unless @w.role==@p.case_id || MedallionWorkbench::INTERNAL.include?(@w.role)
    else @w.guard!('operator','legal','finance','auditor') end
    @p.error('VALIDATION_ERROR') unless limit.is_a?(Integer) && limit.between?(1,100) && offset.is_a?(Integer) && offset>=0
    @p.error('VALIDATION_ERROR') if search && (!search.is_a?(String) || search.length>100)
    @internal=audience!='client'; @limit,@offset,@search=limit,offset,search
    read=proc do
      periods=@p.rows(@internal ? 'calculation' : 'document').select("DISTINCT payload->>'service_start' AS starts, payload->>'service_end_exclusive' AS ends").order(Arel.sql('starts DESC, ends DESC')).limit(1000).map { |r| {'start'=>r['starts'],'end_exclusive'=>r['ends']} }
      @start=service_start || periods.first&.fetch('start'); @finish=service_end_exclusive || periods.first&.fetch('end_exclusive')
      @p.interval!(@start,@finish) if @start && @finish
      body={'available'=>@p.rows('source').exists?,'case_id'=>@p.case_id,'audience'=>audience,'section'=>section,'periods'=>periods,'period'=>{'start'=>@start,'end_exclusive'=>@finish},'page'=>{'limit'=>limit,'offset'=>offset},'campfire'=>{'mocked'=>true,'connected'=>false},'clm'=>{'mocked'=>true,'connected'=>false}}
      return body.merge('record'=>detail(record_id)) if record_id
      body['summary']=summary if %w[overview statements].include?(section)
      case section
      when 'overview'
        body['activity']=document_rows.limit(5).map { |r| document(r) }
      when 'clients' then body.merge!(clients(subject_id))
      when 'statements'
        relation=document_rows; relation=relation.where("payload->>'subject_id' = ?",subject_id) if subject_id
        body['page']['total']=relation.count; body['documents']=relation.offset(offset).limit(limit).map { |r| document(r) }
      when 'terms' then body.merge!(terms(subject_id))
      when 'pipeline'
        @p.error('FORBIDDEN') unless @internal
        body.merge!(pipeline)
      when 'queue'
        @p.error('FORBIDDEN') unless @internal
        body.merge!(queue(audience))
      when 'calculations'
        @p.error('FORBIDDEN') unless @internal
        relation=period_scope(@p.rows('calculation')).order(id: :desc); relation=relation.where("payload->>'subject_id' = ?",subject_id) if subject_id
        body['page']['total']=relation.count
        body['failures']=@p.rows('calculation_attempt').order(id: :desc).limit(20).map { |r| serialize(r).merge('data'=>r.payload) }
        body['calculations']=relation.offset(offset).limit(limit).map do |r|
          root=document_rows.where("payload->>'document_type' = 'invoice' AND payload->>'subject_id' = ?",r.payload['subject_id']).first
          serialize(r).merge('data'=>r.payload.except('segments'),'original_document_id'=>root&.external_id,'issued_target_run_id'=>root && BillingDocuments.new(@p).target(root).external_id)
        end
      end
      body
    end
    ActiveRecord::Base.connection.transaction_open? ? read.call : ActiveRecord::Base.transaction(isolation: :repeatable_read,&read)
  end
  def period_scope(relation)
    return relation unless @start && @finish
    relation.where("payload->>'service_start' = ? AND payload->>'service_end_exclusive' = ?",@start,@finish)
  end
  def document_rows = period_scope(@p.rows('document')).order(id: :desc)
  def summary
    ids=document_rows.reorder(nil).select("(payload->>'native_invoice_id')::bigint")
    relation=BillingInvoice.where(**@w.scope,id:ids,billing_case_id:@p.case_id)
    totals=relation.group(:document_type).sum(:amount_minor)
    # Aggregation of issued native records is not a price calculation.
    billed=totals.fetch('invoice',0)+totals.fetch('debit_note',0)-totals.fetch('credit_note',0)
    roots=document_rows.reorder(nil).where("payload->>'document_type' = 'invoice'")
    target_ids=roots.select("COALESCE((SELECT ci.payload->>'target_run_id' FROM medallion_evidence ci WHERE ci.tenant_id=medallion_evidence.tenant_id AND ci.entity_id=medallion_evidence.entity_id AND ci.case_id=medallion_evidence.case_id AND ci.scenario_id=medallion_evidence.scenario_id AND ci.kind='correction_issue' AND ci.parent_id=medallion_evidence.id ORDER BY ci.id DESC LIMIT 1), payload->>'run_id')")
    selected=@p.rows('calculation').where("external_id IN (#{target_ids.to_sql})")
    compensation=selected.where("payload->>'compensation_minor' IS NOT NULL").exists? ? selected.sum(Arel.sql("(payload->>'compensation_minor')::bigint")).to_i : nil
    payouts=selected.where("payload->>'additional_payout_minor' IS NOT NULL").exists? ? selected.sum(Arel.sql("(payload->>'additional_payout_minor')::bigint")).to_i : nil
    benefit=selected.sum(Arel.sql("(payload->>'pricing_benefit_minor')::bigint")).to_i
    {'original_billed_minor'=>totals.fetch('invoice',0),'debit_minor'=>totals.fetch('debit_note',0),'credit_minor'=>totals.fetch('credit_note',0),'corrected_billed_minor'=>billed,'compensation_minor'=>@p.case_id=='advisor' ? compensation : nil,'additional_payout_minor'=>payouts,'pricing_benefit_minor'=>benefit,'document_count'=>relation.count,'billing_subject_count'=>relation.where(document_type:'invoice').distinct.count(:billing_subject_id),'cash_status'=>'Separate payment evidence','recognition_status'=>'Mock accounting handoff only'}
  end
  def serialize(row)
    {'id'=>row.external_id,'record_id'=>row.id.to_s,'kind'=>row.kind,'status'=>row.status,'hash'=>row.payload_hash,'recorded_at'=>row.recorded_at.iso8601(6)}
  end
  def document(row)
    invoice=BillingDocuments.new(@p).native(row)
    @p.error('HASH_CHANGED','Native document evidence no longer matches') unless BillingDocuments.new(@p).native_hash(invoice)==row.payload['native_hash']
    lines=BillingInvoiceLine.where(**@w.scope,billing_invoice_id:invoice.id).order(:id)
    obligations=BillingObligation.where(**@w.scope,id:lines.select(:billing_obligation_id)).index_by(&:id)
    result={'id'=>invoice.external_id,'type'=>invoice.document_type,'amount_minor'=>invoice.amount_minor,'currency'=>invoice.currency,'payer'=>invoice.debtor_id,'payee'=>invoice.creditor_id,'subject_id'=>invoice.billing_subject_id,'service_start'=>row.payload['service_start'],'service_end_exclusive'=>row.payload['service_end_exclusive'],'issued_on'=>invoice.issued_on&.iso8601,'due_on'=>invoice.due_on&.iso8601,'posting_period'=>invoice.posting_period,'original_document_id'=>row.payload['original_document_id'],'status'=>invoice.status,'lines'=>lines.map { |line| o=obligations.fetch(line.billing_obligation_id); {'id'=>line.external_id,'account_id'=>o.account_id,'customer_id'=>o.customer_id,'description'=>invoice.document_type=='invoice' ? 'Agreed service charge' : 'Billing correction','amount_minor'=>line.amount_minor,'service_start'=>o.service_period_start.iso8601,'service_end_exclusive'=>o.service_period_end.iso8601} }}
    result['run_id']=row.payload['run_id'] if @internal
    observations=BillingPipeline.new(@p).current(Time.current.iso8601(6),types:%w[cash accounting]).where("payload->'record'->>'document_id' = ?",invoice.external_id).order(:id).limit(100).to_a
    result['payment_evidence']=observations.select { |r| r.product_id=='cash' }.filter_map do |r|
      value=r.payload['record']; valid=value['billing_subject_id']==invoice.billing_subject_id && value['currency']==invoice.currency && value['payer_id']==invoice.debtor_id && value['payee_id']==invoice.creditor_id && value['direction']==(invoice.creditor_id=='firm-demo' ? 'inbound' : 'outbound')
      next unless valid || @internal
      {'id'=>r.external_id,'amount_minor'=>value['amount_minor'],'date'=>value['date'],'status'=>value['status'],'direction'=>value['direction'],'link_status'=>valid ? 'document_identity_verified' : 'needs_review'}
    end
    if @internal
      result['accounting_evidence']=observations.select { |r| r.product_id=='accounting' }.map do |r|
        value=r.payload['record']; valid=value['billing_subject_id']==invoice.billing_subject_id && value['currency']==invoice.currency && value['amount_minor']==invoice.amount_minor
        {'id'=>r.external_id,'provider'=>'mock_campfire','mocked'=>true,'reported_status'=>value['reported_status'],'recognized_minor'=>value['recognized_minor'],'deferred_minor'=>value['deferred_minor'],'link_status'=>valid ? 'document_identity_verified' : 'needs_review','journal_id'=>value['journal_id']}
      end
    end
    if row.payload['original_document_id']
      issued=@p.rows('correction_issue').where("payload->'document_ids' @> ?::jsonb",[row.external_id].to_json).order(:id).last
      proposal=issued && @p.get('correction_proposal',issued.payload['proposal_id'])
      result['correction_basis']=proposal&.payload&.slice('before_minor','after_minor','changes','reason')
    end
    run=@p.get('calculation',row.payload['run_id'])
    result['basis']=run.payload['segments'].map do |segment|
      policy=@p.get('policy',segment['policy_id']); config=policy.payload['config']
      ids=config['graph'] ? ['charge'] : Array(config['components']).map { |c| "component_#{c['id']}" }
      trace=segment['result']['details'].select { |d| d['explanation'].present? && !d['id'].start_with?('allocation_') }.map { |d| {'label'=>d['explanation'],'basis'=>d['basis'],'exact_amount'=>d['exact_amount'],'amount_minor'=>d['assessed_minor'],'service_start'=>d['interval']['start'],'service_end_exclusive'=>d['interval']['end_exclusive'],'sources'=>d['source_refs'].map { |r| r.slice('id','revision','kind') }} }
      {'policy_version'=>config['version'],'service_start'=>segment['service_start'],'service_end_exclusive'=>segment['service_end_exclusive'],'account_count'=>segment['manifest']['accounts'].size,'components'=>segment['result']['details'].select { |d| ids.include?(d['id']) }.map { |d| {'label'=>d['explanation'].presence || d['id'].delete_prefix('component_').tr('_',' '),'amount_minor'=>d['assessed_minor'],'exact_amount'=>d['exact_amount'],'basis'=>d['basis'],'included_in_bill'=>d['output_class']!='evidence'} },'trace'=>trace}
    end
    result
  end
  def clients(subject)
    accounts=BillingPipeline.new(@p).accounts
    accounts=accounts.where("payload->'record'->>'label' ILIKE ? OR payload->'record'->>'customer_id' ILIKE ?",'%'+ActiveRecord::Base.sanitize_sql_like(@search)+'%','%'+ActiveRecord::Base.sanitize_sql_like(@search)+'%') if @search.present?
    groups=accounts.group(Arel.sql("payload->'record'->>'customer_id'"))
    if subject
      @p.id!(subject)
      records=accounts.where("payload->'record'->>'customer_id' = ?",subject).order(:id)
      {'client'=>{'id'=>subject,'account_count'=>records.count,'accounts'=>records.offset(@offset).limit(@limit).map { |r| r.payload['record'].slice('account_id','label','billing_subject_id','eligible','active_from','active_to') }},'page'=>{'total'=>records.count,'limit'=>@limit,'offset'=>@offset}}
    else
      total=ActiveRecord::Base.connection.select_value("SELECT count(*) FROM (#{groups.select('1').to_sql}) clients").to_i
      items=groups.select("payload->'record'->>'customer_id' AS customer, MIN(payload->'record'->>'label') AS label, count(*) AS accounts, MIN(payload->'record'->>'billing_subject_id') AS billing_subject").order(Arel.sql('customer')).offset(@offset).limit(@limit)
      {'clients'=>items.map { |row| {'id'=>row['customer'],'name'=>row['label'],'account_count'=>row['accounts'].to_i,'billing_subject_id'=>row['billing_subject']} },'page'=>{'total'=>total,'offset'=>@offset,'limit'=>@limit}}
    end
  end
  def terms(subject)
    assignments=@p.rows('assignment')
    subjects=@p.rows('assignment').select(:subject_id).distinct.order(:subject_id).limit(100).pluck(:subject_id)
    subject ||= subjects.first
    schedule=subject ? @p.schedule(subject) : []
    ids=schedule.map { |r| r.payload['policy_id'] }
    policies=@p.rows('policy').where(external_id:ids).order(:id).map do |p|
      config=p.payload['config']; {'id'=>p.external_id,'version'=>config['version'],'effective_from'=>p.starts_on&.iso8601,'effective_to'=>p.ends_on&.iso8601,'components'=>config['components'],'minimum_minor'=>config['minimum_minor'],'cap_minor'=>config['cap_minor'],'allocation'=>config['allocation'],'graph_configured'=>config.key?('graph')}.tap { |out| out['config']=config if @internal }
    end
    {'subjects'=>subjects,'subject_id'=>subject,'schedule_hash'=>@p.hash(schedule.map { |r| [r.external_id,r.payload_hash] }),'assignments'=>schedule.map { |r| {'id'=>r.external_id,'policy_id'=>r.payload['policy_id'],'effective_from'=>r.starts_on.iso8601,'effective_to'=>r.ends_on.iso8601} },'policies'=>policies,'agreement'=>{'available'=>false,'clm_mocked'=>true}}
  end
  def pipeline
    deliveries=@p.rows('delivery').order(id: :desc).offset(@offset).limit(@limit).to_a
    executions=@p.rows('normalization').where(parent_id:deliveries.map(&:id)).select('DISTINCT ON (parent_id) medallion_evidence.*').order(:parent_id,id: :desc).index_by(&:parent_id)
    normalized=BillingPipeline.new(@p).current.order(:id)
    {'stages'=>[{'title'=>'Original deliveries','service'=>'Source adapter','count'=>@p.rows('delivery').count},{'title'=>'Validated records','service'=>'BillingNormalizeJob','count'=>normalized.count},{'title'=>'Policy assignments','service'=>'BillingPlatform','count'=>@p.rows('assignment').count},{'title'=>'Calculated results','service'=>'Economics::Engine','count'=>@p.rows('calculation').count},{'title'=>'Issued documents','service'=>'BillingDocuments','count'=>@p.rows('document').count}],
      'sources'=>@p.rows('source').order(id: :desc).limit(50).map { |r| serialize(r).merge('data'=>r.payload) },
      'records'=>normalized.offset(@offset).limit(@limit).map { |r| serialize(r).merge('data'=>r.payload['record']) },
      'deliveries'=>deliveries.map { |r| e=executions[r.id]; serialize(r).merge('data'=>r.payload,'execution'=>e && serialize(e).merge('data'=>e.payload)) },'page'=>{'limit'=>@limit,'offset'=>@offset,'total'=>[@p.rows('delivery').count,normalized.count].max},'worker'=>{'class'=>'BillingNormalizeJob','adapter'=>'inline','durable'=>false}}
  end
  def queue(audience)
    assigned=@p.rows('assignment').select("payload->>'policy_id'").to_sql
    draft=@p.rows('policy').where("external_id NOT IN (#{assigned})").select(:id).to_sql
    issued=@p.rows('correction_issue').select("payload->>'proposal_id'").to_sql
    latest=@p.rows('correction_proposal').select('DISTINCT ON (parent_id) medallion_evidence.*').order(:parent_id,id: :desc).to_sql
    corrections=MedallionEvidence.from("(#{latest}) medallion_evidence").where("external_id NOT IN (#{issued})").select(:id).to_sql
    reviewed=@p.rows('event_review').where.not(parent_id:nil).select(:parent_id).to_sql
    events=BillingPipeline.new(@p).current(Time.current.iso8601(6),types:['event']).where("id NOT IN (#{reviewed})").select(:id).to_sql
    union="SELECT id FROM (#{draft}) policies UNION ALL SELECT id FROM (#{corrections}) corrections UNION ALL SELECT id FROM (#{events}) events"
    count=ActiveRecord::Base.connection.select_value("SELECT count(*) FROM (#{union}) requests").to_i
    ids=ActiveRecord::Base.connection.select_values("SELECT id FROM (#{union}) requests ORDER BY id DESC LIMIT #{@limit} OFFSET #{@offset}")
    items=MedallionEvidence.where(**@w.scope,case_id:@p.case_id,scenario_id:BillingPlatform::NS,id:ids).order(id: :desc).map do |r|
      out=serialize(r).merge('data'=>r.payload)
      if r.kind=='policy'
        out['published']=@p.published?(r)
        c=@p.rows('comparison').where(parent_id:r.id).order(:id).last
        if c
          stale=begin @p.comparison_current!(c); false; rescue Economics::Error; true end
          reviews=@p.rows('policy_review').where(parent_id:c.id).select("DISTINCT ON (payload->>'role') medallion_evidence.*").order(Arel.sql("payload->>'role', id DESC"))
          out.merge!('comparison'=>serialize(c).merge('data'=>c.payload.except('manifest')),'reviews'=>reviews.map { |v| serialize(v).merge('data'=>v.payload) },'needs_refresh'=>stale)
        end
      elsif r.kind=='correction_proposal'
        review=@p.rows('correction_review').where(parent_id:r.id).order(:id).last
        stale=begin BillingDocuments.new(@p).current!(r); false; rescue Economics::Error; true end
        out.merge!('review'=>review && serialize(review).merge('data'=>review.payload),'needs_refresh'=>stale)
      end
      out
    end
    {'requests'=>items,'page'=>{'total'=>count,'limit'=>@limit,'offset'=>@offset},'review_role'=>audience=='finance' ? 'finance' : nil}
  end
  def detail(id)
    @p.id!(id)
    doc=@p.rows('document').find_by(external_id:id)
    return document(doc) if doc
    @p.error('FORBIDDEN') unless @internal
    relation=MedallionEvidence.where(**@w.scope,case_id:@p.case_id,scenario_id:BillingPlatform::NS)
    row=(id.match?(/\A\d{1,18}\z/) ? relation.find_by(id:Integer(id,10)) : relation.where(external_id:id).order(revision: :desc).first) || @p.error('NOT_FOUND')
    parent=row.parent_id && MedallionEvidence.find_by(**@w.scope,id:row.parent_id,case_id:@p.case_id,scenario_id:BillingPlatform::NS)
    bytes=row.original_bytes&.dup&.force_encoding(Encoding::UTF_8)
    serialize(row).merge('data'=>row.payload,'original_bytes'=>bytes&.valid_encoding? ? bytes : nil,'original_base64'=>bytes && !bytes.valid_encoding? ? Base64.strict_encode64(row.original_bytes) : nil,'parent'=>parent && serialize(parent))
  end
end
