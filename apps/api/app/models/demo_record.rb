class DemoRecord < ApplicationRecord
  validates :tenant_id, :entity_id, :kind, :external_id, :revision, :payload_hash, presence: true
  validates :synthetic, inclusion: { in: [true] }
  def readonly? = persisted?
end
