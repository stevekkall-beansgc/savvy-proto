# Explicit fictional setup through the same commands used by the application.
# Never invoked from a page read or a deployment activation.
class BillingPlatformSeed
  FIELDS=BillingPipeline::FIELDS
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

  def command(case_id,action,input,key,role='operator')
    BillingPlatform.new(actor(role),case_id).command(action,input,"platform-seed-#{case_id}-#{key}")
  end
  def call
    %w[advisor ria].each do |case_id|
      DemoScope.transaction do
      p=BillingPlatform.new(@workbench,case_id)
      next if p.rows('document').exists?
      source=command(case_id,'REGISTER_SOURCE',{'name'=>'network-report','mapping'=>{'format'=>'json','records_path'=>'records','fields'=>FIELDS.to_h { |f| [f,f] }}},'source')['source_id']
      rows=sample(case_id)
      result=command(case_id,'INGEST',{'source_id'=>source,'delivery_key'=>'network-balances-v1','raw'=>{'records'=>rows}.to_json},'initial-delivery')
      raise "Sample normalization failed: #{result['errors']}" unless result['status']=='completed'
      subjects=case_id=='advisor' ? %w[alder-household birch-household cedar-household] : ['ria-harbor']
      config=case_id=='advisor' ? {
        'version'=>'advisor-service-v1','allocation'=>'balance','components'=>[{'id'=>'advisory','kind'=>'aum','basis'=>'daily','rate'=>'3/250','day_basis'=>365},{'id'=>'planning','kind'=>'flat','amount_minor'=>5000,'proration'=>'service_days'},{'id'=>'additional_service','kind'=>'events','direction'=>'charge'},{'id'=>'service_credit','kind'=>'events','direction'=>'credit'}],'compensation'=>{'share'=>'4/5'}
      } : {'version'=>'ria-platform-v1','allocation'=>'equal','components'=>[{'id'=>'platform','kind'=>'flat','amount_minor'=>10_000,'proration'=>'service_days'},{'id'=>'account_usage','kind'=>'per_account','amount_minor'=>3000,'proration'=>'service_days'},{'id'=>'service_credit','kind'=>'events','direction'=>'credit'},{'id'=>'custodial_income','kind'=>'observation','collection'=>'network_income','label'=>'Reported custodial income, separate from platform fees'}],'cap_minor'=>25_000}
      saved=command(case_id,'SAVE_POLICY',{'policy'=>config,'effective_from'=>'2026-09-01','effective_to'=>'2026-11-01','reason'=>'Fictional two-period billing example'},'initial-policy')
      comparison=command(case_id,'COMPARE_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>subjects.first,'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'},'initial-comparison')
      %w[legal finance].each { |role| command(case_id,'REVIEW_POLICY',{'comparison_id'=>comparison['comparison_id'],'decision'=>'approved','reason'=>'Fictional demonstration review','document_ref'=>{'system'=>'mock_clm','document_id'=>"#{case_id}-terms",'version'=>'v1'}},"initial-#{role}",role) }
      command(case_id,'PUBLISH_POLICY',{'comparison_id'=>comparison['comparison_id']},'initial-publication')
      subjects.each do |subject|
        command(case_id,'ASSIGN_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>subject,'effective_from'=>'2026-09-01','effective_to'=>'2026-11-01','expected_schedule_hash'=>p.hash([]),'reason'=>'Assign reviewed demonstration terms'},"assign-#{subject}")
        [['2026-09-01','2026-10-01'],['2026-10-01','2026-11-01']].each do |from,to|
          run=command(case_id,'EVALUATE',{'subject_id'=>subject,'service_start'=>from,'service_end_exclusive'=>to},"run-#{subject}-#{from}")
          command(case_id,'ISSUE_INVOICE',{'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'due_on'=>(Time.current.to_date+30).iso8601},"invoice-#{subject}-#{from}")
        end
      end
      finance_rows=p.rows('document').where("payload->>'document_type' = 'invoice'").order(:id).flat_map do |document|
        invoice=BillingDocuments.new(p).native(document)
        line=BillingInvoiceLine.where(**p.w.scope,billing_invoice_id:invoice.id).order(:id).first!
        obligation=BillingObligation.find_by!(**p.w.scope,id:line.billing_obligation_id)
        common={'revision'=>1,'observed_at'=>Time.current.iso8601(6),'billing_subject_id'=>invoice.billing_subject_id,'customer_id'=>obligation.customer_id,'account_id'=>obligation.account_id,'date'=>Time.current.to_date.iso8601,'document_id'=>invoice.external_id,'currency'=>'USD'}
        [common.merge('id'=>"cash-#{invoice.external_id}",'type'=>'cash','amount_minor'=>invoice.amount_minor,'direction'=>'inbound','status'=>'confirmed','payer_id'=>invoice.debtor_id,'payee_id'=>invoice.creditor_id),common.merge('id'=>"accounting-#{invoice.external_id}",'type'=>'accounting','amount_minor'=>invoice.amount_minor,'provider'=>'mock_campfire','reported_status'=>'received')]
      end
      finance_rows.group_by { |row| row['type'] }.each do |kind,records|
        producer=kind=='accounting' ? 'mock-campfire' : 'payment-evidence'
        mapped=command(case_id,'REGISTER_SOURCE',{'name'=>producer,'mapping'=>{'format'=>'json','records_path'=>'records','fields'=>FIELDS.to_h { |f| [f,f] }}},"#{kind}-source")['source_id']
        command(case_id,'INGEST',{'source_id'=>mapped,'delivery_key'=>"#{kind}-evidence",'raw'=>{'records'=>records}.to_json},"#{kind}-evidence")
      end
      # Leave a real, unapproved correction proposal so the next step is visible.
      changed=sample(case_id).select { |r| r['type']=='balance' && r['billing_subject_id']==subjects.first && r['date']>='2026-10-01' }.map do |r|
        value=r['amount_minor']+(r['account_id'].end_with?('-a') ? 10_000_000 : -10_000_000)
        r.merge('revision'=>2,'amount_minor'=>value)
      end
      if case_id=='ria'
        changed=sample(case_id).select { |r| r['type']=='account' && r['customer_id']!='alder-household' }.map { |r| r.merge('revision'=>2,'active_to'=>'2026-10-01') }
      end
      command(case_id,'INGEST',{'source_id'=>source,'delivery_key'=>'late-balance-revision','raw'=>{'records'=>changed}.to_json},'late-delivery')
      run=command(case_id,'EVALUATE',{'subject_id'=>subjects.first,'service_start'=>'2026-10-01','service_end_exclusive'=>'2026-11-01'},'corrected-run')
      original=p.rows('document').where("payload->>'subject_id' = ? AND payload->>'service_start' = '2026-10-01' AND payload->>'document_type' = 'invoice'",subjects.first).first!
      command(case_id,'PROPOSE_CORRECTION',{'document_id'=>original.external_id,'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Late network balance revision; review account allocation'},'correction-proposal')
      end
    end
    {'synthetic'=>true,'both_products'=>true,'periods'=>2}
  end
  def sample(case_id)
    rows=%w[alder birch cedar].flat_map.with_index do |name,index|
      %w[a b].flat_map do |member|
        account="#{case_id}-#{name}-#{member}"; customer="#{name}-household"
        common={'revision'=>1,'observed_at'=>'2026-11-01T00:00:00Z','billing_subject_id'=>case_id=='advisor' ? customer : 'ria-harbor','customer_id'=>customer,'account_id'=>account}
        [common.merge('id'=>"account-#{account}",'type'=>'account','label'=>"#{name.capitalize} household",'active_from'=>'2026-09-01','active_to'=>nil,'eligible'=>true,'dimensions'=>{'segment'=>index.zero? ? 'new' : 'established'})]+(Date.iso8601('2026-09-01')...Date.iso8601('2026-11-01')).map do |day|
          common.merge('id'=>"balance-#{account}-#{day}",'type'=>'balance','date'=>day.iso8601,'currency'=>'USD','amount_minor'=>(member=='a' ? 60_000_000 : 40_000_000)+(index*10_000_000))
        end
      end
    end
    if case_id=='ria'
      %w[2026-09-30 2026-10-31].each do |day|
        rows << {'id'=>"custody-income-#{day}",'revision'=>1,'type'=>'measure','observed_at'=>'2026-11-01T00:00:00Z','billing_subject_id'=>'ria-harbor','customer_id'=>'ria-harbor','account_id'=>'ria-harbor','date'=>day,'currency'=>'USD','unit'=>'USD_minor','basis'=>'source_reported','collection'=>'network_income','value'=>'120000','attributes'=>{'stream'=>'custody'}}
      end
    end
    rows
  end
end
