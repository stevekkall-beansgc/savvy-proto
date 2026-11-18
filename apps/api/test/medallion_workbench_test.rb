ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
class MedallionWorkbenchTest < Minitest::Test
  def setup
    SyntheticReset.call
    @workbench=Workbench.new; @workbench.seed!
    @workbench.medallion.bootstrap({},'bootstrap')
    @finance=Workbench.new(role:'finance')
  end
  def test_ria_is_forbidden_from_legacy_queries_and_other_case
    w=Workbench.new(role:'ria')
    out=WorkbenchSchema.execute('{ workbench collections reconciliation(periodStart:"2026-11-01",periodEndExclusive:"2026-12-01") }',context:{workbench:w}).to_h
    assert out['errors']&.any? { |e| e.dig('extensions','code')=='FORBIDDEN' }
    error=assert_raises(Economics::Error) { w.medallion.view(workspace:'advisor',case_id:'advisor') }
    assert_equal 'FORBIDDEN',error.code
  end
  def test_account_month_count_requires_matching_complete_scoped_roster
    _,known=@workbench.medallion.facts('ria','baseline','2026-10-02T23:00:00Z')
    assert_equal '30',known.fetch('account_months').fetch('value')
    assert_includes known['account_months']['evidence_refs'],'baseline-account-roster-artifact'
    source=JSON.parse(File.read(Rails.root.join('../../fixtures/medallion/ria-account-roster.json')))
    variants=[]
    duplicate=Marshal.load(Marshal.dump(source)); duplicate['accounts'][1]['id']=duplicate['accounts'][0]['id']; variants << duplicate
    partial=Marshal.load(Marshal.dump(source)); partial['accounts'][0]['active_to_exclusive']='2026-09-29'; variants << partial
    wrong_scope=Marshal.load(Marshal.dump(source)); wrong_scope['accounts'][0]['firm']='other-firm'; variants << wrong_scope
    wrong_roster=Marshal.load(Marshal.dump(source)); wrong_roster['id']='other-roster'; variants << wrong_roster
    variants.each_with_index do |roster,index|
      raw=JSON.generate(roster).b; id="altered-roster-#{index}"
      artifact=@workbench.medallion.store!('ria','baseline','artifact',id:id,status:'retained',
        payload:{'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>'application/json'},bytes:raw)
      proof={'name'=>'account_roster_proof','value'=>{'roster_id'=>roster['id'],'roster_revision'=>roster['revision'],'source_artifact_id'=>id}}
      @workbench.medallion.store!('ria','baseline','fact',id:'baseline-account-roster-proof',revision:index+2,status:'accepted',payload:proof,parent:artifact)
      _,current=@workbench.medallion.facts('ria','baseline',(Time.current+5).iso8601(6))
      refute current.key?('account_months'),"variant #{index} must not use the claimed count"
      _,historical=@workbench.medallion.facts('ria','baseline','2026-10-02T23:00:00Z')
      assert_equal '30',historical.fetch('account_months').fetch('value')
    end
    _,credit=@workbench.medallion.facts('ria','service_credit','2026-10-03T23:00:00Z')
    assert_equal '30',credit.fetch('account_months').fetch('value')
  end
  def test_source_reversals_are_known_only_after_recording
    @workbench.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'receipt-before')
    receipt=@workbench.medallion.get!('ria','baseline','receipt','receipt-network-1')
    reversal=@finance.medallion.reverse_source_receipt({'case_id'=>'ria','receipt_id'=>receipt.external_id,'revision'=>receipt.revision,'expected_hash'=>receipt.payload_hash,'reason'=>'Revised source report'},'reverse-receipt')
    intent=@workbench.medallion.get!('ria','baseline','adjustment_intent',reversal['adjustment_intent_id'])
    assert_equal(-12000,intent.payload['delta_minor'])
    assert_nil intent.payload['posting_period']
    _,earlier=@workbench.medallion.facts('ria','baseline','2026-10-02T23:00:00Z')
    assert earlier.key?('receipt')
    _,current=@workbench.medallion.facts('ria','baseline',(Time.current+5).iso8601(6))
    refute current.key?('receipt')
    funding=@workbench.medallion.get!('advisor','baseline','funding','funding-advisor-1')
    @finance.medallion.reverse_funding({'case_id'=>'advisor','funding_id'=>funding.external_id,'revision'=>funding.revision,'expected_hash'=>funding.payload_hash,'reason'=>'Correct funding evidence'},'reverse-funding')
    _,earlier=@workbench.medallion.facts('advisor','baseline','2026-10-02T23:00:00Z')
    assert earlier.key?('funded_coverage')
    _,current=@workbench.medallion.facts('advisor','baseline',(Time.current+5).iso8601(6))
    refute current.key?('funded_coverage')
  end
  def test_deliveries_retain_raw_duplicate_and_conflict_without_extra_fact
    raw=JSON.generate({'synthetic'=>true,'source_id'=>'balances','revision'=>2,'records'=>[{'name'=>'cedar_30','value'=>'401500000'}]})
    input={'case_id'=>'advisor','source_kind'=>'balance','source_id'=>'balances','revision'=>2,'raw_json'=>raw}
    first=@workbench.medallion.ingest_delivery(input,'arrival-one')
    assert_equal 'accepted',first['status']
    duplicate=@workbench.medallion.ingest_delivery(input,'arrival-two')
    assert_equal 'duplicate',duplicate['status']
    conflict=@workbench.medallion.ingest_delivery(input.merge('raw_json'=>raw.sub('401500000','400000000')),'arrival-three')
    assert_equal 'rejected',conflict['status']; assert_equal 'SOURCE_CONFLICT',conflict['reason_code']
    source=@workbench.medallion.source('advisor','baseline','fact').where("payload->>'name' = ?",'cedar_30')
    assert_equal 2,source.count
    assert_equal raw.b,@workbench.medallion.get!('advisor','baseline','artifact',first['artifact_id']).original_bytes
    assert_equal '365000000',@workbench.medallion.facts('advisor','baseline','2026-10-02T23:00:00Z')[1]['cedar_30']['value']
    assert_equal '401500000',@workbench.medallion.facts('advisor','baseline',(Time.current+5).iso8601(6))[1]['cedar_30']['value']
  end
  def test_rate_rows_are_shared_and_receipt_has_known_time
    assert_operator CommercialRate.where(configuration_id:'ria-policy-v1').count,:>,0
    cutoff='2026-10-01T23:00:00Z'
    _,facts=@workbench.medallion.facts('ria','baseline',cutoff)
    refute facts.key?('receipt')
    _,facts=@workbench.medallion.facts('ria','baseline','2026-10-02T23:00:00Z')
    assert_equal '30000',facts.fetch('receipt').fetch('value')
  end
  def test_database_rejects_rewriting_history
    row=MedallionEvidence.first
    assert_raises(ActiveRecord::StatementInvalid) { MedallionEvidence.where(id:row.id).update_all(status:'rejected') }
    assert_equal row.status,row.reload.status
  end
  def test_approved_events_use_graph_and_respect_cutoff
    {'bonus_outside'=>['advisor','340000'],'bonus_inside'=>['advisor','330000'],'service_credit'=>['ria','10000']}.each do |scenario,(case_id,amount)|
      policy="#{scenario}-policy-v1"
      early=@workbench.medallion.evaluate_case({'case_id'=>case_id,'scenario_id'=>scenario,'policy_id'=>policy,'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},"#{scenario}-early")
      assert_equal 'completed',early['status']
      early_output=scenario=='service_credit' ? 'current_due' : 'compensation'
      assert_equal(scenario=='service_credit' ? '13000' : '330000',early['result']['details'].find { |x| x['id']==early_output }['assessed_minor'].to_s)
      later=@workbench.medallion.evaluate_case({'case_id'=>case_id,'scenario_id'=>scenario,'policy_id'=>policy,'knowledge_cutoff'=>'2026-10-03T23:00:00Z'},"#{scenario}-later")
      assert_equal 'completed',later['status']
      output=scenario=='service_credit' ? 'current_due' : 'compensation'
      assert_equal amount,later['result']['details'].find { |x| x['id']==output }['assessed_minor'].to_s
    end
  end
  def test_four_policy_only_comparisons_use_identical_evidence
    cases={'rebate-50'=>['ria','net',10000], 'balance-pricing'=>['ria','net',6000],
      'floor-3400'=>['advisor','payable',240000], 'extra-50'=>['ria','net',18000]}
    cases.each do |name,(case_id,output,expected)|
      base=@workbench.medallion.policy!(case_id,'baseline',"#{case_id}-policy-v1")
      graph=JSON.parse(File.read(Rails.root.join("../../fixtures/medallion/comparisons/#{name}-policy.json")))
      rate_rows=graph.delete('rate_rows')
      existing=CommercialRate.where(configuration_id:base.external_id).pluck(:external_id)
      rates=rate_rows.map do |id,source|
        n=Rational(source.fetch('value')); item={'id'=>id,'numerator'=>n.numerator,'denominator'=>n.denominator}
        unless existing.include?(id)
          item.merge!('name'=>'Asset-based platform rate','component'=>'asset_platform_rate','kind'=>'standard',
            'broker_id'=>'ria-harbor','payer_id'=>'ria-harbor','payee_id'=>'firm-demo','starts_on'=>'2026-09-01','ends_on'=>'2026-10-01','selector'=>{})
        end
        item
      end
      draft=@workbench.medallion.save_policy({'case_id'=>case_id,'base_id'=>base.external_id,'expected_base_hash'=>base.payload_hash,
        'policy'=>graph,'rates'=>rates,'reason'=>'Review supported terms'},"draft-#{name}")
      c=@workbench.medallion.compare({'case_id'=>case_id,'baseline_policy_id'=>base.external_id,'proposed_policy_id'=>draft['id'],
        'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},"comparison-#{name}")
      assert_equal 'completed',c['status'],name
      assert_equal expected,c.dig('proposed','details').find { |d| d['id']==output }['assessed_minor'],name
      assert_equal c.dig('baseline','input_manifest_hash'),c.dig('proposed','input_manifest_hash'),name
    end
  end
  def test_publication_rejects_new_same_amount_source_revision
    service=@workbench.medallion; base=service.policy!('ria','baseline','ria-policy-v1')
    draft=service.save_policy({'case_id'=>'ria','base_id'=>base.external_id,'expected_base_hash'=>base.payload_hash,
      'policy'=>base.payload['policy'],'rates'=>[{'id'=>'rate_rebate_rate','numerator'=>1,'denominator'=>2}],'reason'=>'Review change'},'stale-draft')
    c=service.compare({'case_id'=>'ria','baseline_policy_id'=>base.external_id,'proposed_policy_id'=>draft['id'],'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'stale-compare')
    ref={'system'=>'mock_clm','document_id'=>'doc','version'=>'v1','status'=>'reviewed_for_demo'}
    [Workbench.new(role:'finance'),Workbench.new(role:'legal')].each do |actor|
      actor.medallion.review_policy({'case_id'=>'ria','policy_id'=>draft['id'],'comparison_id'=>c['id'],'document_ref'=>ref,'decision'=>'approved_for_demo'},"stale-#{actor.role}")
    end
    raw=JSON.generate({'synthetic'=>true,'source_id'=>'network-revision','revision'=>2,'records'=>[{'name'=>'reported_cash_savvy','value'=>'18000'}]})
    @workbench.medallion.ingest_delivery({'case_id'=>'ria','source_kind'=>'network_report','source_id'=>'network-revision','revision'=>2,'raw_json'=>raw},'same-amount')
    result=assert_raises(Economics::Error) do
      @finance.medallion.publish({'case_id'=>'ria','policy_id'=>draft['id'],'comparison_id'=>c['id'],'effective_from'=>'2026-09-01'},'stale-publish')
    end
    assert_equal 'HASH_CHANGED',result.code
  end
  def test_assignment_replacement_preserves_old_known_schedule
    service=@workbench.medallion; base=service.policy!('ria','baseline','ria-policy-v1')
    old=service.assignment_for('ria','baseline','2026-10-02T23:00:00Z')
    draft=service.save_policy({'case_id'=>'ria','base_id'=>base.external_id,'expected_base_hash'=>base.payload_hash,
      'policy'=>base.payload['policy'],'rates'=>[{'id'=>'rate_rebate_rate','numerator'=>1,'denominator'=>2}],'reason'=>'Review change'},'assignment-draft')
    comparison=service.compare({'case_id'=>'ria','baseline_policy_id'=>base.external_id,'proposed_policy_id'=>draft['id'],'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'assignment-compare')
    ref={'system'=>'mock_clm','document_id'=>'doc','version'=>'v1','status'=>'reviewed_for_demo'}
    [Workbench.new(role:'finance'),Workbench.new(role:'legal')].each do |actor|
      actor.medallion.review_policy({'case_id'=>'ria','policy_id'=>draft['id'],'comparison_id'=>comparison['id'],'document_ref'=>ref,'decision'=>'approved_for_demo'},"assignment-#{actor.role}")
    end
    @finance.medallion.publish({'case_id'=>'ria','policy_id'=>draft['id'],'comparison_id'=>comparison['id'],'effective_from'=>'2026-09-01'},'assignment-publish')
    @finance.medallion.assign_policy({'case_id'=>'ria','policy_id'=>draft['id'],'policy_hash'=>draft['hash'],'subject_id'=>'ria-harbor','product_id'=>'ria-platform',
      'starts_on'=>'2026-09-01','ends_on'=>'2026-10-01','supersedes_assignment_id'=>old.external_id,'expected_assignment_hash'=>old.payload_hash},'replace')
    assert_equal old.external_id,service.assignment_for('ria','baseline','2026-10-02T23:00:00Z').external_id
    current=service.assignment_for('ria','baseline',(Time.current+10).iso8601(6))
    assert_equal draft['id'],current.payload['policy_id']
    assert_equal 2,current.schedule_version
  end
  def test_rate_only_draft_comparison_uses_shared_rate_store
    base=@workbench.medallion.policy!('ria','baseline','ria-policy-v1')
    draft=@workbench.medallion.save_policy({'case_id'=>'ria','base_id'=>base.external_id,'expected_base_hash'=>base.payload_hash,
      'policy'=>base.payload['policy'],'rates'=>[{'id'=>'rate_rebate_rate','numerator'=>1,'denominator'=>2}],'reason'=>'Test revised rate'},'draft')
    comparison=@workbench.medallion.compare({'case_id'=>'ria','baseline_policy_id'=>base.external_id,'proposed_policy_id'=>draft['id'],
      'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'compare')
    assert_equal 'completed',comparison['status']
    assert_equal 13000,comparison.dig('baseline','details').find { |d| d['id']=='net' }['assessed_minor']
    assert_equal 10000,comparison.dig('proposed','details').find { |d| d['id']=='net' }['assessed_minor']
    assert_equal 2,CommercialRate.find_by!(configuration_id:base.external_id,external_id:'rate_rebate_rate').numerator
    assert_equal 1,CommercialRate.find_by!(configuration_id:draft['id'],external_id:'rate_rebate_rate').numerator
  end
  def test_correction_pending_and_confirmed_scenarios_preserve_prior_statement
    cases={'correction'=>['compensation',330000], 'pending_payment'=>['payable',230000], 'confirmed_payment'=>['remaining_after_payment',180000]}
    cases.each do |scenario,(output,expected)|
      prior=@workbench.medallion.get!('advisor',scenario,'statement',"#{scenario}-oct2-statement")
      assert_equal '230000',prior.payload['balance_minor']
      result=@workbench.medallion.evaluate_case({'case_id'=>'advisor','scenario_id'=>scenario,'policy_id'=>"#{scenario}-policy-v1",'knowledge_cutoff'=>'2026-10-03T23:00:00Z'},"#{scenario}-later")
      assert_equal 'completed',result['status']
      assert_equal expected,result['result']['details'].find { |d| d['id']==output }['assessed_minor']
      assert_equal '230000',prior.reload.payload['balance_minor']
    end
  end
  def test_two_approved_bonuses_are_distinct_inputs_and_replay_once
    p=@workbench.medallion.policy!('advisor','baseline','advisor-policy-v1')
    2.times do |i|
      event={'id'=>"bonus-#{i}",'revision'=>1,'kind'=>'compensation_entitlement','amount_minor'=>10000,'currency'=>'USD',
        'debtor_id'=>'firm-demo','creditor_id'=>'advisor-demo','subject_id'=>'advisor-demo','economic_date'=>'2026-09-15',
        'posting_period'=>'2026-10','policy_id'=>p.external_id,'event_policy_id'=>'event-compensation_entitlement-outside','reason'=>'Approved bonus'}
      args={'case_id'=>'advisor','event'=>event}
      saved=@finance.medallion.submit_event(args,"event-#{i}")
      assert_equal saved,@finance.medallion.submit_event(args,"event-#{i}")
      @finance.medallion.review_event({'case_id'=>'advisor','event_id'=>event['id'],'revision'=>1,'expected_hash'=>saved['hash'],'decision'=>'approved'},"review-#{i}")
    end
    cutoff=(Time.current+60).utc.iso8601(6)
    result=@workbench.medallion.evaluate_case({'case_id'=>'advisor','policy_id'=>'advisor-policy-v1','knowledge_cutoff'=>cutoff},'two-bonuses')
    assert_equal 'completed',result['status']
    assert_equal 350000,result['result']['details'].find { |d| d['id']=='compensation' }['assessed_minor']
    facts=result['result']['bindings'].select { |b| b.to_s.include?('event:') }
    refute_empty facts
  end
  def test_ria_payment_application_and_reversal_preserve_sealed_statement
    run=@workbench.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'run')
    assert_equal 'completed',run['status']
    payment={'id'=>'receipt-1','revision'=>1,'amount_minor'=>5000,'currency'=>'USD','debtor_id'=>'ria-harbor','creditor_id'=>'firm-demo','status'=>'confirmed','observed_at'=>'2026-10-02T22:00:00Z'}
    @finance.medallion.record_payment({'case_id'=>'ria','payment'=>payment},'payment')
    changed=payment.merge('revision'=>2)
    assert_equal 'SOURCE_CONFLICT',assert_raises(Economics::Error) { @finance.medallion.record_payment({'case_id'=>'ria','payment'=>changed},'payment-new-revision') }.code
    args={'case_id'=>'ria','payment_id'=>'receipt-1','payment_revision'=>1,'run_id'=>run['id'],'output_id'=>'net','amount_minor'=>5000,'posting_period'=>'2026-10','reason'=>'Allocate payment'}
    before=Time.current.iso8601(6)
    app=@finance.medallion.apply_payment(args,'apply')
    rerun=@workbench.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'rerun')
    current=@workbench.medallion.get!('ria','baseline','run',rerun['id'])
    assert_equal '8000',@workbench.medallion.projected_statement('ria','baseline',current)['balance_minor']
    assert_equal '13000',@workbench.medallion.projected_statement('ria','baseline',current,as_of:before)['balance_minor']
    over=args.merge('run_id'=>rerun['id'],'amount_minor'=>9000)
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { @finance.medallion.apply_payment(over,'over') }.code
    sealed=@finance.medallion.seal_statement({'case_id'=>'ria','run_id'=>rerun['id'],'posting_period'=>'2026-10','reason'=>'Retain preview'},'seal')
    assert_equal '8000',sealed.dig('statement','balance_minor')
    @finance.medallion.reverse_application({'case_id'=>'ria','application_id'=>app['id'],'posting_period'=>'2026-10','reason'=>'Correct allocation'},'reverse')
    row=@workbench.medallion.get!('ria','baseline','statement',sealed['id'])
    assert_equal '8000',row.payload['balance_minor']
    assert_equal '13000',@workbench.medallion.projected_statement('ria','baseline',@workbench.medallion.get!('ria','baseline','run',run['id']))['balance_minor']
  end
end
