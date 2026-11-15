class BillingInvoice < ApplicationRecord
  def readonly? = persisted?
end
