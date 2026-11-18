# Shared orchestration for both products. Monetary work belongs to Economics::Engine.
class BillingPlatform
  NS = 'billing_platform'
  ACTIONS = {'REGISTER_SOURCE'=>:register_source,'INGEST'=>:ingest,'REPLAY'=>:replay,
    'SAVE_POLICY'=>:save_policy,'COMPARE_POLICY'=>:compare_policy,'REVIEW_POLICY'=>:review_policy,
    'PUBLISH_POLICY'=>:publish_policy,'ASSIGN_POLICY'=>:assign_policy,'EVALUATE'=>:evaluate,
    'ISSUE_INVOICE'=>:issue_invoice,'PROPOSE_CORRECTION'=>:propose_correction,
    'REVIEW_CORRECTION'=>:review_correction,'ISSUE_CORRECTION'=>:issue_correction,
    'REVIEW_EVENT'=>:review_event,'CLOSE_PERIOD'=>:close_period}.freeze
  INPUTS={
    'REGISTER_SOURCE'=>%w[name mapping],'INGEST'=>%w[source_id delivery_key raw raw_base64],'REPLAY'=>%w[delivery_id source_id],
    'SAVE_POLICY'=>%w[policy effective_from effective_to reason],'COMPARE_POLICY'=>%w[policy_id baseline_policy_id subject_id service_start service_end_exclusive],
    'REVIEW_POLICY'=>%w[comparison_id decision reason document_ref],'PUBLISH_POLICY'=>%w[comparison_id],
    'ASSIGN_POLICY'=>%w[policy_id subject_id effective_from effective_to reason expected_schedule_hash],
    'EVALUATE'=>%w[subject_id service_start service_end_exclusive],'ISSUE_INVOICE'=>%w[run_id posting_period due_on],
    'PROPOSE_CORRECTION'=>%w[document_id run_id posting_period reason],'REVIEW_CORRECTION'=>%w[proposal_id decision reason],
    'ISSUE_CORRECTION'=>%w[proposal_id],'REVIEW_EVENT'=>%w[record_id expected_hash decision reason],'CLOSE_PERIOD'=>%w[posting_period reason]
  }.freeze
  attr_reader :w,:m,:case_id
  def initialize(workbench,case_id)
    @w=workbench; @m=w.medallion; @case_id=m.case!(case_id)
  end
  def error(code,message=code) = m.error(code,message)
  def rows(kind) = m.source(case_id,NS,kind)
  def get(kind,id) = m.get!(case_id,NS,kind,id)
  def id!(value) = m.id!(value)
  def hash(value) = Economics::Canonical.hash(value)
  def copy(value) = Economics::Canonical.copy(value)
  def uid(prefix) = "bp-#{prefix}-#{SecureRandom.uuid}"
  def store(kind,payload,id:uid(kind),status:'retained',parent:nil,**attrs)
    m.store!(case_id,NS,kind,id:id,status:status,payload:payload,parent:parent,**attrs)
  end
  def date!(value)
    date=m.date!(value); error('INVALID_DATE') unless date.year.between?(1,9999); date
  end
  def clock(value) = m.time!(value)
  def interval!(from,to)
    a=date!(from); b=date!(to); error('INVALID_INTERVAL') unless a<b && (b-a)<=366
    [a,b]
  end
  def implementation_hash
    paths=%w[billing_platform billing_policy billing_pipeline billing_documents].map { |name| Rails.root.join("app/services/#{name}.rb").to_s }+Dir[Rails.root.join('app/jobs/billing_*.rb')]+Dir[Rails.root.join('app/domains/economics/*.rb')]
    hash(paths.sort.to_h { |path| [File.basename(path),Digest::SHA256.file(path).hexdigest] })
  end
  def command(action,input,key)
    w.guard!('operator','finance','legal')
    error('VALIDATION_ERROR') unless input.is_a?(Hash) && ACTIONS.key?(action)
    error('VALIDATION_ERROR','Unsupported command input fields') unless (input.keys-INPUTS.fetch(action)-['case_id']).empty?
    error('SCOPE_MISMATCH') if input.key?('case_id') && input['case_id']!=case_id
    w.operate("billing_platform_#{action}",input.merge('case_id'=>case_id),key) do
      begin
        public_send(ACTIONS.fetch(action),input)
      rescue Economics::Error => e
        raise unless action=='EVALUATE' && w.role=='operator' && e.code!='FORBIDDEN'
        receipt=store('calculation_attempt',{'service'=>'BillingPlatform','input'=>input,'errors'=>[e.to_h],'implementation_hash'=>implementation_hash},status:'blocked')
        {'status'=>'blocked','attempt_id'=>receipt.external_id,'errors'=>[e.to_h]}
      end
    end
  rescue KeyError,ArgumentError,TypeError,NoMethodError => e
    Rails.logger.info("Billing platform rejected #{e.class}")
    error('VALIDATION_ERROR','Incomplete or invalid billing input')
  rescue ActiveRecord::StatementInvalid => e
    if [PG::CheckViolation,PG::ExclusionViolation,PG::UniqueViolation,PG::ForeignKeyViolation].any? { |type| e.cause.is_a?(type) }
      error('RULE_CONFLICT','A scoped date, identity or native conservation constraint rejected this request')
    end
    raise
  end
  def register_source(input) = BillingPipeline.new(self).register(input)
  def ingest(input) = BillingPipeline.new(self).ingest(input)
  def replay(input)
    w.guard!('operator'); delivery=get('delivery',input.fetch('delivery_id'))
    BillingNormalizeJob.perform_now(w.tenant,w.entity,case_id,delivery.external_id,input.fetch('source_id'))
  end
  def review_event(input)
    w.guard!('finance'); row=get('normalized',input.fetch('record_id'))
    error('INVALID_SOURCE') unless row.payload.dig('record','type')=='event' && row.status=='accepted'
    error('HASH_CHANGED','The event source revision changed; review the current record') unless input.fetch('expected_hash')==row.payload_hash
    error('VALIDATION_ERROR') unless %w[approved rejected].include?(input['decision'])
    m.reason!(input['reason'])
    store('event_review',{'record_id'=>row.external_id,'record_hash'=>row.payload_hash,'decision'=>input['decision'],'reason'=>input['reason']},status:input['decision'],parent:row).payload
  end
  def save_policy(input)
    w.guard!('operator'); a=date!(input.fetch('effective_from')); b=input.fetch('effective_to'); b=b.nil? ? nil : date!(b)
    error('INVALID_INTERVAL') if b && a>=b
    config=BillingPolicy.validate!(input.fetch('policy'))
    m.reason!(input['reason'])
    p=store('policy',{'config'=>config,'reason'=>input['reason'],'effective_from'=>a.iso8601,'effective_to'=>b&.iso8601},status:'draft',starts_on:a,ends_on:b)
    BillingPolicy.rates(config).each do |rate|
      number=Rational(rate['value']); start=rate['from'] ? date!(rate['from']) : a; finish=rate['to'] ? date!(rate['to']) : b
      CommercialRate.create!(**w.scope,configuration_id:p.external_id,external_id:rate['id'],broker_id:case_id=='advisor' ? 'advisor-demo' : 'ria-harbor',component:rate['component'],kind:rate['kind'],name:rate['id'].tr('-_','  '),numerator:number.numerator,denominator:number.denominator,starts_on:start,ends_on:finish,selector:rate['selector'],priority:rate['priority'],unit:rate['unit'],payer_id:case_id=='advisor' ? 'client' : 'ria-harbor',payee_id:'firm-demo',recorded_at:Time.current)
    end
    {'policy_id'=>p.external_id,'policy_hash'=>p.payload_hash,'status'=>'draft'}
  end
  def published?(policy)
    rows('policy_publication').where("payload->>'policy_id' = ? AND payload->>'policy_hash' = ?",policy.external_id,policy.payload_hash).exists?
  end
  def compare_policy(input)
    w.guard!('operator'); proposed=get('policy',input.fetch('policy_id'))
    base=input['baseline_policy_id'] && get('policy',input['baseline_policy_id'])
    error('UNAPPROVED_POLICY') if base && !published?(base)
    a,b=interval!(input.fetch('service_start'),input.fetch('service_end_exclusive'))
    subject=id!(input.fetch('subject_id')); cutoff=Time.current.iso8601(6)
    needs=[proposed,base].compact.map { |p| BillingPolicy.requirements(p.payload['config'])['balances'] }
    requirements={'balances'=>needs.include?('daily') ? 'daily' : needs.include?('ending') ? 'ending' : 'none'}
    manifest=BillingPipeline.new(self).manifest(subject,a,b,cutoff,requirements:requirements)
    after=calculate(proposed,manifest,a,b,cutoff,hypothetical:true)
    before=base ? calculate(base,manifest,a,b,cutoff,hypothetical:true) : nil
    binding={'policy_id'=>proposed.external_id,'policy_hash'=>proposed.payload_hash,'baseline_policy_id'=>base&.external_id,'baseline_hash'=>base&.payload_hash,
      'subject_id'=>subject,'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'requirements'=>requirements,'manifest_hash'=>hash(manifest),'implementation_hash'=>implementation_hash}
    c=store('comparison',{'binding'=>binding,'manifest'=>manifest,'before'=>before,'after'=>after,'cutoff'=>cutoff},status:'completed',parent:proposed)
    {'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'before_minor'=>before&.fetch('total_minor'),'after_minor'=>after.fetch('total_minor')}
  end
  def comparison_current!(comparison)
    binding=comparison.payload.fetch('binding'); policy=get('policy',binding.fetch('policy_id'))
    error('HASH_CHANGED') unless policy.payload_hash==binding['policy_hash'] && implementation_hash==binding['implementation_hash']
    if binding['baseline_policy_id']
      base=get('policy',binding['baseline_policy_id']); error('HASH_CHANGED') unless published?(base) && base.payload_hash==binding['baseline_hash']
    end
    a,b=interval!(binding['service_start'],binding['service_end_exclusive'])
    current=BillingPipeline.new(self).manifest(binding['subject_id'],a,b,Time.current.iso8601(6),requirements:binding['requirements'])
    error('HASH_CHANGED','Source evidence changed; compare again') unless hash(current)==binding['manifest_hash']
    policy
  end
  def review_policy(input)
    w.guard!('legal','finance'); c=get('comparison',input.fetch('comparison_id')); comparison_current!(c)
    error('VALIDATION_ERROR') unless %w[approved rejected].include?(input['decision'])
    ref=input.fetch('document_ref'); error('VALIDATION_ERROR','Use a versioned mock CLM reference') unless ref.is_a?(Hash) && ref['system']=='mock_clm' && %w[document_id version].all? { |k| ref[k].is_a?(String) && ref[k].match?(/\A[a-zA-Z0-9_-]{1,100}\z/) }
    m.reason!(input['reason'])
    r=store('policy_review',{'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'role'=>w.role,'decision'=>input['decision'],'document_ref'=>ref,'reason'=>input['reason']},status:input['decision'],parent:c)
    {'review_id'=>r.external_id,'role'=>w.role,'decision'=>r.status}
  end
  def publish_policy(input)
    w.guard!('operator'); c=get('comparison',input.fetch('comparison_id')); p=comparison_current!(c)
    reviews=rows('policy_review').where(parent_id:c.id).select("DISTINCT ON (payload->>'role') medallion_evidence.*").order(Arel.sql("payload->>'role', id DESC")).to_a
    pair=%w[legal finance].map { |role| reviews.find { |r| r.payload['role']==role && r.status=='approved' && r.payload['comparison_hash']==c.payload_hash } }
    error('REVIEW_REQUIRED') unless pair.all? && pair.map { |r| r.payload['document_ref'] }.uniq.one?
    prior=rows('policy_publication').find_by(parent_id:p.id)
    publication=prior || store('policy_publication',{'policy_id'=>p.external_id,'policy_hash'=>p.payload_hash,'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'reviews'=>pair.map(&:external_id)},status:'published',parent:p)
    {'publication_id'=>publication.external_id,'policy_id'=>p.external_id}
  end
  def schedule(subject)
    relation=rows('assignment').where(subject_id:subject)
    version=relation.maximum(:schedule_version)
    version ? relation.where(schedule_version:version).order(:starts_on).to_a : []
  end
  def assign_policy(input)
    w.guard!('operator'); p=get('policy',input.fetch('policy_id')); error('UNAPPROVED_POLICY') unless published?(p)
    subject=id!(input.fetch('subject_id')); a,b=interval!(input.fetch('effective_from'),input.fetch('effective_to'))
    error('INVALID_INTERVAL','Assignment must fit policy validity') unless p.starts_on<=a && (!p.ends_on || b<=p.ends_on)
    m.reason!(input['reason']); old=schedule(subject)
    expected=hash(old.map { |r| [r.external_id,r.payload_hash] }); error('HASH_CHANGED','Assignment schedule changed') unless input.fetch('expected_schedule_hash')==expected
    version=(old.map(&:schedule_version).max || 0)+1
    segments=old.flat_map do |r|
      x,y=r.starts_on,r.ends_on
      if x<b && a<y
        parts=[]; parts << [x,a,get('policy',r.payload['policy_id'])] if x<a; parts << [b,y,get('policy',r.payload['policy_id'])] if b<y; parts
      else [[x,y,get('policy',r.payload['policy_id'])]] end
    end
    segments << [a,b,p]; error('RESOURCE_LIMIT') if segments.size>100
    created=segments.sort_by(&:first).map do |x,y,policy|
      store('assignment',{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'subject_id'=>subject,'reason'=>input['reason'],'superseded'=>old.map(&:external_id)},status:'published',parent:policy,subject_id:subject,product_id:case_id,starts_on:x,ends_on:y,schedule_version:version)
    end
    {'assignment_ids'=>created.map(&:external_id),'schedule_hash'=>hash(created.map { |r| [r.external_id,r.payload_hash] })}
  end
  def calculate(policy,manifest,a,b,cutoff,hypothetical:false,billing_start:a,billing_end:b)
    compiler=BillingPolicy.new(self,policy.payload.fetch('config'),manifest,a,b,billing_start,billing_end)
    specs=BillingPolicy.rates(policy.payload['config']); persisted=CommercialRate.where(**w.scope,configuration_id:policy.external_id).index_by(&:external_id)
    error('HASH_CHANGED','Scalar rate records do not match the reviewed policy') unless specs.size==persisted.size && specs.all? { |r| value=persisted[r['id']]; value && Rational(value.numerator,value.denominator)==Rational(r['value']) && value.kind==r['kind'] && value.selector==r['selector'] && value.component==r['component'] }
    graph=compiler.compile
    context={'tenant_id'=>w.tenant,'entity_id'=>w.entity,'scenario'=>NS,'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'knowledge_cutoff'=>cutoff}
    context['hypothetical']=true if hypothetical
    result=Economics::Engine.new.evaluate(policy_bundle:{'policy'=>graph,'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'approved'=>published?(policy)},input_manifest:compiler.engine_manifest,context:context)
    error('INCOMPLETE_SOURCE','The policy could not complete; no bill was created') unless %w[completed partial].include?(result['status'])
    details=result['details'].index_by { |d| d['id'] }; charge=details['charge'] || error('INCOMPLETE_SOURCE','The mandatory charge output is blocked')
    error('INVALID_PROGRAM','Charge must be a bounded nonnegative assessed obligation') unless charge['assessed_minor'].is_a?(Integer) && charge['assessed_minor'].between?(0,10**15) && charge['output_class']=='obligation' && charge['payer']==manifest['subject_id'] && charge['payee']=='firm-demo' && charge['currency']=='USD'
    allocations=manifest.fetch('accounts').to_h do |account|
      output=details["allocation_#{Digest::SHA256.hexdigest(account['account_id'])[0,16]}"] || error('INCOMPLETE_SOURCE','A mandatory invoice allocation is blocked')
      error('INVALID_ALLOCATION') unless output['assessed_minor'].is_a?(Integer) && output['assessed_minor']>=0
      [account['account_id'],output['assessed_minor']]
    end
    error('INVALID_ALLOCATION') unless allocations.values.sum==charge['assessed_minor']
    {'result'=>result,'graph'=>graph,'total_minor'=>charge['assessed_minor'],'allocations'=>allocations,'manifest'=>manifest,'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash}
  end
  def evaluate(input)
    w.guard!('operator'); subject=id!(input.fetch('subject_id')); a,b=interval!(input.fetch('service_start'),input.fetch('service_end_exclusive'))
    cutoff=Time.current.iso8601(6); assignments=schedule(subject).select { |r| r.starts_on<b && a<r.ends_on }
    bounds=([a,b]+assignments.flat_map { |r| [[r.starts_on,a].max,[r.ends_on,b].min] }).uniq.sort
    segments=bounds.each_cons(2).map do |x,y|
      eligible=assignments.select { |r| r.starts_on<=x && y<=r.ends_on }; error('UNRESOLVED_MAPPING','Assign reviewed terms for every service day') unless eligible.one?
      assignment=eligible.first; policy=get('policy',assignment.payload['policy_id']); error('HASH_CHANGED') unless published?(policy) && policy.payload_hash==assignment.payload['policy_hash'] && policy.starts_on<=x && (!policy.ends_on || y<=policy.ends_on)
      manifest=BillingPipeline.new(self).manifest(subject,x,y,cutoff,requirements:BillingPolicy.requirements(policy.payload['config']))
      calculate(policy,manifest,x,y,cutoff,billing_start:a,billing_end:b).merge('assignment_id'=>assignment.external_id,'service_start'=>x.iso8601,'service_end_exclusive'=>y.iso8601)
    end
    amounts=segments.flat_map { |segment| segment['allocations'].map { |id,amount| [id,amount] } }.group_by(&:first)
    allocations=amounts.to_h { |id,parts| [id,engine_sum(parts.map(&:last),a,b)] }
    total=engine_sum(allocations.values,a,b)
    extras=segments.map { |s| s['result']['details'].index_by { |d| d['id'] } }
    compensation=extras.filter_map { |d| d['compensation'] && d['compensation']['assessed_minor'] }
    payouts=extras.filter_map { |d| d['additional_payout'] && d['additional_payout']['assessed_minor'] }
    benefits=extras.filter_map { |d| d['pricing_benefit'] && d['pricing_benefit']['assessed_minor'] }
    run=store('calculation',{'subject_id'=>subject,'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'knowledge_cutoff'=>cutoff,'segments'=>segments,'allocations'=>allocations,'total_minor'=>total,'compensation_minor'=>compensation.empty? ? nil : engine_sum(compensation,a,b),'additional_payout_minor'=>payouts.empty? ? nil : engine_sum(payouts,a,b),'pricing_benefit_minor'=>benefits.empty? ? nil : engine_sum(benefits,a,b),'implementation_hash'=>implementation_hash},status:'completed')
    {'run_id'=>run.external_id,'amount_minor'=>total,'allocations'=>allocations}
  end
  def engine_sum(amounts,a,b)
    amounts=[0] if amounts.empty?
    graph={'version'=>'billing-rollup/v1','nodes'=>amounts.each_with_index.map { |v,i| {'id'=>"v#{i}",'op'=>'literal','role'=>'intermediate','unit'=>'USD_minor','basis'=>'assessed','value'=>v} } }
    graph['nodes'] << {'id'=>'total','op'=>'add','role'=>'terminal','unit'=>'USD_minor','basis'=>'assessed','inputs'=>graph['nodes'].map { |n| n['id'] }}
    Economics::Engine.new.evaluate_program(policy:graph,facts:{})['terminal_outputs'].first.fetch('value').to_i
  end
  def fresh_run!(run)
    error('HASH_CHANGED','Billing implementation changed; evaluate again') unless run.payload['implementation_hash']==implementation_hash
    run.payload.fetch('segments').each do |s|
      x,y=interval!(s['service_start'],s['service_end_exclusive'])
      current=BillingPipeline.new(self).manifest(run.payload['subject_id'],x,y,Time.current.iso8601(6),requirements:s['manifest']['requirements'])
      error('HASH_CHANGED','Source evidence changed; evaluate again') unless hash(current)==hash(s['manifest'])
      assignment=schedule(run.payload['subject_id']).find { |r| r.starts_on<=x && y<=r.ends_on }
      error('HASH_CHANGED','Assigned policy changed; evaluate again') unless assignment && assignment.payload['policy_id']==s['policy_id'] && assignment.payload['policy_hash']==s['policy_hash']
    end
    run
  end
  def issue_invoice(input) = BillingDocuments.new(self).issue(input)
  def propose_correction(input) = BillingDocuments.new(self).propose(input)
  def review_correction(input) = BillingDocuments.new(self).review(input)
  def issue_correction(input) = BillingDocuments.new(self).correct(input)
  def close_period(input)
    w.guard!('finance'); BillingDocuments.new(self).period!(input.fetch('posting_period')); m.reason!(input['reason'])
    row=rows('period_close').find_by(external_id:"closed-#{input['posting_period']}") || store('period_close',{'posting_period'=>input['posting_period'],'reason'=>input['reason']},id:"closed-#{input['posting_period']}",status:'closed')
    {'period'=>row.payload['posting_period'],'status'=>'closed'}
  end
end
