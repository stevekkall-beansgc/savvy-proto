class MedallionEvidence < ApplicationRecord
  self.table_name = "medallion_evidence"
  def readonly? = persisted?
end
