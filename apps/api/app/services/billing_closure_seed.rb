# Explicit, transactional synthetic acceptance data. Never run by a page or by
# deployment activation. Existing native records are preserved; all changes append.
class BillingClosureSeed
  def self.call(workbench = Workbench.new)
    raise 'Synthetic setup only' unless ENV['SYNTHETIC_DEMO']=='1'
    new(workbench).call
  end
  def initialize(workbench)
    @workbench = workbench
  end

  def actor(role)
    Workbench.new(role: role, tenant: @workbench.tenant, entity: @workbench.entity)
  end

  def command(action,input,role='operator')
    BillingPlatform.new(actor(role),@case).command(action,input,SecureRandom.uuid)
  end
  def ingest(records)
    result=command('INGEST',{'source_id'=>@source,'delivery_key'=>'closure-'+SecureRandom.uuid,'raw'=>{'records'=>records}.to_json})
    raise result.inspect unless result['status']=='completed'
  end
  def current(id)
    @p.rows('normalized').where("payload->'record'->>'id'=?",id).order(:id).last!
  end
  def credit(root,amount)
    id='closure-credit-'+@case; invoice=BillingDocuments.new(@p).native(root)
    line=BillingInvoiceLine.where(**@p.w.scope,billing_invoice_id:invoice.id).first!
    obligation=BillingObligation.find_by!(**@p.w.scope,id:line.billing_obligation_id)
    row=common(root.payload['subject_id'],obligation.customer_id,obligation.account_id).merge('id'=>id,'type'=>'event','date'=>'2026-09-15','amount_minor'=>amount,'direction'=>'credit','reason'=>'Approved service credit including a discretionary account credit','category'=>'service_credit')
    ingest([row]); source=current(id)
    command('REVIEW_EVENT',{'record_id'=>source.external_id,'expected_hash'=>source.payload_hash,'decision'=>'approved','reason'=>'Review the exact discretionary service credit'},'finance')
  end
  def common(subject,customer,account)
    {'revision'=>1,'observed_at'=>Time.current.iso8601(6),'billing_subject_id'=>subject,'customer_id'=>customer,'account_id'=>account,'currency'=>'USD'}
  end
  def correct(root,reason)
    run=command('EVALUATE',root.payload.slice('subject_id','service_start','service_end_exclusive'))
    raise run.inspect unless run['run_id']
    proposal=command('PROPOSE_CORRECTION',{'document_id'=>root.external_id,'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>reason})
    command('REVIEW_CORRECTION',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Review exact account differences'},'finance')
    command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']})
  end
  def apply(root,source,amount,request_id:nil)
    input={'target_id'=>root.external_id,'record_id'=>source.id.to_s,'expected_hash'=>source.payload_hash,'expected_ledger_hash'=>@ledger.position(root)['ledger_hash'],'amount_minor'=>amount,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Match independently confirmed synthetic cash'}
    input['request_id']=request_id if request_id
    command('APPLY_CASH',input,'finance')
  end
  def reviewed(config,subject,a,b)
    saved=command('SAVE_POLICY',{'policy'=>config,'effective_from'=>a,'effective_to'=>b,'reason'=>'Compose reviewed earnings from issued fees and approved events'})
    comparison=command('COMPARE_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>subject,'service_start'=>a,'service_end_exclusive'=>b})
    %w[legal finance].each { |role| command('REVIEW_POLICY',{'comparison_id'=>comparison['comparison_id'],'decision'=>'approved','reason'=>'Review exact earnings composition','document_ref'=>{'system'=>'mock_clm','document_id'=>@case+'-earnings-terms','version'=>'v1'}},role) }
    command('PUBLISH_POLICY',{'comparison_id'=>comparison['comparison_id']})
    command('ASSIGN_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>subject,'effective_from'=>a,'effective_to'=>b,'reason'=>'Assign reviewed earnings terms','expected_schedule_hash'=>@p.hash([])})
  end
  def call
    %w[advisor ria].each do |case_id|
      DemoScope.transaction do
        @case=case_id; @p=BillingPlatform.new(@workbench,@case); @ledger=BillingLifecycle.new(@p)
        next if @p.rows('work_attempt').where(external_id:'closure-fixture-v1').exists?
        @source=command('REGISTER_SOURCE',{'name'=>'lifecycle-evidence','mapping'=>{'format'=>'json','records_path'=>'records','fields'=>BillingPipeline::FIELDS.to_h { |f| [f,f] }}})['source_id']
        roots=@p.rows('document').where("payload->>'original_document_id' IS NULL").order(:id)
        september=roots.where("payload->>'service_start'='2026-09-01'").first!
        october=roots.where("payload->>'service_start'='2026-10-01'").first!
        credit(september,BillingDocuments.new(@p).native(september).amount_minor+5000)
        correct(september,'Late approved credit; preserve original bill and carry excess credit')
        request=command('REQUEST_REFUND',{'target_id'=>september.external_id,'expected_ledger_hash'=>@ledger.position(september)['ledger_hash'],'amount_minor'=>5000,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Request the independently established customer credit'},'finance')
        invoice=BillingDocuments.new(@p).native(september); line=BillingInvoiceLine.where(**@p.w.scope,billing_invoice_id:invoice.id).first!; obligation=BillingObligation.find_by!(**@p.w.scope,id:line.billing_obligation_id)
        refund_id='closure-refund-'+@case
        ingest([common(september.payload['subject_id'],obligation.customer_id,obligation.account_id).merge('id'=>refund_id,'type'=>'cash','date'=>Time.current.to_date.iso8601,'amount_minor'=>2000,'direction'=>'outbound','payer_id'=>'firm-demo','payee_id'=>september.payload['subject_id'],'status'=>'confirmed','document_id'=>september.external_id)])
        apply(september,current(refund_id),2000,request_id:request['request_id'])
        correct(october,'Late network evidence; update native lines before accounting handoff')
        receipt=BillingPipeline.new(@p).current(types:['cash']).where("payload->'record'->>'document_id'=? AND payload->'record'->>'direction'='inbound'",october.external_id).order(:id).first!
        amount=receipt.payload['record']['amount_minor']/2 # Fixture choice, not a billing formula.
        apply(october,receipt,amount)
        package=command('PACKAGE_ACCOUNTING',{'target_id'=>october.external_id,'expected_ledger_hash'=>@ledger.position(october)['ledger_hash'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Prepare explicit fictional October accounting evidence','treatment_ref'=>{'system'=>'mock_campfire','id'=>'fictional-october-treatment','version'=>'v1'}},'finance')
        state=@ledger.position(october); billed=state['assessed_minor']; accounting_id='closure-accounting-'+@case
        # Authored upstream mock outcome. No recognition treatment is inferred by
        # the application from invoice, product name or cash receipt.
        data=common(october.payload['subject_id'],obligation.customer_id,obligation.account_id).merge('id'=>accounting_id,'type'=>'accounting','date'=>Time.current.to_date.iso8601,'amount_minor'=>billed,'provider'=>'mock_campfire','reported_status'=>'posted','document_id'=>october.external_id,'package_id'=>package['package_id'],'package_hash'=>package['package_hash'],'recognized_minor'=>billed,'deferred_minor'=>0,'reported_ar_minor'=>state['balance_minor'],'journal_id'=>'mock-october-'+@case,'schedule'=>[{'period'=>'2026-10','amount_minor'=>billed}])
        ingest([data]); outcome=current(accounting_id)
        command('ACCEPT_ACCOUNTING',{'record_id'=>outcome.id.to_s,'expected_hash'=>outcome.payload_hash},'finance')
        subject=@case=='advisor' ? 'advisor-demo' : 'ria-harbor'
        account=@case=='advisor' ? 'advisor-payroll-account' : BillingPipeline.new(@p).accounts(subject).first!.payload['record']['account_id']
        records=[]
        if @case=='advisor'
          records << common(subject,subject,account).merge('id'=>'advisor-payroll-membership','type'=>'account','active_from'=>'2026-09-01','eligible'=>true,'usage'=>'earnings','dimensions'=>{},'label'=>'Advisor earnings')
        end
        events=@case=='advisor' ? [['bonus',100_000,'charge'],['expense',20_000,'credit'],['advance',100_000,'credit'],['loan_repayment',10_000,'credit']] : [['incentive',5000,'payout']]
        events.each { |category,value,direction| records << common(subject,subject,account).merge('id'=>@case+'-'+category,'type'=>'event','date'=>'2026-10-15','amount_minor'=>value,'direction'=>direction,'category'=>category,'reason'=>'Approved '+category.tr('_',' ')) }
        ingest(records)
        events.each do |category,_amount,_direction|
          source=current(@case+'-'+category)
          command('REVIEW_EVENT',{'record_id'=>source.external_id,'expected_hash'=>source.payload_hash,'decision'=>'approved','reason'=>'Review exact one-time earnings item'},'finance')
        end
        components=@case=='advisor' ? [{'id'=>'fee_share','kind'=>'earned_share'},{'id'=>'salary','kind'=>'flat','amount_minor'=>500_000,'proration'=>'none'},{'id'=>'bonus','kind'=>'events','direction'=>'charge'},{'id'=>'deductions','kind'=>'events','direction'=>'credit'}] : [{'id'=>'incentive','kind'=>'events','direction'=>'payout'}]
        reviewed({'purpose'=>'earnings','version'=>@case+'-earnings-v1','allocation'=>'equal','components'=>components},subject,'2026-10-01','2026-11-01')
        run=command('EVALUATE',{'purpose'=>'earnings','subject_id'=>subject,'service_start'=>'2026-10-01','service_end_exclusive'=>'2026-11-01'})
        proposal=command('PROPOSE_PAYABLE',{'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Prepare approved earnings payable'})
        command('REVIEW_PAYABLE',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Review native payable and retained engine output'},'finance')
        issued=command('ISSUE_PAYABLE',{'proposal_id'=>proposal['proposal_id']}); payable=@p.get('payable',issued['payable_ids'].first)
        paid=@case=='advisor' ? 100_000 : 2000
        payout_id='closure-payout-'+@case
        ingest([common(subject,subject,account).merge('id'=>payout_id,'type'=>'cash','date'=>Time.current.to_date.iso8601,'amount_minor'=>paid,'direction'=>'outbound','payer_id'=>'firm-demo','payee_id'=>subject,'status'=>'confirmed','document_id'=>payable.external_id)])
        apply(payable,current(payout_id),paid)
        batch=command('QUEUE_BATCH',{'subjects'=>[october.payload['subject_id']],'service_start'=>'2026-10-01','service_end_exclusive'=>'2026-11-01','reason'=>'Durable month-end evaluation proof'})
        item=BillingWorkItem.find_by!(**@workbench.scope, batch_id: batch['batch_id']); completed=BillingWorker.perform_one(job_id:item.job_id); raise completed.inspect unless completed.status=='completed'
        @p.store('work_attempt',{'outcome'=>'fixture_installed','version'=>'v1','source_id'=>@source,'september_root_id'=>september.external_id,'october_root_id'=>october.external_id,'payable_id'=>payable.external_id,'batch_id'=>batch['batch_id']},id:'closure-fixture-v1',status:'completed')
      end
    end
    {'synthetic'=>true,'lifecycle_fixture'=>'v1','both_products'=>true}
  end
end
