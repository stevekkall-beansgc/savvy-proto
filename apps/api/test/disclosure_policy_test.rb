require 'minitest/autorun'
require_relative '../app/domains/economics/engine'
require_relative '../app/services/disclosure_policy'
class DisclosurePolicyTest < Minitest::Test
  def test_policy_uses_group_minimum_once_and_allocates_by_eligible_value
    fields={'basis'=>'ending_value','cadence'=>'monthly','annual_rate'=>'3/250','minimum_minor'=>125000,'fixed_amount_minor'=>nil,'optional_service'=>'none'}
    p=DisclosurePolicy.build(fields,version:'v1')
    facts={'a_eligible'=>60000000,'a_private'=>15000000,'b_eligible'=>40000000,'b_held_away'=>10000000}.to_h { |id,value| [id,{'value'=>value,'unit'=>'USD_minor','basis'=>'source_reported'}] }
    facts.keys.each { |key| %w[included excluded].each { |flag| included=%w[a_eligible b_eligible].include?(key); facts["#{key}_#{flag}"]={'value'=>(flag=='included' ? included : !included) ? '1' : '0','unit'=>'scalar','basis'=>'scalar'} } }
    result=Economics::Engine.new.evaluate_program(policy:p,facts:facts)
    detail=result['details'].to_h { |d| [d['id'],d['value']] }
    assert_equal ['125000/1','75000/1','50000/1'],detail.values_at('charge','line_a','line_b')
    assert_equal ['125000000/1','25000000/1','100000000/1'],detail.values_at('reported','excluded','eligible')
  end
end
