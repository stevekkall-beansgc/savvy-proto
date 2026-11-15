ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
require 'active_support/testing/time_helpers'
class SettlementTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  def setup
    SyntheticReset.call
    travel_to(Time.iso8601('2026-11-13T21:30:00Z'))
    @operator=Workbench.new
    @operator.seed!
    @finance=Workbench.new(role:'finance')
  end
  def consume_input(amount=60000,obligation='obligation-alex-cedar',grant='grant-alex')
    {'grant_id'=>grant,'obligation_id'=>obligation,'minor_units'=>amount,'reason'=>'Synthetic settlement example'}
  end
  def test_two_concurrent_claims_cannot_overspend_one_grant
    results=%w[obligation-alex-cedar obligation-alex-maple].map.with_index do |o,i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Workbench.new(role:'finance').consume_entitlement(consume_input(60000,o),"claim-#{i}")
        rescue Economics::Error=>e
          e.code
        end
      end
    end.map(&:value)
    assert_equal 1,results.count('ALLOCATION_EXCEEDED')
    assert_equal 60000,DemoEntitlementEntry.sum(:minor_units)
    assert_equal 40000,@operator.entitlement_ledger('broker-alex')['grants'].find{|g|g['id']=='grant-alex'}['remaining_minor']
  end
  def test_consumption_retry_and_reversal_restore_exact_original_grant_once
    original=@finance.consume_entitlement(consume_input,'first')
    assert_equal original,@finance.consume_entitlement(consume_input,'first')
    assert_equal 1,DemoEntitlementEntry.count
    input={'entry_id'=>original['entry_id'],'reason'=>'Correct the fictional application'}
    reversal=@finance.reverse_entitlement(input,'reverse')
    assert_equal 60000,reversal['restored_minor']
    assert_equal reversal,@finance.reverse_entitlement(input,'reverse')
    assert_equal 'ALREADY_REVERSED',assert_raises(Economics::Error){@finance.reverse_entitlement(input,'new-key')}.code
    book=@operator.entitlement_ledger('broker-alex')
    assert_equal 100000,book['grants'].find{|g|g['id']=='grant-alex'}['remaining_minor']
    assert_equal 75000,book['grants'].find{|g|g['id']=='grant-broker-prepay'}['remaining_minor']
    assert_equal 2,book['entries'].length
    assert_equal false,book['payment_executed']
  end
  def test_direction_and_unit_scope_cannot_be_netted
    assert_equal 'DIRECTION_MISMATCH',assert_raises(Economics::Error){@finance.consume_entitlement(consume_input(50000,'obligation-broker-service','grant-alex'),'opposite')}.code
    result=@finance.consume_entitlement(consume_input(75000,'obligation-broker-service','grant-broker-prepay'),'broker-prepay')
    assert_equal 0,result['remaining_grant_minor']
    o=@operator.entitlement_ledger('broker-alex')['obligations'].find{|x|x['id']=='obligation-broker-service'}
    assert_equal 100000,o['amount_minor'];assert_equal 75000,o['applied_minor'];assert_equal 25000,o['uncovered_minor']
    result=@finance.consume_entitlement(consume_input(100000,'obligation-jordan-birch','grant-jordan-advance'),'jordan')
    assert_equal 50000,result['remaining_grant_minor']
  end
  def test_reversing_a_reversal_and_cross_scope_are_rejected
    first=@finance.consume_entitlement(consume_input,'first')
    r=@finance.reverse_entitlement({'entry_id'=>first['entry_id'],'reason'=>'Fixture correction'},'reverse')
    assert_equal 'INVALID_REVERSAL',assert_raises(Economics::Error){@finance.reverse_entitlement({'entry_id'=>r['entry_id'],'reason'=>'Not allowed'},'double')}.code
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error){@operator.consume_entitlement(consume_input,'not-finance')}.code
    assert_equal 'NOT_FOUND',assert_raises(Economics::Error){Workbench.new(role:'advisor').entitlement_ledger('broker-jordan')}.code
    advisor=Workbench.new(role:'advisor').entitlement_ledger
    refute advisor['grants'].any?{|g|g['payee']=='broker-jordan'}
  end
  def test_projections_freeze_as_known_balances_and_never_spend_coverage
    input={'policy_id'=>'policy-v1','snapshot_id'=>'source-20261113-r1'}
    before=@operator.project(input.merge('knowledge_cutoff'=>'2026-11-13T21:59:00Z'),'before')
    travel_to(Time.iso8601('2026-11-13T22:01:00Z')) do
      @finance.consume_entitlement(consume_input(60000),'a')
      @finance.consume_entitlement(consume_input(40000,'obligation-alex-maple'),'b')
    end
    after=@operator.project(input.merge('knowledge_cutoff'=>'2026-11-13T22:02:00Z'),'after')
    assert_equal 100000,before['lines'].sum{|l|l['coverage']['coverage_minor']}
    assert_equal 0,after['lines'].sum{|l|l['coverage']['coverage_minor']}
    assert_equal before,@operator.run(before['id'])
    assert_equal 100000,@operator.snapshot['grants'][0]['remaining_minor']
    assert_equal 2,DemoEntitlementEntry.count
    refute_equal before['input_hash'],after['input_hash']
  end
  def test_database_reversal_scope_fk_and_unique_original_are_enforced
    original=@finance.consume_entitlement(consume_input,'original')
    assert_raises(ActiveRecord::InvalidForeignKey) do
      DemoEntitlementEntry.create!(tenant_id:Workbench::TENANT,entity_id:'wrong',grant_id:'grant-alex',obligation_id:'obligation-alex-cedar',kind:'reversal',minor_units:60000,currency:'USD',original_entry_id:original['entry_id'],actor_id:'finance',reason:'Invalid scope',business_date:Workbench::DATE,created_at:Time.current)
    end
  end
  def test_match_reversal_releases_allocation_without_reversing_receipt
    match=@operator.match({'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>60000},'match')
    @finance.reverse_match({'allocation_id'=>match['id'],'reason'=>'Correct allocation only'},'undo-match')
    c=@operator.collections('customer-cedar').first
    assert_equal 60000,c['observed_cash_minor'];assert_equal 0,c['operational_matched_minor']
    assert_equal 60000,c['receipts'][0]['unapplied_minor']
    assert_equal 'reversed',c['matches'][0]['status']
    assert_equal 1,DemoAllocation.count
  end
  def test_receipt_reversal_preserves_prior_asof_and_releases_matches
    travel_to(Time.iso8601('2026-11-13T22:00:00Z')) do
      @operator.match({'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>60000},'match')
    end
    input={'receipt_id'=>'receipt-cedar','expected_revision'=>1,'reason'=>'Synthetic source correction'}
    result=nil
    travel_to(Time.iso8601('2026-11-13T22:05:00Z')) { result=@finance.reverse_receipt(input,'reverse-receipt') }
    assert_equal result,@finance.reverse_receipt(input,'reverse-receipt')
    old=@operator.collections('customer-cedar',cutoff:'2026-11-13T22:02:00Z').first
    current=@operator.collections('customer-cedar',cutoff:'2026-11-13T22:06:00Z').first
    assert_equal 60000,old['observed_cash_minor'];assert_equal 60000,old['operational_matched_minor']
    assert_equal 0,current['observed_cash_minor'];assert_equal 0,current['operational_matched_minor']
    assert_equal 60000,current['reversed_receipt_minor'];assert_equal 100000,current['unmatched_charge_minor']
    assert_nil current['bank_settled_minor'];assert_equal false,result['bank_refund_verified']
    assert_equal 2,@operator.records('receipt').where(external_id:'receipt-cedar').count
    assert_equal 1,DemoMatchReversal.count
    assert_equal 'REVISION_CONFLICT',assert_raises(Economics::Error){@finance.reverse_receipt(input,'stale')}.code
    assert_equal 'ALREADY_REVERSED',assert_raises(Economics::Error){@finance.reverse_receipt(input.merge('expected_revision'=>2),'again')}.code
  end
  def test_immediate_reversal_has_a_causally_ordered_previous_view
    @operator.match({'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>60000},'match')
    r=@finance.reverse_receipt({'receipt_id'=>'receipt-cedar','expected_revision'=>1,'reason'=>'Immediate fixture correction'},'reverse')
    old=@operator.collections('customer-cedar',cutoff:r['previous_view_cutoff']).first
    assert_equal 60000,old['observed_cash_minor']
    assert_equal 60000,old['operational_matched_minor']
    assert_equal 0,@operator.collections('customer-cedar').first['observed_cash_minor']
  end
  def test_new_graphql_commands_and_money_strings
    mutation='mutation($input:JSON!){workbenchCommand(action:CONSUME_ENTITLEMENT,input:$input,idempotencyKey:"graphql-consume"){data errors{code message}}}'
    r=WorkbenchSchema.execute(mutation,variables:{'input'=>consume_input.merge('minor_units'=>'50000')},context:{workbench:@finance}).to_h
    assert_nil r['errors']
    assert_empty r.dig('data','workbenchCommand','errors')
    assert_equal '50000',r.dig('data','workbenchCommand','data','minor_units')
    view=WorkbenchSchema.execute('{entitlementLedger(brokerId:"broker-alex")}',context:{workbench:@finance}).to_h
    assert_equal '50000',view.dig('data','entitlementLedger','grants').find{|g|g['id']=='grant-alex'}['remaining_minor']
    denied=WorkbenchSchema.execute('{entitlementLedger(brokerId:"broker-jordan")}',context:{workbench:Workbench.new(role:'advisor')}).to_h
    assert_equal 'NOT_FOUND',denied.dig('errors',0,'extensions','code')
  end
  def test_reversed_receipt_cannot_be_matched_again
    @finance.reverse_receipt({'receipt_id'=>'receipt-cedar','expected_revision'=>1,'reason'=>'Synthetic correction'},'reverse')
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error){@operator.match({'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>1},'reapply')}.code
    assert_equal 0,DemoAllocation.count
  end
  def test_malformed_amount_and_missing_reason_do_not_leave_entries
    assert_equal 'INVALID_INTEGER',assert_raises(Economics::Error){@finance.consume_entitlement(consume_input(1.5),'float')}.code
    assert_equal 'VALIDATION_ERROR',assert_raises(Economics::Error){@finance.consume_entitlement(consume_input.merge('reason'=>''),'no-reason')}.code
    assert_equal 0,DemoEntitlementEntry.count
  end
end
