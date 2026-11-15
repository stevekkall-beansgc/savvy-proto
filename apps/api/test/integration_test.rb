ENV['RAILS_ENV']='test'
ENV['SYNTHETIC_DEMO']='1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'
require 'rack/test'

class WorkbenchIntegrationTest < Minitest::Test
  include Rack::Test::Methods
  def app = Rails.application
  def setup
    header "Host", "localhost"
    SyntheticReset.call
    @s=Workbench.new
    @s.seed!
  end
  def request_input = {'policy_id'=>'policy-v1','snapshot_id'=>'source-20261113-r1'}
  def test_runs_are_persisted_and_idempotency_binds_inputs
    first=@s.project(request_input,'same')
    assert_equal first,@s.project(request_input,'same')
    assert_equal 1,@s.records('run').count
    assert_equal 'IDEMPOTENCY_CONFLICT',assert_raises(Economics::Error){@s.project(request_input.merge('business_date'=>'2026-11-12'),'same')}.code
    assert_equal first,@s.run(first['id'])
    assert_equal 100000,@s.snapshot['grants'][0]['remaining_minor']
  end
  def test_policy_changes_do_not_rewrite_prior_run_or_approval
    old=@s.project(request_input,'original')
    p=@s.policy
    old_hash=Economics::Canonical.hash(p)
    p['rates'].each{|r|r['numerator']=70}
    saved=@s.save_policy({'policy'=>p,'expected_hash'=>old_hash},'change')
    assert_equal 'policy-v2',saved['id']
    assert_equal old,@s.run(old['id'])
    new_run=@s.project(request_input.merge('policy_id'=>saved['id']),'new')
    refute_equal old['policy_hash'],new_run['policy_hash']
    assert_equal 70000,new_run['lines'][0]['earned_minor']
    assert_equal 'REVIEW_REQUIRED',assert_raises(Economics::Error){@s.activate({'policy_id'=>saved['id'],'policy_hash'=>new_run['policy_hash']},'activation')}.code
  end
  def test_hash_bound_review_and_activation
    p=@s.policy;hash=Economics::Canonical.hash(p)
    %w[finance legal].each{|role|Workbench.new(role:role).review({'policy_id'=>p['id'],'policy_hash'=>hash},"approve-#{role}")}
    assert_equal false,@s.activate({'policy_id'=>p['id'],'policy_hash'=>hash},'activate')['contract_executed']
    assert_equal 'HASH_CHANGED',assert_raises(Economics::Error){Workbench.new(role:'legal').review({'policy_id'=>p['id'],'policy_hash'=>'stale'},'stale')}.code
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error){@s.review({'policy_id'=>p['id'],'policy_hash'=>hash},'self')}.code
  end
  def test_cash_before_invoice_and_later_invoice_do_not_create_cash
    input={'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>60000}
    @s.match(input,'cash-a')
    @s.match(input,'cash-a')
    c=@s.collections('customer-cedar')[0]
    assert_equal 60000,c['operational_matched_minor'];assert_equal 40000,c['unmatched_charge_minor'];assert_nil c['ar_minor']
    invoice=c.slice('tenant_id','entity_id','currency','customer_id').merge('id'=>'invoice-a','amount_minor'=>100000,'status'=>'open','synthetic'=>true)
    Workbench.new(role:'finance').link_invoice({'charge_id'=>input['charge_id'],'invoice'=>invoice},'invoice')
    c=@s.collections('customer-cedar')[0]
    assert_equal 60000,c['observed_cash_minor'];assert_equal 60000,c['operational_matched_minor']
    assert_nil c['invoice_applied_minor'];assert_nil c['recognized_revenue_minor'];assert_nil c['bank_settled_minor']
    assert_equal 1,@s.records('receipt').where(external_id:'receipt-cedar').count
  end
  def test_overapplication_and_cross_customer_are_rejected
    input={'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>60001}
    assert_equal 'ALLOCATION_EXCEEDED',assert_raises(Economics::Error){@s.match(input,'over')}.code
    assert_equal 'UNRESOLVED_MAPPING',assert_raises(Economics::Error){@s.match(input.merge('receipt_id'=>'receipt-maple'),'cross')}.code
    assert_equal 0,DemoAllocation.count
  end
  def test_concurrent_match_claims_conserve_cash
    input={'charge_id'=>'charge-customer-cedar','receipt_id'=>'receipt-cedar','minor_units'=>40000}
    results=2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Workbench.new.match(input,"parallel-#{i}")
        rescue Economics::Error => e
          e.code
        end
      end
    end.map(&:value)
    assert_equal 1,results.count('ALLOCATION_EXCEEDED')
    assert_equal 40000,DemoAllocation.sum(:minor_units)
  end
  def test_database_entity_foreign_key_is_enforced
    assert_raises(ActiveRecord::InvalidForeignKey) do
      DemoAllocation.create!(tenant_id:Workbench::TENANT,entity_id:'wrong-entity',kind:'operational_match',source_id:'x',target_id:'y',currency:'USD',minor_units:1,idempotency_key:'bad',created_at:Time.now)
    end
  end
  def test_tenant_scope_and_advisor_scope_do_not_leak
    run=@s.project(request_input,'run')
    assert_equal 'NOT_FOUND',assert_raises(Economics::Error){Workbench.new(tenant:'another',entity:Workbench::ENTITY).run(run['id'])}.code
    advisor=Workbench.new(role:'advisor')
    assert_equal ['broker-alex'],advisor.state['brokers'].map{|b|b['id']}
    assert_nil advisor.state['policy'];assert_nil advisor.state['snapshot']
    assert advisor.run(run['id'])['lines'].all?{|l|l['broker_id']=='broker-alex'}
    assert_empty advisor.collections('customer-birch')
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error){advisor.project(request_input,'denied')}.code
    assert_equal 'FORBIDDEN',assert_raises(Economics::Error){advisor.packet(run['id'])}.code
  end
  def test_import_retries_and_conflicting_revision_are_visible
    snapshot=@s.snapshot
    assert_equal 'completed',@s.import_snapshot({'snapshot'=>snapshot},'same-source')['quality']
    snapshot['facts'][0]['eligible_minor']=123
    result=@s.import_snapshot({'snapshot'=>snapshot},'conflict')
    assert_equal 'SOURCE_CONFLICT',result['code']
    assert_equal 100000,@s.snapshot['facts'][0]['eligible_minor']
    assert_equal 1,@s.records('quarantine').count
  end
  def test_different_batch_cannot_rewrite_accepted_source_revision
    source=@s.snapshot
    source['id']='new-batch-same-source-revision'
    source['facts'][0]['eligible_minor']=555
    assert_equal 'SOURCE_CONFLICT',@s.import_snapshot({'snapshot'=>source},'hidden-change')['code']
    assert_equal 1,@s.records('snapshot').count
    source['facts'][0]['revision']=2
    assert_equal 'completed',@s.import_snapshot({'snapshot'=>source},'new-revision')['quality']
    assert_equal 2,@s.records('snapshot').count
    assert_equal 2,@s.records('source_fact').where(external_id:'synthetic-internal-v1:fee-a').count
  end
  def test_invalid_origin_and_large_body_are_rejected
    post '/graphql',JSON.generate({'query'=>'{workbench}'}),{'CONTENT_TYPE'=>'application/json','HTTP_ORIGIN'=>'https://example.invalid'}
    assert_equal 403,last_response.status
    post '/graphql','x' * 1_048_577,{'CONTENT_TYPE'=>'application/json'}
    assert_equal 413,last_response.status
  end
  def test_packet_freezes_terms_and_examples
    run=@s.project(request_input,'packet')
    packet=@s.packet(run['id'])
    assert_equal run['policy_hash'],packet['policy_hash']
    assert_equal false,packet['contract_executed']
    assert_equal 3,packet['examples']['lines'].size
  end
  def test_graphql_real_http_shape_and_string_money
    post '/graphql',JSON.generate({'query'=>'{ brokerBook(brokerId:"broker-alex") { id earned { minorUnits currency } } }'}),{'CONTENT_TYPE'=>'application/json'}
    assert_equal 200,last_response.status
    assert_nil JSON.parse(last_response.body).dig('data','brokerBook','earned')
    @s.project(request_input,'graphql')
    post '/graphql',JSON.generate({'query'=>'{ brokerBook(brokerId:"broker-alex") { id earned { minorUnits currency } } workbench }'}),{'CONTENT_TYPE'=>'application/json'}
    data=JSON.parse(last_response.body)
    assert_nil data['errors'],data.inspect
    assert_equal '175000',data.dig('data','brokerBook','earned','minorUnits')
    assert_equal '90000',data.dig('data','workbench','latest_run','lines',0,'earned_minor')
  end
  def test_schema_can_be_reloaded_without_duplicate_type_definitions
    expected=WorkbenchSchema.execute('{__typename}').to_h
    Rails.application.reloader.reload!
    assert_equal expected,WorkbenchSchema.execute('{__typename}').to_h
  end
  def test_invalid_request_and_graphql_role_errors
    post '/graphql','[1,2]',{'CONTENT_TYPE'=>'application/json'}
    assert_equal 400,last_response.status
    mutation='mutation($i:JSON!){workbenchCommand(action:PROJECT,input:$i,idempotencyKey:"attempt"){errors{code} data}}'
    post '/graphql',JSON.generate({'query'=>mutation,'variables'=>{'i'=>request_input}}),{'CONTENT_TYPE'=>'application/json','HTTP_X_DEMO_ROLE'=>'advisor'}
    assert_equal 'FORBIDDEN',JSON.parse(last_response.body).dig('data','workbenchCommand','errors',0,'code')
  end
  def test_missing_receipt_evidence_remains_unknown
    c=@s.collections('customer-birch').first
    assert_nil c['observed_cash_minor']
    assert_equal ['broker-jordan'],c['broker_ids']
    assert_equal 0,c['operational_matched_minor']
  end
  def test_invoice_variance_is_not_hidden
    invoice=@s.collections('customer-cedar')[0].slice('tenant_id','entity_id','currency','customer_id').merge('id'=>'wrong','amount_minor'=>105000,'status'=>'open','synthetic'=>true)
    assert_equal 'INVOICE_VARIANCE',assert_raises(Economics::Error){Workbench.new(role:'finance').link_invoice({'charge_id'=>'charge-customer-cedar','invoice'=>invoice},'bad-invoice')}.code
    assert_equal 0,@s.records('invoice').count
  end
end
