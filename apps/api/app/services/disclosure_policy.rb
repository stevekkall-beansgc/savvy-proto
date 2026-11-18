# Constructs bounded graph policies; no commercial arithmetic is performed here.
class DisclosurePolicy
  START='2027-02-01'.freeze
  FINISH='2027-03-01'.freeze
  SUBJECT='disclosure-alder-household'.freeze
  def self.build(fields, version:)
    allowed=%w[basis cadence annual_rate minimum_minor fixed_amount_minor optional_service hourly_rate_minor optional_amount_minor service_mode]
    fail! unless fields.is_a?(Hash) && (fields.keys-allowed).empty?
    basis=fields['basis']; cadence=fields['cadence']
    if basis!='ending_value' || cadence!='monthly'
      fail! unless fields['minimum_minor'].nil?
      alternative=case [basis,cadence]
        when ['ending_value','quarterly'] then 'quarterly'
        when ['average_daily_balance','monthly'] then 'average_daily_balance'
        when ['net_worth','monthly'] then 'net_worth'
        when ['fixed','monthly'] then 'fixed'
        when ['hourly','monthly'] then 'hourly'
        when ['optional_service','monthly'] then 'optional_service'
        else fail!
      end
      fail! unless ['none','accepted'].include?(fields['optional_service']) && (alternative=='optional_service' ? fields['optional_service']=='accepted' : fields['optional_service']=='none')
      amount_keys={'fixed'=>'fixed_amount_minor','hourly'=>'hourly_rate_minor','optional_service'=>'optional_amount_minor'}
      %w[fixed_amount_minor hourly_rate_minor optional_amount_minor].each { |key| fail! if fields[key] && amount_keys[alternative]!=key }
      fail! if fields['service_mode'] && alternative!='fixed'
      params={}; params['annual_rate']=fields['annual_rate'] if fields['annual_rate']
      %w[fixed_amount_minor hourly_rate_minor optional_amount_minor service_mode].each { |key| params[key]=fields[key] unless fields[key].nil? }
      return DisclosureAlternatives.graph(alternative,version:version,fields:params)
    end
    fail! unless fields['optional_service']=='none' && fields['hourly_rate_minor'].nil? && fields['optional_amount_minor'].nil? && fields['service_mode'].nil?
    rate=fields['annual_rate']
    fail! unless rate.is_a?(String) && rate.match?(/\A\d+(?:\/[1-9]\d*)?\z/) && rate.length<=40 && Rational(rate).between?(0,1)
    minimum=fields['minimum_minor']
    fail! unless minimum.nil? || (minimum.is_a?(Integer) && minimum.between?(0,10**15))
    fail! unless fields['fixed_amount_minor'].nil?
    n=[]
    node=lambda do |id,op,unit,basis,extra={}|
      n << {'id'=>id,'op'=>op,'unit'=>unit,'basis'=>basis,'role'=>'intermediate'}.merge(extra)
    end
    %w[a_eligible a_private b_eligible b_held_away].each { |key| node.call(key,'fact','USD_minor','source_reported',{'key'=>key}) }
    holdings=%w[a_eligible a_private b_eligible b_held_away]
    node.call('reported','add','USD_minor','source_reported',{'inputs'=>holdings})
    holdings.each do |holding|
      %w[included excluded].each do |classification|
        flag="#{holding}_#{classification}"
        node.call(flag,'fact','scalar','scalar',{'key'=>flag})
        node.call("#{flag}_amount",'accrue','USD_minor','exact_accrual',{'left'=>holding,'right'=>flag})
      end
    end
    node.call('a_basis','add','USD_minor','exact_accrual',{'inputs'=>%w[a_eligible_included_amount a_private_included_amount]})
    node.call('b_basis','add','USD_minor','exact_accrual',{'inputs'=>%w[b_eligible_included_amount b_held_away_included_amount]})
    node.call('eligible','add','USD_minor','exact_accrual',{'inputs'=>%w[a_basis b_basis]})
    node.call('excluded','add','USD_minor','exact_accrual',{'inputs'=>holdings.map { |holding| "#{holding}_excluded_amount" }})
    node.call('annual_rate','literal','scalar','scalar',{'value'=>rate})
    node.call('month_factor','literal','scalar','scalar',{'value'=>'1/12'})
    node.call('monthly_rate','multiply','scalar','scalar',{'left'=>'annual_rate','right'=>'month_factor'})
    node.call('fee_exact','multiply','USD_minor','exact_accrual',{'left'=>'eligible','right'=>'monthly_rate'})
    node.call('fee_assessed','assess','USD_minor','assessed',{'input'=>'fee_exact','rounding'=>'half_up'})
    assessed='fee_assessed'
    if minimum
      node.call('minimum','literal','USD_minor','assessed',{'value'=>minimum.to_s})
      node.call('minimum_applied','max','USD_minor','assessed',{'inputs'=>%w[fee_assessed minimum]})
      assessed='minimum_applied'
    end
    output={'role'=>'terminal','output_class'=>'obligation','payer'=>SUBJECT,'payee'=>'firm-demo','currency'=>'USD'}
    node.call('charge','add','USD_minor','assessed',{'inputs'=>[assessed]}.merge(output))
    %w[a b].each { |member| node.call("line_#{member}",'allocate_by','USD_minor','assessed',{'input'=>'charge','weights'=>{'disclosure-alder-a'=>'a_basis','disclosure-alder-b'=>'b_basis'},'recipient'=>"disclosure-alder-#{member}"}.merge(output)) }
    graph={'version'=>version,'nodes'=>n}
    Economics::Engine.new.validate(policy:graph)
    graph
  rescue ArgumentError, ZeroDivisionError
    fail!
  end
  def self.fail!
    raise Economics::Error.new('UNSUPPORTED_MECHANISM','Unsupported disclosure policy fields or values')
  end
end
