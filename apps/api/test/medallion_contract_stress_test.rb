ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class MedallionContractStressTest < Minitest::Test
  def setup
    SyntheticReset.call
    @operator=Workbench.new
    @operator.seed!
    @operator.medallion.bootstrap({},'stress-bootstrap')
    @finance=Workbench.new(role:'finance')
    @legal=Workbench.new(role:'legal')
  end

  def schema(query,role='ria')
    WorkbenchSchema.execute(query,context:{workbench:Workbench.new(role:role)}).to_h
  end
  def denied(query,role='ria')
    result=schema(query,role)
    assert result['errors']&.any? { |e| e.dig('extensions','code')=='FORBIDDEN' }, result.inspect
  end
  def policy
    @operator.medallion.policy!('ria','baseline','ria-policy-v1')
  end
  def draft(key='draft')
    @operator.medallion.save_policy({'case_id'=>'ria','base_id'=>policy.external_id,'expected_base_hash'=>policy.payload_hash,
      'policy'=>policy.payload['policy'].merge('version'=>key),'reason'=>'Synthetic stress proposal'},key)
  end
  def event
    {'id'=>'stress-event','revision'=>1,'kind'=>'one_time_credit','amount_minor'=>3000,'currency'=>'USD',
      'debtor_id'=>'firm-demo','creditor_id'=>'ria-harbor','subject_id'=>'ria-harbor','reason'=>'Synthetic service credit',
      'economic_date'=>'2026-09-30','posting_period'=>'2026-10','policy_id'=>'ria-policy-v1','event_policy_id'=>'event-one_time_credit-service_credit'}
  end
  def assert_code(code)
    assert_equal code,assert_raises(Economics::Error) { yield }.code
  end
  def test_each_legacy_field_is_forbidden_for_ria
    ['workbench','collections','entitlementLedger','productWorkspace(workspace:"internal")',
     'reconciliation(periodStart:"2026-11-01",periodEndExclusive:"2026-12-01")',
     'run(id:"not-a-run"){id}','reviewPacket(runId:"not-a-run")',
     'brokerBook(brokerId:"broker-alex"){id}'].each { |field| denied("{ #{field} }") }
    out=schema('mutation { workbenchCommand(action:PROJECT,input:{},idempotencyKey:"x"){data errors{code}} }')
    assert_equal 'FORBIDDEN',out.dig('data','workbenchCommand','errors',0,'code')
  end
  def test_external_case_scenario_and_raw_run_are_scoped
    run=@operator.medallion.evaluate_case({'case_id'=>'advisor','policy_id'=>'advisor-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'advisor-run')
    denied('{medallionWorkspace(workspace:"advisor",caseId:"advisor")}')
    denied('{medallionWorkspace(workspace:"internal",caseId:"ria")}')
    denied("{medallionWorkspace(workspace:\"ria\",caseId:\"advisor\",runId:\"#{run['id']}\")}")
    denied("{run(id:\"#{run['id']}\"){id}}")
    @operator.medallion.store!('ria','private-scenario','artifact',id:'private-artifact',status:'retained',payload:{'secret'=>'synthetic-restricted'},bytes:'synthetic-fixture')
    denied('{medallionWorkspace(workspace:"ria",caseId:"ria",scenarioId:"private-scenario")}')
    denied('{medallionWorkspace(workspace:"advisor",caseId:"advisor",scenarioId:"private-scenario")}', 'advisor')
  end
  def test_changed_revision_even_same_amount_invalidates_reviewed_source
    proposed=draft
    comparison=@operator.medallion.compare({'case_id'=>'ria','baseline_policy_id'=>policy.external_id,'proposed_policy_id'=>proposed['id'],'knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'compare')
    ref={'system'=>'mock_clm','document_id'=>'stress-doc','version'=>'v1','status'=>'reviewed_for_demo'}
    input={'case_id'=>'ria','policy_id'=>proposed['id'],'comparison_id'=>comparison['id'],'document_ref'=>ref,'decision'=>'approved_for_demo'}
    @legal.medallion.review_policy(input,'legal-review'); @finance.medallion.review_policy(input,'finance-review')
    old=@operator.medallion.source('ria','baseline','fact').where("payload->>'name' = ?",'receipt').first
    @operator.medallion.store!('ria','baseline','fact',id:old.external_id,revision:old.revision+1,status:'accepted',payload:old.payload,recorded_at:Time.iso8601('2026-10-02T22:00:00Z'))
    assert_code('HASH_CHANGED') { @finance.medallion.publish({'case_id'=>'ria','policy_id'=>proposed['id'],'comparison_id'=>comparison['id'],'effective_from'=>'2026-10-03'},'publish') }
  end
  def test_bad_graphs_fail_validation
    graph=Economics::Canonical.copy(policy.payload['policy'])
    unsupported=Economics::Canonical.copy(graph); unsupported['nodes'].first['op']='arbitrary_code'
    assert_raises(Economics::Error) { Economics::Engine.new.validate(policy:unsupported) }
    cyclic={'version'=>'cycle','nodes'=>[{'id'=>'a','op'=>'add','inputs'=>['a'],'unit'=>'USD_minor','basis'=>'assessed','role'=>'terminal'}]}
    assert_raises(Economics::Error) { Economics::Engine.new.validate(policy:cyclic) }
    mismatched={'version'=>'units','nodes'=>[{'id'=>'a','op'=>'literal','value'=>'1','unit'=>'scalar','basis'=>'scalar','role'=>'intermediate'},{'id'=>'b','op'=>'add','inputs'=>['a'],'unit'=>'USD_minor','basis'=>'assessed','role'=>'terminal'}]}
    assert_raises(Economics::Error) { Economics::Engine.new.validate(policy:mismatched) }
  end
  def test_duplicate_events_and_forged_approval_time
    first=@operator.medallion.submit_event({'case_id'=>'ria','event'=>event},'submit-a')
    same=@finance.medallion.submit_event({'case_id'=>'ria','event'=>event},'submit-b')
    assert_equal first['hash'],same['hash']
    assert_code('SOURCE_CONFLICT') { @finance.medallion.submit_event({'case_id'=>'ria','event'=>event.merge('amount_minor'=>4000)},'changed') }
    before=Time.current
    @finance.medallion.review_event({'case_id'=>'ria','event_id'=>first['id'],'revision'=>1,'expected_hash'=>first['hash'],'decision'=>'approved','approved_at'=>'2026-10-03T00:00:00Z'},'review-event')
    review=@finance.medallion.source('ria','baseline','event_review').last
    assert_operator review.recorded_at,:>=,before-1
    assert_operator review.recorded_at,:>,Time.iso8601('2026-10-03T00:00:00Z')
  end
  def test_approved_service_credit_is_known_only_after_review
    submitted=@finance.medallion.submit_event({'case_id'=>'ria','event'=>event},'credit-submit')
    before=Time.current.iso8601(6)
    @finance.medallion.review_event({'case_id'=>'ria','event_id'=>submitted['id'],'revision'=>1,'expected_hash'=>submitted['hash'],'decision'=>'approved'},'credit-review')
    early=@operator.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>before},'credit-before')
    later=@operator.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>Time.current.iso8601(6)},'credit-after')
    selected=->(r) { r.fetch('result').fetch('details').find { |d| d['id']=='net' }.fetch('assessed_minor') }
    assert_equal 13000,selected.call(early)
    assert_equal 10000,selected.call(later)
  end
  def test_pending_payment_cannot_apply
    run=@operator.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'},'payment-run')
    pay={'id'=>'pending-pay','revision'=>1,'amount_minor'=>1000,'currency'=>'USD','debtor_id'=>'ria-harbor','creditor_id'=>'firm-demo','status'=>'pending','observed_at'=>'2026-10-02T22:00:00Z'}
    @finance.medallion.record_payment({'case_id'=>'ria','payment'=>pay},'pending')
    assert_code('UNRESOLVED_MAPPING') { @finance.medallion.apply_payment({'case_id'=>'ria','payment_id'=>'pending-pay','payment_revision'=>1,'run_id'=>run['id'],'output_id'=>'net','amount_minor'=>1000,'posting_period'=>'2026-10','reason'=>'Do not apply pending evidence'},'apply') }
  end
end
