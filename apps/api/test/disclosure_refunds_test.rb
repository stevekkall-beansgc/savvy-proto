require 'minitest/autorun'
require_relative '../app/domains/economics/engine'
require_relative '../app/services/disclosure_refunds'
class DisclosureRefundsTest < Minitest::Test
  def proof
    scope={'tenant_id'=>'t','entity_id'=>'e','case_id'=>'advisor','currency'=>'USD'}
    receipt=scope.merge('id'=>'r','hash'=>'a'*64,'status'=>'confirmed','payer'=>'client','payee'=>'firm','amount_minor'=>1000)
    credit=scope.merge('id'=>'c','hash'=>'b'*64,'status'=>'approved','payer'=>'firm','payee'=>'client','amount_minor'=>500)
    payment=scope.merge('id'=>'p','status'=>'confirmed','payer'=>'firm','payee'=>'client','amount_minor'=>300,'original_receipt_id'=>'r','original_receipt_hash'=>'a'*64,'credit_id'=>'c','credit_hash'=>'b'*64)
    [payment,credit,receipt]
  end
  def test_caps_duplicate_and_scope
    p,c,r=proof
    assert DisclosureRefunds.validate!(payment:p,credit:c,receipt:r,applications:[])
    app={'tenant_id'=>'t','entity_id'=>'e','case_id'=>'advisor','currency'=>'USD','payment_id'=>'earlier','credit_id'=>'c','credit_hash'=>'b'*64,'original_receipt_id'=>'r','original_receipt_hash'=>'a'*64,'amount_minor'=>250}
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:p,credit:c,receipt:r,applications:[app]) }.code
    assert_equal 'DUPLICATE_SOURCE',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:p,credit:c,receipt:r,applications:[app.merge('payment_id'=>'p')]) }.code
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:p,credit:c.merge('amount_minor'=>2000),receipt:r.merge('amount_minor'=>200),applications:[]) }.code
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:p,credit:c.merge('amount_minor'=>2000),receipt:r.merge('amount_minor'=>500),applications:[app.merge('credit_id'=>'other','credit_hash'=>'other')]) }.code
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:p,credit:c,receipt:r,applications:[app.merge('original_receipt_id'=>'other','original_receipt_hash'=>'other')]) }.code
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:p.merge('entity_id'=>'wrong'),credit:c,receipt:r,applications:[]) }.code
  end
end
