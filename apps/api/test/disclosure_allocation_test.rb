require 'minitest/autorun'
require_relative '../app/domains/economics/engine'

class DisclosureAllocationTest < Minitest::Test
  def node(id, unit, basis, value)
    {'id'=>id,'op'=>'literal','unit'=>unit,'basis'=>basis,'role'=>'intermediate','value'=>value}
  end
  def policy(amount, a, b)
    weights={'a'=>'wa','b'=>'wb'}
    nodes=[node('amount','USD_minor','assessed',amount),node('wa','USD_minor','source_reported',a),node('wb','USD_minor','source_reported',b)]
    weights.each_key { |id| nodes << {'id'=>id,'op'=>'allocate_by','unit'=>'USD_minor','basis'=>'assessed','role'=>'terminal','output_class'=>'metric','input'=>'amount','weights'=>weights,'recipient'=>id} }
    {'version'=>'allocation-test','nodes'=>nodes}
  end
  def values(p)
    Economics::Engine.new.evaluate_program(policy:p,facts:{}).fetch('terminal_outputs').to_h { |d| [d['id'],Rational(d['value']).to_i] }
  end
  def test_minimum_and_one_cent_ties_conserve_group
    assert_equal({'a'=>75000,'b'=>50000}, values(policy('125000','600','400')))
    assert_equal({'a'=>1,'b'=>0}, values(policy('1','1','1')))
    assert_equal({'a'=>-1,'b'=>0}, values(policy('-1','1','1')))
  end
  def test_invalid_weights_and_units
    ['0','-1'].each do |bad|
      p=policy('1',bad,'0')
      assert_equal 'INVALID_ALLOCATION',assert_raises(Economics::Error) { values(p) }.code
    end
    p=policy('1','1','1');p['nodes'][2]['unit']='EUR_minor'
    assert_equal 'UNIT_MISMATCH',assert_raises(Economics::Error) { values(p) }.code
    p=policy('1','1','1');p['nodes'][2]['basis']='assessed'
    assert_equal 'BASIS_MISMATCH',assert_raises(Economics::Error) { values(p) }.code
  end
end
