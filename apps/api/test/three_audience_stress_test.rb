# Runs only on the disposable synthetic Rails test database. Setup clears demo rows.
ENV['RAILS_ENV'] = 'test'
ENV['SYNTHETIC_DEMO'] = '1'
require_relative '../config/environment'
require_relative 'support/synthetic_reset'
require 'minitest/autorun'

class ThreeAudienceStressTest < Minitest::Test
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    Workbench.new.seed!
    @finance = Workbench.new(role: 'finance')
    %w[cedar maple].each do |name|
      charge = @finance.record!('charge', "charge-customer-#{name}")
      invoice = charge.slice('tenant_id', 'entity_id', 'currency', 'customer_id', 'amount_minor').merge(
        'id' => "stress-invoice-#{name}", 'status' => 'open', 'synthetic' => true
      )
      @finance.link_invoice({'charge_id' => charge['id'], 'invoice' => invoice}, "stress-link-#{name}")
    end
  end

  def application(amount, invoice: 'stress-invoice-cedar', receipt: 'receipt-cedar')
    {'invoice_id' => invoice, 'receipt_id' => receipt, 'minor_units' => amount,
     'business_date' => '2026-11-13', 'reason' => 'Fictional acceptance evidence'}
  end

  def ledger
    @finance.reconciliation(period_start: '2026-11-01', period_end_exclusive: '2026-12-01')
  end

  def test_partial_allocations_replay_and_reversal_conserve_cents
    first = application(12345)
    original = @finance.record_invoice_application(first, 'stress-first')
    assert_equal original, @finance.record_invoice_application(first, 'stress-first')
    assert_equal 'IDEMPOTENCY_CONFLICT', assert_raises(Economics::Error) {
      @finance.record_invoice_application(application(12346), 'stress-first')
    }.code
    second = @finance.record_invoice_application(application(23456), 'stress-second')
    invoice = ledger.fetch('invoices').find { |item| item['id'] == 'stress-invoice-cedar' }
    assert_equal 35801, invoice.fetch('applied_minor')
    assert_equal invoice.fetch('amount_minor') - 35801, invoice.fetch('open_minor')
    assert_nil ledger.dig('totals', 'recognized_revenue_minor')
    reversal = {'application_id' => original.fetch('id'), 'business_date' => '2026-11-13', 'reason' => 'Fictional correction'}
    reversed = @finance.reverse_invoice_application(reversal, 'stress-reverse')
    assert_equal reversed, @finance.reverse_invoice_application(reversal, 'stress-reverse')
    invoice = ledger.fetch('invoices').find { |item| item['id'] == 'stress-invoice-cedar' }
    assert_equal 23456, invoice.fetch('applied_minor')
    assert_equal invoice.fetch('amount_minor') - 23456, invoice.fetch('open_minor')
    assert_equal 1, invoice.fetch('applications').count { |item| item['id'] == second['id'] && item['status'] == 'active' }
    assert_equal 1, invoice.fetch('applications').count { |item| item['reversal_of_id'] == original['id'] }
    assert_nil ledger.dig('totals', 'recognized_revenue_minor')
  end

  def test_cross_customer_and_client_mutations_are_rejected_without_evidence
    assert_equal 'UNRESOLVED_MAPPING', assert_raises(Economics::Error) {
      @finance.record_invoice_application(application(1, invoice: 'stress-invoice-maple'), 'stress-wrong-customer')
    }.code
    %w[advisor ria operator].each do |role|
      actor = Workbench.new(role: role)
      assert_equal 'FORBIDDEN', assert_raises(Economics::Error) {
        actor.record_invoice_application(application(1), "stress-denied-#{role}")
      }.code
    end
    assert_empty @finance.records('invoice_application')
  end
end

