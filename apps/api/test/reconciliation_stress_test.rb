# Run only on the disposable Rails test database; setup clears its demo tables.
ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class ReconciliationStressTest < Minitest::Test
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    @operator=Workbench.new; @operator.seed!; @finance=Workbench.new(role:'finance')
    %w[cedar maple].each do |name|
      charge=@finance.record!('charge',"charge-customer-#{name}")
      invoice=charge.slice('tenant_id','entity_id','currency','customer_id','amount_minor').merge('id'=>"invoice-#{name}",'status'=>'open','synthetic'=>true)
      @finance.link_invoice({'charge_id'=>charge['id'],'invoice'=>invoice},"link-#{name}")
    end
  end
  def app(value=30000)
    {'invoice_id'=>'invoice-cedar','receipt_id'=>'receipt-cedar','minor_units'=>value,'business_date'=>'2026-11-13','reason'=>'Synthetic stress evidence'}
  end
  def batch(id='batch-one',ids=%w[receipt-cedar receipt-maple],gross=160000,fee=3000)
    {'id'=>id,'receipt_ids'=>ids,'gross_minor'=>gross,'fee_minor'=>fee,'net_minor'=>gross-fee,'business_date'=>'2026-11-13','reason'=>'Synthetic bank evidence'}
  end
  def view(id=nil)
    @finance.reconciliation(period_start:'2026-11-01',period_end_exclusive:'2026-12-01',close_id:id)
  end
  def concurrent(count, &block)
    gate=Queue.new
    threads=count.times.map do |i|
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            block.call(Workbench.new(role:'finance'),i)
          rescue Economics::Error => e
            e.code
          end
        end
      end
    end
    count.times { gate << true }
    threads.map(&:value)
  end
  def test_parallel_bounded_applications_and_idempotent_retry
    results=concurrent(4) { |w,i| w.record_invoice_application(app,"claim-#{i}") }
    assert_equal 2,results.count { |x| x.is_a?(Hash) }
    assert_equal 2,results.count('ALLOCATION_EXCEEDED')
    assert_equal 60000,view['invoices'].find { |i| i['id']=='invoice-cedar' }['applied_minor']
    reversal={'application_id'=>results.find { |x| x.is_a?(Hash) }['id'],'business_date'=>'2026-11-13','reason'=>'Correction'}
    undone=@finance.reverse_invoice_application(reversal,'undo')
    assert_equal undone,@finance.reverse_invoice_application(reversal,'undo')
    assert_equal 'ALREADY_REVERSED',assert_raises(Economics::Error) { @finance.reverse_invoice_application(reversal,'undo-again') }.code
  end
  def test_parallel_same_key_and_conflicting_reuse
    results=concurrent(4) { |w,_| w.record_invoice_application(app(60000),'same-key') }
    assert results.all? { |r| r==results.first }
    assert_equal 1,@finance.records('invoice_application').count
    assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error) { @finance.record_invoice_application(app(1),'same-key') }.code
  end
  def test_parallel_duplicate_bank_membership
    results=concurrent(2) { |w,i| w.record_bank_batch(batch("batch-#{i}",['receipt-cedar'],60000,0),"batch-#{i}") }
    assert_equal 1,results.count { |x| x.is_a?(Hash) }
    assert_equal 1,results.count('ALLOCATION_EXCEEDED')
    assert_equal 1,@finance.records('bank_batch').count
  end
  def test_freeze_racing_write_is_coherent
    hash=view['manifest_hash']
    input={'period_start'=>'2026-11-01','period_end_exclusive'=>'2026-12-01','expected_manifest_hash'=>hash,'reason'=>'Synthetic review'}
    results=concurrent(2) { |w,i| i.zero? ? w.close_reconciliation(input,'freeze') : w.record_invoice_application(app(60000),'write') }
    assert_kind_of Hash,results[1]
    if results[0].is_a?(Hash)
      frozen=view(results[0]['id'])
      assert_equal hash,frozen['manifest_hash']
      assert_nil frozen['totals']['invoice_applied_minor']
      assert frozen['later_evidence'].any? { |e| e['id']==results[1]['id'] }
    else
      assert_equal 'HASH_CHANGED',results[0]
      assert_empty @finance.records('reconciliation_close')
    end
  end
  def test_failure_after_evidence_write_rolls_back_record_and_operation
    singleton=class << DemoOperation; self; end
    singleton.alias_method(:stress_original_create!, :create!)
    singleton.define_method(:create!) { |**_| raise 'injected operation failure' }
    begin
      error=assert_raises(RuntimeError) { @finance.record_invoice_application(app(60000),'failure') }
    ensure
      singleton.alias_method(:create!, :stress_original_create!)
      singleton.remove_method(:stress_original_create!)
    end
    assert_equal 'injected operation failure',error.message
    assert_empty @finance.records('invoice_application')
    refute DemoOperation.exists?(operation:'record_invoice_application',idempotency_key:'failure')
    assert_kind_of Hash,@finance.record_invoice_application(app(60000),'failure')
  end
  def test_invalid_decimal_date_scope_and_role_leave_no_evidence
    assert_equal 'INVALID_INTEGER',assert_raises(Economics::Error) { @finance.record_invoice_application(app(1.5),'decimal') }.code
    assert_raises(Economics::Error) { @finance.record_invoice_application(app.merge('business_date'=>'2026-02-30'),'date') }
    assert_equal 'NOT_FOUND',assert_raises(Economics::Error) { @finance.record_invoice_application(app.merge('invoice_id'=>'outside-scope'),'scope') }.code
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error) { @operator.record_invoice_application(app,'role') }.code
    assert_empty @finance.records('invoice_application')
  end
  def test_repeated_races
    20.times do |round|
      # A retry key is immutable and must produce one evidence row despite racing.
      key="repeat-#{round}"
      input=app(1)
      results=concurrent(4) { |w,_| w.record_invoice_application(input,key) }
      assert results.all? { |r| r==results.first }, "retry round #{round}"
      assert_equal 1,@finance.records('invoice_application').where(external_id:results.first['id']).count
    end
    # 59,980 cents remain after the 20 successful one-cent records.
    results=concurrent(4) { |w,i| w.record_invoice_application(app(30000),"bounded-#{i}") }
    assert_equal 1,results.count { |r| r.is_a?(Hash) }
    assert_equal 3,results.count('ALLOCATION_EXCEEDED')
    assert_equal 30020,view['invoices'].find { |i| i['id']=='invoice-cedar' }['applied_minor']
  end
  def test_canonical_populated_reporting_fixture
    assert_nil view['totals']['invoice_applied_minor']
    @finance.record_invoice_application(app(60000),'canonical-cedar')
    @finance.record_invoice_application(app(100000).merge('invoice_id'=>'invoice-maple','receipt_id'=>'receipt-maple'),'canonical-maple')
    @finance.record_bank_batch(batch,'canonical-batch')
    totals=view['totals']
    assert_equal [200000,160000,40000,160000,3000,157000],totals.values_at('invoice_amount_minor','invoice_applied_minor','invoice_open_minor','bank_gross_minor','bank_fee_minor','bank_net_minor')
    assert_nil totals['recognized_revenue_minor']
    @finance.reverse_receipt({'receipt_id'=>'receipt-cedar','expected_revision'=>1,'reason'=>'Synthetic correction'},'canonical-reverse')
    codes=view['exceptions'].map { |e| e['code'] }
    assert_includes codes,'RECEIPT_APPLICATION_CONFLICT'
    assert_includes codes,'RECEIPT_BANK_CONFLICT'
  end

  def test_repeated_freeze_write_races
    10.times do |round|
      setup if round > 0
      hash=view['manifest_hash']
      input={'period_start'=>'2026-11-01','period_end_exclusive'=>'2026-12-01','expected_manifest_hash'=>hash,'reason'=>'Synthetic review'}
      result=concurrent(2) { |w,i| i.zero? ? w.close_reconciliation(input,'freeze') : w.record_invoice_application(app(60000),'write') }
      assert_kind_of Hash,result[1]
      if result[0].is_a?(Hash)
        frozen=view(result[0]['id'])
        assert_equal hash,frozen['manifest_hash']
        assert_nil frozen['totals']['invoice_applied_minor']
        assert frozen['later_evidence'].any? { |e| e['id']==result[1]['id'] }
      else
        assert_equal 'HASH_CHANGED',result[0]
        assert_empty @finance.records('reconciliation_close')
      end
    end
  end
  def test_repeated_apply_and_receipt_reversal_races
    10.times do |round|
      setup if round > 0
      result=concurrent(2) do |w,i|
        i.zero? ? w.record_invoice_application(app(60000),'apply') : w.reverse_receipt({'receipt_id'=>'receipt-cedar','expected_revision'=>1,'reason'=>'Synthetic correction'},'reverse')
      end
      assert_kind_of Hash,result[1]
      if result[0].is_a?(Hash)
        assert_includes view['exceptions'].map { |e| e['code'] },'RECEIPT_APPLICATION_CONFLICT'
      else
        assert_equal 'UNRESOLVED_MAPPING',result[0]
        assert_empty @finance.records('invoice_application')
      end
    end
  end
  def test_graphql_roles_and_unsupported_sources
    query='{ reconciliation(periodStart:"2026-11-01",periodEndExclusive:"2026-12-01") }'
    %w[operator finance legal auditor advisor].each do |role|
      response=WorkbenchSchema.execute(query,context:{workbench:Workbench.new(role:role)}).to_h
      if role=='advisor'
        assert_equal 'FORBIDDEN',response.dig('errors',0,'extensions','code')
      else
        assert_nil response['errors']
        assert_equal '200000',response.dig('data','reconciliation','totals','invoice_amount_minor')
      end
    end
    wrong=app.merge('invoice_id'=>'invoice-maple')
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error) { @finance.record_invoice_application(wrong,'cross-customer') }.code
    receipt=@finance.record!('receipt','receipt-cedar').merge('revision'=>2,'status'=>'unsupported')
    @finance.write!('receipt',receipt,revision:2)
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error) { @finance.record_invoice_application(app,'unknown-status') }.code
    @finance.record_bank_batch(batch('maple-only',['receipt-maple'],100000,0),'first-batch')
    assert_equal 'SOURCE_CONFLICT',assert_raises(Economics::Error) { @finance.record_bank_batch(batch('maple-only',['receipt-maple'],100000,0),'different-key') }.code
  end

end
