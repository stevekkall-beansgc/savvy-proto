Rails.application.configure do
  config.eager_load = ENV["SAVVY_IMMUTABLE_PREVIEW"] == "1"
  config.enable_reloading = ENV["SAVVY_IMMUTABLE_PREVIEW"] != "1"
  if ENV["SAVVY_IMMUTABLE_PREVIEW"] == "1"
    config.logger = ActiveSupport::Logger.new($stdout)
    config.cache_store = :memory_store
  end
  config.consider_all_requests_local = true
  config.active_record.schema_format = :sql
end
