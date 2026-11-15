require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "active_job/railtie"
require "active_record/tasks/database_tasks"
Bundler.require(*Rails.groups)
ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = %w[--exclude-schema=analytics --exclude-schema=raw_demo]
module AdvisorEconomics
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.eager_load_paths << root.join("app/domains")
    config.eager_load_paths << root.join("app/graphql")
    config.active_job.queue_adapter = :inline # Manual synchronous demo only.
    # SQL preserves the billing conservation triggers and temporal exclusions.
    # Analytics is rebuilt separately by its read-only source bootstrap and dbt.
    config.active_record.schema_format = :sql
    config.active_record.dump_schemas = :all
    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "synthetic-loopback-only-" * 4)
    config.hosts = ["localhost", "127.0.0.1", "[::1]"]
  end
end
