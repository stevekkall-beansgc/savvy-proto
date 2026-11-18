# Disposable synthetic DB only; coordinator serializes reset suites.
ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'delegate'
require 'minitest/autorun'

class DisclosureLifecycleStressTest < Minitest::Test
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    @operator=Workbench.new(role:'operator'); @operator.seed!
    @service=DisclosureWorkbench.new(@operator); @service.bootstrap({},'lifecycle-stress')
  end
  def indexed(section, audience='product')
    DisclosureReadModel.new(@operator).view('advisor',audience:audience,limit:100).fetch('sections').fetch(section).index_by { |item| item.fetch('id') }
  end
  def test_temporal_arrivals_credit_and_refund_are_distinct
    %w[termination salary bonus loan forgiveness equity custodian-charge embedded-fund-cost custodian-advisory-observation original-receipt refund recognition loan-cash].each do |name|
      artifact=@service.get('artifact',"disclosure-#{name}-artifact")
      delivery=@service.get('delivery',"disclosure-#{name}-delivery")
      assert_operator delivery.recorded_at, :>=, artifact.recorded_at
      assert_equal artifact.id,delivery.parent_id
      observation=JSON.parse(artifact.original_bytes)
      assert_equal Time.iso8601(observation.fetch('received_at')).to_i,delivery.recorded_at.to_i
    end
    {'fact'=>%w[disclosure-termination disclosure-salary-terms disclosure-bonus-event disclosure-loan-terms disclosure-forgiveness-event disclosure-equity-award disclosure-custody-statement disclosure-fund-cost disclosure-custodian-advisory-observation], 'payment'=>%w[disclosure-receipt disclosure-refund disclosure-loan-cash]}.each do |kind,ids|
      ids.each do |id|
        row=@service.get(kind,id)
        delivery=MedallionEvidence.find(row.parent_id)
        assert_equal 'delivery',delivery.kind
        assert_operator row.recorded_at, :>=, delivery.recorded_at
      end
    end
    credit=@service.get('event','disclosure-credit'); credit_run=@service.get('run',credit.payload.fetch('run_id'))
    assert_equal '2027-02-16T00:00:00Z',credit_run.payload.fetch('knowledge_cutoff')
    refute credit_run.payload.fetch('input_manifest').fetch('facts').key?('refund')
    policy=@service.get('policy',credit_run.payload.fetch('policy_id'))
    earlier=@service.engine_run(policy,credit_run.payload.fetch('input_manifest'),cutoff:'2027-02-15T23:59:59Z')
    refute earlier.fetch('details').any? { |item| item['id']=='credit' }, 'Termination was not known before its arrival'
    life=indexed('lifecycle','finance')
    assert_equal 50000,life.fetch('disclosure-credit').fetch('amount_minor')
    assert_equal 30000,life.fetch('disclosure-refund').fetch('amount_minor')
    assert_equal 20000,life.fetch('disclosure-refund-remaining').fetch('amount_minor')
    schedule=indexed('recognition','finance').fetch('disclosure-recognition-schedule').fetch('supplied_treatment')
    source=@service.get('fact','disclosure-recognition-schedule').payload.fetch('treatment')
    %w[initial_deferred_minor recognized_minor deferred_before_credit_minor correction_deferred_minor missing_outcome].each do |key|
      assert_equal source.fetch(key),schedule.fetch(key), "Schedule projection must preserve supplied #{key}"
    end
    assert indexed('recognition','finance').key?('disclosure-recognition-missing'), 'A schedule is not a correction posting'
    assert_equal 'confirmed_outbound_refund',life.fetch('disclosure-refund').fetch('classification')
    receipt=@service.get('payment','disclosure-receipt'); refund=@service.get('payment','disclosure-refund')
    refute_equal receipt.parent_id,refund.parent_id, 'Cash directions need separate source arrivals'
    assert_equal 100000,receipt.payload.fetch('amount_minor')
  end
  class ApplicationRelation < SimpleDelegator
    def initialize(relation, mode); super(relation); @mode=mode; end
    def find_by(**args)
      row=__getobj__.find_by(**args)
      return row unless args[:external_id]=='disclosure-refund-application'
      return nil if @mode==:missing
      fake=row.dup
      altered=row.payload.merge('payment_hash'=>'forged')
      fake.define_singleton_method(:payload) { altered }
      fake
    end
  end
  def test_unmatched_or_forged_refund_is_not_presented_as_sent
    m=@operator.medallion; original=m.method(:source)
    @operator.define_singleton_method(:medallion) { m }
    [:missing,:forged].each do |mode|
      m.define_singleton_method(:source) do |case_id,scenario,kind|
        relation=original.call(case_id,scenario,kind)
        kind=='application' ? ApplicationRelation.new(relation,mode) : relation
      end
      result=DisclosureReadModel.new(@operator).view('advisor',audience:'finance',limit:100)
      refute result.dig('sections','lifecycle').any? { |item| item['id']=='disclosure-refund' }
      assert result.fetch('exceptions').any? { |item| item['id']=='disclosure-refund-unmatched' }
    end
  ensure
    m.singleton_class.remove_method(:source) if m.singleton_class.instance_methods(false).include?(:source)
    @operator.singleton_class.remove_method(:medallion) if @operator.singleton_class.instance_methods(false).include?(:medallion)
  end
  def test_compensation_costs_and_original_invoice_remain_separate
    comp=indexed('compensation')
    {'disclosure-salary-entitlement'=>500000,'disclosure-bonus-entitlement'=>100000,'disclosure-loan-entitlement'=>1200000,'disclosure-loan-cash'=>1200000,'disclosure-forgiveness-entitlement'=>100000,'disclosure-loan-outstanding'=>1100000}.each { |id,value| assert_equal value,comp.fetch(id).fetch('amount_minor') }
    assert_equal 'loan_principal',comp.fetch('disclosure-loan-entitlement')['classification']
    assert_equal 'confirmed_loan_advance',comp.fetch('disclosure-loan-cash')['classification']
    assert_nil comp.fetch('disclosure-equity')['amount_minor']
    assert_match(/100/,comp.fetch('disclosure-equity')['quantity'])
    costs=indexed('costs')
    assert_equal 102500,costs.fetch('disclosure-known-direct')['amount_minor']
    included=costs.values.select { |item| item['included_in_subtotal']==true }
    assert_equal [2500,100000],included.map { |item| item['amount_minor'] }.sort
    duplicate=costs.fetch('disclosure-custodian-advisory-observation')
    assert_equal 100000,duplicate.fetch('amount_minor')
    assert_equal false,duplicate.fetch('included_in_subtotal')
    assert_equal 'observed_duplicate_of_assessed_charge',duplicate.fetch('classification')
    assert_nil costs.fetch('disclosure-fund-cost')['amount_minor']
    assert_equal 100000,BillingInvoice.find_by!(external_id:'disclosure-invoice-v1').amount_minor
  end
  def test_refund_validator_rejects_forged_and_malformed_sources
    scope={'tenant_id'=>'t','entity_id'=>'e','case_id'=>'advisor','currency'=>'USD'}
    receipt=scope.merge('id'=>'r','hash'=>'a'*64,'status'=>'confirmed','payer'=>'client','payee'=>'firm','amount_minor'=>1000)
    credit=scope.merge('id'=>'c','hash'=>'b'*64,'status'=>'approved','payer'=>'firm','payee'=>'client','amount_minor'=>500)
    payment=scope.merge('id'=>'p','status'=>'confirmed','payer'=>'firm','payee'=>'client','amount_minor'=>300,'original_receipt_id'=>'r','original_receipt_hash'=>'a'*64,'credit_id'=>'c','credit_hash'=>'b'*64)
    assert DisclosureRefunds.validate!(payment:payment,credit:credit,receipt:receipt,applications:[])
    [{payment:payment.merge('original_receipt_hash'=>'f'*64),credit:credit,receipt:receipt,applications:[]},
     {payment:payment.merge('credit_id'=>nil,'credit_hash'=>nil),credit:credit.merge('id'=>nil,'hash'=>nil),receipt:receipt,applications:[]},
     {payment:payment,credit:credit,receipt:receipt,applications:[nil]},
     {payment:payment.merge('status'=>'pending'),credit:credit,receipt:receipt,applications:[]}].each do |bad|
      assert_equal 'SCOPE_MISMATCH',assert_raises(Economics::Error) { DisclosureRefunds.validate!(**bad) }.code
    end
    other=scope.merge('payment_id'=>'prior','credit_id'=>'other','credit_hash'=>'c'*64,'original_receipt_id'=>'r','original_receipt_hash'=>'a'*64,'amount_minor'=>800)
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error) { DisclosureRefunds.validate!(payment:payment,credit:credit,receipt:receipt,applications:[other]) }.code
  end
end
