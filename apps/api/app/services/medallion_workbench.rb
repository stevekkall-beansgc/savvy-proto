require 'securerandom'
require 'digest'

# Isolated, synthetic evidence and review lifecycle. All arithmetic goes through
# Economics::Engine; operational records are immutable scoped versions.
class MedallionWorkbench
  CASES=%w[advisor ria].freeze
  INTERNAL=%w[operator finance legal auditor].freeze
  ROOT=Rails.root.join('../../fixtures/medallion').expand_path
  attr_reader :workbench
  def initialize(workbench) = @workbench=workbench
  def scope = workbench.scope
  def error(code,message=nil) = raise(Economics::Error.new(code,message || code))
  def id!(value)
    error('VALIDATION_ERROR','A bounded identifier is required') unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
    value
  end
  def case!(value)
    error('NOT_FOUND') unless CASES.include?(value)
    value
  end
  def scenario!(value) = id!(value || 'baseline')
  def reason!(value) = workbench.settlement_book.reason!(value)
  def time!(value) = Economics::Engine.new.time!(value)
  def date!(value) = Economics::Engine.new.date!(value)
  def source(case_id,scenario_id,kind) = MedallionEvidence.where(**scope,case_id:case_id,scenario_id:scenario_id,kind:kind)
  def get!(case_id,scenario_id,kind,id,revision:nil)
    rows=source(case_id,scenario_id,kind).where(external_id:id!(id))
    rows=rows.where(revision:revision) if revision
    rows.order(revision: :desc).first || error('NOT_FOUND')
  end
  def store!(case_id,scenario_id,kind,id:,status:,payload:,revision:1,parent:nil,subject_id:nil,product_id:nil,starts_on:nil,ends_on:nil,schedule_version:1,bytes:nil,recorded_at:Time.current)
    case!(case_id); scenario!(scenario_id); id!(id)
    error('VALIDATION_ERROR') unless payload.is_a?(Hash) && revision.is_a?(Integer) && revision>0
    digest=Economics::Canonical.hash(payload)
    rows=source(case_id,scenario_id,kind)
    existing=rows.find_by(external_id:id,revision:revision)
    if existing
      error('SOURCE_CONFLICT','Same identity and revision have different evidence') unless existing.payload_hash==digest && existing.status==status && existing.original_bytes==bytes
      return existing
    end
    MedallionEvidence.create!(**scope,case_id:case_id,scenario_id:scenario_id,kind:kind,external_id:id,revision:revision,status:status,
      subject_id:subject_id,product_id:product_id,starts_on:starts_on,ends_on:ends_on,schedule_version:schedule_version,parent_id:parent&.id,payload_hash:digest,payload:payload,original_bytes:bytes,recorded_at:recorded_at)
  end
  def fixture(case_id,name)
    path=ROOT.join("#{case_id}-#{name}.json")
    raw=File.binread(path); [raw,JSON.parse(raw)]
  end
  def fixture_rate_attributes(case_id,id)
    base={'starts_on'=>'2026-09-01','ends_on'=>'2026-10-01','kind'=>'standard','selector'=>{},'signup_within_days'=>nil,
      'broker_id'=>case_id=='advisor' ? 'advisor-demo' : 'ria-harbor','payer_id'=>case_id=='advisor' ? 'firm-demo' : 'ria-harbor','payee_id'=>case_id=='advisor' ? 'advisor-demo' : 'firm-demo'}
    if case_id=='advisor'
      case id
      when 'rate_s80' then base.merge('component'=>'advisor_share','name'=>'Standard advisor share')
      when 'rate_s85' then base.merge('component'=>'advisor_share','name'=>'General promotion','kind'=>'promotion','starts_on'=>'2026-09-10','ends_on'=>'2026-09-21')
      when 'rate_s90' then base.merge('component'=>'advisor_share','name'=>'Welcome promotion','kind'=>'targeted_promotion','starts_on'=>'2026-09-11','ends_on'=>'2026-09-21','selector'=>{'customer_type'=>'new_signup'},'signup_within_days'=>10)
      when 'rate_r12' then base.merge('component'=>'client_fee_first_band','name'=>'First client fee band','payer_id'=>'client','payee_id'=>'firm-demo')
      when 'rate_r08' then base.merge('component'=>'client_fee_next_band','name'=>'Additional client fee band','payer_id'=>'client','payee_id'=>'firm-demo')
      else error('UNSUPPORTED_MECHANISM',"Unknown fixture rate #{id}") end
    else
      names={'rate_rebate_rate'=>['receipt_rebate','Receipt-qualified rebate'],'rate_savvy_share'=>['network_savvy_allocation','Savvy network allocation'],
        'rate_network_share'=>['network_other_allocation','Network allocation'],'rate_cash_ref'=>['observed_cash_reference','Observed cash reference'],
        'rate_cash_investor_rate'=>['observed_investor_yield','Observed investor yield'],'rate_margin_rate'=>['observed_margin_charge','Observed margin charge'],
        'rate_margin_funding_rate'=>['observed_margin_funding','Observed margin funding']}
      component,name=names.fetch(id) { error('UNSUPPORTED_MECHANISM',"Unknown fixture rate #{id}") }
      base.merge('component'=>component,'name'=>name)
    end
  end
  def install_fixture_rates(case_id, policy_id, graph)
    graph=Economics::Canonical.copy(graph)
    rows=graph.delete('rate_rows') || {}
    rows.each do |id,source|
      id!(id); value=Rational(source.fetch('value')); attrs=fixture_rate_attributes(case_id,id)
      rate=CommercialRate.find_or_create_by!(**scope,configuration_id:policy_id,external_id:id) do |r|
        r.assign_attributes(attrs); r.unit='ratio'; r.numerator=value.numerator; r.denominator=value.denominator
        r.recorded_at=Time.iso8601('2026-09-01T00:00:00Z')
      end
      unless rate.numerator==value.numerator && rate.denominator==value.denominator && attrs.all? { |key,v| rate.public_send(key).to_s==v.to_s }
        error('SOURCE_CONFLICT','Stored rate differs from fixture')
      end
    end
    graph
  end
  def install_source_proof!(case_id,scenario,proof,artifact)
    error('SYNTHETIC_ONLY') unless proof['synthetic']==true
    if case_id=='advisor'
      funding=proof.fetch('funding'); right=proof.fetch('coverage_right')
      error('SCOPE_MISMATCH') unless funding['status']=='confirmed' && funding['payer']=='firm-demo' && funding['payee']=='advisor-demo' && funding['currency']=='USD' &&
        right['status']=='eligible' && right['funding_id']==funding['id'] && right['payer']==funding['payer'] && right['payee']==funding['payee'] && right['subject']=='advisor-demo' && right['currency']=='USD'
      Economics::Engine.integer!(funding['amount_minor'],'funding',min:1); Economics::Engine.integer!(right['available_minor'],'coverage',min:1)
      error('ALLOCATION_EXCEEDED') if right['available_minor']>funding['amount_minor']
      f=store!(case_id,scenario,'funding',id:funding['id'],revision:funding['revision'],status:'confirmed',payload:funding,parent:artifact,recorded_at:time!(funding['recorded_at']))
      store!(case_id,scenario,'coverage_right',id:right['id'],revision:right['revision'],status:'accepted',payload:right,parent:f,recorded_at:time!(right['recorded_at']))
    else
      receipt=proof.fetch('receipt'); allocations=proof.fetch('allocations')
      error('SCOPE_MISMATCH') unless receipt['status']=='confirmed' && receipt['payer']=='network-fixture' && receipt['payee']=='firm-demo' && receipt['currency']=='USD'
      Economics::Engine.integer!(receipt['amount_minor'],'receipt',min:1)
      error('VALIDATION_ERROR') unless allocations.is_a?(Array) && allocations.size==3 && allocations.map { |a| a['id'] }.uniq.size==3 && allocations.map { |a| a['report_line'] }.sort==%w[cash lending margin]
      allocations.each do |a|
        error('SCOPE_MISMATCH') unless a['receipt_id']==receipt['id'] && a['subject']=='ria-harbor' && a['currency']=='USD'
        Economics::Engine.integer!(a['amount_minor'],'allocation',min:1)
      end
      error('ALLOCATION_EXCEEDED') unless assessed_sum(allocations.map { |a| a['amount_minor'] })==receipt['amount_minor']
      r=store!(case_id,scenario,'receipt',id:receipt['id'],revision:receipt['revision'],status:'confirmed',payload:receipt,parent:artifact,recorded_at:time!(receipt['recorded_at']))
      allocations.each { |a| store!(case_id,scenario,'receipt_allocation',id:a['id'],status:'confirmed',payload:a,parent:r,recorded_at:time!(receipt['recorded_at'])) }
    end
  end
  def event_policies(graph)
    nodes=graph.fetch('nodes'); index=nodes.to_h { |node| [node.fetch('id'),node] }
    groups=nodes.select { |node| node['op']=='sum_facts' && node['collection']=='approved_events' }
    rule_keys=[]
    rules=groups.map do |node|
      selector=node['selector']
      unless selector.is_a?(Hash) && selector.keys.sort==%w[group kind] && node['unit']=='USD_minor' && node['basis']=='assessed' && node['role']=='terminal' && node['period']=='service' && node['allow_empty']==true
        error('UNSUPPORTED_MECHANISM','Unsupported event selector or basis')
      end
      kind=selector['kind']; group=selector['group']
      allowed=[['compensation_entitlement','guarantee'],['compensation_entitlement','outside'],['one_time_credit','service_credit'],['one_time_charge','outside']]
      error('UNSUPPORTED_MECHANISM','Unsupported event treatment') unless allowed.include?([kind,group])
      rule_keys << [kind,group]
      target=kind=='compensation_entitlement' ? 'compensation' : 'net'
      if kind=='compensation_entitlement'
        payable=index['payable']; coverage=index['coverage']
        error('UNSUPPORTED_MECHANISM','Unsupported coverage-to-payable composition') unless payable && payable['op']=='subtract' && payable['left']=='compensation' && payable['right']=='coverage' && coverage && coverage['op']=='min' && Array(coverage['inputs']).count('compensation')==1
      end
      memo={}; visiting={}
      paths=lambda do |id|
        return 1 if id==node['id']
        return memo[id] if memo.key?(id)
        error('GRAPH_CYCLE') if visiting[id]
        item=index[id]; return 0 unless item
        visiting[id]=true
        refs=[item['left'],item['right'],item['input'],*Array(item['inputs'])].compact
        count=refs.sum { |ref| paths.call(ref) }
        visiting.delete(id); memo[id]=[count,2].min
      end
      count=paths.call(target)
      if kind=='compensation_entitlement' && group=='guarantee'
        compensation=index['compensation']; topup=index['topup']; shortfall=index['shortfall']; basis=index['guarantee_basis']
        valid=count==2 && compensation && compensation['op']=='add' && Array(compensation['inputs']).count(node['id'])==1 &&
          Array(compensation['inputs']).count('topup')==1 && topup && topup['op']=='max' && Array(topup['inputs']).count('shortfall')==1 &&
          shortfall && shortfall['op']=='subtract' && shortfall['right']=='guarantee_basis' && basis && basis['op']=='add' && Array(basis['inputs']).count(node['id'])==1
        error('UNSUPPORTED_MECHANISM','Guarantee inclusion requires the supported floor composition') unless valid
      else
        error('UNSUPPORTED_MECHANISM','Each approved event needs exactly one path to its payable or net result') unless count==1
      end
      {'id'=>"event-#{kind}-#{group}",'kind'=>kind,'group'=>group}
    end
    error('RULE_CONFLICT','An event group must have exactly one consumer') unless rule_keys.uniq.size==rule_keys.size
    rules
  end
  def install_netting_proof!(case_id,scenario)
    return unless case_id=='ria'
    raw,body=fixture('ria','netting'); authority=body.fetch('authority')
    error('SCOPE_MISMATCH') unless body['synthetic']==true && authority['status']=='authorized' && authority['debtor']=='ria-harbor' && authority['creditor']=='firm-demo' && authority['currency']=='USD'
    artifact=store!(case_id,scenario,'artifact',id:"#{scenario}-netting-proof",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>'application/json','fixture'=>true},bytes:raw)
    store!(case_id,scenario,'netting_authority',id:authority.fetch('id'),revision:authority.fetch('revision'),status:'accepted',payload:authority,parent:artifact,recorded_at:time!(authority.fetch('recorded_at')))
  end
  # Keep the delivered roster bytes and a separate normalized evidence record.
  # The count is recomputed from that source at read time, never trusted as a
  # policy constant or inferred from the account-month claim.
  def install_account_roster!(case_id,scenario)
    return unless case_id=='ria'
    raw,roster=fixture('ria','account-roster')
    known=time!(roster.fetch('recorded_at'))
    artifact=store!(case_id,scenario,'artifact',id:"#{scenario}-account-roster-artifact",status:'retained',
      payload:{'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>'application/json','fixture'=>true},bytes:raw,recorded_at:known)
    body={'name'=>'account_roster_proof','value'=>{'roster_id'=>roster.fetch('id'),'roster_revision'=>roster.fetch('revision'),
      'source_artifact_id'=>artifact.external_id}}
    store!(case_id,scenario,'fact',id:"#{scenario}-account-roster-proof",status:'accepted',payload:body,parent:artifact,recorded_at:known)
  end
  def eligible_account_count(roster,claim)
    return nil unless roster.is_a?(Hash) && roster['synthetic']==true && roster['id']==claim['roster_id'] &&
      roster['subject']=='ria-harbor' && roster['period']=={'start'=>'2026-09-01','end_exclusive'=>'2026-10-01'} &&
      claim['subject_id']=='ria-harbor' && claim['measurement']=='eligible_account_months' &&
      claim['period_start']=='2026-09-01' && claim['period_end_exclusive']=='2026-10-01' &&
      claim['unit']=='scalar' && claim['basis']=='scalar'
    accounts=roster['accounts']
    return nil unless accounts.is_a?(Array) && accounts.size.between?(1,1000)
    ids=accounts.map { |account| account.is_a?(Hash) && account['id'] }
    return nil unless ids.all? { |id| id.is_a?(String) && id.match?(/\Aharbor-account-[0-9]{3}\z/) } && ids.uniq.size==ids.size
    return nil unless accounts.all? { |account| account['firm']=='ria-harbor' && [true,false].include?(account['eligible']) }
    start_date=Date.iso8601('2026-09-01'); end_date=Date.iso8601('2026-10-01')
    count=accounts.count do |account|
      from=date!(account.fetch('active_from')); until_date=date!(account.fetch('active_to_exclusive'))
      return nil unless from<until_date
      account['eligible']==true && from<=start_date && end_date<=until_date
    end
    return nil unless claim['value'].is_a?(String) && claim['value'].match?(/\A\d+\z/) && Integer(claim['value'])==count
    count
  rescue Economics::Error,KeyError,TypeError,ArgumentError
    nil
  end
  def bootstrap(input,key)
    workbench.guard!('operator')
    workbench.operate('medallion_bootstrap',input,key) do
      CASES.each do |case_id|
        scenario='baseline'
        proof_type=case_id=='advisor' ? 'funding' : 'receipt'
        proof_raw,proof=fixture(case_id,proof_type)
        proof_artifact=store!(case_id,scenario,'artifact',id:"#{case_id}-#{proof_type}-proof",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(proof_raw),'media_type'=>'application/json','fixture'=>true},bytes:proof_raw)
        install_source_proof!(case_id,scenario,proof,proof_artifact)
        install_netting_proof!(case_id,scenario)
        install_account_roster!(case_id,scenario)
        %w[policy facts].each do |type|
          raw,body=fixture(case_id,type)
          artifact=store!(case_id,scenario,'artifact',id:"#{case_id}-#{type}",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>'application/json','fixture'=>true},bytes:raw)
          store!(case_id,scenario,'delivery',id:"delivery-#{case_id}-#{type}",status:'accepted',payload:{'artifact_id'=>artifact.external_id,'received_at'=>'2026-10-01T00:00:00Z','fixture'=>true},parent:artifact)
          if type=='policy'
            p=store!(case_id,scenario,'policy',id:"#{case_id}-policy-v1",status:'published',payload:{'policy'=>install_fixture_rates(case_id,"#{case_id}-policy-v1",body),'rate_configuration_id'=>"#{case_id}-policy-v1",'document_ref'=>{'system'=>'mock_clm','document_id'=>"#{case_id}-fixture-document",'version'=>'v1','status'=>'illustrative'},'event_policies'=>event_policies(body),'fixture'=>true},recorded_at:Time.iso8601('2026-09-01T00:00:00Z'))
            install_fixture_assignment!(case_id,scenario,p)
          else
            body.each do |name,value|
              received=Time.iso8601('2026-10-01T00:00:00Z')
              known=[received,value['recorded_at'] && time!(value['recorded_at'])].compact.max
              store!(case_id,scenario,'fact',id:"#{case_id}-fact-#{name}",status:'accepted',payload:{'name'=>name,'value'=>value,'source_artifact_id'=>artifact.external_id},parent:artifact,recorded_at:known)
            end
          end
        end
      end
      %w[bonus_outside bonus_inside service_credit correction pending_payment confirmed_payment].each { |name| bootstrap_scenario!(name) }
      {'synthetic'=>true,'seeded'=>true}
    end
  end
  def bootstrap_scenario!(scenario)
    case_id=scenario=='service_credit' ? 'ria' : 'advisor'
    basename={'correction'=>'late-correction','pending_payment'=>'pending-payout','confirmed_payment'=>'confirmed-payment'}.fetch(scenario,scenario.tr('_','-')); scenario_path=ROOT.join('scenarios')
    policy_raw=File.binread(scenario_path.join("#{basename}-policy.json")); graph=JSON.parse(policy_raw)
    facts_raw=File.binread(scenario_path.join("#{basename}-facts.json")); facts=JSON.parse(facts_raw)
    proof_type=case_id=='advisor' ? 'funding' : 'receipt'; proof_raw,proof=fixture(case_id,proof_type)
    proof_artifact=store!(case_id,scenario,'artifact',id:"#{scenario}-proof",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(proof_raw),'media_type'=>'application/json','fixture'=>true},bytes:proof_raw)
    install_source_proof!(case_id,scenario,proof,proof_artifact)
    install_netting_proof!(case_id,scenario)
    install_account_roster!(case_id,scenario)
    pa=store!(case_id,scenario,'artifact',id:"#{scenario}-policy-artifact",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(policy_raw),'media_type'=>'application/json','fixture'=>true},bytes:policy_raw)
    fa=store!(case_id,scenario,'artifact',id:"#{scenario}-facts-artifact",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(facts_raw),'media_type'=>'application/json','fixture'=>true},bytes:facts_raw)
    policy_id="#{scenario}-policy-v1"
    policy=store!(case_id,scenario,'policy',id:policy_id,status:'published',payload:{'policy'=>install_fixture_rates(case_id,policy_id,graph),'rate_configuration_id'=>policy_id,
      'document_ref'=>{'system'=>'mock_clm','document_id'=>"#{scenario}-document",'version'=>'v1','status'=>'illustrative'},'event_policies'=>event_policies(graph),'fixture'=>true},parent:pa,recorded_at:Time.iso8601('2026-09-01T00:00:00Z'))
    install_fixture_assignment!(case_id,scenario,policy)
    event_key=facts.find { |_,value| value['collection']=='approved_events' }&.first
    event_fact=event_key && facts.delete(event_key)
    payout_request=facts.delete('payout_request')
    payment_key=facts.find { |_,value| value['collection']=='payment_applications' }&.first
    payment_fact=payment_key && facts.delete(payment_key)
    if scenario=='correction'
      _,baseline=fixture('advisor','facts')
      original=baseline.fetch('cedar_30')
      store!(case_id,scenario,'fact',id:"#{scenario}-fact-cedar_30",status:'accepted',payload:{'name'=>'cedar_30','value'=>original,'source_artifact_id'=>fa.external_id},parent:fa,recorded_at:Time.iso8601('2026-10-01T00:00:00Z'))
    end
    facts.each do |name,value|
      known=[Time.iso8601('2026-10-01T00:00:00Z'),value['recorded_at'] && time!(value['recorded_at'])].compact.max
      store!(case_id,scenario,'fact',id:"#{scenario}-fact-#{name}",status:'accepted',payload:{'name'=>name,'value'=>value,'source_artifact_id'=>fa.external_id},revision:scenario=='correction' && name=='cedar_30' ? 2 : 1,parent:fa,recorded_at:known)
    end
    if event_fact
      now=Time.iso8601('2026-10-03T12:00:00Z')
      event={'id'=>"#{scenario}-event",'revision'=>1,'kind'=>case_id=='advisor' ? 'compensation_entitlement' : 'one_time_credit',
        'amount_minor'=>Integer(event_fact.fetch('value')),'currency'=>'USD','debtor_id'=>'firm-demo',
        'creditor_id'=>case_id=='advisor' ? 'advisor-demo' : 'ria-harbor','subject_id'=>case_id=='advisor' ? 'advisor-demo' : 'ria-harbor',
        'economic_date'=>'2026-09-30','posting_period'=>'2026-10','policy_id'=>policy_id,'policy_hash'=>policy.payload_hash,
        'event_policy_id'=>policy.payload.fetch('event_policies').find { |r| r['kind']==event_fact['kind'] && r['group']==event_fact['group'] }.fetch('id'),
        'reason'=>'Fictional approved adjustment','received_at'=>now.iso8601(6)}
      original=store!(case_id,scenario,'event',id:event['id'],status:'draft',payload:event,recorded_at:now)
      body={'event_id'=>original.external_id,'event_revision'=>original.revision,'event_hash'=>original.payload_hash,'decision'=>'approved','approved_at'=>now.iso8601(6),'role'=>'finance'}
      store!(case_id,scenario,'event_review',id:"#{scenario}-approval",status:'approved',payload:body,parent:original,recorded_at:now)
    elsif payout_request
      now=Time.iso8601('2026-10-03T12:00:00Z')
      event={'id'=>'pending-payout-event','revision'=>1,'kind'=>'payout_request','amount_minor'=>Integer(payout_request.fetch('value')),'currency'=>'USD',
        'debtor_id'=>'firm-demo','creditor_id'=>'advisor-demo','subject_id'=>'advisor-demo','economic_date'=>'2026-09-30','posting_period'=>'2026-10',
        'policy_id'=>policy_id,'policy_hash'=>policy.payload_hash,'reason'=>'Requested payout','received_at'=>now.iso8601(6)}
      store!(case_id,scenario,'event',id:event['id'],status:'pending',payload:event,recorded_at:now)
    end
    result,manifest=evaluate(case_id,scenario,policy,'2026-10-02T23:00:00Z')
    error('INCOMPLETE_SOURCE','Historical fixture cannot be sealed') unless result['status']=='completed'
    run_body={'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'knowledge_cutoff'=>'2026-10-02T23:00:00Z','input_manifest'=>manifest,
      'result'=>result,'implementation_hash'=>workbench.implementation_hash,'synthetic'=>true}
    run=store!(case_id,scenario,'run',id:"#{scenario}-oct2-run",status:'completed',payload:run_body,parent:policy,recorded_at:Time.iso8601('2026-10-02T23:00:00Z'))
    statement=projected_statement(case_id,scenario,run,as_of:'2026-10-02T23:00:00Z').merge('status'=>'sealed','posting_period'=>'2026-10','reason'=>'Historical fixture')
    store!(case_id,scenario,'statement',id:"#{scenario}-oct2-statement",status:'sealed',payload:statement,parent:run,recorded_at:Time.iso8601('2026-10-02T23:00:00Z'))
    if payment_fact
      now=Time.iso8601('2026-10-03T00:00:00Z'); amount=Integer(payment_fact.fetch('value'))
      _,owed=obligation!(case_id,scenario,run.external_id,'payable'); error('ALLOCATION_EXCEEDED') if amount>owed
      payment_raw,payment_proof=fixture('advisor','payment'); payment=payment_proof.fetch('payment')
      error('SOURCE_CONFLICT','Payment fixture does not match applied amount or scope') unless payment_proof['synthetic']==true && payment['status']=='confirmed' && payment['amount_minor']==amount && payment['currency']=='USD' && payment['debtor_id']=='firm-demo' && payment['creditor_id']=='advisor-demo' && time!(payment['observed_at'])==now
      artifact=store!(case_id,scenario,'artifact',id:'confirmed-payment-proof',status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(payment_raw),'media_type'=>'application/json','fixture'=>true},bytes:payment_raw)
      pmt=store!(case_id,scenario,'payment',id:payment['id'],status:'confirmed',payload:payment,parent:artifact,recorded_at:now)
      body={'payment_id'=>pmt.external_id,'payment_revision'=>pmt.revision,'payment_hash'=>pmt.payload_hash,'run_id'=>run.external_id,'run_hash'=>run.payload_hash,
        'output_id'=>'payable','obligation_key'=>obligation_key(case_id,scenario,'payable'),'amount_minor'=>amount,'currency'=>'USD','posting_period'=>'2026-10','reason'=>'Fictional confirmed payment'}
      store!(case_id,scenario,'application',id:'fixture-confirmed-application',status:'confirmed',payload:body,parent:pmt,recorded_at:now)
    end
  end
  def install_fixture_assignment!(case_id,scenario,policy)
    subject=case_id=='advisor' ? 'advisor-demo' : 'ria-harbor'
    product=case_id=='advisor' ? 'advisor-compensation' : 'ria-platform'
    body={'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'subject_id'=>subject,'product_id'=>product,'starts_on'=>'2026-09-01','ends_on'=>'2026-10-01','fixture'=>true}
    store!(case_id,scenario,'assignment',id:"#{scenario}-assignment",status:'published',payload:body,parent:policy,subject_id:subject,product_id:product,
      starts_on:'2026-09-01',ends_on:'2026-10-01',recorded_at:Time.iso8601('2026-09-01T00:00:00Z'))
  end
  def assignment_for(case_id,scenario,cutoff)
    subject=case_id=='advisor' ? 'advisor-demo' : 'ria-harbor'; product=case_id=='advisor' ? 'advisor-compensation' : 'ria-platform'
    known=source(case_id,scenario,'assignment').where(subject_id:subject,product_id:product,status:'published').where('recorded_at <= ?',time!(cutoff))
    version=known.maximum(:schedule_version)
    error('UNRESOLVED_MAPPING','No authorized assignment known at cutoff') unless version
    matches=known.where(schedule_version:version).where('starts_on <= ? AND (ends_on IS NULL OR ends_on >= ?)', '2026-09-01','2026-10-01').to_a
    error('UNRESOLVED_MAPPING','No unique authorized policy assignment for service period') unless matches.one?
    matches.first
  end
  def assign_policy(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_assign_policy',input,key) do
      policy=policy!(case_id,scenario,input.fetch('policy_id'))
      error('FORBIDDEN') unless published?(policy) && input['policy_hash']==policy.payload_hash
      subject=case_id=='advisor' ? 'advisor-demo' : 'ria-harbor'; product=case_id=='advisor' ? 'advisor-compensation' : 'ria-platform'
      error('SCOPE_MISMATCH') unless input['subject_id']==subject && input['product_id']==product
      starts=input.fetch('starts_on'); date!(starts); ends=input['ends_on']; date!(ends) if ends
      error('INVALID_INTERVAL') if ends && ends<=starts
      publication=source(case_id,scenario,'publication').where("payload->>'policy_id' = ?",policy.external_id).order(:id).last
      error('FORBIDDEN','Assignment cannot precede publication effective date') if publication && starts<publication.payload['effective_from']
      existing=source(case_id,scenario,'assignment').where(subject_id:subject,product_id:product,status:'published')
      version=existing.maximum(:schedule_version) || 1
      superseded=nil
      if input['supersedes_assignment_id']
        superseded=get!(case_id,scenario,'assignment',input['supersedes_assignment_id'])
        error('HASH_CHANGED','Assignment schedule changed') unless superseded.payload_hash==input['expected_assignment_hash'] && superseded.schedule_version==version && superseded.subject_id==subject && superseded.product_id==product
        error('UNSUPPORTED_MECHANISM','Replace the complete single-interval schedule') unless existing.where(schedule_version:version).count==1 && superseded.starts_on.iso8601==starts && superseded.ends_on&.iso8601==ends
        version+=1
      end
      id="assignment-#{SecureRandom.uuid}"; body={'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'subject_id'=>subject,'product_id'=>product,'starts_on'=>starts,'ends_on'=>ends,
        'schedule_version'=>version,'supersedes_assignment_id'=>superseded&.external_id,'supersedes_hash'=>superseded&.payload_hash}
      store!(case_id,scenario,'assignment',id:id,status:'published',payload:body,parent:policy,subject_id:subject,product_id:product,starts_on:starts,ends_on:ends,schedule_version:version)
      {'id'=>id,'synthetic'=>true}
    end
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::ExclusionViolation)
    error('RULE_CONFLICT','Overlapping assignments require a new nonoverlapping version')
  end
  def policy!(case_id,scenario_id,id)
    get!(case_id,scenario_id,'policy',id)
  end
  def published?(policy)
    policy.status=='published' || source(policy.case_id,policy.scenario_id,'publication').where("payload->>'policy_id' = ?",policy.external_id).exists?
  end
  def facts(case_id,scenario_id,cutoff)
    rows=source(case_id,scenario_id,'fact').where('recorded_at <= ?',time!(cutoff))
      .select('DISTINCT ON (external_id) medallion_evidence.*').order(:external_id,revision: :desc,id: :desc).to_a
    error('INCOMPLETE_SOURCE') if rows.empty?
    known=rows.each_with_object({}) do |row,out|
      name=row.payload.fetch('name'); value=row.payload.fetch('value')
      next if name=='account_roster_proof'
      enriched=value.merge('tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],'id'=>row.external_id,
        'revision'=>row.revision,'recorded_at'=>row.recorded_at.iso8601(6),'approved'=>true)
      enriched['currency']='USD' if value['unit']=='USD_minor'
      out[name]=enriched
    end
    if case_id=='advisor' && known.key?('funded_coverage')
      right=source(case_id,scenario_id,'coverage_right').where('recorded_at <= ?',time!(cutoff)).order(:id).last
      funding=right && source(case_id,scenario_id,'funding').find_by(id:right.parent_id,status:'confirmed')
      funding=nil if funding && funding.recorded_at>time!(cutoff)
      reversal=funding && source(case_id,scenario_id,'funding_reversal').where(parent_id:funding.id).where('recorded_at <= ?',time!(cutoff)).order(:id).last
      if reversal
        rows.concat([funding,right,reversal]); known.delete('funded_coverage')
      elsif right && funding
        error('SOURCE_CONFLICT','Funding evidence differs from coverage fact') unless right.payload['funding_id']==funding.external_id && right.payload['available_minor']<=funding.payload['amount_minor'] && Rational(known['funded_coverage']['value'])==right.payload['available_minor']
        known['funded_coverage']={'id'=>right.external_id,'revision'=>right.revision,'tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],
          'recorded_at'=>right.recorded_at.iso8601(6),'approved'=>true,'status'=>'confirmed','direction'=>'firm_to_advisor','right'=>'eligible','funding'=>'evidenced',
          'unit'=>'USD_minor','currency'=>'USD','basis'=>'assessed','value'=>right.payload['available_minor'].to_s, 'evidence_refs'=>[funding.external_id,right.external_id]}
        rows.concat([funding,right])
      else
        known.delete('funded_coverage')
      end
    elsif case_id=='ria' && known.key?('receipt')
      receipt=source(case_id,scenario_id,'receipt').where(status:'confirmed').where('recorded_at <= ?',time!(cutoff)).order(:id).last
      allocations=receipt ? source(case_id,scenario_id,'receipt_allocation').where(parent_id:receipt.id,status:'confirmed').where('recorded_at <= ?',time!(cutoff)).order(:external_id).to_a : []
      reversal=receipt && source(case_id,scenario_id,'receipt_reversal').where(parent_id:receipt.id).where('recorded_at <= ?',time!(cutoff)).order(:id).last
      if reversal
        rows.concat([receipt,reversal,*allocations])
        known.delete('receipt')
      elsif receipt && allocations.size==3
        linked=allocations.all? do |a|
          report=known["reported_#{a.payload['report_line']}_savvy"]
          report && Rational(report['value'])==a.payload['amount_minor'] && a.payload['subject']=='ria-harbor' && a.payload['currency']=='USD'
        end
        error('SOURCE_CONFLICT','Receipt allocations differ from reported lines') unless linked && Rational(known['receipt']['value'])==receipt.payload['amount_minor'] && assessed_sum(allocations.map { |a| a.payload['amount_minor'] })==receipt.payload['amount_minor']
        known['receipt']={'id'=>receipt.external_id,'revision'=>receipt.revision,'tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],
          'recorded_at'=>receipt.recorded_at.iso8601(6),'approved'=>true,'status'=>'confirmed','direction'=>'network_to_savvy','allocated_to'=>'harbor',
          'unit'=>'USD_minor','currency'=>'USD','basis'=>'source_reported','value'=>receipt.payload['amount_minor'].to_s, 'evidence_refs'=>[receipt.external_id,*allocations.map(&:external_id),*allocations.map { |a| "reported_#{a.payload['report_line']}_savvy" }]}
        rows.concat([receipt,*allocations])
      else
        known.delete('receipt')
      end
    end
    if case_id=='ria' && known.key?('account_months')
      proof=rows.find { |row| row.payload['name']=='account_roster_proof' }
      artifact=proof && source(case_id,scenario_id,'artifact').find_by(id:proof.parent_id)
      count=nil
      if artifact && artifact.recorded_at<=time!(cutoff) && artifact.original_bytes && Digest::SHA256.hexdigest(artifact.original_bytes)==artifact.payload['sha256']
        begin
          roster=JSON.parse(artifact.original_bytes)
          claim=known['account_months']
          if proof.payload.dig('value','roster_id')==roster['id'] && proof.payload.dig('value','roster_revision')==roster['revision'] && proof.payload.dig('value','source_artifact_id')==artifact.external_id && time!(roster.fetch('recorded_at'))<=time!(cutoff)
            count=eligible_account_count(roster,claim)
          end
        rescue JSON::ParserError,Economics::Error,KeyError,TypeError
          count=nil
        end
      end
      if count
        known['account_months']=known['account_months'].merge('value'=>count.to_s,'evidence_refs'=>[artifact.external_id,proof.external_id])
        rows << artifact
      else
        known.delete('account_months')
      end
    end
    if case_id=='ria' && known.key?('netting_authority')
      authority=source(case_id,scenario_id,'netting_authority').where('recorded_at <= ?',time!(cutoff)).order(:id).last
      if authority
        a=authority.payload
        error('SCOPE_MISMATCH') unless a['status']=='authorized' && a['debtor']=='ria-harbor' && a['creditor']=='firm-demo' && a['currency']=='USD'
        known['netting_authority']=a.merge('tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],'id'=>authority.external_id,'revision'=>authority.revision,'recorded_at'=>authority.recorded_at.iso8601(6),'approved'=>true)
        rows << authority
      else
        known.delete('netting_authority')
      end
    end
    [rows,known]
  end
  def context(case_id,cutoff)
    {'tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],'scenario'=>case_id,'service_start'=>'2026-09-01',
      'service_end_exclusive'=>'2026-10-01','knowledge_cutoff'=>cutoff}
  end
  def evaluate(case_id,scenario_id,policy,cutoff,policy_cutoff:nil)
    fact_rows,known=facts(case_id,scenario_id,cutoff)
    assignment=assignment_for(case_id,scenario_id,cutoff)
    rate_config=policy.payload['rate_configuration_id']
    rates=CommercialRate.where(**scope,configuration_id:rate_config).order(:external_id).map do |rate|
      identity={'id'=>rate.external_id,'configuration_id'=>rate.configuration_id,'revision'=>1,'tenant_id'=>rate.tenant_id,'entity_id'=>rate.entity_id,
        'recorded_at'=>rate.recorded_at.iso8601(6),'valid_from'=>rate.starts_on.iso8601,'valid_to'=>rate.ends_on&.iso8601,'approved'=>true,
        'broker_id'=>rate.broker_id,'component'=>rate.component,'kind'=>rate.kind,'selector'=>rate.selector,'priority'=>rate.priority,'signup_within_days'=>rate.signup_within_days,'payer_id'=>rate.payer_id,'payee_id'=>rate.payee_id,
        'unit'=>'scalar','basis'=>'scalar','value'=>"#{rate.numerator}/#{rate.denominator}"}
      identity
    end
    graph=Economics::Canonical.copy(policy.payload.fetch('policy'))
    reviews=source(case_id,scenario_id,'event_review').where(status:'approved').where('recorded_at <= ?',time!(cutoff)).order(:id).to_a
    approved=reviews.map do |review|
      event=source(case_id,scenario_id,'event').find_by(id:review.parent_id)
      error('SOURCE_CONFLICT') unless event && event.recorded_at<=time!(cutoff) && review.payload['event_hash']==event.payload_hash
      [event,review]
    end
    # A replacement supersedes the original only once that version is approved.
    approved.group_by { |event,_| event.external_id }.values.map { |versions| versions.max_by { |event,_| event.revision } }.each do |event,review|
      next if event.payload['kind']=='payout_request'
      approved_policy=policy!(case_id,scenario_id,event.payload.fetch('policy_id'))
      error('SOURCE_CONFLICT','Event approval policy changed') unless approved_policy.payload_hash==event.payload['policy_hash']
      approved_rule=approved_policy.payload.fetch('event_policies',[]).find { |r| r['id']==event.payload['event_policy_id'] && r['kind']==event.payload['kind'] }
      rule=policy.payload.fetch('event_policies',[]).find { |r| r==approved_rule }
      unless policy.external_id==approved_policy.external_id || (policy_cutoff && rule)
        error('UNSUPPORTED_MECHANISM','Hypothetical policy does not accept the approved event treatment')
      end
      group=rule && rule['group']
      supported=graph.fetch('nodes').any? { |n| n['op']=='sum_facts' && n['collection']=='approved_events' && n.dig('selector','kind')==event.payload['kind'] && n.dig('selector','group')==group }
      error('UNSUPPORTED_MECHANISM','Policy does not declare this approved event') unless supported && group
      key="event:#{event.external_id}:#{event.revision}"
      known[key]={'id'=>event.external_id,'revision'=>event.revision,'tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],
        'recorded_at'=>review.recorded_at.iso8601(6),'approved'=>true,'status'=>'approved','unit'=>'USD_minor','currency'=>'USD','basis'=>'assessed',
        'collection'=>'approved_events','kind'=>event.payload['kind'],'group'=>group,'economic_date'=>event.payload['economic_date'],'value'=>event.payload['amount_minor'].to_s}
      fact_rows.concat([event,review])
    end
    if graph.fetch('nodes').any? { |n| n['op']=='sum_facts' && n['collection']=='payment_applications' }
      active_applications(case_id,scenario_id,as_of:cutoff).each do |application|
        next unless application.payload['obligation_key']==obligation_key(case_id,scenario_id,case_id=='advisor' ? 'payable' : 'net')
        payment=source(case_id,scenario_id,'payment').find_by(id:application.parent_id,status:'confirmed')
        error('SOURCE_CONFLICT','Payment application lacks confirmed source') unless payment && payment.recorded_at<=time!(cutoff) && application.payload['payment_hash']==payment.payload_hash
        error('SCOPE_MISMATCH') unless case_id=='advisor' && payment.payload['debtor_id']=='firm-demo' && payment.payload['creditor_id']=='advisor-demo' && payment.payload['currency']=='USD'
        key="application:#{application.external_id}:#{application.revision}"
        known[key]={'id'=>application.external_id,'revision'=>application.revision,'tenant_id'=>scope[:tenant_id],'entity_id'=>scope[:entity_id],
          'recorded_at'=>application.recorded_at.iso8601(6),'approved'=>true,'status'=>'applied','direction'=>'firm_to_advisor','obligation'=>'advisor-september',
          'collection'=>'payment_applications','unit'=>'USD_minor','currency'=>'USD','basis'=>'assessed','value'=>application.payload['amount_minor'].to_s}
        fact_rows.concat([payment,application])
      end
    end
    graph['rate_rows']=rates.to_h { |r| [r['id'],r] }
    input={'facts'=>known,'assignment'=>{'id'=>assignment.external_id,'hash'=>assignment.payload_hash},'source_evidence'=>fact_rows.sort_by { |r| [r.kind,r.external_id,r.revision] }.map { |r| {'id'=>r.external_id,'revision'=>r.revision,'hash'=>r.payload_hash} }}
    ctx=context(case_id,cutoff)
    if policy_cutoff
      ctx['policy_knowledge_cutoff']=policy_cutoff
      ctx['hypothetical']=true
    end
    result=Economics::Engine.new.evaluate(policy_bundle:{'policy'=>graph,'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'approved'=>published?(policy)},input_manifest:input,context:ctx)
    [result,input]
  end
  def save_policy(input,key)
    workbench.guard!('operator','finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_save_policy',input,key) do
      base=policy!(case_id,scenario,input.fetch('base_id'))
      error('HASH_CHANGED') unless input['expected_base_hash']==base.payload_hash && published?(base)
      policy=input.fetch('policy'); error('VALIDATION_ERROR','Rate values must come from the shared rate store') if policy.key?('rate_rows'); Economics::Engine.new.validate(policy:policy)
      id="policy-#{SecureRandom.uuid}"
      changes=input.fetch('rates',[])
      fields=%w[id numerator denominator name kind starts_on ends_on selector signup_within_days priority component payer_id payee_id broker_id commercial_group]
      error('VALIDATION_ERROR') unless changes.is_a?(Array) && changes.all? { |x| x.is_a?(Hash) && (x.keys-fields).empty? && x.key?('id') }
      changes.each { |x| id!(x['id']) }
      error('DUPLICATE_SOURCE') unless changes.map { |x| x['id'] }.uniq.size==changes.size
      base_rates=CommercialRate.where(**scope,configuration_id:base.payload['rate_configuration_id']).order(:id).to_a
      mapped=base_rates.to_h { |r| [r.external_id,r.attributes.except('id','configuration_id','recorded_at')] }
      changes.each do |change|
        rate_id=change['id']; existing=mapped[rate_id]
        attrs=existing ? existing.dup : scope.stringify_keys.merge('external_id'=>rate_id,'unit'=>'ratio','selector'=>{})
        attrs.merge!(change.except('id'))
        %w[name kind starts_on component broker_id numerator denominator].each { |field| error('VALIDATION_ERROR',"Missing rate #{field}") if attrs[field].nil? }
        error('SCOPE_MISMATCH') unless attrs['broker_id']==(case_id=='advisor' ? 'advisor-demo' : 'ria-harbor')
        error('UNSUPPORTED_MECHANISM') unless %w[standard promotion targeted_promotion].include?(attrs['kind']) && attrs['unit']=='ratio'
        id!(attrs['component']); error('VALIDATION_ERROR') unless attrs['name'].is_a?(String) && attrs['name'].strip.length.between?(1,100)
        n=Economics::Engine.integer!(attrs['numerator'],'numerator',max:1_000_000); d=Economics::Engine.integer!(attrs['denominator'],'denominator',min:1,max:1_000_000)
        error('INVALID_RATE') if n>d
        start=date!(attrs['starts_on'].to_s); finish=attrs['ends_on'] && date!(attrs['ends_on'].to_s)
        error('INVALID_INTERVAL') if finish && finish<=start
        error('UNSUPPORTED_DIMENSION') unless attrs['selector'].is_a?(Hash) && attrs['selector'].keys.all? { |k| %w[customer_type product_type].include?(k) } && attrs['selector'].values.all? { |v| v.is_a?(String) && v.match?(/\A[a-zA-Z0-9_-]{1,100}\z/) }
        Economics::Engine.integer!(attrs['signup_within_days'],'signup_within_days',min:1,max:365) unless attrs['signup_within_days'].nil?
        Economics::Engine.integer!(attrs['priority'],'priority',min:-1000,max:1000) unless attrs['priority'].nil?
        allowed_parties=PARTIES.fetch(case_id)+['client']
        error('SCOPE_MISMATCH') unless %w[payer_id payee_id].all? { |k| attrs[k].nil? || allowed_parties.include?(attrs[k]) }
        mapped[rate_id]=attrs
      end
      mapped.each_value do |attrs|
        CommercialRate.create!(attrs.merge('configuration_id'=>id,'recorded_at'=>Time.current))
      end
      p={'policy'=>policy,'rate_configuration_id'=>id,'event_policies'=>event_policies(policy),'base_id'=>base.external_id,'base_hash'=>base.payload_hash,'reason'=>reason!(input['reason'])}
      row=store!(case_id,scenario,'policy',id:id,status:'draft',payload:p,parent:base)
      {'id'=>id,'hash'=>row.payload_hash,'status'=>'draft','version'=>policy['version']}
    end
  end
  def compare(input,key)
    workbench.guard!('operator','finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id']); cutoff=input.fetch('knowledge_cutoff'); time!(cutoff)
    workbench.operate('medallion_compare',input,key) do
      base=policy!(case_id,scenario,input.fetch('baseline_policy_id')); proposed=policy!(case_id,scenario,input.fetch('proposed_policy_id'))
      error('FORBIDDEN') unless published?(base)
      policy_cutoff=Time.current.iso8601(6)
      before,manifest=evaluate(case_id,scenario,base,cutoff,policy_cutoff:policy_cutoff); after,other=evaluate(case_id,scenario,proposed,cutoff,policy_cutoff:policy_cutoff)
      error('HASH_CHANGED') unless manifest==other
      id="comparison-#{SecureRandom.uuid}"; body={'baseline_policy_id'=>base.external_id,'baseline_hash'=>base.payload_hash,'proposed_policy_id'=>proposed.external_id,'proposed_hash'=>proposed.payload_hash,
        'knowledge_cutoff'=>cutoff,'policy_knowledge_cutoff'=>policy_cutoff,'hypothetical'=>true,'implementation_hash'=>workbench.implementation_hash,'input_manifest_hash'=>Economics::Canonical.hash(manifest),'baseline'=>before,'proposed'=>after}
      row=store!(case_id,scenario,'comparison',id:id,status:before['status']=='completed' && after['status']=='completed' ? 'completed' : 'blocked',payload:body,parent:proposed)
      {'id'=>id,'hash'=>row.payload_hash,'status'=>row.status}.merge(body)
    end
  end
  def review_policy(input,key)
    workbench.guard!('finance','legal'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_review_policy',input,key) do
      policy=policy!(case_id,scenario,input.fetch('policy_id')); comparison=get!(case_id,scenario,'comparison',input.fetch('comparison_id'))
      error('BLOCKED_REVIEW') unless comparison.status=='completed' && comparison.payload['proposed_policy_id']==policy.external_id && comparison.payload['proposed_hash']==policy.payload_hash
      error('HASH_CHANGED','Calculation implementation changed') unless comparison.payload['implementation_hash']==workbench.implementation_hash
      ref=input['document_ref']; error('VALIDATION_ERROR','Use a reviewed mock document') unless ref.is_a?(Hash) && ref.keys.sort==%w[document_id status system version] && ref['system']=='mock_clm' && ref['status']=='reviewed_for_demo' && %w[document_id version].all? { |k| ref[k].is_a?(String) && ref[k].match?(/\A[a-zA-Z0-9_-]{1,100}\z/) }
      error('VALIDATION_ERROR') unless input['decision']=='approved_for_demo'
      id="review-#{SecureRandom.uuid}"; body={'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'comparison_id'=>comparison.external_id,'comparison_hash'=>comparison.payload_hash,'role'=>workbench.role,'document_ref'=>ref,'decision'=>'approved_for_demo'}
      store!(case_id,scenario,'review',id:id,status:'approved',payload:body,parent:policy)
      {'id'=>id}.merge(body)
    end
  end
  def publish(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_publish',input,key) do
      p=policy!(case_id,scenario,input.fetch('policy_id')); c=get!(case_id,scenario,'comparison',input.fetch('comparison_id'))
      error('HASH_CHANGED','Calculation implementation changed') unless c.payload['implementation_hash']==workbench.implementation_hash
      error('BLOCKED_REVIEW') unless c.status=='completed' && c.payload['proposed_policy_id']==p.external_id && c.payload['proposed_hash']==p.payload_hash
      base=policy!(case_id,scenario,p.payload.fetch('base_id')); error('HASH_CHANGED') unless base.payload_hash==p.payload['base_hash'] && published?(base)
      effective=input.fetch('effective_from'); date!(effective)
      # Read-model publications share the immutable evidence store, but cannot
      # establish policy chronology or shadow an approved commercial version.
      publications=source(case_id,scenario,'publication').where("payload->>'policy_id' IS NOT NULL AND payload->>'effective_from' IS NOT NULL").order(:id).to_a
      error('RULE_CONFLICT','A later or same-date publication exists') if publications.any? { |r| r.payload['effective_from']>=effective }
      previous=publications.select { |r| r.payload['effective_from']<effective }.max_by { |r| r.payload['effective_from'] }
      latest=previous ? previous.payload['policy_id'] : "#{case_id}-policy-v1"
      error('HASH_CHANGED','A newer published base exists') unless latest==base.external_id
      reviews=source(case_id,scenario,'review').where(status:'approved').map(&:payload).select { |r| r['policy_hash']==p.payload_hash && r['comparison_hash']==c.payload_hash }
      pair=reviews.select { |r| r['role']=='finance' }.product(reviews.select { |r| r['role']=='legal' }).find { |a,b| a['document_ref']==b['document_ref'] }
      error('REVIEW_REQUIRED') unless pair
      before,manifest=evaluate(case_id,scenario,base,c.payload['knowledge_cutoff'],policy_cutoff:c.payload['policy_knowledge_cutoff'])
      after,_=evaluate(case_id,scenario,p,c.payload['knowledge_cutoff'],policy_cutoff:c.payload['policy_knowledge_cutoff'])
      _,current_manifest=evaluate(case_id,scenario,base,Time.current.iso8601(6),policy_cutoff:c.payload['policy_knowledge_cutoff'])
      unless Economics::Canonical.hash(manifest)==c.payload['input_manifest_hash'] && Economics::Canonical.hash(current_manifest)==c.payload['input_manifest_hash'] &&
          before['policy_manifest_hash']==c.payload.dig('baseline','policy_manifest_hash') && after['policy_manifest_hash']==c.payload.dig('proposed','policy_manifest_hash')
        error('HASH_CHANGED','Source or policy dependencies changed')
      end
      id="publication-#{SecureRandom.uuid}"; body={'policy_id'=>p.external_id,'policy_hash'=>p.payload_hash,'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'document_ref'=>pair[0]['document_ref'],'effective_from'=>effective}
      date!(body['effective_from']); store!(case_id,scenario,'publication',id:id,status:'published',payload:body,parent:p)
      {'id'=>id,'synthetic'=>true}
    end
  end
  def evaluate_case(input,key)
    workbench.guard!('operator','finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id']); cutoff=input.fetch('knowledge_cutoff'); time!(cutoff)
    workbench.operate('medallion_evaluate',input,key) do
      policy=policy!(case_id,scenario,input.fetch('policy_id')); error('FORBIDDEN','Policy is not published') unless published?(policy)
      assignment=assignment_for(case_id,scenario,cutoff)
      error('FORBIDDEN','Policy is not assigned for this service period') unless assignment.payload['policy_id']==policy.external_id && assignment.payload['policy_hash']==policy.payload_hash
      error('FORBIDDEN','Policy was not known by cutoff') if policy.recorded_at>time!(cutoff)
      if policy.status!='published'
        publication=source(case_id,scenario,'publication').where("payload->>'policy_id' = ?",policy.external_id).order(:id).last
        error('FORBIDDEN','Policy was not published at cutoff or effective for the service period') unless publication && publication.recorded_at<=time!(cutoff) && publication.payload['effective_from']<='2026-09-01'
      end
      result,manifest=evaluate(case_id,scenario,policy,cutoff)
      id="run-#{SecureRandom.uuid}"; body={'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'knowledge_cutoff'=>cutoff,
        'input_manifest'=>manifest,'result'=>result,'implementation_hash'=>workbench.implementation_hash,'synthetic'=>true}
      row=store!(case_id,scenario,'run',id:id,status:result['status']=='completed' ? 'completed' : 'blocked',payload:body,parent:policy)
      {'id'=>id,'status'=>row.status,'result'=>result,'synthetic'=>true}
    end
  end
  def view(workspace:,case_id:,run_id:nil,scenario_id:nil)
    MedallionPresenter.new(workbench).view(workspace:workspace,case_id:case_id,run_id:run_id,scenario_id:scenario_id)
  end
  PARTIES={'advisor'=>%w[firm-demo advisor-demo], 'ria'=>%w[firm-demo ria-harbor network-fixture]}.freeze
  EVENT_KINDS=%w[one_time_charge one_time_credit compensation_entitlement payout_request].freeze
  def event_input!(input,case_id)
    event=input.fetch('event'); error('VALIDATION_ERROR') unless event.is_a?(Hash)
    allowed=%w[id revision kind amount_minor currency debtor_id creditor_id subject_id reason economic_date posting_period policy_id event_policy_id original_id original_revision original_hash reason_code]
    error('VALIDATION_ERROR','Unsupported event fields') unless (event.keys-allowed).empty?
    id!(event.fetch('id')); revision=Economics::Engine.integer!(event.fetch('revision'),'revision',min:1)
    error('UNSUPPORTED_MECHANISM') unless EVENT_KINDS.include?(event['kind'])
    Economics::Engine.integer!(event['amount_minor'],'amount_minor',min:1)
    error('UNIT_MISMATCH') unless event['currency']=='USD'
    directions={
      ['advisor','compensation_entitlement']=>%w[firm-demo advisor-demo],
      ['advisor','payout_request']=>%w[firm-demo advisor-demo],
      ['ria','one_time_charge']=>%w[ria-harbor firm-demo],
      ['ria','one_time_credit']=>%w[firm-demo ria-harbor]
    }
    error('SCOPE_MISMATCH') unless directions[[case_id,event['kind']]]==[event['debtor_id'],event['creditor_id']]
    expected_subject=case_id=='advisor' ? 'advisor-demo' : 'ria-harbor'
    error('SCOPE_MISMATCH') unless event['subject_id']==expected_subject
    economic=date!(event.fetch('economic_date'))
    error('INVALID_DATE','Event must belong to the service period') unless Date.iso8601('2026-09-01')<=economic && economic<Date.iso8601('2026-10-01')
    error('INVALID_DATE','Posting period must be YYYY-MM') unless event['posting_period'].is_a?(String) && event['posting_period'].match?(/\A\d{4}-\d{2}\z/) && date!(event['posting_period']+'-01')
    reason!(event['reason']); id!(event.fetch('policy_id'))
    id!(event['original_id']) if event['original_id']
    event.merge('revision'=>revision)
  end
  def submit_event(input,key)
    workbench.guard!('operator','finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_submit_event',input,key) do
      event=event_input!(input,case_id); policy=policy!(case_id,scenario,event['policy_id'])
      error('FORBIDDEN','Event policy must be published') unless published?(policy)
      unless event['kind']=='payout_request'
        rule=policy.payload.fetch('event_policies',[]).find { |r| r['id']==event['event_policy_id'] && r['kind']==event['kind'] }
        error('UNRESOLVED_MAPPING','Select a published event policy') unless rule
      end
      error('PERIOD_LOCKED') if MedallionEvidence.where(**scope,kind:'period_lock').where("payload->>'posting_period' = ?",event['posting_period']).exists?
      existing=source(case_id,scenario,'event').where(external_id:event['id']).order(:revision).last
      if existing && existing.revision!=event['revision']
        error('SOURCE_CONFLICT','A replacement must reference its original revision and hash') unless event['original_id']==existing.external_id && event['original_revision']==existing.revision && event['original_hash']==existing.payload_hash && event['revision']==existing.revision+1
      end
      payload=event.merge('received_at'=>Time.current.iso8601(6),'policy_hash'=>policy.payload_hash)
      # A retry by source identity compares the submitted business fields, not arrival time.
      if existing && existing.revision==event['revision']
        error('SOURCE_CONFLICT') unless existing.payload.except('received_at','policy_hash')==event
        delivery_id="event-delivery-#{SecureRandom.uuid}"
        store!(case_id,scenario,'delivery',id:delivery_id,status:'accepted',payload:{'event_id'=>existing.external_id,'event_revision'=>existing.revision,'event_hash'=>existing.payload_hash,'duplicate'=>true,'received_at'=>Time.current.iso8601(6)},parent:existing)
        next {'id'=>existing.external_id,'revision'=>existing.revision,'hash'=>existing.payload_hash,'status'=>'draft'}
      end
      row=store!(case_id,scenario,'event',id:event['id'],revision:event['revision'],status:'draft',payload:payload,parent:existing,subject_id:event['subject_id'])
      delivery_id="event-delivery-#{SecureRandom.uuid}"
      store!(case_id,scenario,'delivery',id:delivery_id,status:'accepted',payload:{'event_id'=>row.external_id,'event_revision'=>row.revision,'event_hash'=>row.payload_hash,'duplicate'=>false,'received_at'=>row.recorded_at.iso8601(6)},parent:row)
      {'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'status'=>'draft'}
    end
  end
  def review_event(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_review_event',input,key) do
      event=get!(case_id,scenario,'event',input.fetch('event_id'),revision:input.fetch('revision'))
      error('HASH_CHANGED') unless input['expected_hash']==event.payload_hash
      error('VALIDATION_ERROR') unless %w[approved rejected].include?(input['decision'])
      error('PERIOD_LOCKED') if MedallionEvidence.where(**scope,kind:'period_lock').where("payload->>'posting_period' = ?",event.payload['posting_period']).exists?
      error('SOURCE_CONFLICT','This event version already has a decision') if source(case_id,scenario,'event_review').where(parent_id:event.id).exists?
      id="event-review-#{SecureRandom.uuid}"; now=Time.current
      body={'event_id'=>event.external_id,'event_revision'=>event.revision,'event_hash'=>event.payload_hash,'decision'=>input['decision'],'approved_at'=>now.iso8601(6),'role'=>workbench.role}
      store!(case_id,scenario,'event_review',id:id,status:input['decision'],payload:body,parent:event,recorded_at:now)
      {'id'=>id,'status'=>input['decision'],'event_hash'=>event.payload_hash}
    end
  end
  def assessed_sum(values)
    nodes=values.each_with_index.map { |amount,i| {'id'=>"v#{i}",'op'=>'literal','unit'=>'USD_minor','basis'=>'assessed','role'=>'intermediate','value'=>amount.to_s} }
    return 0 if nodes.empty?
    nodes << {'id'=>'total','op'=>'add','unit'=>'USD_minor','basis'=>'assessed','role'=>'terminal','inputs'=>nodes.map { |n| n['id'] }}
    result=Economics::Engine.new.evaluate_program(policy:{'version'=>'statement-sum-v1','nodes'=>nodes},facts:{})
    Rational(result['terminal_outputs'].first.fetch('value')).to_i
  end
  def assessed_difference(left,right)
    nodes=[{'id'=>'left','op'=>'literal','unit'=>'USD_minor','basis'=>'assessed','role'=>'intermediate','value'=>left.to_s},
      {'id'=>'right','op'=>'literal','unit'=>'USD_minor','basis'=>'assessed','role'=>'intermediate','value'=>right.to_s},
      {'id'=>'balance','op'=>'subtract','unit'=>'USD_minor','basis'=>'assessed','role'=>'terminal','left'=>'left','right'=>'right'}]
    result=Economics::Engine.new.evaluate_program(policy:{'version'=>'statement-difference-v1','nodes'=>nodes},facts:{})
    Rational(result['terminal_outputs'].first.fetch('value')).to_i
  end
  def ingest_delivery(input,key)
    workbench.guard!('operator','finance')
    case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    source_kind=input.fetch('source_kind'); source_id=id!(input.fetch('source_id'))
    revision=Economics::Engine.integer!(input.fetch('revision'),'revision',min:1)
    raw=input.fetch('raw_json')
    error('VALIDATION_ERROR','Supply bounded UTF-8 fixture JSON') unless raw.is_a?(String) && raw.valid_encoding? && raw.bytesize.between?(1,262_144)
    error('UNSUPPORTED_MECHANISM') unless %w[balance signup network_report].include?(source_kind)
    workbench.operate('medallion_ingest_delivery',input,key) do
      bytes=raw.b; received=Time.current; artifact_id="artifact-#{SecureRandom.uuid}"
      artifact=store!(case_id,scenario,'artifact',id:artifact_id,status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(bytes),'media_type'=>'application/json','source_kind'=>source_kind},bytes:bytes,recorded_at:received)
      outcome='accepted'; code=nil; updates=[]; content_hash=nil
      begin
        body=JSON.parse(raw)
        unless body.is_a?(Hash) && body.keys.sort==%w[records revision source_id synthetic] && body['synthetic']==true && body['source_id']==source_id && body['revision']==revision && body['records'].is_a?(Array) && body['records'].size.between?(1,100)
          error('VALIDATION_ERROR','Invalid synthetic delivery envelope')
        end
        content_hash=Economics::Canonical.hash(body)
        prior=source(case_id,scenario,'delivery').where(status:'accepted').where("payload->>'source_id' = ? AND payload->>'source_revision' = ?",source_id,revision.to_s).order(:id).last
        if prior
          if prior.payload['content_hash']==content_hash
            outcome='duplicate'
          else
            error('SOURCE_CONFLICT','Source identity and revision already contain different content')
          end
        else
          names=[]
          body['records'].each do |record|
            error('VALIDATION_ERROR') unless record.is_a?(Hash) && record.keys.sort==%w[name value] && record['name'].is_a?(String)
            name=record['name']; names << name
            permitted=case source_kind
            when 'balance' then case_id=='advisor' && name.match?(/\A(?:cedar|maple)_\d{2}\z/)
            when 'signup' then case_id=='advisor' && name=='signup'
            when 'network_report' then case_id=='ria' && name.match?(/\A(?:reported_(?:cash|margin|lending)_savvy|lending_(?:gross|investor|network|savvy)_report)\z/)
            end
            error('UNRESOLVED_MAPPING','Only known fixture source fields are allowed') unless permitted
            previous=source(case_id,scenario,'fact').where("payload->>'name' = ?",name).order(revision: :desc,id: :desc).first
            error('NOT_FOUND','Unknown fixture fact') unless previous
            error('SOURCE_CONFLICT','New source revision must advance the fact revision') unless revision>previous.revision
            value=Economics::Canonical.copy(previous.payload.fetch('value'))
            if source_kind=='signup'
              date!(record['value']); value['date']=record['value']
            else
              v=record['value']; error('INVALID_NUMBER') unless v.is_a?(String) && v.match?(/\A\d{1,16}\z/) && Integer(v)<=Economics::Engine::MAX_MINOR
              value['value']=v
            end
            # Knowledge time is assigned by this adapter, not by the sender.
            value.delete('recorded_at')
            updates << [previous,name,value]
          end
          error('DUPLICATE_SOURCE') unless names.uniq.size==names.size
        end
      rescue JSON::ParserError
        outcome='rejected'; code='INVALID_JSON'
      rescue Economics::Error => e
        outcome='rejected'; code=e.code
      end
      if outcome=='accepted'
        updates.each do |previous,name,value|
          store!(case_id,scenario,'fact',id:previous.external_id,revision:revision,status:'accepted',payload:{'name'=>name,'value'=>value,'source_artifact_id'=>artifact.external_id,'source_id'=>source_id,'source_revision'=>revision},parent:previous,recorded_at:received)
        end
      end
      delivery_id="delivery-#{SecureRandom.uuid}"
      delivery={'artifact_id'=>artifact.external_id,'source_kind'=>source_kind,'source_id'=>source_id,'source_revision'=>revision,'content_hash'=>content_hash,'outcome'=>outcome,'reason_code'=>code,'received_at'=>received.iso8601(6)}
      store!(case_id,scenario,'delivery',id:delivery_id,status:outcome=='rejected' ? 'rejected' : 'accepted',payload:delivery,parent:artifact,recorded_at:received)
      {'id'=>delivery_id,'artifact_id'=>artifact.external_id,'status'=>outcome,'reason_code'=>code,'synthetic'=>true}
    end
  end
  def reverse_funding(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_reverse_funding',input,key) do
      funding=get!(case_id,scenario,'funding',input.fetch('funding_id'),revision:input.fetch('revision'))
      error('UNRESOLVED_MAPPING') unless funding.status=='confirmed'
      error('HASH_CHANGED') unless input['expected_hash']==funding.payload_hash
      error('ALREADY_REVERSED') if source(case_id,scenario,'funding_reversal').where(parent_id:funding.id).exists?
      id="funding-reversal-#{SecureRandom.uuid}"
      body={'funding_id'=>funding.external_id,'funding_revision'=>funding.revision,'funding_hash'=>funding.payload_hash,'reason'=>reason!(input['reason']),'cash_refund_verified'=>false}
      store!(case_id,scenario,'funding_reversal',id:id,status:'reversed',payload:body,parent:funding)
      {'id'=>id,'synthetic'=>true,'cash_refund_verified'=>false}
    end
  end
  def reverse_source_receipt(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_reverse_source_receipt',input,key) do
      receipt=get!(case_id,scenario,'receipt',input.fetch('receipt_id'),revision:input.fetch('revision'))
      error('UNRESOLVED_MAPPING') unless receipt.status=='confirmed'
      error('HASH_CHANGED') unless input['expected_hash']==receipt.payload_hash
      error('ALREADY_REVERSED') if source(case_id,scenario,'receipt_reversal').where(parent_id:receipt.id).exists?
      id="receipt-reversal-#{SecureRandom.uuid}"
      body={'receipt_id'=>receipt.external_id,'receipt_revision'=>receipt.revision,'receipt_hash'=>receipt.payload_hash,'reason'=>reason!(input['reason']),'bank_refund_verified'=>false}
      reversal=store!(case_id,scenario,'receipt_reversal',id:id,status:'reversed',payload:body,parent:receipt)
      prior=source(case_id,scenario,'run').where(status:'completed').order(id: :desc).find do |run|
        Array(run.payload.dig('input_manifest','source_evidence')).any? { |ref| ref['id']==receipt.external_id && ref['hash']==receipt.payload_hash }
      end
      detail=prior && prior.payload.dig('result','details')&.find { |d| d['id']=='rebate' && d['basis']=='assessed' && d['assessed_minor'].is_a?(Integer) }
      intent_id=nil
      if detail
        intent_id="adjustment-intent-#{SecureRandom.uuid}"
        intent={'source_reversal_id'=>id,'original_run_id'=>prior.external_id,'original_run_hash'=>prior.payload_hash,'original_output_id'=>'rebate',
          'delta_minor'=>assessed_difference(0,detail['assessed_minor']),'currency'=>'USD','posting_period'=>nil,'status'=>'pending_review'}
        store!(case_id,scenario,'adjustment_intent',id:intent_id,status:'draft',payload:intent,parent:reversal)
      end
      {'id'=>id,'adjustment_intent_id'=>intent_id,'synthetic'=>true,'bank_refund_verified'=>false}
    end
  end
  def record_payment(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_record_payment',input,key) do
      payment=input.fetch('payment'); error('VALIDATION_ERROR') unless payment.is_a?(Hash)
      error('VALIDATION_ERROR') unless (payment.keys-%w[id revision amount_minor currency debtor_id creditor_id status observed_at]).empty?
      id=id!(payment.fetch('id')); revision=Economics::Engine.integer!(payment.fetch('revision'),'revision',min:1)
      Economics::Engine.integer!(payment['amount_minor'],'amount_minor',min:1)
      error('UNIT_MISMATCH') unless payment['currency']=='USD'
      expected=case_id=='advisor' ? %w[firm-demo advisor-demo] : %w[ria-harbor firm-demo]
      error('SCOPE_MISMATCH') unless [payment['debtor_id'],payment['creditor_id']]==expected
      error('VALIDATION_ERROR') unless %w[confirmed pending].include?(payment['status'])
      observed=time!(payment.fetch('observed_at')); error('FUTURE_EVIDENCE') if observed>Time.current
      any_revision=source(case_id,scenario,'payment').where(external_id:id).order(:revision).last
      error('SOURCE_CONFLICT','Payment revisions require a linked correction workflow') if any_revision && any_revision.revision!=revision
      existing=any_revision
      if existing
        error('SOURCE_CONFLICT') unless existing.payload==payment
        next {'id'=>id,'revision'=>revision,'status'=>existing.status}
      end
      row=store!(case_id,scenario,'payment',id:id,revision:revision,status:payment['status'],payload:payment,recorded_at:Time.current)
      {'id'=>row.external_id,'revision'=>row.revision,'status'=>row.status}
    end
  end
  def obligation!(case_id,scenario,run_id,output_id)
    run=get!(case_id,scenario,'run',run_id); error('INCOMPLETE_SOURCE') unless run.status=='completed'
    allowed=case_id=='advisor' ? 'payable' : 'net'
    error('UNRESOLVED_MAPPING','Output is not an authorized payable') unless output_id==allowed
    detail=run.payload.dig('result','details')&.find { |d| d['id']==output_id && d['unit']=='USD_minor' && d['basis']=='assessed' }
    expected_class=case_id=='advisor' ? 'obligation' : 'net_balance'
    parties=case_id=='advisor' ? %w[firm-demo advisor-demo] : %w[ria-harbor firm-demo]
    error('SCOPE_MISMATCH','Result does not establish the scoped obligation') unless detail && detail['output_class']==expected_class && detail['currency']=='USD' && [detail['payer'],detail['payee']]==parties
    amount=detail['assessed_minor']; error('INCOMPLETE_SOURCE') unless amount.is_a?(Integer) && (case_id=='ria' || amount>=0)
    [run,amount]
  end
  def obligation_key(case_id,scenario,output_id)
    parties=case_id=='advisor' ? %w[firm-demo advisor-demo] : %w[ria-harbor firm-demo]
    Economics::Canonical.hash({'scope'=>scope.stringify_keys,'case_id'=>case_id,'scenario_id'=>scenario,'debtor'=>parties[0],'creditor'=>parties[1],
      'currency'=>'USD','component'=>output_id,'service_start'=>'2026-09-01','service_end_exclusive'=>'2026-10-01'})
  end
  def active_applications(case_id,scenario,as_of:nil)
    reversals=source(case_id,scenario,'application_reversal')
    applications=source(case_id,scenario,'application')
    if as_of
      cutoff=time!(as_of); reversals=reversals.where('recorded_at <= ?',cutoff); applications=applications.where('recorded_at <= ?',cutoff)
    end
    applications.where.not(id:reversals.select(:parent_id)).to_a
  end
  def unlocked_period!(case_id,scenario,period)
    error('INVALID_DATE') unless period.is_a?(String) && period.match?(/\A\d{4}-\d{2}\z/) && date!(period+'-01')
    error('PERIOD_LOCKED') if MedallionEvidence.where(**scope,kind:'period_lock').where("payload->>'posting_period' = ?",period).exists?
    period
  end
  def apply_payment(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_apply_payment',input,key) do
      posting_period=unlocked_period!(case_id,scenario,input.fetch('posting_period'))
      payment=get!(case_id,scenario,'payment',input.fetch('payment_id'),revision:input.fetch('payment_revision'))
      error('UNRESOLVED_MAPPING','Payment must be confirmed') unless payment.status=='confirmed'
      run,owed=obligation!(case_id,scenario,input.fetch('run_id'),input.fetch('output_id'))
      latest=source(case_id,scenario,'run').where(status:'completed').order(:id).last
      error('HASH_CHANGED','Select the latest result before applying payment') unless latest && latest.id==run.id
      amount=Economics::Engine.integer!(input['amount_minor'],'amount_minor',min:1)
      economic_key=obligation_key(case_id,scenario,input['output_id'])
      applications=active_applications(case_id,scenario)
      used_payment=assessed_sum(applications.select { |a| a.parent_id==payment.id }.map { |a| a.payload['amount_minor'] })
      used_obligation=assessed_sum(applications.select { |a| a.payload['obligation_key']==economic_key }.map { |a| a.payload['amount_minor'] })
      error('ALLOCATION_EXCEEDED') if amount>assessed_difference(payment.payload['amount_minor'],used_payment) || amount>assessed_difference(owed,used_obligation)
      id="application-#{SecureRandom.uuid}"; body={'payment_id'=>payment.external_id,'payment_revision'=>payment.revision,'payment_hash'=>payment.payload_hash,
        'run_id'=>run.external_id,'run_hash'=>run.payload_hash,'output_id'=>input['output_id'],'obligation_key'=>economic_key,'amount_minor'=>amount,'currency'=>'USD','posting_period'=>posting_period,'reason'=>reason!(input['reason'])}
      store!(case_id,scenario,'application',id:id,status:'confirmed',payload:body,parent:payment)
      {'id'=>id,'amount_minor'=>amount,'accounting_posted'=>false}
    end
  end
  def reverse_application(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_reverse_application',input,key) do
      posting_period=unlocked_period!(case_id,scenario,input.fetch('posting_period'))
      original=get!(case_id,scenario,'application',input.fetch('application_id'))
      error('ALREADY_REVERSED') if source(case_id,scenario,'application_reversal').where(parent_id:original.id).exists?
      id="reversal-#{SecureRandom.uuid}"; body={'application_id'=>original.external_id,'application_hash'=>original.payload_hash,'posting_period'=>posting_period,'reason'=>reason!(input['reason'])}
      store!(case_id,scenario,'application_reversal',id:id,status:'reversed',payload:body,parent:original)
      {'id'=>id,'synthetic'=>true,'cash_refunded'=>false}
    end
  end
  def projected_statement(case_id,scenario,run,as_of:nil)
    MedallionStatements.new(workbench).project(case_id,scenario,run,as_of:as_of)
  end
  def lock_posting_period(input,key)
    workbench.guard!('finance'); case_id=case!(input.fetch('case_id')); scenario=scenario!(input['scenario_id'])
    workbench.operate('medallion_lock_period',input,key) do
      period=input.fetch('posting_period')
      error('INVALID_DATE') unless period.is_a?(String) && period.match?(/\A\d{4}-\d{2}\z/) && date!(period+'-01')
      error('PERIOD_LOCKED') if MedallionEvidence.where(**scope,kind:'period_lock').where("payload->>'posting_period' = ?",period).exists?
      id="period-lock-#{SecureRandom.uuid}"; body={'posting_period'=>period,'reason'=>reason!(input['reason']),'locked_at'=>Time.current.iso8601(6)}
      store!(case_id,scenario,'period_lock',id:id,status:'locked',payload:body)
      {'id'=>id,'posting_period'=>period,'synthetic'=>true}
    end
  end
  def seal_statement(input,key)
    MedallionStatements.new(workbench).seal(input,key)
  end
end
