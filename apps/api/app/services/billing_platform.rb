# Shared orchestration for both products. Monetary work belongs to Economics::Engine.
class BillingPlatform
  NS = 'billing_platform'
  ACTIONS = {'REGISTER_SOURCE'=>:register_source,'INGEST'=>:ingest,'REPLAY'=>:replay,
    'SAVE_POLICY'=>:save_policy,'COMPARE_POLICY'=>:compare_policy,'REVIEW_POLICY'=>:review_policy,
    'PUBLISH_POLICY'=>:publish_policy,'ASSIGN_POLICY'=>:assign_policy,'EVALUATE'=>:evaluate,
    'ISSUE_INVOICE'=>:issue_invoice,'PROPOSE_CORRECTION'=>:propose_correction,
    'REVIEW_CORRECTION'=>:review_correction,'ISSUE_CORRECTION'=>:issue_correction,
    'REVIEW_EVENT'=>:review_event,'CLOSE_PERIOD'=>:close_period,'APPLY_CASH'=>:apply_cash,'REVERSE_CASH'=>:reverse_cash,'REQUEST_REFUND'=>:request_refund,'CANCEL_REFUND'=>:cancel_refund,'PACKAGE_ACCOUNTING'=>:package_accounting,'ACCEPT_ACCOUNTING'=>:accept_accounting,'PROPOSE_PAYABLE'=>:propose_payable,'REVIEW_PAYABLE'=>:review_payable,'ISSUE_PAYABLE'=>:issue_payable,'QUEUE_BATCH'=>:queue_batch,'RETRY_WORK'=>:retry_work}.freeze
  INPUTS={
    'REGISTER_SOURCE'=>%w[name mapping],'INGEST'=>%w[source_id delivery_key raw raw_base64 defer run_at],'REPLAY'=>%w[delivery_id source_id],
    'SAVE_POLICY'=>%w[policy effective_from effective_to reason],'COMPARE_POLICY'=>%w[policy_id baseline_policy_id subject_id service_start service_end_exclusive],
    'REVIEW_POLICY'=>%w[comparison_id decision reason document_ref],'PUBLISH_POLICY'=>%w[comparison_id],
    'ASSIGN_POLICY'=>%w[policy_id subject_id effective_from effective_to reason expected_schedule_hash],
    'EVALUATE'=>%w[subject_id service_start service_end_exclusive purpose],'ISSUE_INVOICE'=>%w[run_id posting_period due_on],
    'PROPOSE_CORRECTION'=>%w[document_id run_id posting_period reason],'REVIEW_CORRECTION'=>%w[proposal_id decision reason],
    'ISSUE_CORRECTION'=>%w[proposal_id],'REVIEW_EVENT'=>%w[record_id expected_hash decision reason],'CLOSE_PERIOD'=>%w[posting_period reason],
    'APPLY_CASH'=>%w[target_id record_id expected_hash expected_ledger_hash amount_minor posting_period reason request_id],
    'REVERSE_CASH'=>%w[application_id expected_hash posting_period reason],
    'CANCEL_REFUND'=>%w[request_id expected_hash posting_period reason],
    'REQUEST_REFUND'=>%w[target_id expected_ledger_hash amount_minor posting_period reason],
    'PACKAGE_ACCOUNTING'=>%w[target_id expected_ledger_hash treatment_ref posting_period reason],
    'ACCEPT_ACCOUNTING'=>%w[record_id expected_hash],
    'PROPOSE_PAYABLE'=>%w[run_id posting_period reason],'REVIEW_PAYABLE'=>%w[proposal_id decision reason],'ISSUE_PAYABLE'=>%w[proposal_id],
    'QUEUE_BATCH'=>%w[subjects service_start service_end_exclusive run_at reason purpose],'RETRY_WORK'=>%w[job_id source_id reason]
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
    paths=%w[billing_platform billing_policy billing_pipeline billing_documents billing_lifecycle billing_payables billing_worker].map { |name| Rails.root.join("app/services/#{name}.rb").to_s }+Dir[Rails.root.join('app/jobs/billing_*.rb')]+Dir[Rails.root.join('app/domains/economics/*.rb')]
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
      CommercialRate.create!(**w.scope,configuration_id:p.external_id,external_id:rate['id'],broker_id:case_id=='advisor' ? 'advisor-demo' : 'ria-harbor',component:rate['component'],kind:rate['kind'],name:rate['id'].tr('-_','  '),numerator:number.numerator,denominator:number.denominator,starts_on:start,ends_on:finish,selector:rate['selector'],priority:rate['priority'],unit:rate['unit'],payer_id:config['purpose']=='earnings' ? 'firm-demo' : case_id=='advisor' ? 'client' : 'ria-harbor',payee_id:config['purpose']=='earnings' ? 'subject' : 'firm-demo',recorded_at:Time.current)
    end
    {'policy_id'=>p.external_id,'policy_hash'=>p.payload_hash,'status'=>'draft'}
  end
  def published?(policy)
    rows('policy_publication').where("payload->>'policy_id' = ? AND payload->>'policy_hash' = ?",policy.external_id,policy.payload_hash).exists?
  end
  def compare_policy(input)
    w.guard!('operator'); proposed=get('policy',input.fetch('policy_id'))
    base=input['baseline_policy_id'] && get('policy',input['baseline_policy_id'])
    error('UNRELATED_POLICY','Compare policies with the same commercial purpose') if base && base.payload['config'].fetch('purpose','billing')!=proposed.payload['config'].fetch('purpose','billing')
    error('UNAPPROVED_POLICY') if base && !published?(base)
    a,b=interval!(input.fetch('service_start'),input.fetch('service_end_exclusive'))
    subject=id!(input.fetch('subject_id')); cutoff=Time.current.iso8601(6)
    needs=[proposed,base].compact.map { |p| BillingPolicy.requirements(p.payload['config'])['balances'] }
    parts=needs.flat_map { |v| v.split('_') }; mode=parts.include?('daily') ? 'daily' : parts.include?('ending') ? 'ending' : 'none'; mode=mode=='none' ? 'opening' : mode+'_opening' if parts.include?('opening')
    requirements={'balances'=>mode}
    manifest=billing_manifest(subject,a,b,cutoff,requirements:requirements,purpose:proposed.payload['config']['purpose'])
    after=calculate(proposed,manifest,a,b,cutoff,hypothetical:true)
    before=base ? calculate(base,manifest,a,b,cutoff,hypothetical:true) : nil
    binding={'policy_id'=>proposed.external_id,'policy_hash'=>proposed.payload_hash,'baseline_policy_id'=>base&.external_id,'baseline_hash'=>base&.payload_hash,
      'purpose'=>proposed.payload['config']['purpose'],'subject_id'=>subject,'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'requirements'=>requirements,'manifest_hash'=>hash(manifest),'implementation_hash'=>implementation_hash}
    c=store('comparison',{'binding'=>binding,'manifest'=>manifest,'before'=>before,'after'=>after,'cutoff'=>cutoff},status:'completed',parent:proposed)
    {'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'before_minor'=>before && before.fetch('net_minor',before['total_minor']),'after_minor'=>after.fetch('net_minor',after['total_minor'])}
  end
  def comparison_current!(comparison)
    binding=comparison.payload.fetch('binding'); policy=get('policy',binding.fetch('policy_id'))
    error('HASH_CHANGED') unless policy.payload_hash==binding['policy_hash'] && implementation_hash==binding['implementation_hash']
    if binding['baseline_policy_id']
      base=get('policy',binding['baseline_policy_id']); error('HASH_CHANGED') unless published?(base) && base.payload_hash==binding['baseline_hash']
    end
    a,b=interval!(binding['service_start'],binding['service_end_exclusive'])
    current=billing_manifest(binding['subject_id'],a,b,Time.current.iso8601(6),requirements:binding['requirements'],purpose:binding['purpose'])
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
  def schedule(subject,purpose:'billing')
    relation=rows('assignment').where(subject_id:subject).where("COALESCE(payload->>'purpose','billing')=?",purpose)
    version=relation.maximum(:schedule_version)
    version ? relation.where(schedule_version:version).order(:starts_on).to_a : []
  end
  def assign_policy(input)
    w.guard!('operator'); p=get('policy',input.fetch('policy_id')); error('UNAPPROVED_POLICY') unless published?(p)
    subject=id!(input.fetch('subject_id')); a,b=interval!(input.fetch('effective_from'),input.fetch('effective_to'))
    error('INVALID_INTERVAL','Assignment must fit policy validity') unless p.starts_on<=a && (!p.ends_on || b<=p.ends_on)
    m.reason!(input['reason']); purpose=p.payload['config'].fetch('purpose','billing'); old=schedule(subject,purpose:purpose)
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
      store('assignment',{'purpose'=>purpose,'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'subject_id'=>subject,'reason'=>input['reason'],'superseded'=>old.map(&:external_id)},status:'published',parent:policy,subject_id:subject,product_id:purpose=='earnings' ? case_id+'-earnings' : case_id,starts_on:x,ends_on:y,schedule_version:version)
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
    purpose=policy.payload['config'].fetch('purpose','billing')
    details=result['details'].index_by { |d| d['id'] }; charge=details[purpose=='earnings' ? 'compensation' : 'charge'] || error('INCOMPLETE_SOURCE','The mandatory charge output is blocked')
    error('INVALID_PROGRAM','Charge must be a bounded nonnegative assessed obligation') unless charge['assessed_minor'].is_a?(Integer) && charge['assessed_minor'].between?(0,10**15) && charge['output_class']=='obligation' && charge['payer']==(purpose=='earnings' ? 'firm-demo' : manifest['subject_id']) && charge['payee']==(purpose=='earnings' ? manifest['subject_id'] : 'firm-demo') && charge['currency']=='USD'
    allocations=manifest.fetch('accounts').to_h do |account|
      output=details["allocation_#{Digest::SHA256.hexdigest(account['account_id'])[0,16]}"] || error('INCOMPLETE_SOURCE','A mandatory invoice allocation is blocked')
      error('INVALID_ALLOCATION') unless output['assessed_minor'].is_a?(Integer) && output['assessed_minor']>=0
      [account['account_id'],output['assessed_minor']]
    end
    error('INVALID_ALLOCATION') unless allocations.values.sum==charge['assessed_minor']
    credit=details['credit_balance']
    error('INVALID_PROGRAM') if credit && (!credit['assessed_minor'].is_a?(Integer) || !credit['assessed_minor'].between?(0,10**15) || credit['output_class']!='obligation' || credit['currency']!='USD' || credit['payer']!=(purpose=='earnings' ? manifest['subject_id'] : 'firm-demo') || credit['payee']!=(purpose=='earnings' ? 'firm-demo' : manifest['subject_id']))
    credit_allocations=manifest.fetch('accounts').to_h do |account|
      value=details["credit_allocation_#{Digest::SHA256.hexdigest(account['account_id'])[0,16]}"]
      amount=value ? value['assessed_minor'] : 0; error('INVALID_ALLOCATION') unless amount.is_a?(Integer) && amount>=0
      [account['account_id'],amount]
    end
    error('INVALID_ALLOCATION') unless credit_allocations.values.sum==(credit ? credit['assessed_minor'] : 0)
    settlement=allocations.to_h { |account,amount| [account,Economics::Engine.new.primitive_binary('subtract',amount,credit_allocations.fetch(account)).to_i] }
    {'purpose'=>purpose,'net_minor'=>engine_sum(settlement.values,a,b),'credit_minor'=>credit_allocations.values.sum,'settlement_allocations'=>settlement,'result'=>result,'graph'=>graph,'total_minor'=>charge['assessed_minor'],'allocations'=>allocations,'manifest'=>manifest,'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash}
  end
  def evaluate(input)
    w.guard!('operator'); subject=id!(input.fetch('subject_id')); a,b=interval!(input.fetch('service_start'),input.fetch('service_end_exclusive'))
    purpose=input.fetch('purpose','billing'); error('VALIDATION_ERROR') unless %w[billing earnings].include?(purpose)
    cutoff=Time.current.iso8601(6); assignments=schedule(subject,purpose:purpose).select { |r| r.starts_on<b && a<r.ends_on }
    bounds=([a,b]+assignments.flat_map { |r| [[r.starts_on,a].max,[r.ends_on,b].min] }).uniq.sort
    segments=bounds.each_cons(2).map do |x,y|
      eligible=assignments.select { |r| r.starts_on<=x && y<=r.ends_on }; error('UNRESOLVED_MAPPING','Assign reviewed terms for every service day') unless eligible.one?
      assignment=eligible.first; policy=get('policy',assignment.payload['policy_id']); error('HASH_CHANGED') unless published?(policy) && policy.payload_hash==assignment.payload['policy_hash'] && policy.starts_on<=x && (!policy.ends_on || y<=policy.ends_on)
      manifest=billing_manifest(subject,x,y,cutoff,requirements:BillingPolicy.requirements(policy.payload['config']),purpose:policy.payload['config']['purpose'])
      calculate(policy,manifest,x,y,cutoff,billing_start:a,billing_end:b).merge('assignment_id'=>assignment.external_id,'service_start'=>x.iso8601,'service_end_exclusive'=>y.iso8601)
    end
    amounts=segments.flat_map { |segment| segment['allocations'].map { |id,amount| [id,amount] } }.group_by(&:first)
    allocations=amounts.to_h { |id,parts| [id,engine_sum(parts.map(&:last),a,b)] }
    purposes=segments.map { |s| s['purpose'] }.uniq; error('INVALID_POLICY','A service interval cannot mix billing and earnings policies') unless purposes.one?
    settlement=segments.flat_map { |s| s['settlement_allocations'].to_a }.group_by(&:first).to_h { |id,parts| [id,engine_sum(parts.map(&:last),a,b)] }
    total=engine_sum(allocations.values,a,b)
    extras=segments.map { |s| s['result']['details'].index_by { |d| d['id'] } }
    compensation=extras.filter_map { |d| d['compensation'] && d['compensation']['assessed_minor'] }
    payouts=extras.filter_map { |d| d['additional_payout'] && d['additional_payout']['assessed_minor'] }
    benefits=extras.filter_map { |d| d['pricing_benefit'] && d['pricing_benefit']['assessed_minor'] }
    run=store('calculation',{'purpose'=>purposes.first,'net_minor'=>engine_sum(settlement.values,a,b),'settlement_allocations'=>settlement,'subject_id'=>subject,'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'knowledge_cutoff'=>cutoff,'segments'=>segments,'allocations'=>allocations,'total_minor'=>total,'compensation_minor'=>compensation.empty? ? nil : engine_sum(compensation,a,b),'additional_payout_minor'=>payouts.empty? ? nil : engine_sum(payouts,a,b),'pricing_benefit_minor'=>benefits.empty? ? nil : engine_sum(benefits,a,b),'implementation_hash'=>implementation_hash},status:'completed')
    {'run_id'=>run.external_id,'amount_minor'=>total,'allocations'=>allocations}
  end
  def billing_manifest(subject,a,b,cutoff,requirements:,purpose:nil)
    manifest=BillingPipeline.new(self).manifest(subject,a,b,cutoff,requirements:requirements)
    if purpose=='earnings'
      roots=rows('document').where("payload->>'original_document_id' IS NULL AND payload->>'service_start' = ? AND payload->>'service_end_exclusive' = ?",a.iso8601,b.iso8601)
      roots.order(:id).limit(1001).each_with_index do |root,index|
        error('RESOURCE_LIMIT','Page earnings by service group') if index>=1000
        run=BillingDocuments.new(self).target(root); amount=run.payload['compensation_minor']; next if amount.nil?
        key="issued_compensation_#{root.id}"
        manifest['engine']['facts'][key]={'id'=>key,'revision'=>run.revision,'tenant_id'=>w.tenant,'entity_id'=>w.entity,'approved'=>true,'recorded_at'=>run.recorded_at.iso8601(6),'unit'=>'USD_minor','basis'=>'assessed','currency'=>'USD','value'=>amount.to_s,'collection'=>'issued_compensation','economic_date'=>a.iso8601,'evidence_refs'=>[root.id.to_s,run.id.to_s]}
        manifest['records'] << {'id'=>run.external_id,'revision'=>run.revision,'hash'=>run.payload_hash,'kind'=>'issued_compensation','record_id'=>run.id.to_s}
      end
    end
    manifest
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
      current=billing_manifest(run.payload['subject_id'],x,y,Time.current.iso8601(6),requirements:s['manifest']['requirements'],purpose:run.payload['purpose'])
      error('HASH_CHANGED','Source evidence changed; evaluate again') unless hash(current)==hash(s['manifest'])
      assignment=schedule(run.payload['subject_id'],purpose:run.payload.fetch('purpose','billing')).find { |r| r.starts_on<=x && y<=r.ends_on }
      error('HASH_CHANGED','Assigned policy changed; evaluate again') unless assignment && assignment.payload['policy_id']==s['policy_id'] && assignment.payload['policy_hash']==s['policy_hash']
    end
    run
  end
  def issue_invoice(input) = BillingDocuments.new(self).issue(input)
  def propose_correction(input) = BillingDocuments.new(self).propose(input)
  def review_correction(input) = BillingDocuments.new(self).review(input)
  def issue_correction(input) = BillingDocuments.new(self).correct(input)
  def apply_cash(input) = BillingLifecycle.new(self).apply(input)
  def reverse_cash(input) = BillingLifecycle.new(self).reverse(input)
  def request_refund(input) = BillingLifecycle.new(self).request_refund(input)
  def cancel_refund(input) = BillingLifecycle.new(self).cancel_refund(input)
  def package_accounting(input) = BillingLifecycle.new(self).package(input)
  def accept_accounting(input) = BillingLifecycle.new(self).accept_accounting(input)
  def propose_payable(input) = BillingPayables.new(self).propose(input)
  def review_payable(input) = BillingPayables.new(self).review(input)
  def issue_payable(input) = BillingPayables.new(self).issue(input)
  def queue_batch(input)
    w.guard!('operator'); a,b=interval!(input.fetch('service_start'),input.fetch('service_end_exclusive')); m.reason!(input['reason'])
    purpose=input.fetch('purpose','billing'); error('VALIDATION_ERROR') unless %w[billing earnings].include?(purpose)
    subjects=input['subjects'] || rows('assignment').where("COALESCE(payload->>'purpose','billing')=? AND starts_on<? AND ends_on>?",purpose,b,a).distinct.order(:subject_id).limit(1001).pluck(:subject_id)
    error('RESOURCE_LIMIT','Submit at most 1,000 groups per batch') unless subjects.is_a?(Array) && subjects.size.between?(1,1000) && subjects.uniq==subjects
    subjects.each { |id| id!(id) }; at=input['run_at'] ? clock(input['run_at']) : Time.current
    error('INVALID_INTERVAL') if at>Time.current+366.days
    batch=store('billing_batch',{'subjects'=>subjects,'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'run_at'=>at.iso8601(6),'reason'=>input['reason']},status:'pending')
    subjects.each { |subject| BillingWorker.enqueue(BillingEvaluateJob.new(w.tenant,w.entity,case_id,subject,a.iso8601,b.iso8601,input.fetch('purpose','billing')),at:at,batch_id:batch.external_id) }
    {'batch_id'=>batch.external_id,'groups'=>subjects.size,'status'=>'queued'}
  end
  def retry_work(input)
    w.guard!('operator'); m.reason!(input['reason'])
    old=BillingWorkItem.find_by(**w.scope,case_id:case_id,job_id:id!(input.fetch('job_id'))) || error('NOT_FOUND')
    error('INVALID_JOB') unless %w[failed quarantined].include?(old.status) && BillingWorker::CLASSES.include?(old.job_class)
    args=copy(old.job_data['arguments']); args[-1]=input['source_id'] if input['source_id'] && old.job_class=='BillingNormalizeJob'
    error('INVALID_JOB') if input['source_id'] && old.job_class!='BillingNormalizeJob'
    job=old.job_class.constantize.new(*args); item=BillingWorker.enqueue(job,batch_id:old.batch_id)
    store('work_attempt',{'job_id'=>old.job_id,'retry_job_id'=>item.job_id,'reason'=>input['reason'],'outcome'=>'manual_retry'},status:'retained')
    {'job_id'=>item.job_id,'status'=>'queued'}
  end
  def close_period(input)
    w.guard!('finance'); BillingDocuments.new(self).period!(input.fetch('posting_period')); m.reason!(input['reason'])
    row=rows('period_close').find_by(external_id:"closed-#{input['posting_period']}") || store('period_close',{'posting_period'=>input['posting_period'],'reason'=>input['reason']},id:"closed-#{input['posting_period']}",status:'closed')
    {'period'=>row.payload['posting_period'],'status'=>'closed'}
  end
end
