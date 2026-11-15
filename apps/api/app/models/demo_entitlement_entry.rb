class DemoEntitlementEntry < ApplicationRecord
  def readonly? = persisted?
end
