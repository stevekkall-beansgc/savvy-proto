class BillingAccountingFact < ApplicationRecord
  def readonly? = persisted?
end
