# Validate a locally recorded association between separately sourced payment,
# credit and receipt. It cannot initiate or attest to a provider transfer.
class DisclosureRefunds
  def self.validate!(payment:, credit:, receipt:, applications:)
    fail_scope=-> { raise Economics::Error.new('SCOPE_MISMATCH') }
    fail_scope.call unless [payment,credit,receipt].all? { |r| r.is_a?(Hash) } && applications.is_a?(Array)
    fail_scope.call unless applications.all? { |a| a.is_a?(Hash) }
    fail_scope.call unless [payment,credit,receipt].all? { |r| r['id'].is_a?(String) && !r['id'].empty? } && [credit,receipt].all? { |r| r['hash'].is_a?(String) && r['hash'].match?(/\A[0-9a-f]{64}\z/) }
    keys=%w[tenant_id entity_id case_id currency]
    fail_scope.call unless keys.all? { |k| [payment[k],credit[k],receipt[k]].uniq.one? && payment[k].is_a?(String) && !payment[k].empty? }
    fail_scope.call unless payment['status']=='confirmed' && receipt['status']=='confirmed' && credit['status']=='approved' && payment['payer']==receipt['payee'] && payment['payee']==receipt['payer'] && credit['payer']==payment['payer'] && credit['payee']==payment['payee']
    fail_scope.call unless payment['original_receipt_id']==receipt['id'] && payment['original_receipt_hash']==receipt['hash'] && payment['credit_id']==credit['id'] && payment['credit_hash']==credit['hash']
    amounts=[payment['amount_minor'],credit['amount_minor'],receipt['amount_minor']]
    raise Economics::Error.new('INVALID_INTEGER') unless amounts.all? { |v| v.is_a?(Integer) && v.positive? }
    raise Economics::Error.new('DUPLICATE_SOURCE') if applications.any? { |a| a['payment_id']==payment['id'] }
    fail_scope.call unless applications.all? { |a| a.is_a?(Hash) && a['credit_id'].is_a?(String) && a['original_receipt_id'].is_a?(String) && a['amount_minor'].is_a?(Integer) && a['amount_minor']>0 && keys.all? { |k| a[k]==payment[k] } }
    credit_uses=applications.select { |a| a['credit_id']==credit['id'] }
    receipt_uses=applications.select { |a| a['original_receipt_id']==receipt['id'] }
    fail_scope.call unless credit_uses.all? { |a| a['credit_hash']==credit['hash'] } && receipt_uses.all? { |a| a['original_receipt_hash']==receipt['hash'] }
    credit_used=credit_uses.sum { |a| a['amount_minor'] }; cash_used=receipt_uses.sum { |a| a['amount_minor'] }
    raise Economics::Error.new('ALLOCATION_EXCEEDED') if credit_used+payment['amount_minor']>credit['amount_minor'] || cash_used+payment['amount_minor']>receipt['amount_minor']
    true
  end
end
