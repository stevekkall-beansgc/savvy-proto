# A visitor gets a fresh synthetic tenant. Persist only the hash of its bearer token.
class DemoSession
  HOURS = 24
  PREFIX = 'visitor-'.freeze
  OPEN = 'demo_session_open'.freeze
  CLOSED = 'demo_session_closed'.freeze
  PROVISIONING_LOCK = 7_522_905_137

  def initialize(token)
    @token = token
  end

  def workspace(role: 'operator')
    return unless @token.is_a?(String) && @token.match?(/\A[0-9a-f]{64}\z/)
    Workbench.new(role: role, tenant: PREFIX + Digest::SHA256.hexdigest(@token))
  end

  def active?(workbench = workspace)
    return false unless workbench
    records = DemoOperation.where(**workbench.scope)
    records.where(operation: OPEN, created_at: HOURS.hours.ago..).exists? &&
      !records.where(operation: CLOSED).exists?
  end

  def start
    return @token if active?
    DemoScope.transaction do
      connection = DemoScope.connection
      unless connection.select_value("SELECT pg_try_advisory_xact_lock(#{PROVISIONING_LOCK})")
        raise Economics::Error.new('DEMO_BUSY', 'Another workspace is starting. Try again in a moment.')
      end
      limit = ENV.fetch('SAVVY_DEMO_WORKSPACE_LIMIT', '200').to_i.clamp(1, 2000)
      if DemoScope.where('tenant_id LIKE ?', PREFIX + '%').count >= limit
        raise Economics::Error.new('DEMO_CAPACITY', 'The demo has reached its workspace limit. You can still explore the examples.')
      end
      @token = SecureRandom.hex(32)
      workbench = workspace
      DemoPresentationSeed.call(workbench)
      BillingPlatformSeed.call(workbench)
      BillingClosureSeed.call(workbench)
      workbench.operate(OPEN, {}, OPEN) { { 'synthetic' => true } }
      @token
    end
  end

  def close
    workbench = workspace
    return unless active?(workbench)
    workbench.operate(CLOSED, {}, CLOSED) { { 'closed' => true } }
  end
end
