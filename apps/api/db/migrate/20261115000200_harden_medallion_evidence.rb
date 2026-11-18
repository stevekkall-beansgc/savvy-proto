class HardenMedallionEvidence < ActiveRecord::Migration[8.0]
  def up
    add_column :medallion_evidence, :scenario_id, :string, null: false, default: 'baseline'
    remove_foreign_key :medallion_evidence, name: 'medallion_parent_scope'
    remove_index :medallion_evidence, name: 'medallion_version_identity'
    remove_index :medallion_evidence, name: 'medallion_scoped_id'
    add_index :medallion_evidence, %i[tenant_id entity_id case_id scenario_id kind external_id revision], unique: true, name: 'medallion_version_identity'
    add_index :medallion_evidence, %i[tenant_id entity_id case_id scenario_id id], unique: true, name: 'medallion_scoped_id'
    add_foreign_key :medallion_evidence, :medallion_evidence, column: %i[tenant_id entity_id case_id scenario_id parent_id], primary_key: %i[tenant_id entity_id case_id scenario_id id], name: 'medallion_parent_scope'
    add_check_constraint :medallion_evidence, "scenario_id ~ '^[a-zA-Z0-9_-]{1,100}$' AND jsonb_typeof(payload) = 'object'", name: 'medallion_scenario_body'
    execute <<~SQL
      CREATE FUNCTION medallion_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'medallion evidence is append-only'; END;
      $$;
      CREATE TRIGGER medallion_no_update_delete BEFORE UPDATE OR DELETE ON medallion_evidence FOR EACH ROW EXECUTE FUNCTION medallion_append_only();
    SQL
  end
  def down
    execute 'DROP TRIGGER medallion_no_update_delete ON medallion_evidence'
    execute 'DROP FUNCTION medallion_append_only()'
    remove_check_constraint :medallion_evidence, name: 'medallion_scenario_body'
    remove_foreign_key :medallion_evidence, name: 'medallion_parent_scope'
    remove_index :medallion_evidence, name: 'medallion_version_identity'
    remove_index :medallion_evidence, name: 'medallion_scoped_id'
    add_index :medallion_evidence, %i[tenant_id entity_id case_id kind external_id revision], unique: true, name: 'medallion_version_identity'
    add_index :medallion_evidence, %i[tenant_id entity_id case_id id], unique: true, name: 'medallion_scoped_id'
    add_foreign_key :medallion_evidence, :medallion_evidence, column: %i[tenant_id entity_id case_id parent_id], primary_key: %i[tenant_id entity_id case_id id], name: 'medallion_parent_scope'
    remove_column :medallion_evidence, :scenario_id
  end
end
