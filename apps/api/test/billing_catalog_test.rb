ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class BillingCatalogTest < Minitest::Test
  def setup
    SyntheticReset.call
    @operator=Workbench.new
    @operator.seed!
    @catalog=BillingCatalog.new(@operator)
    @catalog.seed!
  end
  def view(broker=nil, date='2026-11-13') = @catalog.view(broker_id:broker,business_date:date)
  def test_explicit_lineage_two_line_invoice_and_custodial_path
    result=view
    assert_equal 4,result['obligations'].size
    assert_equal 250000,result['obligations'].sum { |o| o['amount_minor'] }
    cedar=result['invoices'].find { |i| i['id']=='invoice-customer-cedar' }
    assert_equal 'invoice-customer-cedar',cedar['legacy_invoice_id']
    assert_equal [60000,40000],cedar['lines'].map { |l| l['amount_minor'] }.sort.reverse
    assert_equal 100000,cedar['amount_minor']
    cedar['lines'].each do |line|
      obligation=result['obligations'].find { |o| o['id']==line['obligation_id'] }
      assert_equal({'id'=>'fee-a','revision'=>1},obligation['source'])
      assert_equal 'service-customer-cedar',obligation['service_id']
      assert_equal ['account-cedar'],line['account_ids']
      assert_equal ['assignment-customer-cedar'],line['assignment_ids']
    end
    assert_equal 'invoice-customer-maple',result['invoices'].find { |i| i['id']=='invoice-customer-maple' }['legacy_invoice_id']
    instruction=result['instructions'].first
    assert_equal ['billing-obligation-birch'],instruction['obligation_ids']
    assert_equal 50000,instruction['amount_minor']
    assert_nil instruction['execution_status']
    cedar_facts=result['accounting'].select { |f| f['commercial_id']=='invoice-customer-cedar' }.sort_by { |f| f['observed_at'] }
    assert_equal [nil,'mock_observed'],cedar_facts.map { |f| f['reported_status'] }
    assert_equal [1,1],cedar_facts.map { |f| f['commercial_revision'] }
    assert_equal 100000,cedar['amount_minor']
    result['accounting'].each do |fact|
      assert_equal 'mock_campfire',fact['provider']; assert fact['mocked']
      assert_nil fact['applied_minor']; assert_nil fact['ar_minor']; assert_nil fact['recognized_minor']
    end
  end
  def test_seed_idempotent_and_sources_immutable
    before=[BillingObligation.count,BillingInvoice.count,BillingInvoiceLine.count,BillingInstruction.count,BillingAccountingFact.count]
    first=view
    @catalog.seed!
    assert_equal before,[BillingObligation.count,BillingInvoice.count,BillingInvoiceLine.count,BillingInstruction.count,BillingAccountingFact.count]
    assert_equal first,view
    assert_raises(ActiveRecord::ReadOnlyRecord) { BillingObligation.first.update!(amount_minor:1) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { BillingAccountingFact.first.update!(reported_status:'paid') }
  end
  def test_scoping_period_and_advisor_access
    alex=view('broker-alex')
    assert_equal %w[customer-cedar customer-maple],alex['obligations'].map { |o| o['customer_id'] }.uniq.sort
    assert_empty alex['instructions']
    advisor=BillingCatalog.new(Workbench.new(role:'advisor'))
    assert_equal alex,advisor.view(broker_id:nil,business_date:'2026-11-13')
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { advisor.view(broker_id:'broker-jordan',business_date:'2026-11-13') }.code
    assert_empty view(nil,'2026-12-01')['obligations']
    assert_equal 'INVALID_DATE',assert_raises(Economics::Error) { view(nil,'2026-02-30') }.code
    assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { @catalog.insert!(BillingInvoice,{external_id:'wrong'},{'tenant_id'=>'other','external_id'=>'wrong'}) }.code
  end
  def test_database_rejects_cross_scope_and_unbalanced_header
    other=DemoScope.create!(tenant_id:'other',entity_id:'other')
    original=BillingInvoiceLine.first
    assert_raises(ActiveRecord::InvalidForeignKey) do
      BillingInvoiceLine.create!(tenant_id:other.tenant_id,entity_id:other.entity_id,external_id:'bad',billing_invoice_id:original.billing_invoice_id,billing_obligation_id:original.billing_obligation_id,amount_minor:1)
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      BillingInvoice.where(id:BillingInvoice.first.id).update_all(amount_minor:999)
    end
  end
end
