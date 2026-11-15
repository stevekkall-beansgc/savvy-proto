class BillingInstructionItem < ApplicationRecord
  def readonly? = persisted?
end
