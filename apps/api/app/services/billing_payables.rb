# The same engine produces earnings. This service issues native commercial payout
# instructions; an instruction is never a bank execution or payroll confirmation.
class BillingPayables
  def initialize(platform) = @p=platform
  def root(subject,a,b)
    @p.rows('payable').where("payload->>'subject_id'=? AND payload->>'service_start'=? AND payload->>'service_end_exclusive'=? AND payload->>'original_payable_id' IS NULL",subject,a,b).order(:id).first
  end
  def target(root)
    cursor=@p.rows('payable_issue').where(parent_id:root.id).order(:id).last
    @p.get('calculation',cursor ? cursor.payload['run_id'] : root.payload['run_id'])
  end
  def native_hash(instruction)
    @p.hash({'instruction'=>instruction.attributes,'items'=>BillingInstructionItem.where(**@p.w.scope,billing_instruction_id:instruction.id).order(:id).map(&:attributes)})
  end
  def propose(input)
    @p.w.guard!('operator'); run=@p.fresh_run!(@p.get('calculation',input.fetch('run_id')))
    @p.error('INVALID_POLICY','An earnings policy is required') unless run.payload['purpose']=='earnings'
    BillingDocuments.new(@p).open!(input.fetch('posting_period')); @p.m.reason!(input['reason'])
    previous=root(*run.payload.values_at('subject_id','service_start','service_end_exclusive'))
    proposal=@p.store('payable_review',{'run_id'=>run.external_id,'run_hash'=>run.payload_hash,'previous_root_id'=>previous&.external_id,'previous_run_id'=>previous && target(previous).external_id,'posting_period'=>input['posting_period'],'reason'=>input['reason'],'amount_minor'=>run.payload['net_minor']},status:'proposed',parent:run)
    {'proposal_id'=>proposal.external_id,'amount_minor'=>run.payload['net_minor']}
  end
  def current!(proposal)
    run=@p.fresh_run!(@p.get('calculation',proposal.payload['run_id']))
    @p.error('HASH_CHANGED') unless run.payload_hash==proposal.payload['run_hash']
    previous=root(*run.payload.values_at('subject_id','service_start','service_end_exclusive'))
    @p.error('HASH_CHANGED','Another payable changed this period') unless previous&.external_id==proposal.payload['previous_root_id'] && (previous && target(previous).external_id)==proposal.payload['previous_run_id']
    BillingDocuments.new(@p).open!(proposal.payload['posting_period']); [run,previous]
  end
  def review(input)
    @p.w.guard!('finance'); proposal=@p.get('payable_review',input.fetch('proposal_id')); @p.error('VALIDATION_ERROR') unless proposal.status=='proposed'
    current!(proposal); @p.m.reason!(input['reason']); @p.error('VALIDATION_ERROR') unless %w[approved rejected].include?(input['decision'])
    row=@p.store('payable_review',{'proposal_id'=>proposal.external_id,'proposal_hash'=>proposal.payload_hash,'reason'=>input['reason']},status:input['decision'],parent:proposal)
    {'review_id'=>row.external_id,'decision'=>row.status}
  end
  def issue(input)
    @p.w.guard!('operator'); proposal=@p.get('payable_review',input.fetch('proposal_id'))
    prior=@p.rows('payable_issue').where("payload->>'proposal_id'=?",proposal.external_id).first
    return prior.payload.merge('duplicate'=>true) if prior
    run,original=current!(proposal)
    review=@p.rows('payable_review').where(parent_id:proposal.id).order(:id).last
    @p.error('REVIEW_REQUIRED') unless review && review.status=='approved' && review.payload['proposal_hash']==proposal.payload_hash
    old=original ? target(original).payload['settlement_allocations'] : {}
    selected=run.payload['settlement_allocations']; changes=(old.keys+selected.keys).uniq.to_h { |account| [account,Economics::Engine.new.primitive_binary('subtract',selected.fetch(account,0),old.fetch(account,0)).to_i] }
    issued=[]
    [1,-1].each do |sign|
      entries=changes.select { |_,value| value*sign>0 }.transform_values(&:abs); next if entries.empty?
      row=persist(run,entries,sign,proposal.payload['posting_period'],original)
      original ||= row; issued << row.external_id
    end
    @p.error('NO_CHARGE','No commercial payable is due') unless original
    receipt=@p.store('payable_issue',{'proposal_id'=>proposal.external_id,'run_id'=>run.external_id,'payable_ids'=>issued,'review_id'=>review.external_id,'cash_moved'=>false},status:issued.empty? ? 'unchanged' : 'issued',parent:original)
    receipt.payload
  end
  def persist(run,entries,sign,posting,original)
    body=run.payload; a,b=@p.interval!(*body.values_at('service_start','service_end_exclusive')); external=@p.uid('payable')
    instruction=BillingInstruction.create!(**@p.w.scope,external_id:external,revision:1,amount_minor:@p.engine_sum(entries.values,a,b),status:'approved',execution_status:'not_sent',debtor_id:sign>0 ? 'firm-demo' : body['subject_id'],creditor_id:sign>0 ? body['subject_id'] : 'firm-demo',billing_case_id:@p.case_id,billing_subject_id:body['subject_id'],currency:'USD',calculation_ref:run.external_id,posting_period:posting,corrects_instruction_id:original && original.payload['native_instruction_id'])
    entries.sort.each do |account,amount|
      membership=body['segments'].flat_map { |s| s['manifest']['accounts'] }.find { |r| r['account_id']==account }
      @p.error('INCOMPLETE_SOURCE') unless membership
      obligation=BillingObligation.create!(**@p.w.scope,external_id:@p.uid('obligation'),revision:1,customer_id:membership['customer_id'],service_id:'advisor-earnings',broker_id:body['subject_id'],account_id:account,assignment_id:body['segments'].map { |s| s['assignment_id'] }.join(','),client_terms_ref:body['segments'].map { |s| s['policy_id'] }.join(','),source_id:run.external_id,source_revision:run.revision,route:'custodial',currency:'USD',amount_minor:amount,service_period_start:a,service_period_end:b)
      BillingInstructionItem.create!(**@p.w.scope,billing_instruction_id:instruction.id,billing_obligation_id:obligation.id,amount_minor:amount)
    end
    @p.store('payable',{'native_instruction_id'=>instruction.id,'native_hash'=>native_hash(instruction),'run_id'=>run.external_id,'subject_id'=>body['subject_id'],'service_start'=>a.iso8601,'service_end_exclusive'=>b.iso8601,'posting_period'=>posting,'original_payable_id'=>original&.external_id,'direction'=>sign>0 ? 'payout' : 'recoupment','amount_minor'=>instruction.amount_minor,'execution_status'=>'not_sent'},id:external,status:'issued',parent:run)
  end
end
