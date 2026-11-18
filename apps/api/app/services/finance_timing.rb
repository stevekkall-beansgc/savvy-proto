# A fictional, isolated Finance example. The commercial amount is assessed by
# the shared graph interpreter. Recognition and accounting are supplied facts.
class FinanceTiming
  CASE = 'ria'.freeze
  SCENARIO = 'finance_timing_2027'.freeze
  def initialize(workbench)
    @w=workbench; @m=workbench.medallion
  end
  def rows(kind) = @m.source(CASE, SCENARIO, kind)
  def fixture = JSON.parse(rows('artifact').find_by!(external_id:'finance-timing-source').original_bytes)
  def keys!(input, allowed)
    @m.error('VALIDATION_ERROR', 'Unexpected Finance input fields') unless input.is_a?(Hash) && (input.keys - allowed).empty?
  end
  def fact(id, payload, parent: nil, status: 'accepted')
    body=payload.merge('source_artifact_id'=>'finance-timing-source','source_artifact_role'=>'authored_fixture_or_context')
    @m.store!(CASE, SCENARIO, 'fact', id: id, status: status, payload: body, parent: parent)
  end
  def bootstrap(input, key)
    @w.guard!('operator'); @m.error('VALIDATION_ERROR') unless input == {}
    @w.operate('finance_timing_bootstrap',input,key) do
      timing_bytes=File.binread(Rails.root.join('../../fixtures/finance/timing.json'))
      policy_bytes=File.binread(Rails.root.join('../../fixtures/finance/commercial-policy.json'))
      f=JSON.parse(timing_bytes); policy=JSON.parse(policy_bytes)
      author_clock=Time.iso8601('2026-11-01T00:00:00Z')
      artifacts=[['finance-timing-source',timing_bytes],['finance-policy-source',policy_bytes]].map do |id, bytes|
        artifact=@m.store!(CASE,SCENARIO,'artifact',id:id,status:'retained',bytes:bytes,
          payload:{'sha256'=>Digest::SHA256.hexdigest(bytes),'media_type'=>'application/json','fixture'=>true,'source'=>'authored_synthetic_fixture'},recorded_at:author_clock)
        @m.store!(CASE,SCENARIO,'delivery',id:"delivery-#{id}",status:'accepted',parent:artifact,
          payload:{'artifact_id'=>id,'received_at'=>author_clock.iso8601,'source'=>'authored_synthetic_fixture','fixture'=>true},recorded_at:author_clock)
        artifact
      end
      policy_row=@m.store!(CASE,SCENARIO,'policy',id:'finance-commercial-v1',status:'published',parent:artifacts.last,payload:{'policy'=>policy,'synthetic'=>true,'source_artifact_id'=>artifacts.last.external_id},recorded_at:author_clock)
      assignment=@m.store!(CASE,SCENARIO,'assignment',id:'finance-assignment-v1',status:'published',parent:policy_row,
        subject_id:'ria-harbor',product_id:'finance-service',starts_on:f['period_start'],ends_on:f['period_end_exclusive'],
        payload:{'policy_id'=>policy_row.external_id,'policy_hash'=>policy_row.payload_hash,'subject_id'=>'ria-harbor','product_id'=>'finance-service','starts_on'=>f['period_start'],'ends_on'=>f['period_end_exclusive']},recorded_at:Time.iso8601('2026-11-01T00:00:00Z'))
      manifest={'facts'=>{},'assignment'=>{'id'=>assignment.external_id,'revision'=>assignment.revision,'hash'=>assignment.payload_hash},'source_evidence'=>artifacts.map { |a| {'id'=>a.external_id,'revision'=>a.revision,'hash'=>a.payload_hash} }}
      cutoff='2027-01-31T23:59:59Z'
      context={'tenant_id'=>@w.scope[:tenant_id], 'entity_id'=>@w.scope[:entity_id], 'scenario'=>SCENARIO,
        'service_start'=>f['period_start'],'service_end_exclusive'=>f['period_end_exclusive'],'knowledge_cutoff'=>cutoff}
      result=Economics::Engine.new.evaluate(policy_bundle:{'policy'=>policy,'policy_id'=>policy_row.external_id,'policy_hash'=>policy_row.payload_hash,'approved'=>true},input_manifest:manifest,context:context)
      assessed=result.fetch('details').find { |d| d['id']=='service_charge' }.fetch('assessed_minor')
      @m.error('INCOMPLETE_SOURCE') unless assessed.is_a?(Integer) && assessed>0
      run=@m.store!(CASE,SCENARIO,'run',id:'finance-commercial-run-v1',status:'completed',payload:{'policy_id'=>policy_row.external_id,'policy_hash'=>policy_row.payload_hash,'knowledge_cutoff'=>cutoff,'input_manifest'=>manifest,'implementation_hash'=>@w.implementation_hash,'result'=>result,'synthetic'=>true},parent:policy_row)
      attrs={**@w.scope, external_id:'finance-obligation-advance',revision:1,customer_id:'ria-harbor',service_id:'finance-service',broker_id:'ria-harbor',account_id:'ria-harbor',assignment_id:assignment.external_id,client_terms_ref:'finance-commercial-v1',source_id:run.external_id,source_revision:1,legacy_charge_id:'finance-commercial-run-v1',route:'invoice',currency:'USD',amount_minor:assessed,service_period_start:f['period_start'],service_period_end:f['period_end_exclusive']}
      catalog=BillingCatalog.new(@w)
      obligation=catalog.insert!(BillingObligation,{external_id:attrs[:external_id]},attrs)
      invoice=catalog.insert!(BillingInvoice,{external_id:'finance-invoice-advance'},@w.scope.merge(external_id:'finance-invoice-advance',revision:1,debtor_id:'ria-harbor',amount_minor:assessed,currency:'USD',status:'issued',legacy_invoice_id:'finance-invoice-advance'))
      line=catalog.insert!(BillingInvoiceLine,{external_id:'finance-line-advance'},@w.scope.merge(external_id:'finance-line-advance',billing_invoice_id:invoice.id,billing_obligation_id:obligation.id,amount_minor:assessed))
      unbilled_value=result.fetch('details').find { |d| d['id']=='unbilled_service' }.fetch('assessed_minor')
      @m.error('INCOMPLETE_SOURCE') unless unbilled_value.is_a?(Integer) && unbilled_value>0
      ub_attrs=attrs.merge(external_id:'finance-obligation-unbilled',amount_minor:unbilled_value.to_i,service_id:'finance-unbilled-service',service_period_end:'2027-02-01')
      ub_obligation=catalog.insert!(BillingObligation,{external_id:ub_attrs[:external_id]},ub_attrs)
      ub_invoice=catalog.insert!(BillingInvoice,{external_id:'finance-invoice-unbilled'},@w.scope.merge(external_id:'finance-invoice-unbilled',revision:1,debtor_id:'ria-harbor',amount_minor:unbilled_value,currency:'USD',status:'issued',legacy_invoice_id:'finance-invoice-unbilled'))
      catalog.insert!(BillingInvoiceLine,{external_id:'finance-line-unbilled'},@w.scope.merge(external_id:'finance-line-unbilled',billing_invoice_id:ub_invoice.id,billing_obligation_id:ub_obligation.id,amount_minor:unbilled_value))
      f.fetch('invoice_issuance').each do |issuance|
        fact("issuance-#{issuance.fetch('invoice_id')}",issuance.merge('entity_id'=>@w.scope[:entity_id],'currency'=>'USD'))
      end
      cash_rows=f.fetch('cash_sources').to_h do |source|
        amount=source.fetch('amount_minor')
        @m.error('SOURCE_CONFLICT') unless amount==source.fetch('net_minor') && source.fetch('gross_minor')-source.fetch('fee_minor')==amount
        body=source.except('return').merge('currency'=>'USD','debtor_id'=>'ria-harbor','creditor_id'=>'firm-demo','source'=>'fixture_bank_evidence','direction'=>'inbound_client','entity_id'=>@w.scope[:entity_id],'source_artifact_id'=>'finance-timing-source')
        row=@m.store!(CASE,SCENARIO,'payment',id:source.fetch('id'),status:source.fetch('status'),payload:body)
        if source['return']
          fact(source['return'].fetch('id'),source['return'].merge('payment_id'=>row.external_id,'payment_revision'=>row.revision,'payment_hash'=>row.payload_hash,'currency'=>'USD','entity_id'=>@w.scope[:entity_id]),parent:row)
        end
        [row.external_id,row]
      end
      f.fetch('suggestions').each_with_index do |suggestion,index|
        fact("finance-suggestion-#{index+1}",suggestion.merge('currency'=>'USD','entity_id'=>@w.scope[:entity_id]),parent:cash_rows.fetch(suggestion.fetch('payment_id')))
      end
      cash=cash_rows.fetch('finance-cash-900')
      initial=@m.store!(CASE,SCENARIO,'application',id:'finance-association-600',status:'confirmed',parent:cash,payload:{'payment_id'=>cash.external_id,'payment_revision'=>cash.revision,'payment_hash'=>cash.payload_hash,'invoice_id'=>invoice.external_id,'invoice_revision'=>invoice.revision,'invoice_line_id'=>line.external_id,'amount_minor'=>60000,'currency'=>'USD','classification'=>'local_association','accounting_posted'=>false,'posting_period'=>'2027-01','source_artifact_id'=>'finance-timing-source'})
      fact('finance-accounting-initial',f.fetch('mock_accounting_initial').merge('invoice_id'=>invoice.external_id,'cash_id'=>cash.external_id,'application_id'=>initial.external_id,'application_revision'=>initial.revision,'application_hash'=>initial.payload_hash),parent:initial)
      input_record=fact('recognition-input-advance-v1',{'id'=>'recognition-input-advance-v1','revision'=>1,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','run_id'=>run.external_id,'run_revision'=>run.revision,'run_hash'=>run.payload_hash,'result_id'=>'service_charge','invoice_id'=>invoice.external_id,'invoice_revision'=>invoice.revision,'invoice_line_id'=>line.external_id,'invoice_line_revision'=>1,'amount_minor'=>assessed,'service_start'=>f['period_start'],'service_end_exclusive'=>f['period_end_exclusive'],'agreement_ref'=>policy_row.external_id,'treatment'=>f['treatment'],'cutoff'=>'2027-01-31T23:59:59Z','missing_decisions'=>[]},parent:run)
      schedule=fact(f['schedule']['id'],f['schedule'].merge('mocked'=>true,'revision'=>1,'treatment_version'=>1,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','effective_at'=>'2027-01-01T00:00:00Z','received_at'=>'2027-01-31T23:59:59Z'),parent:input_record)
      fact(f['posted']['id'],f['posted'].merge('mocked'=>true,'revision'=>1,'input_id'=>input_record.external_id,'treatment_id'=>f['treatment']['id'],'treatment_version'=>1,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','posted_at'=>'2027-01-31T23:59:59Z','received_at'=>'2027-01-31T23:59:59Z'),parent:schedule)
      ub=f['unbilled']
      ub_input=fact('recognition-input-unbilled-v1',ub.except('outcomes').merge('id'=>'recognition-input-unbilled-v1','revision'=>1,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','run_id'=>run.external_id,'run_revision'=>run.revision,'run_hash'=>run.payload_hash,'result_id'=>'unbilled_service','service_start'=>'2027-01-01','service_end_exclusive'=>'2027-02-01','agreement_ref'=>policy_row.external_id,'cutoff'=>'2027-01-31T23:59:59Z','missing_decisions'=>[]),parent:run)
      billed_input=fact('recognition-input-unbilled-billed-v2',{'id'=>'recognition-input-unbilled-billed-v2','revision'=>2,'supersedes'=>ub_input.external_id,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','run_id'=>run.external_id,'run_revision'=>run.revision,'run_hash'=>run.payload_hash,'result_id'=>'unbilled_service','amount_minor'=>unbilled_value,'invoice_id'=>ub_invoice.external_id,'invoice_revision'=>ub_invoice.revision,'invoice_line_id'=>'finance-line-unbilled','invoice_line_revision'=>1,'invoice_issuance_ref'=>'issuance-finance-invoice-unbilled','invoice_issued_at'=>'2027-02-01T00:00:00Z','invoice_effective_at'=>'2027-02-01T00:00:00Z','invoice_known_at'=>'2027-02-01T00:00:00Z','treatment_id'=>ub['treatment_id'],'treatment_version'=>1,'cutoff'=>'2027-02-28T23:59:59Z'},parent:ub_input)
      ub['outcomes'].each do |outcome|
        package=outcome['period']=='2027-01' ? ub_input : billed_input
        fact(outcome.fetch('id'),outcome.merge('revision'=>1,'mocked'=>true,'input_id'=>package.external_id,'treatment_id'=>ub['treatment_id'],'treatment_version'=>1,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','posted_at'=>outcome['period']+'-28T23:59:59Z','received_at'=>outcome['period']+'-28T23:59:59Z'),parent:package)
      end
      credit=@m.store!(CASE,SCENARIO,'event',id:'finance-credit-proposed',status:'draft',parent:run,payload:{'kind'=>'one_time_credit','invoice_line_id'=>line.external_id,'currency'=>'USD','status'=>'draft','reason'=>'Proposed later credit requires review and accounting treatment'})
      fact('finance-credit-exception',{'id'=>'finance-credit-exception','credit_id'=>credit.external_id,'invoice_line_id'=>line.external_id,'status'=>'needs_treatment','reason'=>'Later credit needs a Finance treatment and posting-period decision; prior evidence is retained'},parent:credit)
      {'synthetic'=>true,'namespace'=>SCENARIO,'run_id'=>run.external_id,'invoice_id'=>invoice.external_id}
    end
  end
  def view(case_id = 'ria')
    @w.guard!('operator','finance','auditor')
    @m.case!(case_id)
    return advisor_view if case_id == 'advisor'
    run=rows('run').find_by(external_id:'finance-commercial-run-v1')
    return {'available'=>false,'reason'=>'The isolated Finance fixture has not been initialized.'} unless run
    invoice=BillingInvoice.find_by!(**@w.scope,external_id:'finance-invoice-advance')
    reversals=rows('application_reversal').pluck(:parent_id)
    applications=rows('application').order(:id).map { |a| a.payload.merge('id'=>a.external_id,'status'=>reversals.include?(a.id) ? 'reversed' : 'confirmed') }
    returned=rows('fact').where("payload->>'status' = ?",'returned').order(:id).map(&:payload)
    payments=rows('payment').order(:id).map do |p|
      linked=applications.select { |a| a['payment_id']==p.external_id }
      used=@m.assessed_sum(linked.select { |a| a['status']=='confirmed' }.map { |a| a.fetch('amount_minor') })
      is_returned=returned.any? { |r| r['payment_id']==p.external_id }
      p.payload.merge('id'=>p.external_id,'revision'=>p.revision,'status'=>is_returned ? 'returned' : p.status,
        'associated_minor'=>used,'unapplied_minor'=>is_returned ? 0 : @m.assessed_difference(p.payload['amount_minor'],used),'applications'=>linked)
    end
    cash=payments.find { |p| p['id']=='finance-cash-900' }
    invoices=rows('fact').where("external_id LIKE 'issuance-%'").order(:id).map do |issuance|
      row=BillingInvoice.find_by!(**@w.scope,external_id:issuance.payload.fetch('invoice_id'))
      linked=applications.select { |a| a['invoice_id']==row.external_id && a['status']=='confirmed' }
      used=@m.assessed_sum(linked.map { |a| a.fetch('amount_minor') })
      issuance.payload.merge('id'=>row.external_id,'line_id'=>issuance.payload.fetch('invoice_line_id'),'amount_minor'=>row.amount_minor,
        'associated_minor'=>used,'residual_minor'=>@m.assessed_difference(row.amount_minor,used))
    end
    suggestions=rows('fact').where("external_id LIKE 'finance-suggestion-%'").order(:id).map(&:payload)
    accounting=rows('fact').where("external_id LIKE 'finance-accounting-%'").order(:id).map(&:payload)
    records=rows('fact').where("external_id LIKE 'recognition-%' OR external_id LIKE 'schedule-%' OR external_id LIKE 'journal-%'").order(:id).map { |r| r.payload.merge('record_id'=>r.external_id) }
    exceptions=[rows('fact').find_by!(external_id:'finance-credit-exception').payload]
    accounting.each do |outcome|
      refs=Array(outcome['application_ids']) | Array(outcome['application_id'])
      linked=applications.find { |item| refs.include?(item['id']) && item['status']=='reversed' }
      if linked
        exceptions << {'id'=>'accounting-correction-required','status'=>'needs_review','application_id'=>linked['id'],
          'reason'=>'A local association was reversed after the mock accounting outcome. Request an independent accounting correction; the posted evidence remains unchanged.'}
      end
    end
    {'available'=>true,'context'=>{'namespace'=>SCENARIO,'case_id'=>CASE,'entity_id'=>@w.scope[:entity_id],'currency'=>'USD','period_start'=>'2027-01-01','period_end_exclusive'=>'2027-04-01'},
     'commercial'=>{'run_id'=>run.external_id,'result_id'=>'service_charge','invoice_id'=>invoice.external_id,'invoice_line_id'=>'finance-line-advance','amount_minor'=>invoice.amount_minor},
     'cash'=>{'id'=>cash['id'],'amount_minor'=>cash['amount_minor'],'associated_minor'=>cash['associated_minor'],'unapplied_minor'=>cash['unapplied_minor'],'payments'=>payments,'invoices'=>invoices,'suggestions'=>suggestions,'returns'=>returned,'applications'=>applications,'accounting_outcomes'=>accounting},
     'recognition'=>{'records'=>records,'missing_outcome'=>{'period'=>'2027-02','status'=>'missing','next_action'=>'Await independent posted outcome'}},
     'exceptions'=>exceptions}
  end
  # The advisor book uses its own baseline evidence and existing governed
  # medallion application commands. No RIA fixture values enter these totals.
  def advisor_view
    scope=@m.source('advisor','baseline','payment')
    applications=@m.source('advisor','baseline','application').order(:id).to_a
    reversed=@m.source('advisor','baseline','application_reversal').pluck(:parent_id)
    payments=scope.order(:id).map do |row|
      linked=applications.select { |a| a.parent_id==row.id }
      used=@m.assessed_sum(linked.reject { |a| reversed.include?(a.id) }.map { |a| a.payload.fetch('amount_minor') })
      {'id'=>row.external_id,'revision'=>row.revision,'status'=>row.status,'direction'=>'outbound_advisor',
        'amount_minor'=>row.payload['amount_minor'],'currency'=>row.payload['currency'],
        'associated_minor'=>used,'unapplied_minor'=>@m.assessed_difference(row.payload['amount_minor'],used),
        'applications'=>linked.map { |a| a.payload.merge('id'=>a.external_id,'status'=>reversed.include?(a.id) ? 'reversed' : 'confirmed') }}
    end
    alternate_rows=@m.source('advisor','confirmed_payment','payment').order(:id).to_a
    alternate_applications=@m.source('advisor','confirmed_payment','application').order(:id).to_a
    alternate_reversals=@m.source('advisor','confirmed_payment','application_reversal').order(:id).to_a
    alternate_payments=alternate_rows.map do |p|
      linked=alternate_applications.select { |a| a.parent_id==p.id }
      {'id'=>p.external_id,'revision'=>p.revision,'payload_hash'=>p.payload_hash,'status'=>p.status,'direction'=>'outbound_advisor',
        'source'=>'independent_synthetic_payment_evidence','amount_minor'=>p.payload['amount_minor'],'currency'=>p.payload['currency'],
        'observed_at'=>p.payload['observed_at'],'applications'=>linked.map { |a| a.payload.merge('id'=>a.external_id,'revision'=>a.revision,'hash'=>a.payload_hash) }}
    end
    alternative={'namespace'=>'confirmed_payment','label'=>'Separate confirmed payment example','direction'=>'outbound_advisor',
      'payments'=>alternate_payments,
      'applications'=>alternate_applications.map { |a| a.payload.merge('id'=>a.external_id,'revision'=>a.revision,'hash'=>a.payload_hash) },
      'reversals'=>alternate_reversals.map { |a| a.payload.merge('id'=>a.external_id,'revision'=>a.revision,'hash'=>a.payload_hash) },
      'instructions'=>[], 'instruction_status'=>'No linked payout instruction evidence was recorded for this payment.',
      'reversal_status'=>alternate_reversals.empty? ? 'No reversal evidence recorded.' : 'See linked reversal evidence.'}
    funding=@m.source('advisor','baseline','funding').order(:id).map { |r| r.payload.merge('id'=>r.external_id,'recorded_status'=>r.status,'direction'=>'outbound_advisor') }
    run=@m.source('advisor','baseline','run').where(status:'completed').order(:id).last
    {'available'=>true,'context'=>{'case_id'=>'advisor','namespace'=>'baseline','entity_id'=>@w.scope[:entity_id],'currency'=>'USD','period_start'=>'2026-09-01','period_end_exclusive'=>'2026-10-01'},
      'commercial'=>run ? {'run_id'=>run.external_id,'result_id'=>'payable','direction'=>'outbound_advisor'} : nil,
      'cash'=>{'direction'=>'outbound_advisor','payments'=>payments,'funding'=>funding,'alternative_contexts'=>[alternative],'applications'=>payments.flat_map { |p| p['applications'] },'accounting_outcomes'=>[],
        'amount_minor'=>nil,'associated_minor'=>nil,'unapplied_minor'=>nil},
      'recognition'=>{'records'=>[],'missing_outcome'=>{'status'=>'not_applicable','next_action'=>'Advisor compensation is not Savvy revenue; no recognition outcome is inferred.'}},
      'exceptions'=>[]}
  end
  def associate(input,key)
    @w.guard!('finance')
    keys!(input,%w[payment_id invoice_id currency amount_minor posting_period reason])
    @w.operate('finance_timing_associate',input,key) do
      cash=rows('payment').find_by(external_id:input['payment_id']) || @m.error('SCOPE_MISMATCH')
      invoice=BillingInvoice.find_by(**@w.scope,external_id:input['invoice_id']) || @m.error('SCOPE_MISMATCH')
      suggestion=rows('fact').where("payload->>'payment_id' = ? AND payload->>'invoice_id' = ? AND payload->>'status' = ?",cash.external_id,invoice.external_id,'suggested').first
      @m.error('SCOPE_MISMATCH') unless suggestion && input['currency']=='USD' && cash.payload['currency']==invoice.currency &&
        cash.payload['debtor_id']==invoice.debtor_id && cash.payload['creditor_id']=='firm-demo' && cash.payload['entity_id']==@w.scope[:entity_id]
      @m.error('UNRESOLVED_MAPPING','Returned cash cannot be associated') if rows('fact').where(parent_id:cash.id).where("payload->>'status' = ?",'returned').exists?
      amount=Economics::Engine.integer!(input['amount_minor'],'amount_minor',min:1)
      reason=@m.reason!(input['reason'])
      posting_period=@m.unlocked_period!(CASE,SCENARIO,input.fetch('posting_period'))
      issuance=rows('fact').find_by!(external_id:"issuance-#{invoice.external_id}")
      @m.error('FUTURE_EVIDENCE','Invoice or cash was not yet known in this posting period') if posting_period < issuance.payload.fetch('known_at')[0,7] || posting_period < cash.payload.fetch('observed_at')[0,7]
      reversals=rows('application_reversal').select(:parent_id)
      active=rows('application').where.not(id:reversals).to_a
      used_cash=@m.assessed_sum(active.select { |a| a.parent_id==cash.id }.map { |a| a.payload['amount_minor'] })
      used_invoice=@m.assessed_sum(active.select { |a| a.payload['invoice_id']==invoice.external_id }.map { |a| a.payload['amount_minor'] })
      @m.error('ALLOCATION_EXCEEDED') if amount>@m.assessed_difference(cash.payload['amount_minor'],used_cash) || amount>@m.assessed_difference(invoice.amount_minor,used_invoice)
      id="finance-association-#{SecureRandom.uuid}"
      @m.store!(CASE,SCENARIO,'application',id:id,status:'confirmed',parent:cash,payload:{'payment_id'=>cash.external_id,'payment_revision'=>cash.revision,'payment_hash'=>cash.payload_hash,'invoice_id'=>invoice.external_id,'invoice_revision'=>invoice.revision,'invoice_line_id'=>issuance.payload.fetch('invoice_line_id'),'suggestion_id'=>suggestion.external_id,'amount_minor'=>amount,'currency'=>'USD','classification'=>'local_association','accounting_posted'=>false,'reason'=>reason,'posting_period'=>posting_period})
      {'id'=>id,'accounting_posted'=>false,'cash_executed'=>false}
    end
  end
  def reverse(input,key)
    @w.guard!('finance')
    keys!(input,%w[application_id reason posting_period])
    @w.operate('finance_timing_reverse',input,key) do
      original=@m.get!(CASE,SCENARIO,'application',input.fetch('application_id'))
      @m.error('ALREADY_REVERSED') if rows('application_reversal').where(parent_id:original.id).exists?
      reason=@m.reason!(input['reason']); posting_period=@m.unlocked_period!(CASE,SCENARIO,input.fetch('posting_period'))
      @m.error('FUTURE_EVIDENCE','Reversal cannot precede its association posting period') if posting_period < original.payload.fetch('posting_period')
      id="finance-reversal-#{SecureRandom.uuid}"
      @m.store!(CASE,SCENARIO,'application_reversal',id:id,status:'reversed',parent:original,payload:{'application_id'=>original.external_id,'application_hash'=>original.payload_hash,'reason'=>reason,'posting_period'=>posting_period})
      {'id'=>id,'cash_refunded'=>false,'accounting_posted'=>false}
    end
  end
  # This is an authored fixture response, not a local AR calculation. It only
  # acknowledges the precise outstanding fixture application.
  def mock_acknowledge(input,key)
    @w.guard!('finance')
    keys!(input,%w[application_id])
    @w.operate('finance_timing_mock_ack',input,key) do
      association=@m.get!(CASE,SCENARIO,'application',input.fetch('application_id'))
      @m.error('UNRESOLVED_MAPPING') unless association.payload['amount_minor']==30000 && association.payload['invoice_id']=='finance-invoice-advance' && association.payload['payment_id']=='finance-cash-900'
      @m.error('FUTURE_EVIDENCE','The supplied mock acknowledgment predates this association posting period') if association.payload.fetch('posting_period') > fixture.fetch('mock_accounting_acknowledgment').fetch('observed_at')[0,7]
      @m.error('UNRESOLVED_MAPPING') if rows('application_reversal').where(parent_id:association.id).exists?
      @m.error('SOURCE_CONFLICT') if rows('fact').where(external_id:'finance-accounting-after-900').exists?
      first=@m.get!(CASE,SCENARIO,'application','finance-association-600')
      @m.error('UNRESOLVED_MAPPING') if rows('application_reversal').where(parent_id:first.id).exists?
      active=rows('application').where.not(id:rows('application_reversal').select(:parent_id)).to_a
      applied=@m.assessed_sum(active.select { |a| a.payload['invoice_id']=='finance-invoice-advance' }.map { |a| a.payload['amount_minor'] })
      @m.error('UNRESOLVED_MAPPING','The supplied acknowledgment only matches the original fixture and $300 association') unless applied==90000 && active.select { |a| a.payload['invoice_id']=='finance-invoice-advance' }.map(&:external_id).sort==[first.external_id,association.external_id].sort
      body=fixture.fetch('mock_accounting_acknowledgment').merge('application_id'=>association.external_id,'application_revision'=>association.revision,'application_hash'=>association.payload_hash,'application_ids'=>[first.external_id,association.external_id])
      fact('finance-accounting-after-900',body,parent:association)
      body
    end
  end

end
