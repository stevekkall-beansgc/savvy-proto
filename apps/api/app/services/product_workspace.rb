require 'securerandom'
class ProductWorkspace
  def initialize(workbench) = @w=workbench
  def date!(v) = Economics::Engine.new.date!(v)
  def hash(v) = Economics::Canonical.hash(v)
  def rows(kind) = @w.records(kind).order(:id).map(&:payload)
  def rate_rows(config_id)
    CommercialRate.where(**@w.scope,configuration_id:config_id).order(:id).map do |r|
      { 'id'=>r.external_id,'broker_id'=>r.broker_id,'component'=>r.component,'kind'=>r.kind,'name'=>r.name,
        'numerator'=>r.numerator,'denominator'=>r.denominator,'starts_on'=>r.starts_on.iso8601,'ends_on'=>r.ends_on&.iso8601,
        'selector'=>r.selector,'signup_within_days'=>r.signup_within_days,'priority'=>r.priority }
    end
  end
  def config(id)
    c=@w.record!('commercial_configuration',id)
    full=c.merge('rates'=>rate_rows(id))
    raise Economics::Error.new('HASH_CHANGED','Configuration evidence changed') unless config_hash(full)==c['hash']
    full
  end
  def config_hash(c) = hash(c.except('hash'))
  def insert_rates(id,rates)
    rates.each do |r|
      CommercialRate.create!(**@w.scope,configuration_id:id,external_id:r.fetch('id'),broker_id:r.fetch('broker_id'),component:r.fetch('component'),
        kind:r.fetch('kind'),name:r.fetch('name'),numerator:r.fetch('numerator'),denominator:r.fetch('denominator'),starts_on:r.fetch('starts_on'),
        ends_on:r['ends_on'],selector:r.fetch('selector'),signup_within_days:r['signup_within_days'],priority:r['priority'],recorded_at:Time.current)
    end
  end
  def bootstrap!
    # Import retained policies as distinct versions. Draft versions stay drafts;
    # only the legacy active version (or initial synthetic baseline) is selectable.
    activations=@w.records('activation').order(:id).map(&:payload)
    active=activations.last&.fetch('policy_id',nil) || 'policy-v1'
    historical=(activations.map { |a| a['policy_id'] } + ['policy-v1']).uniq
    @w.records('policy').order(:id).each do |record|
      policy=record.payload
      @w.directory['brokers'].each do |broker|
        id="config-#{policy['id']}-#{broker['id']}"
        next if @w.records('commercial_configuration').exists?(external_id:id)
        rates=policy.fetch('rates').select { |r| r['broker_id']==broker['id'] }.map do |r|
          { 'id'=>r['id'],'broker_id'=>r['broker_id'],'component'=>r['component'],'kind'=>r['kind']=='override' ? 'targeted_promotion' : r['kind'],
            'name'=>r['kind']=='override' ? 'Managed service share' : r['kind'].capitalize+' share', 'numerator'=>r['numerator'],'denominator'=>r['denominator'],
            'starts_on'=>r['valid_from'],'ends_on'=>r['valid_to'],'selector'=>r['selector'],'signup_within_days'=>nil,'priority'=>r['priority'] }
        end
        next if rates.empty?
        c={'id'=>id,'broker_id'=>broker['id'],'effective_from'=>rates.map { |r| r['starts_on'] }.min,
          'status'=>policy['id']==active ? 'legacy_active' : (historical.include?(policy['id']) ? 'legacy_historical' : 'legacy_draft'),'agreement_id'=>"agreement-#{id}",
          'document_ref'=>{'system'=>'mock_clm','document_id'=>"document-#{id}",'version'=>'legacy-illustration','status'=>'illustrative'},
          'guarantees'=>policy.fetch('guarantees',[]).select { |g| g['broker_id']==broker['id'] }, 'required_dimensions'=>policy['required_dimensions'], 'allowed_dimensions'=>policy['allowed_dimensions'], 'source_policy_id'=>policy['id'],'rates'=>rates}
        c['hash']=config_hash(c)
        insert_rates(id,rates)
        @w.write!('commercial_configuration',c.except('rates'))
      end
    end
  end
  def selected(broker,date)
    date!(date)
    configs=rows('commercial_configuration').select { |c| c['broker_id']==broker }
    schedule_ids=rows('commercial_schedule').select { |s| s['broker_id']==broker && s['effective_from']<=date }.map { |s| s['configuration_id'] }
    selected=configs.select { |c| schedule_ids.include?(c['id']) }.max_by { |c| c['effective_from'] }
    selected ||= configs.select { |c| c['status']=='legacy_active' && c['effective_from']<=date }.max_by { |c| c['effective_from'] }
    raise Economics::Error.new('NOT_FOUND','No effective configuration') unless selected
    config(selected['id'])
  end
  def validate_rates!(rates,broker,allowed)
    raise Economics::Error.new('VALIDATION_ERROR','Supply one to 100 rates') unless rates.is_a?(Array) && rates.size.between?(1,100)
    ids=[]
    normalized=rates.map do |input|
      raise Economics::Error.new('VALIDATION_ERROR') unless input.is_a?(Hash)
      fields=%w[id broker_id component kind name numerator denominator starts_on ends_on selector signup_within_days priority]
      raise Economics::Error.new('UNSUPPORTED_MECHANISM') unless (input.keys-fields).empty?
      r=input.slice(*fields)
      raise Economics::Error.new('VALIDATION_ERROR','Invalid rate ID or name') unless r['id'].is_a?(String) && r['id'].match?(/\A[a-zA-Z0-9_-]{1,100}\z/) && r['name'].is_a?(String) && r['name'].strip.length.between?(1,100)
      r['name']=r['name'].strip; r['broker_id'] ||= broker; r['component'] ||= 'advisor_share'; r['selector'] ||= {}
      raise Economics::Error.new('SCOPE_MISMATCH') unless r['broker_id']==broker && r['component']=='advisor_share'
      raise Economics::Error.new('UNSUPPORTED_MECHANISM') unless %w[standard promotion targeted_promotion].include?(r['kind'])
      r['numerator']=Economics::Engine.integer!(r['numerator'],'numerator',max:1_000_000)
      r['denominator']=Economics::Engine.integer!(r['denominator'],'denominator',min:1,max:1_000_000)
      raise Economics::Error.new('INVALID_RATE') if r['numerator']>r['denominator']
      start=date!(r['starts_on']); finish=r['ends_on'] && date!(r['ends_on']); raise Economics::Error.new('INVALID_INTERVAL') if finish && finish<=start
      raise Economics::Error.new('UNSUPPORTED_DIMENSION') unless r['selector'].is_a?(Hash) && r['selector'].all? { |k,v| allowed.fetch(k,[]).include?(v) }
      raise Economics::Error.new('INVALID_SELECTOR') if r['kind']!='targeted_promotion' && (!r['selector'].empty? || r['signup_within_days'])
      raise Economics::Error.new('INVALID_SELECTOR') if r['kind']=='targeted_promotion' && r['selector'].empty? && !r['signup_within_days']
      Economics::Engine.integer!(r['signup_within_days'],'signup_within_days',min:1,max:365) unless r['signup_within_days'].nil?
      Economics::Engine.integer!(r['priority'],'priority',min:-1000,max:1000) unless r['priority'].nil?
      %w[ends_on signup_within_days priority].each { |key| r[key]=nil unless r.key?(key) }
      ids << r['id']; r
    end
    raise Economics::Error.new('DUPLICATE_SOURCE') unless ids.uniq.size==ids.size
    normalized.combination(2) do |a,b|
      next unless a['kind']==b['kind'] && (a['ends_on'].nil? || b['starts_on']<a['ends_on']) && (b['ends_on'].nil? || a['starts_on']<b['ends_on'])
      if a['kind']!='targeted_promotion'
        raise Economics::Error.new('RULE_CONFLICT','Overlapping rates')
      end
      intersect=(a['selector'].keys & b['selector'].keys).all? { |key| a['selector'][key]==b['selector'][key] }
      next unless intersect
      if (a['selector']==b['selector'] && a['signup_within_days']==b['signup_within_days']) || a['priority'].nil? || b['priority'].nil? || a['priority']==b['priority']
        raise Economics::Error.new('RULE_CONFLICT','Intersecting targeted promotions need distinct priorities and eligibility')
      end
    end
    normalized
  end
  def save(input,key)
    @w.guard!('operator','finance')
    @w.operate('save_terms_proposal',input,key) do
      broker=input.fetch('broker_id'); raise Economics::Error.new('NOT_FOUND') unless @w.directory['brokers'].any? { |b| b['id']==broker }
      day=input.fetch('effective_from'); raise Economics::Error.new('INVALID_DATE') if date!(day)<date!(Workbench::DATE)
      base=selected(broker,day)
      raise Economics::Error.new('HASH_CHANGED','Base configuration changed') unless base['id']==input['base_configuration_id'] && base['hash']==input['expected_base_hash']
      reason=@w.settlement_book.reason!(input['reason']); rates=validate_rates!(input['rates'],broker,base['allowed_dimensions'])
      unless rates.any? { |r| r['kind']=='standard' && r['starts_on']<=day && (r['ends_on'].nil? || day<r['ends_on']) }
        raise Economics::Error.new('INCOMPLETE_POLICY','A standard share must cover the effective date')
      end
      id="proposal-#{SecureRandom.uuid}"; cid="config-#{id}"
      data={'id'=>id,'configuration_id'=>cid,'broker_id'=>broker,'base_configuration_id'=>base['id'],'base_hash'=>base['hash'],'effective_from'=>day,'reason'=>reason,'rates'=>rates,'guarantees'=>base['guarantees'],'required_dimensions'=>base['required_dimensions'],'allowed_dimensions'=>base['allowed_dimensions']}
      data['hash']=hash(data)
      insert_rates(cid,rates); @w.write!('terms_proposal',data.except('rates'))
      data.merge('status'=>'draft','comparison'=>nil,'reviews'=>[])
    end
  end
  def proposal(id)
    p=@w.record!('terms_proposal',id)
    full=p.merge('rates'=>rate_rows(p['configuration_id']))
    raise Economics::Error.new('HASH_CHANGED','Proposal evidence changed') unless hash(full.except('hash'))==p['hash']
    full
  end
  def comparison(id,expected_hash)
    p=proposal(id); raise Economics::Error.new('HASH_CHANGED') unless p['hash']==expected_hash
    p
  end
  def evaluate_for(broker, day, override: nil, example: 'current_book')
    raise Economics::Error.new('VALIDATION_ERROR') unless %w[current_book future_signup_example].include?(example)
    if example=='current_book' && day!=Workbench::DATE
      return {'status'=>'blocked','earned_minor'=>nil,'lines'=>[],'exceptions'=>[{'code'=>'STALE_SOURCE','message'=>'Retained observations only cover 2026-11-13'}]}
    end
    if example=='future_signup_example'
      scope=@w.scope.stringify_keys.merge('currency'=>'USD'); example_day=date!(day); signup=(example_day-1).iso8601
      stamp="#{day}T20:00:00Z"
      snapshot=scope.merge('id'=>'future-signup-example-v1','source'=>'synthetic-future-example-v1','synthetic'=>true,'complete'=>true,'business_date'=>day,'watermark'=>stamp,
        'minimum_watermark'=>stamp,'recorded_at'=>stamp,
        'facts'=>[scope.merge('id'=>'future-signup-fee','revision'=>1,'customer_id'=>'future-signup-customer','service_id'=>'future-signup-service',
          'component'=>'advisor_share','eligible_minor'=>100000,'dimensions'=>{'customer_type'=>'individual','product_type'=>'planning'},
          'signup_date'=>signup,'economic_date'=>day,'observed_at'=>stamp,'recorded_at'=>stamp)],
        'assignments'=>[scope.merge('id'=>'future-signup-assignment','customer_id'=>'future-signup-customer','broker_id'=>broker,'role'=>'compensation_recipient',
          'weight_bps'=>10000,'approved'=>true,'valid_from'=>day,'valid_to'=>(example_day+1).iso8601,'recorded_at'=>stamp)], 'grants'=>[])
    else
      snapshot=@w.settlement_book.projection_snapshot(@w.snapshot,cutoff:Workbench::CUTOFF)
      # Evaluate only customers assigned to the requested broker; retain all of
      # those customers' assignments so shared allocations remain exact.
      customer_ids=snapshot['assignments'].select { |a| a['broker_id']==broker }.map { |a| a['customer_id'] }.uniq
      snapshot['facts']=snapshot['facts'].select { |f| customer_ids.include?(f['customer_id']) }
      snapshot['assignments']=snapshot['assignments'].select { |a| customer_ids.include?(a['customer_id']) }
    end
    configs=@w.directory['brokers'].map do |b|
      if override && b['id']==broker then override else selected(b['id'],day) end
    end
    primary=configs.find { |c| c['broker_id']==broker }
    policy=Economics::Canonical.copy(@w.policy).merge('required_dimensions'=>primary['required_dimensions'],'allowed_dimensions'=>primary['allowed_dimensions'],'rates'=>configs.flat_map { |c| c['rates'] },'guarantees'=>configs.flat_map { |c| c['guarantees'] }.select { |g| g.dig('period','start')<=day && day<g.dig('period','end_exclusive') })
    cutoff=example=='future_signup_example' ? "#{day}T23:00:00Z" : Workbench::CUTOFF
    begin
      result=CommercialEngine.new.evaluate(snapshot,policy,date:day,cutoff:cutoff)
    rescue Economics::Error => e
      return { 'status'=>'blocked', 'earned_minor'=>nil, 'lines'=>[],
        'exceptions'=>[e.to_h.transform_keys(&:to_s).merge('owner'=>'Demo finance operations','next_action'=>'Supply complete eligible source evidence before review')],
        'input_manifest'=>{'template'=>example=='future_signup_example' ? 'future-signup-example-v1' : 'retained-current-book', 'snapshot_hash'=>hash(snapshot),'policy_hash'=>hash(policy),'business_date'=>day}, 'guarantees'=>[] }
    end
    rate_lookup=configs.flat_map { |c| c['rates'] }.index_by { |r| [r['broker_id'],r['id']] }
    customer_names=@w.directory['customers'].to_h { |c| [c['id'],c['name']] }
    lines=result['lines'].select { |l| l['broker_id']==broker }.map do |line|
      rate=rate_lookup[[broker,line.dig('trace','winner')]]
      line.merge('customer_name'=>customer_names[line['customer_id']] || 'Hypothetical new customer',
        'rate'=>rate&.slice('id','name','kind','numerator','denominator')&.merge('reason'=>line.dig('trace','reason')))
    end
    {'status'=>result['status'],'earned_minor'=>result['status']=='completed' ? lines.sum { |l| l['earned_minor'] } : nil,
      'lines'=>lines,'exceptions'=>result['exceptions'],'input_manifest'=>{'template'=>example=='future_signup_example' ? 'future-signup-example-v1' : 'retained-current-book', 'snapshot_hash'=>result['input_hash'],'policy_hash'=>result['policy_hash'],'business_date'=>day},'guarantees'=>result['guarantees'].select { |g| g['broker_id']==broker }}
  end
  def compare(input,key)
    @w.guard!('operator','finance')
    @w.operate('compare_terms_proposal',input,key) do
      p=comparison(input.fetch('proposal_id'),input.fetch('expected_hash'))
      example=input.fetch('example_id'); raise Economics::Error.new('VALIDATION_ERROR') unless %w[current_book future_signup_example].include?(example)
      day=example=='current_book' ? Workbench::DATE : [p['effective_from'],'2026-11-16'].max
      baseline=config(p['base_configuration_id'])
      proposed={'id'=>p['configuration_id'],'broker_id'=>p['broker_id'],'rates'=>p['rates'],'guarantees'=>p['guarantees'],'required_dimensions'=>p['required_dimensions'],'allowed_dimensions'=>p['allowed_dimensions']}
      before=evaluate_for(p['broker_id'],day,override:baseline,example:example)
      after=evaluate_for(p['broker_id'],day,override:proposed,example:example)
      c={'id'=>"comparison-#{SecureRandom.uuid}",'example_id'=>example,'business_date'=>day,'hypothetical'=>example!='current_book' || p['effective_from']>day,
        'baseline_configuration_id'=>baseline['id'],'proposal_id'=>p['id'],'proposal_hash'=>p['hash'],'baseline'=>before,'proposed'=>after,
        'delta_minor'=>before['earned_minor'] && after['earned_minor'] ? after['earned_minor']-before['earned_minor'] : nil}
      c['hash']=hash(c); @w.write!('terms_comparison',c)
    end
  end
  def comparison!(p,comparison_hash)
    c=rows('terms_comparison').find { |v| v['proposal_id']==p['id'] && v['hash']==comparison_hash }
    raise Economics::Error.new('HASH_CHANGED','Comparison not found') unless c && c['proposal_hash']==p['hash'] && hash(c.except('hash'))==c['hash']
    raise Economics::Error.new('BLOCKED_REVIEW','Comparison must complete') unless c.dig('baseline','status')=='completed' && c.dig('proposed','status')=='completed'
    c
  end
  def document!(v)
    unless v.is_a?(Hash) && v.keys.sort==%w[document_id status system version] && v['system']=='mock_clm' && v['status']=='reviewed_for_demo' &&
        %w[document_id version].all? { |k| v[k].is_a?(String) && v[k].match?(/\A[a-zA-Z0-9_-]{1,100}\z/) }
      raise Economics::Error.new('VALIDATION_ERROR','Use a bounded reviewed mock CLM reference')
    end
    v
  end
  def review(input,key)
    @w.guard!('finance','legal')
    @w.operate('review_terms_proposal',input,key) do
      p=comparison(input.fetch('proposal_id'),input.fetch('expected_hash'))
      c=comparison!(p,input.fetch('comparison_hash')); document=document!(input['document_ref'])
      raise Economics::Error.new('VALIDATION_ERROR') unless input['decision']=='approved_for_demo'
      r={'id'=>"terms-review-#{SecureRandom.uuid}",'proposal_id'=>p['id'],'proposal_hash'=>p['hash'],'comparison_hash'=>c['hash'],
        'role'=>@w.role,'decision'=>'approved_for_demo','document_ref'=>document,'recorded_at'=>Time.current.iso8601(6)}
      @w.write!('terms_review',r)
    end
  end
  def schedule(input,key)
    @w.guard!('finance')
    @w.operate('schedule_terms_proposal',input,key) do
      p=comparison(input.fetch('proposal_id'),input.fetch('expected_hash'))
      c=comparison!(p,input.fetch('comparison_hash'))
      base=selected(p['broker_id'],p['effective_from'])
      raise Economics::Error.new('HASH_CHANGED','Base configuration changed') unless base['id']==p['base_configuration_id'] && base['hash']==p['base_hash']
      proposed={'id'=>p['configuration_id'],'broker_id'=>p['broker_id'],'rates'=>p['rates'],'guarantees'=>p['guarantees'],
        'required_dimensions'=>p['required_dimensions'],'allowed_dimensions'=>p['allowed_dimensions']}
      before=evaluate_for(p['broker_id'],c['business_date'],override:base,example:c['example_id'])
      after=evaluate_for(p['broker_id'],c['business_date'],override:proposed,example:c['example_id'])
      unless before['input_manifest']==c.dig('baseline','input_manifest') && after['input_manifest']==c.dig('proposed','input_manifest') &&
          before['status']=='completed' && after['status']=='completed'
        raise Economics::Error.new('HASH_CHANGED','Comparison inputs changed; compare and review again')
      end
      raise Economics::Error.new('RULE_CONFLICT','A schedule already exists at or after this effective date') if rows('commercial_schedule').any? { |s| s['broker_id']==p['broker_id'] && s['effective_from']>=p['effective_from'] }
      reviews=rows('terms_review').select { |r| r['proposal_id']==p['id'] && r['proposal_hash']==p['hash'] && r['comparison_hash']==c['hash'] }
      pair=reviews.select { |r| r['role']=='finance' }.product(reviews.select { |r| r['role']=='legal' }).find { |a,b| a['document_ref']==b['document_ref'] }
      raise Economics::Error.new('REVIEW_REQUIRED','Finance and Legal must approve the same comparison and document') unless pair
      conf={'id'=>p['configuration_id'],'broker_id'=>p['broker_id'],'effective_from'=>p['effective_from'],'status'=>'scheduled',
        'agreement_id'=>"agreement-#{p['configuration_id']}",'document_ref'=>pair[0]['document_ref'],'guarantees'=>p['guarantees'],
        'source_proposal_id'=>p['id'],'required_dimensions'=>p['required_dimensions'],'allowed_dimensions'=>p['allowed_dimensions'],'rates'=>p['rates']}
      conf['hash']=config_hash(conf)
      @w.write!('commercial_configuration',conf.except('rates'))
      s={'id'=>"schedule-#{SecureRandom.uuid}",'configuration_id'=>conf['id'],'broker_id'=>p['broker_id'],'effective_from'=>p['effective_from'],
        'proposal_id'=>p['id'],'proposal_hash'=>p['hash'],'comparison_hash'=>c['hash'],'review_ids'=>pair.map { |r| r['id'] }}
      @w.write!('commercial_schedule',s)
    end
  end
  def view(workspace:,broker_id:nil,business_date:nil)
    DemoScope.transaction do
      DemoScope.where(**@w.scope).lock.first!
      view_locked(workspace:workspace,broker_id:broker_id,business_date:business_date)
    end
  end
  def view_locked(workspace:,broker_id:nil,business_date:nil)
    raise Economics::Error.new('VALIDATION_ERROR','Workspace must be broker or internal') unless %w[broker internal].include?(workspace)
    raise Economics::Error.new('FORBIDDEN') if @w.role=='advisor' && (workspace!='broker' || (broker_id && broker_id!='broker-alex'))
    date=business_date || Workbench::DATE; date!(date)
    brokers=@w.directory['brokers']; brokers=brokers.select { |b| b['id']=='broker-alex' } if @w.role=='advisor'
    broker_id ||= brokers.first['id']; raise Economics::Error.new('NOT_FOUND') unless brokers.any? { |b| b['id']==broker_id }
    chosen=selected(broker_id,date)
    billing=BillingCatalog.new(@w).view(broker_id:broker_id,business_date:date)
    evaluation=evaluate_for(broker_id,date)
    customers=@w.directory['customers'].index_by { |c| c['id'] }
    lines=evaluation['lines'].map do |l|
      rate=chosen['rates'].find { |r| r['id']==l.dig('trace','winner') }
      obligations=billing.fetch('obligations',[]).select do |o|
        o.dig('source','id')==l['source_id'] && o.dig('source','revision')==l['source_revision'] && o['customer_id']==l['customer_id'] && o['service_id']==l['service_id']
      end
      ids=obligations.map { |o| o['id'] }
      invoice_lines=billing.fetch('invoices',[]).flat_map { |i| i.fetch('lines',[]) }.select { |line| ids.include?(line['obligation_id']) }.map { |line| line['id'] }
      l.slice('id','customer_id','service_id','source_id','source_revision','eligible_minor','earned_minor').merge('customer_name'=>customers.dig(l['customer_id'],'name') || l['customer_id'],
        'coverage_minor'=>l.dig('coverage','coverage_minor'),'incremental_minor'=>l.dig('coverage','incremental_cash_minor'),
        'rate'=>rate&.slice('id','name','kind','numerator','denominator')&.merge('reason'=>l.dig('trace','reason')),
        'agreement_id'=>chosen['agreement_id'],'billing_line_ids'=>invoice_lines,'billing_obligation_ids'=>ids,'exceptions'=>[])
    end
    complete=evaluation['status']=='completed'
    earnings={'status'=>evaluation['status'],'basis'=>'Supplied eligible fee observations; no unseen monthly forecast', 'business_date'=>date,
      'updated_at'=>@w.snapshot['recorded_at'],'earned_minor'=>complete ? lines.sum { |l| l['earned_minor'] } : nil,
      'coverage_minor'=>complete ? lines.sum { |l| l['coverage_minor'] } : nil,'incremental_minor'=>complete ? lines.sum { |l| l['incremental_minor'] } : nil,
      'guarantee_minor'=>complete ? evaluation['guarantees'].sum { |g| g['obligation_minor'] } : nil,'lines'=>lines,'exceptions'=>evaluation['exceptions']}
    valid_ids=rows('commercial_schedule').map { |s| s['configuration_id'] }
    agreements=rows('commercial_configuration').select { |c| c['broker_id']==broker_id && (%w[legacy_active legacy_historical].include?(c['status']) || valid_ids.include?(c['id'])) }.map do |c|
      full=config(c['id']); later=rows('commercial_schedule').select { |s| s['broker_id']==broker_id && s['effective_from']>c['effective_from'] }.map { |s| s['effective_from'] }.min
      { 'id'=>c['agreement_id'],'title'=>'Illustrative advisor terms','document_version'=>c.dig('document_ref','version'),'document_status'=>c.dig('document_ref','status'),'document_ref'=>c['document_ref'],
        'effective_from'=>c['effective_from'],'effective_to'=>later,'illustrative'=>true,'configuration_id'=>c['id'],'rates'=>full['rates'],'guarantees'=>c['guarantees'] }
    end
    out={'schema_version'=>'product-v1','synthetic'=>true,'workspace'=>workspace,'business_date'=>date,'brokers'=>brokers,'selected_broker_id'=>broker_id,
      'earnings'=>earnings,'agreements'=>agreements,'billing'=>billing}
    if workspace=='internal'
      out['configuration']=chosen
      out['proposals']=rows('terms_proposal').select { |p| p['broker_id']==broker_id }.map do |p|
        comps=rows('terms_comparison').select { |v| v['proposal_id']==p['id'] }
        reviews=rows('terms_review').select { |v| v['proposal_id']==p['id'] }
        scheduled=rows('commercial_schedule').any? { |v| v['proposal_id']==p['id'] }
        p.merge('rates'=>rate_rows(p['configuration_id']),'status'=>scheduled ? 'scheduled' : 'draft','comparison'=>comps.last,'reviews'=>reviews)
      end
    end
    out
  end
end
