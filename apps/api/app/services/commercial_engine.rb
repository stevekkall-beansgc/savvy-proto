# Adapter preserves the existing allocation, coverage and guarantee engine while
# selecting the typed commercial terms on service date.
class CommercialEngine < Economics::Engine
  def validate_policy!(policy)
    scope!(policy, policy)
    raise Economics::Error.new('SYNTHETIC_ONLY') unless policy['synthetic'] == true
    true
  end

  def select_rate(rules, fact, date:, cutoff:)
    day=date!(date)
    eligible=rules.select do |r|
      next false unless r['broker_id']==fact['broker_id'] && r['component']==fact['component'] && date!(r['starts_on'])<=day && (!r['ends_on'] || day<date!(r['ends_on']))
      next false unless r['selector'].all? { |key,value| fact.fetch('dimensions',{})[key]==value }
      if r['signup_within_days']
        signup=fact['signup_date']
        raise Economics::Error.new('MISSING_SIGNUP_DATE','Signup date is required for a potentially applicable promotion') unless signup
        start=date!(signup)
        next false unless start<=day && day<start+r['signup_within_days']
      end
      true
    end
    targeted=eligible.select { |r| r['kind']=='targeted_promotion' }
    pool=targeted.any? ? targeted : (eligible.select { |r| r['kind']=='promotion' }.presence || eligible.select { |r| r['kind']=='standard' })
    raise Economics::Error.new('UNRESOLVED_MAPPING','No effective commercial rate') if pool.empty?
    if pool.size>1
      raise Economics::Error.new('RULE_CONFLICT') if pool.any? { |r| r['priority'].nil? }
      max=pool.map { |r| r['priority'] }.max
      pool=pool.select { |r| r['priority']==max }
    end
    raise Economics::Error.new('RULE_CONFLICT') unless pool.one?
    winner=pool.first
    { 'rate'=>Rational(winner['numerator'],winner['denominator']), 'winner'=>winner['id'], 'candidates'=>eligible.map { |r| r['id'] }.sort,
      'reason'=>"#{winner['kind']} replacement", 'date'=>date,'numerator'=>winner['numerator'],'denominator'=>winner['denominator'] }
  end
end
