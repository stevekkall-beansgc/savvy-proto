ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class WorkspaceStressTest < Minitest::Test
  def setup
    SyntheticReset.call
    @operator=Workbench.new; @operator.seed!
    @finance=Workbench.new(role:'finance'); @legal=Workbench.new(role:'legal')
  end
  def workspace(w=@operator)
    w.product_workspace(workspace:'internal',broker_id:'broker-alex')
  end
  def input(n)
    base=workspace['configuration']; rates=Marshal.load(Marshal.dump(base['rates']))
    rates.find { |r| r['kind']=='promotion' }['numerator']=80+n
    {'broker_id'=>'broker-alex','base_configuration_id'=>base['id'],'expected_base_hash'=>base['hash'],'effective_from'=>'2026-11-14','rates'=>rates,'reason'=>'Synthetic competing terms'}
  end
  def prepare(n)
    p=@operator.save_terms_proposal(input(n),"save-#{n}")
    c=@operator.compare_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>'current_book'},"compare-#{n}")
    [@finance,@legal].each do |w|
      w.review_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash'],'document_ref'=>{'system'=>'mock_clm','document_id'=>'document-demo','version'=>'v1','status'=>'reviewed_for_demo'},'decision'=>'approved_for_demo'},"#{w.role}-#{n}")
    end
    [p,c]
  end
  def concurrent(n,&block)
    gate=Queue.new
    threads=n.times.map do |i|
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection do
          begin; block.call(i); rescue Economics::Error => e; e.code; end
        end
      end
    end
    n.times { gate << true }
    threads.map(&:value)
  end
  def test_concurrent_competing_schedule_is_single_and_reviewed
    @operator.project({'policy_id'=>'policy-v1','snapshot_id'=>'source-20261113-r1'},'historical-run')
    proposals=[prepare(1),prepare(2)]
    prior=@operator.records('run').order(:id).pluck(:payload_hash,:payload)
    results=concurrent(2) do |i|
      p,c=proposals[i]
      Workbench.new(role:'finance').schedule_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']},"race-#{i}")
    end
    assert_equal 1,results.count { |r| r.is_a?(Hash) }
    assert_equal 1,results.count { |r| %w[HASH_CHANGED RULE_CONFLICT].include?(r) }
    assert_equal 1,@operator.records('commercial_schedule').count
    assert_equal prior,@operator.records('run').order(:id).pluck(:payload_hash,:payload)
    proposals.each { |p,c| assert_equal c,@operator.record!('terms_comparison',c['id']) }
  end
  def test_parallel_same_key_retry_conflict_and_lost_result
    data=input(3)
    results=concurrent(4) { |_| Workbench.new.save_terms_proposal(data,'same-key') }
    assert results.all? { |r| r==results.first }
    assert_equal 1,@operator.records('terms_proposal').count
    assert_equal results.first,@operator.save_terms_proposal(data,'same-key')
    assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error) { @operator.save_terms_proposal(data.merge('reason'=>'Different'),'same-key') }.code
  end
  def test_failure_after_rate_insert_rolls_back_all
    before=CommercialRate.count
    singleton=class << DemoOperation; self; end
    singleton.alias_method(:stress_original_create!, :create!)
    singleton.define_method(:create!) { |**_| raise 'injected failure' }
    begin
      assert_raises(RuntimeError) { @operator.save_terms_proposal(input(4),'failed') }
    ensure
      singleton.alias_method(:create!, :stress_original_create!)
      singleton.remove_method(:stress_original_create!)
    end
    assert_equal before,CommercialRate.count
    assert_empty @operator.records('terms_proposal')
    refute DemoOperation.exists?(operation:'save_terms_proposal',idempotency_key:'failed')
  end
  def test_signup_boundaries_and_open_ended_rates
    engine=CommercialEngine.new
    rate={'id'=>'welcome','broker_id'=>'broker-alex','component'=>'advisor_share','kind'=>'targeted_promotion','selector'=>{'product_type'=>'planning'},'signup_within_days'=>7,'priority'=>1,'numerator'=>9,'denominator'=>10,'starts_on'=>'2026-11-01','ends_on'=>nil}
    standard=rate.merge('id'=>'standard','kind'=>'standard','selector'=>{},'signup_within_days'=>nil,'priority'=>nil,'numerator'=>8)
    fact={'broker_id'=>'broker-alex','component'=>'advisor_share','dimensions'=>{'product_type'=>'planning'},'signup_date'=>'2026-11-10'}
    {'2026-11-09'=>'standard','2026-11-10'=>'welcome','2026-11-16'=>'welcome','2026-11-17'=>'standard','2027-01-01'=>'standard'}.each do |date,winner|
      assert_equal winner,engine.select_rate([rate,standard],fact,date:date,cutoff:'2026-11-13T23:00:00Z')['winner']
    end
    assert_equal 'MISSING_SIGNUP_DATE',assert_raises(Economics::Error) { engine.select_rate([rate,standard],fact.except('signup_date'),date:'2026-11-13',cutoff:'2026-11-13T23:00:00Z') }.code
  end
  def test_reviews_are_bound_to_exact_proposal_and_comparison
    p1,c1=prepare(1)
    p2=@operator.save_terms_proposal(input(2),'other-save')
    c2=@operator.compare_terms_proposal({'proposal_id'=>p2['id'],'expected_hash'=>p2['hash'],'example_id'=>'current_book'},'other-compare')
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) {
      @finance.schedule_terms_proposal({'proposal_id'=>p2['id'],'expected_hash'=>p2['hash'],'comparison_hash'=>c1['hash']},'wrong-comparison')
    }.code
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) {
      @finance.schedule_terms_proposal({'proposal_id'=>p2['id'],'expected_hash'=>p2['hash'],'comparison_hash'=>c2['hash']},'unreviewed')
    }.code
    assert_empty @operator.records('commercial_schedule')
    assert_equal c1,@operator.record!('terms_comparison',c1['id'])
    assert_equal c2,@operator.record!('terms_comparison',c2['id'])
  end
  def test_overlaps_open_ended_rates_and_commercial_billing_stability
    before=[BillingObligation.order(:id).map(&:attributes),BillingInvoice.order(:id).pluck(:amount_minor),BillingInvoiceLine.order(:id).pluck(:amount_minor)]
    data=input(1); standard=data['rates'].find { |r| r['kind']=='standard' }
    standard['ends_on']=nil
    data['rates'] << standard.merge('id'=>'overlap-standard','starts_on'=>'2026-11-14','ends_on'=>nil)
    assert_equal 'RULE_CONFLICT',assert_raises(Economics::Error) { @operator.save_terms_proposal(data,'overlap') }.code
    assert_empty @operator.records('terms_proposal')
    assert_equal before,[BillingObligation.order(:id).map(&:attributes),BillingInvoice.order(:id).pluck(:amount_minor),BillingInvoiceLine.order(:id).pluck(:amount_minor)]
  end
  def test_graphql_advisor_scope_and_internal_data_denial
    query='query($broker:ID,$workspace:String!){productWorkspace(workspace:$workspace,brokerId:$broker)}'
    advisor=Workbench.new(role:'advisor')
    data=WorkbenchSchema.execute(query,variables:{'workspace'=>'broker'},context:{workbench:advisor}).to_h
    view=data.dig('data','productWorkspace')
    assert_nil data['errors']
    refute view.key?('configuration'); refute view.key?('proposals')
    assert_equal ['broker-alex'],view['brokers'].map { |b| b['id'] }
    assert_equal ['customer-cedar','customer-maple'],view.dig('billing','obligations').map { |o| o['customer_id'] }.uniq.sort
    %w[internal broker].each do |workspace|
      out=WorkbenchSchema.execute(query,variables:{'workspace'=>workspace,'broker'=>'broker-jordan'},context:{workbench:advisor}).to_h
      assert_equal 'FORBIDDEN',out.dig('errors',0,'extensions','code')
    end
  end

  def test_repeated_parallel_retries_and_competing_schedules
    10.times do |round|
      data=input(1)
      results=concurrent(4) { |_| Workbench.new.save_terms_proposal(data,"replay-#{round}") }
      assert results.all? { |r| r==results.first }, "proposal replay round #{round}"
      assert_equal results.first,@operator.save_terms_proposal(data,"replay-#{round}")
    end
    10.times do |round|
      setup
      pairs=[prepare(1),prepare(2)]
      results=concurrent(2) do |i|
        p,c=pairs[i]
        Workbench.new(role:'finance').schedule_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']},"schedule-race-#{round}-#{i}")
      end
      assert_equal 1,results.count { |r| r.is_a?(Hash) }, "schedule race round #{round}"
      assert_equal 1,results.count { |r| %w[HASH_CHANGED RULE_CONFLICT].include?(r) }
      assert_equal 1,@operator.records('commercial_schedule').count
      winner=results.find { |r| r.is_a?(Hash) }
      selected=pairs.find { |p,_| p['id']==winner['proposal_id'] }
      if selected
        p,c=selected
        args={'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']}
        key="schedule-race-#{round}-#{pairs.index(selected)}"
        retries=concurrent(4) { |_| Workbench.new(role:'finance').schedule_terms_proposal(args,key) }
        assert retries.all? { |r| r==winner }
        assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error) { @finance.schedule_terms_proposal(args.merge('comparison_hash'=>'changed'),key) }.code
      else
        flunk 'schedule result did not identify its source proposal'
      end
    end
  end
  def test_sql_temporal_scope_and_targeted_priority
    base=CommercialRate.first.attributes.except('id').merge('configuration_id'=>'sql-stress','external_id'=>'sql-a','kind'=>'standard','selector'=>{},'signup_within_days'=>nil,'starts_on'=>Date.iso8601('2026-01-01'),'ends_on'=>Date.iso8601('2026-06-01'))
    CommercialRate.create!(base)
    CommercialRate.create!(base.merge('external_id'=>'sql-adjacent','starts_on'=>Date.iso8601('2026-06-01'),'ends_on'=>nil))
    CommercialRate.create!(base.merge('external_id'=>'sql-other-broker','broker_id'=>'broker-jordan','ends_on'=>nil))
    CommercialRate.create!(base.merge('external_id'=>'sql-other-config','configuration_id'=>'sql-other','ends_on'=>nil))
    assert_raises(ActiveRecord::StatementInvalid) { CommercialRate.create!(base.merge('external_id'=>'sql-overlap','ends_on'=>nil)) }
    data=input(1)
    common={'broker_id'=>'broker-alex','component'=>'advisor_share','kind'=>'targeted_promotion','numerator'=>90,'denominator'=>100,'starts_on'=>'2026-11-01','ends_on'=>nil,'signup_within_days'=>nil}
    data['rates'].reject! { |r| r['kind']=='targeted_promotion' }
    data['rates'] << common.merge('id'=>'broad','name'=>'Broad','selector'=>{'customer_type'=>'individual'},'priority'=>1)
    data['rates'] << common.merge('id'=>'specific','name'=>'Specific','selector'=>{'customer_type'=>'individual','product_type'=>'planning'},'priority'=>2)
    assert_kind_of Hash,@operator.save_terms_proposal(data,'priorities')
    data['rates'].last['priority']=1
    assert_equal 'RULE_CONFLICT',assert_raises(Economics::Error) { @operator.save_terms_proposal(data,'equal-priority') }.code
  end
  def test_schedule_failure_rolls_back_configuration_and_preserves_history
    @operator.project({'policy_id'=>'policy-v1','snapshot_id'=>'source-20261113-r1'},'history')
    historical=@operator.records('run').order(:id).pluck(:payload_hash,:payload)
    p,c=prepare(1)
    before=@operator.records('commercial_configuration').count
    singleton=class << DemoRecord; self; end
    singleton.alias_method(:stress_original_create!, :create!)
    singleton.define_method(:create!) do |**attrs|
      raise 'injected schedule failure' if attrs[:kind]=='commercial_schedule'
      stress_original_create!(**attrs)
    end
    begin
      assert_raises(RuntimeError) do
        @finance.schedule_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']},'inject-schedule')
      end
    ensure
      singleton.alias_method(:create!, :stress_original_create!)
      singleton.remove_method(:stress_original_create!)
    end
    assert_equal before,@operator.records('commercial_configuration').count
    assert_empty @operator.records('commercial_schedule')
    refute DemoOperation.exists?(operation:'schedule_terms_proposal',idempotency_key:'inject-schedule')
    assert_equal historical,@operator.records('run').order(:id).pluck(:payload_hash,:payload)
  end

  def test_incomplete_examples_block_review_and_old_comparison_stays_frozen
    p=@operator.save_terms_proposal(input(1),'save-incomplete')
    args={'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>'current_book'}
    old=@operator.compare_terms_proposal(args,'complete')
    snapshot=Economics::Canonical.copy(@operator.snapshot)
    snapshot['id']='source-incomplete'; snapshot['complete']=false
    @operator.write!('snapshot',snapshot)
    blocked=@operator.compare_terms_proposal(args,'incomplete')
    assert_equal 'blocked',blocked.dig('baseline','status')
    assert_equal 'blocked',blocked.dig('proposed','status')
    assert_nil blocked['delta_minor']
    review={'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>blocked['hash'],'document_ref'=>{'system'=>'mock_clm','document_id'=>'doc','version'=>'v1','status'=>'reviewed_for_demo'},'decision'=>'approved_for_demo'}
    assert_equal 'BLOCKED_REVIEW',assert_raises(Economics::Error) { @finance.review_terms_proposal(review,'blocked-review') }.code
    assert_equal old,@operator.record!('terms_comparison',old['id'])
    refute_equal old['hash'],blocked['hash']
  end
  def test_document_version_mismatch_and_all_roles
    p=@operator.save_terms_proposal(input(1),'document-save')
    c=@operator.compare_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>'current_book'},'document-compare')
    [@finance,@legal].each_with_index do |w,i|
      w.review_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash'],'document_ref'=>{'system'=>'mock_clm','document_id'=>'doc','version'=>"v#{i}",'status'=>'reviewed_for_demo'},'decision'=>'approved_for_demo'},"doc-#{i}")
    end
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) { @finance.schedule_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']},'doc-schedule') }.code
    query='query($workspace:String!,$broker:ID){productWorkspace(workspace:$workspace,brokerId:$broker)}'
    %w[operator finance legal auditor advisor].each do |role|
      out=WorkbenchSchema.execute(query,variables:{'workspace'=>'internal'},context:{workbench:Workbench.new(role:role)}).to_h
      if role=='advisor'
        assert_equal 'FORBIDDEN',out.dig('errors',0,'extensions','code')
      else
        assert_nil out['errors']; assert out.dig('data','productWorkspace','configuration')
      end
      out=WorkbenchSchema.execute(query,variables:{'workspace'=>'broker','broker'=>'missing-broker'},context:{workbench:Workbench.new(role:role)}).to_h
      assert_includes %w[FORBIDDEN NOT_FOUND],out.dig('errors',0,'extensions','code')
    end
  end

  def test_unchanged_earnings_changed_source_requires_fresh_comparison_and_reviews
    p,c=prepare(1)
    assert c['hypothetical']
    assert_equal 64,c.dig('baseline','input_manifest','snapshot_hash').length
    old_snapshot=Economics::Canonical.copy(@operator.snapshot)
    @operator.write!('snapshot',old_snapshot.merge('id'=>'same-values-new-source'))
    newer=@operator.compare_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>'current_book'},'fresh-comparison')
    assert_equal c.dig('baseline','earned_minor'),newer.dig('baseline','earned_minor')
    refute_equal c.dig('baseline','input_manifest','snapshot_hash'),newer.dig('baseline','input_manifest','snapshot_hash')
    assert_equal c,@operator.record!('terms_comparison',c['id'])
    input={'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']}
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { @finance.schedule_terms_proposal(input,'stale-source') }.code
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) { @finance.schedule_terms_proposal(input.merge('comparison_hash'=>newer['hash']),'fresh-unreviewed') }.code
    assert_empty @operator.records('commercial_schedule')
  end
  def test_mock_document_reference_rejects_urls_and_unknown_fields
    p=@operator.save_terms_proposal(input(1),'doc-check-save')
    c=@operator.compare_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>'current_book'},'doc-check-compare')
    common={'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash'],'decision'=>'approved_for_demo'}
    reference={'system'=>'mock_clm','document_id'=>'doc','version'=>'v1','status'=>'reviewed_for_demo'}
    [nil, reference.merge('document_id'=>'https://example.org/doc'),reference.merge('url'=>'https://example.org'),reference.merge('system'=>'unknown'),reference.merge('status'=>'signed')].each_with_index do |bad,i|
      assert_equal 'VALIDATION_ERROR',assert_raises(Economics::Error) { @finance.review_terms_proposal(common.merge('document_ref'=>bad),"bad-doc-#{i}") }.code
    end
    assert_empty @operator.records('terms_review')
  end
  def test_future_example_uses_future_effective_date_and_is_not_current_source
    data=input(1); data['effective_from']='2026-12-10'
    data['rates'].each { |r| r['ends_on']=nil if r['kind']=='standard' }
    data['rates'] << {'id'=>'future-signup','broker_id'=>'broker-alex','component'=>'advisor_share','kind'=>'targeted_promotion','name'=>'Welcome',
      'numerator'=>95,'denominator'=>100,'starts_on'=>'2026-12-01','ends_on'=>nil,'selector'=>{'product_type'=>'planning'},'signup_within_days'=>7,'priority'=>10}
    p=@operator.save_terms_proposal(data,'future-source')
    args={'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>'future_signup_example'}
    c=@operator.compare_terms_proposal(args,'future-before')
    assert_equal '2026-12-10',c['business_date']; assert c['hypothetical']
    assert_equal 'completed',c.dig('proposed','status'); assert_equal 95000,c.dig('proposed','earned_minor')
    prior_hash=c.dig('proposed','input_manifest','snapshot_hash')
    @operator.write!('snapshot',Economics::Canonical.copy(@operator.snapshot).merge('id'=>'new-incomplete-current-source','complete'=>false))
    after=@operator.compare_terms_proposal(args,'future-after')
    assert_equal 'completed',after.dig('proposed','status')
    assert_equal prior_hash,after.dig('proposed','input_manifest','snapshot_hash')
  end

end
