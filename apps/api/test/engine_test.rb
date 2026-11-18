require "minitest/autorun"
require_relative "../app/domains/economics/engine"
class EngineTest < Minitest::Test
  FIXTURES = File.expand_path("../../../fixtures/synthetic", __dir__)
  def setup
    @s = JSON.parse(File.read("#{FIXTURES}/snapshot.json"))
    @p = JSON.parse(File.read("#{FIXTURES}/policy.json"))
    @e = Economics::Engine.new
  end
  def evaluate
    @e.evaluate(@s, @p, date: "2026-11-13", cutoff: "2026-11-13T23:00:00Z")
  end
  def test_legacy_request_compiles_to_one_program_including_guarantee
    @p['guarantees']=[guarantee_policy]
    calls=0
    trace=TracePoint.new(:call) { |event| calls += 1 if event.defined_class == Economics::Program && event.method_id == :run }
    result=nil
    trace.enable { result=evaluate }
    assert_equal 'completed',result['status']
    assert_equal 1,calls
  end
  def test_shared_advance_is_not_reused_and_inputs_are_unchanged
    original = Economics::Canonical.copy(@s)
    r = evaluate
    assert_equal 100000, r['lines'].sum { |l| l['coverage']['coverage_minor'] }
    assert_equal 75000, r['lines'].select { |l| l['broker_id']=='broker-alex' }.sum { |l| l['coverage']['incremental_cash_minor'] }
    assert_equal original, @s
    assert_equal r, evaluate
  end
  def test_rate_precedence_and_boundaries
    fact=@s['facts'][0].merge('broker_id'=>'broker-alex')
    assert_equal Rational(9,10), @e.select_rate(@p['rates'],fact,date:'2026-11-13',cutoff:'2026-11-13T23:00:00Z')['rate']
    fact['dimensions']['product_type']='planning'
    [['2026-11-09',Rational(4,5)],['2026-11-10',Rational(17,20)],['2026-11-20',Rational(17,20)],['2026-11-21',Rational(4,5)]].each do |date,expected|
      assert_equal expected,@e.select_rate(@p['rates'],fact,date:date,cutoff:'2026-12-01T00:00:00Z')['rate']
    end
  end
  def test_incomparable_rules_require_priority
    r=Economics::Canonical.copy(@p['rates'][2]);r.merge!('id'=>'customer-override','selector'=>{'customer_type'=>'individual'})
    @p['rates'] << r
    result=evaluate
    assert_equal 'blocked',result['status'];assert_equal [],result['lines']
    assert_includes result['exceptions'].map{|x|x['code']},'RULE_CONFLICT'
    r['priority']=2;@p['rates'][2]['priority']=1
    assert_equal 'completed',evaluate['status']
  end
  def test_precise_line_rounding_does_not_use_display_base
    @s['facts']=[@s['facts'][0].merge('eligible_minor'=>1)]
    @s['assignments']=[@s['assignments'][0].merge('weight_bps'=>5000),@s['assignments'][0].merge('id'=>'shared','broker_id'=>'broker-jordan','weight_bps'=>5000)]
    @p['rates'].each{|r|r['numerator']=r['broker_id']=='broker-alex' ? 40 : 80;r['denominator']=100}
    r=evaluate
    assert_equal [0,1], r['lines'].map{|l|l['earned_minor']}
    assert_equal 1,r['lines'].sum{|l|l['eligible_minor']}
  end
  def test_largest_remainder_is_stable
    assert_equal({'a'=>1,'b'=>1,'c'=>0}, Economics::Engine.allocate(2,{'c'=>3333,'b'=>3333,'a'=>3334}))
  end
  def test_recipient_rounding_conserves_line_total_and_cannot_overpay_base
    rng=Random.new(731)
    200.times do
      base=rng.rand(0..10000)
      first=rng.rand(0..10000)
      exact={'a'=>Rational(base*first*rng.rand(0..100),1_000_000),'b'=>Rational(base*(10000-first)*rng.rand(0..100),1_000_000)}
      rounded=Economics::Engine.round_components(exact)
      assert_equal Economics::Engine.round(exact.values.sum),rounded.values.sum
      assert_operator rounded.values.sum,:<=,base
      assert_equal rounded,Economics::Engine.round_components(exact.to_a.reverse.to_h)
    end
  end
  def test_scope_mismatch_is_rejected
    @p['entity_id']='another'
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error){evaluate}.code
  end
  def test_duplicate_facts_are_rejected
    @s['facts'] << @s['facts'][0].dup
    assert_equal 'DUPLICATE_SOURCE',assert_raises(Economics::Error){evaluate}.code
  end
  def test_selector_requirements_and_unknown_rate_operations_fail_closed
    @p['required_dimensions']=['customer_type']
    assert_equal 'INCOMPLETE_POLICY',assert_raises(Economics::Error){evaluate}.code
    @p['required_dimensions']=['customer_type','product_type']
    @p['rates'][0]['operation']='additive'
    assert_equal 'UNSUPPORTED_MECHANISM',assert_raises(Economics::Error){evaluate}.code
  end
  def test_missing_and_unmapped_dimensions_block_instead_of_zero
    @s['facts'][0]['dimensions'].delete('product_type')
    assert_equal 'MISSING_DIMENSION',evaluate['exceptions'][0]['code']
    @s['facts'][0]['dimensions']['product_type']='guessed'
    assert_equal 'UNMAPPED_DIMENSION',evaluate['exceptions'][0]['code']
  end
  def test_negative_assignment_and_duplicate_broker_are_blocked
    @s['assignments'][0]['weight_bps']=-1
    assert_equal 'INVALID_INTEGER',evaluate['exceptions'][0]['code']
    @s['assignments'][0]['weight_bps']=5000
    @s['assignments'] << @s['assignments'][0].merge('id'=>'duplicate-broker')
    assert_equal 'RULE_CONFLICT',evaluate['exceptions'][0]['code']
  end
  def test_future_fact_cannot_enter_known_at_time_run
    @s['facts'][0]['recorded_at']='2026-11-14T00:00:00Z'
    assert_equal 'blocked',evaluate['status']
    assert_equal 'FUTURE_EVIDENCE',evaluate['exceptions'][0]['code']
  end
  def test_equivalent_timestamp_offsets_compare_as_time
    @s['facts'][0]['recorded_at']='2026-11-13T18:00:00-05:00'
    assert_equal 'completed',evaluate['status']
  end
  def test_expired_and_reverse_direction_coverage_is_not_applied
    @s['grants'][0]['valid_to']='2026-11-13'
    assert_equal 0,evaluate['lines'].sum{|l|l['coverage']['coverage_minor']}
    @s['grants'][0]['valid_to']='2026-12-01';@s['grants'][0]['payer']='broker-alex';@s['grants'][0]['payee']='firm-demo'
    assert_equal 0,evaluate['lines'].sum{|l|l['coverage']['coverage_minor']}
  end
  def test_unit_coverage
    assert_equal({'billing_minor'=>20000,'coverage_minor'=>16000,'incremental_cash_minor'=>4000,'remaining_units'=>0},@e.unit_prepaid(quantity:100,unit_price_minor:200,covered_units:80))
  end
  def guarantee_policy
    @p.slice('tenant_id','entity_id','currency').merge('id'=>'floor','kind'=>'floor','aggregation'=>'sum','metric'=>'earned_minor','metric_unit'=>'USD_minor','threshold_unit'=>'USD_minor','payment_unit'=>'USD_minor','stacking'=>'exclusive','filters'=>{},'threshold'=>10000,'broker_id'=>'broker-alex','group'=>'broker','period'=>{'start'=>'2026-11-01','end_exclusive'=>'2026-12-01'})
  end
  def test_guarantee_uses_earned_not_cash_and_only_its_period_and_broker
    p=guarantee_policy
    row=@s.slice('tenant_id','entity_id','currency').merge('broker_id'=>'broker-alex','economic_date'=>'2026-11-13','earned_minor'=>7000,'cash_minor'=>100)
    r=@e.guarantee(p,[row,row.merge('broker_id'=>'other','earned_minor'=>100000),row.merge('economic_date'=>'2026-12-01')],prior_minor:1000)
    assert_equal 7000,r['measure'];assert_equal 3000,r['obligation_minor'];assert_equal 2000,r['delta_minor']
    assert_equal 0,@e.guarantee(p,[row.merge('earned_minor'=>20000)])['obligation_minor']
  end
  def test_guarantee_count_to_money_and_overlap_are_rejected
    p=guarantee_policy;p['metric_unit']='customers'
    assert_equal 'UNIT_MISMATCH',assert_raises(Economics::Error){@e.guarantee(p,[])}.code
    @p['guarantees']=[guarantee_policy,guarantee_policy.merge('id'=>'second')]
    assert_equal 'RULE_CONFLICT',assert_raises(Economics::Error){evaluate}.code
  end
  def test_incomplete_and_stale_snapshot_are_not_zero
    @s['complete']=false
    assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error){evaluate}.code
    @s['complete']=true;@s['watermark']='2026-11-12T21:00:00Z'
    assert_equal 'STALE_SOURCE',assert_raises(Economics::Error){evaluate}.code
  end
  def test_input_order_does_not_change_economic_output
    r=evaluate
    @s['facts'].reverse!;@s['assignments'].reverse!
    assert_equal r['lines'],evaluate['lines']
    assert_equal r['grant_closing_projection'],evaluate['grant_closing_projection']
  end
  def test_source_fact_is_atomic_if_one_recipient_fails
    @s['facts']=[@s['facts'][0]]
    @s['assignments']=[@s['assignments'][0].merge('weight_bps'=>5000),@s['assignments'][0].merge('id'=>'z-bad','broker_id'=>'unmapped','weight_bps'=>5000)]
    r=@e.evaluate(@s,@p,date:'2026-11-13',cutoff:'2026-11-13T23:00:00Z',allow_partial:true)
    assert_equal [],r['lines'];assert_equal 100000,r['grant_closing_projection'][0]['remaining_minor']
  end
end
