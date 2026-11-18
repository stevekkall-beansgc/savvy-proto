class AllowNativeBillingWithoutLegacyIds < ActiveRecord::Migration[8.0]
  def up
    change_column_null :billing_invoices,:legacy_invoice_id,true
    change_column_null :billing_obligations,:legacy_charge_id,true
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Restore the prior snapshot; do not invent legacy billing IDs'
  end
end
