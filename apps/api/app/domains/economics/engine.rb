require "date"
require "time"
require_relative "error"
require_relative "canonical"
require_relative "program"

module Economics
  # Pure USD example policy. Inputs are frozen values; this class does no IO.
  class Engine
    VERSION = "economics-ruby/0.6.0"
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
      nodes = [{ 'id'=>'total', 'op'=>'literal', 'unit'=>'USD_minor', 'basis'=>'assessed', 'role'=>'intermediate', 'value'=>amount }]
      weights.keys.sort.each { |key| nodes << { 'id'=>"recipient:#{key}", 'op'=>'allocate', 'unit'=>'USD_minor', 'basis'=>'assessed', 'role'=>'terminal', 'input'=>'total', 'weights'=>weights.transform_values { |w| "#{w}/10000" }, 'recipient'=>key } }
      result = Program.new(policy: { 'version'=>'legacy-allocation/v1', 'nodes'=>nodes }, facts: {}).run
      result['terminal_outputs'].to_h { |d| [d['id'].delete_prefix('recipient:'), Rational(d['value']).to_i] }
    end

    def self.round_components(exact)
      return {} if exact.empty?
      ids = exact.keys.sort.to_h { |key| [key, "part:#{key}"] }
      nodes = ids.map { |key,id| { 'id'=>id, 'op'=>'literal', 'unit'=>'USD_minor', 'basis'=>'exact_accrual', 'role'=>'intermediate', 'value'=>"#{exact[key].numerator}/#{exact[key].denominator}" } }
      ids.each { |key,id| nodes << { 'id'=>"result:#{key}", 'op'=>'distribute', 'unit'=>'USD_minor', 'basis'=>'assessed', 'role'=>'terminal', 'inputs'=>ids.values, 'recipient'=>id } }
      result = Program.new(policy: { 'version'=>'legacy-distribution/v1', 'nodes'=>nodes }, facts: {}).run
      result['terminal_outputs'].to_h { |d| [d['id'].delete_prefix('result:'), Rational(d['value']).to_i] }
    end

    def evaluate_program(policy:, facts:, cutoff: nil, period: nil, policy_cutoff: nil)
      Program.new(policy: policy, facts: facts, cutoff: cutoff, period: period, policy_cutoff: policy_cutoff).run
    end

    def primitive_binary(op, left, right, basis: 'assessed', unit: 'USD_minor', right_unit: nil)
      number = ->(x) { r = Rational(x); "#{r.numerator}/#{r.denominator}" }
      nodes = [
        { 'id'=>'left', 'op'=>'literal', 'unit'=>unit, 'basis'=>basis, 'role'=>'intermediate', 'value'=>number.call(left) },
        { 'id'=>'right', 'op'=>'literal', 'unit'=>right_unit || unit, 'basis'=>right_unit == 'scalar' ? 'scalar' : basis, 'role'=>'intermediate', 'value'=>number.call(right) },
        { 'id'=>'result', 'op'=>op, 'unit'=>unit, 'basis'=>basis, 'role'=>'terminal' }.merge(%w[add min max].include?(op) ? { 'inputs'=>%w[left right] } : { 'left'=>'left', 'right'=>'right' })
      ]
      Rational(evaluate_program(policy: { 'version'=>'legacy-primitive/v1', 'nodes'=>nodes }, facts: {})['terminal_outputs'][0]['value'])
    end

    def primitive_sum(values)
      return 0 if values.empty?
      nodes = values.each_with_index.map { |value, i| { 'id'=>"part#{i}", 'op'=>'literal', 'unit'=>'USD_minor', 'basis'=>'assessed', 'role'=>'intermediate', 'value'=>value } }
      nodes << { 'id'=>'total', 'op'=>'add', 'unit'=>'USD_minor', 'basis'=>'assessed', 'role'=>'terminal', 'inputs'=>nodes.map { |n| n['id'] } }
      Rational(evaluate_program(policy: { 'version'=>'legacy-sum/v1', 'nodes'=>nodes }, facts: {})['terminal_outputs'][0]['value']).to_i
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
      guarantees.each { |g| scope!(g, policy); validate_guarantee!(g) }
      true
    rescue KeyError, TypeError, NoMethodError
      raise Error.new("VALIDATION_ERROR", "Incomplete policy contract")
    end

    # Translate both historical rate-record formats to the same selector.
    def select_rate(rules, fact, date:, cutoff:)
      commercial = rules.any? { |r| r.key?('starts_on') }
      date!(date); time!(cutoff)
      winner, candidates = Program.bind_legacy_rate(rules: rules, fact: fact, date: date, cutoff: cutoff, commercial: commercial)
      reason = commercial ? "#{winner['kind']} replacement" : "#{winner['kind']} replacement; scope containment then explicit priority"
      { 'rate'=>Rational(winner.fetch('numerator'),winner.fetch('denominator')), 'winner'=>winner['id'], 'candidates'=>candidates.map { |r| r['id'] }.sort,
        'reason'=>reason, 'date'=>date, 'numerator'=>winner['numerator'], 'denominator'=>winner['denominator'] }
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
        applied = primitive_binary('min', remaining, available).to_i
        next if applied.zero?
        allocations << { "grant_id" => g["id"], "applied_minor" => applied, "remaining_minor" => primitive_binary('subtract', available, applied).to_i, "upfront_cash_minor" => g["upfront_cash_minor"] }
        remaining = primitive_binary('subtract', remaining, applied).to_i
      end
      { "billing_minor" => amount, "coverage_minor" => primitive_binary('subtract', amount, remaining).to_i, "incremental_cash_minor" => remaining,
        "allocations" => allocations, "mode" => "projection_does_not_consume" }
    end

    def unit_prepaid(quantity:, unit_price_minor:, covered_units:)
      [quantity, unit_price_minor, covered_units].each { |n| self.class.integer!(n, "unit input") }
      covered = primitive_binary('min', quantity, covered_units, unit: 'count').to_i
      billing = primitive_binary('multiply', unit_price_minor, quantity, right_unit: 'scalar').to_i
      coverage = primitive_binary('multiply', unit_price_minor, covered, right_unit: 'scalar').to_i
      { "billing_minor" => billing, "coverage_minor" => coverage,
        "incremental_cash_minor" => primitive_binary('subtract', billing, coverage).to_i, "remaining_units" => primitive_binary('subtract', covered_units, covered, unit: 'count').to_i }
    end

    def validate_guarantee!(policy)
      unless %w[floor ceiling].include?(policy["kind"]) && policy["aggregation"] == "sum" && policy["metric"] == "earned_minor"
        raise Error.new("UNSUPPORTED_MECHANISM", "Only an exclusive broker monthly earnings floor/ceiling is supported")
      end
      raise Error.new("UNIT_MISMATCH") unless %w[metric_unit threshold_unit payment_unit].all? { |k| policy[k] == "USD_minor" }
      raise Error.new("UNSUPPORTED_MECHANISM") unless policy["stacking"] == "exclusive" && policy.fetch("filters", {}).empty? && policy["group"] == "broker"
      start_date = date!(policy.fetch("period").fetch("start"))
      end_date = date!(policy["period"].fetch("end_exclusive"))
      raise Error.new("INVALID_INTERVAL") unless start_date.day == 1 && end_date == start_date.next_month
      self.class.integer!(policy.fetch("threshold"), "threshold")
      true
    end

    def guarantee(policy, rows, prior_minor: 0)
      validate_guarantee!(policy)
      start_date = date!(policy.fetch("period").fetch("start"))
      end_date = date!(policy["period"].fetch("end_exclusive"))
      threshold = policy.fetch("threshold")
      self.class.integer!(prior_minor, "prior_minor", min: -MAX_MINOR)
      eligible = rows.select { |r| r["broker_id"] == policy["broker_id"] && start_date <= date!(r.fetch("economic_date")) && date!(r["economic_date"]) < end_date }
      eligible.each { |r| scope!(r, policy) }
      raise Error.new("INCOMPLETE_SOURCE") if eligible.any? { |r| r[policy["metric"]].nil? }
      measure = primitive_sum(eligible.map { |r| self.class.integer!(r[policy["metric"]], "metric") })
      difference = policy["kind"] == "floor" ? primitive_binary('subtract', threshold, measure) : primitive_binary('subtract', measure, threshold)
      magnitude = primitive_binary('max', difference, 0).to_i
      amount = policy["kind"] == "floor" ? magnitude : primitive_binary('subtract', 0, magnitude).to_i
      { "policy_id" => policy["id"], "broker_id" => policy["broker_id"], "measure" => measure,
        "obligation_minor" => amount, "delta_minor" => primitive_binary('subtract', amount, prior_minor).to_i, "period" => policy["period"], "group" => "broker", "provisional" => true }
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

    # Both public and legacy envelopes execute through the same graph interpreter.
    def validate(policy:)
      Program.validate!(policy)
      nodes = policy.fetch('nodes').to_h { |node| [node.fetch('id'),node] }
      edges = lambda do |node|
        case node['op']
        when 'add','min','max','distribute' then node.fetch('inputs')
        when 'subtract','net','multiply','accrue' then [node.fetch('left'),node.fetch('right')]
        when 'exact','assess','allocate' then [node.fetch('input')]
        when 'allocate_by' then [node.fetch('input')] + node.fetch('weights').values
        when 'bands' then [node.fetch('input')] + node.fetch('bands').map { |band| band.fetch('rate') }
        when 'select' then node.fetch('candidates').map { |candidate| candidate.fetch('value') }
        else []
        end
      end
      memo={}; directions = lambda do |id|
        return memo[id] if memo.key?(id)
        node=nodes.fetch(id)
        own = node['payer'] && node['payee'] && node['currency'] ? [[node['payer'],node['payee'],node['currency']]] : []
        children = node['op']=='net' ? [] : edges.call(node).flat_map { |ref| directions.call(ref) }
        memo[id]=(own+children).uniq
      end
      nodes.each_value do |node|
        if node['op']=='subtract'
          left=directions.call(node['left']); right=directions.call(node['right'])
          raise Error.new('NETTING_UNAUTHORIZED', 'Opposing obligations require the net operator') if left.any? { |a| right.any? { |b| a[0]==b[1] && a[1]==b[0] && a[2]==b[2] } }
        end
        next unless %w[terminal summary].include?(node['role']) && node['unit'].end_with?('_minor')
        raise Error.new('INVALID_OUTPUT_CONTRACT') unless %w[metric comparison evidence obligation net_balance].include?(node['output_class'])
        if %w[obligation net_balance].include?(node['output_class'])
          raise Error.new('INVALID_OUTPUT_CONTRACT') unless node['payer'].is_a?(String) && !node['payer'].empty? && node['payee'].is_a?(String) && !node['payee'].empty? && node['payer']!=node['payee'] && node['unit']=="#{node['currency']}_minor"
        end
        raise Error.new('NETTING_UNAUTHORIZED') if node['output_class']=='net_balance' && node['op']!='net'
      end
      Canonical.copy(policy)
    rescue KeyError, TypeError
      raise Error.new('INVALID_PROGRAM')
    end

    def evaluate(*args, **kwargs)
      return evaluate_legacy(*args, **kwargs) unless args.empty?
      bundle = kwargs.fetch(:policy_bundle)
      manifest = kwargs.fetch(:input_manifest)
      context = kwargs.fetch(:context)
      %w[tenant_id entity_id scenario service_start service_end_exclusive knowledge_cutoff].each { |k| raise Error.new('INVALID_CONTEXT', k) unless context[k].is_a?(String) && !context[k].empty? }
      raise Error.new('INVALID_INTERVAL') unless date!(context['service_start']) < date!(context['service_end_exclusive'])
      time!(context['knowledge_cutoff'])
      raise Error.new('UNAPPROVED_POLICY') unless bundle['approved'] == true || (context['hypothetical'] == true && bundle['approved'] == false)
      raise Error.new('INVALID_PROGRAM') unless bundle['policy_id'].is_a?(String) && !bundle['policy_id'].empty? && bundle['policy_hash'].is_a?(String) && bundle['policy_hash'].match?(/\A[0-9a-f]{64}\z/)
      policy = validate(policy: bundle.fetch('policy'))
      policy_cutoff = context.fetch('policy_knowledge_cutoff', context['knowledge_cutoff'])
      time!(policy_cutoff)
      raise Error.new('INVALID_CONTEXT') if time!(policy_cutoff) != time!(context['knowledge_cutoff']) && context['hypothetical'] != true
      facts = manifest.fetch('facts')
      raise Error.new('INVALID_PROGRAM') unless facts.is_a?(Hash)
      check_fact = lambda do |f, is_rate|
        raise Error.new('INVALID_SOURCE') unless f.is_a?(Hash) && f['id'].is_a?(String) && !f['id'].empty? && f['revision'].is_a?(Integer) && f['revision'] > 0
        raise Error.new('SCOPE_MISMATCH') unless f['tenant_id'] == context['tenant_id'] && f['entity_id'] == context['entity_id']
        time!(f.fetch('recorded_at'))
        if f['unit'].is_a?(String) && f['unit'].end_with?('_minor')
          raise Error.new('UNIT_MISMATCH') unless f['currency'].is_a?(String) && f['unit'] == "#{f['currency']}_minor"
        end
        if is_rate
          raise Error.new('UNAPPROVED_POLICY') unless f['approved'] == true
          starts = date!(f.fetch('valid_from')); ends = f.fetch('valid_to')
          raise Error.new('INVALID_INTERVAL') if ends && starts >= date!(ends)
        end
      end
      facts.each_value { |fact| check_fact.call(fact, false) }
      identities = facts.values.map { |fact| [fact['id'], fact['revision']] }
      raise Error.new('DUPLICATE_SOURCE', 'Duplicate fact identity and revision') unless identities.uniq.size == identities.size
      rates = policy.fetch('rate_rows', {})
      rates.each_value { |rate| check_fact.call(rate, true) }
      selected_keys = policy['nodes'].select { |n| n['op']=='select' }.flat_map { |n| n['candidates'].map { |c| c['value'] } }.filter_map { |id| policy['nodes'].find { |n| n['id']==id && n['op']=='fact' }&.fetch('key') }
      rates.each do |key, rate|
        next if selected_keys.include?(key)
        raise Error.new('RATE_NOT_EFFECTIVE') unless date!(rate['valid_from']) <= date!(context['service_start']) && (rate['valid_to'].nil? || date!(context['service_end_exclusive']) <= date!(rate['valid_to']))
      end
      eligible = facts.select { |_key, fact| fact['approved'] == true }
      result = evaluate_program(policy: policy, facts: eligible, cutoff: context['knowledge_cutoff'], policy_cutoff: policy_cutoff, period: context.slice('service_start', 'service_end_exclusive'))
      node_map = policy['nodes'].to_h { |node| [node['id'], node] }
      dependencies = lambda do |node|
        case node['op']
        when 'add', 'min', 'max', 'distribute' then node.fetch('inputs')
        when 'subtract', 'net', 'multiply', 'accrue' then [node.fetch('left'),node.fetch('right')]
        when 'exact', 'assess', 'allocate' then [node.fetch('input')]
        when 'allocate_by' then [node.fetch('input')] + node.fetch('weights').values
        when 'bands' then [node.fetch('input')] + node.fetch('bands').map { |band| band.fetch('rate') }
        when 'select' then node.fetch('candidates').map { |c| c.fetch('value') }
        else []
        end
      end
      source_cache = {}
      source_refs = lambda do |id, visited|
        return source_cache[id] if source_cache.key?(id)
        return [] if visited.include?(id)
        node = node_map.fetch(id); own = []
        keys = []
        keys << node['key'] if node['op']=='fact'
        keys << node['authority_fact'] if node['op']=='net'
        if node['op']=='sum_facts'
          binding=result['bindings'].find { |entry| entry['node']==id }
          keys.concat(binding.fetch('facts')) if binding
        end
        keys << node['interval_fact'] if node['interval_fact']
        if node['op']=='select'
          keys << node['date_fact'] if node['date_fact']
          keys.concat(node.fetch('candidates').filter_map { |candidate| candidate['signup_fact'] })
          keys.concat(node.fetch('candidates').flat_map { |candidate| candidate.fetch('matches',{}).keys })
        end
        keys.uniq.each do |key|
          fact = facts[key] || rates[key]
          if fact
            own << { 'id'=>fact['id'], 'revision'=>fact['revision'], 'key'=>key, 'kind'=>rates.key?(key) ? 'policy_rate' : 'source_fact' }
            own.concat(fact.fetch('evidence_refs', []).map { |ref| ref.is_a?(String) ? { 'id'=>ref, 'kind'=>'linked_evidence' } : ref })
          end
        end
        source_cache[id] = (own + dependencies.call(node).flat_map { |ref| source_refs.call(ref, visited + [id]) }).uniq
      end
      details = result['details'].map do |d|
        node = node_map.fetch(d['id'])
        exact = Rational(d['value'])
        date_fact = node['interval_fact'] && facts[node['interval_fact']]
        interval = if date_fact && date_fact['date']
          day = date!(date_fact['date']); { 'start'=>day.iso8601, 'end_exclusive'=>(day+1).iso8601 }
        else
          { 'start'=>context['service_start'], 'end_exclusive'=>context['service_end_exclusive'] }
        end
        d.merge('explanation'=>node['explanation'], 'output_class'=>node['output_class'], 'economic_key' => node['economic_key'] || d['id'], 'component' => node['component'] || d['id'], 'payer' => node['payer'], 'payee' => node['payee'], 'subject' => node['subject'], 'currency' => node['currency'] || (d['unit'].match?(/\A[A-Z]{3}_minor\z/) ? d['unit'][0,3] : nil), 'interval' => interval, 'netting_authority_ref'=>node['authority_fact'], 'dependency_refs'=>dependencies.call(node), 'binding_refs'=>result['bindings'].select { |binding| binding['node'] == d['id'] }.map { |binding| binding['node'] }, 'source_refs'=>source_refs.call(d['id'], []), 'exact_amount' => d['value'], 'assessed_minor' => d['basis'] == 'assessed' && exact.denominator == 1 ? exact.numerator : nil)
      end
      { 'schema_version' => 'medallion-evaluation/v1', 'engine_language_version' => 'primitive-graph/0.5', 'status' => result['status'], 'context' => Canonical.copy(context), 'input_manifest_hash' => Canonical.hash(manifest), 'policy_manifest_hash' => Canonical.hash(bundle), 'bindings' => result['bindings'], 'details' => details, 'outputs' => details.select { |d| %w[terminal summary].include?(d['role']) }.map { |d| { 'id' => d['id'], 'detail_refs' => [d['id']] } }, 'coverage' => [], 'exceptions' => result['exceptions'] }
    rescue KeyError, TypeError
      raise Error.new('INVALID_PROGRAM', 'Incomplete manifest interface')
    end

    def evaluate_legacy(snapshot, policy, date:, cutoff:, allow_partial: false)
      date!(date); time!(cutoff)
      validate_policy!(policy); scope!(policy, snapshot)
      policy.fetch('guarantees', []).each { |g| scope!(g, policy); validate_guarantee!(g) }
      raise Error.new('SYNTHETIC_ONLY') unless snapshot['synthetic'] == true
      raise Error.new('INCOMPLETE_SOURCE') unless snapshot['complete'] == true && snapshot.fetch('facts').any?
      raise Error.new('STALE_SOURCE') if snapshot['business_date'] != date || time!(snapshot.fetch('watermark')) < time!(snapshot.fetch('minimum_watermark'))
      raise Error.new('FUTURE_EVIDENCE') if time!(snapshot.fetch('recorded_at')) > time!(cutoff) || time!(snapshot['watermark']) > time!(cutoff)
      %w[facts assignments grants].each { |key| unique!(snapshot.fetch(key, [])) }
      grants = Canonical.copy(snapshot.fetch('grants', []))
      grants.each { |g| scope!(g, snapshot); self.class.integer!(g.fetch('remaining_minor'), 'remaining_minor') }
      nodes=[]; errors=[]; descriptors=[]; zero_id='zero'
      add = lambda do |id, op, basis: 'assessed', unit: 'USD_minor', **args|
        nodes << { 'id'=>id, 'op'=>op, 'basis'=>basis, 'unit'=>unit, 'role'=>'intermediate' }.merge(args.transform_keys(&:to_s))
        id
      end
      add.call(zero_id,'literal',value:'0')
      remaining = grants.each_with_index.to_h { |g,i| [g['id'], add.call("grant:#{i}:opening",'literal',value:g['remaining_minor'])] }
      snapshot['facts'].sort_by { |f| f.fetch('id') }.each_with_index do |fact,index|
        begin
          scope!(fact,snapshot)
          raise Error.new('FUTURE_EVIDENCE') if %w[observed_at recorded_at].any? { |k| time!(fact.fetch(k)) > time!(cutoff) }
          raise Error.new('INVALID_DATE', 'Fact must belong to the selected business date') unless fact['economic_date']==date
          self.class.integer!(fact.fetch('revision'),'revision',min:1)
          base=self.class.integer!(fact.fetch('eligible_minor'),'eligible_minor')
          dimensions=fact.fetch('dimensions',{})
          policy['required_dimensions'].each { |key| raise Error.new('MISSING_DIMENSION',"#{key} is not supplied") if dimensions[key].nil? || dimensions[key]=='unknown' }
          dimensions.each { |key,value| raise Error.new('UNMAPPED_DIMENSION',key) unless policy['allowed_dimensions'].fetch(key,[]).include?(value) }
          assignments=relationship(snapshot['assignments'],customer_id:fact['customer_id'],date:date,cutoff:cutoff)
          assignments.each { |a| scope!(a,fact) }
          rates=assignments.to_h { |a| [a['broker_id'],select_rate(policy['rates'],fact.merge('broker_id'=>a['broker_id']),date:date,cutoff:cutoff)] }
          eligible=assignments.to_h do |assignment|
            broker=assignment['broker_id']
            rows=grants.select do |g|
              active?(g,date,cutoff) && g['payer']=='firm-demo' && g['payee']==broker && g['component']==fact['component'] && (g['customer_id'].nil? || g['customer_id']==fact['customer_id'])
            end.sort_by { |g| [g.fetch('priority'),g['valid_to'],g['id']] }
            rows.each { |g| raise Error.new('UNSUPPORTED_MECHANISM') unless g['mechanism']=='monetary_credit' }
            [broker,rows]
          end
          prefix="f#{index}:"; base_id=add.call(prefix+'base','literal',value:base)
          exact_base=add.call(prefix+'exact_base','literal',basis:'exact_accrual',value:base)
          weights=assignments.to_h { |a| [a['broker_id'],"#{a['weight_bps']}/10000"] }
          exact_ids=assignments.to_h do |a|
            broker=a['broker_id']; key=prefix+'share:'+broker
            weight=add.call(key+':weight','literal',unit:'scalar',basis:'scalar',value:weights.fetch(broker))
            rate=add.call(key+':rate','literal',unit:'scalar',basis:'scalar',value:"#{rates[broker]['numerator']}/#{rates[broker]['denominator']}")
            part=add.call(key+':part','multiply',basis:'exact_accrual',left:exact_base,right:weight)
            [broker,add.call(key+':exact','multiply',basis:'exact_accrual',left:part,right:rate)]
          end
          assignments.each do |a|
            broker=a['broker_id']; key=prefix+'share:'+broker
            allocated=add.call(key+':base','allocate',input:base_id,weights:weights,recipient:broker)
            earned=add.call(key+':earned','distribute',inputs:exact_ids.values,recipient:exact_ids.fetch(broker))
            available=earned; applications=[]
            eligible.fetch(broker).each_with_index do |g,j|
              apply=add.call(key+":coverage:#{j}",'min',inputs:[available,remaining.fetch(g['id'])])
              grant_left=add.call(key+":grant_left:#{j}",'subtract',left:remaining.fetch(g['id']),right:apply)
              available=add.call(key+":payable:#{j}",'subtract',left:available,right:apply)
              remaining[g['id']]=grant_left
              applications << [g,apply,grant_left]
            end
            coverage=add.call(key+':coverage_total','subtract',left:earned,right:available)
            descriptors << {fact:fact,assignment:a,rate:rates.fetch(broker),base:allocated,exact:exact_ids.fetch(broker),earned:earned,coverage:coverage,payable:available,applications:applications}
          end
        rescue Error => e
          errors << e.to_h.transform_keys(&:to_s).merge('source_id'=>fact['id'],'owner'=>'Demo finance operations','next_action'=>'Review source or approved policy before rerun')
        end
      end
      guarantee_nodes=[]
      if errors.empty?
        policy.fetch('guarantees',[]).each_with_index do |g,index|
          start=date!(g.fetch('period').fetch('start')); finish=date!(g['period'].fetch('end_exclusive'))
          selected=descriptors.select { |d| d[:assignment]['broker_id']==g['broker_id'] && start<=date!(d[:fact]['economic_date']) && date!(d[:fact]['economic_date'])<finish }
          ids=selected.map { |d| d[:earned] }; ids=[zero_id] if ids.empty?
          measure=add.call("guarantee:#{index}:measure",'add',inputs:ids)
          threshold=add.call("guarantee:#{index}:threshold",'literal',value:g.fetch('threshold'))
          diff=add.call("guarantee:#{index}:difference",'subtract',left:g['kind']=='floor' ? threshold : measure,right:g['kind']=='floor' ? measure : threshold)
          magnitude=add.call("guarantee:#{index}:magnitude",'max',inputs:[diff,zero_id])
          amount=g['kind']=='floor' ? magnitude : add.call("guarantee:#{index}:amount",'subtract',left:zero_id,right:magnitude)
          guarantee_nodes << [g,measure,amount]
        end
      end
      nodes.each { |node| node['role']='terminal' }
      graph=Program.new(policy:{'version'=>'legacy-envelope/v1','nodes'=>nodes},facts:{}).run
      values=graph.fetch('details').to_h { |d| [d['id'],Rational(d['value'])] }
      lines=descriptors.map do |d|
        fact=d[:fact]; assignment=d[:assignment]; broker=assignment['broker_id']; exact=values.fetch(d[:exact]); earned=values.fetch(d[:earned]).to_i
        allocations=d[:applications].filter_map do |g,applied,left|
          amount=values.fetch(applied).to_i
          { 'grant_id'=>g['id'], 'applied_minor'=>amount, 'remaining_minor'=>values.fetch(left).to_i, 'upfront_cash_minor'=>g['upfront_cash_minor'] } if amount>0
        end
        coverage={ 'billing_minor'=>earned, 'coverage_minor'=>values.fetch(d[:coverage]).to_i, 'incremental_cash_minor'=>values.fetch(d[:payable]).to_i, 'allocations'=>allocations, 'mode'=>'projection_does_not_consume' }
        fact.slice('tenant_id','entity_id','currency','economic_date','service_id','dimensions').merge('id'=>"#{fact['id']}:#{assignment['id']}", 'customer_id'=>fact['customer_id'], 'broker_id'=>broker,
          'source_id'=>fact['id'], 'source_revision'=>fact['revision'], 'relationship_id'=>assignment['id'], 'eligible_minor'=>values.fetch(d[:base]).to_i, 'earned_minor'=>earned, 'coverage'=>coverage,
          'trace'=>d[:rate].reject { |key,_| key=='rate' }.merge('exact_earned_minor'=>"#{exact.numerator}/#{exact.denominator}", 'weight_bps'=>assignment['weight_bps'], 'rounding'=>'half_up_per_source_line_then_largest_remainder'),
          'status'=>'projected', 'source_grain'=>'customer_service_fee_observation')
      end
      lines=[] if errors.any? && !allow_partial
      guarantees=guarantee_nodes.map do |g,measure,amount|
        value=values.fetch(amount).to_i
        { 'policy_id'=>g['id'], 'broker_id'=>g['broker_id'], 'measure'=>values.fetch(measure).to_i, 'obligation_minor'=>value, 'delta_minor'=>value, 'period'=>g['period'], 'group'=>'broker', 'provisional'=>true }
      end
      closing=grants.map { |g| { 'id'=>g['id'], 'remaining_minor'=>values.fetch(remaining.fetch(g['id'])).to_i } }
      { 'status'=>errors.empty? ? 'completed' : (lines.empty? ? 'blocked' : 'partial'), 'lines'=>lines, 'guarantees'=>guarantees,
        'exceptions'=>errors, 'engine_version'=>VERSION, 'input_hash'=>Canonical.hash(snapshot), 'policy_hash'=>Canonical.hash(policy), 'business_date'=>date, 'knowledge_cutoff'=>cutoff, 'profile'=>PROFILE, 'synthetic'=>true,
        'grant_closing_projection'=>errors.any? && !allow_partial ? nil : closing,
        'assumptions'=>['USD; service-date rate and attribution; half-open intervals; fictional approved dimensions.', 'Fixed eligible fee observations, not a daily-AUM fee accrual or full-month forecast.', 'Total entitlement rounds half-up once per source fee line; recipient cents use stable largest remainders of exact weighted shares. Allocated base cents are display-only.', 'Coverage simulates a shared opening balance; no actual grant is spent.', 'Guarantee is a provisional monthly true-up on supplied earnings only; no payment or accounting recognition.'] }
    rescue KeyError, TypeError, NoMethodError
      raise Error.new('VALIDATION_ERROR', 'Incomplete synthetic input contract')
    end
  end
end
