require 'securerandom'

# Independent, append-only synthetic evidence. The workbench scope lock serializes
# all writes, including the comparison and storage of a frozen review.
class ReconciliationBook
  KINDS = %w[charge receipt invoice invoice_application invoice_application_reversal bank_batch bank_batch_reversal].freeze
  def initialize(workbench) = @w = workbench

  def date!(value) = Economics::Engine.new.date!(value)
  def amount!(value, name, min: 0) = Economics::Engine.integer!(value, name, min: min)
  def reason!(value) = @w.settlement_book.reason!(value)
  def id!(value)
    raise Economics::Error.new('VALIDATION_ERROR', 'A bounded ID is required') unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
    value
  end
  def period!(start_date, end_date)
    raise Economics::Error.new('INVALID_INTERVAL') unless date!(start_date) < date!(end_date)
    { 'start'=>start_date, 'end_exclusive'=>end_date }
  end
  def in_period?(date, period) = date >= period['start'] && date < period['end_exclusive']
  def payloads(kind) = @w.records(kind).order(:id).map(&:payload)
  def active(kind, reversal_kind)
    reversed = payloads(reversal_kind).map { |r| r['reversal_of_id'] }
    payloads(kind).reject { |r| reversed.include?(r['id']) }
  end
  def eligible_receipt!(id)
    receipt = @w.record!('receipt', id!(id))
    Economics::Engine.new.scope!(receipt, @w.policy)
    raise Economics::Error.new('UNRESOLVED_MAPPING', 'Receipt must be verified cash') unless receipt['status'] == 'verified_cash'
    amount!(receipt['amount_minor'], 'receipt amount', min: 1)
    receipt
  end
  def write(kind, data)
    now = Time.current
    payload = data.merge('recorded_at'=>now.iso8601(6), 'synthetic'=>true)
    @w.write!(kind, payload, recorded_at: now)
    { 'id'=>payload['id'], 'synthetic'=>true, 'accounting_posted'=>false }
  end
  def metadata(input)
    date!(input.fetch('business_date'))
    { 'business_date'=>input['business_date'], 'reason'=>reason!(input['reason']) }
  end
  def record_application(input, key)
    @w.guard!('finance')
    @w.operate('record_invoice_application', input, key) do
      meta = metadata(input)
      invoice = @w.record!('invoice', id!(input.fetch('invoice_id')))
      receipt = eligible_receipt!(input.fetch('receipt_id'))
      Economics::Engine.new.scope!(invoice, @w.policy)
      unless invoice['status']=='open' && invoice['customer_id']==receipt['customer_id']
        raise Economics::Error.new('UNRESOLVED_MAPPING', 'Invoice and receipt must have the same customer')
      end
      value=amount!(input['minor_units'], 'minor_units', min: 1)
      amount!(invoice['amount_minor'], 'invoice amount', min: 1)
      applications=active('invoice_application','invoice_application_reversal')
      if applications.select { |a| a['invoice_id']==invoice['id'] }.sum { |a| a['minor_units'] } + value > invoice['amount_minor'] ||
          applications.select { |a| a['receipt_id']==receipt['id'] }.sum { |a| a['minor_units'] } + value > receipt['amount_minor']
        raise Economics::Error.new('ALLOCATION_EXCEEDED', 'Application exceeds invoice or receipt')
      end
      write('invoice_application', meta.merge('id'=>"application-#{SecureRandom.uuid}", 'invoice_id'=>invoice['id'], 'receipt_id'=>receipt['id'], 'receipt_revision'=>receipt['revision'], 'receipt_amount_minor'=>receipt['amount_minor'], 'customer_id'=>receipt['customer_id'], 'minor_units'=>value, 'currency'=>'USD'))
    end
  end
  def reverse_application(input, key)
    reverse(input,key,'invoice_application','invoice_application_reversal','application_id')
  end
  def record_batch(input, key)
    @w.guard!('finance')
    @w.operate('record_bank_batch', input, key) do
      meta=metadata(input); id=id!(input.fetch('id'))
      raise Economics::Error.new('SOURCE_CONFLICT', 'Batch ID already exists') if @w.records('bank_batch').exists?(external_id:id)
      ids=input['receipt_ids']
      unless ids.is_a?(Array) && ids.size.between?(1,1000) && ids.all? { |v| v.is_a?(String) } && ids.uniq.size==ids.size
        raise Economics::Error.new('VALIDATION_ERROR', 'Supply unique receipt IDs')
      end
      receipts=ids.map { |r| eligible_receipt!(r) }
      used=active('bank_batch','bank_batch_reversal').flat_map { |b| b['receipt_ids'] }
      raise Economics::Error.new('ALLOCATION_EXCEEDED', 'Receipt is already in an active batch') if (ids & used).any?
      gross=amount!(input['gross_minor'],'gross_minor'); fee=amount!(input['fee_minor'],'fee_minor'); net=amount!(input['net_minor'],'net_minor')
      unless gross==receipts.sum { |r| r['amount_minor'] } && gross==fee+net
        raise Economics::Error.new('BANK_VARIANCE', 'Gross must equal attributed receipts and fee plus net')
      end
      write('bank_batch',meta.merge('id'=>id,'receipt_ids'=>ids.sort,'receipt_evidence'=>receipts.sort_by { |r| r['id'] }.map { |r| r.slice('id','revision','amount_minor','customer_id','currency') },'currency'=>'USD','gross_minor'=>gross,'fee_minor'=>fee,'net_minor'=>net))
    end
  end
  def reverse_batch(input, key) = reverse(input,key,'bank_batch','bank_batch_reversal','batch_id')
  def reverse(input,key,kind,reversal_kind,id_key)
    @w.guard!('finance')
    @w.operate("reverse_#{kind}",input,key) do
      meta=metadata(input); original=@w.record!(kind,id!(input.fetch(id_key)))
      raise Economics::Error.new('ALREADY_REVERSED') if payloads(reversal_kind).any? { |r| r['reversal_of_id']==original['id'] }
      write(reversal_kind,meta.merge('id'=>"reversal-#{SecureRandom.uuid}",'reversal_of_id'=>original['id']))
    end
  end
  def evidence
    DemoRecord.where(**@w.scope,kind:KINDS).order(:id).to_a
  end
  def current(start_date, end_date)
    period=period!(start_date,end_date)
    rows=evidence
    manifest=Economics::Canonical.hash({ 'scope'=>@w.scope.stringify_keys, 'period'=>period,
      'evidence'=>rows.map { |r| { 'kind'=>r.kind, 'external_id'=>r.external_id, 'revision'=>r.revision, 'payload_hash'=>r.payload_hash } } })
    applications=payloads('invoice_application'); app_reversals=payloads('invoice_application_reversal')
    batch_reversals=payloads('bank_batch_reversal')
    charges=@w.current_records('charge').map(&:payload).index_by { |c| c['id'] }
    invoices=@w.current_records('invoice').map(&:payload).filter_map do |invoice|
      charge=charges[invoice['charge_id']]; next unless charge && in_period?(charge.fetch('service_period_start'),period)
      apps=applications.select { |a| a['invoice_id']==invoice['id'] }
      entries=apps.flat_map do |a|
        rev=app_reversals.find { |r| r['reversal_of_id']==a['id'] }
        original=a.slice('id','receipt_id','receipt_revision','receipt_amount_minor','customer_id','minor_units','recorded_at','business_date','reason').merge('status'=>rev ? 'reversed' : 'active','reversal_of_id'=>nil)
        rev ? [original,rev.slice('id','recorded_at','business_date','reason').merge('receipt_id'=>a['receipt_id'],'minor_units'=>a['minor_units'],'status'=>'reversal','reversal_of_id'=>a['id'])] : [original]
      end
      active_apps=apps.reject { |a| app_reversals.any? { |r| r['reversal_of_id']==a['id'] } }
      applied=apps.empty? ? nil : active_apps.sum { |a| a['minor_units'] }
      invoice.slice('id','charge_id','customer_id','currency','amount_minor').merge('applied_minor'=>applied,'open_minor'=>applied.nil? ? nil : invoice['amount_minor']-applied,'application_status'=>apps.empty? ? 'unknown' : 'evidenced','applications'=>entries)
    end
    batches=payloads('bank_batch').select { |b| in_period?(b['business_date'],period) }.map do |b|
      b.slice('id','currency','gross_minor','fee_minor','net_minor','receipt_ids','receipt_evidence','recorded_at','business_date','reason').merge('status'=>batch_reversals.any? { |r| r['reversal_of_id']==b['id'] } ? 'reversed' : 'active', 'reversal'=>batch_reversals.find { |r| r['reversal_of_id']==b['id'] }&.slice('id','reversal_of_id','recorded_at','business_date','reason'))
    end
    active_batches=batches.select { |b| b['status']=='active' }
    exceptions=[]
    invoices.select { |i| i['application_status']=='unknown' }.each do |i|
      exceptions << { 'code'=>'INVOICE_APPLICATION_UNKNOWN','owner'=>'Finance','next_action'=>'Supply independent invoice application evidence','evidence_ids'=>[i['id']] }
    end
    if batches.empty?
      exceptions << { 'code'=>'BANK_SETTLEMENT_UNKNOWN','owner'=>'Finance','next_action'=>'Supply independent bank batch evidence','evidence_ids'=>[] }
    end
    exceptions << { 'code'=>'RECOGNITION_UNKNOWN','owner'=>'Finance','next_action'=>'Review recognition with separate accounting evidence','evidence_ids'=>[] }
    receipt_status=@w.current_records('receipt').map(&:payload).index_by { |r| r['id'] }
    invoices.each do |i|
      i['applications'].select { |a| a['status']=='active' }.each do |a|
        unless receipt_status[a['receipt_id']] && receipt_status[a['receipt_id']]['status']=='verified_cash' && receipt_status[a['receipt_id']]['revision']==a['receipt_revision'] && receipt_status[a['receipt_id']]['amount_minor']==a['receipt_amount_minor'] && receipt_status[a['receipt_id']]['customer_id']==a['customer_id']
          exceptions << { 'code'=>'RECEIPT_APPLICATION_CONFLICT','owner'=>'Finance','next_action'=>'Review independent application and receipt evidence','evidence_ids'=>[a['id'],a['receipt_id']] }
        end
      end
    end
    active_batches.each do |b|
      b['receipt_ids'].each do |id|
        source=b['receipt_evidence'].find { |r| r['id']==id }
        current_receipt=receipt_status[id]
        unless source && current_receipt && current_receipt['status']=='verified_cash' && %w[revision amount_minor customer_id currency].all? { |key| source[key]==current_receipt[key] }
          exceptions << { 'code'=>'RECEIPT_BANK_CONFLICT','owner'=>'Finance','next_action'=>'Review independent bank and receipt evidence','evidence_ids'=>[b['id'],id] }
        end
      end
    end
    complete=invoices.any? && invoices.all? { |i| !i['applied_minor'].nil? }
    closes=payloads('reconciliation_close').select { |c| c['period']==period }.map { |c| c.slice('id','manifest_hash','closed_at','reason') }
    { 'synthetic'=>true,'period'=>period,'knowledge_cutoff'=>Time.current.iso8601(6),'manifest_hash'=>manifest,'mode'=>'current','close'=>nil,
      'invoices'=>invoices,'bank_batches'=>batches,'totals'=>{'invoice_amount_minor'=>invoices.empty? ? nil : invoices.sum { |i| i['amount_minor'] },
      'invoice_applied_minor'=>complete ? invoices.sum { |i| i['applied_minor'] } : nil,'invoice_open_minor'=>complete ? invoices.sum { |i| i['open_minor'] } : nil,
      'bank_gross_minor'=>batches.empty? ? nil : active_batches.sum { |b| b['gross_minor'] },'bank_fee_minor'=>batches.empty? ? nil : active_batches.sum { |b| b['fee_minor'] },'bank_net_minor'=>batches.empty? ? nil : active_batches.sum { |b| b['net_minor'] },'recognized_revenue_minor'=>nil},
      'exceptions'=>exceptions,'later_evidence'=>[],'late_exceptions'=>[],'closes'=>closes }
  end
  def view(period_start:,period_end_exclusive:,close_id:nil)
    @w.guard!('operator','finance','legal','auditor')
    DemoScope.transaction do
      DemoScope.where(**@w.scope).lock.first!
      view_locked(period_start:period_start,period_end_exclusive:period_end_exclusive,close_id:close_id)
    end
  end
  def view_locked(period_start:,period_end_exclusive:,close_id:nil)
    period=period!(period_start,period_end_exclusive)
    return current(period_start,period_end_exclusive) unless close_id
    close=@w.record!('reconciliation_close',id!(close_id))
    raise Economics::Error.new('NOT_FOUND') unless close['period']==period
    later=evidence.select { |r| r.id > close['evidence_max_id'] }.map { |r| { 'id'=>r.external_id,'kind'=>r.kind,'recorded_at'=>r.recorded_at.iso8601(6),'reason'=>r.payload['reason'] || r.payload['reversal_reason'] || 'Evidence recorded after this review', 'business_date'=>r.payload['business_date'] } }
    snapshot=Economics::Canonical.copy(close['review'])
    snapshot['later_evidence']=later
    snapshot['late_exceptions']=later.empty? ? [] : [{ 'code'=>'LATE_EVIDENCE','owner'=>'Finance','next_action'=>'Review later evidence against this frozen review','evidence_ids'=>later.map { |r| r['id'] } }]
    snapshot
  end
  def close(input,key)
    @w.guard!('finance')
    @w.operate('close_reconciliation',input,key) do
      reason=reason!(input['reason']); review=current(input.fetch('period_start'),input.fetch('period_end_exclusive'))
      unless input['expected_manifest_hash'].is_a?(String) && input['expected_manifest_hash']==review['manifest_hash']
        raise Economics::Error.new('HASH_CHANGED','Evidence changed; reload before freezing')
      end
      id="close-#{SecureRandom.uuid}"; now=Time.current.iso8601(6)
      info={'id'=>id,'manifest_hash'=>review['manifest_hash'],'closed_at'=>now,'reason'=>reason}
      review['mode']='frozen'; review['close']=info
      review['closes']=review['closes']+[info]
      @w.write!('reconciliation_close',info.merge('period'=>review['period'],'review'=>review,'evidence_max_id'=>evidence.map(&:id).max || 0))
      { 'id'=>id,'synthetic'=>true,'accounting_posted'=>false }
    end
  end
end
