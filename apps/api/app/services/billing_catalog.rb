# Local synthetic commercial evidence. Mock accounting observations never create
# or alter an invoice, collection, deduction, cash event, or recognized revenue.
class BillingCatalog
  def initialize(workbench) = @w = workbench

  def scope = @w.scope
  def rows(klass) = klass.where(**scope)

  def insert!(klass, key, attrs)
    supplied_scope = attrs.stringify_keys.slice('tenant_id','entity_id')
    unless supplied_scope.all? { |name,value| scope.fetch(name.to_sym)==value }
      raise Economics::Error.new('SCOPE_MISMATCH', 'Billing evidence must remain in the selected scope')
    end
    row = rows(klass).find_or_initialize_by(key)
    if row.persisted?
      expected = row.class.new(attrs)
      unless attrs.keys.all? { |name| row.public_send(name) == expected.public_send(name) }
        raise Economics::Error.new('SOURCE_CONFLICT', 'Synthetic billing fixture differs from existing commercial evidence')
      end
    else
      row.assign_attributes(attrs)
      row.save!
    end
    row
  end

  def seed!
    data = JSON.parse(File.read(Workbench::FIXTURES.join('billing.json')))
    DemoScope.transaction do
      DemoScope.where(**scope).lock.first!
      # The explicit source IDs, service IDs and charge IDs are verified; never
      # infer identity from an equal amount. Multiple obligations may split a fact.
      snapshot=@w.record!('snapshot','source-20261113-r1')
      data.fetch('obligations').group_by { |o| [o.fetch('source_id'),o.fetch('source_revision')] }.each do |(source_id,revision), group|
        fact=snapshot.fetch('facts').find { |f| f['id']==source_id && f['revision']==revision }
        raise Economics::Error.new('SOURCE_CONFLICT','Billing source lineage mismatch') unless fact && group.all? { |o| o['customer_id']==fact['customer_id'] && o['service_id']==fact['service_id'] } && group.sum { |o| o.fetch('amount_minor') }==fact['eligible_minor']
      end
      data.fetch('obligations').each do |entry|
        charge=@w.record!('charge',entry.fetch('legacy_charge_id'))
        assignment=snapshot.fetch('assignments').find { |a| a['id']==entry.fetch('assignment_id') }
        unless charge['customer_id']==entry['customer_id'] && charge['currency']==entry['currency'] && assignment && assignment['customer_id']==entry['customer_id'] && assignment['broker_id']==entry['broker_id']
          raise Economics::Error.new('SOURCE_CONFLICT','Billing customer or assignment lineage mismatch')
        end
      end
      obligations = data.fetch('obligations').to_h do |entry|
        row = insert!(BillingObligation, {external_id: entry.fetch('external_id')}, entry)
        [entry.fetch('external_id'), row]
      end
      invoices = data.fetch('invoices').to_h do |entry|
        # Existing legacy invoice evidence, if present, must map to the same
        # explicit charge identity; absence does not fabricate older evidence.
        legacy=@w.records('invoice').where(external_id:entry.fetch('legacy_invoice_id')).order(revision: :desc).first&.payload
        linked=data.fetch('invoice_lines').select { |l| l['invoice']==entry['external_id'] }.map { |l| obligations.fetch(l['obligation']) }
        if legacy && (linked.empty? || linked.any? { |o| o.legacy_charge_id!=legacy['charge_id'] } || legacy['customer_id']!=entry['debtor_id'])
          raise Economics::Error.new('SOURCE_CONFLICT','Legacy invoice identity has different lineage')
        end
        row = insert!(BillingInvoice, {external_id: entry.fetch('external_id')}, entry)
        [entry.fetch('external_id'), row]
      end
      instructions = data.fetch('instructions').to_h do |entry|
        row = insert!(BillingInstruction, {external_id: entry.fetch('external_id')}, entry)
        [entry.fetch('external_id'), row]
      end
      data.fetch('invoice_lines').each do |entry|
        attrs = entry.except('invoice','obligation').merge('billing_invoice_id'=>invoices.fetch(entry.fetch('invoice')).id, 'billing_obligation_id'=>obligations.fetch(entry.fetch('obligation')).id)
        insert!(BillingInvoiceLine, {external_id: entry.fetch('external_id')}, attrs)
      end
      data.fetch('instruction_items').each do |entry|
        key = {billing_instruction_id: instructions.fetch(entry.fetch('instruction')).id, billing_obligation_id: obligations.fetch(entry.fetch('obligation')).id}
        insert!(BillingInstructionItem, key, key.merge(amount_minor: entry.fetch('amount_minor')))
      end
      data.fetch('accounting').each do |entry|
        attrs = entry.except('invoice','instruction').merge('billing_invoice_id'=>entry['invoice'] && invoices.fetch(entry['invoice']).id, 'billing_instruction_id'=>entry['instruction'] && instructions.fetch(entry['instruction']).id)
        insert!(BillingAccountingFact, {external_id: entry.fetch('external_id')}, attrs)
      end
      validate_conservation!
    end
    { 'synthetic'=>true }
  end

  def validate_conservation!
    rows(BillingInvoice).each do |invoice|
      lines=rows(BillingInvoiceLine).where(billing_invoice_id: invoice.id)
      raise Economics::Error.new('BILLING_VARIANCE') unless lines.exists? && lines.sum(:amount_minor)==invoice.amount_minor && lines.all? { |l| (o=rows(BillingObligation).find(l.billing_obligation_id)).route=='invoice' && o.amount_minor==l.amount_minor && o.currency==invoice.currency }
    end
    rows(BillingInstruction).each do |instruction|
      items=rows(BillingInstructionItem).where(billing_instruction_id: instruction.id)
      raise Economics::Error.new('BILLING_VARIANCE') unless items.exists? && items.sum(:amount_minor)==instruction.amount_minor && items.all? { |i| (o=rows(BillingObligation).find(i.billing_obligation_id)).route=='custodial' && o.amount_minor==i.amount_minor }
    end
  end

  def view(broker_id:, business_date:)
    date=Economics::Engine.new.date!(business_date)
    if @w.role=='advisor'
      raise Economics::Error.new('FORBIDDEN') if broker_id && broker_id!='broker-alex'
      broker_id='broker-alex'
    end
    obligations=rows(BillingObligation).where('service_period_start <= ? AND service_period_end > ?',date,date)
    obligations=obligations.where(broker_id: broker_id) if broker_id
    obligations=obligations.order(:external_id).to_a
    permitted=obligations.index_by(&:id)
    lines=rows(BillingInvoiceLine).where(billing_obligation_id: permitted.keys).order(:external_id).to_a
    items=rows(BillingInstructionItem).where(billing_obligation_id: permitted.keys).to_a
    # Never expose a partial invoice's full debtor or amount across broker scopes.
    invoices=rows(BillingInvoice).where(id:lines.map(&:billing_invoice_id).uniq).order(:external_id).select do |invoice|
      rows(BillingInvoiceLine).where(billing_invoice_id:invoice.id).all? { |l| permitted.key?(l.billing_obligation_id) }
    end
    instructions=rows(BillingInstruction).where(id:items.map(&:billing_instruction_id).uniq).order(:external_id).select do |instruction|
      rows(BillingInstructionItem).where(billing_instruction_id:instruction.id).all? { |i| permitted.key?(i.billing_obligation_id) }
    end
    accounting=rows(BillingAccountingFact).where(billing_invoice_id:invoices.map(&:id)).or(rows(BillingAccountingFact).where(billing_instruction_id:instructions.map(&:id))).order(:external_id).to_a
    { 'obligations'=>obligations.map { |o| { 'id'=>o.external_id,'revision'=>o.revision,'customer_id'=>o.customer_id,'service_id'=>o.service_id,'amount_minor'=>o.amount_minor,'currency'=>o.currency,'service_period_start'=>o.service_period_start.iso8601,'service_period_end'=>o.service_period_end.iso8601,'client_terms_ref'=>o.client_terms_ref,'source'=>{'id'=>o.source_id,'revision'=>o.source_revision},'route'=>o.route,'account_id'=>o.account_id,'assignment_id'=>o.assignment_id,'legacy_charge_id'=>o.legacy_charge_id } },
      'invoices'=>invoices.map { |i| { 'id'=>i.external_id,'revision'=>i.revision,'debtor_id'=>i.debtor_id,'amount_minor'=>i.amount_minor,'currency'=>i.currency,'status'=>i.status,'legacy_invoice_id'=>i.legacy_invoice_id,'lines'=>lines.select { |l| l.billing_invoice_id==i.id }.map { |l| o=permitted.fetch(l.billing_obligation_id); {'id'=>l.external_id,'obligation_id'=>o.external_id,'amount_minor'=>l.amount_minor,'account_ids'=>[o.account_id],'assignment_ids'=>[o.assignment_id]} },'accounting_ref'=>accounting.select { |a| a.billing_invoice_id==i.id }.max_by(&:observed_at)&.external_id } },
      'instructions'=>instructions.map { |i| selected=items.select { |item| item.billing_instruction_id==i.id }; { 'id'=>i.external_id,'revision'=>i.revision,'obligation_ids'=>selected.map { |item| permitted.fetch(item.billing_obligation_id).external_id },'account_ids'=>selected.map { |item| permitted.fetch(item.billing_obligation_id).account_id }.uniq,'amount_minor'=>i.amount_minor,'status'=>i.status,'execution_status'=>i.execution_status } },
      'accounting'=>accounting.map { |a| parent=a.billing_invoice_id ? invoices.find { |i| i.id==a.billing_invoice_id } : instructions.find { |i| i.id==a.billing_instruction_id }; { 'id'=>a.external_id,'provider'=>'mock_campfire','commercial_id'=>parent.external_id,'commercial_revision'=>a.commercial_revision,'reported_status'=>a.reported_status,'applied_minor'=>a.applied_minor,'ar_minor'=>a.ar_minor,'recognized_minor'=>a.recognized_minor,'observed_at'=>a.observed_at.iso8601(6),'mocked'=>true } } }
  end
end
