class AddBillingCalculationAttempts < ActiveRecord::Migration[8.0]
  def up
    old=select_value("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='medallion_evidence'::regclass AND conname='medallion_evidence_kind'").delete_prefix('CHECK ')
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_evidence_kind'
    execute "ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_evidence_kind CHECK (#{old} OR (scenario_id='billing_platform' AND kind='calculation_attempt'))"
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Retain failed calculation evidence'
  end
end
