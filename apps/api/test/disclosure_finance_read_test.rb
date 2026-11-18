ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
require 'delegate'
class DisclosureFinanceReadTest < Minitest::Test
  def with_method(object, name, replacement)
    eigen=object.singleton_class
    defined_here=eigen.instance_methods(false).include?(name)
    original=eigen.instance_method(name) if defined_here
    eigen.send(:define_method,name,&replacement)
    yield
  ensure
    if defined_here
      eigen.send(:define_method,name,original)
    else
      eigen.send(:remove_method,name)
    end
  end
  def setup
    SyntheticReset.call
    @w=Workbench.new(role:'operator'); @w.seed!
    @service=DisclosureWorkbench.new(@w)
    @service.bootstrap({},'finance-bootstrap')
  end
  def test_finance_receives_same_comparison_and_separate_cash
    draft=@service.save_policy({'case_id'=>'advisor','base_policy_id'=>'disclosure-policy-v1','policy'=>@service.fields.merge('annual_rate'=>'33/2500'),'effective_from'=>'2027-02-01','effective_to'=>'2027-03-01','reason'=>'Review fictional rate'},'finance-draft')
    cmp=@service.compare({'case_id'=>'advisor','policy_id'=>draft['policy_id'],'baseline_run_id'=>'disclosure-run-v1'},'finance-compare')
    product=DisclosureReadModel.new(@w).view('advisor',audience:'product',limit:100)
    finance=DisclosureReadModel.new(Workbench.new(role:'finance')).view('advisor',audience:'finance',limit:100)
    p=product.dig('sections','changes').find { |x| x['comparison_id']==cmp['comparison_id'] }
    f=finance.dig('sections','changes').find { |x| x['comparison_id']==cmp['comparison_id'] }
    assert_equal p, f
    assert_equal [100000,110000,false], f.values_at('old_amount_minor','new_amount_minor','needs_fresh_comparison')
    cash=(finance.dig('sections','lifecycle')+finance.dig('sections','compensation')).index_by { |x| x['classification'] }
    assert_equal [100000,30000,1200000], %w[confirmed_inbound_receipt confirmed_outbound_refund confirmed_loan_advance].map { |key| cash.fetch(key).fetch('amount_minor') }
    assert cash['confirmed_loan_advance']['record_id']
    before=MedallionEvidence.count
    service=@service
    with_method(DisclosureWorkbench,:new,->(*) { service }) do
      with_method(@service,:implementation_hash,-> { 'changed-implementation' }) do
        stale=DisclosureReadModel.new(Workbench.new(role:'finance')).view('advisor',audience:'finance',limit:100)
        assert_equal true,stale.dig('sections','changes').find { |x| x['comparison_id']==cmp['comparison_id'] }['needs_fresh_comparison']
      end
    end
    assert_equal before,MedallionEvidence.count
  end
  def test_unconfirmed_or_mismatched_cash_is_not_presented_as_confirmed
    reader=DisclosureReadModel.new(Workbench.new(role:'finance'))
    medallion=reader.instance_variable_get(:@m)
    original=medallion.method(:source)
    payment_scope=original.call('advisor',DisclosureWorkbench::NS,'payment')
    overrides={}
    wrapper=Class.new(SimpleDelegator) do
      define_method(:find_by) do |**criteria|
        overrides.fetch(criteria[:external_id]) { __getobj__.find_by(**criteria) }
      end
    end.new(payment_scope)
    source=->(case_id,scenario,kind) { kind=='payment' && case_id=='advisor' && scenario==DisclosureWorkbench::NS ? wrapper : original.call(case_id,scenario,kind) }
    with_method(medallion,:source,source) do
      receipt=payment_scope.find_by!(external_id:'disclosure-receipt').dup
      receipt.status='pending'; overrides['disclosure-receipt']=receipt
      view=reader.view('advisor',audience:'finance',limit:100)
      classes=view.dig('sections','lifecycle').map { |row| row['classification'] }
      refute_includes classes,'confirmed_inbound_receipt'
      refute_includes classes,'confirmed_outbound_refund'
      overrides.clear
      refund=payment_scope.find_by!(external_id:'disclosure-refund').dup
      refund.status='pending'; overrides['disclosure-refund']=refund
      view=reader.view('advisor',audience:'finance',limit:100)
      refute_includes view.dig('sections','lifecycle').map { |row| row['classification'] },'confirmed_outbound_refund'
      overrides.clear
      loan=payment_scope.find_by!(external_id:'disclosure-loan-cash').dup
      loan.payload=loan.payload.merge('loan_terms_hash'=>'mismatch'); overrides['disclosure-loan-cash']=loan
      view=reader.view('advisor',audience:'finance',limit:100)
      refute_includes view.dig('sections','compensation').map { |row| row['classification'] },'confirmed_loan_advance'
    end
    event_scope=original.call('advisor',DisclosureWorkbench::NS,'event')
    credit=event_scope.find_by!(external_id:'disclosure-credit').dup
    credit.status='pending'
    event_wrapper=Class.new(SimpleDelegator) do
      define_method(:find_by) do |**criteria|
        criteria[:external_id]=='disclosure-credit' ? credit : __getobj__.find_by(**criteria)
      end
    end.new(event_scope)
    event_source=->(case_id,scenario,kind) { kind=='event' && case_id=='advisor' && scenario==DisclosureWorkbench::NS ? event_wrapper : original.call(case_id,scenario,kind) }
    with_method(medallion,:source,event_source) do
      view=reader.view('advisor',audience:'finance',limit:100)
      classes=view.dig('sections','lifecycle').map { |row| row['classification'] }
      refute_includes classes,'commercial_credit'
      refute_includes classes,'confirmed_outbound_refund'
    end
  end

end
