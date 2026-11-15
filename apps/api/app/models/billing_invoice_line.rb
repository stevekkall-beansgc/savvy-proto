class BillingInvoiceLine < ApplicationRecord
  def readonly? = persisted?
end
