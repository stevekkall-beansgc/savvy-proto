require 'date'
require 'time'

# Select complete, scoped fictional source observations before invoking the
# shared interpreter. This adapter does not calculate fees or average values.
class DisclosureSources
  def self.error(code, message = code)
    raise Economics::Error.new(code, message)
  end

  def self.memberships!(memberships:, service_start:, service_end_exclusive:, cutoff:, group_id:)
    start=Date.iso8601(service_start); finish=Date.iso8601(service_end_exclusive); known=Time.iso8601(cutoff)
    error('INVALID_INTERVAL') unless start < finish
    error('INVALID_SOURCE') unless memberships.is_a?(Array) && memberships.any?
    identities={}
    memberships.each do |row|
      error('INVALID_SOURCE') unless row.is_a?(Hash) && row['id'].is_a?(String) && row['membership_id'].is_a?(String) && row['revision'].is_a?(Integer) && row['revision']>0
      error('SCOPE_MISMATCH') unless row['group_id']==group_id
      from=Date.iso8601(row.fetch('effective_from')); to=Date.iso8601(row.fetch('effective_to'))
      error('INVALID_INTERVAL') unless from<to
      Time.iso8601(row.fetch('recorded_at'))
      identity=[row['membership_id'],row['revision']]; error('DUPLICATE_SOURCE') if identities[identity]; identities[identity]=true
    end
    known_rows=memberships.select { |row| Time.iso8601(row['recorded_at']) <= known }.group_by { |row| row['membership_id'] }.values.map { |rows| rows.max_by { |row| row['revision'] } }
    active=known_rows.select { |row| Date.iso8601(row['effective_from'])<finish && start<Date.iso8601(row['effective_to']) }
    error('INCOMPLETE_SOURCE') if active.empty?
    error('RULE_CONFLICT','Overlapping membership for one account') unless active.map { |row| row['id'] }.uniq.size==active.size
    error('INCOMPLETE_SOURCE','Membership must cover the service interval') unless active.all? { |row| Date.iso8601(row['effective_from'])<=start && finish<=Date.iso8601(row['effective_to']) }
    active
  rescue KeyError,ArgumentError,TypeError
    error('INVALID_SOURCE','Invalid membership interval or clock')
  end

  def self.select(observations:, members:, holdings:, dates:, cutoff:, tenant_id:, entity_id:, currency: 'USD')
    known = Time.iso8601(cutoff)
    error('INVALID_INTERVAL') unless dates.is_a?(Array) && dates.any? && dates.uniq == dates && dates.all? { |d| Date.iso8601(d).iso8601 == d }
    error('INVALID_SOURCE') unless members.is_a?(Array) && members.any? && members.uniq == members && observations.is_a?(Array)
    error('INVALID_SOURCE') unless holdings.is_a?(Hash) && holdings.keys.sort == members.sort && holdings.values.all? { |ids| ids.is_a?(Array) && ids.any? && ids.uniq == ids }
    identities = {}
    observations.each do |o|
      error('INVALID_SOURCE') unless o.is_a?(Hash) && o['id'].is_a?(String) && o['revision'].is_a?(Integer) && o['revision'] > 0
      identity = [o['id'], o['revision']]
      error('DUPLICATE_SOURCE') if identities.key?(identity)
      identities[identity] = true
      error('SCOPE_MISMATCH') unless o['tenant_id'] == tenant_id && o['entity_id'] == entity_id && o['currency'] == currency && members.include?(o['member_id']) && holdings.fetch(o['member_id']).include?(o['holding_id'])
      error('INVALID_SOURCE') unless o['amount_minor'].is_a?(Integer) && o['amount_minor'] >= 0 && [true, false].include?(o['eligible'])
      Date.iso8601(o.fetch('date')); Time.iso8601(o.fetch('recorded_at'))
    end
    candidates = observations.select { |o| Time.iso8601(o['recorded_at']) <= known }
    candidates.group_by { |o| o['id'] }.each_value do |versions|
      error('SOURCE_CONFLICT', 'A source identity cannot move between members or holdings') unless versions.map { |o| [o['member_id'], o['holding_id']] }.uniq.one?
    end
    # A revision replaces the same source identity only. Independent sources for
    # the same holding and date are ambiguous and must never be silently summed.
    latest = candidates.group_by { |o| o['id'] }.values.map { |rows| rows.max_by { |o| o['revision'] } }.select { |o| dates.include?(o['date']) }
    slots = latest.group_by { |o| [o['date'], o['member_id'], o.fetch('holding_id')] }
    error('SOURCE_CONFLICT', 'Multiple observations claim the same holding') if slots.any? { |_k, rows| rows.size != 1 }
    dates.product(members).each do |date, member|
      holdings.fetch(member).each do |holding|
        error('INCOMPLETE_SOURCE', "Missing observation for #{member}/#{holding} on #{date}") unless slots.key?([date, member, holding])
      end
    end
    latest.sort_by { |o| [o['date'], o['member_id'], o['holding_id'], o['id']] }
  rescue KeyError, ArgumentError, TypeError
    error('INVALID_SOURCE', 'Invalid source identity, clock, or date')
  end
end
