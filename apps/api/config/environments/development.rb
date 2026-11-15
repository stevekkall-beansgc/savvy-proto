Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true
  config.active_record.schema_format = :sql
end
