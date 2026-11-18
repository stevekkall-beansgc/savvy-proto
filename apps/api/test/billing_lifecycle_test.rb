require_relative 'billing_platform_test'
class BillingLifecycleTest < BillingPlatformTest
  def self.runnable_methods = public_instance_methods(false).grep(/^test_/).map(&:to_s).sort
  def lifecycle = BillingLifecycle.new(@p)
  def root_for(id) = lifecycle.target(id)
  def cash(root,amount,direction:'inbound',id:SecureRandom.uuid,revision:1)
    common=records.first.slice('billing_subject_id','customer_id','account_id')
    row=common.merge('id'=>id,'revision'=>revision,'observed_at'=>Time.current.iso8601(6),'type'=>'cash','date'=>Time.current.to_date.iso8601,'currency'=>'USD','amount_minor'=>amount,'direction'=>direction,'status'=>'confirmed','document_id'=>root.external_id,'billing_subject_id'=>root.payload['subject_id'],'payer_id'=>direction=='inbound' ? root.payload['subject_id'] : 'firm-demo','payee_id'=>direction=='inbound' ? 'firm-demo' : root.payload['subject_id'])
    assert_equal 'completed',ingest([row])['status']
    @p.rows('normalized').where("payload->'record'->>'id'=?",id).order(:id).last!
  end
  def apply(root,row,amount,extra={})
    command('APPLY_CASH',{'target_id'=>root.external_id,'record_id'=>row.id.to_s,'expected_hash'=>row.payload_hash,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'amount_minor'=>amount,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Apply independently confirmed synthetic evidence'}.merge(extra),'finance')
  end
  def approved_credit(amount)
    record=records.first.slice('billing_subject_id','customer_id','account_id').merge('id'=>'credit-source','revision'=>1,'observed_at'=>Time.current.iso8601(6),'type'=>'event','date'=>'2026-09-02','currency'=>'USD','amount_minor'=>amount,'direction'=>'credit','reason'=>'Agreed discretionary service credit')
    ingest([record]); row=@p.rows('normalized').where("payload->'record'->>'id'='credit-source'").order(:id).last!
    command('REVIEW_EVENT',{'record_id'=>row.external_id,'expected_hash'=>row.payload_hash,'decision'=>'approved','reason'=>'Finance approves explicit credit'},'finance')
  end
  def correct(root,run)
    proposed=command('PROPOSE_CORRECTION',{'document_id'=>root.external_id,'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Correct this billing claim'})
    command('REVIEW_CORRECTION',{'proposal_id'=>proposed['proposal_id'],'decision'=>'approved','reason'=>'Review exact correction'},'finance')
    command('ISSUE_CORRECTION',{'proposal_id'=>proposed['proposal_id']})
  end
  def test_excess_credit_partial_refund_reversal_and_native_history
    base=publish(policy); assign(base); original=issue(evaluate); root=root_for(original['document_id']); frozen=BillingDocuments.new(@p).native(root).attributes
    approved_credit(15_000)
    revised=publish(policy.merge('components'=>policy['components']+[{'id'=>'credit','kind'=>'events','direction'=>'credit'}]),base:base); assign(revised)
    run=evaluate; assert_equal 0,run['amount_minor']; assert_equal(-5000,@p.get('calculation',run['run_id']).payload['net_minor'])
    notes=correct(root,run); assert_equal 15_000,BillingInvoice.where(external_id:notes['document_ids']).sum(:amount_minor)
    assert_equal 5000,lifecycle.position(root)['credit_balance_minor']
    request=command('REQUEST_REFUND',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'amount_minor'=>5000,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Request available customer credit'},'finance')
    assert_equal 5000,lifecycle.position(root)['credit_balance_minor']; refute request['cash_moved']
    refund=cash(root,3000,direction:'outbound'); result=apply(root,refund,3000,{'request_id'=>request['request_id']})
    assert_equal 2000,result['position']['credit_balance_minor']
    assert_equal 'INSUFFICIENT_CASH',assert_raises(Economics::Error) { apply(root,refund,1) }.code
    application=@p.get('cash_application',result['application_id'])
    reverse=command('REVERSE_CASH',{'application_id'=>application.external_id,'expected_hash'=>application.payload_hash,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Reverse operational association only'},'finance')
    assert_equal 5000,reverse['position']['credit_balance_minor']; assert_equal frozen,BillingDocuments.new(@p).native(root).attributes
    assert_equal 0,@p.rows('accounting_acceptance').count
  end
  def test_standalone_credit_can_later_be_corrected_to_a_debit
    approved_credit(5000); config=policy(0).merge('components'=>[{'id'=>'credit','kind'=>'events','direction'=>'credit'}]); assign(publish(config))
    original=issue(evaluate); root=root_for(original['document_id']); assert_equal 'credit_note',BillingDocuments.new(@p).native(root).document_type
    assign(publish(policy(2000))); notes=correct(root,evaluate)
    assert_equal 7000,BillingInvoice.where(external_id:notes['document_ids']).sum(:amount_minor)
    assert_equal 2000,lifecycle.position(root)['outstanding_minor']
  end
  def test_cash_scope_stale_evidence_and_concurrent_allocation
    assign(publish(policy)); root=root_for(issue(evaluate)['document_id']); receipt=cash(root,6000)
    result=apply(root,receipt,4000); assert_equal 6000,result['position']['outstanding_minor']
    snapshot=lifecycle.position(root)
    results=2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            BillingPlatform.new(Workbench.new(role:'finance'),@case).command('APPLY_CASH',{'target_id'=>root.external_id,'record_id'=>receipt.id.to_s,'expected_hash'=>receipt.payload_hash,'expected_ledger_hash'=>snapshot['ledger_hash'],'amount_minor'=>2000,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Concurrent scoped application'},"cash-race-#{index}")
          rescue Economics::Error => e; e.code end
        end
      end
    end.map(&:value)
    assert_equal 1,results.count { |v| v.is_a?(Hash) }; assert_includes results,'HASH_CHANGED'
    assert_equal 4000,lifecycle.position(root)['outstanding_minor']
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { command('APPLY_CASH',{}) }.code
    cash(root,7000,id:receipt.payload.dig('record','id'),revision:2)
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { apply(root,receipt,1) }.code
    assert lifecycle.position(root)['needs_source_review']
  end
  def test_accounting_package_independent_schedule_and_correction_reversal_link
    assign(publish(policy)); root=root_for(issue(evaluate)['document_id']); apply(root,cash(root,4000),4000)
    package=command('PACKAGE_ACCOUNTING',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Prepare mock accounting handoff','treatment_ref'=>{'system'=>'mock_campfire','id'=>'finance-treatment','version'=>'v1'}},'finance')
    assert_nil lifecycle.evidence(root,internal:true)['accounting']
    common=records.first.slice('billing_subject_id','customer_id','account_id')
    value=common.merge('id'=>'mock-journal','revision'=>1,'type'=>'accounting','observed_at'=>Time.current.iso8601(6),'date'=>Time.current.to_date.iso8601,'currency'=>'USD','amount_minor'=>10000,'provider'=>'mock_campfire','reported_status'=>'posted','document_id'=>root.external_id,'package_id'=>package['package_id'],'package_hash'=>package['package_hash'],'recognized_minor'=>4000,'deferred_minor'=>6000,'reported_ar_minor'=>6000,'journal_id'=>'mock-posting-1','schedule'=>[{'period'=>'2026-09','amount_minor'=>4000},{'period'=>'2026-10','amount_minor'=>6000}])
    ingest([value]); row=@p.rows('normalized').where("payload->'record'->>'id'='mock-journal'").last!
    command('ACCEPT_ACCOUNTING',{'record_id'=>row.id.to_s,'expected_hash'=>row.payload_hash},'finance')
    assert_equal 4000,lifecycle.evidence(root,internal:true).dig('accounting','recognized_minor')
    apply(root,cash(root,1000),1000); assert_equal false,lifecycle.evidence(root,internal:true).dig('accounting','current')
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { command('ACCEPT_ACCOUNTING',{'record_id'=>row.id.to_s,'expected_hash'=>row.payload_hash},'finance') }.code
    next_package=command('PACKAGE_ACCOUNTING',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Refresh the accounting package','treatment_ref'=>{'system'=>'mock_campfire','id'=>'finance-treatment','version'=>'v2'}},'finance')
    replacement=value.merge('id'=>'replacement-journal','package_id'=>next_package['package_id'],'package_hash'=>next_package['package_hash'],'reported_ar_minor'=>5000,'recognized_minor'=>10000,'deferred_minor'=>0,'journal_id'=>'mock-posting-2','schedule'=>[{'period'=>'2026-09','amount_minor'=>10000}])
    ingest([replacement]); incoming=@p.rows('normalized').where("payload->'record'->>'id'='replacement-journal'").order(:id).last!
    assert_equal 'REVERSAL_REFERENCE_REQUIRED',assert_raises(Economics::Error) { command('ACCEPT_ACCOUNTING',{'record_id'=>incoming.id.to_s,'expected_hash'=>incoming.payload_hash},'finance') }.code
    ingest([replacement.merge('revision'=>2,'replaces_record_id'=>row.id.to_s,'reverses_hash'=>row.payload_hash,'reversal_journal_id'=>'mock-reversal-1')])
    incoming=@p.rows('normalized').where("payload->'record'->>'id'='replacement-journal'").order(:id).last!
    command('ACCEPT_ACCOUNTING',{'record_id'=>incoming.id.to_s,'expected_hash'=>incoming.payload_hash},'finance')
    evidence=lifecycle.evidence(root,internal:true)['accounting']; assert_equal true,evidence['current']; assert_equal 'mock-reversal-1',evidence['reversal_journal_id']
    assert_equal 2,@p.rows('accounting_acceptance').count
    ingest([replacement.merge('revision'=>3)])
    assert_equal false,lifecycle.evidence(root,internal:true).dig('accounting','current')

  end
  def test_database_queue_scheduling_quarantine_replay_and_retry_after_crash
    before=@p.rows('normalized').count; due=Time.current+30
    result=command('INGEST',{'source_id'=>@source,'delivery_key'=>'durable-delivery','raw'=>{'rows'=>records}.to_json,'defer'=>true,'run_at'=>due.iso8601(6)})
    assert_equal 'queued',result['status']; assert_equal before,@p.rows('normalized').count
    assert_nil BillingWorker.perform_one
    attempted=BillingWorker.perform_one(now:due+1,after_execute:->(*) { raise 'crash after normalization commit' })
    assert_equal 'queued',attempted.status; assert_equal before,@p.rows('normalized').count
    completed=BillingWorker.perform_one(now:due+10); assert_equal 'completed',completed.status; assert_equal 2,completed.attempts
    execution=@p.rows('normalization').where("payload->>'delivery_id'='durable-delivery'").order(:id).last!
    assert_equal 'postgresql',execution.payload['adapter']
    command('INGEST',{'source_id'=>@source,'delivery_key'=>'bad-durable','raw'=>'bad bytes','defer'=>true})
    rejected=BillingWorker.perform_one; assert_equal 'quarantined',rejected.status
    assert_equal 1,rejected.attempts
    retry_job=command('RETRY_WORK',{'job_id'=>rejected.job_id,'reason'=>'Operator retries retained delivery'})
    assert_equal 'queued',retry_job['status']; assert_equal 'quarantined',BillingWorker.perform_one.status
  end
  def test_batch_restart_and_concurrent_workers_do_not_duplicate_gold_execution
    assign(publish(policy)); batch=command('QUEUE_BATCH',{'subjects'=>['group-one'],'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03','reason'=>'Queue scheduled monthly calculation'})
    first=BillingWorker.perform_one(after_execute:->(*) { raise 'process interrupted after domain commit' }); assert_equal 'queued',first.status
    work=BillingWorkItem.find_by!(batch_id:batch['batch_id']); work.update!(run_at:Time.current-1)
    results=2.times.map { Thread.new { ActiveRecord::Base.connection_pool.with_connection { BillingWorker.perform_one } } }.map(&:value)
    assert_equal 1,results.compact.size; assert_equal 'completed',results.compact.first.status
    assert_equal 1,@p.rows('calculation').count
    assert_equal 10000,@p.rows('calculation').first.payload['total_minor']
  end
  def test_earnings_share_salary_bonus_deduction_native_payable_and_partial_payment
    config=policy.merge('compensation'=>{'share'=>'4/5'}); assign(publish(config)); issue(evaluate)
    common={'observed_at'=>Time.current.iso8601(6),'billing_subject_id'=>'advisor-demo','customer_id'=>'advisor-demo','account_id'=>'payroll-account'}
    ingest([common.merge('id'=>'payroll-account','revision'=>1,'type'=>'account','active_from'=>'2026-09-01','eligible'=>true,'dimensions'=>{},'label'=>'Advisor earnings')])
    earnings={'purpose'=>'earnings','version'=>'earnings-v1','allocation'=>'equal','components'=>[{'id'=>'share','kind'=>'earned_share'},{'id'=>'salary','kind'=>'flat','amount_minor'=>5000,'proration'=>'none'}]}
    saved=command('SAVE_POLICY',{'policy'=>earnings,'effective_from'=>'2026-09-01','effective_to'=>'2026-10-01','reason'=>'Salary plus issued fee share'})
    comparison=command('COMPARE_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>'advisor-demo','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'})
    %w[legal finance].each { |role| command('REVIEW_POLICY',{'comparison_id'=>comparison['comparison_id'],'decision'=>'approved','reason'=>'Review composed earnings','document_ref'=>{'system'=>'mock_clm','document_id'=>'earnings-terms','version'=>'v1'}},role) }
    command('PUBLISH_POLICY',{'comparison_id'=>comparison['comparison_id']})
    command('ASSIGN_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>'advisor-demo','effective_from'=>'2026-09-01','effective_to'=>'2026-09-03','reason'=>'Assign reviewed earnings','expected_schedule_hash'=>@p.hash([])})
    run=command('EVALUATE',{'purpose'=>'earnings','subject_id'=>'advisor-demo','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'}); assert_equal 13000,run['amount_minor']
    proposal=command('PROPOSE_PAYABLE',{'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Prepare advisor payable'})
    command('REVIEW_PAYABLE',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Finance reviews exact earnings'},'finance')
    issued=command('ISSUE_PAYABLE',{'proposal_id'=>proposal['proposal_id']}); root=root_for(issued['payable_ids'].first)
    assert_equal 13000,lifecycle.position(root)['outstanding_minor']
    paid=apply(root,cash(root,5000,direction:'outbound'),5000); assert_equal 8000,paid['position']['outstanding_minor']
    instruction=BillingInstruction.find(root.payload['native_instruction_id']); assert_equal 'not_sent',instruction.execution_status
    assert_raises(ActiveRecord::StatementInvalid) { BillingInstruction.where(id:instruction.id).update_all(amount_minor:1) }
    client_root=@p.rows('document').where("payload->>'original_document_id' IS NULL").first!
    revised=publish(policy(5000).merge('compensation'=>{'share'=>'4/5'})); assign(revised); correct(client_root,evaluate)
    next_run=command('EVALUATE',{'purpose'=>'earnings','subject_id'=>'advisor-demo','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'})
    assert_equal 9000,next_run['amount_minor']
    next_proposal=command('PROPOSE_PAYABLE',{'run_id'=>next_run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Adjust earnings after corrected client fees'})
    command('REVIEW_PAYABLE',{'proposal_id'=>next_proposal['proposal_id'],'decision'=>'approved','reason'=>'Review earnings correction'},'finance')
    command('ISSUE_PAYABLE',{'proposal_id'=>next_proposal['proposal_id']})
    assert_equal 4000,lifecycle.position(root)['outstanding_minor']
    assert_equal 13000,instruction.reload.amount_minor

  end
  def reviewed(config,subject,a,b)
    saved=command('SAVE_POLICY',{'policy'=>config,'effective_from'=>a,'effective_to'=>b,'reason'=>'Review dated commercial lifecycle'})
    comparison=command('COMPARE_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>subject,'service_start'=>a,'service_end_exclusive'=>b})
    %w[legal finance].each { |role| command('REVIEW_POLICY',{'comparison_id'=>comparison['comparison_id'],'decision'=>'approved','reason'=>'Review exact lifecycle proof','document_ref'=>{'system'=>'mock_clm','document_id'=>'lifecycle-terms','version'=>'v1'}},role) }
    command('PUBLISH_POLICY',{'comparison_id'=>comparison['comparison_id']})
    purpose=config.fetch('purpose','billing'); schedule=@p.schedule(subject,purpose:purpose)
    command('ASSIGN_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>subject,'effective_from'=>a,'effective_to'=>b,'reason'=>'Assign lifecycle policy','expected_schedule_hash'=>@p.hash(schedule.map { |r| [r.external_id,r.payload_hash] })})
    saved['policy_id']
  end
  def test_advance_valuation_termination_refund_and_arrears_gate
    a=Time.current.to_date; b=a+30
    balances=records.select { |r| r['type']=='balance' && r['date']=='2026-09-01' }.map { |r| r.merge('id'=>"opening-#{r['account_id']}",'date'=>(a-1).iso8601,'observed_at'=>Time.current.iso8601(6)) }
    ingest(balances)
    config={'version'=>'advance-v1','invoice_timing'=>'advance','allocation'=>'balance','components'=>[{'id'=>'asset','kind'=>'aum','basis'=>'ending_value','valuation'=>'prior_period_end','rate'=>'1/100','period_factor'=>'1/12'}]}
    reviewed(config,'group-one',a.iso8601,b.iso8601)
    run=command('EVALUATE',{'subject_id'=>'group-one','service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601}); assert_equal 166667,run['amount_minor']
    root=root_for(issue(run)['document_id']); apply(root,cash(root,166667),166667)
    ingest(records.select { |r| r['type']=='account' }.map { |r| r.merge('revision'=>2,'active_to'=>(a+15).iso8601,'observed_at'=>Time.current.iso8601(6)) })
    revised=command('EVALUATE',{'subject_id'=>'group-one','service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601}); assert_equal 83333,revised['amount_minor']
    correct(root,revised); assert_equal 83333,lifecycle.position(root)['assessed_minor']
    assert_equal 83334,lifecycle.position(root)['credit_balance_minor']
    request=command('REQUEST_REFUND',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'amount_minor'=>83334,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Return the unearned portion of a prepaid fee'},'finance')
    apply(root,cash(root,83334,direction:'outbound'),83334,{'request_id'=>request['request_id']})
    assert_equal 0,lifecycle.position(root)['balance_minor']
    reviewed(config.merge('version'=>'arrears-v1','invoice_timing'=>'arrears'),'group-one',a.iso8601,b.iso8601)
    next_run=command('EVALUATE',{'subject_id'=>'group-one','service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601})
    assert_equal 'SERVICE_NOT_FINISHED',assert_raises(Economics::Error) { issue(next_run) }.code
  end
  def test_ria_billing_and_earnings_schedules_are_independent
    @case='ria'; @p=BillingPlatform.new(@w,@case); @source=command('REGISTER_SOURCE',{'name'=>'custodian','mapping'=>@mapping})['source_id']; ingest(records)
    reviewed(policy.merge('allocation'=>'equal'),'group-one','2026-09-01','2026-09-03'); invoice=root_for(issue(evaluate)['document_id']); apply(invoice,cash(invoice,5000),5000)
    assert_equal 5000,lifecycle.position(invoice)['outstanding_minor']
    reviewed({'purpose'=>'earnings','version'=>'ria-incentive','allocation'=>'equal','components'=>[{'id'=>'incentive','kind'=>'flat','amount_minor'=>2500,'proration'=>'none'}]},'group-one','2026-09-01','2026-09-03')
    assert_equal 10000,evaluate['amount_minor']
    earnings=command('EVALUATE',{'purpose'=>'earnings','subject_id'=>'group-one','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'})
    assert_equal 2500,earnings['amount_minor']; assert_equal 1,@p.schedule('group-one',purpose:'earnings').size
  end
  def test_representative_book_batch_is_paged_and_recoverable
    config=policy(100).merge('allocation'=>'equal'); policy_id=publish(config)
    members=200.times.map do |index|
      {'id'=>"book-account-#{index}",'revision'=>1,'type'=>'account','observed_at'=>Time.current.iso8601(6),'billing_subject_id'=>"book-group-#{index}",'customer_id'=>"book-client-#{index}",'account_id'=>"book-account-#{index}",'active_from'=>'2026-09-01','eligible'=>true,'label'=>"Synthetic client #{index}",'dimensions'=>{}}
    end
    ingest(members)
    members.each do |member|
      command('ASSIGN_POLICY',{'policy_id'=>policy_id,'subject_id'=>member['billing_subject_id'],'effective_from'=>'2026-09-01','effective_to'=>'2026-09-03','reason'=>'Assign representative book terms','expected_schedule_hash'=>@p.hash([])})
    end
    batch=command('QUEUE_BATCH',{'subjects'=>members.map { |r| r['billing_subject_id'] },'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03','reason'=>'Representative paged book evaluation'})
    assert_equal 200,batch['groups']
    200.times { assert_equal 'completed',BillingWorker.perform_one.status }
    assert_equal 200,@p.rows('calculation').count
    read=BillingWorkspace.new(Workbench.new(role:'advisor'),'advisor').view(audience:'client',section:'clients',limit:20,offset:180)
    assert_equal 201,read['page']['total']; assert_equal 20,read['clients'].size
    assert_equal 200,BillingWorkItem.where(batch_id:batch['batch_id'],status:'completed').count
  end

  def test_expired_worker_lease_is_recovered_and_client_reads_do_not_price_or_write
    assign(publish(policy)); run=evaluate; issue(run)
    job=BillingEvaluateJob.new(@w.tenant,@w.entity,@case,'group-one','2026-09-01','2026-09-03')
    queued=BillingWorker.enqueue(job)
    queued.update!(status:'running',attempts:1,lease_token:'abandoned-worker',leased_until:Time.current-1)
    assert_equal 'completed',BillingWorker.perform_one.status
    assert_equal 2,queued.reload.attempts
    before=[MedallionEvidence.count,BillingInvoice.count,DemoOperation.count]
    original=Economics::Engine.instance_method(:evaluate)
    Economics::Engine.define_method(:evaluate) { |*args,**kw| raise 'Read-side pricing' }
    client=BillingWorkspace.new(Workbench.new(role:'advisor'),'advisor')
    assert client.view(audience:'client',section:'statements')['documents'].first['position']
    assert_equal [],client.view(audience:'client',section:'earnings')['payables']
    assert_equal before,[MedallionEvidence.count,BillingInvoice.count,DemoOperation.count]
  ensure
    Economics::Engine.define_method(:evaluate,original) if original
  end

  def test_cancel_unpaid_refund_remainder_and_closed_period_are_independent_of_cash
    assign(publish(policy)); root=root_for(issue(evaluate)['document_id']); apply(root,cash(root,12000),12000)
    assert_equal 2000,lifecycle.position(root)['credit_balance_minor']
    request=command('REQUEST_REFUND',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'amount_minor'=>2000,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Refund overpayment'},'finance')
    apply(root,cash(root,500,direction:'outbound'),500,{'request_id'=>request['request_id']})
    prior=@p.get('refund_request',request['request_id'])
    command('CANCEL_REFUND',{'request_id'=>prior.external_id,'expected_hash'=>prior.payload_hash,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Cancel unapplied remainder'},'finance')
    assert_equal 1500,lifecycle.position(root)['credit_balance_minor']
    command('REQUEST_REFUND',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'amount_minor'=>1500,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Replace cancelled remainder'},'finance')
    command('CLOSE_PERIOD',{'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Close posting month'},'finance')
    assert_equal 'PERIOD_CLOSED',assert_raises(Economics::Error) { command('REQUEST_REFUND',{'target_id'=>root.external_id,'expected_ledger_hash'=>lifecycle.position(root)['ledger_hash'],'amount_minor'=>1,'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Attempt closed period'},'finance') }.code
  end

  def test_average_daily_and_daily_accrual_are_distinct_api_policy_choices
    config={'version'=>'average-daily','allocation'=>'balance','components'=>[{'id'=>'asset','kind'=>'aum','basis'=>'average_daily','rate'=>'1/100','period_factor'=>'1/12'}]}
    assign(publish(config)); assert_equal 166667,evaluate['amount_minor']
    revised={'version'=>'daily-accrual','allocation'=>'balance','components'=>[{'id'=>'asset','kind'=>'aum','basis'=>'daily','rate'=>'1/100','day_basis'=>365}]}
    assign(publish(revised)); assert_equal 10959,evaluate['amount_minor']
    assert_equal 'INVALID_POLICY',assert_raises(Economics::Error) { command('SAVE_POLICY',{'policy'=>config.merge('components'=>[config['components'].first.merge('day_basis'=>365)]),'effective_from'=>'2026-09-01','effective_to'=>nil,'reason'=>'Reject an ignored day basis'}) }.code
  end

end
