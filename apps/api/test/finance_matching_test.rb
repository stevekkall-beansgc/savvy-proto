ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class FinanceMatchingTest < Minitest::Test
  def setup
    SyntheticReset.call
    operator=Workbench.new(role:'operator')
    operator.seed!
    operator.medallion.bootstrap({},'matching-medallion')
    FinanceTiming.new(operator).bootstrap({},'matching-fixture')
    @finance=FinanceTiming.new(Workbench.new(role:'finance'))
  end
  def input(payment, invoice, amount, period='2027-02')
    {'payment_id'=>payment,'invoice_id'=>invoice,'currency'=>'USD','amount_minor'=>amount,'posting_period'=>period,'reason'=>'Explicit fictional remittance'}
  end
  def test_multiple_sources_and_invoices_conserve_each_side
    before=@finance.view('ria')
    payment=before.dig('cash','payments').find { |r| r['id']=='finance-cash-200' }
    assert_equal [21000,1000,20000],payment.values_at('gross_minor','fee_minor','net_minor')
    assert_equal 'returned',before.dig('cash','payments').find { |r| r['id']=='finance-cash-returned' }['status']
    assert_equal 4,before.dig('cash','suggestions').size
    a=@finance.associate(input('finance-cash-900','finance-invoice-unbilled',4000),'match-a')
    @finance.associate(input('finance-cash-200','finance-invoice-unbilled',6000),'match-b')
    @finance.associate(input('finance-cash-200','finance-invoice-advance',14000),'match-c')
    view=@finance.view('ria')
    p900=view.dig('cash','payments').find { |r| r['id']=='finance-cash-900' }
    p200=view.dig('cash','payments').find { |r| r['id']=='finance-cash-200' }
    second=view.dig('cash','invoices').find { |r| r['id']=='finance-invoice-unbilled' }
    assert_equal [64000,26000],p900.values_at('associated_minor','unapplied_minor')
    assert_equal [20000,0],p200.values_at('associated_minor','unapplied_minor')
    assert_equal [10000,0],second.values_at('associated_minor','residual_minor')
    assert_equal '2027-02-01T00:00:00Z',second['known_at']
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { @finance.associate(input('finance-cash-900','finance-invoice-unbilled',1),'over-invoice') }.code
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { @finance.associate(input('finance-cash-200','finance-invoice-advance',1),'over-cash') }.code
    @finance.reverse({'application_id'=>a.fetch('id'),'posting_period'=>'2027-02','reason'=>'Correction of allocation'},'reverse-a')
    assert_equal 4000,@finance.view('ria').dig('cash','invoices').find { |r| r['id']=='finance-invoice-unbilled' }['residual_minor']
  end
  def test_scope_time_and_reported_accounting_are_independent
    assert_equal 'FUTURE_EVIDENCE',assert_raises(Economics::Error) { @finance.associate(input('finance-cash-900','finance-invoice-unbilled',1,'2027-01'),'early') }.code
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { @finance.associate(input('finance-cash-returned','finance-invoice-advance',1),'returned') }.code
    view=@finance.view('ria')
    outcome=view.dig('cash','accounting_outcomes').first
    initial=MedallionEvidence.find_by!(case_id:'ria',scenario_id:'finance_timing_2027',kind:'application',external_id:'finance-association-600')
    assert_equal initial.external_id,outcome['application_id']
    assert_equal initial.payload_hash,outcome['application_hash']
    records=view.dig('recognition','records')
    january=records.find { |r| r['record_id']=='recognition-input-unbilled-v1' }
    february=records.find { |r| r['record_id']=='recognition-input-unbilled-billed-v2' }
    refute january.key?('invoice_id')
    assert_equal ['finance-invoice-unbilled','2027-02-01T00:00:00Z'],february.values_at('invoice_id','invoice_known_at')
    alternative=@finance.view('advisor').dig('cash','alternative_contexts').first
    assert_equal 'confirmed_payment',alternative['namespace']
    assert_equal 'fixture-confirmed-payment',alternative.dig('payments',0,'id')
    assert_empty alternative['reversals']
    assert_empty alternative['instructions']
  end
  def test_reversal_and_acknowledgment_respect_supplied_timing
    association=@finance.associate(input('finance-cash-900','finance-invoice-advance',30000,'2027-03'),'march-association')
    reversal={'application_id'=>association.fetch('id'),'posting_period'=>'2027-02','reason'=>'Correction of allocation'}
    assert_equal 'FUTURE_EVIDENCE',assert_raises(Economics::Error) { @finance.reverse(reversal,'early-reversal') }.code
    assert_equal 'FUTURE_EVIDENCE',assert_raises(Economics::Error) { @finance.mock_acknowledge({'application_id'=>association.fetch('id')},'early-ack') }.code
    assert_equal 1,@finance.view('ria').dig('cash','accounting_outcomes').size
    @finance.reverse(reversal.merge('posting_period'=>'2027-03'),'valid-reversal')
  end

  def test_february_acknowledgment_uses_supplied_evidence
    association=@finance.associate(input('finance-cash-900','finance-invoice-advance',30000),'feb-association')
    ack=@finance.mock_acknowledge({'application_id'=>association.fetch('id')},'feb-ack')
    assert_equal ['2027-02-01T00:00:00Z',90000,30000],ack.values_at('observed_at','applied_minor','ar_minor')
  end

  def test_original_fixtures_are_retained_with_hash_and_linked_records
    scope=MedallionEvidence.where(case_id:'ria',scenario_id:'finance_timing_2027')
    {'finance-timing-source'=>'timing.json','finance-policy-source'=>'commercial-policy.json'}.each do |id,name|
      artifact=scope.find_by!(kind:'artifact',external_id:id)
      original=File.binread(Rails.root.join('../../fixtures/finance',name))
      assert_equal original,artifact.original_bytes
      assert_equal Digest::SHA256.hexdigest(original),artifact.payload.fetch('sha256')
      assert_equal artifact.id,scope.find_by!(kind:'delivery',external_id:"delivery-#{id}").parent_id
    end
    %w[schedule-advance-v1 journal-advance-2027-01-v1 journal-unbilled-2027-01].each do |id|
      assert_equal 'finance-timing-source',scope.find_by!(kind:'fact',external_id:id).payload.fetch('source_artifact_id')
    end
    assert_equal 'finance-policy-source',scope.find_by!(kind:'policy',external_id:'finance-commercial-v1').payload.fetch('source_artifact_id')
    obligation=BillingObligation.find_by!(external_id:'finance-obligation-unbilled')
    invoice=BillingInvoice.find_by!(external_id:'finance-invoice-unbilled')
    line=BillingInvoiceLine.find_by!(external_id:'finance-line-unbilled')
    run=scope.find_by!(kind:'run',external_id:'finance-commercial-run-v1')
    assessed=run.payload.fetch('result').fetch('details').find { |d| d['id']=='unbilled_service' }.fetch('assessed_minor')
    assert_equal 'finance-assignment-v1',obligation.assignment_id
    assert_equal [assessed,assessed,assessed],[obligation.amount_minor,invoice.amount_minor,line.amount_minor]
  end

end
