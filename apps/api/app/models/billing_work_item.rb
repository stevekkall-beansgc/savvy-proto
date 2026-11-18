# Mutable operational queue state. Attempts/results are retained separately as
# append-only evidence; the queue row is not a commercial or statement ledger.
class BillingWorkItem < ApplicationRecord
end
