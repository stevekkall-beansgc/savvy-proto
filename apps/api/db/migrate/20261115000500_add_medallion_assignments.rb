class AddMedallionAssignments < ActiveRecord::Migration[8.0]
  def up
    add_column :medallion_evidence, :product_id, :string
    add_column :medallion_evidence, :starts_on, :date
    add_column :medallion_evidence, :ends_on, :date
    add_check_constraint :medallion_evidence, "kind <> 'assignment' OR (subject_id IS NOT NULL AND product_id IS NOT NULL AND starts_on IS NOT NULL AND (ends_on IS NULL OR starts_on < ends_on))", name: 'medallion_assignment_interval'
    execute <<~SQL
      ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_assignment_no_overlap
      EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, case_id WITH =, scenario_id WITH =, subject_id WITH =, product_id WITH =, daterange(starts_on,ends_on,'[)') WITH &&)
      WHERE (kind = 'assignment');
    SQL
  end
  def down
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_assignment_no_overlap'
    remove_check_constraint :medallion_evidence, name: 'medallion_assignment_interval'
    remove_column :medallion_evidence, :ends_on
    remove_column :medallion_evidence, :starts_on
    remove_column :medallion_evidence, :product_id
  end
end
