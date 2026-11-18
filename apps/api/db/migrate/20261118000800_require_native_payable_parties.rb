class RequireNativePayableParties < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :billing_instructions,"external_id NOT LIKE 'bp-payable-%' OR (debtor_id IS NOT NULL AND creditor_id IS NOT NULL AND debtor_id<>creditor_id AND billing_case_id IS NOT NULL AND billing_subject_id IS NOT NULL AND currency IS NOT NULL AND calculation_ref IS NOT NULL AND posting_period IS NOT NULL)",name:'native_payable_required_metadata'
  end
end
