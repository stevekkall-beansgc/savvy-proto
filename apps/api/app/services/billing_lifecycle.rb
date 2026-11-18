# Commercial claim lifecycle. Ledger projections never reprice a policy. Campfire
# schedules and cash confirmations enter independently as retained source records.
class BillingLifecycle
  def initialize(platform) = @p=platform
  def target(id)
    @p.id!(id)
    row=@p.rows('document').find_by(external_id:id) || @p.rows('payable').find_by(external_id:id) || @p.error('NOT_FOUND')
    if row.kind=='document'
      @p.error('VALIDATION_ERROR','Select the original claim') if row.payload['original_document_id']
    else
      @p.error('VALIDATION_ERROR','Select the original payable') if row.payload['original_payable_id']
    end
    row
  end
  def documents(root)
    root.kind=='document' ? @p.rows('document').where("external_id=? OR payload->>'original_document_id'=?",root.external_id,root.external_id) : @p.rows('payable').where("external_id=? OR payload->>'original_payable_id'=?",root.external_id,root.external_id)
  end
  def applications(root)
    reversed=@p.rows('cash_reversal').select(:parent_id)
    @p.rows('cash_application').where("payload->>'target_id'=?",root.external_id).where.not(id:reversed)
  end
  def position(root)
    docs=documents(root).order(:id).to_a
    # The persisted native objects are the financial claims. JSON evidence supplies
    # provenance and hashes, not a competing writable statement amount.
    claims=docs.map do |record|
      if root.kind=='document'
        service=BillingDocuments.new(@p); native=service.native(record)
        @p.error('HASH_CHANGED') unless service.native_hash(native)==record.payload['native_hash']
        [record,native.amount_minor*(native.document_type=='credit_note' ? -1 : 1)]
      else
        native=BillingInstruction.find_by!(**@p.w.scope,id:record.payload['native_instruction_id'])
        @p.error('HASH_CHANGED') unless BillingPayables.new(@p).native_hash(native)==record.payload['native_hash']
        [record,native.amount_minor*(native.debtor_id=='firm-demo' ? 1 : -1)]
      end
    end
    apps=applications(root).order(:id)
    source_states=apps.map do |app|
      source=@p.rows('normalized').find_by(id:app.payload['cash_record_id'])
      current=source && BillingPipeline.new(@p).current(types:['cash']).where(external_id:source.external_id).first
      [app.external_id,current&.payload_hash,current&.id==source&.id]
    end
    # Reporting arithmetic at claim grain; no fee or recognition calculation.
    assessed=claims.sum(&:last); applied=apps.sum(Arel.sql("(payload->>'effect_minor')::bigint")).to_i
    all_apps=@p.rows('cash_application').where("payload->>'target_id'=?",root.external_id).order(:id)
    reversals=@p.rows('cash_reversal').where(parent_id:all_apps.select(:id)).order(:id)
    balance=assessed-applied
    {'target_id'=>root.external_id,'kind'=>root.kind,'subject_id'=>root.payload['subject_id'],'assessed_minor'=>assessed,'applied_minor'=>applied,'balance_minor'=>balance,'outstanding_minor'=>[balance,0].max,'credit_balance_minor'=>[-balance,0].max,'ledger_hash'=>@p.hash({'claims'=>claims.map { |r,amount| [r.external_id,r.payload_hash,amount] },'applications'=>apps.map { |r| [r.external_id,r.payload_hash] },'current_cash_sources'=>source_states,'application_history'=>all_apps.map { |r| [r.external_id,r.payload_hash] },'reversals'=>reversals.map { |r| [r.external_id,r.payload_hash] }}),'documents'=>docs.map(&:external_id),'needs_source_review'=>source_states.any? { |state| !state.last }}
  end
  def source(input,type)
    id=input.fetch('record_id').to_s
    row=id.match?(/\A\d+\z/) ? @p.rows('normalized').find_by(id:id.to_i) : @p.rows('normalized').where(external_id:id).order(revision: :desc).first
    @p.error('NOT_FOUND') unless row
    @p.error('HASH_CHANGED','Review the current exact source revision') unless row.payload_hash==input.fetch('expected_hash') && BillingPipeline.new(@p).current.where(id:row.id).exists?
    @p.error('INVALID_SOURCE') unless row.product_id==type
    row
  end
  def apply(input)
    @p.w.guard!('finance'); root=target(input.fetch('target_id')); state=position(root)
    @p.error('HASH_CHANGED','Claim or applications changed') unless state['ledger_hash']==input.fetch('expected_ledger_hash')
    BillingDocuments.new(@p).open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    row=source(input,'cash'); @p.error('SOURCE_REVIEW_REQUIRED','Reverse associations to superseded cash evidence before applying its replacement') if state['needs_source_review']; value=row.payload['record']; amount=input.fetch('amount_minor'); Economics::Engine.integer!(amount,'application',min:1)
    @p.error('INVALID_SOURCE','Only independently confirmed cash may be applied') unless value['status']=='confirmed' && value['currency']=='USD' && value['billing_subject_id']==root.payload['subject_id'] && (state['documents']+[root.external_id]).include?(value['document_id'])
    forward=root.kind=='document' ? 'inbound' : 'outbound'
    payer=value['direction']=='inbound' ? root.payload['subject_id'] : 'firm-demo'; payee=payer=='firm-demo' ? root.payload['subject_id'] : 'firm-demo'
    @p.error('SCOPE_MISMATCH','Cash counterparties do not match the claim') unless value['payer_id']==payer && value['payee_id']==payee
    reversed=@p.rows('cash_reversal').select(:parent_id)
    used=@p.rows('cash_application').where("payload->>'cash_external_id'=?",row.external_id).where.not(id:reversed).sum(Arel.sql("(payload->>'amount_minor')::bigint")).to_i
    @p.error('INSUFFICIENT_CASH') if used+amount>value['amount_minor']
    direction=value['direction']==forward ? 1 : -1
    @p.error('REFUND_EXCEEDS_CREDIT','Refunds/recoupments cannot exceed the available credit') if direction<0 && amount>state['credit_balance_minor']
    request=input['request_id'] && @p.get('refund_request',input['request_id'])
    if request
      @p.error('REQUEST_CANCELLED') if @p.rows('refund_request').where(parent_id:request.id,status:'rejected').exists?
      @p.error('SCOPE_MISMATCH') unless request.payload['target_id']==root.external_id && direction<0
      fulfilled=applications(root).where("payload->>'request_id'=?",request.external_id).sum(Arel.sql("(payload->>'amount_minor')::bigint")).to_i
      @p.error('INVALID_ALLOCATION') if fulfilled+amount>request.payload['amount_minor']
    end
    effect=direction>0 ? amount : Economics::Engine.new.primitive_binary('subtract',0,amount).to_i
    result=@p.store('cash_application',{'target_id'=>root.external_id,'cash_record_id'=>row.id.to_s,'cash_external_id'=>row.external_id,'cash_hash'=>row.payload_hash,'amount_minor'=>amount,'effect_minor'=>effect,'posting_period'=>input['posting_period'],'reason'=>input['reason'],'request_id'=>request&.external_id},status:'confirmed',parent:row)
    {'application_id'=>result.external_id,'position'=>position(root),'cash_moved'=>false}
  end
  def reverse(input)
    @p.w.guard!('finance'); application=@p.get('cash_application',input.fetch('application_id'))
    prior=@p.rows('cash_reversal').find_by(parent_id:application.id)
    return {'reversal_id'=>prior.external_id,'duplicate'=>true} if prior
    @p.error('HASH_CHANGED') unless application.payload_hash==input.fetch('expected_hash')
    BillingDocuments.new(@p).open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    result=@p.store('cash_reversal',{'application_id'=>application.external_id,'application_hash'=>application.payload_hash,'posting_period'=>input['posting_period'],'reason'=>input['reason']},status:'reversed',parent:application)
    {'reversal_id'=>result.external_id,'position'=>position(target(application.payload['target_id'])),'cash_moved'=>false}
  end
  def request_refund(input)
    @p.w.guard!('finance'); root=target(input.fetch('target_id')); state=position(root)
    @p.error('HASH_CHANGED') unless state['ledger_hash']==input.fetch('expected_ledger_hash')
    BillingDocuments.new(@p).open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    amount=input.fetch('amount_minor'); Economics::Engine.integer!(amount,'refund request',min:1)
    @p.error('SOURCE_REVIEW_REQUIRED') if state['needs_source_review']
    cancelled=@p.rows('refund_request').where(status:'rejected').select(:parent_id)
    reserved=@p.rows('refund_request').where(parent_id:root.id).where.not(id:cancelled).sum(Arel.sql("(payload->>'amount_minor')::bigint")).to_i
    open_ids=@p.rows('refund_request').where(parent_id:root.id).where.not(id:cancelled).select(:external_id)
    fulfilled=applications(root).where("payload->>'request_id' IN (#{open_ids.to_sql})").sum(Arel.sql("(payload->>'amount_minor')::bigint")).to_i
    @p.error('INSUFFICIENT_CREDIT') if amount>state['credit_balance_minor']-[reserved-fulfilled,0].max
    record=@p.store('refund_request',{'target_id'=>root.external_id,'ledger_hash'=>state['ledger_hash'],'amount_minor'=>amount,'posting_period'=>input['posting_period'],'reason'=>input['reason'],'handoff'=>'mock_cash_operations','execution_status'=>'not_sent'},status:'pending',parent:root)
    {'request_id'=>record.external_id,'status'=>'pending','cash_moved'=>false}
  end
  def cancel_refund(input)
    @p.w.guard!('finance'); request=@p.get('refund_request',input.fetch('request_id'))
    @p.error('VALIDATION_ERROR') unless request.status=='pending'
    prior=@p.rows('refund_request').where(parent_id:request.id,status:'rejected').first
    return {'cancellation_id'=>prior.external_id,'duplicate'=>true} if prior
    @p.error('HASH_CHANGED') unless request.payload_hash==input.fetch('expected_hash')
    BillingDocuments.new(@p).open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    result=@p.store('refund_request',{'cancels_request_id'=>request.external_id,'reason'=>input['reason'],'posting_period'=>input['posting_period'],'cash_moved'=>false},status:'rejected',parent:request)
    {'cancellation_id'=>result.external_id,'cash_moved'=>false}
  end
  def package(input)
    @p.w.guard!('finance'); root=target(input.fetch('target_id')); state=position(root)
    @p.error('SOURCE_REVIEW_REQUIRED','Reverse or review associations whose cash evidence changed') if state['needs_source_review']
    @p.error('VALIDATION_ERROR','Recognition packages apply to client/platform claims') unless root.kind=='document'
    @p.error('HASH_CHANGED') unless state['ledger_hash']==input.fetch('expected_ledger_hash')
    BillingDocuments.new(@p).open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    ref=input.fetch('treatment_ref'); @p.error('VALIDATION_ERROR','Use an explicit versioned mock Finance treatment') unless ref.is_a?(Hash) && ref.keys.sort==%w[system id version].sort && ref['system']=='mock_campfire' && %w[id version].all? { |k| ref[k].is_a?(String) && ref[k].match?(/\A[a-zA-Z0-9_-]{1,100}\z/) }
    lines=documents(root).order(:id).flat_map do |doc|
      invoice=BillingDocuments.new(@p).native(doc)
      BillingInvoiceLine.where(**@p.w.scope,billing_invoice_id:invoice.id).order(:id).map do |line|
        obligation=BillingObligation.find_by!(**@p.w.scope,id:line.billing_obligation_id)
        {'document_id'=>invoice.external_id,'line_id'=>line.external_id,'amount_minor'=>line.amount_minor,'direction'=>invoice.document_type=='credit_note' ? 'credit' : 'debit','service_start'=>obligation.service_period_start.iso8601,'service_end_exclusive'=>obligation.service_period_end.iso8601,'policy_refs'=>obligation.client_terms_ref,'calculation_ref'=>invoice.calculation_ref}
      end
    end
    result=@p.store('accounting_package',{'target_id'=>root.external_id,'subject_id'=>root.payload['subject_id'],'currency'=>'USD','ledger_hash'=>state['ledger_hash'],'net_billed_minor'=>state['assessed_minor'],'reported_ar_expected_minor'=>state['balance_minor'],'lines'=>lines,'treatment_ref'=>ref,'posting_period'=>input['posting_period'],'reason'=>input['reason'],'mocked'=>true},status:'pending',parent:root)
    {'package_id'=>result.external_id,'package_hash'=>result.payload_hash,'accounting_posted'=>false}
  end
  def accept_accounting(input)
    @p.w.guard!('finance'); row=source(input,'accounting'); value=row.payload['record']
    package=@p.get('accounting_package',value.fetch('package_id')); root=target(package.payload['target_id'])
    @p.error('HASH_CHANGED') unless value['package_hash']==package.payload_hash && position(root)['ledger_hash']==package.payload['ledger_hash']
    @p.error('SCOPE_MISMATCH') unless value['document_id']==root.external_id && value['billing_subject_id']==root.payload['subject_id'] && value['currency']=='USD' && value['provider']=='mock_campfire'
    BillingDocuments.new(@p).open!(package.payload['posting_period'])
    if value['reported_status']=='posted'
      @p.error('INVALID_ACCOUNTING','Reported AR must reconcile to this exact package') unless value['reported_ar_minor']==package.payload['reported_ar_expected_minor']
      schedule=value.fetch('schedule'); total=@p.engine_sum(schedule.map { |s| s.fetch('amount_minor') },@p.date!(root.payload['service_start']),@p.date!(root.payload['service_end_exclusive']))
      @p.error('INVALID_ACCOUNTING','Supplied schedules must reconcile to the packaged claim') unless total==package.payload['net_billed_minor']
      @p.error('INVALID_ACCOUNTING','Supplied recognized and deferred totals must reconcile') unless value['recognized_minor'] && value['deferred_minor'] && @p.engine_sum([value['recognized_minor'],value['deferred_minor']],@p.date!(root.payload['service_start']),@p.date!(root.payload['service_end_exclusive']))==total
    end
    previous=@p.rows('accounting_acceptance').where("payload->>'target_id'=?",root.external_id).order(:id).last
    if previous && previous.payload['record_id']!=row.id.to_s && previous.payload['reported_status']=='posted'
      @p.error('REVERSAL_REFERENCE_REQUIRED') unless value['replaces_record_id']==previous.payload['record_id'] && value['reversal_journal_id'].present? && value['reverses_hash']==previous.payload['record_hash']
    end
    prior=@p.rows('accounting_acceptance').find_by(parent_id:row.id)
    result=prior || @p.store('accounting_acceptance',{'target_id'=>root.external_id,'package_id'=>package.external_id,'package_hash'=>package.payload_hash,'ledger_hash'=>package.payload['ledger_hash'],'record_id'=>row.id.to_s,'record_hash'=>row.payload_hash,'reported_status'=>value['reported_status'],'recognized_minor'=>value['recognized_minor'],'deferred_minor'=>value['deferred_minor'],'reported_ar_minor'=>value['reported_ar_minor'],'journal_id'=>value['journal_id'],'schedule'=>value['schedule'],'replaces_record_id'=>value['replaces_record_id'],'reversal_journal_id'=>value['reversal_journal_id'],'mocked'=>true},status:'accepted',parent:row)
    {'acceptance_id'=>result.external_id,'mocked'=>true,'live_accounting_posted'=>false}
  end
  def evidence(root,internal:false)
    state=position(root); apps=applications(root).order(:id).map { |r| {'id'=>r.external_id,'hash'=>r.payload_hash,**r.payload.slice('amount_minor','effect_minor','posting_period','reason','cash_record_id')} }
    state['applications']=apps
    state['refund_requests']=@p.rows('refund_request').where(parent_id:root.id).order(:id).map { |r| {'id'=>r.external_id,'hash'=>r.payload_hash,'cancelled'=>@p.rows('refund_request').where(parent_id:r.id,status:'rejected').exists?,**r.payload.slice('amount_minor','execution_status','reason'),'confirmed_minor'=>applications(root).where("payload->>'request_id'=?",r.external_id).sum(Arel.sql("(payload->>'amount_minor')::bigint")).to_i} }
    if internal
      ack=@p.rows('accounting_acceptance').where("payload->>'target_id'=?",root.external_id).order(:id).last
      state['accounting']=ack && ack.payload.merge('id'=>ack.external_id,'current'=>ack.payload['ledger_hash']==state['ledger_hash'])
      state['packages']=@p.rows('accounting_package').where(parent_id:root.id).order(id: :desc).limit(10).map { |r| {'id'=>r.external_id,'hash'=>r.payload_hash,'current'=>r.payload['ledger_hash']==state['ledger_hash'],**r.payload.slice('posting_period','treatment_ref')} }
      cash=BillingPipeline.new(@p).current(types:['cash']).where(subject_id:root.payload['subject_id']).where("payload->'record'->>'document_id' IN (?)",state['documents'])
      state['cash_observations']=cash.order(:id).limit(100).map { |r| {'id'=>r.id.to_s,'hash'=>r.payload_hash,**r.payload['record'].slice('amount_minor','status','direction','date','payer_id','payee_id')} }
      state['accounting_observations']=BillingPipeline.new(@p).current(types:['accounting']).where("payload->'record'->>'document_id'=?",root.external_id).order(id: :desc).limit(20).map { |r| {'id'=>r.id.to_s,'hash'=>r.payload_hash,**r.payload['record'].slice('reported_status','package_id','recognized_minor','deferred_minor','journal_id')} }
    end
    state
  end
end
