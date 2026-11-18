# Read projections only. Every monetary field references an assessed engine
# detail or a separately evidenced application; this class does not price deals.
class MedallionPresenter
  LABELS = {
    'fees'=>'Client advisory fees', 'cedar_fee'=>'Cedar advisory fee',
    'maple_fee'=>'Maple advisory fee', 'share_total'=>'Fee-share compensation',
    'cedar_share'=>'Cedar compensation', 'maple_share'=>'Maple compensation',
    'topup'=>'Earnings guarantee', 'compensation'=>'Total compensation',
    'coverage'=>'Advance applied', 'payable'=>'Remaining payable',
    'bonus'=>'Bonus', 'bonus_assessed'=>'Bonus', 'service_credit'=>'Service credit',
    'bonus_guarantee'=>'Bonus', 'bonus_outside'=>'Bonus', 'outside_charge'=>'One-time charge',
    'charge'=>'Platform charge after cap', 'rebate'=>'Qualified account-related credit',
    'fixed'=>'Monthly platform charge', 'usage'=>'Account activity charge',
    'uncapped'=>'Platform charges before cap', 'cap'=>'Platform charge cap',
    'net'=>'Amount due', 'standard_compensation'=>'Standard terms',
    'promotion_benefit'=>'Promotion benefit', 'guarantee_benefit'=>'Guarantee benefit',
    'baseline_charge'=>'Fixed and account charges before benefits',
    'cap_benefit'=>'Charge cap saving', 'rebate_benefit'=>'Qualified credit',
    'total_benefit'=>'Value of selected terms', 'cash_assessed'=>'Cash gross yield',
    'cash_investor_assessed'=>'Investor cash allocation', 'cash_savvy'=>'Savvy cash allocation',
    'cash_network'=>'Network cash allocation', 'margin_assessed'=>'Investor margin charge',
    'margin_funding_assessed'=>'Margin funding amount', 'margin_savvy'=>'Savvy margin allocation',
    'lending_gross_report'=>'Reported lending gross', 'lending_investor_report'=>'Investor lending allocation',
    'lending_network_report'=>'Network lending allocation', 'lending_savvy_report'=>'Savvy lending allocation',
    'reported_cash_savvy'=>'Reported Savvy cash allocation',
    'reported_margin_savvy'=>'Reported Savvy margin allocation',
    'reported_lending_savvy'=>'Reported Savvy lending allocation'
  }.freeze
  SCENARIOS = {
    'baseline'=>'Original terms and activity', 'correction'=>'Late balance correction',
    'bonus_outside'=>'Bonus outside the earnings guarantee',
    'bonus_inside'=>'Bonus within the earnings guarantee',
    'pending_payment'=>'Payout awaiting confirmation', 'confirmed_payment'=>'Confirmed payout applied',
    'service_credit'=>'Post hoc service credit'
  }.freeze
  # Explicitly shared fictional cases. An external identity cannot turn an
  # internal/private scenario into a product view by guessing its identifier.
  EXTERNAL_SCENARIOS = {
    'advisor'=>%w[baseline correction bonus_outside bonus_inside pending_payment confirmed_payment],
    'ria'=>%w[baseline service_credit]
  }.freeze

  def initialize(workbench)
    @workbench = workbench
    @service = workbench.medallion
  end

  def view(workspace:, case_id:, run_id: nil, scenario_id: nil)
    @case_id = @service.case!(case_id)
    @scenario = @service.scenario!(scenario_id)
    authorize!(workspace)
    DemoScope.transaction do
      DemoScope.where(**@workbench.scope).lock.first!
      runs = rows('run')
      @run = run_id ? @service.get!(@case_id, @scenario, 'run', run_id) : runs.last
      @result = @run&.payload&.fetch('result', {}) || {}
      @details = @result.fetch('details', []).index_by { |detail| detail.fetch('id') }
      @policy = @run && rows('policy').find { |p| p.external_id == @run.payload['policy_id'] }
      @statement = statement_view(historical: run_id.present?)
      out = {
        'case_id'=>@case_id, 'scenario_id'=>@scenario, 'workspace'=>workspace,
        'run'=>run_view, 'terms'=>terms_view,
        'statement'=>@statement
      }
      out.merge!(internal_view(runs)) if workspace == 'internal'
      out
    end
  end

  private

  def authorize!(workspace)
    @service.error('FORBIDDEN') unless %w[internal advisor ria].include?(workspace)
    allowed = case @workbench.role
    when 'advisor' then workspace == 'advisor' && @case_id == 'advisor'
    when 'ria' then workspace == 'ria' && @case_id == 'ria'
    else MedallionWorkbench::INTERNAL.include?(@workbench.role) && (workspace == 'internal' || workspace == @case_id)
    end
    @service.error('FORBIDDEN') unless allowed
    if %w[advisor ria].include?(@workbench.role)
      @service.error('FORBIDDEN') unless EXTERNAL_SCENARIOS.fetch(@case_id).include?(@scenario)
    end
  end

  def rows(kind)
    @service.source(@case_id, @scenario, kind).order(:id).to_a
  end

  def item(id, description: nil)
    detail = @details[id]
    unless detail
      return { 'output_id'=>id, 'detail_refs'=>[], 'run_id'=>@run.external_id,
        'label'=>LABELS.fetch(id, id.tr('_', ' ').capitalize), 'minor'=>nil,
        'currency'=>'USD', 'status'=>'pending' }
    end
    return nil unless detail['unit'] == 'USD_minor'
    amount = detail['assessed_minor']
    reported = detail['basis'] == 'source_reported'
    if amount.nil? && reported
      exact = Rational(detail.fetch('value'))
      amount = exact.numerator if exact.denominator == 1
    end
    {
      'output_id'=>id, 'detail_refs'=>[detail['id']], 'run_id'=>@run.external_id,
      'label'=>id == 'net' && amount && amount.negative? ? 'Credit balance' : LABELS.fetch(id, id.tr('_', ' ').capitalize),
      'minor'=>amount&.to_s, 'currency'=>detail['currency'] || 'USD',
      'basis'=>detail['basis'], 'description'=>description || detail['explanation'],
      'client_ids'=>source_client_ids(detail),
      'basis_rows'=>balance_basis(detail),
      'category'=>detail_category(id, detail),
      'status'=>amount.nil? ? 'pending' : (reported ? 'source_reported' : 'assessed')
    }
  end

  def source_client_ids(detail)
    facts = @run.payload.dig('input_manifest','facts') || {}
    detail.fetch('source_refs', []).filter_map do |reference|
      next unless reference['kind']=='source_fact'
      facts.dig(reference['key'],'subject_id')
    end.uniq
  end

  def balance_basis(detail)
    return [] unless @case_id == 'advisor' && detail['payee'] == 'firm-demo'
    facts = @run.payload.dig('input_manifest', 'facts') || {}
    detail.fetch('source_refs', []).select { |ref| ref['kind'] == 'source_fact' }.map { |ref| ref['key'] }.uniq.filter_map do |key|
      fact = facts[key]
      next unless fact && fact['date'] && fact['unit'] == 'USD_minor' && fact['basis'] == 'source_reported'
      value = Rational(fact.fetch('value'))
      next unless value.denominator == 1
      { 'date'=>fact['date'], 'minor'=>value.numerator.to_s, 'label'=>'Billable balance', 'subject_id'=>fact['subject_id'] }
    end.sort_by { |row| row['date'] }
  end

  def detail_category(id, detail)
    return %w[fees cedar_fee maple_fee].include?(id) ? 'client_fees' : 'compensation' if @case_id == 'advisor'
    return 'investor' if id.include?('investor') || id == 'margin_assessed'
    return 'charges' if %w[fixed usage uncapped cap charge rebate service_credit outside_charge].include?(id)
    parties = [detail['payer'], detail['payee']]
    return 'charges' if parties.all? { |party| party.is_a?(String) } && parties.sort == %w[firm-demo ria-harbor] && !id.start_with?('comparison_')
    'network'
  end

  def items(ids)
    ids.filter_map { |id| item(id) }
  end

  def run_view
    return nil unless @run
    context = @result.fetch('context', {})
    headline = @case_id == 'advisor' ? %w[compensation coverage payable] : %w[net charge rebate]
    breakdown = @case_id == 'advisor' ? %w[fees cedar_fee maple_fee share_total cedar_share maple_share bonus bonus_assessed topup] :
      %w[fixed usage uncapped cap cash_assessed cash_investor_assessed cash_savvy cash_network margin_assessed margin_funding_assessed margin_savvy lending_gross_report lending_investor_report lending_network_report lending_savvy_report]
    # Newly authored terminal components remain explainable without a frontend
    # deployment. Headline/summary values are never added to their child rows.
    optional_events = %w[bonus_guarantee bonus_outside outside_charge service_credit]
    additional = @details.values.select do |d|
      d['role'] == 'terminal' && d['unit'] == 'USD_minor' &&
        !(optional_events.include?(d['id']) && d['assessed_minor'] == 0)
    end.map { |d| d['id'] }
    one_time = %w[bonus_guarantee bonus_outside outside_charge].select do |id|
      @details[id] && @details[id]['assessed_minor'] && @details[id]['assessed_minor'] != 0
    end
    breakdown = (breakdown + additional + one_time).uniq - headline
    summary = items(headline)
    # Cash evidence changes the outstanding balance, not earned compensation or
    # commercial benefit. Use the common statement projection for that headline
    # and retain its underlying obligation/application references explicitly.
    if @statement && @statement.fetch('application_refs', []).any?
      before_payment = @case_id == 'advisor' ? 'payable' : 'net'
      summary = summary.map do |entry|
        next entry unless entry['output_id'] == before_payment
        entry.merge('output_id'=>'statement_balance', 'obligation_output_id'=>before_payment,
          'minor'=>@statement['balance_minor'], 'source_kind'=>'statement_projection',
          'application_refs'=>@statement['application_refs'], 'as_of'=>@statement['as_of'])
      end
    end
    {
      'id'=>@run.external_id, 'status'=>@result['status'] || @run.status,
      'period_start'=>context['service_start'], 'period_end'=>context['service_end_exclusive'],
      'knowledge_cutoff'=>context['knowledge_cutoff'],
      'summary'=>summary, 'detail'=>items(breakdown.select { |id| @details.key?(id) }), 'comparison'=>comparison_view,
      'exceptions'=>@result.fetch('exceptions', []).map { |e| e.slice('code', 'message') },
      'coverage'=>@result.fetch('coverage', [])
    }
  end

  def comparison_view
    baseline = 'comparison_baseline'
    selected = 'comparison_selected'
    benefits = @case_id == 'advisor' ? %w[promotion_benefit guarantee_benefit] : %w[cap_benefit rebate_benefit]
    return nil unless @details.key?(baseline) && @details.key?(selected)
    {
      'baseline_label'=>@case_id == 'advisor' ? 'Standard terms, same activity and one-time items' : 'Charges before cap and rebate, same one-time items',
      'baseline_minor'=>item(baseline)['minor'],
      'selected_minor'=>item(selected)['minor'], 'benefits'=>items(benefits),
      'benefit'=>item('total_benefit'), 'run_id'=>@run.external_id,
      'detail_refs'=>[baseline, selected, *benefits],
      'description'=>@case_id == 'advisor' ?
        'The same client activity under standard terms and your selected terms. Advances and payments are shown separately.' :
        'The same account activity under the fixed and account charges, compared with your selected cap and qualified credit. Investor amounts are separate.'
    }
  end

  def terms_view
    rows('policy').select { |p| @service.published?(p) }.map do |policy|
      graph = policy.payload.fetch('policy')
      rates = CommercialRate.where(**@workbench.scope, configuration_id: policy.payload['rate_configuration_id']).order(:external_id)
      parameter_labels = { 'floor'=>'Monthly earnings floor', 'cap'=>'Platform charge cap', 'fixed'=>'Monthly platform charge', 'price'=>'Price per eligible account-month' }
      parameters = graph.fetch('nodes').filter_map do |node|
        next unless parameter_labels.key?(node['id']) && node['op'] == 'literal' && node['unit'] == 'USD_minor'
        { 'label'=>parameter_labels.fetch(node['id']), 'value'=>minor_label(Rational(node.fetch('value'))) }
      end
      graph.fetch('nodes').select { |n| n['op'] == 'bands' }.map { |n| n.fetch('bands').map { |band| band['upper'] } }.uniq.each do |limits|
        limits.compact.each_with_index do |limit, index|
          parameters << { 'label'=>"Advisory balance band #{index + 1} ceiling", 'value'=>minor_label(Rational(limit)) }
        end
      end
      day = graph.fetch('nodes').find { |node| node['id'] == 'day' && node['op'] == 'literal' && node['unit'] == 'scalar' }
      if day
        fraction = Rational(day.fetch('value'))
        parameters << { 'label'=>'Annual-rate basis', 'value'=>fraction.numerator == 1 ? "Actual days / #{fraction.denominator}" : "#{fraction.numerator}/#{fraction.denominator} per day" }
      end
      {
        'policy_id'=>policy.external_id,
        'title'=>@case_id == 'advisor' ? 'Client fee basis and advisor compensation' : 'Platform service terms',
        'version'=>graph['version'], 'status'=>policy == @policy ? 'applied' : 'available',
        'period_start'=>rates.filter_map(&:starts_on).min&.iso8601 || '2026-09-01',
        'period_end'=>rates.filter_map(&:ends_on).max&.iso8601,
        'items'=>rates.map { |r| { 'label'=>rate_name(r), 'value'=>term_rate_label(r) } } + parameters,
        'document_ref'=>policy.payload['document_ref']&.slice('document_id', 'version')
      }
    end
  end

  def rate_name(rate)
    {
      'rate_r12'=>'Client advisory fee: first balance band',
      'rate_r08'=>'Client advisory fee: remaining balance band',
      'rate_s80'=>'Standard advisor share', 'rate_s85'=>'General promotion share',
      'rate_s90'=>'Targeted welcome share', 'rate_rebate_rate'=>'Qualified receipt rebate',
      'rate_cash_ref'=>'Cash reference yield', 'rate_cash_investor_rate'=>'Investor cash yield',
      'rate_margin_rate'=>'Client margin rate', 'rate_margin_funding_rate'=>'Margin funding rate',
      'rate_savvy_share'=>'Savvy cash spread allocation', 'rate_network_share'=>'Network cash spread allocation'
    }.fetch(rate.external_id, rate.name.tr('_', ' ').capitalize)
  end

  def rate_label(rate)
    ratio = Rational(rate.numerator, rate.denominator)
    if rate.unit == 'ratio'
      percent = ratio * 100
      "#{finite_decimal_or_fraction(percent)}%"
    elsif rate.unit == 'USD_minor'
      minor_label(ratio)
    else
      "#{ratio.numerator}/#{ratio.denominator} #{rate.unit}"
    end
  end

  def term_rate_label(rate)
    dates = rate.starts_on.strftime('%b %-d, %Y') + ' – ' +
      (rate.ends_on ? (rate.ends_on - 1).strftime('%b %-d, %Y') : 'ongoing')
    scope = rate.selector.map { |key, value| "#{key.tr('_', ' ')}: #{value.to_s.tr('_', ' ')}" }
    scope << "First #{rate.signup_within_days} days after signup" if rate.signup_within_days
    [rate_label(rate), dates, *scope].join(' · ')
  end

  def finite_decimal_or_fraction(value)
    denominator = value.denominator
    twos = fives = 0
    while (denominator % 2).zero?
      denominator /= 2
      twos += 1
    end
    while (denominator % 5).zero?
      denominator /= 5
      fives += 1
    end
    return "#{value.numerator}/#{value.denominator}" unless denominator == 1
    places = [twos, fives].max
    return value.numerator.to_s if places.zero?
    digits = (value.abs * (10**places)).numerator.to_s.rjust(places + 1, '0')
    "#{value.negative? ? '-' : ''}#{digits[0...-places]}.#{digits[-places..]}".sub(/0+\z/, '').sub(/\.\z/, '')
  end

  def minor_label(value)
    exact = finite_decimal_or_fraction(value / 100)
    return "$#{exact}" if exact.include?('/')
    whole, point, fraction = exact.partition('.')
    sign = whole.start_with?('-') ? '−' : ''
    digits = whole.delete_prefix('-').reverse.scan(/.{1,3}/).join(',').reverse
    "#{sign}$#{digits}#{point}#{fraction}"
  end

  def statement_view(historical:)
    return nil unless @run && @result['status'] == 'completed'
    cutoff = historical ? @run.payload['knowledge_cutoff'] : Time.current.iso8601(6)
    statement = @service.projected_statement(@case_id, @scenario, @run, as_of: cutoff)
    statement['detail_refs'] = [@case_id == 'advisor' ? 'payable' : 'net']
    statement['as_of'] = cutoff
    statement
  rescue Economics::Error => e
    { 'status'=>'needs_review', 'lines'=>[], 'balance_minor'=>nil, 'exceptions'=>[e.to_h.transform_keys(&:to_s).slice('code', 'message')] }
  end

  def serialize(row)
    row.payload.merge('id'=>row.external_id, 'revision'=>row.revision, 'hash'=>row.payload_hash, 'status'=>row.status, 'recorded_at'=>row.recorded_at.iso8601(6))
  end

  def internal_view(runs)
    policies = rows('policy')
    events = rows('event').map do |event|
      review = rows('event_review').select { |r| r.parent_id == event.id }.last
      serialize(event).merge('status'=>review&.status || event.status)
    end
    reversed = rows('application_reversal').map(&:parent_id)
    scenarios = MedallionEvidence.where(**@workbench.scope, case_id:@case_id).distinct.order(:scenario_id).pluck(:scenario_id)
    {
      'parties'=>MedallionWorkbench::PARTIES.fetch(@case_id).map { |id| { 'id'=>id, 'name'=>party_name(id) } },
      'subjects'=>[{ 'id'=>@case_id == 'advisor' ? 'advisor-demo' : 'ria-harbor', 'name'=>@case_id == 'advisor' ? 'Affiliated advisor' : 'Harbor RIA' }],
      'products'=>[{ 'id'=>@case_id == 'advisor' ? 'advisor-compensation' : 'ria-platform', 'name'=>@case_id == 'advisor' ? 'Advisor compensation' : 'Custodial platform' }],
      'assignments'=>rows('assignment').map { |r| serialize(r).merge('schedule_version'=>r.schedule_version) },
      'scenarios'=>scenarios.map { |id| { 'id'=>id, 'label'=>SCENARIOS.fetch(id, id.tr('_-', ' ').capitalize) } },
      'event_kinds'=>MedallionWorkbench::EVENT_KINDS,
      'event_policies'=>policies.select { |p| @service.published?(p) }.flat_map do |p|
        p.payload.fetch('event_policies', []).map { |rule| rule.merge('policy_id'=>p.external_id) }
      end,
      'policies'=>policies.map do |p|
        serialize(p).merge('version'=>p.payload.dig('policy', 'version'), 'status'=>@service.published?(p) ? 'published' : p.status,
          'rates'=>CommercialRate.where(**@workbench.scope, configuration_id:p.payload['rate_configuration_id']).order(:external_id).map do |r|
            r.attributes.slice('name', 'kind', 'numerator', 'denominator', 'unit', 'selector',
              'signup_within_days', 'priority', 'component', 'payer_id', 'payee_id',
              'broker_id', 'commercial_group').merge('id'=>r.external_id,
                'starts_on'=>r.starts_on.iso8601, 'ends_on'=>r.ends_on&.iso8601)
          end)
      end,
      'comparisons'=>rows('comparison').map { |r| serialize(r) },
      'reviews'=>rows('review').map { |r| serialize(r) }, 'events'=>events,
      'payments'=>rows('payment').map { |r| serialize(r) },
      'payment_applications'=>rows('application').map { |r| serialize(r).merge('status'=>reversed.include?(r.id) ? 'reversed' : 'confirmed') },
      'statements'=>rows('statement').map { |r| serialize(r) },
      'runs'=>runs.map { |r| { 'id'=>r.external_id, 'case_id'=>@case_id, 'scenario_id'=>@scenario, 'status'=>r.payload.dig('result', 'status') || r.status, 'knowledge_cutoff'=>r.payload['knowledge_cutoff'] } },
      'pipeline'=>pipeline_view
    }
  end

  def party_name(id)
    { 'firm-demo'=>'Savvy', 'advisor-demo'=>'Affiliated advisor', 'ria-harbor'=>'Harbor RIA', 'network-fixture'=>'Custodial network' }.fetch(id, id)
  end

  def pipeline_view
    artifacts = rows('artifact')
    deliveries = rows('delivery')
    facts = @run&.payload&.dig('input_manifest', 'facts') || {}
    {
      'stages'=>[
        { 'name'=>'Bronze', 'summary'=>'Original deliveries and every retained revision', 'count'=>artifacts.size,
          'samples'=>artifacts.first(4).map { |r| serialize(r).merge('byte_count'=>r.original_bytes&.bytesize) } },
        { 'name'=>'Deliveries', 'summary'=>'Arrival, acceptance and rejection history', 'count'=>deliveries.size,
          'samples'=>deliveries.last(4).map { |r| serialize(r) } },
        { 'name'=>'Silver facts', 'summary'=>'Known source facts with original identity, basis and unit', 'count'=>facts.size,
          'samples'=>facts.first(5).map { |id, fact| fact.merge('fact_key'=>id) } },
        { 'name'=>'Silver term binding', 'summary'=>'The common engine selects the applicable terms', 'count'=>@result.fetch('bindings', []).size,
          'samples'=>@result.fetch('bindings', []).first(5) },
        { 'name'=>'Gold', 'summary'=>'Immutable detailed results; intermediate, terminal and summary roles remain distinct', 'count'=>@details.size,
          'samples'=>@details.values.select { |d| %w[terminal summary].include?(d['role']) }.first(8) },
        { 'name'=>'Publications', 'summary'=>'Hourly and daily snapshots select the same component results; refreshes do not add new earnings', 'count'=>@run ? 2 : 0,
          'samples'=>@run ? %w[hour day].map do |grain|
            { 'grain'=>grain, 'published_bucket'=>grain == 'hour' ? @run.recorded_at.beginning_of_hour.iso8601 : @run.recorded_at.beginning_of_day.iso8601,
              'run_id'=>@run.external_id, 'service_period'=>@result['context']&.slice('service_start', 'service_end_exclusive'),
              'component_results'=>items(@case_id == 'advisor' ? %w[compensation coverage payable] : %w[charge rebate net]), 'semantics'=>'snapshot' }
          end : [] }
      ],
      'result'=>@result, 'exceptions'=>@result.fetch('exceptions', []),
      'publication'=>{ 'run_id'=>@run&.external_id, 'refresh_grains'=>%w[hour day],
        'rule'=>'Select retained results once per manifest. Refresh cadence does not create new accrual or change billing cadence.' }
    }
  end
end
