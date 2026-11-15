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
  class Payload < GraphQL::Schema::Object
    field :data, GraphQL::Types::JSON
    field :run, Run
    field :errors, [DomainError], null: false
  end
  class Query < GraphQL::Schema::Object
    field :entitlement_ledger, GraphQL::Types::JSON, null: false do
      argument :broker_id, ID, required: false
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
    def service = context.fetch(:workbench)
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
    field :workbench_command, Payload, null: false do
      argument :action, Command, required: true
      argument :input, GraphQL::Types::JSON, required: true
      argument :idempotency_key, String, required: true
    end
    def workbench_command(action:, input:, idempotency_key:)
      service = context.fetch(:workbench)
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

