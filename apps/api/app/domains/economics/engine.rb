require "date"
require "time"
require_relative "error"
require_relative "canonical"

module Economics
  # Pure USD example policy. Inputs are frozen values; this class does no IO.
  class Engine
    VERSION = "economics-ruby/0.2.1"
    PROFILE = "demo-policy-profile-v1"
    DIMENSIONS = %w[customer_type product_type].freeze
    MAX_MINOR = 10**15

    def self.integer!(value, name, min: 0, max: MAX_MINOR)
      raise Error.new("INVALID_INTEGER", name) unless value.is_a?(Integer) && value.between?(min, max)
      value
    end

    def self.round(value)
      (value.negative? ? -1 : 1) * (value.abs + Rational(1, 2)).floor
    end

    def self.allocate(amount, weights)
      integer!(amount, "amount")
      if weights.empty? || weights.keys.any? { |key| !key.is_a?(String) || key.empty? } ||
          weights.values.any? { |w| !w.is_a?(Integer) || w < 0 } || weights.values.sum != 10_000
        raise Error.new("ALLOCATION_EXCEEDED", "Approved weights must sum to 10000")
      end
      exact = weights.transform_values { |w| Rational(amount * w, 10_000) }
      result = exact.transform_values(&:floor)
      order = exact.keys.sort_by { |key| [-(exact[key] - result[key]), key] }
      (amount - result.values.sum).times { |i| result[order[i]] += 1 }
      result
    end

    def self.round_components(exact)
      result = exact.transform_values(&:floor)
      target = round(exact.values.sum)
      order = exact.keys.sort_by { |key| [-(exact[key] - result[key]), key] }
      (target - result.values.sum).times { |i| result[order[i]] += 1 }
      result
    end

    def date!(value)
      raise ArgumentError unless value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
      Date.iso8601(value)
    rescue ArgumentError
      raise Error.new("INVALID_DATE", "Expected an ISO calendar date")
    end

    def time!(value)
      raise ArgumentError unless value.is_a?(String) && /(?:Z|[+-]\d{2}:\d{2})\z/.match?(value)
      Time.iso8601(value)
    rescue ArgumentError
      raise Error.new("INVALID_TIME", "Expected an ISO timestamp with timezone")
    end

    def scope!(row, context)
      %w[tenant_id entity_id currency].each do |key|
        unless context[key].is_a?(String) && !context[key].empty? && row[key] == context[key]
          raise Error.new("SCOPE_MISMATCH", "Mismatched #{key}")
        end
      end
      raise Error.new("UNIT_MISMATCH", "Demo supports USD only") unless row["currency"] == "USD"
    end

    def active?(row, date, cutoff)
      from, to = date!(row.fetch("valid_from")), date!(row.fetch("valid_to"))
      raise Error.new("INVALID_INTERVAL") unless from < to
      row["approved"] == true && from <= date!(date) && date!(date) < to &&
        time!(row.fetch("recorded_at")) <= time!(cutoff) &&
        (row["superseded_at"].nil? || time!(cutoff) < time!(row["superseded_at"]))
    end

    def unique!(rows, key = "id")
      values = rows.map { |r| r.fetch(key) }
      raise Error.new("DUPLICATE_SOURCE", "Duplicate or empty #{key}") if values.uniq.size != values.size || values.any? { |v| !v.is_a?(String) || v.empty? }
    end

    def validate_policy!(policy)
      scope!(policy, policy)
      raise Error.new("SYNTHETIC_ONLY") unless policy["synthetic"] == true
      raise Error.new("UNSUPPORTED_MECHANISM", "Unknown demo profile") unless policy["profile"] == PROFILE
      required, allowed = policy.fetch("required_dimensions"), policy.fetch("allowed_dimensions")
      unless required.is_a?(Array) && (required - DIMENSIONS).empty? && allowed.is_a?(Hash) &&
          (allowed.keys - DIMENSIONS).empty? && (required - allowed.keys).empty? &&
          allowed.values.all? { |v| v.is_a?(Array) && !v.empty? && v.all? { |x| x.is_a?(String) && !x.empty? } }
        raise Error.new("UNSUPPORTED_DIMENSION")
      end
      rules = policy.fetch("rates")
      raise Error.new("INCOMPLETE_POLICY") unless rules.is_a?(Array) && rules.any? && rules.size <= 100
      unique!(rules)
      rules.each do |r|
        scope!(r, policy)
        active?(r, r.fetch("valid_from"), r.fetch("recorded_at"))
        raise Error.new("UNSUPPORTED_MECHANISM") unless %w[standard promotion override].include?(r["kind"]) && r["component"] == "advisor_share"
        raise Error.new("UNRESOLVED_MAPPING") unless r["broker_id"].is_a?(String) && !r["broker_id"].empty?
        known_keys = %w[id tenant_id entity_id currency approved valid_from valid_to recorded_at superseded_at broker_id component kind selector numerator denominator priority]
        raise Error.new("UNSUPPORTED_MECHANISM", "Unsupported rate fields") unless (r.keys - known_keys).empty?
        selector = r.fetch("selector")
        unless selector.is_a?(Hash) && selector.all? { |k, v| allowed.fetch(k, []).include?(v) }
          raise Error.new("UNSUPPORTED_DIMENSION")
        end
        raise Error.new("INCOMPLETE_POLICY", "Required dimensions must cover every selector") unless (selector.keys - required).empty?
        raise Error.new("INVALID_SELECTOR") if (r["kind"] == "override") == selector.empty?
        n = self.class.integer!(r.fetch("numerator"), "numerator", max: 1_000_000)
        d = self.class.integer!(r.fetch("denominator"), "denominator", min: 1, max: 1_000_000)
        raise Error.new("INVALID_RATE") if n > d
        self.class.integer!(r["priority"], "priority", min: -1000, max: 1000) unless r["priority"].nil?
      end
      guarantees = policy.fetch("guarantees", [])
      unique!(guarantees)
      # Initial support: one earnings floor/ceiling per broker+month, not arbitrary ASTs.
      keys = guarantees.map { |g| [g["broker_id"], g["period"]] }
      raise Error.new("RULE_CONFLICT", "Overlapping guarantees require a supported stacking policy") unless keys.uniq.size == keys.size
      guarantees.each { |g| scope!(g, policy); guarantee(g, [], prior_minor: 0) }
      true
    rescue KeyError, TypeError, NoMethodError
      raise Error.new("VALIDATION_ERROR", "Incomplete policy contract")
    end

    def select_rate(rules, fact, date:, cutoff:)
      candidates = rules.select do |r|
        active?(r, date, cutoff) && r["broker_id"] == fact["broker_id"] && r["component"] == fact["component"] &&
          r.fetch("selector").all? { |k, v| fact.fetch("dimensions", {})[k] == v }
      end
      candidates.each { |r| scope!(r, fact) }
      overrides = candidates.select { |r| r["kind"] == "override" }
      pool = if overrides.any?
        overrides.reject do |a|
          overrides.any? { |b| a != b && (a["selector"].to_a - b["selector"].to_a).empty? && b["selector"].size > a["selector"].size }
        end
      else
        promotions = candidates.select { |r| r["kind"] == "promotion" }
        promotions.empty? ? candidates.select { |r| r["kind"] == "standard" } : promotions
      end
      raise Error.new("UNRESOLVED_MAPPING", "No approved active rate") if pool.empty?
      if pool.size > 1
        raise Error.new("RULE_CONFLICT", "Incomparable rules need explicit priorities") if pool.any? { |r| r["priority"].nil? }
        highest = pool.map { |r| r["priority"] }.max
        pool = pool.select { |r| r["priority"] == highest }
      end
      raise Error.new("RULE_CONFLICT", "Multiple equally ranked rules") unless pool.size == 1
      winner = pool.first
      { "rate" => Rational(winner.fetch("numerator"), winner.fetch("denominator")), "winner" => winner["id"],
        "candidates" => candidates.map { |r| r["id"] }.sort, "reason" => "#{winner['kind']} replacement; scope containment then explicit priority",
        "date" => date, "numerator" => winner["numerator"], "denominator" => winner["denominator"] }
    end

    def prepaid(obligation, grants, date:, cutoff:)
      amount = self.class.integer!(obligation.fetch("billing_minor"), "billing_minor")
      scope!(obligation, obligation)
      remaining, allocations = amount, []
      eligible = grants.select do |g|
        active?(g, date, cutoff) && g["payer"] == obligation["payer"] && g["payee"] == obligation["payee"] &&
          g["component"] == obligation["component"] && (g["customer_id"].nil? || g["customer_id"] == obligation["customer_id"])
      end.sort_by { |g| [g.fetch("priority"), g["valid_to"], g["id"]] }
      eligible.each do |g|
        scope!(g, obligation)
        raise Error.new("UNSUPPORTED_MECHANISM") unless g["mechanism"] == "monetary_credit"
        available = self.class.integer!(g.fetch("remaining_minor"), "remaining_minor")
        applied = [remaining, available].min
        next if applied.zero?
        allocations << { "grant_id" => g["id"], "applied_minor" => applied, "remaining_minor" => available - applied, "upfront_cash_minor" => g["upfront_cash_minor"] }
        remaining -= applied
      end
      { "billing_minor" => amount, "coverage_minor" => amount - remaining, "incremental_cash_minor" => remaining,
        "allocations" => allocations, "mode" => "projection_does_not_consume" }
    end

    def unit_prepaid(quantity:, unit_price_minor:, covered_units:)
      [quantity, unit_price_minor, covered_units].each { |n| self.class.integer!(n, "unit input") }
      covered = [quantity, covered_units].min
      { "billing_minor" => quantity * unit_price_minor, "coverage_minor" => covered * unit_price_minor,
        "incremental_cash_minor" => (quantity - covered) * unit_price_minor, "remaining_units" => covered_units - covered }
    end

    def guarantee(policy, rows, prior_minor: 0)
      unless %w[floor ceiling].include?(policy["kind"]) && policy["aggregation"] == "sum" && policy["metric"] == "earned_minor"
        raise Error.new("UNSUPPORTED_MECHANISM", "Only an exclusive broker monthly earnings floor/ceiling is supported")
      end
      raise Error.new("UNIT_MISMATCH") unless %w[metric_unit threshold_unit payment_unit].all? { |k| policy[k] == "USD_minor" }
      raise Error.new("UNSUPPORTED_MECHANISM") unless policy["stacking"] == "exclusive" && policy.fetch("filters", {}).empty? && policy["group"] == "broker"
      start_date = date!(policy.fetch("period").fetch("start"))
      end_date = date!(policy["period"].fetch("end_exclusive"))
      raise Error.new("INVALID_INTERVAL") unless start_date.day == 1 && end_date == start_date.next_month
      threshold = self.class.integer!(policy.fetch("threshold"), "threshold")
      self.class.integer!(prior_minor, "prior_minor", min: -MAX_MINOR)
      eligible = rows.select { |r| r["broker_id"] == policy["broker_id"] && start_date <= date!(r.fetch("economic_date")) && date!(r["economic_date"]) < end_date }
      eligible.each { |r| scope!(r, policy) }
      raise Error.new("INCOMPLETE_SOURCE") if eligible.any? { |r| r[policy["metric"]].nil? }
      measure = eligible.sum { |r| self.class.integer!(r[policy["metric"]], "metric") }
      amount = policy["kind"] == "floor" ? [threshold - measure, 0].max : -[measure - threshold, 0].max
      { "policy_id" => policy["id"], "broker_id" => policy["broker_id"], "measure" => measure,
        "obligation_minor" => amount, "delta_minor" => amount - prior_minor, "period" => policy["period"], "group" => "broker", "provisional" => true }
    end

    def relationship(assignments, customer_id:, date:, cutoff:)
      rows = assignments.select { |a| a["customer_id"] == customer_id && a["role"] == "compensation_recipient" && active?(a, date, cutoff) }
      raise Error.new("UNRESOLVED_MAPPING", "No approved compensation assignment") if rows.empty?
      rows.each { |r| self.class.integer!(r.fetch("weight_bps"), "weight_bps", max: 10_000) }
      if rows.map { |r| r["broker_id"] }.uniq.size != rows.size || rows.sum { |r| r["weight_bps"] } != 10_000
        raise Error.new("RULE_CONFLICT", "Unique recipients and weights totaling 10000 are required")
      end
      rows.sort_by { |a| a["id"] }
    end

    def evaluate(snapshot, policy, date:, cutoff:, allow_partial: false)
      date!(date); time!(cutoff)
      validate_policy!(policy); scope!(policy, snapshot)
      raise Error.new("SYNTHETIC_ONLY") unless snapshot["synthetic"] == true
      raise Error.new("INCOMPLETE_SOURCE") unless snapshot["complete"] == true && snapshot.fetch("facts").any?
      if snapshot["business_date"] != date || time!(snapshot.fetch("watermark")) < time!(snapshot.fetch("minimum_watermark"))
        raise Error.new("STALE_SOURCE")
      end
      raise Error.new("FUTURE_EVIDENCE") if time!(snapshot.fetch("recorded_at")) > time!(cutoff) || time!(snapshot["watermark"]) > time!(cutoff)
      %w[facts assignments grants].each { |k| unique!(snapshot.fetch(k, [])) }
      pool = Canonical.copy(snapshot.fetch("grants", []))
      pool.each { |g| scope!(g, snapshot); self.class.integer!(g.fetch("remaining_minor"), "remaining_minor") }
      lines, exceptions = [], []
      snapshot["facts"].sort_by { |f| f.fetch("id") }.each do |fact|
        begin
          scope!(fact, snapshot)
          raise Error.new("FUTURE_EVIDENCE") if %w[observed_at recorded_at].any? { |k| time!(fact.fetch(k)) > time!(cutoff) }
          raise Error.new("INVALID_DATE", "Fact must belong to the selected business date") unless fact["economic_date"] == date
          self.class.integer!(fact.fetch("revision"), "revision", min: 1)
          base = self.class.integer!(fact["eligible_minor"], "eligible_minor")
          dimensions = fact.fetch("dimensions", {})
          policy["required_dimensions"].each do |key|
            raise Error.new("MISSING_DIMENSION", "#{key} is not supplied") if dimensions[key].nil? || dimensions[key] == "unknown"
          end
          dimensions.each do |k, v|
            raise Error.new("UNMAPPED_DIMENSION", k) unless policy["allowed_dimensions"].fetch(k, []).include?(v)
          end
          assignments = relationship(snapshot["assignments"], customer_id: fact["customer_id"], date: date, cutoff: cutoff)
          assignments.each { |a| scope!(a, fact) }
          portions = self.class.allocate(base, assignments.to_h { |a| [a["broker_id"], a["weight_bps"]] })
          fact_pool = Canonical.copy(pool)
          rates = assignments.to_h do |assignment|
            broker = assignment.fetch("broker_id")
            [broker, select_rate(policy["rates"], fact.merge("broker_id" => broker), date: date, cutoff: cutoff)]
          end
          exact_earnings = assignments.to_h do |a|
            [a["broker_id"], Rational(base * a["weight_bps"], 10_000) * rates[a["broker_id"]]["rate"]]
          end
          earned_portions = self.class.round_components(exact_earnings)
          pending = assignments.map do |assignment|
            broker = assignment.fetch("broker_id")
            source = fact.merge("broker_id" => broker)
            rate = rates.fetch(broker)
            exact = exact_earnings.fetch(broker)
            earned = earned_portions.fetch(broker)
            obligation = source.merge("billing_minor" => earned, "payer" => "firm-demo", "payee" => broker)
            coverage = prepaid(obligation, fact_pool, date: date, cutoff: cutoff)
            coverage["allocations"].each { |a| fact_pool.find { |g| g["id"] == a["grant_id"] }["remaining_minor"] = a["remaining_minor"] }
            fact.slice("tenant_id", "entity_id", "currency", "economic_date", "service_id", "dimensions").merge(
              "id" => "#{fact['id']}:#{assignment['id']}", "customer_id" => fact["customer_id"], "broker_id" => broker,
              "source_id" => fact["id"], "source_revision" => fact["revision"], "relationship_id" => assignment["id"],
              "eligible_minor" => portions[broker], "earned_minor" => earned, "coverage" => coverage,
              "trace" => rate.reject { |key, _| key == "rate" }.merge("exact_earned_minor" => "#{exact.numerator}/#{exact.denominator}", "weight_bps" => assignment["weight_bps"], "rounding" => "half_up_per_source_line_then_largest_remainder"),
              "status" => "projected", "source_grain" => "customer_service_fee_observation")
          end
          lines.concat(pending)
          pool = fact_pool
        rescue Error => e
          exceptions << e.to_h.transform_keys(&:to_s).merge("source_id" => fact["id"], "owner" => "Demo finance operations", "next_action" => "Review source or approved policy before rerun")
        end
      end
      lines = [] if exceptions.any? && !allow_partial
      guarantees = exceptions.empty? ? policy.fetch("guarantees", []).map { |g| guarantee(g, lines) } : []
      { "status" => exceptions.empty? ? "completed" : (lines.empty? ? "blocked" : "partial"), "lines" => lines, "guarantees" => guarantees,
        "exceptions" => exceptions, "engine_version" => VERSION, "input_hash" => Canonical.hash(snapshot), "policy_hash" => Canonical.hash(policy),
        "business_date" => date, "knowledge_cutoff" => cutoff, "profile" => PROFILE, "synthetic" => true,
        "grant_closing_projection" => exceptions.any? && !allow_partial ? nil : pool.map { |g| g.slice("id", "remaining_minor") },
        "assumptions" => ["USD; service-date rate and attribution; half-open intervals; fictional approved dimensions.", "Fixed eligible fee observations, not a daily-AUM fee accrual or full-month forecast.", "Total entitlement rounds half-up once per source fee line; recipient cents use stable largest remainders of exact weighted shares. Allocated base cents are display-only.", "Coverage simulates a shared opening balance; no actual grant is spent.", "Guarantee is a provisional monthly true-up on supplied earnings only; no payment or accounting recognition."] }
    rescue KeyError, TypeError, NoMethodError
      raise Error.new("VALIDATION_ERROR", "Incomplete synthetic input contract")
    end
  end
end
