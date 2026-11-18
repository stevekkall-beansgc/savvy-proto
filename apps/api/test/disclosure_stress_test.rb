# Independent disclosure contract stress checks. Run only on the disposable
# synthetic test database, serially with other reset-using suites.
ENV['RAILS_ENV'] = 'test'
ENV['SYNTHETIC_DEMO'] = '1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class DisclosureStressTest < Minitest::Test
  QUERY = 'query($case:ID!,$audience:String!,$limit:Int,$offset:Int){disclosureWorkspace(caseId:$case,audience:$audience,limit:$limit,offset:$offset)}'
  MUTATION = 'mutation($action:String!,$input:JSON!,$key:String!){disclosureCommand(action:$action,input:$input,idempotencyKey:$key){data errors{code message}}}'

  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    Workbench.new.seed!
    result = command('operator', 'BOOTSTRAP', {}, 'independent-bootstrap')
    assert_empty result.fetch('errors')
  end

  def execute(role, document, variables)
    WorkbenchSchema.execute(document, variables: variables, context: {workbench: Workbench.new(role: role)}).to_h
  end

  def command(role, action, input, key)
    response = execute(role, MUTATION, {'action'=>action, 'input'=>input, 'key'=>key})
    assert_nil response['errors'], response.inspect
    response.fetch('data').fetch('disclosureCommand')
  end

  def workspace(role, case_id, audience, limit: 20, offset: 0)
    execute(role, QUERY, {'case'=>case_id, 'audience'=>audience, 'limit'=>limit, 'offset'=>offset})
  end

  def test_scope_and_audience_cannot_be_escalated_by_arguments
    [['advisor','ria','client'], ['ria','advisor','client'],
     ['advisor','advisor','product'], ['advisor','advisor','finance'],
     ['ria','ria','product'], ['ria','ria','finance'],
     ['finance','ria','product']].each do |role, case_id, audience|
      response = workspace(role, case_id, audience)
      assert_equal 'FORBIDDEN', response.dig('errors', 0, 'extensions', 'code'), "#{role} accessed #{case_id}/#{audience}: #{response.inspect}"
    end
    %w[advisor ria finance auditor].each do |role|
      result = command(role, 'BOOTSTRAP', {}, "unauthorized-#{role}")
      assert_equal 'FORBIDDEN', result.dig('errors', 0, 'code'), "#{role} bootstrapped"
    end
  end

  def test_idempotency_unknown_actions_and_fields_are_rejected
    first = command('operator', 'BOOTSTRAP', {}, 'independent-replay')
    assert_equal first, command('operator', 'BOOTSTRAP', {}, 'independent-replay')
    conflict = command('operator', 'BOOTSTRAP', {'unexpected'=>true}, 'independent-replay')
    assert conflict.fetch('errors').any?, 'Changed input with same key must fail'
    assert command('operator', 'BOOTSTRAP', {'unexpected'=>true}, 'independent-bad-field').fetch('errors').any?
    assert command('operator', 'DOES_NOT_EXIST', {}, 'independent-bad-action').fetch('errors').any?
  end

  def test_queries_do_not_create_evidence_or_run_pricing
    before = MedallionEvidence.count
    engine_methods = %i[evaluate evaluate_program].to_h { |name| [name, Economics::Engine.instance_method(name)] }
    engine_methods.each_key { |name| Economics::Engine.define_method(name) { |*| raise 'read invoked pricing engine' } }
    program_method = Economics::Program.instance_method(:run)
    Economics::Program.define_method(:run) { raise 'read invoked graph interpreter' }
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*args| writes << args.last[:sql] if args.last[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    begin
      [['operator','advisor','product'], ['operator','advisor','finance'], ['advisor','advisor','client']].each do |role, case_id, audience|
        response = workspace(role, case_id, audience, limit: 1)
        assert_nil response['errors'], response.inspect
        assert response.dig('data', 'disclosureWorkspace', 'available')
      end
      assert_equal before, MedallionEvidence.count
      assert_empty writes, 'Queries must not persist or bootstrap anything'
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
      engine_methods.each { |name, method| Economics::Engine.define_method(name, method) }
      Economics::Program.define_method(:run, program_method)
    end
  end
  def test_pagination_traverses_each_global_record_once
    first=workspace('operator','advisor','product',limit:100,offset:0).dig('data','disclosureWorkspace')
    assert first.fetch('available')
    total=first.dig('page','total')
    expected=[]
    (0...total).step(100) do |offset|
      page=workspace('operator','advisor','product',limit:100,offset:offset).dig('data','disclosureWorkspace')
      expected.concat(page.fetch('sections').flat_map { |section,items| items.map { |item| [section,item.fetch('id')] } })
    end
    actual=(0...total).flat_map do |offset|
      page=workspace('operator','advisor','product',limit:1,offset:offset).dig('data','disclosureWorkspace')
      page.fetch('sections').flat_map { |section,items| items.map { |item| [section,item.fetch('id')] } }
    end
    assert_equal total,actual.length
    assert_equal expected,actual
    assert_equal actual.length,actual.uniq.length
  end

end
