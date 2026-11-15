require_relative "../domains/economics/engine"
require "securerandom"

class Workbench
  TENANT = "demo-workspace"
  ENTITY = "entity-demo"
  CUTOFF = "2026-11-13T23:00:00Z"
  DATE = "2026-11-13"
  FIXTURES = Rails.root.join("../../fixtures/synthetic").expand_path
  ROLES = %w[operator finance legal advisor auditor].freeze
  attr_reader :role, :tenant, :entity

  def initialize(role: "operator", tenant: TENANT, entity: ENTITY)
    raise Economics::Error.new("FORBIDDEN") unless ROLES.include?(role)
    @role, @tenant, @entity = role, tenant, entity
  end

  def scope
    { tenant_id: tenant, entity_id: entity }
  end

  def records(kind)
    DemoRecord.where(**scope, kind: kind)
  end

  def current_records(kind, cutoff: nil)
    rows=records(kind)
    rows=rows.where('recorded_at <= ?',Economics::Engine.new.time!(cutoff)) if cutoff
    rows.select('DISTINCT ON (external_id) demo_records.*').order(:external_id,revision: :desc,id: :desc)
  end

  def product_workspace_service = ProductWorkspace.new(self)
  def product_workspace(workspace:, broker_id: nil, business_date: nil) = product_workspace_service.view(workspace: workspace, broker_id: broker_id, business_date: business_date)
  def save_terms_proposal(input, key) = product_workspace_service.save(input, key)
  def compare_terms_proposal(input, key) = product_workspace_service.compare(input, key)
  def review_terms_proposal(input, key) = product_workspace_service.review(input, key)
  def schedule_terms_proposal(input, key) = product_workspace_service.schedule(input, key)

  def reconciliation_book = ReconciliationBook.new(self)
  def reconciliation(period_start:, period_end_exclusive:, close_id: nil) = reconciliation_book.view(period_start: period_start, period_end_exclusive: period_end_exclusive, close_id: close_id)
  def record_invoice_application(input, key) = reconciliation_book.record_application(input, key)
  def reverse_invoice_application(input, key) = reconciliation_book.reverse_application(input, key)
  def record_bank_batch(input, key) = reconciliation_book.record_batch(input, key)
  def reverse_bank_batch(input, key) = reconciliation_book.reverse_batch(input, key)
  def close_reconciliation(input, key) = reconciliation_book.close(input, key)

  def cash_book = CashBook.new(self)
  def reverse_match(input,key) = cash_book.reverse_match(input,key)
  def reverse_receipt(input,key) = cash_book.reverse_receipt(input,key)

  def settlement_book = SettlementBook.new(self)
  def entitlement_ledger(broker_id = nil) = settlement_book.view(broker_id)
  def consume_entitlement(input,key) = settlement_book.consume(input,key)
  def reverse_entitlement(input,key) = settlement_book.reverse(input,key)

  def record!(kind, id)
    records(kind).where(external_id: id).order(revision: :desc).first!.payload
  rescue ActiveRecord::RecordNotFound
    raise Economics::Error.new("NOT_FOUND", "Record not found in the selected demo scope")
  end

  def write!(kind, payload, id: payload.fetch("id"), revision: 1, recorded_at: Time.current)
    canonical = Economics::Canonical.hash(payload)
    existing = records(kind).find_by(external_id: id, revision: revision)
    if existing
      raise Economics::Error.new("SOURCE_CONFLICT", "Same source ID and revision has different content") unless existing.payload_hash == canonical
      return existing.payload
    end
    DemoRecord.create!(**scope, kind: kind, external_id: id, revision: revision,
      synthetic: true, payload_hash: canonical, payload: payload, recorded_at: recorded_at)
    payload
  end

  def guard!(*allowed)
    raise Economics::Error.new("FORBIDDEN", "This simulated role cannot perform this action") unless allowed.include?(role)
  end

  def operate(action, input, key)
    unless key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
      raise Economics::Error.new("VALIDATION_ERROR", "A bounded idempotency key is required")
    end
    request_hash = Economics::Canonical.hash(input)
    DemoScope.transaction do
      DemoScope.where(**scope).lock.first! # One local serializable write lane per demo entity.
      prior = DemoOperation.find_by(**scope, actor_id: role, operation: action, idempotency_key: key)
      if prior
        raise Economics::Error.new("IDEMPOTENCY_CONFLICT", "This key was used with different inputs") unless prior.request_hash == request_hash
        next prior.result
      end
      result = yield
      DemoOperation.create!(**scope, actor_id: role, operation: action, idempotency_key: key,
        request_hash: request_hash, result: result, created_at: Time.current)
      result
    end
  end

  def seed!
    guard!("operator")
    DemoScope.find_or_create_by!(**scope)
    result=operate("seed", {}, "seed-v1") do
      directory = JSON.parse(File.read(FIXTURES.join("directory.json")))
      write!("directory", directory, id: "directory")
      policy = JSON.parse(File.read(FIXTURES.join("policy.json")))
      write!("policy", policy)
      snapshot = JSON.parse(File.read(FIXTURES.join("snapshot.json")))
      write!("snapshot", snapshot)
      snapshot["facts"].each { |fact| write!("source_fact", fact, id: "#{snapshot['source']}:#{fact['id']}", revision: fact.fetch("revision")) }
      %w[charges receipts].each do |kind|
        JSON.parse(File.read(FIXTURES.join("#{kind}.json"))).each { |p| write!(kind.singularize, p) }
      end
      { "seeded" => true, "synthetic" => true }
    end
    operate("seed_settlements",{},"seed-settlements-v1") do
      fixture=JSON.parse(File.read(FIXTURES.join("settlement.json")))
      fixture.fetch("grants").each { |g| write!("grant",g) }
      fixture.fetch("obligations").each { |o| write!("obligation",o) }
      {"seeded"=>true}
    end
    operate("seed_product_workspace", {}, "seed-product-workspace-v1") do
      product_workspace_service.bootstrap!
      BillingCatalog.new(self).seed!
      { "seeded"=>true, "synthetic"=>true }
    end
    result
  end

  def directory
    record!("directory", "directory")
  end

  def policy(id = nil)
    id ? record!("policy", id) : records("policy").order(:id).last!.payload
  end

  def snapshot(id = nil)
    id ? record!("snapshot", id) : records("snapshot").order(:id).last!.payload
  end

  def state
    d = directory
    brokers = d["brokers"]
    brokers = brokers.select { |b| b["id"] == "broker-alex" } if role == "advisor"
    p = policy
    latest_run = records("run").order(:id).last&.payload
    latest_run = redact_run(latest_run) if latest_run
    { "synthetic" => true, "role" => role, "scope" => scope.transform_keys(&:to_s), "business_date" => DATE,
      "knowledge_cutoff" => CUTOFF, "brokers" => brokers,
      "customers" => role == "advisor" ? d["customers"].select { |c| allowed_customer?(c["id"]) } : d["customers"],
      "policy" => role == "advisor" ? nil : p,
      "snapshot" => role == "advisor" ? nil : snapshot,
      "latest_run" => latest_run, "policy_hash" => role == "advisor" ? nil : Economics::Canonical.hash(p),
      "approvals" => role == "advisor" ? [] : records("review").order(:id).last(20).map(&:payload),
      "active_policy_id" => records("activation").order(:id).last&.payload&.fetch("policy_id"),
      "runs" => records("run").order(id: :desc).limit(20).map { |r| redact_run(r.payload).slice("id", "status", "policy_hash", "input_hash", "business_date", "knowledge_cutoff") },
      "source_history" => role == "advisor" ? [] : records("snapshot").order(id: :desc).limit(20).map { |r| r.payload.slice("id", "business_date", "watermark", "complete", "source") } }
  end

  def allowed_customer?(id)
    return true unless role == "advisor"
    Economics::Engine.new.relationship(snapshot["assignments"], customer_id: id, date: DATE, cutoff: CUTOFF).any? { |a| a["broker_id"] == "broker-alex" }
  rescue Economics::Error
    false
  end

  def redact_run(run)
    return run if role != "advisor"
    run.slice("id", "status", "business_date", "knowledge_cutoff", "engine_version", "profile", "synthetic", "assumptions", "input_hash", "policy_hash").merge(
      "lines" => run.fetch("lines").select { |l| l["broker_id"] == "broker-alex" },
      "guarantees" => run.fetch("guarantees", []).select { |g| g["broker_id"] == "broker-alex" }, "exceptions" => [])
  end

  def project(input, key)
    guard!("operator", "finance")
    # Resolve defaults before hashing, so a replay can never substitute a new source/policy.
    raise Economics::Error.new("VALIDATION_ERROR", "Pin policy_id and snapshot_id") unless input["policy_id"] && input["snapshot_id"]
    operate("project", input, key) do
      p, s = policy(input["policy_id"]), snapshot(input["snapshot_id"])
      date = input.fetch("business_date", DATE); cutoff = input.fetch("knowledge_cutoff", CUTOFF)
      s=settlement_book.projection_snapshot(s,cutoff:cutoff)
      result = Economics::Engine.new.evaluate(s, p, date: date, cutoff: cutoff)
      result["implementation_hash"] = Digest::SHA256.file(Rails.root.join("app/domains/economics/engine.rb")).hexdigest
      result.merge!("id" => "run-#{SecureRandom.uuid}", "policy_id" => p["id"], "snapshot_id" => s["id"], "inputs" => { "snapshot" => s, "policy" => p })
      write!("run", result)
    end
  end

  def save_policy(input, key)
    guard!("operator")
    operate("save_policy", input, key) do
      p = Economics::Canonical.copy(input.fetch("policy"))
      raise Economics::Error.new("HASH_CHANGED", "Policy was edited in another view") unless input["expected_hash"] == Economics::Canonical.hash(policy)
      Economics::Engine.new.scope!(p, policy)
      Economics::Engine.new.validate_policy!(p)
      # Reject potential same-rank conflicts on controlled dimension combinations and boundaries.
      dimensions = p.fetch("allowed_dimensions")
      dates = p["rates"].flat_map { |r| [r["valid_from"], (Date.iso8601(r["valid_to"]) - 1).iso8601] }.uniq
      directory["brokers"].each do |b|
        dimensions.fetch("customer_type").product(dimensions.fetch("product_type")).each do |customer_type, product_type|
          dates.each do |date|
            fact = p.slice("tenant_id", "entity_id", "currency").merge("broker_id" => b["id"], "component" => "advisor_share", "dimensions" => { "customer_type" => customer_type, "product_type" => product_type })
            begin
              Economics::Engine.new.select_rate(p["rates"], fact, date: date, cutoff: "9999-01-01T00:00:00Z")
            rescue Economics::Error => e
              raise if e.code != "UNRESOLVED_MAPPING"
            end
          end
        end
      end
      valid_brokers = directory["brokers"].map { |b| b["id"] }
      raise Economics::Error.new("UNRESOLVED_MAPPING", "Unknown guarantee broker") unless p.fetch("guarantees", []).all? { |g| valid_brokers.include?(g["broker_id"]) }
      p["version"] = records("policy").count + 1
      p["id"] = "policy-v#{p['version']}"
      p["status"] = "draft"
      write!("policy", p)
    end
  end

  def review(input, key)
    guard!("finance", "legal")
    operate("review", input, key) do
      p = policy(input.fetch("policy_id"))
      raise Economics::Error.new("HASH_CHANGED") unless input["policy_hash"] == Economics::Canonical.hash(p)
      review_snapshot=settlement_book.projection_snapshot(snapshot,cutoff:CUTOFF)
      examples = Economics::Engine.new.evaluate(review_snapshot, p, date: DATE, cutoff: CUTOFF)
      raise Economics::Error.new("BLOCKED_REVIEW", "Resolve calculation exceptions first") unless examples["status"] == "completed"
      write!("review", { "id" => "review-#{SecureRandom.uuid}", "policy_id" => p["id"], "policy_hash" => input["policy_hash"],
        "document_hash" => Economics::Canonical.hash(p["clause_text"]), "examples_hash" => Economics::Canonical.hash(examples), "snapshot_hash" => Economics::Canonical.hash(review_snapshot),
        "role" => role, "actor" => "simulated-#{role}", "decision" => "approved_for_demo", "contract_executed" => false })
    end
  end

  def activate(input, key)
    guard!("operator")
    operate("activate", input, key) do
      p = policy(input.fetch("policy_id")); hash = Economics::Canonical.hash(p)
      raise Economics::Error.new("HASH_CHANGED") unless input["policy_hash"] == hash
      s = settlement_book.projection_snapshot(snapshot,cutoff:CUTOFF)
      examples_hash = Economics::Canonical.hash(Economics::Engine.new.evaluate(s,p,date:DATE,cutoff:CUTOFF))
      approvals = records("review").map(&:payload).select { |r| r["policy_hash"] == hash && r["snapshot_hash"] == Economics::Canonical.hash(s) && r["examples_hash"] == examples_hash }
      raise Economics::Error.new("REVIEW_REQUIRED", "Legal and Finance must approve the current policy and examples") unless (%w[finance legal] - approvals.map { |r| r["role"] }).empty?
      write!("activation", { "id" => "activation-#{SecureRandom.uuid}", "policy_id" => p["id"], "policy_hash" => hash, "review_ids" => approvals.map { |a| a["id"] }, "contract_executed" => false })
    end
  end

  def import_snapshot(input, key)
    guard!("operator")
    operate("import_snapshot", input, key) do
      s = input.fetch("snapshot")
      Economics::Engine.new.scope!(s, policy)
      raise Economics::Error.new("SYNTHETIC_ONLY") unless s["synthetic"] == true && s["source"] == "synthetic-internal-v1"
      raise Economics::Error.new("VALIDATION_ERROR", "Snapshot must be bounded with explicit source records") unless s["facts"].is_a?(Array) && s["facts"].size.between?(1,1000)
      known_customers = directory["customers"].map { |c| c["id"] }
      known_brokers = directory["brokers"].map { |b| b["id"] }
      unless s["facts"].all? { |f| known_customers.include?(f["customer_id"]) } && s.fetch("assignments").all? { |a| known_customers.include?(a["customer_id"]) && known_brokers.include?(a["broker_id"]) }
        raise Economics::Error.new("UNRESOLVED_MAPPING", "Use the supplied fictional directory; arbitrary customer identities are not accepted")
      end
      # Validate structure/quality before accepting; retain row-level blocked outcomes.
      result = Economics::Engine.new.evaluate(s, policy, date: s.fetch("business_date"), cutoff: input.fetch("knowledge_cutoff", CUTOFF))
      existing = records("snapshot").find_by(external_id: s.fetch("id"))
      if existing && existing.payload_hash != Economics::Canonical.hash(s)
        next write!("quarantine", { "id" => "quarantine-#{SecureRandom.uuid}", "source_id" => s["id"], "code" => "SOURCE_CONFLICT", "payload_hash" => Economics::Canonical.hash(s), "owner" => "Demo data owner", "next_action" => "Supply a new source revision; accepted history is preserved" })
      end
      conflict = s["facts"].find do |fact|
        previous = records("source_fact").find_by(external_id: "#{s['source']}:#{fact['id']}", revision: fact.fetch("revision"))
        previous && previous.payload_hash != Economics::Canonical.hash(fact)
      end
      if conflict
        next write!("quarantine", { "id" => "quarantine-#{SecureRandom.uuid}", "source_id" => conflict["id"], "code" => "SOURCE_CONFLICT", "payload_hash" => Economics::Canonical.hash(s), "owner" => "Demo data owner", "next_action" => "A different batch cannot change an accepted record at the same source revision" })
      end
      s["facts"].each { |fact| write!("source_fact", fact, id: "#{s['source']}:#{fact['id']}", revision: fact.fetch("revision")) }
      write!("snapshot", s)
      { "id" => s["id"], "quality" => result["status"], "exceptions" => result["exceptions"] }
    end
  end

  def match(input, key)
    guard!("operator", "finance")
    operate("match", input, key) do
      charge, receipt = record!("charge", input.fetch("charge_id")), record!("receipt", input.fetch("receipt_id"))
      unless charge["status"] == "approved_for_collection" && receipt["status"] == "verified_cash" && charge["customer_id"] == receipt["customer_id"]
        raise Economics::Error.new("UNRESOLVED_MAPPING", "Requires an approved charge and verified customer-attributed cash")
      end
      [charge, receipt].each { |r| Economics::Engine.new.scope!(r, policy) }
      amount = Economics::Engine.integer!(input["minor_units"], "minor_units", min: 1)
      used_receipt = cash_book.active_matches.where(source_id: receipt["id"]).sum(:minor_units)
      used_charge = cash_book.active_matches.where(target_id: charge["id"]).sum(:minor_units)
      if amount + used_receipt > receipt["amount_minor"] || amount + used_charge > charge["amount_minor"]
        raise Economics::Error.new("ALLOCATION_EXCEEDED", "Match exceeds eligible cash or charge remaining")
      end
      a = DemoAllocation.create!(**scope, kind: "operational_match", source_id: receipt["id"], target_id: charge["id"], currency: "USD", minor_units: amount, idempotency_key: key, created_at: Time.current)
      { "id" => a.id.to_s, "status" => "matched_to_charge_pending_invoice", "minor_units" => amount, "invoice_payment_created" => false }
    end
  end

  def link_invoice(input, key)
    guard!("finance")
    operate("link_invoice", input, key) do
      c = record!("charge", input.fetch("charge_id"))
      invoice = input.fetch("invoice")
      Economics::Engine.new.scope!(invoice, c)
      unless invoice["synthetic"] == true && invoice["customer_id"] == c["customer_id"] && invoice["status"] == "open" && invoice["amount_minor"] == c["amount_minor"]
        raise Economics::Error.new("INVOICE_VARIANCE", "Only matching synthetic invoice evidence can link; a variance requires review")
      end
      # This action links evidence, and does not create/apply a receipt in Campfire.
      same_charge = records("invoice").map(&:payload).find { |i| i["charge_id"] == c["id"] }
      if same_charge && same_charge["id"] != invoice["id"]
        raise Economics::Error.new("SOURCE_CONFLICT", "This initial model supports one invoice per charge; split invoices require an extension")
      end
      prior = records("invoice").find_by(external_id: invoice.fetch("id"))
      if prior && prior.payload["charge_id"] != c["id"]
        raise Economics::Error.new("SOURCE_CONFLICT", "Invoice already belongs to a different charge")
      end
      write!("invoice", invoice.merge("charge_id" => c["id"], "application_minor" => nil, "source" => "offline_fixture_only"))
    end
  end

  def collections(customer_id = nil, cutoff: nil)
    charges = current_records("charge",cutoff:cutoff).map(&:payload)
    charges = charges.select { |c| c["customer_id"] == customer_id } if customer_id
    charges = charges.select { |c| allowed_customer?(c["customer_id"]) }
    charges.map do |c|
      matched = cash_book.active_matches(cutoff:cutoff).where(target_id:c["id"]).sum(:minor_units)
      receipts = cash_book.current_receipts(cutoff:cutoff).map(&:payload).select { |r| r["customer_id"] == c["customer_id"] }.map do |r|
        unless %w[verified_cash reversed].include?(r["status"])
          raise Economics::Error.new("UNRESOLVED_MAPPING", "Unknown receipt status requires review")
        end
        used = cash_book.active_matches(cutoff:cutoff).where(source_id:r["id"]).sum(:minor_units)
        available=r["status"]=="verified_cash" ? r["amount_minor"]-used : 0
        r.merge("unapplied_minor"=>available,"suggested_match_minor"=>[available,c["amount_minor"]-matched].min)
      end
      invoice = current_records("invoice",cutoff:cutoff).map(&:payload).find { |i| i["charge_id"] == c["id"] }
      begin
        brokers = Economics::Engine.new.relationship(snapshot["assignments"],customer_id:c["customer_id"],date:DATE,cutoff:cutoff || CUTOFF).map { |a| a["broker_id"] }
        attribution = "resolved"
      rescue Economics::Error
        brokers, attribution = [], "unresolved"
      end
      c.merge("broker_ids"=>brokers,"attribution_status"=>attribution,"operational_matched_minor"=>matched,"unmatched_charge_minor"=>c["amount_minor"]-matched,
        "observed_cash_minor"=>receipts.empty? ? nil : receipts.select { |r| r["status"]=="verified_cash" }.sum { |r| r["amount_minor"] },
        "reversed_receipt_minor"=>receipts.select { |r| r["status"]=="reversed" }.sum { |r| r["amount_minor"] },
        "receipts"=>receipts,"matches"=>cash_book.history(c["id"],cutoff:cutoff),"knowledge_cutoff"=>cutoff,
        "invoice"=>invoice,"invoice_applied_minor"=>nil,"bank_settled_minor"=>nil,"recognized_revenue_minor"=>nil,"ar_minor"=>nil,
        "status"=>invoice ? "invoice_linked_application_unknown" : "preinvoice",
        "unknown_reason"=>"Campfire application, bank settlement and recognition evidence are not supplied")
    end
  end

  def run(id)
    redact_run(record!("run", id))
  end

  def packet(id)
    guard!("operator", "finance", "legal", "auditor")
    r = record!("run", id)
    p = r.fetch("inputs").fetch("policy")
    { "title" => "Draft commercial review packet", "synthetic" => true, "contract_executed" => false,
      "run_id" => r["id"], "policy_hash" => r["policy_hash"], "input_hash" => r["input_hash"], "profile" => r["profile"],
      "draft_language" => p["clause_text"], "structured_terms" => p, "examples" => r.except("inputs"),
      "unresolved" => ["Illustrative terms only; not an actual Savvy contract.", "No legal signature, company approval, Campfire connection or accounting assessment.", "Guarantees measure supplied snapshot earnings, not unseen remaining monthly activity."],
      "review_note" => "Review wording AND structured terms; neither is generated legal advice. Approval binds the full policy and examples." }
  end
end
