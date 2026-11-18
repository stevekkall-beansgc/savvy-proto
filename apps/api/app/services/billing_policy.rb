# A data compiler, not a calculator. Every monetary operation is a graph node.
class BillingPolicy
  attr_reader :engine_manifest
  def self.validate!(config)
    fail! unless config.is_a?(Hash) && (config.keys-%w[version components graph allocation minimum_minor cap_minor compensation input_requirements invoice_timing purpose]).empty? && config['version'].is_a?(String) && config['version'].length.between?(1,100)
    fail! unless %w[equal balance].include?(config.fetch('allocation','equal'))
    fail! unless %w[billing earnings].include?(config.fetch('purpose','billing'))
    fail! unless %w[advance arrears].include?(config.fetch('invoice_timing','arrears'))
    if config['input_requirements']
      fail! unless config['input_requirements'].is_a?(Hash) && config['input_requirements'].keys==['balances'] && %w[daily ending opening daily_opening ending_opening none].include?(config['input_requirements']['balances'])
    end
    if config['graph']
      fail! if config['components'] || config['minimum_minor'] || config['cap_minor'] || config['compensation']
      Economics::Engine.new.validate(policy:config['graph'])
      fail! unless config['graph']['nodes'].any? { |n| n['id']==(config['purpose']=='earnings' ? 'compensation' : 'charge') }
      fail! if config['graph']['nodes'].any? { |n| n['id'].start_with?('allocation_','weight_') }
      fail! if config['graph']['nodes'].any? { |n| n.key?('explanation') && (!n['explanation'].is_a?(String) || n['explanation'].length>500) }
      fail! unless config['graph']['nodes'].find { |n| n['id']==(config['purpose']=='earnings' ? 'compensation' : 'charge') }['explanation'].to_s.length.between?(1,500)
    else
      fail! if config['input_requirements']
      components=config['components']; fail! unless components.is_a?(Array) && components.size.between?(1,20)
      fail! unless components.map { |c| c['id'] }.uniq.size==components.size
      fail! if config['purpose']=='earnings' && config['compensation']
      components.each do |component|
        fail! unless component.is_a?(Hash) && component['id'].is_a?(String) && component['id'].match?(/\A[a-z][a-z0-9_]{0,30}\z/) && %w[aum flat per_account hourly events observation earned_share].include?(component['kind'])
        fail! if component['kind']=='earned_share' && config['purpose']!='earnings'
        allowed={'aum'=>%w[id kind basis rate rates tiers day_basis period_factor valuation],'flat'=>%w[id kind amount_minor proration],'per_account'=>%w[id kind amount_minor proration],'hourly'=>%w[id kind rate_minor],'events'=>%w[id kind direction],'observation'=>%w[id kind collection selector label],'earned_share'=>%w[id kind]}.fetch(component['kind'])
        fail! unless (component.keys-allowed).empty?
        case component['kind']
        when 'aum'
          fail! unless %w[service_end prior_period_end].include?(component.fetch('valuation','service_end'))
          fail! if component['valuation']=='prior_period_end' && component.fetch('basis','daily')!='ending_value'
          fail! unless %w[daily ending_value].include?(component.fetch('basis','daily'))
          fail! unless [360,365,366].include?(component.fetch('day_basis',365))
          ratio!(component['period_factor']) if component['period_factor']
          ratio!(component['rate']) if component.key?('rate')
          fail! unless %w[rate rates tiers].count { |key| component.key?(key) }==1
          if component['rates']
            fail! if component['tiers']
            rates=component['rates']; fail! unless rates.is_a?(Array) && rates.size.between?(1,50) && rates.map { |r| r['id'] }.uniq.size==rates.size
            rates.each do |rate|
              fail! unless rate.is_a?(Hash) && (rate.keys-%w[id rate from to priority selector kind]).empty? && rate['id'].is_a?(String) && rate['id'].match?(/\A[a-zA-Z0-9_-]{1,60}\z/) && rate['priority'].is_a?(Integer) && rate['priority'].between?(-1000,1000)
              fail! if rate['kind'] && !%w[standard promotion targeted_promotion].include?(rate['kind'])
              ratio!(rate.fetch('rate')); a=rate['from'] && Date.iso8601(rate['from']); b=rate['to'] && Date.iso8601(rate['to']); fail! if a && b && a>=b
              fail! unless rate.fetch('selector',{}).is_a?(Hash) && rate.fetch('selector',{}).size<=10
              fail! if rate['kind']=='targeted_promotion' && rate.fetch('selector',{}).empty?
              fail! if %w[standard promotion].include?(rate['kind']) && rate.fetch('selector',{}).any?
            end
          end
          if component['tiers']
            tiers=component['tiers']; fail! unless tiers.is_a?(Array) && tiers.size.between?(1,20) && tiers.last['upper_minor'].nil?
            previous=0
            tiers.each_with_index do |tier,index|
              fail! unless tier.is_a?(Hash) && (tier.keys-%w[upper_minor rate]).empty?
              ratio!(tier.fetch('rate')); upper=tier['upper_minor']; fail! if upper && (!upper.is_a?(Integer) || upper<=previous || upper>10**15)
              fail! if !upper && index!=tiers.size-1
              previous=upper if upper
            end
          end
        when 'flat','per_account'
          Economics::Engine.integer!(component.fetch('amount_minor'),'component amount')
          fail! unless %w[none service_days].include?(component.fetch('proration','service_days'))
        when 'hourly' then Economics::Engine.integer!(component.fetch('rate_minor'),'hourly rate')
        when 'events' then fail! unless %w[charge credit payout].include?(component['direction'])
        when 'observation'
          fail! unless component['collection'].is_a?(String) && component['collection'].match?(/\A[a-zA-Z0-9_-]{1,100}\z/) && component.fetch('selector',{}).is_a?(Hash) && component.fetch('label',component['id']).is_a?(String)
        end
      end
      %w[minimum_minor cap_minor].each { |key| Economics::Engine.integer!(config[key],key) if config.key?(key) }
      fail! if config['minimum_minor'] && config['cap_minor'] && config['minimum_minor']>config['cap_minor']
      if config['compensation']
        c=config['compensation']; fail! unless c.is_a?(Hash) && (c.keys-%w[share floor_minor]).empty?
        ratio!(c.fetch('share')); Economics::Engine.integer!(c['floor_minor'],'compensation floor') if c['floor_minor']
      end
    end
    Economics::Canonical.copy(config).merge('invoice_timing'=>config.fetch('invoice_timing','arrears'))
  rescue KeyError,ArgumentError,TypeError
    fail!
  end
  def self.ratio!(value)
    fail! unless value.is_a?(String) && value.match?(/\A\d+(?:\/[1-9]\d*)?\z/) && value.length<=40
    fail! unless Rational(value).between?(0,10)
    fail! unless Rational(value).numerator<=10**15 && Rational(value).denominator<=10**15
    value
  end
  def self.rates(config)
    return [] if config['graph']
    specs=config['components'].flat_map do |component|
      base={'component'=>component['id'],'kind'=>'standard','selector'=>{},'unit'=>'ratio'}
      if component['rates']
        component['rates'].map { |r| base.merge('id'=>"#{component['id']}-#{r['id']}",'value'=>r['rate'],'kind'=>r['kind'] || (r.fetch('selector',{}).any? ? 'targeted_promotion' : r['priority']>0 ? 'promotion' : 'standard'),'selector'=>r.fetch('selector',{}),'from'=>r['from'],'to'=>r['to'],'priority'=>r['priority']) }
      elsif component['tiers']
        component['tiers'].each_with_index.map { |r,i| base.merge('id'=>"#{component['id']}-band-#{i}",'component'=>"#{component['id']}-band-#{i}",'value'=>r['rate']) }
      elsif component['rate']
        [base.merge('id'=>component['id'],'value'=>component['rate'])]
      elsif component['amount_minor'] || component['rate_minor']
        [base.merge('id'=>component['id'],'value'=>(component['amount_minor']||component['rate_minor']).to_s,'unit'=>component['kind']=='flat' ? 'USD_minor' : 'unit_price')]
      else [] end
    end
    specs << {'id'=>'compensation-share','component'=>'compensation-share','kind'=>'standard','selector'=>{},'unit'=>'ratio','value'=>config['compensation']['share']} if config['compensation']
    specs
  end
  def self.rate_kind(rate) = rate['kind'] || (rate.fetch('selector',{}).any? ? 'targeted_promotion' : rate['priority']>0 ? 'promotion' : 'standard')
  def self.fail! = raise(Economics::Error.new('INVALID_POLICY','Invalid typed policy configuration'))
  def self.requirements(config)
    return config['input_requirements'] if config['graph'] && config['input_requirements']
    return {'balances'=>'daily'} if config['graph']
    components=config.fetch('components'); opening=components.any? { |c| c['valuation']=='prior_period_end' }
    bases=components.select { |c| c['kind']=='aum' && c['valuation']!='prior_period_end' }.map { |c| c.fetch('basis','daily') }
    mode=bases.include?('daily') ? 'daily' : (bases.any? || config['allocation']=='balance') && !opening ? 'ending' : 'none'
    mode=mode=='none' ? 'opening' : mode+'_opening' if opening
    {'balances'=>mode}
  end
  def initialize(platform,config,manifest,a,b,billing_start,billing_end)
    @p,@config,@manifest,@a,@b,@bill_a,@bill_b=platform,config,manifest,a,b,billing_start,billing_end
    @engine_manifest=@p.copy(manifest.fetch('engine')); @nodes=[]
  end
  def node(id,op,unit,basis,extra={})
    @nodes << {'id'=>id,'op'=>op,'role'=>'intermediate','unit'=>unit,'basis'=>basis}.merge(extra); id
  end
  def literal(id,value,unit='scalar',basis='scalar') = node(id,'literal',unit,basis,{'value'=>value.is_a?(Rational) ? "#{value.numerator}/#{value.denominator}" : value})
  def sum(id,collection,selector={},unit:'USD_minor',basis:'source_reported')
    node(id,'sum_facts',unit,basis,{'collection'=>collection,'selector'=>selector,'allow_empty'=>true,'period'=>'service'})
  end
  def add(id,inputs,basis='assessed') = node(id,'add','USD_minor',basis,{'inputs'=>inputs.empty? ? [literal("#{id}_zero",0,'USD_minor',basis)] : inputs})
  def metadata(value)
    {'role'=>'terminal','output_class'=>'obligation','payer'=>earnings? ? 'firm-demo' : @manifest['subject_id'],'payee'=>earnings? ? @manifest['subject_id'] : 'firm-demo','subject'=>@manifest['subject_id'],'currency'=>'USD','explanation'=>value}
  end
  def active_days(account)
    (@a...@b).select { |d| @p.date!(account['active_from'])<=d && (!account['active_to'] || d<@p.date!(account['active_to'])) }
  end
  def earnings? = @config['purpose']=='earnings'
  def compile
    accounts=@manifest.fetch('accounts')
    if @config['graph']
      graph=@p.copy(@config['graph'])
      graph['nodes'].each do |n|
        %w[payer payee subject].each { |key| n[key]=@manifest['subject_id'] if n[key]=='$subject' }
      end
      @nodes=graph.fetch('nodes')
    else
      charges=[]; credits=[]; payouts=[]
      @config['components'].each do |component|
        id="component_#{component['id']}"; kind=component['kind']
        output=case kind
        when 'aum' then aum(component,id)
        when 'flat','per_account'
          amount=literal("#{id}_amount",component['amount_minor'],'USD_minor','exact_accrual')
          days=accounts.flat_map { |account| active_days(account) }.uniq.size
          units=if kind=='flat'
            component.fetch('proration','service_days')=='none' ? Rational(1) : Rational(days,(@bill_b-@bill_a).to_i)
          elsif component.fetch('proration','service_days')=='none'
            Rational(accounts.count { |account| account['eligible'] })
          else Rational(accounts.select { |a| a['eligible'] }.sum { |a| active_days(a).size },(@bill_b-@bill_a).to_i) end
          factor=literal("#{id}_measured_units",units)
          exact=node("#{id}_exact",'multiply','USD_minor','exact_accrual',{'left'=>amount,'right'=>factor})
          node(id,'assess','USD_minor','assessed',{'input'=>exact,'rounding'=>'half_up'})
        when 'earned_share' then sum(id,'issued_compensation',{},basis:'assessed')
        when 'hourly'
          quantity=sum("#{id}_hours",'hours',{},unit:'scalar',basis:'scalar'); @nodes.last['allow_empty']=false; rate=literal("#{id}_rate",component['rate_minor'],'USD_minor','exact_accrual')
          exact=node("#{id}_exact",'multiply','USD_minor','exact_accrual',{'left'=>quantity,'right'=>rate})
          node(id,'assess','USD_minor','assessed',{'input'=>exact,'rounding'=>'half_up'})
        when 'events' then sum(id,'events',{'direction'=>component['direction']},basis:'assessed')
        when 'observation'
          sum(id,component['collection'],component.fetch('selector',{}))
          @nodes.last.merge!('allow_empty'=>false,'role'=>'summary','output_class'=>'evidence','explanation'=>component.fetch('label',component['id']))
          id
        end
        if kind=='observation' then next
        elsif kind=='events' && component['direction']=='credit' then credits << output
        elsif kind=='events' && component['direction']=='payout' && !earnings? then payouts << output
        else charges << output end
      end
      gross=add('gross_charge',charges); selected=gross
      %w[minimum_minor cap_minor].each do |key|
        next unless @config[key]
        amount=literal(key,@config[key],'USD_minor','assessed')
        # The policy explicitly prorates a period floor/cap when a schedule splits.
        factor=literal("#{key}_fraction",Rational((@b-@a).to_i,(@bill_b-@bill_a).to_i))
        exact=literal("#{key}_exact",@config[key],'USD_minor','exact_accrual')
        scaled=node("#{key}_scaled",'multiply','USD_minor','exact_accrual',{'left'=>exact,'right'=>factor})
        assessed=node("#{key}_assessed",'assess','USD_minor','assessed',{'input'=>scaled,'rounding'=>'half_up'})
        selected=node("#{key}_applied",key=='minimum_minor' ? 'max' : 'min','USD_minor','assessed',{'inputs'=>[selected,assessed]})
      end
      if credits.any?
        credit=add('approved_credit',credits)
        selected=node('after_credit','subtract','USD_minor','assessed',{'left'=>selected,'right'=>credit})
      end
      zero=literal('billing_zero',0,'USD_minor','assessed')
      selected=node('net_charge','add','USD_minor','assessed',{'inputs'=>[selected]})
      positive=node('positive_charge','max','USD_minor','assessed',{'inputs'=>[selected,zero]})
      credit_delta=node('credit_delta','subtract','USD_minor','assessed',{'left'=>zero,'right'=>selected})
      node('credit_balance','max','USD_minor','assessed',{'inputs'=>[credit_delta,zero],'role'=>'summary','output_class'=>'obligation','payer'=>earnings? ? @manifest['subject_id'] : 'firm-demo','payee'=>earnings? ? 'firm-demo' : @manifest['subject_id'],'currency'=>'USD','explanation'=>'Excess credit carried as a separate claim'})
      node(earnings? ? 'compensation' : 'charge','add','USD_minor','assessed',{'inputs'=>[positive]}.merge(metadata('Client or platform charge under assigned terms')))
      node('pricing_benefit','subtract','USD_minor','assessed',{'left'=>gross,'right'=>selected,'role'=>'summary','output_class'=>'metric','explanation'=>'Difference between component charges and the final charge'})
      if @config['compensation'] && !earnings?
        share=literal('compensation_share',@config['compensation']['share'])
        exact=node('compensation_exact_charge','exact','USD_minor','exact_accrual',{'input'=>'charge'})
        node('compensation_exact','multiply','USD_minor','exact_accrual',{'left'=>exact,'right'=>share})
        compensation=node('compensation_assessed','assess','USD_minor','assessed',{'input'=>'compensation_exact','rounding'=>'half_up'})
        if @config['compensation']['floor_minor']
          exact_floor=literal('compensation_floor_exact',@config['compensation']['floor_minor'],'USD_minor','exact_accrual')
          fraction=literal('compensation_floor_fraction',Rational((@b-@a).to_i,(@bill_b-@bill_a).to_i))
          scaled=node('compensation_floor_scaled','multiply','USD_minor','exact_accrual',{'left'=>exact_floor,'right'=>fraction})
          floor=node('compensation_floor','assess','USD_minor','assessed',{'input'=>scaled,'rounding'=>'half_up'})
          compensation=node('compensation_with_floor','max','USD_minor','assessed',{'inputs'=>[compensation,floor]})
        end
        node('compensation','add','USD_minor','assessed',{'inputs'=>[compensation],'role'=>'summary','output_class'=>'obligation','payer'=>'firm-demo','payee'=>@p.case_id=='advisor' ? 'advisor-demo' : @manifest['subject_id'],'currency'=>'USD','explanation'=>'Compensation entitlement; no cash payment is inferred'})
      end
      if payouts.any?
        node('additional_payout','add','USD_minor','assessed',{'inputs'=>payouts,'role'=>'summary','output_class'=>'obligation','payer'=>'firm-demo','payee'=>@p.case_id=='advisor' ? 'advisor-demo' : @manifest['subject_id'],'currency'=>'USD','explanation'=>'Approved one-time payout entitlement, separate from client fees'})
      end
      graph={'version'=>@config['version'],'nodes'=>@nodes}
    end
    weights=accounts.to_h do |account|
      key=Digest::SHA256.hexdigest(account['account_id'])[0,16]
      value=if @config.fetch('allocation','equal')=='balance'
        sum("weight_#{key}",@manifest['requirements']['balances']=='opening' ? 'opening_balances' : 'balances',{'account_id'=>account['account_id']})
      else literal("weight_#{key}",1,'USD_minor','source_reported') end
      [account['account_id'],value]
    end
    accounts.each do |account|
      key=Digest::SHA256.hexdigest(account['account_id'])[0,16]
      if @nodes.any? { |n| n['id']=='credit_balance' }
        node("credit_allocation_#{key}",'allocate_by','USD_minor','assessed',{'input'=>'credit_balance','weights'=>weights,'recipient'=>account['account_id']}.merge(metadata('Conserved excess credit allocation')).merge('role'=>'intermediate'))
      end
      node("allocation_#{key}",'allocate_by','USD_minor','assessed',{'input'=>earnings? ? 'compensation' : 'charge','weights'=>weights,'recipient'=>account['account_id']}.merge(metadata('Conserved allocation of the same charge')))
    end
    Economics::Engine.new.validate(policy:graph)
    graph
  end
  def aum(component,id)
    days=component.fetch('basis','daily')=='ending_value' ? [component['valuation']=='prior_period_end' ? @a : @b-1] : (@a...@b).to_a
    targeted=component.fetch('basis','daily')=='ending_value' || component.fetch('rates',[]).any? { |r| r.fetch('selector',{}).any? }
    points=targeted ? days.flat_map { |d| @manifest['accounts'].select { |a| a['eligible'] && (component.fetch('basis','daily')=='ending_value' ? active_days(a).any? : active_days(a).include?(d)) }.map { |a| [d,a] } } : days.map { |d| [d,nil] }
    parts=points.map.with_index do |(day,account),index|
      calendar="calendar_#{day.strftime('%Y%m%d')}"
      known=@engine_manifest['facts'].values.map { |f| f['recorded_at'] }.max || '1970-01-01T00:00:00Z'
      @engine_manifest['facts'][calendar]={'id'=>calendar,'revision'=>1,'tenant_id'=>@p.w.tenant,'entity_id'=>@p.w.entity,'recorded_at'=>known,'approved'=>true,'unit'=>'scalar','basis'=>'scalar','value'=>'1','date'=>day.iso8601,'derivation'=>'ISO service calendar'}
      key="#{id}_#{index}"; selector={'eligible'=>true,'economic_date'=>day.iso8601}; selector['account_id']=account['account_id'] if account
      source=sum("#{key}_balance",component['valuation']=='prior_period_end' ? 'opening_balances' : 'balances',selector)
      exact=if component['tiers']
        rates=component['tiers'].each_with_index.map { |tier,i| {'upper'=>tier['upper_minor'],'rate'=>literal("#{key}_band_#{i}",tier['rate'])} }
        node("#{key}_tiered",'bands','USD_minor','exact_accrual',{'input'=>source,'bands'=>rates})
      else
        rate=if component['rates']
          candidates=component['rates'].map do |r|
            matches=r.fetch('selector',{}).to_h do |dimension,value|
              fact_key="dimension_#{Digest::SHA256.hexdigest(account['account_id']+dimension)[0,24]}"
              @engine_manifest['facts'][fact_key]={'id'=>fact_key,'revision'=>account['revision'],'tenant_id'=>@p.w.tenant,'entity_id'=>@p.w.entity,'recorded_at'=>account['observed_at'],'approved'=>true,'unit'=>'scalar','basis'=>'scalar','value'=>account.fetch('dimensions',{})[dimension]}
              [fact_key,value]
            end
            priority=%w[standard promotion targeted_promotion].index(self.class.rate_kind(r))*10_000+r['priority']
            {'id'=>r['id'],'priority'=>priority,'from'=>r['from'],'to'=>r['to'],'value'=>literal("#{key}_rate_#{r['id']}",r['rate']),'matches'=>matches}.compact
          end
          node("#{key}_selected_rate",'select','scalar','scalar',{'date'=>day.iso8601,'candidates'=>candidates})
        else literal("#{key}_rate",component.fetch('rate')) end
        node("#{key}_rated",'accrue','USD_minor','exact_accrual',{'left'=>source,'right'=>rate})
      end
      factor=component.fetch('basis','daily')=='daily' ? Rational(1,component.fetch('day_basis',365)) : Rational(account ? active_days(account).size : (@b-@a).to_i,(@bill_b-@bill_a).to_i)*Rational(component.fetch('period_factor','1/12'))
      scalar=literal("#{key}_calendar",factor)
      node("#{key}_exact",'multiply','USD_minor','exact_accrual',{'left'=>exact,'right'=>scalar,'component'=>component['id'],'explanation'=>component.fetch('basis','daily')=='daily' ? "Accrual for #{day}" : "Valuation as of #{component['valuation']=='prior_period_end' ? @a-1 : @b-1}",**(component.fetch('basis','daily')=='daily' ? {'interval_fact'=>calendar} : {})})
    end
    exact=add("#{id}_accrual",parts,'exact_accrual')
    node(id,'assess','USD_minor','assessed',{'input'=>exact,'rounding'=>'half_up'})
  end
end
