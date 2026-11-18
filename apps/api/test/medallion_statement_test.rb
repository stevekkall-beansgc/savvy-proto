ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
class MedallionStatementTest < Minitest::Test
  OCT2='2026-10-02T23:00:00Z'
  OCT3='2026-10-03T23:00:00Z'
  def setup
    SyntheticReset.call
    @operator=Workbench.new; @operator.seed!; @operator.medallion.bootstrap({},'bootstrap')
    @finance=Workbench.new(role:'finance')
  end
  def scenario_run(scenario, case_id)
    @operator.medallion.evaluate_case({'case_id'=>case_id,'scenario_id'=>scenario,'policy_id'=>"#{scenario}-policy-v1",'knowledge_cutoff'=>OCT3},"run-#{scenario}")
  end
  def row(case_id,scenario,result)
    @operator.medallion.get!(case_id,scenario,'run',result.fetch('id'))
  end
  def test_historical_statements_reconcile_adjustments_and_keep_prior_unchanged
    cases={'bonus_inside'=>['advisor','230000',{'bonus_guarantee'=>'10000','topup'=>'-10000'}],
      'bonus_outside'=>['advisor','240000',{'bonus_outside'=>'10000'}],
      'service_credit'=>['ria','10000',{'service_credit'=>'-3000'}]}
    cases.each do |scenario,(case_id,balance,expected)|
      prior=@operator.medallion.get!(case_id,scenario,'statement',"#{scenario}-oct2-statement")
      retained=prior.payload.deep_dup
      result=scenario_run(scenario,case_id); assert_equal 'completed',result['status']
      statement=@operator.medallion.projected_statement(case_id,scenario,row(case_id,scenario,result),as_of:OCT3)
      assert_equal(case_id=='ria' ? '13000' : '230000',statement['opening_balance_minor'])
      assert_equal balance,statement['balance_minor']
      changes=statement['lines'].select { |x| x['economic_key'] }.to_h { |x| [x['economic_key'],x['signed_minor']] }
      expected.each { |key,value| assert_equal value,changes[key],"#{scenario}: #{changes.inspect}" }
      assert_equal retained,prior.reload.payload
      assert statement['lines'].all? { |line| line['effect']=='opening' || line['run_id'] && line['detail_refs'].is_a?(Array) }
    end
  end
  def test_missing_receipt_does_not_become_zero_statement_balance
    result=@operator.medallion.evaluate_case({'case_id'=>'ria','policy_id'=>'ria-policy-v1','knowledge_cutoff'=>'2026-10-01T23:00:00Z'},'missing-receipt')
    refute_equal 'completed',result['status']
    error=assert_raises(Economics::Error) { @operator.medallion.projected_statement('ria','baseline',row('ria','baseline',result)) }
    assert_equal 'INCOMPLETE_SOURCE',error.code
    details=result['result']['details']
    assert_equal 25000,details.find { |detail| detail['id']=='charge' }['assessed_minor']
    refute details.any? { |detail| detail['id']=='net' }
  end
  def test_statement_component_refs_resolve_to_policy_and_source_evidence
    result=scenario_run('bonus_outside','advisor');run=row('advisor','bonus_outside',result)
    statement=@operator.medallion.projected_statement('advisor','bonus_outside',run,as_of:OCT3)
    line=statement['lines'].find { |item| item['economic_key']=='bonus_outside' }
    refute_nil line
    details=run.payload.fetch('result').fetch('details').index_by { |detail| detail['id'] }
    detail=details.fetch(line.fetch('detail_refs').first)
    assert_equal 'bonus_outside-event',detail.fetch('source_refs').find { |source| source['id']=='bonus_outside-event' }.fetch('id')
    policy=@operator.medallion.get!('advisor','bonus_outside','policy',run.payload.fetch('policy_id'))
    assert_equal policy.payload_hash,run.payload.fetch('policy_hash')
    refute_empty run.payload.fetch('input_manifest').fetch('source_evidence')
  end
  def test_credit_larger_than_bill_preserves_signed_credit_balance
    base=@operator.medallion.policy!('ria','baseline','ria-policy-v1')
    draft=@operator.medallion.save_policy({'case_id'=>'ria','base_id'=>base.external_id,'expected_base_hash'=>base.payload_hash,'policy'=>base.payload['policy'],
      'rates'=>[{'id'=>'rate_rebate_rate','numerator'=>1,'denominator'=>1}],'reason'=>'Test credit balance'},'credit-draft')
    policy=@operator.medallion.policy!('ria','baseline',draft.fetch('id'))
    result,manifest=@operator.medallion.evaluate('ria','baseline',policy,OCT2,policy_cutoff:(Time.current+1).utc.iso8601(6))
    assert_equal 'completed',result['status']
    run=@operator.medallion.store!('ria','baseline','run',id:'synthetic-credit-run',status:'completed',payload:{'policy_id'=>policy.external_id,
      'policy_hash'=>policy.payload_hash,'knowledge_cutoff'=>OCT2,'input_manifest'=>manifest,'result'=>result,'synthetic'=>true},parent:policy)
    statement=@operator.medallion.projected_statement('ria','baseline',run)
    assert_equal 'credit_balance',statement['status'];assert_equal '-5000',statement['balance_minor']
    assert_equal ['25000','-30000'],statement['lines'].select { |l| l['effect']!='opening' && l['signed_minor']!='0' }.map { |l| l['signed_minor'] }.sort.reverse
  end
  def test_payment_application_once_reversal_and_refresh
    scenario='confirmed_payment';prior=@operator.medallion.get!('advisor',scenario,'statement',"#{scenario}-oct2-statement")
    result=scenario_run(scenario,'advisor'); run=row('advisor',scenario,result)
    statement=@operator.medallion.projected_statement('advisor',scenario,run,as_of:OCT3)
    assert_equal '230000',prior.payload['balance_minor'];assert_equal '180000',statement['balance_minor']
    payment=statement['lines'].select { |line| line['label']=='Payment applied' }
    assert_equal ['-50000'],payment.map { |line| line['signed_minor'] }
    refresh=@operator.medallion.evaluate_case({'case_id'=>'advisor','scenario_id'=>scenario,'policy_id'=>"#{scenario}-policy-v1",'knowledge_cutoff'=>OCT3},'refresh')
    again=@operator.medallion.projected_statement('advisor',scenario,row('advisor',scenario,refresh),as_of:OCT3)
    assert_equal statement['obligation_key'],again['obligation_key'];assert_equal '180000',again['balance_minor'];assert_equal 1,again['lines'].count { |line| line['label']=='Payment applied' }
    sealed=@finance.medallion.seal_statement({'case_id'=>'advisor','scenario_id'=>scenario,'run_id'=>refresh['id'],'posting_period'=>'2026-10','reason'=>'Retain payment statement'},'payment-seal')
    assert_equal '180000',sealed['statement']['balance_minor']
    app=@operator.medallion.get!('advisor',scenario,'application','fixture-confirmed-application')
    @finance.medallion.reverse_application({'case_id'=>'advisor','scenario_id'=>scenario,'application_id'=>app.external_id,'posting_period'=>'2026-11','reason'=>'Correct duplicate'},'reverse')
    after=@operator.medallion.projected_statement('advisor',scenario,row('advisor',scenario,refresh))
    assert_equal '230000',after['balance_minor'];assert_equal '230000',prior.reload.payload['balance_minor']
    assert_equal ['50000'],after['lines'].select { |line| line['label']=='Payment application reversed' }.map { |line| line['signed_minor'] }
    assert_equal '180000',@operator.medallion.get!('advisor',scenario,'statement',sealed['id']).payload['balance_minor']
  end
  def test_statement_never_displays_a_future_result_at_earlier_cutoff
    result=scenario_run('bonus_outside','advisor');run=row('advisor','bonus_outside',result)
    error=assert_raises(Economics::Error){@operator.medallion.projected_statement('advisor','bonus_outside',run,as_of:OCT2)}
    assert_includes %w[FUTURE_EVIDENCE INVALID_TIME],error.code
  end
  def test_sequential_seals_do_not_rebook_unchanged_earnings
    result=scenario_run('bonus_outside','advisor');run=row('advisor','bonus_outside',result)
    first=@finance.medallion.seal_statement({'case_id'=>'advisor','scenario_id'=>'bonus_outside','run_id'=>run.external_id,'posting_period'=>'2026-11','reason'=>'First retained statement'},'seal-first')
    second=@finance.medallion.seal_statement({'case_id'=>'advisor','scenario_id'=>'bonus_outside','run_id'=>run.external_id,'posting_period'=>'2026-12','reason'=>'Second retained statement'},'seal-second')
    assert_equal first['statement']['balance_minor'],second['statement']['balance_minor']
    assert_equal ['opening'],second['statement']['lines'].map { |line| line['effect'] }
    @finance.medallion.lock_posting_period({'case_id'=>'advisor','scenario_id'=>'bonus_outside','posting_period'=>'2026-11','reason'=>'Lock reviewed period'},'lock-period')
    error=assert_raises(Economics::Error) do
      @finance.medallion.seal_statement({'case_id'=>'advisor','scenario_id'=>'bonus_outside','run_id'=>run.external_id,'posting_period'=>'2026-11','reason'=>'Attempt locked period'},'locked-seal')
    end
    assert_equal 'PERIOD_LOCKED',error.code
  end
end
