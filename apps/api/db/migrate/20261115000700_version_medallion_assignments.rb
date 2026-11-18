class VersionMedallionAssignments < ActiveRecord::Migration[8.0]
  def up
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_assignment_no_overlap'
    add_column :medallion_evidence, :schedule_version, :integer, null: false, default: 1
    add_check_constraint :medallion_evidence, 'schedule_version > 0', name: 'medallion_schedule_version'
    execute <<~SQL
      ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_assignment_no_overlap
      EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, case_id WITH =, scenario_id WITH =, schedule_version WITH =,
        subject_id WITH =, product_id WITH =, daterange(starts_on,ends_on,'[)') WITH &&)
      WHERE (kind = 'assignment');
    SQL
  end
  def down
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_assignment_no_overlap'
    remove_check_constraint :medallion_evidence, name: 'medallion_schedule_version'
    remove_column :medallion_evidence, :schedule_version
    execute <<~SQL
      ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_assignment_no_overlap
      EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, case_id WITH =, scenario_id WITH =,
        subject_id WITH =, product_id WITH =, daterange(starts_on,ends_on,'[)') WITH &&)
      WHERE (kind = 'assignment');
    SQL
  end
end
