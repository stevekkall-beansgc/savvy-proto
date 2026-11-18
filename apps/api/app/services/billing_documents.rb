# Native issue and append-only correction workflow. Statements are read projections.
class BillingDocuments
  def initialize(platform) = @p=platform
  def period!(value)
    @p.error('INVALID_INTERVAL','Expected a posting month') unless value.is_a?(String) && value.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
    @p.date!(value+'-01'); value
  end
  def open!(period)
    period!(period); @p.error('PERIOD_CLOSED','Choose an open posting period; original service history stays closed') if @p.rows('period_close').where(external_id:"closed-#{period}").exists?
  end
  def native(record)
    BillingInvoice.find_by!(**@p.w.scope,id:record.payload.fetch('native_invoice_id'),billing_case_id:@p.case_id)
  end
  def native_hash(invoice)
    @p.hash({'invoice'=>invoice.attributes,'lines'=>BillingInvoiceLine.where(**@p.w.scope,billing_invoice_id:invoice.id).order(:id).map(&:attributes)})
  end
  def root!(id)
    record=@p.get('document',id); invoice=native(record)
    @p.error('VALIDATION_ERROR','Select the original invoice') unless invoice.corrects_invoice_id.nil?
    @p.error('HASH_CHANGED') unless record.payload['native_hash']==native_hash(invoice)
    [record,invoice]
  end
  def target(root)
    issued=@p.rows('correction_issue').where(parent_id:root.id).order(:id).last
    @p.get('calculation',issued ? issued.payload.fetch('target_run_id') : root.payload.fetch('run_id'))
  end
  def issue(input)
    @p.w.guard!('operator'); run=@p.fresh_run!(@p.get('calculation',input.fetch('run_id'))); body=run.payload
    @p.error('INVALID_POLICY','Use the earnings payable workflow') if body['purpose']=='earnings'
    body['segments'].each do |segment|
      policy=@p.get('policy',segment['policy_id'])
      @p.error('SERVICE_NOT_FINISHED','Arrears billing requires completed service dates') if policy.payload['config'].fetch('invoice_timing','arrears')=='arrears' && @p.date!(body['service_end_exclusive'])>Time.current.to_date
    end
    open!(input.fetch('posting_period')); due=@p.date!(input.fetch('due_on')); @p.error('INVALID_INTERVAL') if due<Time.current.to_date
    prior=@p.rows('document').where("payload->>'subject_id' = ? AND payload->>'service_start' = ? AND payload->>'service_end_exclusive' = ? AND payload->>'original_document_id' IS NULL",body['subject_id'],body['service_start'],body['service_end_exclusive']).first
    if prior
      @p.error('CORRECTION_REQUIRED','This period is already billed; propose a correction') unless prior.payload['run_id']==run.external_id
      return {'document_id'=>prior.external_id,'status'=>'issued','duplicate'=>true}
    end
    overlap=@p.rows('document').where("payload->>'subject_id' = ? AND payload->>'original_document_id' IS NULL AND payload->>'service_start' < ? AND payload->>'service_end_exclusive' > ?",body['subject_id'],body['service_end_exclusive'],body['service_start']).exists?
    @p.error('CORRECTION_REQUIRED','Overlapping service dates are already billed; correct the issued interval') if overlap
    allocations=body.fetch('settlement_allocations',body.fetch('allocations'))
    positives=allocations.select { |_,amount| amount>0 }; negatives=allocations.select { |_,amount| amount<0 }.transform_values { |amount| -amount }
    @p.error('NO_CHARGE','No net billing claim is due') if positives.empty? && negatives.empty?
    document=persist(run,positives.empty? ? negatives : positives,positives.empty? ? 'credit_note' : 'invoice',input['posting_period'],due:positives.empty? ? nil : due)
    persist(run,negatives,'credit_note',input['posting_period'],root:document) if positives.any? && negatives.any?
    {'document_id'=>document.external_id,'amount_minor'=>native(document).amount_minor,'status'=>'issued'}
  end
  def persist(run,allocations,type,posting,root:nil,due:nil)
    allocations=allocations.select { |_,amount| amount>0 }; @p.error('NO_CHARGE') if allocations.empty?
    body=run.payload; a,b=@p.interval!(body['service_start'],body['service_end_exclusive'])
    amount=@p.engine_sum(allocations.values,a,b); external=@p.uid('doc')
    original=root && native(root); debtor=type=='credit_note' ? 'firm-demo' : body['subject_id']; creditor=type=='credit_note' ? body['subject_id'] : 'firm-demo'
    invoice=BillingInvoice.create!(**@p.w.scope,external_id:external,revision:1,debtor_id:debtor,creditor_id:creditor,currency:'USD',amount_minor:amount,status:'issued',document_type:type,corrects_invoice_id:original&.id,billing_case_id:@p.case_id,billing_subject_id:body['subject_id'],issued_on:Time.current.to_date,due_on:due,posting_period:posting,calculation_ref:run.external_id)
    lines=allocations.sort.map do |account,value|
      source=body.fetch('segments').flat_map { |s| s['manifest']['accounts'] }.find { |r| r['account_id']==account }
      # Closed account corrections still use the original account identity.
      parent_documents=original && BillingInvoice.where(**@p.w.scope,).where('id = ? OR corrects_invoice_id = ?',original.id,original.id).select(:id)
      old_line=original && BillingInvoiceLine.joins('JOIN billing_obligations o ON o.id=billing_invoice_lines.billing_obligation_id AND o.tenant_id=billing_invoice_lines.tenant_id AND o.entity_id=billing_invoice_lines.entity_id').where(**@p.w.scope,billing_invoice_id:parent_documents).where('o.account_id = ?',account).order(:id).first
      old_obligation=old_line && BillingObligation.find_by!(**@p.w.scope,id:old_line.billing_obligation_id)
      @p.error('INCOMPLETE_SOURCE','Account identity is absent from current and original billing') unless source || old_obligation
      obligation=BillingObligation.create!(**@p.w.scope,external_id:@p.uid('obligation'),revision:1,customer_id:source ? source['customer_id'] : old_obligation.customer_id,service_id:'platform-billing',broker_id:@p.case_id=='advisor' ? 'advisor-demo' : 'ria-harbor',account_id:account,assignment_id:body['segments'].map { |s| s['assignment_id'] }.join(','),client_terms_ref:body['segments'].map { |s| s['policy_id'] }.join(','),source_id:run.external_id,source_revision:run.revision,route:'invoice',currency:'USD',amount_minor:value,service_period_start:a,service_period_end:b)
      BillingInvoiceLine.create!(**@p.w.scope,external_id:@p.uid('line'),billing_invoice_id:invoice.id,billing_obligation_id:obligation.id,amount_minor:value,corrects_line_id:old_line&.id)
    end
    @p.store('document',{'native_invoice_id'=>invoice.id,'native_hash'=>native_hash(invoice),'document_type'=>type,'run_id'=>run.external_id,'run_hash'=>run.payload_hash,'subject_id'=>body['subject_id'],'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'original_document_id'=>root&.external_id,'line_ids'=>lines.map(&:id)},id:external,status:'issued',parent:run)
  end
  def propose(input)
    @p.w.guard!('operator'); root,invoice=root!(input.fetch('document_id')); run=@p.fresh_run!(@p.get('calculation',input.fetch('run_id'))); previous=target(root)
    %w[subject_id service_start service_end_exclusive].each { |key| @p.error('SCOPE_MISMATCH') unless run.payload[key]==root.payload[key] }
    open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    old=previous.payload.fetch('settlement_allocations',previous.payload.fetch('allocations')); new=run.payload.fetch('settlement_allocations',run.payload.fetch('allocations'))
    changes=(old.keys+new.keys).uniq.sort.to_h do |account|
      value=Economics::Engine.new.primitive_binary('subtract',new.fetch(account,0),old.fetch(account,0)).to_i
      [account,value]
    end
    proposal=@p.store('correction_proposal',{'root_document_id'=>root.external_id,'native_hash'=>native_hash(invoice),'previous_run_id'=>previous.external_id,'previous_run_hash'=>previous.payload_hash,'target_run_id'=>run.external_id,'target_run_hash'=>run.payload_hash,'implementation_hash'=>@p.implementation_hash,'posting_period'=>input['posting_period'],'reason'=>input['reason'],'changes'=>changes,'before_minor'=>previous.payload.fetch('net_minor',previous.payload['total_minor']),'after_minor'=>run.payload.fetch('net_minor',run.payload['total_minor'])},status:'proposed',parent:root)
    {'proposal_id'=>proposal.external_id,'changes'=>changes,'before_minor'=>previous.payload.fetch('net_minor',previous.payload['total_minor']),'after_minor'=>run.payload.fetch('net_minor',run.payload['total_minor'])}
  end
  def current!(proposal)
    body=proposal.payload; root,invoice=root!(body['root_document_id']); previous=target(root)
    @p.error('HASH_CHANGED','Another correction changed the issued baseline') unless previous.external_id==body['previous_run_id'] && previous.payload_hash==body['previous_run_hash'] && native_hash(invoice)==body['native_hash']
    @p.error('HASH_CHANGED') unless @p.implementation_hash==body['implementation_hash']
    run=@p.fresh_run!(@p.get('calculation',body['target_run_id'])); @p.error('HASH_CHANGED') unless run.payload_hash==body['target_run_hash']
    open!(body['posting_period']); [root,run]
  end
  def review(input)
    @p.w.guard!('finance'); proposal=@p.get('correction_proposal',input.fetch('proposal_id')); current!(proposal)
    @p.error('VALIDATION_ERROR') unless %w[approved rejected].include?(input['decision']); @p.m.reason!(input['reason'])
    row=@p.store('correction_review',{'proposal_id'=>proposal.external_id,'proposal_hash'=>proposal.payload_hash,'decision'=>input['decision'],'reason'=>input['reason']},status:input['decision'],parent:proposal)
    {'review_id'=>row.external_id,'decision'=>row.status}
  end
  def correct(input)
    @p.w.guard!('operator'); proposal=@p.get('correction_proposal',input.fetch('proposal_id'))
    prior=@p.rows('correction_issue').where("payload->>'proposal_id' = ?",proposal.external_id).first
    return {'document_ids'=>prior.payload['document_ids'],'status'=>prior.status,'duplicate'=>true} if prior
    root,run=current!(proposal)
    review=@p.rows('correction_review').where(parent_id:proposal.id).order(:id).last
    @p.error('REVIEW_REQUIRED') unless review && review.status=='approved' && review.payload['proposal_hash']==proposal.payload_hash
    changes=proposal.payload.fetch('changes'); documents=[]
    {'credit_note'=>changes.select { |_,v| v<0 }.transform_values { |v| -v },'debit_note'=>changes.select { |_,v| v>0 }}.each do |type,allocations|
      next if allocations.empty?
      documents << persist(run,allocations,type,proposal.payload['posting_period'],root:root)
    end
    status=documents.empty? ? 'unchanged' : 'issued'
    @p.store('correction_issue',{'proposal_id'=>proposal.external_id,'proposal_hash'=>proposal.payload_hash,'target_run_id'=>run.external_id,'target_run_hash'=>run.payload_hash,'document_ids'=>documents.map(&:external_id),'review_id'=>review.external_id},status:status,parent:root)
    {'document_ids'=>documents.map(&:external_id),'status'=>status,'cash_moved'=>false,'accounting_posted'=>false}
  end
end
