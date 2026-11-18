require 'digest'
require 'securerandom'

# Isolated, synthetic household commercial adapter. Historical evidence is
# append-only; reading this service never initializes or evaluates a case.
class DisclosureWorkbench
  CASE='advisor'.freeze
  NS='disclosure_2027'.freeze
  START='2027-02-01'.freeze
  FINISH='2027-03-01'.freeze
  SUBJECT='disclosure-alder-household'.freeze
  CUTOFF='2027-02-01T00:00:00Z'.freeze
  def initialize(workbench)
    @w=workbench; @m=workbench.medallion
  end
  def rows(kind) = @m.source(CASE,NS,kind)
  def get(kind,id) = @m.get!(CASE,NS,kind,id)
  def error(code,message=nil) = @m.error(code,message)
  def keys!(input,allowed,required=allowed)
    error('VALIDATION_ERROR','Invalid fields') unless input.is_a?(Hash) && (input.keys-allowed).empty? && (required-input.keys).empty?
  end
  def implementation_hash
    paths=%w[app/domains/economics/engine.rb app/domains/economics/program.rb app/services/disclosure_sources.rb app/services/disclosure_policy.rb app/services/disclosure_alternatives.rb app/services/disclosure_lifecycle.rb app/services/disclosure_refunds.rb app/services/disclosure_workbench.rb app/services/disclosure_read_model.rb]
    Digest::SHA256.hexdigest(paths.map { |p| "#{p}:#{Digest::SHA256.file(Rails.root.join(p)).hexdigest}" }.join("\n"))
  end
  def store(kind,id:,status:,payload:,parent:nil,recorded_at:Time.current,bytes:nil,subject_id:SUBJECT,starts_on:START,ends_on:FINISH,schedule_version:1)
    body={'contract_version'=>'disclosure/v1','synthetic'=>true,'kind'=>kind,'classification'=>status,'id'=>id,'revision'=>1,
      'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],'case_id'=>CASE,'subject_id'=>subject_id,
      'currency'=>'USD','service_start'=>starts_on,'service_end_exclusive'=>ends_on,'recorded_at'=>recorded_at.utc.iso8601,
      'provenance'=>parent ? [{'id'=>parent.id.to_s,'external_id'=>parent.external_id,'revision'=>parent.revision,'hash'=>parent.payload_hash}] : []}.merge(payload)
    @m.store!(CASE,NS,kind,id:id,status:status,payload:body,parent:parent,recorded_at:recorded_at,bytes:bytes,subject_id:subject_id,product_id:'disclosure-advisory',starts_on:starts_on,ends_on:ends_on,schedule_version:schedule_version)
  end
  def fixture
    JSON.parse(File.binread(Rails.root.join('../../fixtures/disclosures/household.json')))
  end
  def fields
    {'basis'=>'ending_value','cadence'=>'monthly','annual_rate'=>'3/250','minimum_minor'=>nil,'fixed_amount_minor'=>nil,'optional_service'=>'none'}
  end
  def engine_run(policy, manifest, cutoff:, hypothetical:false, service_start:START, service_end_exclusive:FINISH)
    context={'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],'scenario'=>NS,'service_start'=>service_start,'service_end_exclusive'=>service_end_exclusive,'knowledge_cutoff'=>cutoff}
    context.merge!('hypothetical'=>true,'policy_knowledge_cutoff'=>Time.current.utc.iso8601) if hypothetical
    Economics::Engine.new.evaluate(policy_bundle:{'policy'=>policy.payload.fetch('graph'),'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'approved'=>!hypothetical},input_manifest:manifest,context:context)
  end
  def amount(result,id) = result.fetch('details').find { |d| d['id']==id }&.fetch('assessed_minor')
  def add_eligibility!(facts,observations)
    observations.each do |key,observation|
      parent=facts.fetch(key)
      %w[included excluded].each do |classification|
        selected=classification=='included' ? observation.fetch('eligible') : !observation.fetch('eligible')
        facts["#{key}_#{classification}"]=parent.merge('id'=>"#{parent.fetch('id')}-#{classification}",'unit'=>'scalar','basis'=>'scalar','value'=>selected ? '1' : '0').except('currency')
      end
    end
  end
  def membership_selection(cutoff)
    artifact=get('artifact','disclosure-household-source')
    expected=JSON.parse(artifact.original_bytes).fetch('members').map { |member| member.fetch('membership_id') }
    member_rows=rows('fact').where("payload->>'source_family' = ?",'disclosure-household-membership').to_a
    selected=DisclosureSources.memberships!(memberships:member_rows.map { |row| row.payload.fetch('membership') },service_start:START,service_end_exclusive:FINISH,cutoff:cutoff,group_id:SUBJECT)
    error('INCOMPLETE_SOURCE') unless selected.map { |member| member.fetch('membership_id') }.sort==expected.sort
    refs=selected.map do |member|
      row=member_rows.find { |r| r.external_id==member['membership_id'] && r.revision==member['revision'] }
      {'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}
    end
    [selected,refs]
  end
  def manifest_for(assignment, cutoff)
    artifact=get('artifact','disclosure-household-source'); terms=get('fact','disclosure-terms-v1')
    selected_members,member_refs=membership_selection(cutoff)
    roster=selected_members.to_h { |member| [member.fetch('id'),member.fetch('holdings')] }
    evidence=rows('fact').where("payload->>'source_family' = ?",'disclosure-ending-valuation').where("payload ? 'observation'").to_a
    observations=evidence.map { |r| r.payload.fetch('observation') }
    selected=DisclosureSources.select(observations:observations,members:roster.keys,holdings:roster,dates:['2027-01-31'],cutoff:cutoff,tenant_id:@w.scope[:tenant_id],entity_id:@w.scope[:entity_id])
    facts=selected.to_h do |obs|
      row=evidence.find { |r| r.external_id==obs['id'] && r.revision==obs['revision'] }
      [obs.fetch('holding_id').tr('-','_'),{'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
        'recorded_at'=>obs['recorded_at'],'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>obs['amount_minor'],
        'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}]
    end
    add_eligibility!(facts,selected.to_h { |obs| [obs.fetch('holding_id').tr('-','_'),obs] })
    {'facts'=>facts,'assignment'=>{'id'=>assignment.external_id,'revision'=>assignment.revision,'hash'=>assignment.payload_hash},
      'source_evidence'=>[artifact,terms].map { |r| {'id'=>r.external_id,'revision'=>r.revision,'hash'=>r.payload_hash} }+member_refs}
  end
  def alternative_manifest_for(policy, assignment, cutoff)
    fields=policy.payload.fetch('fields'); basis=fields['basis']; cadence=fields['cadence']
    name=case [basis,cadence]
      when ['ending_value','quarterly'] then 'quarterly'
      when ['average_daily_balance','monthly'] then 'average_daily_balance'
      when ['net_worth','monthly'] then 'net_worth'
      when ['fixed','monthly'] then 'fixed'
      when ['hourly','monthly'] then 'hourly'
      when ['optional_service','monthly'] then 'optional_service'
      else error('UNSUPPORTED_MECHANISM')
    end
    template=get('run',"disclosure-option-run-#{name.tr('_','-')}")
    original=template.payload.fetch('input_manifest'); known=@m.time!(cutoff)
    facts=Economics::Canonical.copy(original.fetch('facts').select { |_key,fact| @m.time!(fact['recorded_at']) <= known })
    if name=='average_daily_balance'
      dates=(1..28).map { |day| format('2027-02-%02d',day) }
      memberships,member_refs=membership_selection(cutoff)
      roster=memberships.to_h { |member| [member.fetch('id'),member.fetch('adb_holdings')] }
      error('INCOMPLETE_SOURCE') unless roster.keys.sort==%w[disclosure-alder-a disclosure-alder-b] && roster.all? { |member,holdings| holdings==["#{member[-1]}-eligible"] }
      source_rows=rows('fact').where("payload->>'source_family' = ?",'disclosure-daily-valuation').where("payload->'observation' ? 'date'").to_a
      selected=DisclosureSources.select(observations:source_rows.map { |row| row.payload.fetch('observation') },members:roster.keys,holdings:roster,dates:dates,cutoff:cutoff,tenant_id:@w.scope[:tenant_id],entity_id:@w.scope[:entity_id])
      selected.each do |obs|
        row=source_rows.find { |r| r.external_id==obs['id'] && r.revision==obs['revision'] }
        key="#{obs['member_id'][-1]}_day_#{Date.iso8601(obs['date']).day}"
        facts[key]={'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],'recorded_at'=>obs['recorded_at'],'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>obs['amount_minor'],'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}
        facts["#{key}_included"]=facts[key].merge('id'=>"#{row.external_id}-included",'unit'=>'scalar','basis'=>'scalar','value'=>obs['eligible'] ? '1' : '0').except('currency')
      end
    end
    {'facts'=>facts,'assignment'=>{'id'=>assignment.external_id,'revision'=>assignment.revision,'hash'=>assignment.payload_hash},'source_evidence'=>original.fetch('source_evidence')+(member_refs || [])}
  end
  def bootstrap(input,key)
    @w.guard!('operator'); keys!(input,[])
    @w.operate('disclosure_bootstrap',input,key) do
      clock=Time.iso8601('2027-01-31T12:00:00Z')
      bytes=File.binread(Rails.root.join('../../fixtures/disclosures/household.json')); f=JSON.parse(bytes)
      artifact=store('artifact',id:'disclosure-household-source',status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(bytes),'media_type'=>'application/json'},recorded_at:clock,bytes:bytes)
      store('delivery',id:'disclosure-household-delivery',status:'accepted',payload:{'artifact_id'=>artifact.external_id,'received_at'=>clock.iso8601},parent:artifact,recorded_at:clock)
      terms=store('fact',id:'disclosure-terms-v1',status:'approved',payload:{'terms'=>f.fetch('terms'),'source_artifact_id'=>artifact.external_id},parent:artifact,recorded_at:clock)
      selected_members=DisclosureSources.memberships!(memberships:f.fetch('members'),service_start:START,service_end_exclusive:FINISH,cutoff:CUTOFF,group_id:SUBJECT)
      selected_members.each do |member|
        store('fact',id:member.fetch('membership_id'),status:'accepted',payload:{'membership'=>member,'source_artifact_id'=>artifact.external_id,'source_family'=>'disclosure-household-membership'},parent:artifact,recorded_at:clock)
      end
      roster=selected_members.to_h { |member| [member.fetch('id'),member.fetch('holdings')] }
      observations=f.fetch('observations').map { |o| o.merge('tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id]) }
      selected=DisclosureSources.select(observations:observations,members:roster.keys,holdings:roster,dates:['2027-01-31'],cutoff:CUTOFF,tenant_id:@w.scope[:tenant_id],entity_id:@w.scope[:entity_id])
      source_rows=selected.to_h do |obs|
        row=store('fact',id:obs.fetch('id'),status:'accepted',payload:{'observation'=>obs,'source_artifact_id'=>artifact.external_id,'source_family'=>'disclosure-ending-valuation'},parent:artifact,recorded_at:clock)
        [obs.fetch('holding_id').tr('-','_'),[obs,row]]
      end
      policy=store('policy',id:'disclosure-policy-v1',status:'published',payload:{'fields'=>fields,'graph'=>DisclosurePolicy.build(fields,version:'disclosure-policy-v1'),'terms_ref'=>terms.external_id,'terms_hash'=>terms.payload_hash},parent:terms,recorded_at:clock)
      assignment=store('assignment',id:'disclosure-assignment-v1',status:'published',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'subject_id'=>SUBJECT},parent:policy,recorded_at:clock)
      facts=source_rows.to_h do |name,(obs,row)|
        [name,{'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
          'recorded_at'=>obs['recorded_at'],'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>obs['amount_minor'],
          'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}]
      end
      add_eligibility!(facts,source_rows.transform_values(&:first))
      manifest={'facts'=>facts,'assignment'=>{'id'=>assignment.external_id,'revision'=>assignment.revision,'hash'=>assignment.payload_hash},
        'source_evidence'=>[artifact,terms].map { |r| {'id'=>r.external_id,'revision'=>r.revision,'hash'=>r.payload_hash} } + selected_members.map { |member| row=get('fact',member.fetch('membership_id')); {'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash} }}
      result=engine_run(policy,manifest,cutoff:CUTOFF)
      error('INCOMPLETE_SOURCE') unless result['status']=='completed'
      run=store('run',id:'disclosure-run-v1',status:'completed',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'assignment_id'=>assignment.external_id,'input_manifest'=>manifest,'implementation_hash'=>implementation_hash,'knowledge_cutoff'=>CUTOFF,'result'=>result},parent:policy,recorded_at:clock)
      catalog=BillingCatalog.new(@w)
      invoice_amount=amount(result,'charge'); error('INCOMPLETE_SOURCE') unless invoice_amount.is_a?(Integer) && invoice_amount>0
      invoice=catalog.insert!(BillingInvoice,{external_id:'disclosure-invoice-v1'},@w.scope.merge(external_id:'disclosure-invoice-v1',revision:1,debtor_id:SUBJECT,amount_minor:invoice_amount,currency:'USD',status:'issued',legacy_invoice_id:'disclosure-invoice-v1'))
      issuance_bytes=File.binread(Rails.root.join('../../fixtures/disclosures/invoice_issuance.json')); issuance=JSON.parse(issuance_bytes); issuance_clock=@m.time!(issuance.fetch('received_at'))
      issuance_artifact=store('artifact',id:'disclosure-invoice-issuance-artifact',status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(issuance_bytes),'media_type'=>'application/json'},bytes:issuance_bytes,recorded_at:issuance_clock)
      issuance_delivery=store('delivery',id:'disclosure-invoice-issuance-delivery',status:'accepted',payload:{'artifact_id'=>issuance_artifact.external_id,'received_at'=>issuance_clock.iso8601},parent:issuance_artifact,recorded_at:issuance_clock)
      store('fact',id:'disclosure-invoice-issuance',status:'accepted',payload:issuance.merge('source_artifact_id'=>issuance_artifact.external_id,'invoice_id'=>invoice.external_id),parent:issuance_delivery,recorded_at:issuance_clock)
      %w[a b].each do |member|
        value=amount(result,"line_#{member}"); account="disclosure-alder-#{member}"
        attrs=@w.scope.merge(external_id:"disclosure-obligation-#{member}",revision:1,customer_id:SUBJECT,service_id:'disclosure-advisory',broker_id:'advisor-demo',account_id:account,assignment_id:assignment.external_id,client_terms_ref:terms.external_id,source_id:run.external_id,source_revision:run.revision,legacy_charge_id:"disclosure-#{member}",route:'invoice',currency:'USD',amount_minor:value,service_period_start:START,service_period_end:FINISH)
        obligation=catalog.insert!(BillingObligation,{external_id:attrs[:external_id]},attrs)
        line=catalog.insert!(BillingInvoiceLine,{external_id:"disclosure-line-#{member}"},@w.scope.merge(external_id:"disclosure-line-#{member}",billing_invoice_id:invoice.id,billing_obligation_id:obligation.id,amount_minor:value))
        store('fact',id:"disclosure-billing-binding-#{member}",status:'accepted',payload:{'run_id'=>run.external_id,'run_revision'=>run.revision,'run_hash'=>run.payload_hash,'output_id'=>"line_#{member}",'obligation_id'=>obligation.external_id,'invoice_id'=>invoice.external_id,'invoice_line_id'=>line.external_id,'amount_minor'=>value},parent:run,recorded_at:clock)
      end
      bootstrap_alternatives(manifest,terms)
      bootstrap_lifecycle(run,invoice,terms)
      bootstrap_ria_cost
      publication=store('publication',id:'disclosure-publication-v1',status:'published',payload:{'run_id'=>run.external_id,'run_hash'=>run.payload_hash,'policy_id'=>policy.external_id,'invoice_id'=>invoice.external_id},parent:run,recorded_at:clock)
      {'namespace'=>NS,'run_id'=>run.external_id,'invoice_id'=>invoice.external_id,'publication_id'=>publication.external_id}
    end
  end
  def bootstrap_ria_cost
    raw=File.binread(Rails.root.join('../../fixtures/disclosures/ria_cost.json')); obs=JSON.parse(raw); clock=@m.time!(obs.fetch('recorded_at'))
    common={'contract_version'=>'disclosure/v1','synthetic'=>true,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],'case_id'=>'ria','subject_id'=>'ria-harbor','currency'=>'USD','service_start'=>START,'service_end_exclusive'=>FINISH,'recorded_at'=>clock.iso8601,'revision'=>1}
    artifact=@m.store!('ria',NS,'artifact',id:'disclosure-ria-cost-artifact',status:'retained',bytes:raw,recorded_at:clock,payload:common.merge('kind'=>'artifact','classification'=>'retained','id'=>'disclosure-ria-cost-artifact','sha256'=>Digest::SHA256.hexdigest(raw),'provenance'=>[]))
    delivery=@m.store!('ria',NS,'delivery',id:'disclosure-ria-cost-delivery',status:'accepted',parent:artifact,recorded_at:clock,payload:common.merge('kind'=>'delivery','classification'=>'accepted','id'=>'disclosure-ria-cost-delivery','provenance'=>[{'id'=>artifact.id.to_s,'external_id'=>artifact.external_id,'revision'=>artifact.revision,'hash'=>artifact.payload_hash}]))
    @m.store!('ria',NS,'fact',id:'disclosure-ria-cost-source',status:'accepted',parent:delivery,recorded_at:clock,payload:common.merge('kind'=>'fact','classification'=>'observed_outside_charge','id'=>'disclosure-ria-cost-source','observation'=>obs,'provenance'=>[{'id'=>delivery.id.to_s,'external_id'=>delivery.external_id,'revision'=>delivery.revision,'hash'=>delivery.payload_hash}]))
  end
  def bootstrap_lifecycle(original_run,invoice,terms)
    clock=Time.iso8601('2027-02-18T00:00:00Z'); credit_clock=Time.iso8601('2027-02-16T00:00:00Z')
    names=%w[termination salary bonus loan forgiveness equity custodian_charge embedded_fund_cost custodian_advisory_observation original_receipt refund recognition loan_cash]
    data={}; artifacts={}; deliveries={}
    names.each do |name|
      raw=File.binread(Rails.root.join("../../fixtures/disclosures/#{name}.json")); item=JSON.parse(raw); data[name]=item
      received=@m.time!(item.fetch('received_at'))
      artifact=store('artifact',id:"disclosure-#{name.tr('_','-')}-artifact",status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(raw),'media_type'=>'application/json'},bytes:raw,recorded_at:received)
      delivery=store('delivery',id:"disclosure-#{name.tr('_','-')}-delivery",status:'accepted',payload:{'artifact_id'=>artifact.external_id,'received_at'=>received.iso8601},parent:artifact,recorded_at:received)
      artifacts[name]=artifact; deliveries[name]=delivery
    end
    source={}
    %w[termination salary bonus loan forgiveness equity custodian_charge embedded_fund_cost custodian_advisory_observation].each do |name|
      item=data.fetch(name); id=item['id'] || 'disclosure-termination'; delivery=deliveries.fetch(name)
      source[name]=store('fact',id:id,status:'accepted',payload:{'observation'=>item,'source_artifact_id'=>artifacts.fetch(name).external_id,'delivery_id'=>delivery.external_id},parent:delivery,recorded_at:delivery.recorded_at)
    end
    receipt_data=data.fetch('original_receipt'); refund_data=data.fetch('refund'); loan_cash_data=data.fetch('loan_cash')
    [[receipt_data,'disclosure-alder-household','firm-demo'],[refund_data,'firm-demo','disclosure-alder-household'],[loan_cash_data,'firm-demo','advisor-demo']].each do |item,payer,payee|
      error('SCOPE_MISMATCH') unless item['synthetic']==true && item['payer']==payer && item['payee']==payee && item['currency']=='USD' && item['status']=='confirmed' && item['amount_minor'].is_a?(Integer) && item['amount_minor']>0
      error('FUTURE_EVIDENCE') if @m.time!(item['received_at']) < @m.time!(item['effective_at'])
    end
    receipt=store('payment',id:receipt_data.fetch('id'),status:'confirmed',payload:receipt_data.merge('direction'=>'inbound_client','invoice_id'=>invoice.external_id,'source_artifact_id'=>artifacts['original_receipt'].external_id,'delivery_id'=>deliveries['original_receipt'].external_id),parent:deliveries['original_receipt'],recorded_at:deliveries['original_receipt'].recorded_at)
    refund=store('payment',id:refund_data.fetch('id'),status:'confirmed',payload:refund_data.merge('direction'=>'outbound_refund','original_receipt_id'=>receipt.external_id,'original_receipt_hash'=>receipt.payload_hash,'source_artifact_id'=>artifacts['refund'].external_id,'delivery_id'=>deliveries['refund'].external_id),parent:deliveries['refund'],recorded_at:deliveries['refund'].recorded_at)
    store('payment',id:loan_cash_data.fetch('id'),status:'confirmed',payload:loan_cash_data.merge('direction'=>'outbound_loan_advance','loan_terms_id'=>source['loan'].external_id,'loan_terms_hash'=>source['loan'].payload_hash,'source_artifact_id'=>artifacts['loan_cash'].external_id,'delivery_id'=>deliveries['loan_cash'].external_id),parent:deliveries['loan_cash'],recorded_at:deliveries['loan_cash'].recorded_at)
    duplicate=data.fetch('custodian_advisory_observation')
    error('SOURCE_CONFLICT') unless duplicate['original_invoice_id']==invoice.external_id && duplicate['amount_minor']==invoice.amount_minor && duplicate['included_in_subtotal']==false
    source['refund']=refund
    error('INCOMPLETE_SOURCE') unless %w[salary bonus loan forgiveness].all? { |name| data[name]['approved']==true && data[name]['amount_minor'].is_a?(Integer) && data[name]['amount_minor']>0 }
    error('SOURCE_CONFLICT') unless loan_cash_data['amount_minor']==data['loan']['amount_minor']
    result=original_run.payload.fetch('result')
    originals={'original_charge'=>'charge','line_a'=>'line_a','line_b'=>'line_b'}
    values=originals.to_h { |name,output| [name,amount(result,output)] }
    %w[salary bonus loan forgiveness].each { |name| values[name]=data.fetch(name).fetch('amount_minor') }
    values['refund']=refund_data.fetch('amount_minor'); values['custody']=data.fetch('custodian_charge').fetch('amount_minor')
    facts=values.to_h do |name,value|
      row=originals.key?(name) ? original_run : (name=='custody' ? source.fetch('custodian_charge') : source.fetch(name))
      [name,{'id'=>"#{row.external_id}-#{name.tr('_','-')}",'revision'=>1,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
        'recorded_at'=>row.recorded_at.utc.iso8601,'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>value,
        'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'output_id'=>originals[name]}]}]
    end
    termination=source.fetch('termination'); t=data.fetch('termination')
    error('INVALID_INTERVAL') unless t['approved']==true && @m.date!(t.fetch('effective_at')[0,10])==Date.iso8601(START)+14 && t['unused_days']==14 && t['period_days']==28
    facts['unused_fraction']={'id'=>'disclosure-unused-service-days','revision'=>1,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
      'recorded_at'=>termination.recorded_at.utc.iso8601,'approved'=>true,'unit'=>'scalar','basis'=>'scalar','value'=>"#{t['unused_days']}/#{t['period_days']}",
      'evidence_refs'=>[{'id'=>termination.id.to_s,'external_id'=>termination.external_id,'revision'=>termination.revision,'hash'=>termination.payload_hash}]}
    graph=DisclosureLifecycle.graph
    policy=store('policy',id:'disclosure-lifecycle-policy-v1',status:'published',payload:{'graph'=>graph,'terms_ref'=>terms.external_id,'terms_hash'=>terms.payload_hash},parent:terms,recorded_at:Time.iso8601('2027-02-01T00:00:00Z'))
    manifest={'facts'=>facts,'source_evidence'=>[artifacts['termination'],original_run].map { |r| {'id'=>r.external_id,'revision'=>r.revision,'hash'=>r.payload_hash} }}
    credit_manifest=manifest.merge('facts'=>facts.select { |_name,fact| @m.time!(fact['recorded_at']) <= credit_clock })
    credit_result=engine_run(policy,credit_manifest,cutoff:credit_clock.iso8601)
    error('INCOMPLETE_SOURCE') unless amount(credit_result,'credit').is_a?(Integer)
    credit_run=store('run',id:'disclosure-credit-run-v1',status:'accepted',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'input_manifest'=>credit_manifest,'implementation_hash'=>implementation_hash,'knowledge_cutoff'=>credit_clock.iso8601,'result'=>credit_result},parent:policy,recorded_at:credit_clock)
    computed=engine_run(policy,manifest,cutoff:clock.iso8601); error('INCOMPLETE_SOURCE') unless computed['status']=='completed'
    error('ALLOCATION_EXCEEDED') if refund_data['amount_minor']>amount(computed,'credit') || refund_data['amount_minor']>receipt_data['amount_minor']
    run=store('run',id:'disclosure-lifecycle-run-v1',status:'completed',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'input_manifest'=>manifest,'implementation_hash'=>implementation_hash,'knowledge_cutoff'=>clock.iso8601,'result'=>computed},parent:policy,recorded_at:clock)
    credit=store('event',id:'disclosure-credit',status:'approved',payload:{'classification'=>'commercial_credit','amount_minor'=>amount(computed,'credit'),'run_id'=>credit_run.external_id,'output_id'=>'credit','original_run_id'=>original_run.external_id,'original_invoice_id'=>invoice.external_id,'original_invoice_line_ids'=>%w[disclosure-line-a disclosure-line-b],'direction'=>'firm_to_household','accounting_posted'=>false},parent:credit_run,recorded_at:credit_clock)
    payment_proof=refund.payload.merge('id'=>refund.external_id,'status'=>refund.status,'credit_id'=>credit.external_id,'credit_hash'=>credit.payload_hash)
    receipt_proof=receipt.payload.merge('id'=>receipt.external_id,'hash'=>receipt.payload_hash,'status'=>receipt.status)
    credit_proof=credit.payload.merge('id'=>credit.external_id,'hash'=>credit.payload_hash,'status'=>credit.status,'payer'=>'firm-demo','payee'=>SUBJECT)
    applications=rows('application').where.not(external_id:'disclosure-refund-application').map(&:payload)
    DisclosureRefunds.validate!(payment:payment_proof,credit:credit_proof,receipt:receipt_proof,applications:applications)
    error('ALLOCATION_EXCEEDED') if refund_data['amount_minor']>amount(credit_result,'credit_a')
    application=store('application',id:'disclosure-refund-application',status:'confirmed',payload:{'payment_id'=>refund.external_id,'payment_hash'=>refund.payload_hash,'credit_id'=>credit.external_id,'credit_hash'=>credit.payload_hash,'original_receipt_id'=>receipt.external_id,'original_receipt_hash'=>receipt.payload_hash,'credit_run_id'=>credit_run.external_id,'credit_run_hash'=>credit_run.payload_hash,'credit_allocation_output_id'=>'credit_a','original_invoice_line_id'=>'disclosure-line-a','amount_minor'=>refund_data['amount_minor']},parent:refund,recorded_at:clock)
    input=store('fact',id:'disclosure-recognition-input',status:'accepted',payload:{'invoice_id'=>invoice.external_id,'credit_id'=>credit.external_id,'credit_hash'=>credit.payload_hash,'commercial_run_id'=>original_run.external_id,'treatment_id'=>data['recognition']['treatment_id']},parent:credit,recorded_at:clock)
    schedule=store('fact',id:'disclosure-recognition-schedule',status:'accepted',payload:{'classification'=>'supplied_schedule','treatment'=>data['recognition'],'input_id'=>input.external_id,'source_artifact_id'=>artifacts['recognition'].external_id,'delivery_id'=>deliveries['recognition'].external_id,'mocked'=>true},parent:input,recorded_at:clock)
    store('fact',id:'disclosure-recognition-posted',status:'confirmed',payload:{'classification'=>'mock_posting','recognized_minor'=>data['recognition']['recognized_minor'],'deferred_minor'=>data['recognition']['deferred_before_credit_minor'],'schedule_id'=>schedule.external_id,'source_artifact_id'=>artifacts['recognition'].external_id,'delivery_id'=>deliveries['recognition'].external_id,'mocked'=>true},parent:schedule,recorded_at:clock)
    application
  end
  def bootstrap_alternatives(baseline_manifest,terms)
    bytes=File.binread(Rails.root.join('../../fixtures/disclosures/alternatives.json')); data=JSON.parse(bytes)
    known=Time.iso8601(data.fetch('recorded_at'))
    artifact=store('artifact',id:'disclosure-alternative-source',status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(bytes),'media_type'=>'application/json'},recorded_at:known,bytes:bytes)
    store('delivery',id:'disclosure-alternative-delivery',status:'accepted',payload:{'artifact_id'=>artifact.external_id,'received_at'=>known.iso8601},parent:artifact,recorded_at:known)
    daily=data.fetch('daily').map { |row| row.merge('tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id]) }
    dates=(1..28).map { |day| format('2027-02-%02d',day) }
    adb_members,adb_membership_refs=membership_selection(known.iso8601)
    roster=adb_members.to_h { |member| [member.fetch('id'),member.fetch('adb_holdings')] }
    error('INCOMPLETE_SOURCE') unless roster.keys.sort==%w[disclosure-alder-a disclosure-alder-b] && roster.all? { |member,holdings| holdings==["#{member[-1]}-eligible"] }
    selected=DisclosureSources.select(observations:daily,members:roster.keys,holdings:roster,dates:dates,cutoff:known.iso8601,tenant_id:@w.scope[:tenant_id],entity_id:@w.scope[:entity_id])
    facts=Economics::Canonical.copy(baseline_manifest.fetch('facts'))
    selected.each do |obs|
      row=store('fact',id:obs.fetch('id'),status:'accepted',payload:{'observation'=>obs,'source_artifact_id'=>artifact.external_id,'source_family'=>'disclosure-daily-valuation'},parent:artifact,recorded_at:known)
      member=obs['member_id'][-1]; day=Date.iso8601(obs['date']).day
      key="#{member}_day_#{day}"
      facts[key]={'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
        'recorded_at'=>known.iso8601,'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>obs['amount_minor'],'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}
      facts["#{key}_included"]=facts[key].merge('id'=>"#{row.external_id}-included",'unit'=>'scalar','basis'=>'scalar','value'=>obs['eligible'] ? '1' : '0').except('currency')
    end
    data.fetch('facts').each do |name,value|
      row=store('fact',id:"disclosure-input-#{name.tr('_','-')}",status:'accepted',payload:{'name'=>name,'value'=>value,'source_artifact_id'=>artifact.external_id},parent:artifact,recorded_at:known)
      facts[name]={'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
        'recorded_at'=>known.iso8601,'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>value,'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}
    end
    %w[service_fraction approved_hours].each do |name|
      observation=data.fetch(name)
      row=store('fact',id:observation.fetch('id'),status:'approved',payload:{'observation'=>observation,'source_artifact_id'=>artifact.external_id},parent:artifact,recorded_at:known)
      facts[name]={'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
        'recorded_at'=>known.iso8601,'approved'=>true,'unit'=>'scalar','basis'=>'scalar','value'=>observation.fetch('value'),
        'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}
    end
    election=store('fact',id:'disclosure-optional-election',status:'approved',payload:{'election'=>data.fetch('election'),'source_artifact_id'=>artifact.external_id},parent:artifact,recorded_at:known)
    facts['election']={'id'=>election.external_id,'revision'=>election.revision,'hash'=>election.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],
      'recorded_at'=>known.iso8601,'approved'=>true,'unit'=>'scalar','basis'=>'scalar','value'=>'1','accepted'=>true,'evidence_refs'=>[{'id'=>election.id.to_s,'external_id'=>election.external_id,'revision'=>election.revision,'hash'=>election.payload_hash}]}
    quarterly_bytes=File.binread(Rails.root.join('../../fixtures/disclosures/quarterly_valuation.json')); quarterly=JSON.parse(quarterly_bytes); quarterly_clock=@m.time!(quarterly.fetch('received_at'))
    quarterly_artifact=store('artifact',id:'disclosure-quarterly-source',status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(quarterly_bytes),'media_type'=>'application/json'},bytes:quarterly_bytes,recorded_at:quarterly_clock,starts_on:'2027-01-01',ends_on:'2027-04-01')
    quarterly_delivery=store('delivery',id:'disclosure-quarterly-delivery',status:'accepted',payload:{'artifact_id'=>quarterly_artifact.external_id,'received_at'=>quarterly_clock.iso8601},parent:quarterly_artifact,recorded_at:quarterly_clock,starts_on:'2027-01-01',ends_on:'2027-04-01')
    quarterly_terms_bytes=File.binread(Rails.root.join('../../fixtures/disclosures/quarterly_terms.json')); quarterly_terms_data=JSON.parse(quarterly_terms_bytes)
    quarterly_terms_artifact=store('artifact',id:'disclosure-quarterly-terms-artifact',status:'retained',payload:{'sha256'=>Digest::SHA256.hexdigest(quarterly_terms_bytes),'media_type'=>'application/json'},bytes:quarterly_terms_bytes,recorded_at:quarterly_clock,starts_on:'2027-01-01',ends_on:'2027-04-01')
    quarterly_terms_delivery=store('delivery',id:'disclosure-quarterly-terms-delivery',status:'accepted',payload:{'artifact_id'=>quarterly_terms_artifact.external_id,'received_at'=>quarterly_clock.iso8601},parent:quarterly_terms_artifact,recorded_at:quarterly_clock,starts_on:'2027-01-01',ends_on:'2027-04-01')
    quarterly_terms=store('fact',id:'disclosure-quarterly-terms-v1',status:'approved',payload:{'terms'=>quarterly_terms_data,'source_artifact_id'=>quarterly_terms_artifact.external_id},parent:quarterly_terms_delivery,recorded_at:quarterly_clock,starts_on:'2027-01-01',ends_on:'2027-04-01')
    quarterly.fetch('accounts').each do |key,value|
      row=store('fact',id:"disclosure-#{key.tr('_','-')}",status:'accepted',payload:{'value'=>value,'valuation_date'=>quarterly['valuation_date'],'source_artifact_id'=>quarterly_artifact.external_id},parent:quarterly_delivery,recorded_at:quarterly_clock,starts_on:'2027-01-01',ends_on:'2027-04-01')
      facts[key]={'id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash,'tenant_id'=>@w.scope[:tenant_id],'entity_id'=>@w.scope[:entity_id],'recorded_at'=>quarterly_clock.iso8601,'approved'=>true,'unit'=>'USD_minor','basis'=>'source_reported','currency'=>'USD','value'=>value,'evidence_refs'=>[{'id'=>row.id.to_s,'external_id'=>row.external_id,'revision'=>row.revision,'hash'=>row.payload_hash}]}
    end
    minimum_fields=fields.merge('minimum_minor'=>125000)
    minimum_policy=store('policy',id:'disclosure-option-monthly-minimum',status:'draft',payload:{'name'=>'monthly_minimum','fields'=>minimum_fields,'graph'=>DisclosurePolicy.build(minimum_fields,version:'disclosure-option-monthly-minimum'),'terms_ref'=>terms.external_id,'terms_hash'=>terms.payload_hash,'comparison_only'=>true},parent:terms,recorded_at:known)
    minimum_result=engine_run(minimum_policy,baseline_manifest,cutoff:known.iso8601,hypothetical:true)
    error('INCOMPLETE_SOURCE') unless minimum_result['status']=='completed'
    store('run',id:'disclosure-option-run-monthly-minimum',status:'completed',payload:{'policy_id'=>minimum_policy.external_id,'policy_hash'=>minimum_policy.payload_hash,'input_manifest'=>baseline_manifest,'implementation_hash'=>implementation_hash,'knowledge_cutoff'=>known.iso8601,'result'=>minimum_result,'comparison_only'=>true},parent:minimum_policy,recorded_at:known)
    DisclosureAlternatives::NAMES.each do |name|
      policy_id="disclosure-option-#{name.tr('_','-')}"; graph=DisclosureAlternatives.graph(name,version:policy_id)
      option_fields=case name
        when 'average_daily_balance' then fields.merge('basis'=>'average_daily_balance')
        when 'quarterly' then fields.merge('cadence'=>'quarterly')
        when 'net_worth' then fields.merge('basis'=>'net_worth','annual_rate'=>'3/2500')
        when 'fixed' then fields.merge('basis'=>'fixed','annual_rate'=>nil,'fixed_amount_minor'=>40000,'service_mode'=>'partial')
        when 'hourly' then fields.merge('basis'=>'hourly','annual_rate'=>nil,'hourly_rate_minor'=>20000)
        when 'optional_service' then fields.merge('basis'=>'optional_service','annual_rate'=>nil,'optional_service'=>'accepted','optional_amount_minor'=>10000)
        else nil
      end
      option_terms=name=='quarterly' ? quarterly_terms : terms
      policy=store('policy',id:policy_id,status:'draft',payload:{'name'=>name,'fields'=>option_fields,'graph'=>graph,'terms_ref'=>option_terms.external_id,'terms_hash'=>option_terms.payload_hash,'comparison_only'=>true},parent:option_terms,recorded_at:known)
      cutoff=name=='quarterly' ? '2027-01-01T00:00:00Z' : known.iso8601
      selected_keys=graph['nodes'].select { |node| node['op']=='fact' }.map { |node| node['key'] }
      selected_facts=facts.slice(*selected_keys)
      source_artifact=name=='quarterly' ? quarterly_artifact : artifact
      manifest={'facts'=>selected_facts,'source_evidence'=>[source_artifact,option_terms].map { |record| {'id'=>record.external_id,'revision'=>record.revision,'hash'=>record.payload_hash} }+(name=='average_daily_balance' ? adb_membership_refs : [])}
      service_start=name=='quarterly' ? '2027-01-01' : name=='onboarding' ? '2027-02-15' : START
      service_end=name=='quarterly' ? '2027-04-01' : FINISH
      result=engine_run(policy,manifest,cutoff:cutoff,hypothetical:true,service_start:service_start,service_end_exclusive:service_end)
      invoice_on={'arrears'=>'2027-03-01','quarterly'=>'2027-01-01','onboarding'=>'2027-02-15'}.fetch(name,START)
      error('INCOMPLETE_SOURCE',"Comparison #{name} is incomplete") unless result['status']=='completed'
      store('run',id:"disclosure-option-run-#{name.tr('_','-')}",status:'completed',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'input_manifest'=>manifest,'implementation_hash'=>implementation_hash,'knowledge_cutoff'=>cutoff,'service_start'=>service_start,'service_end_exclusive'=>service_end,'invoice_on'=>invoice_on,'due_on'=>invoice_on,'invoice_timing'=>name=='arrears' ? 'arrears' : 'advance','cash_status'=>'no_execution_evidence','result'=>result,'comparison_only'=>true},parent:policy,recorded_at:known,starts_on:service_start,ends_on:service_end)
    end
  end
  def case_check!(value)
    error('SCOPE_MISMATCH') unless value==CASE
  end
  def interval!(from,to)
    start=@m.date!(from); finish=to.nil? ? nil : @m.date!(to)
    error('INVALID_INTERVAL') if finish && start >= finish
  end
  def identifier(prefix) = "disclosure-#{prefix}-#{SecureRandom.uuid}"
  def policy_window!(policy, from, to)
    start=@m.date!(from.to_s); finish=to.nil? ? nil : @m.date!(to.to_s)
    error('INVALID_INTERVAL','Assignment must be contained within the policy effective window') unless policy.starts_on && finish && policy.starts_on <= start && (policy.ends_on.nil? || finish <= policy.ends_on)
  end
  # Compare economic outputs with the retained native invoice and its bound lines.
  def correction_required?(result, policy, original_run)
    invoice=BillingInvoice.find_by!(**@w.scope,external_id:'disclosure-invoice-v1')
    details=result.fetch('details'); original=original_run.payload.fetch('result').fetch('details')
    standard=policy.payload.dig('fields','basis')=='ending_value' && policy.payload.dig('fields','cadence')=='monthly'
    expected_class=standard ? 'obligation' : 'comparison'
    pick=lambda do |items,id|
      matches=items.select { |d| d['id']==id }
      error('INCOMPLETE_SOURCE','Missing or duplicate billing output') unless matches.one? && matches.first['assessed_minor'].is_a?(Integer) && matches.first['assessed_minor']>=0
      matches.first
    end
    validate_output=lambda do |item|
      valid=item['role']=='terminal' && item['unit']=='USD_minor' && item['basis']=='assessed' && item['output_class']==expected_class && item['currency'].is_a?(String) && !item['currency'].empty? && item['interval'].is_a?(Hash) && item['interval']['start'].is_a?(String) && item['interval']['end_exclusive'].is_a?(String)
      valid &&= %w[payer payee].all? { |key| standard ? item[key].is_a?(String) && !item[key].empty? : item[key].nil? || (item[key].is_a?(String) && !item[key].empty?) }
      error('INCOMPLETE_SOURCE','Invalid billing output contract') unless valid
    end
    charge=pick.call(details,'charge'); original_charge=pick.call(original,'charge'); validate_output.call(charge)
    error('INCOMPLETE_SOURCE','Missing retained billing party') unless original_charge['payer']==invoice.debtor_id && original_charge['payee'].is_a?(String) && !original_charge['payee'].empty?
    interval={'start'=>START,'end_exclusive'=>FINISH}
    economic=lambda do |item|
      [item['currency'],item['payer'],item['payee'],item['interval'],item['basis'],item['unit'],item['output_class']]
    end
    changed=charge['assessed_minor']!=invoice.amount_minor || economic.call(charge)!=[invoice.currency,invoice.debtor_id,original_charge['payee'],interval,'assessed',"#{invoice.currency}_minor",'obligation']
    bindings=%w[a b].map { |member| get('fact',"disclosure-billing-binding-#{member}").payload }
    lines=bindings.map do |binding|
      error('INCOMPLETE_SOURCE','Invoice binding does not match original run') unless binding['run_id']==original_run.external_id && binding['run_revision']==original_run.revision && binding['run_hash']==original_run.payload_hash && binding['invoice_id']==invoice.external_id
      line=BillingInvoiceLine.find_by!(**@w.scope,external_id:binding.fetch('invoice_line_id'),billing_invoice_id:invoice.id)
      obligation=BillingObligation.find_by!(**@w.scope,id:line.billing_obligation_id,external_id:binding.fetch('obligation_id'))
      error('INCOMPLETE_SOURCE','Invoice binding does not match retained line') unless line.amount_minor==binding['amount_minor'] && obligation.amount_minor==line.amount_minor && obligation.currency==invoice.currency
      [binding, line, obligation]
    end
    error('INCOMPLETE_SOURCE','Retained invoice does not balance') unless lines.map { |_,line,_| line.amount_minor }.sum==invoice.amount_minor && BillingInvoiceLine.where(**@w.scope,billing_invoice_id:invoice.id).count==lines.size
    allocated=policy.payload.dig('fields','basis').in?(%w[ending_value average_daily_balance])
    unless allocated
      error('INCOMPLETE_SOURCE','Unexpected partial allocation') if details.any? { |d| %w[line_a line_b].include?(d['id']) }
      return true
    end
    expected_ids=['charge']+bindings.map { |binding| binding.fetch('output_id') }
    unexpected=details.any? { |detail| detail['role']=='terminal' && %w[obligation net_balance].include?(detail['output_class']) && detail['unit'].is_a?(String) && detail['unit'].end_with?('_minor') && !expected_ids.include?(detail['id']) }
    error('INCOMPLETE_SOURCE','Unexpected billable output') if unexpected
    outputs=lines.map do |binding,line,obligation|
      item=pick.call(details,binding.fetch('output_id')); old_item=pick.call(original,binding.fetch('output_id')); validate_output.call(item)
      error('INCOMPLETE_SOURCE','Missing retained billing party') unless old_item['payer']==obligation.customer_id && old_item['payee'].is_a?(String) && !old_item['payee'].empty?
      changed ||= item['assessed_minor']!=line.amount_minor || economic.call(item)!=[obligation.currency,obligation.customer_id,old_item['payee'],{'start'=>obligation.service_period_start.iso8601,'end_exclusive'=>obligation.service_period_end.iso8601},'assessed',"#{obligation.currency}_minor",'obligation']
      expected_account="disclosure-alder-#{binding.fetch('output_id').delete_prefix('line_')}"
      nodes=policy.payload.fetch('graph').fetch('nodes').select { |node| node['id']==binding.fetch('output_id') }
      error('INCOMPLETE_SOURCE','Missing allocation identity') unless nodes.one? && nodes.first['recipient'].is_a?(String)
      changed ||= obligation.account_id!=expected_account || nodes.first['recipient']!=obligation.account_id
      item['assessed_minor']
    end
    error('INCOMPLETE_SOURCE','Allocation does not balance') unless outputs.sum==charge['assessed_minor']
    changed
  rescue KeyError, ActiveRecord::RecordNotFound
    error('INCOMPLETE_SOURCE','Missing retained billing evidence')
  end
  def save_policy(input,key)
    @w.guard!('operator'); keys!(input,%w[case_id base_policy_id policy effective_from effective_to reason])
    case_check!(input['case_id']); interval!(input['effective_from'],input['effective_to']); @m.reason!(input['reason'])
    @w.operate('disclosure_save_policy',input,key) do
      base=get('policy',input['base_policy_id']); id=identifier('policy')
      base_run=rows('run').where("payload->>'policy_id' = ?",base.external_id).order(:id).last
      error('INCOMPLETE_SOURCE','No baseline run exists for this policy') unless base_run
      graph=DisclosurePolicy.build(input['policy'],version:id)
      p=store('policy',id:id,status:'draft',payload:{'fields'=>input['policy'],'graph'=>graph,'base_policy_id'=>base.external_id,'base_policy_hash'=>base.payload_hash,'baseline_run_id'=>base_run.external_id,'terms_ref'=>base.payload.fetch('terms_ref'),'terms_hash'=>base.payload.fetch('terms_hash'),'reason'=>input['reason']},parent:base,starts_on:input['effective_from'],ends_on:input['effective_to'])
      {'id'=>p.external_id,'policy_id'=>p.external_id,'status'=>'draft'}
    end
  end
  def compare(input,key)
    @w.guard!('operator'); keys!(input,%w[case_id policy_id baseline_run_id]); case_check!(input['case_id'])
    @w.operate('disclosure_compare',input,key) do
      policy=get('policy',input['policy_id']); baseline=get('run',input['baseline_run_id'])
      error('SCOPE_MISMATCH','Comparison baseline must match the policy being edited') unless policy.payload['base_policy_id']==baseline.payload['policy_id']
      ctx=baseline.payload.fetch('result').fetch('context')
      result=engine_run(policy,baseline.payload.fetch('input_manifest'),cutoff:baseline.payload.fetch('knowledge_cutoff'),hypothetical:true,service_start:ctx.fetch('service_start'),service_end_exclusive:ctx.fetch('service_end_exclusive'))
      error('INCOMPLETE_SOURCE') unless result['status']=='completed'
      old=baseline.payload.fetch('result'); id=identifier('comparison')
      binding={'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'baseline_run_id'=>baseline.external_id,'baseline_run_hash'=>baseline.payload_hash,
        'baseline_policy_id'=>baseline.payload.fetch('policy_id'),'baseline_policy_hash'=>baseline.payload.fetch('policy_hash'),
        'manifest_hash'=>Economics::Canonical.hash(baseline.payload.fetch('input_manifest')),'terms_ref'=>policy.payload.fetch('terms_ref'),'terms_hash'=>policy.payload.fetch('terms_hash'),'implementation_hash'=>implementation_hash}
      data={'binding'=>binding,'old_amount_minor'=>amount(old,'charge'),'new_amount_minor'=>amount(result,'charge'),'old_lines'=>%w[line_a line_b].map { |x| amount(old,x) },'new_lines'=>%w[line_a line_b].map { |x| amount(result,x) },'result'=>result,'required_roles'=>%w[legal finance]}
      comparison=store('comparison',id:id,status:'completed',payload:data,parent:policy)
      {'id'=>id,'comparison_id'=>id,'policy_id'=>policy.external_id,'old_amount_minor'=>data['old_amount_minor'],'new_amount_minor'=>data['new_amount_minor'],'required_roles'=>data['required_roles'],'status'=>'compared'}
    end
  end
  def binding_current!(comparison)
    b=comparison.payload.fetch('binding'); policy=get('policy',b.fetch('policy_id')); baseline=get('run',b.fetch('baseline_run_id')); terms=get('fact',b.fetch('terms_ref'))
    error('STALE_REVIEW','The comparison evidence or implementation changed') unless policy.payload_hash==b['policy_hash'] && baseline.payload_hash==b['baseline_run_hash'] && terms.payload_hash==b['terms_hash'] && Economics::Canonical.hash(baseline.payload.fetch('input_manifest'))==b['manifest_hash'] && implementation_hash==b['implementation_hash']
    [policy,baseline]
  end
  def review(input,key)
    @w.guard!('legal','finance'); keys!(input,%w[case_id comparison_id decision reason]); case_check!(input['case_id']); @m.reason!(input['reason'])
    error('VALIDATION_ERROR') unless %w[approve reject].include?(input['decision'])
    @w.operate('disclosure_review',input,key) do
      c=get('comparison',input['comparison_id']); binding_current!(c)
      id=identifier('review')
      store('review',id:id,status:(input['decision']=='approve' ? 'approved' : 'rejected'),payload:{'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'role'=>@w.role,'decision'=>input['decision'],'reason'=>input['reason'],'binding'=>c.payload.fetch('binding')},parent:c)
      {'id'=>id,'comparison_id'=>c.external_id,'role'=>@w.role,'decision'=>input['decision']}
    end
  end
  def publish(input,key)
    @w.guard!('operator'); keys!(input,%w[case_id policy_id comparison_id]); case_check!(input['case_id'])
    @w.operate('disclosure_publish_policy',input,key) do
      c=get('comparison',input['comparison_id']); policy,_=binding_current!(c)
      error('SCOPE_MISMATCH') unless policy.external_id==input['policy_id']
      reviews=rows('review').where(parent_id:c.id).order(:id).to_a.group_by { |r| r.payload['role'] }.transform_values(&:last)
      error('REVIEW_REQUIRED','Current Legal and Finance approvals are required') unless %w[legal finance].all? { |role| r=reviews[role]; r && r.status=='approved' && r.payload['comparison_hash']==c.payload_hash && r.payload['binding']==c.payload['binding'] }
      id=identifier('policy-publication')
      store('publication',id:id,status:'published',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'comparison_id'=>c.external_id,'comparison_hash'=>c.payload_hash,'review_ids'=>reviews.values.map(&:external_id)},parent:policy)
      {'id'=>id,'policy_id'=>policy.external_id,'comparison_id'=>c.external_id,'status'=>'published','assigned'=>false}
    end
  end
  def assign(input,key)
    @w.guard!('operator'); keys!(input,%w[case_id policy_id subject_id effective_from effective_to reason supersedes_assignment_id],%w[case_id policy_id subject_id effective_from effective_to reason]); case_check!(input['case_id'])
    error('SCOPE_MISMATCH') unless input['subject_id']==SUBJECT
    interval!(input['effective_from'],input['effective_to']); @m.reason!(input['reason'])
    @w.operate('disclosure_assign_policy',input,key) do
      policy=get('policy',input['policy_id'])
      policy_window!(policy,input['effective_from'],input['effective_to'])
      expected=policy.payload.dig('fields','cadence')=='quarterly' ? ['2027-01-01','2027-04-01'] : [START,FINISH]
      error('INVALID_INTERVAL','The selected fixture policy requires its matching service period') unless [input['effective_from'],input['effective_to']]==expected
      pub=rows('publication').where("payload->>'policy_id' = ? AND payload->>'comparison_id' IS NOT NULL",policy.external_id).order(:id).last
      error('UNAPPROVED_POLICY') unless pub && pub.payload['policy_hash']==policy.payload_hash
      comparison=get('comparison',pub.payload.fetch('comparison_id')); binding_current!(comparison)
      current_reviews=rows('review').where(parent_id:comparison.id).order(:id).to_a.group_by { |review| review.payload['role'] }.transform_values(&:last)
      error('REVIEW_REQUIRED','Published reviews are no longer current') unless %w[legal finance].all? { |role| review=current_reviews[role]; review && review.status=='approved' && pub.payload['review_ids'].include?(review.external_id) && review.payload['comparison_hash']==comparison.payload_hash }
      active=rows('assignment').order(:id).to_a.reject { |row| rows('assignment').where("payload->>'supersedes_assignment_id' = ?",row.external_id).exists? }
      overlap=active.select { |row| (input['effective_to'].nil? || row.starts_on.to_s<input['effective_to']) && (row.ends_on.nil? || input['effective_from']<row.ends_on.to_s) }
      supersedes=input['supersedes_assignment_id']
      if overlap.any?
        error('RULE_CONFLICT','Overlapping assignments require explicit exact-interval supersession') unless overlap.one? && overlap.first.external_id==supersedes && overlap.first.starts_on.to_s==input['effective_from'] && overlap.first.ends_on&.to_s==input['effective_to']
      else
        error('RULE_CONFLICT') if supersedes
      end
      old=overlap.first; id=identifier('assignment')
      row=store('assignment',id:id,status:'published',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'policy_publication_id'=>pub.external_id,'comparison_id'=>comparison.external_id,'subject_id'=>SUBJECT,'reason'=>input['reason'],'supersedes_assignment_id'=>old&.external_id,'supersedes_assignment_hash'=>old&.payload_hash},parent:policy,starts_on:input['effective_from'],ends_on:input['effective_to'],schedule_version:(old ? old.schedule_version+1 : 1))
      {'id'=>row.external_id,'assignment_id'=>row.external_id,'policy_id'=>policy.external_id,'status'=>'assigned'}
    end
  end
  def evaluate(input,key)
    @w.guard!('operator'); keys!(input,%w[case_id knowledge_cutoff]); case_check!(input['case_id']); @m.time!(input['knowledge_cutoff'])
    @w.operate('disclosure_evaluate',input,key) do
      candidates=rows('assignment').where('starts_on <= ? AND (ends_on IS NULL OR ends_on >= ?) AND recorded_at <= ?',START,FINISH,@m.time!(input['knowledge_cutoff'])).order(:id).to_a
      active=candidates.reject { |r| candidates.any? { |newer| newer.payload['supersedes_assignment_id']==r.external_id } }
      error('RULE_CONFLICT') unless active.one?
      assignment=active.first; policy=get('policy',assignment.payload.fetch('policy_id'))
      policy_window!(policy,assignment.starts_on,assignment.ends_on)
      old=get('run','disclosure-run-v1')
      standard=policy.payload.dig('fields','basis')=='ending_value' && policy.payload.dig('fields','cadence')=='monthly'
      manifest=standard ? manifest_for(assignment,input['knowledge_cutoff']) : alternative_manifest_for(policy,assignment,input['knowledge_cutoff'])
      result=engine_run(policy,manifest,cutoff:input['knowledge_cutoff']); error('INCOMPLETE_SOURCE') unless result['status']=='completed'
      changed=correction_required?(result,policy,old)
      id=identifier('run'); run=store('run',id:id,status:'completed',payload:{'policy_id'=>policy.external_id,'policy_hash'=>policy.payload_hash,'assignment_id'=>assignment.external_id,'input_manifest'=>manifest,'implementation_hash'=>implementation_hash,'knowledge_cutoff'=>input['knowledge_cutoff'],'result'=>result},parent:policy)
      publication_id=identifier('publication')
      store('publication',id:publication_id,status:'published',payload:{'run_id'=>id,'run_hash'=>run.payload_hash,'policy_id'=>policy.external_id,'invoice_id'=>'disclosure-invoice-v1','correction_required'=>changed},parent:run)
      {'id'=>id,'run_id'=>id,'publication_id'=>publication_id,'amount_minor'=>amount(result,'charge'),'correction_required'=>changed,'invoice_reissued'=>false}
    end
  end

end
