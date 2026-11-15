class DemoMatchReversal < ApplicationRecord
  def readonly? = persisted?
end
