class DemoOperation < ApplicationRecord
  validates :tenant_id, :actor_id, :operation, :idempotency_key, :request_hash, presence: true
end
