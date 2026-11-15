ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
class ProductWorkspaceTest < Minitest::Test
  def setup
    SyntheticReset.call
    @operator=Workbench.new; @operator.seed!
    @finance=Workbench.new(role:'finance'); @legal=Workbench.new(role:'legal')
  end
  def workspace(service=@operator, **args)
    service.product_workspace(workspace:'internal',broker_id:'broker-alex',**args)
  end
  def proposal(effective='2026-11-14')
    base=workspace['configuration']; rates=Marshal.load(Marshal.dump(base['rates']))
    rates.find { |r| r['kind']=='promotion' }['numerator']=87
    @operator.save_terms_proposal({'broker_id'=>'broker-alex','base_configuration_id'=>base['id'],'expected_base_hash'=>base['hash'],
      'effective_from'=>effective,'rates'=>rates,'reason'=>'Synthetic revised terms'},'save')
  end
  def compare(p, example='current_book')
    @operator.compare_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'example_id'=>example},"compare-#{example}")
  end
  def review(service,p,c,version='v1',key=nil)
    service.review_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash'],
      'document_ref'=>{'system'=>'mock_clm','document_id'=>'doc-alex','version'=>version,'status'=>'reviewed_for_demo'},'decision'=>'approved_for_demo'},key || service.role)
  end
  def schedule(p,c,key='schedule')
    @finance.schedule_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>p['hash'],'comparison_hash'=>c['hash']},key)
  end
  def test_product_workspace_preserves_money_and_isolation
    w=workspace
    assert_equal 'product-v1',w['schema_version']; assert_equal 175000,w['earnings']['earned_minor']
    assert_equal 100000,w['earnings']['coverage_minor']; assert_equal 75000,w['earnings']['incremental_minor']
    assert_equal %w[billing-line-cedar-a billing-line-cedar-b],w['earnings']['lines'].find { |l| l['customer_id']=='customer-cedar' }['billing_line_ids'].sort
    broker=Workbench.new(role:'advisor').product_workspace(workspace:'broker')
    refute broker.key?('proposals'); refute broker.key?('configuration')
    assert_raises(Economics::Error) { Workbench.new(role:'advisor').product_workspace(workspace:'internal') }
    assert_raises(Economics::Error) { Workbench.new(role:'advisor').product_workspace(workspace:'broker',broker_id:'broker-jordan') }
    assert_equal 'blocked',workspace(@operator,business_date:'2026-11-16')['earnings']['status']
  end
  def test_review_schedule_and_effective_date
    p=proposal; c=compare(p)
    assert_equal 2000,c['delta_minor']; assert_equal true,c['hypothetical']
    review(@finance,p,c)
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) { schedule(p,c) }.code
    review(@legal,p,c,'other')
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error) { schedule(p,c,'different-doc') }.code
    review(@legal,p,c,'v1','legal-match')
    schedule(p,c,'approved')
    assert_equal p['base_configuration_id'],workspace['configuration']['id']
    assert_equal p['configuration_id'],workspace(@operator,business_date:'2026-11-14')['configuration']['id']
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { schedule(p,c,'again') }.code
  end
  def test_signup_window_blocks_missing_and_future_is_hypothetical
    base=workspace['configuration']; rates=Marshal.load(Marshal.dump(base['rates']))
    rates << {'id'=>'signup-promo','broker_id'=>'broker-alex','component'=>'advisor_share','kind'=>'targeted_promotion','name'=>'Welcome share',
      'numerator'=>95,'denominator'=>100,'starts_on'=>'2026-11-01','ends_on'=>nil,'selector'=>{'product_type'=>'planning'},'signup_within_days'=>7,'priority'=>5}
    p=@operator.save_terms_proposal({'broker_id'=>'broker-alex','base_configuration_id'=>base['id'],'expected_base_hash'=>base['hash'],
      'effective_from'=>'2026-11-14','rates'=>rates,'reason'=>'Welcome example'},'welcome')
    c=compare(p); assert_equal 'blocked',c.dig('proposed','status'); assert_nil c['delta_minor']
    assert_equal 'BLOCKED_REVIEW',assert_raises(Economics::Error) { review(@finance,p,c) }.code
    future=compare(p,'future_signup_example'); assert_equal true,future['hypothetical']; assert_equal '2026-11-16',future['business_date']
    assert_equal 95000,future.dig('proposed','earned_minor')
  end
  def test_stale_hash_and_sql_overlap_constraint
    p=proposal
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { @operator.compare_terms_proposal({'proposal_id'=>p['id'],'expected_hash'=>'wrong','example_id'=>'current_book'},'bad') }.code
    rate=CommercialRate.first
    assert_raises(ActiveRecord::StatementInvalid) do
      CommercialRate.create!(rate.attributes.except('id').merge('external_id'=>'overlap'))
    end
  end
  def test_future_example_is_independent_of_incomplete_current_source
    p=proposal
    @operator.write!('snapshot',@operator.snapshot.merge('id'=>'incomplete-source','complete'=>false))
    c=compare(p,'future_signup_example')
    assert_equal 'completed',c.dig('baseline','status')
    assert_equal 'completed',c.dig('proposed','status')
  end
  def test_source_change_requires_fresh_comparison_even_with_same_amounts
    p=proposal; c=compare(p); review(@finance,p,c); review(@legal,p,c)
    current=@operator.snapshot
    @operator.write!('snapshot',current.merge('id'=>'same-amounts-new-source'))
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { schedule(p,c) }.code
    assert_empty @operator.records('commercial_schedule')
  end
  def test_future_example_uses_proposal_date_and_binds_inputs
    base=workspace['configuration']; rates=Marshal.load(Marshal.dump(base['rates']))
    rates.each { |r| r['ends_on']=nil if r['kind']=='standard' }
    p=@operator.save_terms_proposal({'broker_id'=>'broker-alex','base_configuration_id'=>base['id'],'expected_base_hash'=>base['hash'],
      'effective_from'=>'2026-12-10','rates'=>rates,'reason'=>'December example'},'december')
    c=compare(p,'future_signup_example')
    assert_equal '2026-12-10',c['business_date']
    assert_equal '2026-12-10',c.dig('proposed','input_manifest','business_date')
    assert_equal 'future-signup-example-v1',c.dig('proposed','input_manifest','template')
    assert_equal 64,c.dig('proposed','input_manifest','snapshot_hash').length
    assert_equal 'blocked',c.dig('baseline','status') # The retained baseline expires in November.
    assert_equal 'completed',c.dig('proposed','status')
  end
  def test_standard_must_cover_first_effective_day
    base=workspace['configuration']; rates=Marshal.load(Marshal.dump(base['rates']))
    rates.find { |r| r['kind']=='standard' }['ends_on']='2026-11-14'
    error=assert_raises(Economics::Error) do
      @operator.save_terms_proposal({'broker_id'=>'broker-alex','base_configuration_id'=>base['id'],'expected_base_hash'=>base['hash'],
        'effective_from'=>'2026-11-14','rates'=>rates,'reason'=>'Boundary example'},'boundary')
    end
    assert_equal 'INCOMPLETE_POLICY',error.code
  end
  def test_graphql_uses_decimal_strings
    query='{ productWorkspace(workspace:"broker") }'
    out=WorkbenchSchema.execute(query,context:{workbench:Workbench.new(role:'advisor')}).to_h
    assert_equal '175000',out.dig('data','productWorkspace','earnings','earned_minor')
  end
end
