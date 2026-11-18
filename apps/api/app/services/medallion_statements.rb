# A statement selects engine results and cash applications; it never assesses
# fees. Additive graph boundaries provide its component explanation without a
# separate product calculator or a manually writable statement total.
class MedallionStatements
  def initialize(workbench)
    @workbench = workbench
    @service = workbench.medallion
  end

  def project(case_id, scenario, run, as_of: nil)
    cutoff = as_of || Time.current.iso8601(6)
    instant = @service.time!(cutoff)
    @service.error('FUTURE_EVIDENCE', 'The selected result was not known at this statement cutoff') if instant < @service.time!(run.payload.fetch('knowledge_cutoff'))
    output = case_id == 'advisor' ? 'payable' : 'net'
    _, owed = @service.obligation!(case_id, scenario, run.external_id, output)
    economic_key = @service.obligation_key(case_id, scenario, output)
    applications = @service.active_applications(case_id, scenario, as_of: cutoff).select { |a| a.payload['obligation_key'] == economic_key }
    applied = @service.assessed_sum(applications.map { |a| a.payload.fetch('amount_minor') })
    @service.error('ALLOCATION_EXCEEDED', 'Existing payments exceed this revised obligation') if applied > 0 && (owed < 0 || applied > owed)
    current_components = components(case_id, scenario, run, output)
    assert_total!(current_components.values.map { |c| c.fetch('signed_minor') }, owed)

    prior = @service.source(case_id, scenario, 'statement').where(status: 'sealed').where('recorded_at <= ?', @service.time!(cutoff))
      .where("payload->>'obligation_key' = ?", economic_key).order(:recorded_at, :id).last
    previous_components = {}
    previous_apps = []
    opening = 0
    if prior
      previous_run = @service.get!(case_id, scenario, 'run', prior.payload.fetch('run_id'))
      previous_components = prior.payload['component_values'] || components(case_id, scenario, previous_run, output)
      opening = Integer(prior.payload.fetch('balance_minor'), 10)
      previous_apps = prior.payload['application_refs'] || @service.active_applications(case_id, scenario,
        as_of: prior.payload['as_of'] || prior.recorded_at.iso8601(6)).select { |a| a.payload['obligation_key'] == economic_key }.map(&:external_id)
    end

    lines = []
    if prior
      lines << { 'label'=>'Opening balance', 'minor'=>opening.to_s, 'signed_minor'=>opening.to_s,
        'status'=>'sealed', 'statement_ref'=>prior.external_id, 'effect'=>'opening' }
    end
    (previous_components.keys | current_components.keys).sort.each do |key|
      current = current_components[key]
      previous = previous_components[key]
      delta = @service.assessed_difference(current ? Integer(current.fetch('signed_minor')) : 0,
        previous ? Integer(previous.fetch('signed_minor')) : 0)
      next if delta.zero?
      component = current || previous
      lines << { 'label'=>component.fetch('label') + (prior ? ' adjustment' : ''),
        'minor'=>delta.to_s, 'signed_minor'=>delta.to_s, 'status'=>'assessed',
        'effect'=>delta.negative? ? 'decrease' : 'increase',
        'economic_key'=>key, 'output_id'=>component.fetch('output_id'),
        'detail_refs'=>current ? current.fetch('detail_refs') : [], 'run_id'=>run.external_id,
        'original_detail_refs'=>previous ? previous.fetch('detail_refs') : [],
        'original_run_id'=>prior&.payload&.fetch('run_id', nil),
        'reason'=>prior ? 'Change from the retained statement result' : nil }
    end
    application_ids = applications.map(&:external_id)
    applications.reject { |a| previous_apps.include?(a.external_id) }.each do |application|
      decrease = @service.assessed_difference(0, application.payload.fetch('amount_minor'))
      lines << { 'label'=>'Payment applied', 'minor'=>decrease.to_s, 'signed_minor'=>decrease.to_s,
        'status'=>'confirmed', 'effect'=>'decrease', 'application_ref'=>application.external_id,
        'reason'=>application.payload['reason'] }
    end
    (previous_apps - application_ids).each do |id|
      original = @service.get!(case_id, scenario, 'application', id)
      lines << { 'label'=>'Payment application reversed', 'minor'=>original.payload.fetch('amount_minor').to_s,
        'signed_minor'=>original.payload.fetch('amount_minor').to_s, 'status'=>'reversed', 'effect'=>'increase',
        'application_ref'=>id, 'reason'=>'The prior application was reversed; this does not establish a cash refund.' }
    end
    balance = @service.assessed_difference(owed, applied)
    # Opening and linked differences must reconcile independently to the current
    # selected obligation less evidenced applications. No entered total is trusted.
    assert_total!(lines.map { |line| Integer(line.fetch('signed_minor')) }, balance)
    {
      'status'=>balance.negative? ? 'credit_balance' : 'preview', 'run_id'=>run.external_id, 'obligation_key'=>economic_key,
      'as_of'=>cutoff, 'currency'=>'USD', 'previous_statement_id'=>prior&.external_id,
      'opening_balance_minor'=>opening.to_s, 'before_payment_minor'=>owed.to_s,
      'application_refs'=>application_ids, 'component_values'=>current_components,
      'lines'=>lines, 'balance_minor'=>balance.to_s,
      'pending_items'=>pending_items(case_id, scenario, cutoff),
      'service_start'=>run.payload.dig('result', 'context', 'service_start'),
      'service_end_exclusive'=>run.payload.dig('result', 'context', 'service_end_exclusive')
    }
  end

  def seal(input, key)
    @workbench.guard!('finance')
    case_id = @service.case!(input.fetch('case_id'))
    scenario = @service.scenario!(input['scenario_id'])
    @workbench.operate('medallion_seal_statement', input, key) do
      run = @service.get!(case_id, scenario, 'run', input.fetch('run_id'))
      period = input.fetch('posting_period')
      @service.error('INVALID_DATE') unless period.is_a?(String) && period.match?(/\A\d{4}-\d{2}\z/)
      @service.date!(period + '-01')
      @service.error('PERIOD_LOCKED') if MedallionEvidence.where(**@workbench.scope, kind: 'period_lock').where("payload->>'posting_period' = ?", period).exists?
      latest = @service.source(case_id, scenario, 'run').where(status: 'completed').order(:id).last
      historical = input['historical_as_of']
      if historical
        instant = @service.time!(historical)
        @service.error('FUTURE_EVIDENCE') if instant > Time.current || instant < @service.time!(run.payload.fetch('knowledge_cutoff'))
      else
        @service.error('HASH_CHANGED', 'Select the latest result before retaining a statement') unless latest && latest.id == run.id
      end
      statement = project(case_id, scenario, run, as_of: historical).merge('status'=>'sealed',
        'posting_period'=>period, 'reason'=>@service.reason!(input['reason']), 'historical'=>!!historical)
      id = "statement-#{SecureRandom.uuid}"
      @service.store!(case_id, scenario, 'statement', id: id, status: 'sealed', payload: statement, parent: run)
      { 'id'=>id, 'statement'=>statement, 'synthetic'=>true, 'document_issued'=>false }
    end
  end

  private

  def pending_items(case_id, scenario, cutoff)
    known = @service.time!(cutoff)
    applications = @service.active_applications(case_id, scenario, as_of: cutoff)
    decisions = @service.source(case_id, scenario, 'event_review').where('recorded_at <= ?', known).order(:id).to_a.group_by(&:parent_id).transform_values(&:last)
    requests = @service.source(case_id, scenario, 'event').where('recorded_at <= ?', known)
      .select { |row| row.payload['kind'] == 'payout_request' }.group_by(&:external_id).values.map { |versions| versions.max_by(&:revision) }.map do |row|
      next if decisions[row.id]&.status == 'rejected'
      { 'label'=>'Payout requested', 'minor'=>row.payload.fetch('amount_minor').to_s,
        'status'=>decisions[row.id]&.status == 'approved' ? 'requested' : 'pending_review', 'reason'=>row.payload['reason'], 'event_ref'=>row.external_id }
    end.compact
    payments = @service.source(case_id, scenario, 'payment').where('recorded_at <= ?', known).filter_map do |row|
      used = @service.assessed_sum(applications.select { |a| a.parent_id == row.id }.map { |a| a.payload.fetch('amount_minor') })
      unapplied = @service.assessed_difference(row.payload.fetch('amount_minor'), used)
      next unless unapplied > 0
      { 'label'=>row.status == 'confirmed' ? 'Payment awaiting allocation' : 'Payment awaiting confirmation',
        'minor'=>unapplied.to_s, 'status'=>row.status == 'confirmed' ? 'unapplied' : 'pending',
        'payment_ref'=>row.external_id }
    end
    requests + payments
  end

  def assert_total!(amounts, expected)
    @service.error('STATEMENT_CONSERVATION', 'Statement components do not reconcile to the selected engine result') unless @service.assessed_sum(amounts) == expected
  end

  def components(case_id, scenario, run, output)
    policy = @service.get!(case_id, scenario, 'policy', run.payload.fetch('policy_id'))
    nodes = policy.payload.fetch('policy').fetch('nodes').index_by { |node| node.fetch('id') }
    details = run.payload.fetch('result').fetch('details').index_by { |detail| detail.fetch('id') }
    entries = []
    visit = lambda do |id, sign, path|
      @service.error('GRAPH_CYCLE') if path.include?(id) || path.size >= 128
      node = nodes.fetch(id)
      boundary = id != output && node['role'] == 'terminal'
      if !boundary && node['op'] == 'add'
        node.fetch('inputs').each { |child| visit.call(child, sign, path + [id]) }
      elsif !boundary && %w[subtract net].include?(node['op'])
        visit.call(node.fetch('left'), sign, path + [id])
        visit.call(node.fetch('right'), sign == '+' ? '-' : '+', path + [id])
      else
        detail = details.fetch(id)
        amount = detail['assessed_minor']
        @service.error('INCOMPLETE_SOURCE') unless detail['unit'] == 'USD_minor' && amount.is_a?(Integer)
        amount = @service.assessed_difference(0, amount) if sign == '-'
        entries << { 'economic_key'=>detail.fetch('economic_key'), 'output_id'=>id,
          'label'=>MedallionPresenter::LABELS.fetch(id, id.tr('_', ' ').capitalize),
          'signed_minor'=>amount.to_s, 'detail_refs'=>[id] }
      end
    end
    visit.call(output, '+', [])
    entries.group_by { |entry| entry.fetch('economic_key') }.transform_values do |group|
      group.first.merge('signed_minor'=>@service.assessed_sum(group.map { |entry| Integer(entry.fetch('signed_minor')) }).to_s,
        'detail_refs'=>group.flat_map { |entry| entry.fetch('detail_refs') }.uniq)
    end
  end
end
