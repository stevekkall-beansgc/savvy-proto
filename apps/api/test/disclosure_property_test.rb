# Pure deterministic checks; no database or Rails environment required.
require 'minitest/autorun'
require_relative '../app/domains/economics/engine'
require_relative '../app/services/disclosure_sources'
require_relative '../app/services/disclosure_refunds'

class DisclosurePropertyTest < Minitest::Test
  def literal(id, value, basis='source_reported')
    {'id'=>id,'op'=>'literal','unit'=>'USD_minor','basis'=>basis,'role'=>'intermediate','value'=>value.to_s}
  end
  def allocate(amount, weights)
    ids=weights.keys.sort
    refs=ids.to_h { |id| [id,"weight_#{id}"] }
    nodes=[literal('amount',amount,'assessed')]+ids.map { |id| literal(refs[id],weights[id]) }
    nodes+=ids.map { |id| {'id'=>"out_#{id}",'op'=>'allocate_by','unit'=>'USD_minor','basis'=>'assessed','role'=>'terminal','input'=>'amount','weights'=>refs,'recipient'=>id} }
    Economics::Engine.new.evaluate_program(policy:{'version'=>'property','nodes'=>nodes},facts:{}).fetch('terminal_outputs').to_h { |o| [o['id'].delete_prefix('out_'),Rational(o['value']).to_i] }
  end
  def test_seeded_signed_allocations_conserve_and_are_order_independent
    rng=Random.new(9148)
    1000.times do
      weights=%w[a b c d].to_h { |id| [id,rng.rand(1000)] }
      weights['a']=1 if weights.values.sum.zero?
      amount=rng.rand(-100000..100000)
      portions=allocate(amount,weights)
      assert_equal amount,portions.values.sum
      assert_equal portions,allocate(amount,weights.to_a.reverse.to_h)
      assert portions.values.all? { |v| amount < 0 ? v <= 0 : v >= 0 }
    end
    assert_equal({'a'=>1,'b'=>0},allocate(1,{'a'=>1,'b'=>1}))
    [{'a'=>0,'b'=>0},{'a'=>-1,'b'=>2}].each do |weights|
      assert_equal 'INVALID_ALLOCATION',assert_raises(Economics::Error) { allocate(1,weights) }.code
    end
  end
  def test_seeded_source_revisions_and_missing_holdings
    1000.times do |i|
      a={'id'=>"a#{i}",'revision'=>1,'recorded_at'=>'2027-02-02T00:00:00Z','tenant_id'=>'t','entity_id'=>'e','currency'=>'USD','date'=>'2027-02-01','member_id'=>'a','holding_id'=>"a#{i}",'amount_minor'=>i,'eligible'=>true}
      b=a.merge('id'=>"b#{i}",'member_id'=>'b','holding_id'=>"b#{i}")
      revision=a.merge('revision'=>2,'date'=>'2027-02-02','recorded_at'=>'2027-02-03T00:00:00Z')
      args={observations:[a,b,revision],members:%w[a b],holdings:{'a'=>["a#{i}"],'b'=>["b#{i}"]},dates:['2027-02-01'],tenant_id:'t',entity_id:'e'}
      before=DisclosureSources.select(**args,cutoff:'2027-02-02T12:00:00Z')
      assert_equal 1,before.find { |row| row['id']==a['id'] }['revision']
      assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { DisclosureSources.select(**args,cutoff:'2027-02-04T00:00:00Z') }.code
      incomplete=args.merge(holdings:{'a'=>["a#{i}",'missing'],'b'=>["b#{i}"]})
      assert_equal 'INCOMPLETE_SOURCE',assert_raises(Economics::Error) { DisclosureSources.select(**incomplete,cutoff:'2027-02-02T12:00:00Z') }.code
    end
  end
  def test_seeded_refund_caps_count_credit_and_cash_independently
    rng=Random.new(7502)
    scope={'tenant_id'=>'t','entity_id'=>'e','case_id'=>'advisor','currency'=>'USD'}
    receipt=scope.merge('id'=>'r','hash'=>('a'*64),'status'=>'confirmed','payer'=>'client','payee'=>'firm','amount_minor'=>1000)
    credit=scope.merge('id'=>'c','hash'=>('b'*64),'status'=>'approved','payer'=>'firm','payee'=>'client','amount_minor'=>500)
    1000.times do |i|
      amount=rng.rand(1..600); prior_credit=rng.rand(1..600); prior_cash=rng.rand(1..1100)
      payment=scope.merge('id'=>"p#{i}",'status'=>'confirmed','payer'=>'firm','payee'=>'client','amount_minor'=>amount,'original_receipt_id'=>'r','original_receipt_hash'=>('a'*64),'credit_id'=>'c','credit_hash'=>('b'*64))
      applications=[scope.merge('payment_id'=>"credit#{i}",'credit_id'=>'c','credit_hash'=>('b'*64),'original_receipt_id'=>'other','original_receipt_hash'=>'other-hash','amount_minor'=>prior_credit),scope.merge('payment_id'=>"cash#{i}",'credit_id'=>'other','credit_hash'=>'other-hash','original_receipt_id'=>'r','original_receipt_hash'=>('a'*64),'amount_minor'=>prior_cash)]
      if prior_credit+amount>500 || prior_cash+amount>1000
        assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:payment,credit:credit,receipt:receipt,applications:applications) }.code
      else
        assert DisclosureRefunds.validate!(payment:payment,credit:credit,receipt:receipt,applications:applications)
      end
    end
  end

end
