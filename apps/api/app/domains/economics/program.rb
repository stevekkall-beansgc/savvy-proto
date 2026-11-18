require 'date'
require 'time'
require_relative 'error'

module Economics
  # A bounded, declarative graph. Money is denominated in minor units and all
  # calculations remain rational until an explicit assessment node.
  class Program
    LIMIT = 1000
    ROLES = %w[intermediate terminal summary].freeze
    BASES = %w[exact_accrual assessed source_reported scalar].freeze
    Value = Struct.new(:amount, :unit, :basis, keyword_init: true)

    # Shared replacement-selection primitive. Adapters provide normalized
    # temporal candidates and the policy's explicit precedence vocabulary.
    def self.choose_rate(candidates:, precedence:, containment: [])
      raise Error.new('UNRESOLVED_MAPPING', 'No approved active rate') if candidates.empty?
      selected_kind = precedence.find { |kind| candidates.any? { |c| c.fetch('kind') == kind } }
      raise Error.new('UNRESOLVED_MAPPING') unless selected_kind
      pool = candidates.select { |c| c['kind'] == selected_kind }
      if containment.include?(selected_kind)
        pool = pool.reject do |a|
          pool.any? { |b| a != b && (a.fetch('selector').to_a - b.fetch('selector').to_a).empty? && b.fetch('selector').size > a.fetch('selector').size }
        end
      end
      if pool.size > 1
        raise Error.new('RULE_CONFLICT', 'Incomparable rules need explicit priorities') if pool.any? { |r| r['priority'].nil? }
        highest = pool.map { |r| r['priority'] }.max
        pool = pool.select { |r| r['priority'] == highest }
      end
      raise Error.new('RULE_CONFLICT', 'Multiple equally ranked rules') unless pool.one?
      pool.first
    end

    def self.bind_legacy_rate(rules:, fact:, date:, cutoff:, commercial:)
      day = Date.iso8601(date)
      known = Time.iso8601(cutoff)
      candidates = rules.select do |r|
        next false unless r['broker_id'] == fact['broker_id'] && r['component'] == fact['component']
        if commercial
          start = Date.iso8601(r.fetch('starts_on'))
          finish = r['ends_on'] && Date.iso8601(r['ends_on'])
          active = start <= day && (!finish || day < finish)
        else
          start, finish = Date.iso8601(r.fetch('valid_from')), Date.iso8601(r.fetch('valid_to'))
          raise Error.new('INVALID_INTERVAL') unless start < finish
          active = r['approved'] == true && start <= day && day < finish && Time.iso8601(r.fetch('recorded_at')) <= known && (!r['superseded_at'] || known < Time.iso8601(r['superseded_at']))
        end
        next false unless active && r.fetch('selector').all? { |key,value| fact.fetch('dimensions', {})[key] == value }
        unless commercial
          %w[tenant_id entity_id currency].each { |key| raise Error.new('SCOPE_MISMATCH', "Mismatched #{key}") unless fact[key].is_a?(String) && !fact[key].empty? && r[key] == fact[key] }
          raise Error.new('UNIT_MISMATCH') unless r['currency'] == 'USD'
        end
        if commercial && r['signup_within_days']
          raise Error.new('MISSING_SIGNUP_DATE', 'Signup date is required for a potentially applicable promotion') unless fact['signup_date']
          start = Date.iso8601(fact['signup_date'])
          next false unless start <= day && day < start + r['signup_within_days']
        end
        true
      end
      winner = choose_rate(candidates: candidates, precedence: commercial ? %w[targeted_promotion promotion standard] : %w[override promotion standard], containment: commercial ? [] : ['override'])
      [winner,candidates]
    rescue ArgumentError, KeyError, TypeError
      raise Error.new('VALIDATION_ERROR', 'Incomplete rate binding')
    end

    def self.validate!(policy)
      raise Error.new('UNSUPPORTED_MECHANISM', 'Unknown policy fields') unless (policy.keys - %w[version nodes rate_rows]).empty?
      nodes = policy.fetch('nodes')
      raise Error.new('INVALID_PROGRAM') unless policy['version'].is_a?(String) && !policy['version'].empty? && nodes.is_a?(Array) && nodes.size.between?(1, LIMIT)
      parse_number = lambda do |value|
        raise Error.new('INVALID_NUMBER') unless (value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A-?\d+(?:\/\d+)?\z/))) && value.to_s.length <= 100
        Rational(value)
      end
      rows=policy.fetch('rate_rows', {})
      raise Error.new('INVALID_PROGRAM') unless rows.is_a?(Hash) && rows.size <= LIMIT
      rows.each do |key, row|
        raise Error.new('INVALID_PROGRAM') unless key.is_a?(String) && !key.empty? && row.is_a?(Hash) && row['unit']=='scalar' && row['basis']=='scalar'
        parse_number.call(row.fetch('value'))
        raise Error.new('INVALID_PROGRAM') if row.key?('selector') && !row['selector'].is_a?(Hash)
      end
      map = {}
      nodes.each do |n|
        id = n.fetch('id')
        raise Error.new('INVALID_PROGRAM') unless id.is_a?(String) && !id.empty? && !map.key?(id)
        raise Error.new('INVALID_ROLE') unless ROLES.include?(n.fetch('role'))
        raise Error.new('INVALID_BASIS') unless BASES.include?(n.fetch('basis'))
        raise Error.new('INVALID_UNIT') unless n.fetch('unit').is_a?(String) && n['unit'].match?(/\A[A-Za-z][A-Za-z0-9_]*\z/)
        raise Error.new('UNSUPPORTED_MECHANISM') unless %w[literal fact sum_facts add min max subtract net multiply accrue assess bands select allocate allocate_by distribute].include?(n.fetch('op'))
        map[id] = n
      end
      edges = {}
      nodes.each do |n|
        refs = case n['op']
        when 'literal' then n.fetch('value'); []
        when 'fact' then n.fetch('key'); []
        when 'sum_facts' then []
        when 'add', 'min', 'max'
          a=n.fetch('inputs'); raise Error.new('INVALID_PROGRAM') unless a.is_a?(Array) && a.size.between?(1,LIMIT); a
        when 'subtract', 'net', 'multiply', 'accrue' then [n.fetch('left'),n.fetch('right')]
        when 'assess', 'allocate' then [n.fetch('input')]
        when 'allocate_by'
          weights=n.fetch('weights')
          raise Error.new('INVALID_ALLOCATION') unless weights.is_a?(Hash) && weights.any?
          [n.fetch('input')] + weights.values
        when 'distribute' then n.fetch('inputs')
        when 'bands'
          bands=n.fetch('bands'); raise Error.new('INVALID_BANDS') unless bands.is_a?(Array) && bands.size.between?(1,100)
          [n.fetch('input')] + bands.map { |b| b.fetch('rate') }
        when 'select'
          candidates=n.fetch('candidates'); raise Error.new('INVALID_PROGRAM') unless candidates.is_a?(Array) && candidates.size.between?(1,100)
          raise Error.new('INVALID_PROGRAM') unless n.key?('date') ^ n.key?('date_fact')
          candidates.each { |c| c.fetch('id'); Integer(c.fetch('priority')); c.fetch('value') }
          candidates.map { |c| c.fetch('value') }
        end
        raise Error.new('INVALID_REFERENCE') unless refs.all? { |ref| ref.is_a?(String) && map.key?(ref) }
        common = %w[id op role unit basis economic_key component payer payee subject currency interval_fact output_class explanation]
        params = { 'literal'=>%w[value], 'fact'=>%w[key requires], 'sum_facts'=>%w[collection selector allow_empty period], 'add'=>%w[inputs], 'min'=>%w[inputs], 'max'=>%w[inputs], 'subtract'=>%w[left right], 'net'=>%w[left right authority_fact], 'multiply'=>%w[left right], 'accrue'=>%w[left right], 'assess'=>%w[input rounding], 'bands'=>%w[input bands], 'select'=>%w[date date_fact candidates], 'allocate'=>%w[input weights recipient], 'allocate_by'=>%w[input weights recipient], 'distribute'=>%w[inputs recipient] }.fetch(n['op'])
        raise Error.new('UNSUPPORTED_MECHANISM', 'Unknown node fields') unless (n.keys - common - params).empty?
        values = refs.map { |id| map.fetch(id) }
        same = ->(v) { raise Error.new('UNIT_MISMATCH') unless v['unit'] == n['unit'] }
        case n['op']
        when 'literal'
          parse_number.call(n.fetch('value'))
        when 'fact'
          raise Error.new('INVALID_PROGRAM') unless n['key'].is_a?(String) && !n['key'].empty?
          raise Error.new('INVALID_PROGRAM') unless n.fetch('requires', {}).is_a?(Hash) && n.fetch('requires', {}).all? { |key, value| key.is_a?(String) && (value.is_a?(String) || value == true || value == false) }
        when 'sum_facts'
          raise Error.new('INVALID_PROGRAM') unless n['collection'].is_a?(String) && !n['collection'].empty? && n['selector'].is_a?(Hash) && n['selector'].all? { |key,value| key.is_a?(String) && (value.is_a?(String) || value==true || value==false) } && [true,false].include?(n['allow_empty']) && %w[service all].include?(n['period'])
        when 'add', 'min', 'max', 'subtract'
          values.each { |v| same.call(v); raise Error.new('BASIS_MISMATCH') unless v['basis'] == n['basis'] }
          if n['op']=='subtract' && values[0]['payer'] && values[0]['payee'] && values[0]['payer']==values[1]['payee'] && values[0]['payee']==values[1]['payer']
            raise Error.new('NETTING_UNAUTHORIZED', 'Opposing obligations require the net operator')
          end
        when 'net'
          values.each { |v| same.call(v); raise Error.new('BASIS_MISMATCH') unless v['basis']=='assessed' }
          raise Error.new('INVALID_BASIS') unless n['basis']=='assessed'
          left,right=values
          raise Error.new('NETTING_UNAUTHORIZED') unless n['authority_fact'].is_a?(String) && !n['authority_fact'].empty? && left['payer'].is_a?(String) && left['payee'].is_a?(String) && left['payer']!=left['payee'] && right['payer']==left['payee'] && right['payee']==left['payer'] && left['currency']==right['currency'] && n['unit']=="#{left['currency']}_minor"
        when 'multiply', 'accrue'
          a,b=values
          raise Error.new('UNIT_MISMATCH') unless (a['unit']=='scalar' && b['unit']==n['unit']) || (b['unit']=='scalar' && a['unit']==n['unit'])
          m=a['unit']=='scalar' ? b : a
          valid=n['op']=='accrue' ? m['basis']=='source_reported' && n['basis']=='exact_accrual' : m['basis']==n['basis']
          raise Error.new('BASIS_MISMATCH') unless valid
        when 'assess'
          same.call(values.first)
          raise Error.new('INVALID_BASIS') unless %w[exact_accrual source_reported].include?(values.first['basis']) && n['basis']=='assessed' && n.fetch('rounding')=='half_up'
        when 'allocate'
          same.call(values.first)
          raise Error.new('INVALID_BASIS') unless values.first['basis']=='assessed' && n['basis']=='assessed'
          weights=n.fetch('weights'); recipient=n.fetch('recipient')
          raise Error.new('INVALID_ALLOCATION') unless weights.is_a?(Hash) && weights.size.between?(1, LIMIT) && weights.key?(recipient) && weights.keys.all? { |key| key.is_a?(String) && !key.empty? }
          amounts=weights.values.map { |weight| parse_number.call(weight) }
          raise Error.new('INVALID_ALLOCATION') if amounts.any?(&:negative?) || amounts.sum != 1
        when 'allocate_by'
          input, *weight_nodes = values
          raise Error.new('INVALID_BASIS') unless input['unit']==n['unit'] && input['basis']=='assessed' && n['basis']=='assessed'
          weights=n.fetch('weights')
          raise Error.new('INVALID_ALLOCATION') unless weights.is_a?(Hash) && weights.size.between?(1,LIMIT) && weights.key?(n.fetch('recipient')) && weights.keys.all? { |key| key.is_a?(String) && !key.empty? } && weights.values.uniq.size==weights.size
          raise Error.new('UNIT_MISMATCH') unless weight_nodes.all? { |v| v['unit']==weight_nodes.first['unit'] && v['unit']!='scalar' }
          raise Error.new('BASIS_MISMATCH') unless weight_nodes.all? { |v| v['basis']==weight_nodes.first['basis'] && %w[source_reported exact_accrual assessed].include?(v['basis']) }
        when 'distribute'
          raise Error.new('INVALID_PROGRAM') if values.empty? || values.size > LIMIT
          values.each { |v| same.call(v); raise Error.new('INVALID_BASIS') unless v['basis']=='exact_accrual' }
          raise Error.new('INVALID_BASIS') unless n['basis']=='assessed' && n.fetch('inputs').include?(n.fetch('recipient')) && n['inputs'].uniq == n['inputs']
        when 'bands'
          same.call(values.first)
          raise Error.new('INVALID_BASIS') unless values.first['basis']=='source_reported' && n['basis']=='exact_accrual'
          raise Error.new('UNIT_MISMATCH') unless values.drop(1).all? { |v| v['unit']=='scalar' && v['basis']=='scalar' }
          previous=0
          n['bands'].each_with_index do |band,i|
            raise Error.new('INVALID_BANDS') unless (band.keys - %w[upper rate]).empty? && band.key?('upper')
            upper=band['upper'] && parse_number.call(band['upper'])
            raise Error.new('INVALID_BANDS') if (upper && upper <= previous) || (!upper && i != n['bands'].size-1)
            previous=upper if upper
          end
        when 'select'
          values.each { |v| same.call(v); raise Error.new('BASIS_MISMATCH') unless v['basis']==n['basis'] }
          Date.iso8601(n['date']) if n['date']
          raise Error.new('INVALID_PROGRAM') if n['date_fact'] && (!n['date_fact'].is_a?(String) || n['date_fact'].empty?)
          candidate_ids=[]
          n['candidates'].each do |candidate|
            raise Error.new('UNSUPPORTED_MECHANISM') unless (candidate.keys - %w[id priority value from to signup_fact days matches]).empty?
            candidate_ids << candidate.fetch('id')
            from=candidate['from'] && Date.iso8601(candidate['from']); to=candidate['to'] && Date.iso8601(candidate['to'])
            raise Error.new('INVALID_INTERVAL') if from && to && from >= to
            raise Error.new('INVALID_PROGRAM') if candidate['signup_fact'] && (!candidate['days'].is_a?(Integer) || !candidate['days'].between?(1, 3660))
            raise Error.new('INVALID_PROGRAM') unless candidate.fetch('matches', {}).is_a?(Hash)
          end
          raise Error.new('INVALID_PROGRAM') unless candidate_ids.all? { |id| id.is_a?(String) && !id.empty? } && candidate_ids.uniq == candidate_ids
        end
        edges[n['id']] = refs
      end
      raise Error.new('RESOURCE_LIMIT', 'Too many dependencies') if edges.values.sum(&:size) > 10_000
      seen = {}; visit = lambda do |id, path|
        raise Error.new('GRAPH_CYCLE') if path.include?(id)
        raise Error.new('RESOURCE_LIMIT') if path.size >= 128
        return if seen[id]
        edges.fetch(id).each { |ref| visit.call(ref, path + [id]) }
        seen[id] = true
      end
      map.each_key { |id| visit.call(id, []) }
      true
    rescue KeyError, TypeError, ArgumentError, ZeroDivisionError
      raise Error.new('INVALID_PROGRAM', 'Incomplete graph')
    end

    def initialize(policy:, facts:, cutoff: nil, period: nil, policy_cutoff: nil)
      rate_rows = policy.fetch('rate_rows', {})
      raise Error.new('INVALID_PROGRAM') unless facts.is_a?(Hash) && rate_rows.is_a?(Hash) && (facts.keys & rate_rows.keys).empty?
      @policy, @facts, @cutoff, @period, @policy_cutoff = policy, rate_rows.merge(facts), cutoff, period, policy_cutoff || cutoff
      @values, @bindings, @failures = {}, [], {}
    end

    def run
      self.class.validate!(@policy)
      nodes = @policy.fetch('nodes')
      raise Error.new('INVALID_PROGRAM') unless nodes.is_a?(Array) && nodes.size.between?(1, LIMIT)
      ids = nodes.map { |n| n.fetch('id') }
      raise Error.new('INVALID_PROGRAM', 'Node IDs must be unique nonempty strings') unless ids.all? { |id| id.is_a?(String) && !id.empty? } && ids.uniq == ids
      @nodes = nodes.to_h { |n| [n['id'], n] }
      nodes.each do |node|
        begin
          calculate(node['id'], [])
        rescue Error => e
          raise unless %w[INCOMPLETE_SOURCE FUTURE_EVIDENCE MISSING_SIGNUP_DATE UNRESOLVED_MAPPING RULE_CONFLICT].include?(e.code)
          @failures[node['id']] = e
        end
      end
      details = nodes.select { |node| @values.key?(node['id']) }.map do |node|
        v = @values.fetch(node['id'])
        { 'id' => node['id'], 'role' => node.fetch('role'), 'unit' => v.unit, 'basis' => v.basis, 'value' => encode(v.amount) }
      end
      output_ids = nodes.select { |n| %w[terminal summary].include?(n['role']) }.map { |n| n['id'] }
      output_failures = @failures.select { |id, _| output_ids.include?(id) }
      { 'version' => @policy.fetch('version'), 'engine_version' => Engine::VERSION,
        'bindings' => @bindings.sort_by { |x| x['node'] }, 'details' => details,
        'terminal_outputs' => details.select { |x| x['role'] == 'terminal' },
        'exceptions' => output_failures.sort.map { |id, e| e.to_h.transform_keys(&:to_s).merge('node' => id) },
        'status' => output_failures.empty? ? 'completed' : (details.any? { |d| output_ids.include?(d['id']) } ? 'partial' : 'blocked') }
    rescue KeyError, TypeError, ArgumentError, ZeroDivisionError
      raise Error.new('INVALID_PROGRAM', 'Incomplete or invalid graph')
    end

    private

    def proportional_allocation(amount, weights, recipient)
      raise Error.new('INVALID_ALLOCATION') unless weights.key?(recipient) && weights.values.none?(&:negative?) && weights.values.sum.positive?
      total=weights.values.sum
      sign=amount.negative? ? -1 : 1
      exact=weights.transform_values { |weight| amount.abs * weight / total }
      portions=exact.transform_values(&:floor)
      order=exact.keys.sort_by { |key| [-(exact[key]-portions[key]), key] }
      (amount.abs.to_i-portions.values.sum).times { |i| portions[order[i]] += 1 }
      sign * portions.fetch(recipient)
    end

    def rational(value)
      raise Error.new('INVALID_NUMBER') unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A-?\d+(?:\/\d+)?\z/))
      raise Error.new('RESOURCE_LIMIT') if value.to_s.length > 100
      Rational(value)
    end

    def encode(value)
      "#{value.numerator}/#{value.denominator}"
    end

    def calculate(id, visiting)
      return @values[id] if @values.key?(id)
      raise @failures[id] if @failures.key?(id)
      raise Error.new('INVALID_REFERENCE', id.to_s) unless @nodes.key?(id)
      raise Error.new('GRAPH_CYCLE') if visiting.include?(id)
      raise Error.new('RESOURCE_LIMIT', 'Graph depth exceeded') if visiting.size >= 128
      n = @nodes[id]
      raise Error.new('INVALID_ROLE') unless ROLES.include?(n.fetch('role'))
      unit, basis = n.fetch('unit'), n.fetch('basis')
      raise Error.new('INVALID_UNIT') unless unit.is_a?(String) && unit.match?(/\A[A-Za-z][A-Za-z0-9_]*\z/)
      raise Error.new('INVALID_BASIS') unless BASES.include?(basis)
      ref = ->(key) { calculate(n.fetch(key), visiting + [id]) }
      refs = -> { n.fetch('inputs').map { |x| calculate(x, visiting + [id]) } }
      same = ->(values) { raise Error.new('UNIT_MISMATCH') unless values.all? { |v| v.unit == unit } }
      amount = case n.fetch('op')
      when 'literal'
        rational(n.fetch('value'))
      when 'fact'
        f = @facts[n.fetch('key')]
        raise Error.new('INCOMPLETE_SOURCE', 'Required fact unavailable') unless f
        raise Error.new('UNIT_MISMATCH') unless f.fetch('unit') == unit
        raise Error.new('BASIS_MISMATCH') unless f.fetch('basis') == basis
        raise Error.new('INCOMPLETE_SOURCE', 'Fact does not meet required evidence predicates') unless n.fetch('requires', {}).all? { |key,value| f[key] == value }
        clock = @policy.fetch('rate_rows', {}).key?(n['key']) ? @policy_cutoff : @cutoff
        if f['recorded_at'] && clock && Time.iso8601(f['recorded_at']) > Time.iso8601(clock)
          raise Error.new('FUTURE_EVIDENCE')
        end
        @bindings << { 'node' => id, 'fact' => n['key'] }
        rational(f.fetch('value'))
      when 'sum_facts'
        raise Error.new('INVALID_PROGRAM') if @facts.size > LIMIT
        selected = @facts.select { |_key, fact| fact.is_a?(Hash) && fact['collection']==n['collection'] && n['selector'].all? { |key,value| fact[key]==value } }.sort.to_h
        selected = selected.select do |_key, fact|
          known = !fact['recorded_at'] || !@cutoff || Time.iso8601(fact['recorded_at']) <= Time.iso8601(@cutoff)
          if n['period']=='service'
            raise Error.new('INVALID_PROGRAM', 'Service period required') unless @period && @period['service_start'] && @period['service_end_exclusive']
            day=Date.iso8601(fact.fetch('economic_date'))
            known &&= Date.iso8601(@period['service_start']) <= day && day < Date.iso8601(@period['service_end_exclusive'])
          end
          known
        end
        raise Error.new('INCOMPLETE_SOURCE', 'Required collection is empty') if selected.empty? && !n['allow_empty']
        total=selected.sum do |_key, fact|
          raise Error.new('UNIT_MISMATCH') unless fact.fetch('unit') == unit
          raise Error.new('BASIS_MISMATCH') unless fact.fetch('basis') == basis
          rational(fact.fetch('value'))
        end
        @bindings << { 'node'=>id, 'facts'=>selected.keys }
        total
      when 'add', 'min', 'max'
        vs = refs.call; raise Error.new('INVALID_PROGRAM') if vs.empty? || vs.size > LIMIT; same.call(vs)
        raise Error.new('BASIS_MISMATCH') unless vs.all? { |v| v.basis == basis }
        case n['op']; when 'add' then vs.sum(&:amount); when 'min' then vs.map(&:amount).min; else vs.map(&:amount).max; end
      when 'subtract', 'net'
        a, b = ref.call('left'), ref.call('right'); same.call([a, b]); raise Error.new('BASIS_MISMATCH') unless a.basis == basis && b.basis == basis
        if n['op']=='net'
          authority=@facts[n.fetch('authority_fact')]; left=@nodes.fetch(n.fetch('left'))
          raise Error.new('INCOMPLETE_SOURCE', 'Netting authority unavailable') unless authority
          raise Error.new('INCOMPLETE_SOURCE', 'Netting authority not eligible') unless authority['status']=='authorized' && authority['debtor']==left['payer'] && authority['creditor']==left['payee'] && authority['currency']==left['currency']
          raise Error.new('FUTURE_EVIDENCE') if authority['recorded_at'] && @cutoff && Time.iso8601(authority['recorded_at']) > Time.iso8601(@cutoff)
          raise Error.new('INCOMPLETE_SOURCE', 'Netting authority interval unavailable') unless authority['valid_from'] && authority['valid_to'] && @period && @period['service_start'] && @period['service_end_exclusive']
          raise Error.new('INCOMPLETE_SOURCE', 'Netting authority not effective') unless Date.iso8601(authority['valid_from']) <= Date.iso8601(@period['service_start']) && Date.iso8601(@period['service_end_exclusive']) <= Date.iso8601(authority['valid_to'])
        end
        a.amount - b.amount
      when 'multiply', 'accrue'
        a, b = ref.call('left'), ref.call('right')
        raise Error.new('UNIT_MISMATCH') unless (a.unit == 'scalar' && b.unit == unit) || (b.unit == 'scalar' && a.unit == unit)
        monetary = a.unit == 'scalar' ? b : a
        valid_basis = n['op'] == 'accrue' ? monetary.basis == 'source_reported' && basis == 'exact_accrual' : monetary.basis == basis
        raise Error.new('BASIS_MISMATCH') unless valid_basis
        a.amount * b.amount
      when 'distribute'
        ids = n.fetch('inputs'); values = ids.to_h { |ref_id| [ref_id, calculate(ref_id, visiting + [id])] }
        amounts = values.transform_values(&:amount)
        raise Error.new('UNSUPPORTED_MECHANISM', 'Mixed-sign distribution requires a separate policy') if amounts.values.any?(&:negative?) && amounts.values.any?(&:positive?)
        sign = amounts.values.any?(&:negative?) ? -1 : 1
        absolute = amounts.transform_values(&:abs)
        floors = absolute.transform_values(&:floor)
        target = Engine.round(absolute.values.sum)
        order = ids.sort_by { |key| [-(absolute[key] - floors[key]), key] }
        (target - floors.values.sum).times { |i| floors[order[i]] += 1 }
        sign * floors.fetch(n.fetch('recipient'))
      when 'allocate_by'
        v = ref.call('input'); same.call([v])
        raise Error.new('INVALID_BASIS') unless v.basis == 'assessed' && basis == 'assessed' && v.amount.denominator == 1
        weights = n.fetch('weights').transform_values { |node_id| calculate(node_id, visiting + [id]) }
        raise Error.new('UNIT_MISMATCH') unless weights.values.all? { |w| w.unit == weights.values.first.unit && w.unit != 'scalar' }
        raise Error.new('BASIS_MISMATCH') unless weights.values.all? { |w| w.basis == weights.values.first.basis }
        proportional_allocation(v.amount, weights.transform_values(&:amount), n.fetch('recipient'))
      when 'allocate'
        v = ref.call('input'); same.call([v])
        raise Error.new('INVALID_BASIS') unless v.basis == 'assessed' && basis == 'assessed' && v.amount.denominator == 1
        weights = n.fetch('weights'); recipient = n.fetch('recipient')
        raise Error.new('INVALID_ALLOCATION') unless weights.is_a?(Hash) && weights.key?(recipient) && weights.keys.all? { |k| k.is_a?(String) && !k.empty? }
        weights = weights.transform_values { |w| rational(w) }
        raise Error.new('INVALID_ALLOCATION') if weights.values.any?(&:negative?) || weights.values.sum != 1
        proportional_allocation(v.amount, weights, recipient)
      when 'assess'
        v = ref.call('input'); same.call([v]); raise Error.new('INVALID_BASIS') unless basis == 'assessed' && %w[exact_accrual source_reported].include?(v.basis) && n.fetch('rounding') == 'half_up'
        Engine.round(v.amount)
      when 'bands'
        v = ref.call('input'); same.call([v]); raise Error.new('INVALID_BASIS') unless v.basis == 'source_reported' && basis == 'exact_accrual'; raise Error.new('INVALID_NUMBER') if v.amount.negative?
        previous = 0; total = 0
        n.fetch('bands').each_with_index do |band, i|
          upper = band['upper'] && rational(band['upper'])
          raise Error.new('INVALID_BANDS') if (upper && upper <= previous) || (!upper && i != n['bands'].size - 1)
          slice = upper ? [[v.amount - previous, 0].max, upper - previous].min : [v.amount - previous, 0].max
          rate = calculate(band.fetch('rate'), visiting + [id]); raise Error.new('UNIT_MISMATCH') unless rate.unit == 'scalar'
          total += slice * rate.amount
          previous = upper if upper
        end
        raise Error.new('INCOMPLETE_BANDS') if n['bands'].last['upper'] && v.amount > previous
        total
      when 'select'
        candidates = n.fetch('candidates').select do |c|
          date_fact = n['date_fact'] && @facts[n['date_fact']]
          raise Error.new('INCOMPLETE_SOURCE', 'Service date unavailable') if n['date_fact'] && (!date_fact || !date_fact['date'])
          date = Date.iso8601(n['date'] || date_fact['date'])
          active = (!c['from'] || Date.iso8601(c['from']) <= date) && (!c['to'] || date < Date.iso8601(c['to']))
          value_node = @nodes.fetch(c.fetch('value'))
          row = value_node['op'] == 'fact' && @policy.fetch('rate_rows', {})[value_node['key']]
          if row && row['valid_from']
            if row['signup_within_days']
              raise Error.new('RULE_CONFLICT', 'Rate signup condition differs from policy candidate') unless c['signup_fact'] && c['days'] == row['signup_within_days']
            elsif c['signup_fact']
              raise Error.new('RULE_CONFLICT', 'Policy candidate requires an unbound signup condition')
            end
            active &&= row['approved'] == true && Date.iso8601(row['valid_from']) <= date && (!row['valid_to'] || date < Date.iso8601(row['valid_to']))
            active &&= !row['recorded_at'] || !@policy_cutoff || Time.iso8601(row['recorded_at']) <= Time.iso8601(@policy_cutoff)
            if row.fetch('selector', {}).any?
              raise Error.new('UNRESOLVED_MAPPING', 'Rate scope requires a dated subject fact') unless date_fact
              attributes = date_fact.merge(date_fact.fetch('dimensions', {}))
              active &&= row['selector'].all? { |key,value| attributes[key] == value }
            end
          end
          if active && c['signup_fact']
            signup = @facts[c['signup_fact']]; raise Error.new('MISSING_SIGNUP_DATE') unless signup && signup['date']
            start = Date.iso8601(signup['date']); active &&= start <= date && date < start + Integer(c.fetch('days'))
          end
          active && (c.fetch('matches', {}).all? { |key, value| @facts.fetch(key).fetch('value') == value })
        end
        raise Error.new('UNRESOLVED_MAPPING') if candidates.empty?
        normalized = candidates.map { |candidate| candidate.merge('kind'=>'candidate', 'priority'=>Integer(candidate.fetch('priority'))) }
        winner = self.class.choose_rate(candidates: normalized, precedence: ['candidate'])
        @bindings << { 'node' => id, 'winner' => winner.fetch('id'), 'candidates' => candidates.map { |c| c.fetch('id') }.sort }
        v = calculate(winner.fetch('value'), visiting + [id]); same.call([v]); raise Error.new('BASIS_MISMATCH') unless v.basis == basis; v.amount
      else
        raise Error.new('UNSUPPORTED_MECHANISM', n['op'].to_s)
      end
      raise Error.new('INVALID_BASIS', 'Assessed amounts must be whole minor units') if basis == 'assessed' && amount.denominator != 1
      raise Error.new('RESOURCE_LIMIT', 'Numeric result exceeded limit') if amount.numerator.bit_length > 1024 || amount.denominator.bit_length > 1024
      @values[id] = Value.new(amount: amount, unit: unit, basis: basis)
    end
  end
end
