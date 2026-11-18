# Named, versioned comparison graphs. All pricing and distribution remains in
# the common interpreter; the wrapper only binds authored inputs and metadata.
class DisclosureAlternatives
  NAMES=%w[average_daily_balance quarterly onboarding arrears net_worth fixed hourly optional_service].freeze
  def self.graph(name, version:, fields: {})
    raise Economics::Error.new('UNSUPPORTED_MECHANISM') unless NAMES.include?(name)
    raise Economics::Error.new('UNSUPPORTED_MECHANISM') unless fields.is_a?(Hash) && (fields.keys-%w[annual_rate fixed_amount_minor hourly_rate_minor optional_amount_minor service_mode]).empty?
    annual=fields.fetch('annual_rate',name=='net_worth' ? '3/2500' : '3/250')
    raise Economics::Error.new('INVALID_NUMBER') unless annual.is_a?(String) && annual.length<=40 && annual.match?(/\A\d+(?:\/[1-9]\d*)?\z/) && Rational(annual).between?(0,1)
    n=[]
    node=lambda { |id,op,unit,basis,extra={}| n << {'id'=>id,'op'=>op,'unit'=>unit,'basis'=>basis,'role'=>'intermediate'}.merge(extra) }
    fact=lambda { |id| node.call(id,'fact','USD_minor','source_reported',{'key'=>id}) }
    scalar=lambda { |id,value| node.call(id,'literal','scalar','scalar',{'value'=>value}) }
    if name=='average_daily_balance'
      %w[a b].each do |member|
        ids=(1..28).map { |day| "#{member}_day_#{day}" }
        ids.each do |id|
          fact.call(id)
          node.call("#{id}_included",'fact','scalar','scalar',{'key'=>"#{id}_included"})
          node.call("#{id}_eligible_amount",'accrue','USD_minor','exact_accrual',{'left'=>id,'right'=>"#{id}_included"})
        end
        node.call("#{member}_sum",'add','USD_minor','exact_accrual',{'inputs'=>ids.map { |id| "#{id}_eligible_amount" }})
      end
      scalar.call('average_factor','1/28')
      %w[a b].each { |member| node.call("#{member}_average",'multiply','USD_minor','exact_accrual',{'left'=>"#{member}_sum",'right'=>'average_factor'}) }
      node.call('basis','add','USD_minor','exact_accrual',{'inputs'=>%w[a_average b_average]})
      scalar.call('annual_rate',annual); scalar.call('period_factor','1/12')
      node.call('fee_factor','multiply','scalar','scalar',{'left'=>'annual_rate','right'=>'period_factor'})
      node.call('fee_exact','multiply','USD_minor','exact_accrual',{'left'=>'basis','right'=>'fee_factor'})
      weights={'disclosure-alder-a'=>'a_average','disclosure-alder-b'=>'b_average'}
    elsif %w[quarterly onboarding arrears].include?(name)
      account_facts=name=='quarterly' ? %w[q_a_eligible q_b_eligible] : %w[a_eligible b_eligible]
      account_facts.each { |id| fact.call(id) }
      node.call('basis','add','USD_minor','source_reported',{'inputs'=>account_facts})
      scalar.call('annual_rate',annual); scalar.call('period_factor',name=='quarterly' ? '1/4' : '1/12')
      node.call('period_rate','multiply','scalar','scalar',{'left'=>'annual_rate','right'=>'period_factor'})
      if name=='onboarding'
        node.call('fee_factor','fact','scalar','scalar',{'key'=>'service_fraction','requires'=>{'approved'=>true}})
      else
        node.call('fee_factor','literal','scalar','scalar',{'value'=>'1'})
      end
      node.call('period_fee','accrue','USD_minor','exact_accrual',{'left'=>'basis','right'=>'period_rate'})
      node.call('fee_exact','multiply','USD_minor','exact_accrual',{'left'=>'period_fee','right'=>'fee_factor'})
      weights={'disclosure-alder-a'=>account_facts[0],'disclosure-alder-b'=>account_facts[1]}
    elsif name=='net_worth'
      %w[assets liabilities].each { |id| fact.call(id) }
      node.call('basis','subtract','USD_minor','source_reported',{'left'=>'assets','right'=>'liabilities'})
      scalar.call('annual_rate',annual); scalar.call('period_factor','1/12')
      node.call('fee_factor','multiply','scalar','scalar',{'left'=>'annual_rate','right'=>'period_factor'})
      node.call('fee_exact','accrue','USD_minor','exact_accrual',{'left'=>'basis','right'=>'fee_factor'})
    else
      source=name=='hourly' ? 'hourly_rate' : name=='fixed' ? 'fixed_amount' : 'optional_amount'
      key=source+'_minor'; default={'hourly_rate_minor'=>20000,'fixed_amount_minor'=>40000,'optional_amount_minor'=>10000}.fetch(key)
      amount=fields.fetch(key,default)
      raise Economics::Error.new('INVALID_INTEGER') unless amount.is_a?(Integer) && amount.between?(0,10**15)
      node.call(source,'literal','USD_minor','source_reported',{'value'=>amount.to_s})
      if name=='optional_service'
        node.call('election','fact','scalar','scalar',{'key'=>'election','requires'=>{'accepted'=>true}})
        factor='election'
      else
        factor=name=='fixed' ? 'service_fraction' : 'approved_hours'
        if name=='fixed' && fields.fetch('service_mode','partial')=='full'
          scalar.call(factor,'1')
        else
          raise Economics::Error.new('UNSUPPORTED_MECHANISM') if name=='fixed' && fields.fetch('service_mode','partial')!='partial'
          node.call(factor,'fact','scalar','scalar',{'key'=>factor,'requires'=>{'approved'=>true}})
        end
      end
      node.call('fee_exact','accrue','USD_minor','exact_accrual',{'left'=>source,'right'=>factor})
    end
    node.call('charge','assess','USD_minor','assessed',{'input'=>'fee_exact','rounding'=>'half_up','role'=>'terminal','output_class'=>'comparison'})
    if weights
      %w[a b].each { |member| node.call("line_#{member}",'allocate_by','USD_minor','assessed',{'input'=>'charge','weights'=>weights,'recipient'=>"disclosure-alder-#{member}",'role'=>'terminal','output_class'=>'comparison'}) }
    end
    policy={'version'=>version,'nodes'=>n}; Economics::Engine.new.validate(policy:policy); policy
  end
end
