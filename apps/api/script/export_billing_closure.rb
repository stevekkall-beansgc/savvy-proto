# Read-only export of executed synthetic lifecycle proof for the architecture.
raise 'Synthetic export only' unless ENV['SYNTHETIC_DEMO']=='1'
cases=%w[advisor ria].map do |case_id|
  p=BillingPlatform.new(Workbench.new(role:'auditor'),case_id)
  marker=p.get('work_attempt','closure-fixture-v1').payload
  service=BillingLifecycle.new(p)
  september=p.get('document',marker['september_root_id']); october=p.get('document',marker['october_root_id']); payable=p.get('payable',marker['payable_id'])
  a=service.evidence(september,internal:true); b=service.evidence(october,internal:true); e=service.evidence(payable,internal:false)
  job=BillingWorkItem.find_by!(**p.w.scope,case_id:case_id,batch_id:marker['batch_id'])
  raise 'Incomplete executed fixture' unless job.status=='completed' && b['accounting'] && b['accounting']['current']
  {'case_id'=>case_id,'label'=>case_id=='advisor' ? 'Advisor business' : 'Independent RIA','billing_period'=>'October 2026',
   'billing'=>b.slice('target_id','assessed_minor','applied_minor','outstanding_minor','ledger_hash'),
   'credit'=>a.slice('target_id','credit_balance_minor','ledger_hash').merge('requested_minor'=>a['refund_requests'].first['amount_minor'],'confirmed_refund_minor'=>a['refund_requests'].first['confirmed_minor']),
   'earnings'=>e.slice('target_id','assessed_minor','applied_minor','outstanding_minor','ledger_hash'),
   'accounting'=>b['accounting'].slice('package_id','package_hash','recognized_minor','deferred_minor','reported_ar_minor','journal_id','current','mocked'),
   'worker'=>{'job_id'=>job.job_id,'job_class'=>job.job_class,'attempts'=>job.attempts,'status'=>job.status}}
end
puts JSON.pretty_generate({'schema'=>'billing-lifecycle-proof/v1','synthetic'=>true,'captured_on'=>Time.current.to_date.iso8601,'description'=>'Executed synthetic cases exported without calculating or changing data. Cash and accounting are independent evidence.','cases'=>cases})