class ThreeAudienceReadBoundaryTest < Minitest::Test
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    @operator = Workbench.new
    @operator.seed!
    @operator.medallion.bootstrap({}, 'stress-bootstrap')
  end

  def graphql(role, query, variables = {})
    WorkbenchSchema.execute(query, variables: variables, context: {workbench: Workbench.new(role: role)}).to_h
  end

  def test_every_lineage_page_is_retrievable_and_clients_are_denied_raw_records
    query = 'query($offset:Int!){lineageRecords(caseId:"ria",limit:7,offset:$offset)}'
    ids = []
    offset = 0
    loop do
      response = graphql('operator', query, {'offset' => offset})
      assert_nil response['errors']
      page = response.dig('data', 'lineageRecords')
      ids.concat(page.fetch('items').map { |row| row.fetch('id') })
      break if ids.length >= page.fetch('total')
      refute_empty page.fetch('items'), 'pagination ended before total'
      offset += page.fetch('items').length
    end
    assert_operator ids.length, :>, 7
    assert_equal ids.length, ids.uniq.length
    reader = AudienceReadModel.new(@operator)
    expected = MedallionEvidence.where(**@operator.scope, case_id: 'ria').pluck(:id).map(&:to_s)
    reader.native_relations('ria').each { |kind, relation| expected.concat(relation.pluck(:id).map { |id| "#{kind}:#{id}" }) }
    assert_equal expected.sort, ids.sort
    detail_query = 'query($id:ID!){lineageRecord(caseId:"ria",recordId:$id)}'
    detail = graphql('operator', detail_query, {'id' => ids.last})
    assert_equal ids.last, detail.dig('data', 'lineageRecord', 'record', 'id')
    %w[advisor ria].each do |role|
      [graphql(role, query, {'offset' => 0}), graphql(role, detail_query, {'id' => ids.last})].each do |response|
        assert_equal 'FORBIDDEN', response.dig('errors', 0, 'extensions', 'code')
      end
    end
  end

  def test_client_scope_cannot_be_changed_by_argument
    response = graphql('advisor', '{audienceSummary(caseId:"ria")}')
    assert_equal 'FORBIDDEN', response.dig('errors', 0, 'extensions', 'code')
    response = graphql('ria', '{audienceSummary(caseId:"advisor")}')
    assert_equal 'FORBIDDEN', response.dig('errors', 0, 'extensions', 'code')
  end
end

