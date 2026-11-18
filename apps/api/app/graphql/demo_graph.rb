module DemoGraph
  def self.present(value)
    case value
    when Hash
      value.to_h { |k,v| [k, (v.is_a?(Integer) && k.to_s.match?(/(?:_minor|minor_units|threshold|measure)\z/)) ? v.to_s : present(v)] }
    when Array then value.map { |v| present(v) }
    else value
    end
  end

  def self.input_data(value)
    case value
    when Hash
      value.to_h { |k,v| [k, v.is_a?(String) && k.to_s.match?(/(?:_minor|minor_units|threshold)\z/) && v.match?(/\A-?\d{1,16}\z/) ? Integer(v, 10) : input_data(v)] }
    when Array then value.map { |v| input_data(v) }
    else value
    end
  end

  class DomainError < GraphQL::Schema::Object
    field :code, String, null: false
    field :message, String, null: false
    field :path, [String], null: false
  end
  class Money < GraphQL::Schema::Object
    field :minor_units, String, null: false
    field :currency, String, null: false
  end
  class Run < GraphQL::Schema::Object
    field :id, ID, null: false
    field :status, String, null: false
    field :policy_hash, String, null: false
    field :input_manifest_hash, String, null: false, hash_key: "input_hash"
    field :business_date, String, null: false
    field :knowledge_cutoff, String, null: false
    field :data, GraphQL::Types::JSON, null: false
    def data = DemoGraph.present(object)
  end
  class BrokerBook < GraphQL::Schema::Object
    field :id, ID, null: false
    field :name, String, null: false
    field :completeness, String, null: false
    field :earned, Money
    field :coverage, Money
    field :incremental_cash, Money
    field :customers, GraphQL::Types::JSON, null: false
  end
  class Command < GraphQL::Schema::Enum
    %w[PROJECT SAVE_POLICY IMPORT_SNAPSHOT REVIEW ACTIVATE MATCH LINK_INVOICE CONSUME_ENTITLEMENT REVERSE_ENTITLEMENT REVERSE_MATCH REVERSE_RECEIPT RECORD_INVOICE_APPLICATION REVERSE_INVOICE_APPLICATION RECORD_BANK_BATCH REVERSE_BANK_BATCH CLOSE_RECONCILIATION SAVE_TERMS_PROPOSAL COMPARE_TERMS_PROPOSAL REVIEW_TERMS_PROPOSAL SCHEDULE_TERMS_PROPOSAL].each { |name| value name }
  end
  class MedallionCommand < GraphQL::Schema::Enum
    %w[BOOTSTRAP INGEST_DELIVERY EVALUATE_CASE ASSIGN_POLICY SAVE_POLICY_VERSION COMPARE_POLICIES REVIEW_POLICY PUBLISH_POLICY SUBMIT_EVENT REVIEW_EVENT RECORD_PAYMENT REVERSE_SOURCE_RECEIPT REVERSE_FUNDING APPLY_PAYMENT REVERSE_PAYMENT_APPLICATION SEAL_STATEMENT LOCK_POSTING_PERIOD].each { |name| value name }
  end
  class FinanceCommand < GraphQL::Schema::Enum
    %w[FINANCE_BOOTSTRAP FINANCE_ASSOCIATE FINANCE_REVERSE FINANCE_MOCK_ACKNOWLEDGE].each { |name| value name }
  end
  class Payload < GraphQL::Schema::Object
    field :data, GraphQL::Types::JSON
    field :run, Run
    field :errors, [DomainError], null: false
  end
  class Query < GraphQL::Schema::Object
    field :disclosure_workspace, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
      argument :audience, String, required: true
      argument :page_changes, Boolean, required: false
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    def disclosure_workspace(case_id:, audience:, **options) = DemoGraph.present(DisclosureReadModel.new(context.fetch(:workbench)).view(case_id,audience:audience,**options))
    field :finance_workspace, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
    end
    field :audience_statement, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    field :audience_summary, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
    end
    field :audience_clients, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
      argument :search, String, required: false
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    field :audience_client, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
      argument :client_id, ID, required: true
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    field :lineage_records, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
      argument :search, String, required: false
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    field :lineage_record, GraphQL::Types::JSON, null: false do
      argument :case_id, ID, required: true
      argument :record_id, ID, required: true
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    field :entitlement_ledger, GraphQL::Types::JSON, null: false do
      argument :broker_id, ID, required: false
    end
    field :medallion_workspace, GraphQL::Types::JSON, null: false do
      argument :workspace, String, required: true
      argument :case_id, ID, required: true
      argument :run_id, ID, required: false
      argument :scenario_id, ID, required: false
      argument :limit, Integer, required: false
      argument :offset, Integer, required: false
    end
    field :product_workspace, GraphQL::Types::JSON, null: false do
      argument :workspace, String, required: true
      argument :broker_id, ID, required: false
      argument :business_date, String, required: false
    end
    field :reconciliation, GraphQL::Types::JSON, null: false do
      argument :period_start, String, required: true
      argument :period_end_exclusive, String, required: true
      argument :close_id, ID, required: false
    end
    field :workbench, GraphQL::Types::JSON, null: false
    field :collections, GraphQL::Types::JSON, null: false do
      argument :customer_id, ID, required: false
      argument :knowledge_cutoff, String, required: false
    end
    field :run, Run do
      argument :id, ID, required: true
    end
    field :review_packet, GraphQL::Types::JSON do
      argument :run_id, ID, required: true
    end
    field :broker_book, BrokerBook do
      argument :broker_id, ID, required: true
      argument :run_id, ID, required: false
    end
    def finance_workspace(case_id:) = DemoGraph.present(FinanceTiming.new(context.fetch(:workbench)).view(case_id))
    def audience_statement(case_id:, **options) = DemoGraph.present(AudienceReadModel.new(context.fetch(:workbench)).statement(case_id, **options))
    def audience_summary(case_id:) = DemoGraph.present(AudienceReadModel.new(context.fetch(:workbench)).summary(case_id))
    def audience_clients(case_id:, **options) = DemoGraph.present(AudienceReadModel.new(context.fetch(:workbench)).clients(case_id, **options))
    def audience_client(case_id:, client_id:, **options) = DemoGraph.present(AudienceReadModel.new(context.fetch(:workbench)).client(case_id, client_id, **options))
    def lineage_records(case_id:, **options) = DemoGraph.present(AudienceReadModel.new(context.fetch(:workbench)).lineage_records(case_id, **options))
    def lineage_record(case_id:, record_id:, **options) = DemoGraph.present(AudienceReadModel.new(context.fetch(:workbench)).lineage_record(case_id, record_id, **options))
    def service
      w=context.fetch(:workbench)
      raise Economics::Error.new("FORBIDDEN") if w.role=="ria"
      w
    end
    def medallion_workspace(workspace:, case_id:, run_id: nil, scenario_id: nil, limit: nil, offset: nil)
      DemoGraph.present(context.fetch(:workbench).medallion.view(workspace:workspace,case_id:case_id,run_id:run_id,scenario_id:scenario_id,limit:limit,offset:offset))
    end
    def entitlement_ledger(broker_id: nil) = DemoGraph.present(service.entitlement_ledger(broker_id))
    def product_workspace(workspace:, broker_id: nil, business_date: nil) = DemoGraph.present(service.product_workspace(workspace: workspace, broker_id: broker_id, business_date: business_date))
    def reconciliation(period_start:, period_end_exclusive:, close_id: nil) = DemoGraph.present(service.reconciliation(period_start: period_start, period_end_exclusive: period_end_exclusive, close_id: close_id))
    def workbench = DemoGraph.present(service.state)
    def collections(customer_id: nil, knowledge_cutoff: nil) = DemoGraph.present(service.collections(customer_id,cutoff:knowledge_cutoff))
    def run(id:) = service.run(id)
    def review_packet(run_id:) = DemoGraph.present(service.packet(run_id))
    def broker_book(broker_id:, run_id: nil)
      state = service.state
      broker = state["brokers"].find { |b| b["id"] == broker_id }
      raise Economics::Error.new("NOT_FOUND") unless broker
      run = run_id ? service.run(run_id) : state["latest_run"]
      lines = run ? run["lines"].select { |l| l["broker_id"] == broker_id } : []
      complete = run && run["status"] == "completed"
      money = ->(amount) { { minor_units: amount.to_s, currency: "USD" } }
      broker.merge("completeness" => run ? run["status"] : "not_run",
        "earned" => complete ? money.call(lines.sum { |l| l["earned_minor"] }) : nil,
        "coverage" => complete ? money.call(lines.sum { |l| l["coverage"]["coverage_minor"] }) : nil,
        "incremental_cash" => complete ? money.call(lines.sum { |l| l["coverage"]["incremental_cash_minor"] }) : nil,
        "customers" => DemoGraph.present(service.collections.select { |c| lines.any? { |l| l["customer_id"] == c["customer_id"] } }))
    end
  end
  class Mutation < GraphQL::Schema::Object
    field :disclosure_command, Payload, null: false do
      argument :action, String, required: true
      argument :input, GraphQL::Types::JSON, required: true
      argument :idempotency_key, String, required: true
    end
    def disclosure_command(action:,input:,idempotency_key:)
      methods={'BOOTSTRAP'=>:bootstrap,'SAVE_POLICY'=>:save_policy,'COMPARE_POLICY'=>:compare,'REVIEW_POLICY'=>:review,'PUBLISH_POLICY'=>:publish,'ASSIGN_POLICY'=>:assign,'EVALUATE'=>:evaluate}
      raise Economics::Error.new('VALIDATION_ERROR') unless input.is_a?(Hash) && methods.key?(action)
      result=DisclosureWorkbench.new(context.fetch(:workbench)).public_send(methods.fetch(action),DemoGraph.input_data(input),idempotency_key)
      {data:DemoGraph.present(result),errors:[]}
    rescue Economics::Error => e
      {data:nil,errors:[e.to_h]}
    rescue KeyError,ArgumentError,TypeError,NoMethodError
      {data:nil,errors:[{code:'VALIDATION_ERROR',message:'Invalid disclosure input',path:[]}]}
    end
    field :finance_command, Payload, null: false do
      argument :action, FinanceCommand, required: true
      argument :input, GraphQL::Types::JSON, required: true
      argument :idempotency_key, String, required: true
    end
    def finance_command(action:, input:, idempotency_key:)
      raise Economics::Error.new('VALIDATION_ERROR') unless input.is_a?(Hash)
      method={'FINANCE_BOOTSTRAP'=>:bootstrap,'FINANCE_ASSOCIATE'=>:associate,'FINANCE_REVERSE'=>:reverse,'FINANCE_MOCK_ACKNOWLEDGE'=>:mock_acknowledge}.fetch(action)
      result=FinanceTiming.new(context.fetch(:workbench)).public_send(method,DemoGraph.input_data(input),idempotency_key)
      {data:DemoGraph.present(result),errors:[]}
    rescue Economics::Error => e
      {data:nil,errors:[e.to_h]}
    rescue KeyError, ArgumentError, TypeError
      {data:nil,errors:[{code:'VALIDATION_ERROR',message:'Invalid Finance input',path:[]}]}
    end
    field :medallion_command, Payload, null: false do
      argument :action, MedallionCommand, required: true
      argument :input, GraphQL::Types::JSON, required: true
      argument :idempotency_key, String, required: true
    end
    def medallion_command(action:,input:,idempotency_key:)
      raise Economics::Error.new("VALIDATION_ERROR") unless input.is_a?(Hash)
      methods={"BOOTSTRAP"=>:bootstrap,"INGEST_DELIVERY"=>:ingest_delivery,"EVALUATE_CASE"=>:evaluate_case,"ASSIGN_POLICY"=>:assign_policy,"SAVE_POLICY_VERSION"=>:save_policy,
        "COMPARE_POLICIES"=>:compare,"REVIEW_POLICY"=>:review_policy,"PUBLISH_POLICY"=>:publish,
        "SUBMIT_EVENT"=>:submit_event,"REVIEW_EVENT"=>:review_event,"RECORD_PAYMENT"=>:record_payment,"REVERSE_SOURCE_RECEIPT"=>:reverse_source_receipt,"REVERSE_FUNDING"=>:reverse_funding,
        "APPLY_PAYMENT"=>:apply_payment,"REVERSE_PAYMENT_APPLICATION"=>:reverse_application,"SEAL_STATEMENT"=>:seal_statement,"LOCK_POSTING_PERIOD"=>:lock_posting_period}
      workbench=context.fetch(:workbench)
      result=DemoScope.transaction do
        value=workbench.medallion.public_send(methods.fetch(action),DemoGraph.input_data(input),idempotency_key)
        if input['case_id'].present? && (input['scenario_id'].nil? || input['scenario_id']=='baseline')
          AudienceReadModel.new(workbench).refresh!(input['case_id'])
        end
        value
      end
      {data:DemoGraph.present(result),errors:[]}
    rescue Economics::Error => e
      {data:nil,errors:[e.to_h]}
    rescue KeyError,ArgumentError,TypeError,NoMethodError
      {data:nil,errors:[{code:"VALIDATION_ERROR",message:"Invalid synthetic command input",path:[]}]}
    end
    field :workbench_command, Payload, null: false do
      argument :action, Command, required: true
      argument :input, GraphQL::Types::JSON, required: true
      argument :idempotency_key, String, required: true
    end
    def workbench_command(action:, input:, idempotency_key:)
      service = context.fetch(:workbench)
      raise Economics::Error.new("FORBIDDEN") if service.role=="ria"
      raise Economics::Error.new("VALIDATION_ERROR") unless input.is_a?(Hash)
      methods = { "PROJECT"=>:project, "SAVE_POLICY"=>:save_policy, "IMPORT_SNAPSHOT"=>:import_snapshot,
        "REVIEW"=>:review, "ACTIVATE"=>:activate, "MATCH"=>:match, "LINK_INVOICE"=>:link_invoice, "CONSUME_ENTITLEMENT"=>:consume_entitlement, "REVERSE_ENTITLEMENT"=>:reverse_entitlement, "REVERSE_MATCH"=>:reverse_match, "REVERSE_RECEIPT"=>:reverse_receipt,
        "RECORD_INVOICE_APPLICATION"=>:record_invoice_application, "REVERSE_INVOICE_APPLICATION"=>:reverse_invoice_application,
        "RECORD_BANK_BATCH"=>:record_bank_batch, "REVERSE_BANK_BATCH"=>:reverse_bank_batch, "CLOSE_RECONCILIATION"=>:close_reconciliation,
        "SAVE_TERMS_PROPOSAL"=>:save_terms_proposal, "COMPARE_TERMS_PROPOSAL"=>:compare_terms_proposal,
        "REVIEW_TERMS_PROPOSAL"=>:review_terms_proposal, "SCHEDULE_TERMS_PROPOSAL"=>:schedule_terms_proposal }
      result = service.public_send(methods.fetch(action), DemoGraph.input_data(input), idempotency_key)
      { data: DemoGraph.present(result), run: action == "PROJECT" ? result : nil, errors: [] }
    rescue Economics::Error => e
      { data: nil, run: nil, errors: [e.to_h] }
    rescue KeyError, ArgumentError, TypeError, NoMethodError
      { data: nil, run: nil, errors: [{ code: "VALIDATION_ERROR", message: "Invalid synthetic command input", path: [] }] }
    end
  end
end

