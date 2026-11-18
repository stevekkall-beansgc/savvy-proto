# Audience-scoped read projection. It never prices or writes evidence.
class DisclosureReadModel
  def initialize(workbench)
    @w=workbench; @m=workbench.medallion
  end
  def view(case_id,audience:,limit:nil,offset:nil)
    @m.case!(case_id)
    @m.error('VALIDATION_ERROR') unless %w[client product finance].include?(audience)
    if audience=='client'
      AudienceReadModel.new(@w).authorize!(case_id)
    elsif audience=='finance'
      @w.guard!('operator','finance','auditor')
    else
      @w.guard!('operator','legal','auditor')
    end
    limit=limit || 20; offset=offset || 0
    @m.error('VALIDATION_ERROR') unless limit.is_a?(Integer) && limit.between?(1,100) && offset.is_a?(Integer) && offset>=0
    body={'contract_version'=>'disclosure/v1','available'=>false,'case_id'=>case_id,'audience'=>audience,
      'context'=>{'namespace'=>DisclosureWorkbench::NS,'currency'=>'USD','service_start'=>DisclosureWorkbench::START,'service_end_exclusive'=>DisclosureWorkbench::FINISH,'knowledge_cutoff'=>DisclosureWorkbench::CUTOFF},
      'summary'=>{},'sections'=>%w[billing valuation terms lifecycle compensation costs recognition policy_options changes].to_h { |name| [name,[]] },'page'=>{'limit'=>limit,'offset'=>offset,'total'=>0},'exceptions'=>[]}
    if case_id=='ria'
      row=@m.source(case_id,DisclosureWorkbench::NS,'fact').find_by(external_id:'disclosure-ria-cost-source')
      return body unless row
      obs=row.payload.fetch('observation')
      body['available']=true; body['context']['knowledge_cutoff']=obs['recorded_at']
      cost={'id'=>row.external_id,'label'=>'Observed custodial charge','classification'=>obs['classification'],'amount_minor'=>obs['amount_minor'],'currency'=>obs['currency'],'payer'=>obs['payer'],'payee'=>obs['payee'],'charger'=>obs['charger'],'category'=>obs['category'],'source'=>'Custodian statement','service_start'=>obs['service_start'],'service_end_exclusive'=>obs['service_end_exclusive'],'reason'=>obs['reason'],'included_in_subtotal'=>false}
      cost['record_id']=row.id.to_s if audience!='client'
      body['sections']['costs']=[cost].drop(offset).take(limit);body['page']['total']=1
      return body
    end
    return body unless case_id==DisclosureWorkbench::CASE
    scope=@m.source(case_id,DisclosureWorkbench::NS,'publication').where("payload->>'run_id' IS NOT NULL").order(:id)
    publication=scope.last; return body unless publication
    run=@m.get!(case_id,DisclosureWorkbench::NS,'run',publication.payload.fetch('run_id'))
    original=@m.get!(case_id,DisclosureWorkbench::NS,'run','disclosure-run-v1')
    details=original.payload.fetch('result').fetch('details').index_by { |d| d['id'] }
    body['context']['knowledge_cutoff']=run.payload['knowledge_cutoff']
    body['available']=true
    body['summary']={'selected_policy_id'=>publication.payload['policy_id'],'selected_run_id'=>run.external_id,'publication_id'=>publication.external_id,'status'=>publication.status,'current_assignment_id'=>run.payload['assignment_id'],'correction_required'=>publication.payload['correction_required']==true}
    billed_policy=@m.get!(case_id,DisclosureWorkbench::NS,'policy',original.payload.fetch('policy_id'))
    billed_fields=billed_policy.payload.fetch('fields')
    valuation_fact=original.payload.dig('input_manifest','facts','a_eligible')
    valuation_row=valuation_fact && @m.source(case_id,DisclosureWorkbench::NS,'fact').find_by(external_id:valuation_fact['id'],revision:valuation_fact['revision'],payload_hash:valuation_fact['hash'])
    valuation_date=valuation_row&.payload&.dig('observation','date')
    common={'currency'=>'USD','payer'=>DisclosureWorkbench::SUBJECT,'payee'=>'firm-demo','service_start'=>DisclosureWorkbench::START,'service_end_exclusive'=>DisclosureWorkbench::FINISH,'run_id'=>original.external_id}
    %w[charge line_a line_b].each do |id|
      detail=details.fetch(id)
      item=common.merge('id'=>"disclosure-#{id}",'label'=>{'charge'=>'Household advisory charge','line_a'=>'Account A allocation','line_b'=>'Account B allocation'}.fetch(id),'classification'=>'assessed','amount_minor'=>detail['assessed_minor'],'output_id'=>id)
      item.merge!('basis'=>billed_fields['basis'],'annual_rate'=>billed_fields['annual_rate'],'cadence'=>billed_fields['cadence'],'valuation_date'=>valuation_date,'reason'=>id=='charge' ? 'The annual rate applies to eligible household assets for one month. The account lines allocate this same charge.' : 'This line allocates the household charge to this account; it is not an additional charge.')
      if id=='charge'
        issuance=@m.source(case_id,DisclosureWorkbench::NS,'fact').find_by(external_id:'disclosure-invoice-issuance')
        if issuance
          item['issued_at']=issuance.payload['issued_at']; item['due_on']=issuance.payload['due_on']
        end
      end
      if audience!='client'
        invoice=BillingInvoice.find_by!(**@w.scope,external_id:'disclosure-invoice-v1')
        line=BillingInvoiceLine.find_by(**@w.scope,external_id:"disclosure-#{id.tr('_','-')}") if id!='charge'
        item['record_id']=id=='charge' ? "invoice:#{invoice.id}" : (line ? "invoice_line:#{line.id}" : original.id.to_s)
      end
      body['sections']['billing'] << item
    end
    if publication.payload['correction_required']
      current=run.payload.fetch('result').fetch('details').find { |d| d['id']=='charge' }
      body['sections']['billing'] << common.merge('id'=>'disclosure-current-assessment','label'=>'Current assessment requiring billing review','classification'=>'unbilled_assessment','amount_minor'=>current['assessed_minor'],'run_id'=>run.external_id,'output_id'=>'charge','status'=>'correction_required')
      body['exceptions'] << {'id'=>'disclosure-correction-required','reason'=>'The current assessment differs from the original invoice. Review a correction; the original invoice is unchanged.'}
    end
    %w[reported excluded eligible].each do |id|
      value=common.merge('id'=>"disclosure-#{id}",'label'=>{'reported'=>'Reported assets','excluded'=>'Excluded assets','eligible'=>'Eligible assets'}.fetch(id),'classification'=>'source_reported','amount_minor'=>Rational(details.fetch(id)['exact_amount']).to_i,'output_id'=>id)
      explanation={'reported'=>'All selected reported holdings before eligibility exclusions.','excluded'=>'Private and held-away holdings excluded under the original terms. These are already part of reported assets.','eligible'=>'Selected reported holdings that qualify under the original terms. Private and held-away holdings are excluded.'}.fetch(id)
      value.merge!('basis'=>billed_fields['basis'],'valuation_date'=>valuation_date,'reason'=>explanation)
      value['record_id']=original.id.to_s if audience!='client'
      body['sections']['valuation'] << value
    end
    [['a_private','Account A private assets'],['b_held_away','Account B held-away assets']].each do |key,label|
      fact=original.payload.dig('input_manifest','facts',key); next unless fact
      row=@m.source(case_id,DisclosureWorkbench::NS,'fact').find_by(external_id:fact['id'],revision:fact['revision'],payload_hash:fact['hash'])
      next unless row && row.payload['observation']
      observation=row.payload['observation']
      value=common.merge('id'=>"disclosure-excluded-#{key.tr('_','-')}",'label'=>label,'classification'=>'excluded_holding','amount_minor'=>observation['amount_minor'],'reason'=>"#{observation['reason']}. This is part of excluded assets and is not added again.",'source'=>'Selected valuation observation','valuation_date'=>observation['date'],'basis'=>billed_fields['basis'],'output_id'=>key)
      value['record_id']=row.id.to_s if audience!='client'
      body['sections']['valuation'] << value
    end
    policy=@m.get!(case_id,DisclosureWorkbench::NS,'policy',publication.payload.fetch('policy_id'))
    body['sections']['terms'] << {'id'=>'disclosure-terms-v1','label'=>'Original invoice terms · ending value on January 31','classification'=>'fictional_terms','annual_rate'=>billed_policy.payload.fetch('fields').fetch('annual_rate'),'cadence'=>billed_policy.payload.fetch('fields').fetch('cadence'),'service_start'=>DisclosureWorkbench::START,'service_end_exclusive'=>DisclosureWorkbench::FINISH}
    body['sections']['terms'].last['record_id']=billed_policy.id.to_s if audience!='client'
    if policy.external_id != billed_policy.external_id
      body['sections']['terms'] << {'id'=>'disclosure-current-terms','label'=>"Current selected terms · #{policy.payload.fetch('fields')['basis'].to_s.tr('_',' ')} · billing correction review",'classification'=>'selected_policy','annual_rate'=>policy.payload.fetch('fields')['annual_rate'],'cadence'=>policy.payload.fetch('fields')['cadence'],'service_start'=>run.payload.dig('result','context','service_start'),'service_end_exclusive'=>run.payload.dig('result','context','service_end_exclusive')}
      body['sections']['terms'].last.merge!(policy.payload.fetch('fields').slice('basis','fixed_amount_minor','hourly_rate_minor','optional_amount_minor','service_mode','optional_service'))
      body['sections']['terms'].last['record_id']=policy.id.to_s if audience!='client'
    end
    # Lifecycle outputs are taken from the retained engine run; observations and
    # accounting outcomes stay separate and are never inferred from billing.
    lifecycle=@m.source(case_id,DisclosureWorkbench::NS,'run').find_by(external_id:'disclosure-lifecycle-run-v1')
    if lifecycle
      body['context']['lifecycle_knowledge_cutoff']=lifecycle.payload['knowledge_cutoff']
      outputs=lifecycle.payload.fetch('result').fetch('details').index_by { |d| d['id'] }
      amount_for=->(id) { outputs[id] && outputs[id]['assessed_minor'] }
      find_row=->(kind,id) { @m.source(case_id,DisclosureWorkbench::NS,kind).find_by(external_id:id) }
      item=->(id,label,classification,amount,kind,record_id,extra={}) do
        row=find_row.call(kind,record_id)
        result=common.merge('id'=>id,'label'=>label,'classification'=>classification,'amount_minor'=>amount,'status'=>row&.status).merge(extra)
        result['record_id']=row.id.to_s if audience!='client' && row
        result
      end
      credit=find_row.call('event','disclosure-credit')
      credit_run=credit && find_row.call('run',credit.payload['run_id'])
      credit_detail=credit_run && credit_run.payload.fetch('result').fetch('details').find { |d| d['id']==credit.payload['output_id'] }
      credit_valid=credit && credit_detail && credit_detail['assessed_minor']==credit.payload['amount_minor']
      refund=find_row.call('payment','disclosure-refund')
      receipt=find_row.call('payment','disclosure-receipt')
      application=find_row.call('application','disclosure-refund-application')
      refund_linked=refund && receipt && credit_valid && application && application.status=='confirmed' && application.payload['payment_id']==refund.external_id && application.payload['payment_hash']==refund.payload_hash && application.payload['credit_id']==credit.external_id && application.payload['credit_hash']==credit.payload_hash && application.payload['original_receipt_id']==receipt.external_id && application.payload['original_receipt_hash']==receipt.payload_hash && application.payload['amount_minor']==refund.payload['amount_minor']
      body['sections']['lifecycle'] << item.call('disclosure-credit','Termination credit','commercial_credit',credit_detail['assessed_minor'],'event','disclosure-credit',{'reason'=>'Approved credit for unused prepaid service; it is separate from refund cash.','run_id'=>credit.payload['run_id'],'output_id'=>'credit','payer'=>'firm-demo','payee'=>DisclosureWorkbench::SUBJECT}) if credit_valid
      if outputs['service_retained']
        body['sections']['lifecycle'] << item.call('disclosure-service-retained','Charge for service retained','retained_service_charge',amount_for.call('service_retained'),'run','disclosure-lifecycle-run-v1',{'reason'=>'The portion of the original invoice retained after the termination credit; not an additional charge.','run_id'=>lifecycle.external_id,'output_id'=>'service_retained'})
      end
      if credit_valid
        %w[a b].each do |member|
          output="credit_#{member}"
          detail=credit_run.payload.fetch('result').fetch('details').find { |d| d['id']==output }
          next unless detail
          body['sections']['lifecycle'] << item.call("disclosure-credit-#{member}","Termination credit · account #{member.upcase}",'credit_allocation',detail['assessed_minor'],'event','disclosure-credit',{'reason'=>'Allocation of the termination credit to the original account invoice line; not an additional credit.','run_id'=>credit_run.external_id,'output_id'=>output,'payer'=>'firm-demo','payee'=>DisclosureWorkbench::SUBJECT})
        end
      end
      body['sections']['lifecycle'] << item.call('disclosure-refund','Refund sent','confirmed_outbound_refund',refund.payload['amount_minor'],'payment','disclosure-refund',{'reason'=>'Separately evidenced outbound cash.','payer'=>'firm-demo','payee'=>DisclosureWorkbench::SUBJECT}) if refund_linked
      if refund && !refund_linked
        body['exceptions'] << {'id'=>'disclosure-refund-unmatched','reason'=>'Refund evidence is not linked to the original receipt and credit; review the application.'}
      end
      body['sections']['lifecycle'] << item.call('disclosure-refund-remaining','Refund still outstanding','refund_obligation',amount_for.call('refund_remaining'),'application','disclosure-refund-application',{'reason'=>'Remaining credit after the evidenced refund.','run_id'=>lifecycle.external_id,'output_id'=>'refund_remaining','payer'=>'firm-demo','payee'=>DisclosureWorkbench::SUBJECT}) if refund_linked
      body['sections']['lifecycle'] << item.call('disclosure-receipt','Original receipt','confirmed_inbound_receipt',receipt.payload['amount_minor'],'payment','disclosure-receipt',{'reason'=>'Separately evidenced inbound cash.'}) if audience=='finance' && receipt
      if audience!='finance'
        [['salary_entitlement','Salary entitlement','salary','disclosure-salary-terms','Salary entitlement; this observation records no confirmed payment.'],['bonus_entitlement','Bonus entitlement','bonus','disclosure-bonus-event','Bonus entitlement; payment is not inferred.'],['loan_entitlement','Transition loan principal','loan_principal','disclosure-loan-terms','Loan principal is not fee revenue or salary.'],['forgiveness_entitlement','Loan forgiveness','loan_forgiveness','disclosure-forgiveness-event','A separate forgiveness event; it is not another cash payment.'],['loan_outstanding','Loan principal outstanding','loan_balance','disclosure-forgiveness-event','Outstanding principal after forgiveness.']].each do |output,label,classification,source,reason|
          body['sections']['compensation'] << item.call("disclosure-#{output.tr('_','-')}",label,classification,amount_for.call(output),'fact',source,{'reason'=>reason,'run_id'=>lifecycle.external_id,'output_id'=>output,'payer'=>'firm-demo','payee'=>'advisor-demo'})
        end
        loan_cash=find_row.call('payment','disclosure-loan-cash')
        loan_terms=find_row.call('fact','disclosure-loan-terms')
        if loan_cash && loan_terms && loan_cash.status=='confirmed' && loan_cash.payload['loan_terms_id']==loan_terms.external_id && loan_cash.payload['loan_terms_hash']==loan_terms.payload_hash
          body['sections']['compensation'] << item.call('disclosure-loan-cash','Loan cash advance','confirmed_loan_advance',loan_cash.payload['amount_minor'],'payment','disclosure-loan-cash',{'reason'=>'Separately evidenced outbound loan cash; not salary or advisory revenue.','payer'=>'firm-demo','payee'=>'advisor-demo'})
        end
        equity=find_row.call('fact','disclosure-equity-award')
        if equity
          observation=equity.payload.fetch('observation')
          body['sections']['compensation'] << item.call('disclosure-equity','Equity award','equity_award',nil,'fact','disclosure-equity-award',{'quantity'=>"#{observation['units']} units",'reason'=>observation['reason'],'payer'=>'firm-demo','payee'=>'advisor-demo'})
        end
      end
      body['sections']['costs'] << common.merge('id'=>'disclosure-advisory-cost','label'=>'Savvy advisory charge','classification'=>'assessed_advisory_charge','amount_minor'=>details.fetch('charge')['assessed_minor'],'output_id'=>'charge','reason'=>'The Savvy assessed charge, also shown on the invoice; it is counted once.','category'=>'advisory','charger'=>'firm-demo','source'=>'Savvy invoice','included_in_subtotal'=>true)
      observed_advisory=find_row.call('fact','disclosure-custodian-advisory-observation')
      if observed_advisory
        obs=observed_advisory.payload.fetch('observation')
        if obs['original_invoice_id']=='disclosure-invoice-v1' && obs['amount_minor']==details.fetch('charge')['assessed_minor']
          body['sections']['costs'] << item.call('disclosure-custodian-advisory-observation','Advisory charge also shown by custodian','observed_duplicate_of_assessed_charge',obs['amount_minor'],'fact','disclosure-custodian-advisory-observation',{'payer'=>obs['payer'],'payee'=>obs['recipient'],'charger'=>obs['charger'],'category'=>obs['category'],'source'=>'Custodian statement','included_in_subtotal'=>false,'reason'=>'This observes the same Savvy invoice charge and is not counted again.'})
        else
          body['exceptions'] << {'id'=>'disclosure-observation-conflict','reason'=>'The custodian advisory observation does not match the original invoice.'}
        end
      end
      custody=find_row.call('fact','disclosure-custody-statement')
      if custody
        obs=custody.payload.fetch('observation')
        body['sections']['costs'] << item.call('disclosure-custody-cost','Custodian charge','observed_outside_charge',obs['amount_minor'],'fact','disclosure-custody-statement',{'payer'=>obs['payer'],'payee'=>obs['recipient'],'reason'=>'Separate custodian charge, outside the Savvy invoice.','category'=>'custodial','charger'=>obs['charger'],'source'=>'Custodian statement','included_in_subtotal'=>true})
      end
      body['sections']['costs'] << item.call('disclosure-known-direct','Known direct charges','known_direct_subtotal',amount_for.call('known_direct'),'run','disclosure-lifecycle-run-v1',{'reason'=>'Includes the assessed advisory charge and separate observed custodian charge.','category'=>'direct charges','charger'=>nil,'payee'=>nil,'included_in_subtotal'=>nil,'source'=>'Engine output from the invoice and custodian statement','run_id'=>lifecycle.external_id,'output_id'=>'known_direct'})
      fund=find_row.call('fact','disclosure-fund-cost')
      body['sections']['costs'] << item.call('disclosure-fund-cost','Total costs incomplete','embedded_cost',nil,'fact','disclosure-fund-cost',{'reason'=>fund.payload.dig('observation','reason'),'category'=>'embedded fund costs','charger'=>nil,'source'=>'Fund-cost observation','included_in_subtotal'=>false,'payer'=>DisclosureWorkbench::SUBJECT,'payee'=>nil}) if fund
      if audience=='finance'
        if publication.payload['correction_required']
          body['exceptions'] << {'id'=>'disclosure-recognition-correction-required','reason'=>'The supplied recognition schedule belongs to the original commercial input. The changed assessment requires new accounting treatment or correction evidence.'}
        end
        [['disclosure-recognition-input','Commercial input package','commercial_input'],['disclosure-recognition-schedule','Supplied recognition schedule','supplied_schedule'],['disclosure-recognition-posted','Reported recognition posting','mock_posting']].each do |id,label,classification|
          row=find_row.call('fact',id); next unless row
          amount=classification=='mock_posting' ? row.payload['recognized_minor'] : nil
          reason=case classification
          when 'commercial_input' then 'Links the original invoice and termination credit to the accounting input.'
          when 'supplied_schedule' then 'Finance supplied this treatment; a schedule is not a posted outcome.'
          else 'Reported recognized amount before the credit correction.' end
          extra={'reason'=>reason,'deferred_minor'=>row.payload['deferred_minor']}
          if classification=='supplied_schedule'
            treatment=row.payload.fetch('treatment')
            extra['supplied_treatment']=treatment.slice('initial_deferred_minor','recognized_minor','deferred_before_credit_minor','correction_deferred_minor','missing_outcome')
          end
          body['sections']['recognition'] << item.call(id,label,classification,amount,'fact',id,extra)
        end
        body['sections']['recognition'] << {'id'=>'disclosure-recognition-missing','label'=>'Correction posting not received','classification'=>'missing_posting','amount_minor'=>nil,'reason'=>'Await independent posting for the credit correction.'}
      end
    end
    if audience=='product'
      body['sections']['policy_options'] << {'id'=>policy.external_id,'label'=>"Selected #{policy.payload.fetch('fields')['basis'].to_s.tr('_',' ')} terms",'classification'=>'selected_policy','fields'=>policy.payload['fields'],'comparison_only'=>false,'record_id'=>policy.id.to_s}
      @m.source(case_id,DisclosureWorkbench::NS,'run').where("payload->>'comparison_only' = ?",'true').order(:id).each do |option|
        detail=option.payload.fetch('result').fetch('details').find { |d| d['id']=='charge' }
        option_policy=@m.get!(case_id,DisclosureWorkbench::NS,'policy',option.payload.fetch('policy_id'))
        body['sections']['policy_options'] << {'id'=>option.payload['policy_id'],'label'=>option.payload['policy_id'].delete_prefix('disclosure-option-').tr('-',' ').capitalize,
          'classification'=>'comparison','amount_minor'=>detail['assessed_minor'],'currency'=>'USD','comparison_only'=>true,'fields'=>option_policy.payload['fields'],'baseline_run_id'=>option.external_id,'service_start'=>option.payload['service_start'],'service_end_exclusive'=>option.payload['service_end_exclusive'],'invoice_on'=>option.payload['invoice_on'],'due_on'=>option.payload['due_on'],'invoice_timing'=>option.payload['invoice_timing'],'cash_status'=>option.payload['cash_status'],'run_id'=>option.external_id,'output_id'=>'charge','record_id'=>option.id.to_s}
      end
      # A request has one current comparison; older versions remain in lineage.
      comparisons=@m.source(case_id,DisclosureWorkbench::NS,'comparison').order(:id).to_a
      comparisons.group_by { |row| row.payload.dig('binding','policy_id') }.values.map(&:last).each do |comparison|
        p=comparison.payload; binding=p.fetch('binding')
        reviews=@m.source(case_id,DisclosureWorkbench::NS,'review').where(parent_id:comparison.id).order(:id).to_a.group_by { |r| r.payload['role'] }.values.map(&:last).map { |r| {'id'=>r.external_id,'role'=>r.payload['role'],'decision'=>r.payload['decision']} }
        published=@m.source(case_id,DisclosureWorkbench::NS,'publication').where("payload->>'comparison_id' = ?",comparison.external_id).exists?
        body['sections']['changes'] << {'id'=>comparison.external_id,'label'=>'Terms comparison','status'=>published ? 'published' : 'compared','policy_id'=>binding['policy_id'],
          'comparison_id'=>comparison.external_id,'baseline_run_id'=>binding['baseline_run_id'],'required_roles'=>p['required_roles'],'reviews'=>reviews,'old_amount_minor'=>p['old_amount_minor'],'new_amount_minor'=>p['new_amount_minor'],'record_id'=>comparison.id.to_s}
      end
      @m.source(case_id,DisclosureWorkbench::NS,'policy').where(status:'draft').order(:id).each do |draft|
        next if draft.payload['comparison_only'] || body['sections']['changes'].any? { |c| c['policy_id']==draft.external_id }
        base_run=@m.source(case_id,DisclosureWorkbench::NS,'run').where("payload->>'policy_id' = ?",draft.payload['base_policy_id']).order(:id).last
        body['sections']['changes'] << {'baseline_run_id'=>draft.payload['baseline_run_id']||base_run&.external_id,'id'=>draft.external_id,'label'=>'Draft terms change','status'=>'draft','policy_id'=>draft.external_id,'comparison_id'=>nil,'required_roles'=>%w[legal finance],'reviews'=>[],'record_id'=>draft.id.to_s}
      end
    end
    body['page']['total']=body['sections'].values.sum(&:size)
    cursor=0
    body['sections'].each do |key,list|
      section_start=cursor; cursor+=list.size
      start=[offset-section_start,0].max
      finish=[offset+limit-section_start,list.size].min
      body['sections'][key]=finish>start ? list.slice(start,finish-start) : []
    end
    body
  end
end
