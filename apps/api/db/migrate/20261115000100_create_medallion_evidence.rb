class CreateMedallionEvidence < ActiveRecord::Migration[8.0]
  def change
    create_table :medallion_evidence do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.string :case_id, null: false
      t.string :kind, null: false
      t.string :external_id, null: false
      t.integer :revision, null: false, default: 1
      t.string :status, null: false
      t.string :subject_id
      t.bigint :parent_id
      t.string :payload_hash, null: false
      t.jsonb :payload, null: false, default: {}
      t.binary :original_bytes
      t.datetime :recorded_at, null: false
    end
    add_index :medallion_evidence, %i[tenant_id entity_id case_id kind external_id revision], unique: true, name: 'medallion_version_identity'
    add_index :medallion_evidence, %i[tenant_id entity_id case_id id], unique: true, name: 'medallion_scoped_id'
    add_index :medallion_evidence, %i[tenant_id entity_id case_id kind recorded_at], name: 'medallion_history'
    add_foreign_key :medallion_evidence, :demo_scopes, column: %i[tenant_id entity_id], primary_key: %i[tenant_id entity_id]
    add_foreign_key :medallion_evidence, :medallion_evidence, column: %i[tenant_id entity_id case_id parent_id], primary_key: %i[tenant_id entity_id case_id id], name: 'medallion_parent_scope'
    add_check_constraint :medallion_evidence, "revision > 0 AND length(payload_hash)=64 AND case_id IN ('advisor','ria')", name: 'medallion_scope_contract'
    add_check_constraint :medallion_evidence, "kind IN ('artifact','delivery','fact','policy','assignment','comparison','review','publication','event','event_review','payment','application','application_reversal','run','statement','period_lock')", name: 'medallion_evidence_kind'
    add_check_constraint :medallion_evidence, "status IN ('retained','accepted','draft','approved','rejected','published','confirmed','pending','reversed','completed','blocked','sealed','locked')", name: 'medallion_evidence_status'
    add_check_constraint :medallion_evidence, "(kind = 'artifact' AND original_bytes IS NOT NULL) OR (kind <> 'artifact' AND original_bytes IS NULL)", name: 'medallion_original_bytes'
    add_column :commercial_rates, :unit, :string, null: false, default: 'ratio'
    add_column :commercial_rates, :payer_id, :string
    add_column :commercial_rates, :payee_id, :string
    add_column :commercial_rates, :commercial_group, :string
    remove_check_constraint :commercial_rates, name: 'valid_commercial_rate'
    add_check_constraint :commercial_rates, "length(component)>0 AND kind IN ('standard','promotion','targeted_promotion') AND numerator >= 0 AND denominator BETWEEN 1 AND 1000000 AND (unit <> 'ratio' OR numerator <= denominator) AND unit IN ('ratio','USD_minor','unit_price') AND (ends_on IS NULL OR starts_on < ends_on) AND (signup_within_days IS NULL OR signup_within_days BETWEEN 1 AND 365) AND jsonb_typeof(selector) = 'object'", name: 'valid_commercial_rate_v2'
  end
end
