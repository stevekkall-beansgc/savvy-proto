ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class BillingPlatformTest < Minitest::Test
  def setup
    SyntheticReset.call; @w=Workbench.new(role:'operator'); @w.seed!
    @case='advisor'; @p=BillingPlatform.new(@w,@case); @n=0
    fields=BillingPipeline::FIELDS
    @mapping={'format'=>'json','records_path'=>'rows','fields'=>fields.to_h { |key| [key,key] }}
    @source=command('REGISTER_SOURCE',{'name'=>'custodian','mapping'=>@mapping})['source_id']
    ingest(records)
  end
  def command(action,input,role='operator')
    @n+=1; BillingPlatform.new(Workbench.new(role:role),@case).command(action,input,"platform-test-#{@n}")
  end
  def records
    %w[a b].flat_map.with_index do |account,index|
      common={'revision'=>1,'observed_at'=>'2026-10-01T00:00:00Z','billing_subject_id'=>'group-one','customer_id'=>'client-one','account_id'=>account}
      [common.merge('id'=>"account-#{account}",'type'=>'account','active_from'=>'2026-09-01','active_to'=>nil,'eligible'=>true,'dimensions'=>{'segment'=>index.zero? ? 'new' : 'existing'},'label'=>'Client One')]+%w[2026-09-01 2026-09-02].map { |date| common.merge('id'=>"balance-#{account}-#{date}",'type'=>'balance','date'=>date,'currency'=>'USD','amount_minor'=>100_000_000) }
    end
  end
  def ingest(rows,key=nil)
    command('INGEST',{'source_id'=>@source,'delivery_key'=>key || "delivery-#{@n}",'raw'=>{'rows'=>rows}.to_json})
  end
  def policy(amount=10_000,extra={})
    {'version'=>'config-v1','components'=>[{'id'=>'service','kind'=>'flat','amount_minor'=>amount,'proration'=>'none'}],'allocation'=>'balance'}.merge(extra)
  end
  def publish(config,base:nil,start:'2026-09-01',finish:'2026-10-01')
    saved=command('SAVE_POLICY',{'policy'=>config,'effective_from'=>start,'effective_to'=>finish,'reason'=>'Fictional policy test'})
    compared=command('COMPARE_POLICY',{'policy_id'=>saved['policy_id'],'baseline_policy_id'=>base,'subject_id'=>'group-one','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'})
    %w[legal finance].each do |role|
      command('REVIEW_POLICY',{'comparison_id'=>compared['comparison_id'],'decision'=>'approved','reason'=>'Review fictional policy','document_ref'=>{'system'=>'mock_clm','document_id'=>'terms-one','version'=>'v1'}},role)
    end
    command('PUBLISH_POLICY',{'comparison_id'=>compared['comparison_id']})
    saved['policy_id']
  end
  def assign(id)
    schedule=@p.schedule('group-one')
    command('ASSIGN_POLICY',{'policy_id'=>id,'subject_id'=>'group-one','effective_from'=>'2026-09-01','effective_to'=>'2026-09-03','reason'=>'Assign reviewed test','expected_schedule_hash'=>@p.hash(schedule.map { |r| [r.external_id,r.payload_hash] })})
  end
  def evaluate
    command('EVALUATE',{'subject_id'=>'group-one','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'})
  end
  def issue(run)
    command('ISSUE_INVOICE',{'run_id'=>run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'due_on'=>(Time.current.to_date+30).iso8601})
  end
  def test_both_products_use_same_complete_path_and_native_lines
    %w[advisor ria].each do |product|
      if product=='ria'
        @case=product; @p=BillingPlatform.new(@w,@case)
        @source=command('REGISTER_SOURCE',{'name'=>'custodian','mapping'=>@mapping})['source_id']; ingest(records)
      end
      p=publish(policy); assign(p); run=evaluate; assert_equal 10_000,run['amount_minor']
      document=issue(run); native=BillingInvoice.find_by!(external_id:document['document_id'])
      assert_equal [product,'invoice',10_000,'group-one','firm-demo'],native.attributes.values_at('billing_case_id','document_type','amount_minor','debtor_id','creditor_id')
      assert_equal [5000,5000],BillingInvoiceLine.where(billing_invoice_id:native.id).order(:id).pluck(:amount_minor)
      assert_equal document['document_id'],issue(run)['document_id']
    end
  end
  def test_reallocation_and_repeated_correction_do_not_double_charge_or_mutate_original
    assign(publish(policy)); original=issue(evaluate); invoice=BillingInvoice.find_by!(external_id:original['document_id']); old=invoice.attributes
    %w[a b].each_with_index do |account,index|
      rows=records.select { |r| r['type']=='balance' && r['account_id']==account }.map { |r| r.merge('revision'=>2,'amount_minor'=>index.zero? ? 130_000_000 : 70_000_000) }
      assert_equal 'completed',ingest(rows)['status']
    end
    new_run=evaluate; proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>new_run['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Late balance allocation correction'})
    assert_equal({'a'=>1500,'b'=>-1500},proposal['changes'])
    assert_raises(Economics::Error) { command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']}) }
    command('REVIEW_CORRECTION',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Review source correction'},'finance')
    result=command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']})
    assert_equal %w[credit_note debit_note],BillingInvoice.where(external_id:result['document_ids']).order(:id).pluck(:document_type)
    assert_equal [1500,1500],BillingInvoice.where(external_id:result['document_ids']).order(:id).pluck(:amount_minor)
    assert_equal result['document_ids'],command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']})['document_ids']
    assert_equal old,invoice.reload.attributes
    records.select { |r| r['type']=='balance' }.group_by { |r| r['account_id'] }.each do |account,rows|
      ingest(rows.map { |r| r.merge('revision'=>3,'amount_minor'=>account=='a' ? 120_000_000 : 80_000_000) })
    end
    next_proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>evaluate['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Second source correction'})
    assert_equal({'a'=>-500,'b'=>500},next_proposal['changes'])
  end
  def test_source_quarantine_deduplication_replay_and_revision_before_date_filter
    before=@p.rows('normalized').count
    assert_equal 'completed',ingest(records)['status']; assert_equal before,@p.rows('normalized').count
    bad=records.first.merge('eligible'=>'yes')
    delivery=ingest([bad]); assert_equal 'quarantined',delivery['status']; assert_equal before,@p.rows('normalized').count
    assert_equal 'quarantined',command('REPLAY',{'delivery_id'=>delivery['delivery_id'],'source_id'=>@source})['status']
    raw=command('INGEST',{'source_id'=>@source,'delivery_key'=>'invalid-json','raw'=>'not json'})
    assert_equal 'quarantined',raw['status']; assert_equal 'not json',BillingPipeline.new(@p).original_bytes(@p.get('delivery','invalid-json'))
    conflict=ingest([records.find { |r| r['type']=='balance' }.merge('amount_minor'=>3)])
    assert_equal 'quarantined',conflict['status']
    moved=records.find { |r| r['type']=='balance' }.merge('revision'=>2,'date'=>'2026-09-04')
    ingest([moved]); error=assert_raises(Economics::Error) { BillingPipeline.new(@p).manifest('group-one',Date.iso8601('2026-09-01'),Date.iso8601('2026-09-03'),Time.current.iso8601(6)) }
    assert_equal 'INCOMPLETE_SOURCE',error.code
  end
  def test_policy_composition_uses_engine_for_fees_and_compensation
    config={'version'=>'composed-v1','allocation'=>'equal','components'=>[{'id'=>'aum','kind'=>'aum','basis'=>'daily','rate'=>'1/100','day_basis'=>365},{'id'=>'platform','kind'=>'per_account','amount_minor'=>1000},{'id'=>'planning','kind'=>'flat','amount_minor'=>2000,'proration'=>'none'}],'cap_minor'=>20_000,'compensation'=>{'share'=>'4/5'}}
    assign(publish(config)); run=evaluate; assert_equal 14_959,run['amount_minor']
    stored=@p.get('calculation',run['run_id']); comp=stored.payload['segments'].first['result']['details'].find { |d| d['id']=='compensation' }
    assert_equal 11_967,comp['assessed_minor']
    assert stored.payload['segments'].first['result']['details'].any? { |d| d['id']=='compensation_exact_charge' && d['basis']=='exact_accrual' }
  end
  def test_client_reads_are_scoped_read_only_and_show_issued_basis
    assign(publish(policy)); document=issue(evaluate)
    reader=BillingWorkspace.new(Workbench.new(role:'advisor'),'advisor')
    before=[MedallionEvidence.count,BillingInvoice.count,BillingInvoiceLine.count]
    original=Economics::Engine.instance_method(:evaluate)
    Economics::Engine.define_method(:evaluate) { |*args,**kw| raise 'A read attempted pricing' }
    overview=reader.view(audience:'client')
    assert_equal 10_000,overview.dig('summary','corrected_billed_minor')
    assert_nil overview.dig('summary','compensation_minor')
    detail=reader.view(audience:'client',record_id:document['document_id'])['record']
    assert_equal 10_000,detail['amount_minor']; assert_equal 2,detail['lines'].size
    assert_equal 10_000,detail['basis'].first['components'].first['amount_minor']
    refute detail.key?('run_id'); refute detail.key?('original_bytes')
    clients=reader.view(audience:'client',section:'clients',limit:1)
    assert_equal 1,clients['page']['total']; assert_equal 1,clients['clients'].size
    assert_equal before,[MedallionEvidence.count,BillingInvoice.count,BillingInvoiceLine.count]
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { reader.view(audience:'product',section:'pipeline') }.code
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { BillingWorkspace.new(Workbench.new(role:'advisor'),'ria').view(audience:'client') }.code
  ensure
    Economics::Engine.define_method(:evaluate,original) if original
  end
  def test_both_zero_and_increase_corrections_use_the_latest_issued_target
    base=publish(policy); assign(base); original=issue(evaluate)
    zero=publish(policy(0),base:base); assign(zero); changed=evaluate
    proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>changed['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Full service credit'})
    command('REVIEW_CORRECTION',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Review full credit'},'finance')
    credits=command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']})
    assert_equal 10_000,BillingInvoice.where(external_id:credits['document_ids']).sum(:amount_minor)
    assert_equal ['credit_note'],BillingInvoice.where(external_id:credits['document_ids']).pluck(:document_type)
    later=publish(policy(5000),base:zero); assign(later)
    next_proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>evaluate['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Revised service obligation'})
    assert_equal 5000,next_proposal['changes'].values.sum
    command('REVIEW_CORRECTION',{'proposal_id'=>next_proposal['proposal_id'],'decision'=>'approved','reason'=>'Review revised obligation'},'finance')
    debits=command('ISSUE_CORRECTION',{'proposal_id'=>next_proposal['proposal_id']})
    assert_equal ['debit_note'],BillingInvoice.where(external_id:debits['document_ids']).pluck(:document_type)
    summary=BillingWorkspace.new(Workbench.new(role:'advisor'),'advisor').view(audience:'client')['summary']
    assert_equal 5000,summary['corrected_billed_minor']
  end
  def test_assignment_boundaries_are_split_without_hardcoded_fixture_dates
    base=publish(policy(10_000).merge('components'=>[{'id'=>'service','kind'=>'flat','amount_minor'=>10_000,'proration'=>'service_days'}])); assign(base)
    future=publish(policy(20_000).merge('components'=>[{'id'=>'service','kind'=>'flat','amount_minor'=>20_000,'proration'=>'service_days'}]),base:base,start:'2026-09-02')
    schedule=@p.schedule('group-one')
    command('ASSIGN_POLICY',{'policy_id'=>future,'subject_id'=>'group-one','effective_from'=>'2026-09-02','effective_to'=>'2026-09-03','reason'=>'Reviewed mid-period change','expected_schedule_hash'=>@p.hash(schedule.map { |r| [r.external_id,r.payload_hash] })})
    run=evaluate; assert_equal 15_000,run['amount_minor']
    segments=@p.get('calculation',run['run_id']).payload['segments']; assert_equal 2,segments.size
    assert_equal [5000,10_000],segments.map { |s| s['total_minor'] }
  end
  def test_event_approval_is_independent_and_binds_the_exact_revision
    common=records.first.slice('observed_at','billing_subject_id','customer_id','account_id')
    event=common.merge('id'=>'ad-hoc-service','revision'=>1,'type'=>'event','date'=>'2026-09-02','currency'=>'USD','amount_minor'=>1200,'direction'=>'charge','reason'=>'Additional agreed service')
    ingest([event])
    config=policy.merge('components'=>policy['components']+[{'id'=>'adjustments','kind'=>'events','direction'=>'charge'}]); assign(publish(config))
    before=evaluate; assert_equal 10_000,before['amount_minor']
    source=@p.rows('normalized').where("payload->'record'->>'id' = 'ad-hoc-service'").first!
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { command('REVIEW_EVENT',{'record_id'=>source.external_id,'expected_hash'=>source.payload_hash,'decision'=>'approved','reason'=>'Not finance'}) }.code
    command('REVIEW_EVENT',{'record_id'=>source.external_id,'expected_hash'=>source.payload_hash,'decision'=>'approved','reason'=>'Finance reviewed service'},'finance')
    assert_equal 11_200,evaluate['amount_minor']
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { @p.fresh_run!(@p.get('calculation',before['run_id'])) }.code
    ingest([event.merge('revision'=>2,'amount_minor'=>1500)])
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { command('REVIEW_EVENT',{'record_id'=>source.external_id,'expected_hash'=>source.payload_hash,'decision'=>'approved','reason'=>'Stale event view'},'finance') }.code
  end
  def test_raw_graph_and_source_mapping_changes_use_data_only
    graph={'version'=>'bespoke-v1','nodes'=>[{'id'=>'charge','op'=>'literal','role'=>'terminal','unit'=>'USD_minor','basis'=>'assessed','value'=>12_345,'output_class'=>'obligation','payer'=>'$subject','payee'=>'firm-demo','currency'=>'USD','explanation'=>'Agreed bespoke service charge'}]}
    config={'version'=>'bespoke-v1','graph'=>graph,'allocation'=>'equal','input_requirements'=>{'balances'=>'none'}}
    assign(publish(config)); assert_equal 12_345,evaluate['amount_minor']
    bad_mapping=@mapping.merge('fields'=>@mapping['fields'].merge('id'=>'external_key'))
    source=command('REGISTER_SOURCE',{'name'=>'alternate-feed','mapping'=>bad_mapping})['source_id']
    arrival=command('INGEST',{'source_id'=>source,'delivery_key'=>'mapped-delivery','raw'=>{'rows'=>[records.first]}.to_json})
    assert_equal 'quarantined',arrival['status']
    corrected=command('REGISTER_SOURCE',{'name'=>'alternate-feed','mapping'=>@mapping})['source_id']
    outcome=command('REPLAY',{'source_id'=>corrected,'delivery_id'=>arrival['delivery_id']})
    assert_equal 'completed',outcome['status']; assert_equal 1,outcome['record_count']
    execution=@p.get('normalization',outcome['execution_id']); assert_equal corrected,execution.payload['source_id']
  end
  def test_conflicting_delivery_and_binary_bytes_are_retained_in_quarantine
    first=ingest(records,'stable-delivery'); assert_equal 'completed',first['status']
    conflict=command('INGEST',{'source_id'=>@source,'delivery_key'=>'stable-delivery','raw'=>'different original bytes'})
    assert_equal 'quarantined',conflict['status']; refute_equal 'stable-delivery',conflict['delivery_id']
    assert_equal 'different original bytes',BillingPipeline.new(@p).original_bytes(@p.get('delivery',conflict['delivery_id']))
    binary=command('INGEST',{'source_id'=>@source,'delivery_key'=>'binary-delivery','raw_base64'=>Base64.strict_encode64("\xff\x00".b)})
    assert_equal 'quarantined',binary['status']
    artifact=@p.get('artifact',@p.get('delivery',binary['delivery_id']).payload['artifact_id'])
    detail=BillingWorkspace.new(@w,@case).view(audience:'product',record_id:artifact.external_id)['record']
    assert_nil detail['original_bytes']; assert_equal '/wA=',detail['original_base64']
  end
  def test_closed_posting_period_and_stale_correction_review_fail_closed
    assign(publish(policy)); original=issue(evaluate)
    proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>evaluate['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Review retained evidence'})
    command('REVIEW_CORRECTION',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Review same result'},'finance')
    command('CLOSE_PERIOD',{'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Close synthetic posting month'},'finance')
    assert_equal 'PERIOD_CLOSED',assert_raises(Economics::Error) { command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']}) }.code
    assert_equal 1,@p.rows('document').count
    next_period=(Time.current.to_date>>1).strftime('%Y-%m')
    next_proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>evaluate['run_id'],'posting_period'=>next_period,'reason'=>'Post in the next open period'})
    command('REVIEW_CORRECTION',{'proposal_id'=>next_proposal['proposal_id'],'decision'=>'approved','reason'=>'Approve open-period request'},'finance')
    ingest([records.find { |r| r['type']=='balance' && r['date']=='2026-09-02' }.merge('revision'=>2,'amount_minor'=>50_000_000)])
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { command('ISSUE_CORRECTION',{'proposal_id'=>next_proposal['proposal_id']}) }.code
    assert_equal 1,@p.rows('document').count
  end
  def test_versioned_normalization_preserves_exact_decimals_and_withdrawals
    mapping={'format'=>'json','records_path'=>'data','fields'=>{'id'=>'key','revision'=>'rev','observed_at'=>'observed','date'=>'day','amount_minor'=>'usd'},'constants'=>{'type'=>'balance','currency'=>'USD','billing_subject_id'=>'group-one','customer_id'=>'client-one','account_id'=>'a'},'coercions'=>{'revision'=>'integer','amount_minor'=>'decimal_usd','date'=>'us_date'}}
    source=command('REGISTER_SOURCE',{'name'=>'precise-feed','mapping'=>mapping})['source_id']
    result=command('INGEST',{'source_id'=>source,'delivery_key'=>'precise-delivery','raw'=>'{"data":[{"key":"precise-1","rev":"1","observed":"2026-10-01T00:00:00Z","day":"09/03/2026","usd":123.4567}]}'})
    assert_equal 'completed',result['status']
    row=@p.rows('normalized').where("payload->'record'->>'id' = 'precise-1'").first!
    assert_equal '1234567/100',row.payload.dig('record','amount_minor')
    assert_equal '2026-09-03',row.payload.dig('record','date')
    balance=records.find { |r| r['type']=='balance' && r['date']=='2026-09-02' }
    old_cutoff=Time.current.iso8601(6)
    ingest([balance.merge('revision'=>2,'withdrawn'=>true)])
    old=BillingPipeline.new(@p).manifest('group-one',Date.iso8601('2026-09-01'),Date.iso8601('2026-09-03'),old_cutoff)
    assert_equal 4,old['engine']['facts'].size
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { BillingPipeline.new(@p).manifest('group-one',Date.iso8601('2026-09-01'),Date.iso8601('2026-09-03'),Time.current.iso8601(6)) }.code
  end
  def test_dated_targeted_rates_tiers_and_rate_table_are_composable
    config={'version'=>'dated-v1','allocation'=>'balance','components'=>[{'id'=>'asset','kind'=>'aum','basis'=>'daily','rates'=>[{'id'=>'standard','kind'=>'standard','rate'=>'1/100','priority'=>100},{'id'=>'promotion','kind'=>'promotion','rate'=>'2/100','priority'=>-100,'from'=>'2026-09-02','to'=>'2026-09-03'},{'id'=>'new-client','kind'=>'targeted_promotion','rate'=>'3/100','priority'=>0,'selector'=>{'segment'=>'new'}}]}]}
    id=publish(config); assign(id); run=evaluate
    # Account A: 3% both days. B: 1%, then 2%. Assessment occurs once.
    assert_equal 24_658,run['amount_minor']
    assert_equal %w[promotion standard targeted_promotion],CommercialRate.where(configuration_id:id).pluck(:kind).sort
    details=@p.get('calculation',run['run_id']).payload['segments'].first['result']['details']
    assert details.any? { |d| d['source_refs'].any? { |r| r['id'].start_with?('dimension_') } }
    assert details.any? { |d| d['explanation']&.start_with?('Accrual') && d['interval']['start']=='2026-09-02' && d['interval']['end_exclusive']=='2026-09-03' }
    tiers={'version'=>'tiers-v1','allocation'=>'equal','components'=>[{'id'=>'asset','kind'=>'aum','basis'=>'daily','tiers'=>[{'upper_minor'=>100_000_000,'rate'=>'1/100'},{'upper_minor'=>nil,'rate'=>'1/200'}]}]}
    revised=publish(tiers,base:id); assign(revised); assert_equal 8219,evaluate['amount_minor']
  end
  def test_raw_graph_rejects_wrong_party_and_unsupported_fields
    config=policy.merge('components'=>[{'id'=>'service','kind'=>'flat','amount_minor'=>10_000,'rate'=>'1/100'}])
    assert_equal 'INVALID_POLICY',assert_raises(Economics::Error) { command('SAVE_POLICY',{'policy'=>config,'effective_from'=>'2026-09-01','effective_to'=>'2026-10-01','reason'=>'Reject ignored field'}) }.code
    graph={'version'=>'bad-party','nodes'=>[{'id'=>'charge','op'=>'literal','role'=>'terminal','unit'=>'USD_minor','basis'=>'assessed','value'=>1000,'output_class'=>'obligation','payer'=>'unrelated-party','payee'=>'firm-demo','currency'=>'USD','explanation'=>'Wrong customer'}]}
    saved=command('SAVE_POLICY',{'policy'=>{'version'=>'bad-party','graph'=>graph,'allocation'=>'equal','input_requirements'=>{'balances'=>'none'}},'effective_from'=>'2026-09-01','effective_to'=>'2026-10-01','reason'=>'Check declared payer'})
    assert_equal 'INVALID_PROGRAM',assert_raises(Economics::Error) { command('COMPARE_POLICY',{'policy_id'=>saved['policy_id'],'subject_id'=>'group-one','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'}) }.code
    assert_equal 0,@p.rows('policy_publication').count
  end
  def test_correction_is_atomic_under_failure_and_concurrent_retries
    assign(publish(policy)); original=issue(evaluate)
    ingest(records.select { |r| r['type']=='balance' && r['date']=='2026-09-02' }.map { |r| r.merge('revision'=>2,'amount_minor'=>r['account_id']=='a' ? 130_000_000 : 70_000_000) })
    proposal=command('PROPOSE_CORRECTION',{'document_id'=>original['document_id'],'run_id'=>evaluate['run_id'],'posting_period'=>Time.current.strftime('%Y-%m'),'reason'=>'Concurrency allocation example'})
    command('REVIEW_CORRECTION',{'proposal_id'=>proposal['proposal_id'],'decision'=>'approved','reason'=>'Review exact proposal'},'finance')
    service=BillingDocuments.new(@p); original_persist=service.method(:persist); calls=0
    service.define_singleton_method(:persist) do |*args,**kw|
      result=original_persist.call(*args,**kw); calls+=1
      raise Economics::Error.new('INJECTED_FAILURE') if calls==2
      result
    end
    before=[BillingInvoice.count,BillingInvoiceLine.count,BillingObligation.count,@p.rows('document').count]
    assert_raises(Economics::Error) { @w.operate('test_atomic_correction',{},'atomic-failure') { service.correct({'proposal_id'=>proposal['proposal_id']}) } }
    assert_equal before,[BillingInvoice.count,BillingInvoiceLine.count,BillingObligation.count,@p.rows('document').count]
    results=2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          BillingPlatform.new(Workbench.new(role:'operator'),@case).command('ISSUE_CORRECTION',{'proposal_id'=>proposal['proposal_id']},"concurrent-correction-#{i}")
        end
      end
    end.map(&:value)
    assert_equal results.first['document_ids'],results.last['document_ids']
    assert_equal 1,@p.rows('correction_issue').count
    assert_equal 3,@p.rows('document').count
    invoice=BillingInvoice.find_by!(external_id:original['document_id'])
    assert_raises(ActiveRecord::StatementInvalid) { BillingInvoice.where(id:invoice.id).update_all(amount_minor:1) }
  end
  def test_missing_evidence_has_a_blocked_execution_receipt_and_no_invoice
    assign(publish(policy)); balance=records.find { |r| r['type']=='balance' && r['date']=='2026-09-02' }
    ingest([balance.merge('revision'=>2,'withdrawn'=>true)])
    result=evaluate; assert_equal 'blocked',result['status']
    attempt=@p.get('calculation_attempt',result['attempt_id']); assert_equal 'INCOMPLETE_SOURCE',attempt.payload['errors'].first['code']
    assert_equal 0,@p.rows('document').count
    before=@p.rows('calculation_attempt').count
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { command('EVALUATE',{'subject_id'=>'group-one','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-03'},'finance') }.code
    assert_equal before,@p.rows('calculation_attempt').count
  end
  def test_replay_replaces_accepted_mapping_without_rewriting_frozen_source
    old=@p.rows('normalized').where("payload->'record'->>'id' = 'balance-a-2026-09-01'").first!
    cutoff=Time.current.iso8601(6)
    mapping=@mapping.merge('constants'=>{'currency'=>'USD'},'fields'=>@mapping['fields'].except('currency'))
    source=command('REGISTER_SOURCE',{'name'=>'custodian','mapping'=>mapping})['source_id']
    assert_equal 0,BillingPipeline.new(@p).current.count
    delivery=@p.rows('delivery').order(:id).first!
    replay=command('REPLAY',{'delivery_id'=>delivery.external_id,'source_id'=>source})
    assert_equal 'completed',replay['status']; assert_equal 6,BillingPipeline.new(@p).current.count
    assert_equal 6,BillingPipeline.new(@p).current(cutoff).count
    selected=BillingPipeline.new(@p).current.find_by!(external_id:old.external_id)
    refute_equal old.id,selected.id
    assert_equal old.payload['record'],selected.payload['record']
    detail=BillingWorkspace.new(@w,@case).view(audience:'product',record_id:old.id.to_s)['record']
    assert_equal @source,detail.dig('data','mapping_id')
    assert_equal 'quarantined',ingest(records.map { |r| r.merge('amount_minor'=>33) },'mapping-conflict')['status']
  end
  def test_optional_reported_income_is_visible_but_never_netted_into_platform_bill
    config=policy.merge('components'=>policy['components']+[{'id'=>'network_income','kind'=>'observation','collection'=>'network_income','label'=>'Reported custody income'}])
    assign(publish(config)); first=evaluate
    assert_equal 10_000,first['amount_minor']
    common=records.first.slice('observed_at','billing_subject_id','customer_id','account_id')
    measure=common.merge('id'=>'custody-income','revision'=>1,'type'=>'measure','date'=>'2026-09-02','currency'=>'USD','unit'=>'USD_minor','basis'=>'source_reported','value'=>'120000','collection'=>'network_income')
    assert_equal 'completed',ingest([measure])['status']
    run=evaluate; assert_equal 10_000,run['amount_minor']
    doc=issue(run); detail=BillingWorkspace.new(Workbench.new(role:'advisor'),@case).view(audience:'client',record_id:doc['document_id'])['record']
    observation=detail['basis'].first['components'].find { |c| c['label']=='Reported custody income' }
    assert_equal false,observation['included_in_bill']; assert_equal '120000/1',observation['exact_amount']
    assert_nil observation['amount_minor']
  end

  def test_overlapping_invoices_and_missing_hourly_evidence_are_rejected
    assign(publish(policy)); issue(evaluate)
    run=command('EVALUATE',{'subject_id'=>'group-one','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-09-02'})
    assert_equal 'CORRECTION_REQUIRED',assert_raises(Economics::Error) { issue(run) }.code
    hourly_config=policy.merge('components'=>[{'id'=>'time','kind'=>'hourly','rate_minor'=>10000}])
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { publish(hourly_config) }.code
    time=records.first.slice('observed_at','billing_subject_id','customer_id','account_id').merge('id'=>'service-time','revision'=>1,'type'=>'time','date'=>'2026-09-01','quantity'=>'3/2')
    ingest([time]); assign(publish(hourly_config)); assert_equal 15000,evaluate['amount_minor']
    ingest([time.merge('revision'=>2,'withdrawn'=>true)]); assert_equal 'blocked',evaluate['status']
  end

end