class ThreeAudienceFinanceLifecycleTest < Minitest::Test
  MUTATION = 'mutation($action:FinanceCommand!,$input:JSON!,$key:String!){financeCommand(action:$action,input:$input,idempotencyKey:$key){data errors{code message}}}'
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    operator = Workbench.new
    operator.seed!
    operator.medallion.bootstrap({}, 'finance-stress-medallion-bootstrap')
    result = command('operator', 'FINANCE_BOOTSTRAP', {}, 'finance-stress-bootstrap')
    assert_empty result.fetch('errors')
  end

  def command(role, action, input, key)
    response = WorkbenchSchema.execute(MUTATION, variables: {'action'=>action, 'input'=>input, 'key'=>key}, context: {workbench: Workbench.new(role: role)}).to_h
    assert_nil response['errors']
    response.dig('data', 'financeCommand')
  end

  def finance_view(role = 'finance')
    response = WorkbenchSchema.execute('{financeWorkspace(caseId:"ria")}', context: {workbench: Workbench.new(role: role)}).to_h
    assert_nil response['errors']
    response.dig('data', 'financeWorkspace')
  end

  def association(amount = '30000')
    {'payment_id'=>'finance-cash-900', 'invoice_id'=>'finance-invoice-advance', 'currency'=>'USD', 'amount_minor'=>amount, 'posting_period'=>'2027-01', 'reason'=>'Fictional stress evidence'}
  end

  def test_mock_confirmation_is_separate_from_local_cash_and_recognition
    before = finance_view
    assert_equal ['90000', '60000', '30000'], before.fetch('cash').values_at('amount_minor', 'associated_minor', 'unapplied_minor')
    recognition = before.fetch('recognition')
    outcomes = before.dig('cash', 'accounting_outcomes')
    result = command('finance', 'FINANCE_ASSOCIATE', association, 'finance-stress-associate')
    assert_empty result['errors']
    assert_equal false, result.dig('data', 'accounting_posted')
    assert_equal result, command('finance', 'FINANCE_ASSOCIATE', association, 'finance-stress-associate')
    changed = command('finance', 'FINANCE_ASSOCIATE', association('1'), 'finance-stress-associate')
    assert_equal 'IDEMPOTENCY_CONFLICT', changed.dig('errors', 0, 'code')
    local = finance_view
    assert_equal ['90000', '90000', '0'], local.fetch('cash').values_at('amount_minor', 'associated_minor', 'unapplied_minor')
    assert_equal outcomes, local.dig('cash', 'accounting_outcomes')
    assert_equal recognition, local['recognition']
    assert_equal 'ALLOCATION_EXCEEDED', command('finance', 'FINANCE_ASSOCIATE', association('1'), 'finance-stress-over').dig('errors', 0, 'code')
    id = result.dig('data', 'id')
    ack = command('finance', 'FINANCE_MOCK_ACKNOWLEDGE', {'application_id'=>id}, 'finance-stress-ack')
    assert_empty ack['errors']
    assert_equal '30000', ack.dig('data', 'ar_minor')
    assert_equal '40000', ack.dig('data', 'recognized_minor')
    acknowledged = finance_view
    assert_equal recognition, acknowledged['recognition']
    assert_equal 2, acknowledged.dig('cash', 'accounting_outcomes').length
    assert_equal 'finance-accounting-initial', acknowledged.dig('cash', 'accounting_outcomes').last['supersedes']
    reversal = command('finance', 'FINANCE_REVERSE', {'application_id'=>id, 'posting_period'=>'2027-01', 'reason'=>'Fictional correction'}, 'finance-stress-reverse')
    assert_empty reversal['errors']
    assert_equal false, reversal.dig('data', 'cash_refunded')
    after = finance_view
    assert_equal ['90000', '60000', '30000'], after.fetch('cash').values_at('amount_minor', 'associated_minor', 'unapplied_minor')
    assert_equal recognition, after['recognition']
    assert_equal 2, after.dig('cash', 'accounting_outcomes').length
    assert after.fetch('exceptions').any? { |e| e['id'] == 'accounting-correction-required' && e['application_id'] == id }, 'Acknowledged reversal must identify the accounting correction'
  end

  def test_scope_role_and_recognition_evidence_boundaries
    %w[advisor ria operator].each do |role|
      assert_equal 'FORBIDDEN', command(role, 'FINANCE_ASSOCIATE', association, "finance-stress-deny-#{role}").dig('errors', 0, 'code')
    end
    %w[payment_id invoice_id currency].each do |key|
      wrong = association.merge(key => 'wrong')
      assert_equal 'SCOPE_MISMATCH', command('finance', 'FINANCE_ASSOCIATE', wrong, "finance-stress-#{key}").dig('errors', 0, 'code')
    end
    assert_equal 'VALIDATION_ERROR', command('finance', 'FINANCE_ASSOCIATE', association.merge('entity_id'=>'wrong'), 'finance-stress-entity').dig('errors', 0, 'code')
    result = finance_view
    assert_equal '60000', result.dig('cash', 'associated_minor')
    records = result.dig('recognition', 'records')
    input = records.find { |r| r['record_id'] == 'recognition-input-advance-v1' }
    schedule = records.find { |r| r['record_id'] == 'schedule-advance-v1' }
    posting = records.find { |r| r['record_id'] == 'journal-advance-2027-01-v1' }
    assert_equal input['record_id'], schedule['input_id']
    assert_equal schedule['record_id'], posting['schedule_id']
    assert_equal 'posted', posting['status']
    assert_equal 'missing', result.dig('recognition', 'missing_outcome', 'status')
    assert_equal ['40000', '40000', '40000'], schedule.fetch('periods').map { |p| p['amount_minor'] }
    assert_equal '40000', posting['recognized_minor']
    run = MedallionEvidence.find_by!(case_id: 'ria', scenario_id: 'finance_timing_2027', kind: 'run', external_id: input['run_id'])
    assert_equal run.revision, input['run_revision']
    assert_equal run.payload_hash, input['run_hash']
    assert_equal 'finance-line-advance', input['invoice_line_id']
    assert_equal '120000', input['amount_minor']
    unbilled_input = records.find { |r| r['record_id'] == 'recognition-input-unbilled-v1' }
    first = records.find { |r| r['record_id'] == 'journal-unbilled-2027-01' }
    later = records.find { |r| r['record_id'] == 'journal-unbilled-reclass-2027-02' }
    [first, later].each do |item|
      assert_equal 'posted', item['status']
      assert_equal true, item['mocked']
    end
    assert_equal unbilled_input['record_id'], first['input_id']
    billed_input = records.find { |r| r['record_id'] == 'recognition-input-unbilled-billed-v2' }
    assert_equal billed_input['record_id'], later['input_id']
    assert_equal unbilled_input['record_id'], billed_input['supersedes']
    assert_nil unbilled_input['invoice_id']
    assert_equal 'finance-invoice-unbilled', billed_input['invoice_id']
    assert_equal ['10000', '10000'], first.values_at('recognized_minor', 'unbilled_minor')
    assert_equal ['0', '0', '10000'], later.values_at('recognized_minor', 'unbilled_minor', 'billed_reclassification_minor')
    wrong_case = WorkbenchSchema.execute('{financeWorkspace(caseId:"advisor")}', context: {workbench: Workbench.new(role: 'finance')}).to_h
    assert_nil wrong_case['errors']
    advisor = wrong_case.dig('data', 'financeWorkspace')
    assert_equal 'advisor', advisor.dig('context', 'case_id')
    assert_equal 'outbound_advisor', advisor.dig('cash', 'direction')
    assert_equal 'not_applicable', advisor.dig('recognition', 'missing_outcome', 'status')
    refute_includes advisor.to_s, 'finance-cash-900'
    %w[advisor ria].each do |role|
      denied = WorkbenchSchema.execute('{financeWorkspace(caseId:"ria")}', context: {workbench: Workbench.new(role: role)}).to_h
      assert_equal 'FORBIDDEN', denied.dig('errors', 0, 'extensions', 'code')
    end
  end
