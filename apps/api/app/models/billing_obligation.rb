class BillingObligation < ApplicationRecord
  def readonly? = persisted?
end
