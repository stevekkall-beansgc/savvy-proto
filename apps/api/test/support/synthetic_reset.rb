# Test-only reset shared by the legacy and new domain suites. Discover demo tables
# so new scoped foreign keys cannot make an older suite leave evidence behind.
module SyntheticReset
  def self.call
    unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'advisor_economics_synthetic_test'
      raise 'Only the disposable synthetic test database may be reset'
    end
    connection = ActiveRecord::Base.connection
    tables = connection.select_values("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename NOT IN ('ar_internal_metadata','schema_migrations') ORDER BY tablename")
    raise 'No synthetic test tables found' if tables.empty?
    names = tables.map { |name| "public.#{connection.quote_table_name(name)}" }.join(', ')
    connection.execute("TRUNCATE TABLE #{names} RESTART IDENTITY CASCADE")
  end
end
