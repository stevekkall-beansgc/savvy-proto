require 'minitest/autorun'
require_relative '../app/domains/economics/engine'
class MedallionProgramTest < Minitest::Test
  def node(id, op, unit, basis, **attrs)
    { 'id'=>id, 'op'=>op, 'unit'=>unit, 'basis'=>basis, 'role'=>'intermediate' }.merge(attrs.transform_keys(&:to_s))
  end
  def test_public_output_contract_prevents_stripping_direction_to_fake_net
    engine=Economics::Engine.new
    charge=node('charge','literal','USD_minor','assessed',value:'25000').merge('payer'=>'ria','payee'=>'firm','currency'=>'USD')
    credit=node('credit','literal','USD_minor','assessed',value:'12000').merge('payer'=>'firm','payee'=>'ria','currency'=>'USD')
    a=node('a','add','USD_minor','assessed',inputs:['charge'])
    b=node('b','add','USD_minor','assessed',inputs:['credit'])
    fake=node('fake','subtract','USD_minor','assessed',left:'a',right:'b').merge('role'=>'summary','output_class'=>'metric')
    assert_equal 'NETTING_UNAUTHORIZED',assert_raises(Economics::Error){engine.validate(policy:{'version'=>'1','nodes'=>[charge,credit,a,b,fake]})}.code
    fake['output_class']='net_balance';fake.merge!('payer'=>'ria','payee'=>'firm','currency'=>'USD')
    assert_equal 'NETTING_UNAUTHORIZED',assert_raises(Economics::Error){engine.validate(policy:{'version'=>'1','nodes'=>[charge,credit,a,b,fake]})}.code
  end
  def test_published_fixture_contracts_validate
    base=File.expand_path('../../../fixtures/medallion', __dir__)
    Dir.glob("#{base}/**/*-policy.json").sort.each { |path| assert Economics::Engine.new.validate(policy:JSON.parse(File.read(path))), path }
  end
  def test_exact_basis_and_explicit_assessment
    nodes = [node('daily','literal','USD_minor','exact_accrual',value:'1/2'),
      node('sum','add','USD_minor','exact_accrual',inputs:%w[daily daily daily]),
      node('share','literal','scalar','scalar',value:'4/5'),
      node('earned','multiply','USD_minor','exact_accrual',left:'sum',right:'share'),
      node('fee','assess','USD_minor','assessed',input:'sum',rounding:'half_up'),
      node('payout','assess','USD_minor','assessed',input:'earned',rounding:'half_up').merge('role'=>'terminal')]
    r=Economics::Engine.new.evaluate_program(policy:{'version'=>'1','nodes'=>nodes},facts:{})
    assert_equal '2/1',r['details'].find{|x|x['id']=='fee'}['value']
    assert_equal '1/1',r['terminal_outputs'].first['value']
  end
  def test_golden_programs_and_dependent_correction
    base=File.expand_path('../../../fixtures/medallion', __dir__)
    engine=Economics::Engine.new
    run=->(name, facts) { engine.evaluate_program(policy:JSON.parse(File.read("#{base}/#{name}-policy.json")),facts:facts,cutoff:'2026-10-02T23:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})['details'].to_h { |v| [v['id'],v['value']] } }
    advisor=JSON.parse(File.read("#{base}/advisor-facts.json"))
    a=run.call('advisor',advisor)
    assert_equal ['380000/1','313500/1','16500/1','330000/1','230000/1'],a.values_at('fees','share_total','topup','compensation','payable')
    assert_equal ['304000/1','9500/1','16500/1','26000/1'],a.values_at('standard_compensation','promotion_benefit','guarantee_benefit','total_benefit')
    advisor['cedar_30']['value']='401500000'
    a=run.call('advisor',advisor)
    assert_equal ['380800/1','314140/1','15860/1','330000/1','230000/1'],a.values_at('fees','share_total','topup','compensation','payable')
    b=run.call('ria',JSON.parse(File.read("#{base}/ria-facts.json")))
    assert_equal ['25000/1','12000/1','13000/1'],b.values_at('charge','rebate','net')
    assert_equal ['26000/1','1000/1','12000/1','13000/1'],b.values_at('baseline_charge','cap_benefit','rebate_benefit','total_benefit')
    assert_equal ['120000/1','90000/1','18000/1','12000/1','24000/1','18000/1','6000/1'],b.values_at('cash_assessed','cash_investor_assessed','cash_savvy','cash_network','margin_assessed','margin_funding_assessed','margin_savvy')
  end
  def test_account_usage_comes_from_measured_roster_fact
    base=File.expand_path('../../../fixtures/medallion', __dir__)
    policy=JSON.parse(File.read("#{base}/ria-policy.json"));facts=JSON.parse(File.read("#{base}/ria-facts.json"));roster=JSON.parse(File.read("#{base}/ria-account-roster.json"))
    assert_equal 30,roster.fetch('accounts').map { |a| a.fetch('id') }.uniq.size
    facts['account_months']['value']='29'
    result=Economics::Engine.new.evaluate_program(policy:policy,facts:facts,cutoff:'2026-10-02T23:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})['details'].to_h { |d| [d['id'],d['value']] }
    assert_equal ['5800/1','25800/1','25000/1'],result.values_at('usage','uncapped','charge')
  end
  def test_policy_comparisons
    base=File.expand_path('../../../fixtures/medallion', __dir__)
    engine=Economics::Engine.new
    [['rebate-50','ria-facts.json','net','10000/1'],['extra-50','ria-facts.json','net','18000/1'],['balance-pricing','ria-facts.json','net','6000/1'],['floor-3400','advisor-facts.json','payable','240000/1']].each do |name,factfile,id,expected|
      policy=JSON.parse(File.read("#{base}/comparisons/#{name}-policy.json"));facts=JSON.parse(File.read("#{base}/#{factfile}"))
      result=engine.evaluate_program(policy:policy,facts:facts,cutoff:'2026-10-02T23:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})['details'].to_h { |d| [d['id'],d['value']] }
      assert_equal expected,result[id]
    end
  end
  def test_governed_event_scenario_graphs
    base=File.expand_path('../../../fixtures/medallion/scenarios', __dir__)
    {'bonus-outside'=>['compensation','340000/1','payable','240000/1'], 'bonus-inside'=>['topup','6500/1','payable','230000/1'], 'confirmed-payment'=>['compensation','330000/1','remaining_after_payment','180000/1'], 'service-credit'=>['rebate','12000/1','current_due','10000/1']}.each do |name,(first,amount,second,remaining)|
      policy=JSON.parse(File.read("#{base}/#{name}-policy.json"));facts=JSON.parse(File.read("#{base}/#{name}-facts.json"))
      result=Economics::Engine.new.evaluate_program(policy:policy,facts:facts,cutoff:'2026-10-03T23:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})['details'].to_h { |d| [d['id'],d['value']] }
      assert_equal amount,result[first]; assert_equal remaining,result[second]
    end
  end
  def test_missing_receipt_retains_charge_and_blocks_dependent_outputs
    base=File.expand_path('../../../fixtures/medallion', __dir__)
    policy=JSON.parse(File.read("#{base}/ria-policy.json"))
    facts=JSON.parse(File.read("#{base}/ria-facts.json"));facts.delete('receipt')
    r=Economics::Engine.new.evaluate_program(policy:policy,facts:facts,cutoff:'2026-10-01T23:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})
    assert_equal 'partial',r['status']
    assert_equal '25000/1',r['details'].find { |x| x['id']=='charge' }['value']
    refute r['details'].any? { |x| x['id']=='rebate' || x['id']=='net' }
    assert_includes r['exceptions'].map { |x| x['code'] },'INCOMPLETE_SOURCE'
  end
  def test_period_rounding_and_daily_remainders
    {'1/2'=>[2,[1,1,0]],'2/5'=>[1,[1,0,0]]}.each do |daily,(expected, allocations)|
      nodes=%w[c b a].map { |id| node(id,'literal','USD_minor','exact_accrual',value:daily) }
      nodes << node('sum','add','USD_minor','exact_accrual',inputs:%w[a b c])
      nodes << node('assessed','assess','USD_minor','assessed',input:'sum',rounding:'half_up').merge('role'=>'terminal')
      %w[c b a].each { |id| nodes << node("display_#{id}",'distribute','USD_minor','assessed',inputs:%w[a b c],recipient:id).merge('role'=>'terminal') }
      result=Economics::Engine.new.evaluate_program(policy:{'version'=>'1','nodes'=>nodes},facts:{})['terminal_outputs'].to_h { |d| [d['id'],Rational(d['value']).to_i] }
      assert_equal expected,result['assessed'];assert_equal allocations,result.values_at('display_a','display_b','display_c')
    end
    assert_equal 1,Economics::Engine.round(Rational(1,2))
    assert_equal(-1,Economics::Engine.round(Rational(-1,2)))
  end
  def test_signed_allocation_conserves_and_reverses
    [-5, 5].each do |amount|
      nodes=[node('total','literal','USD_minor','assessed',value:amount)]
      %w[b a].each { |key| nodes << node(key,'allocate','USD_minor','assessed',input:'total',weights:{'b'=>'1/2','a'=>'1/2'},recipient:key).merge('role'=>'terminal') }
      outputs=Economics::Engine.new.evaluate_program(policy:{'version'=>'1','nodes'=>nodes},facts:{})['terminal_outputs'].to_h { |x| [x['id'],x['value']] }
      assert_equal(amount.negative? ? '-3/1' : '3/1',outputs['a'])
      assert_equal(amount.negative? ? '-2/1' : '2/1',outputs['b'])
    end
  end
  def test_baseline_graph_accepts_multiple_approved_events
    base=File.expand_path('../../../fixtures/medallion', __dir__)
    policy=JSON.parse(File.read("#{base}/advisor-policy.json"));facts=JSON.parse(File.read("#{base}/advisor-facts.json"))
    2.times { |i| facts["event#{i}"]={'collection'=>'approved_events','kind'=>'compensation_entitlement','group'=>'guarantee','unit'=>'USD_minor','basis'=>'assessed','value'=>'5000','economic_date'=>'2026-09-15','recorded_at'=>'2026-10-03T00:00:00Z'} }
    result=Economics::Engine.new.evaluate_program(policy:policy,facts:facts,cutoff:'2026-10-03T23:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})['details'].to_h { |d| [d['id'],d['value']] }
    assert_equal '6500/1',result['topup'];assert_equal '330000/1',result['compensation'];assert_equal '230000/1',result['payable']
    assert_equal ['314000/1','330000/1','16000/1'],result.values_at('comparison_baseline','comparison_selected','total_benefit')
  end
  def test_sum_facts_filters_period_and_preserves_independent_events
    engine=Economics::Engine.new
    n=node('bonuses','sum_facts','USD_minor','assessed',collection:'approved_events',selector:{'kind'=>'bonus','group'=>'guarantee'},allow_empty:true,period:'service').merge('role'=>'terminal')
    facts={}
    [['a','100','2026-09-10','guarantee'],['b','200','2026-09-11','guarantee'],['c','700','2026-09-12','outside'],['d','500','2026-10-01','guarantee']].each do |id,amount,day,group|
      facts[id]={'collection'=>'approved_events','kind'=>'bonus','group'=>group,'unit'=>'USD_minor','basis'=>'assessed','value'=>amount,'economic_date'=>day,'recorded_at'=>'2026-10-01T00:00:00Z'}
    end
    r=engine.evaluate_program(policy:{'version'=>'1','nodes'=>[n]},facts:facts,cutoff:'2026-10-02T00:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})
    assert_equal '300/1',r['terminal_outputs'][0]['value']; assert_equal %w[a b],r['bindings'][0]['facts']
    facts['a']['unit']='EUR_minor'
    assert_equal 'UNIT_MISMATCH',assert_raises(Economics::Error) { engine.evaluate_program(policy:{'version'=>'1','nodes'=>[n]},facts:facts,cutoff:'2026-10-02T00:00:00Z',period:{'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'}) }.code
  end
  def test_netting_requires_scoped_authority_and_opposing_directions
    charge=node('charge','literal','USD_minor','assessed',value:'25000').merge('role'=>'terminal','payer'=>'ria','payee'=>'firm','currency'=>'USD','output_class'=>'obligation')
    credit=node('credit','literal','USD_minor','assessed',value:'12000').merge('role'=>'terminal','payer'=>'firm','payee'=>'ria','currency'=>'USD','output_class'=>'obligation')
    net=node('net','net','USD_minor','assessed',left:'charge',right:'credit',authority_fact:'authority').merge('role'=>'summary','output_class'=>'net_balance','payer'=>'ria','payee'=>'firm','currency'=>'USD')
    policy={'version'=>'1','nodes'=>[charge,credit,net]};engine=Economics::Engine.new
    r=engine.evaluate_program(policy:policy,facts:{})
    assert_equal 'partial',r['status'];assert_equal %w[charge credit],r['terminal_outputs'].map { |d| d['id'] }
    authority={'status'=>'authorized','debtor'=>'ria','creditor'=>'firm','currency'=>'USD','valid_from'=>'2026-09-01','valid_to'=>'2026-10-01'}
    period={'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'}
    ['EUR','USD'].each do |currency|
      facts={'authority'=>authority.merge('currency'=>currency)}
      r=engine.evaluate_program(policy:policy,facts:facts,period:period)
      assert_equal(currency=='USD' ? 'completed' : 'partial',r['status'])
    end
    assert_equal 'partial',engine.evaluate_program(policy:policy,facts:{'authority'=>authority.merge('debtor'=>'other')},period:period)['status']
    credit['payee']='other'
    assert_equal 'NETTING_UNAUTHORIZED',assert_raises(Economics::Error){engine.evaluate_program(policy:policy,facts:{'authority'=>authority})}.code
    credit['payee']='ria'
    ctx={'tenant_id'=>'t','entity_id'=>'e','scenario'=>'fixture','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01','knowledge_cutoff'=>'2026-10-02T00:00:00Z'}
    evidence=authority.merge('id'=>'auth','revision'=>1,'tenant_id'=>'t','entity_id'=>'other','recorded_at'=>'2026-09-01T00:00:00Z','approved'=>true)
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error){engine.evaluate(policy_bundle:{'policy'=>policy,'approved'=>true,'policy_id'=>'p','policy_hash'=>'a'*64},input_manifest:{'facts'=>{'authority'=>evidence}},context:ctx)}.code
  end
  def test_open_ended_rate_binding_remains_effective_and_checks_start
    engine=Economics::Engine.new
    rate={'id'=>'rate','revision'=>1,'tenant_id'=>'t','entity_id'=>'e','recorded_at'=>'2026-09-01T00:00:00Z','approved'=>true,'valid_from'=>'2026-09-01','valid_to'=>nil,'unit'=>'scalar','basis'=>'scalar','value'=>'4/5'}
    nodes=[node('rate','fact','scalar','scalar',key:'rate'),node('balance','literal','USD_minor','exact_accrual',value:'100'),node('amount','multiply','USD_minor','exact_accrual',left:'balance',right:'rate'),node('assessed','assess','USD_minor','assessed',input:'amount',rounding:'half_up').merge('role'=>'terminal','output_class'=>'metric')]
    policy={'version'=>'1','nodes'=>nodes,'rate_rows'=>{'rate'=>rate}}
    context={'tenant_id'=>'t','entity_id'=>'e','scenario'=>'fixture','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01','knowledge_cutoff'=>'2026-10-02T00:00:00Z'}
    call=-> { engine.evaluate(policy_bundle:{'policy'=>policy,'approved'=>true,'policy_id'=>'p','policy_hash'=>'a'*64},input_manifest:{'facts'=>{}},context:context) }
    assert_equal 80,call.call['details'].find { |d| d['id']=='assessed' }['assessed_minor']
    rate['valid_from']='2026-09-02'; assert_equal 'RATE_NOT_EFFECTIVE',assert_raises(Economics::Error){call.call}.code
    rate['valid_from']='2026-09-01'; rate['valid_to']='2026-10-01'; assert_equal 80,call.call['details'].find { |d| d['id']=='assessed' }['assessed_minor']
    rate['valid_to']='2026-09-30'; assert_equal 'RATE_NOT_EFFECTIVE',assert_raises(Economics::Error){call.call}.code
    rate['valid_to']=nil
    choice=node('choice','select','scalar','scalar',date:'2026-09-15',candidates:[{'id'=>'standard','priority'=>1,'value'=>'rate'}])
    policy['nodes'].insert(1,choice); policy['nodes'].find { |n| n['id']=='amount' }['right']='choice'
    assert_equal 80,call.call['details'].find { |d| d['id']=='assessed' }['assessed_minor']
    rate['valid_from']='2026-09-16';assert_equal 'blocked',call.call['status']
  end
  def test_manifest_scope_approval_and_policy_time
    engine=Economics::Engine.new
    ctx={'tenant_id'=>'t','entity_id'=>'e','scenario'=>'fictional','service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01','knowledge_cutoff'=>'2026-10-02T00:00:00Z'}
    p={'version'=>'1','nodes'=>[node('amount','fact','USD_minor','assessed',key:'amount').merge('role'=>'terminal','output_class'=>'metric')]}
    fact={'id'=>'source','revision'=>1,'tenant_id'=>'t','entity_id'=>'e','currency'=>'USD','unit'=>'USD_minor','basis'=>'assessed','value'=>'100','recorded_at'=>'2026-10-01T00:00:00Z','approved'=>true}
    call=-> { engine.evaluate(policy_bundle:{'policy'=>p,'approved'=>true,'policy_id'=>'policy','policy_hash'=>'a'*64},input_manifest:{'facts'=>{'amount'=>fact}},context:ctx) }
    assert_equal 100,call.call['details'][0]['assessed_minor']
    fact['entity_id']='other'; assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error){call.call}.code
    fact['entity_id']='e';fact['approved']=false;assert_equal 'blocked',call.call['status']
    fact['approved']=true;fact['recorded_at']='2026-10-03T00:00:00Z';assert_equal 'blocked',call.call['status']
  end
  def test_invalid_hidden_branch_is_rejected_before_missing_fact
    nodes=[node('missing','fact','USD_minor','source_reported',key:'absent'),node('bad','surprise','USD_minor','exact_accrual')]
    assert_equal 'UNSUPPORTED_MECHANISM',assert_raises(Economics::Error){Economics::Engine.new.evaluate_program(policy:{'version'=>'1','nodes'=>nodes},facts:{})}.code
  end
  def test_cycle_and_currency_mismatch_fail
    a=node('a','add','USD_minor','assessed',inputs:['a'])
    assert_equal 'GRAPH_CYCLE',assert_raises(Economics::Error){Economics::Engine.new.evaluate_program(policy:{'version'=>'1','nodes'=>[a]},facts:{})}.code
    a=node('a','literal','EUR_minor','assessed',value:1)
    b=node('b','add','USD_minor','assessed',inputs:['a'])
    assert_equal 'UNIT_MISMATCH',assert_raises(Economics::Error){Economics::Engine.new.evaluate_program(policy:{'version'=>'1','nodes'=>[a,b]},facts:{})}.code
  end
end