end

class ThreeAudiencePublishedReadTest < Minitest::Test
  def setup
    raise 'Disposable test database required' unless ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
    SyntheticReset.call
    @operator = Workbench.new
    @operator.seed!
    @operator.medallion.bootstrap({}, 'published-stress-bootstrap')
    @operator.medallion.evaluate_case({'case_id'=>'advisor','policy_id'=>'advisor-policy-v1','knowledge_cutoff'=>'2026-10-02T23:00:00Z'}, 'published-stress-run')
    @reader = AudienceReadModel.new(@operator)
    @reader.refresh!('advisor')
    @reader.refresh!('ria')
  end

  def test_reads_do_not_create_evidence_or_invoke_engine_or_full_view
    before = MedallionEvidence.count
    view_method = MedallionWorkbench.instance_method(:view)
    engine_method = Economics::Engine.instance_method(:evaluate)
    MedallionWorkbench.define_method(:view) { |**| raise 'full view invoked during read' }
    Economics::Engine.define_method(:evaluate) { |**| raise 'engine invoked during read' }
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*args| queries << args.last[:sql] }
    begin
      summary = @reader.summary('advisor')
      statement = @reader.statement('advisor', limit: 1, offset: 0)
      client = @reader.client('advisor', 'cedar', limit: 1, offset: 0)
      assert summary['run']
      assert_operator statement['total'], :>, 0
      assert_operator client['observation_total'], :>, 1
      assert_equal before, MedallionEvidence.count
      refute queries.any? { |sql| sql.match?(/SELECT\s+(?:"medallion_evidence"\.\*|\*)/i) && sql.include?('audience/v1') }, 'Published reads should select only needed JSON projections'
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
      MedallionWorkbench.define_method(:view, view_method)
      Economics::Engine.define_method(:evaluate, engine_method)
    end
    @reader.refresh!('advisor')
    assert_equal before, MedallionEvidence.count, 'Identical refresh must reuse publication'
  end

  def test_statement_and_client_observation_pages_are_complete_and_have_basis
    first = @reader.statement('advisor', limit: 1, offset: 0)
    pages = (0...first['total']).map { |offset| @reader.statement('advisor', limit: 1, offset: offset).fetch('lines').first }
    assert pages.all?
    assert_equal first['total'], pages.length
    assert pages.all? { |line| line['source_record_id'].present? && line.key?('basis') && line.key?('governing_terms') }
    client = @reader.client('advisor', 'cedar', limit: 7, offset: 0)
    observations = (0...client['observation_total']).step(7).flat_map { |offset| @reader.client('advisor', 'cedar', limit: 7, offset: offset).fetch('observations') }
    assert_equal client['observation_total'], observations.length
    assert_equal observations.length, observations.map { |item| item['id'] }.uniq.length
    assert observations.all? { |item| item['date'].present? && item['minor'].present? }
  end

  def test_assignment_dates_classify_current_scheduled_and_history
    assignment = @operator.medallion.source('advisor', 'baseline', 'assignment').order(schedule_version: :desc).first
    term = {'policy_id'=>assignment.payload.fetch('policy_id'), 'status'=>'applied'}
    start = assignment.starts_on
    finish = assignment.ends_on
    assert start && finish
    assert_equal 'scheduled', @reader.dated_terms('advisor', [term], (start - 1).iso8601).first['status']
    assert_equal 'current', @reader.dated_terms('advisor', [term], start.iso8601).first['status']
    assert_equal 'historical', @reader.dated_terms('advisor', [term], finish.iso8601).first['status']
  end

  def test_lineage_edges_page_without_omissions
    run = @operator.medallion.source('advisor', 'baseline', 'run').order(:id).last
    full = @reader.lineage_record('advisor', run.id.to_s, limit: 100, offset: 0)
    assert_operator full['edge_total'], :>, 1
    paged = (0...full['edge_total']).step(2).flat_map { |offset| @reader.lineage_record('advisor', run.id.to_s, limit: 2, offset: offset).fetch('edges') }
    assert_equal full['edge_total'], paged.length
    assert_equal full['edges'], paged if full['edge_total'] <= 100
  end

  def test_native_invoice_links_are_scoped_and_client_cannot_read_internal_records
    FinanceTiming.new(@operator).bootstrap({}, 'published-finance-bootstrap')
    model = AudienceReadModel.new(@operator)
    invoice = model.native_relations('ria').fetch('invoice').find_by!(external_id: 'finance-invoice-advance')
    record_id = "invoice:#{invoice.id}"
    detail = model.lineage_record('ria', record_id)
    assert_equal 'finance-invoice-advance', detail.dig('record', 'external_id')
    assert detail.fetch('edges').any? { |edge| edge.dig('input', 'kind') == 'invoice_line' }
    assert_equal 'NOT_FOUND', assert_raises(Economics::Error) { model.lineage_record('advisor', record_id) }.code
    assert_equal 'FORBIDDEN', assert_raises(Economics::Error) { AudienceReadModel.new(Workbench.new(role: 'ria')).lineage_record('ria', record_id) }.code
  end
end
