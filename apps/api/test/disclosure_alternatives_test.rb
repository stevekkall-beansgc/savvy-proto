require 'minitest/autorun'
require 'json'
require_relative '../app/domains/economics/engine'
require_relative '../app/services/disclosure_alternatives'
class DisclosureAlternativesTest < Minitest::Test
  def facts
    f={'a_eligible'=>60000000,'b_eligible'=>40000000,'q_a_eligible'=>60000000,'q_b_eligible'=>40000000,'assets'=>600000000,'liabilities'=>100000000,'fixed_amount'=>40000,'hourly_rate'=>20000,'optional_amount'=>10000}
    (1..28).each { |d| f["a_day_#{d}"]=d<=14 ? 60000000 : 70000000; f["b_day_#{d}"]=d<=14 ? 40000000 : 50000000 }
    f=f.to_h { |k,v| [k,{'value'=>v,'unit'=>'USD_minor','basis'=>'source_reported'}] }
    (1..28).each { |d| %w[a b].each { |member| f["#{member}_day_#{d}_included"]={'value'=>'1','unit'=>'scalar','basis'=>'scalar'} } }
    f['service_fraction']={'value'=>'1/2','unit'=>'scalar','basis'=>'scalar','approved'=>true}; f['approved_hours']={'value'=>'7/2','unit'=>'scalar','basis'=>'scalar','approved'=>true}
    f['election']={'value'=>'1','unit'=>'scalar','basis'=>'scalar','accepted'=>true}; f
  end
  def test_all_named_treatments_are_graph_evaluations
    expected={'average_daily_balance'=>[110000,65000,45000],'quarterly'=>[300000,180000,120000], 'onboarding'=>[50000,30000,20000], 'arrears'=>[100000,60000,40000], 'net_worth'=>[50000], 'fixed'=>[20000], 'hourly'=>[70000], 'optional_service'=>[10000]}
    expected.each do |name,values|
      result=Economics::Engine.new.evaluate_program(policy:DisclosureAlternatives.graph(name,version:'test'),facts:facts)
      assert_equal 'completed',result['status'],name
      details=result['details'].to_h { |d| [d['id'],Rational(d['value']).to_i] }
      assert_equal values, %w[charge line_a line_b].filter_map { |id| details[id] },name
    end
  end
  def test_missing_daily_observation_or_election_blocks_dependent_output
    f=facts;f.delete('a_day_3')
    assert_equal 'blocked',Economics::Engine.new.evaluate_program(policy:DisclosureAlternatives.graph('average_daily_balance',version:'x'),facts:f)['status']
    f=facts;f.delete('election')
    assert_equal 'blocked',Economics::Engine.new.evaluate_program(policy:DisclosureAlternatives.graph('optional_service',version:'x'),facts:f)['status']
  end
end
