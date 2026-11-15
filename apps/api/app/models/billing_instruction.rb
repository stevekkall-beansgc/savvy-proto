class BillingInstruction < ApplicationRecord
  def readonly? = persisted?
end
