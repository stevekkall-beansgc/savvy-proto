ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
require 'active_support/testing/time_helpers'

class ReconciliationTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  def setup
    SyntheticReset.call
    travel_to(Time.iso8601('2026-11-13T21:30:00Z'))
    @operator=Workbench.new; @operator.seed!; @finance=Workbench.new(role:'finance')
    %w[cedar maple].each do |name|
      charge=@finance.record!('charge',"charge-customer-#{name}")
      invoice=charge.slice('tenant_id','entity_id','currency','customer_id','amount_minor').merge('id'=>"invoice-#{name}",'status'=>'open','synthetic'=>true)
      @finance.link_invoice({'charge_id'=>charge['id'],'invoice'=>invoice},"link-#{name}")
    end
  end
  def app(invoice='invoice-cedar', receipt='receipt-cedar', value=60000)
    {'invoice_id'=>invoice,'receipt_id'=>receipt,'minor_units'=>value,'business_date'=>'2026-11-13','reason'=>'Synthetic evidence'}
  end
  def batch
    {'id'=>'batch-one','receipt_ids'=>%w[receipt-cedar receipt-maple],'gross_minor'=>160000,'fee_minor'=>3000,'net_minor'=>157000,'business_date'=>'2026-11-13','reason'=>'Synthetic bank statement'}
  end
  def review(close_id=nil)
    @finance.reconciliation(period_start:'2026-11-01',period_end_exclusive:'2026-12-01',close_id:close_id)
  end
  def test_independent_applications_and_bank_bridge_with_source_reversal_conflict
    assert_nil review['totals']['invoice_applied_minor']
    a=@finance.record_invoice_application(app,'a')
    @finance.record_invoice_application(app('invoice-maple','receipt-maple',100000),'b')
    @finance.record_bank_batch(batch,'batch')
    result=review
    assert_equal 160000,result['totals']['invoice_applied_minor']
    assert_equal 40000,result['totals']['invoice_open_minor']
    assert_equal [160000,3000,157000],result['totals'].values_at('bank_gross_minor','bank_fee_minor','bank_net_minor')
    assert_equal false,a['accounting_posted']
    @finance.reverse_receipt({'receipt_id'=>'receipt-cedar','expected_revision'=>1,'reason'=>'Synthetic correction'},'receipt-reverse')
    result=review
    assert_equal 160000,result['totals']['invoice_applied_minor']
    assert_equal 160000,result['totals']['bank_gross_minor']
    assert_equal %w[RECEIPT_APPLICATION_CONFLICT RECEIPT_BANK_CONFLICT],result['exceptions'].map { |x| x['code'] }.grep(/CONFLICT/)
    @finance.reverse_invoice_application({'application_id'=>a['id'],'business_date'=>'2026-11-13','reason'=>'Correct application'},'undo')
    assert_equal 0,review['invoices'].find { |i| i['id']=='invoice-cedar' }['applied_minor']
    assert_equal 'ALREADY_REVERSED',assert_raises(Economics::Error) { @finance.reverse_invoice_application({'application_id'=>a['id'],'business_date'=>'2026-11-13','reason'=>'Correct application'},'undo-again') }.code
  end
  def test_freeze_is_optimistic_and_frozen_content_remains_unchanged
    old=review['manifest_hash']
    @finance.record_bank_batch(batch,'batch')
    params={'period_start'=>'2026-11-01','period_end_exclusive'=>'2026-12-01','expected_manifest_hash'=>old,'reason'=>'Review complete'}
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error) { @finance.close_reconciliation(params,'stale') }.code
    params['expected_manifest_hash']=review['manifest_hash']
    close=@finance.close_reconciliation(params,'close')
    frozen=review(close['id'])
    @finance.reverse_bank_batch({'batch_id'=>'batch-one','business_date'=>'2026-11-14','reason'=>'Correction'},'reverse')
    later=review(close['id'])
    assert_equal frozen.except('later_evidence','late_exceptions'),later.except('later_evidence','late_exceptions')
    assert_equal ['bank_batch_reversal'],later['later_evidence'].map { |r| r['kind'] }
    assert_equal 'LATE_EVIDENCE',later['late_exceptions'].first['code']
    assert_equal 0,review['totals']['bank_gross_minor']
  end
  def test_validation_role_conservation_and_idempotency
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { @operator.record_bank_batch(batch,'no') }.code
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error) { @finance.record_invoice_application(app('invoice-maple'),'wrong') }.code
    result=@finance.record_invoice_application(app,'a')
    assert_equal result,@finance.record_invoice_application(app,'a')
    assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error) { @finance.record_invoice_application(app('invoice-cedar','receipt-cedar',1),'a') }.code
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { @finance.record_invoice_application(app('invoice-cedar','receipt-cedar',1),'excess') }.code
    assert_equal 'BANK_VARIANCE',assert_raises(Economics::Error) { @finance.record_bank_batch(batch.merge('net_minor'=>1),'bad') }.code
    assert_equal 'VALIDATION_ERROR',assert_raises(Economics::Error) { @finance.record_bank_batch(batch.merge('receipt_ids'=>%w[receipt-cedar receipt-cedar]),'duplicate') }.code
    assert_equal 'INVALID_INTERVAL',assert_raises(Economics::Error) { @finance.reconciliation(period_start:'2026-12-01',period_end_exclusive:'2026-11-01') }.code
  end
  def test_revised_receipt_amount_preserves_original_proof_and_flags_conflicts
    @finance.record_invoice_application(app,'application')
    @finance.record_bank_batch(batch,'batch')
    original=@finance.record!('receipt','receipt-cedar')
    @finance.write!('receipt',original.merge('revision'=>2,'amount_minor'=>59000),revision:2)
    result=review
    assert_equal %w[RECEIPT_APPLICATION_CONFLICT RECEIPT_BANK_CONFLICT],result['exceptions'].map { |x| x['code'] }.grep(/CONFLICT/)
    assert_equal 60000,result['invoices'].find { |i| i['id']=='invoice-cedar' }['applications'].first['receipt_amount_minor']
    assert_equal 60000,result['bank_batches'].first['receipt_evidence'].find { |r| r['id']=='receipt-cedar' }['amount_minor']
    assert_equal 160000,result['totals']['bank_gross_minor']
  end
  def test_graphql_money_and_unknown_receipt_status_fail_closed
    receipt=@finance.record!('receipt','receipt-cedar').merge('revision'=>2,'status'=>'mystery')
    @finance.write!('receipt',receipt,revision:2)
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error) { @finance.record_bank_batch(batch,'bad') }.code
    query='{ reconciliation(periodStart:"2026-11-01",periodEndExclusive:"2026-12-01") }'
    result=WorkbenchSchema.execute(query,context:{workbench:@finance}).to_h
    assert_equal '200000',result.dig('data','reconciliation','totals','invoice_amount_minor')
    assert_nil result.dig('data','reconciliation','totals','invoice_applied_minor')
  end
end
