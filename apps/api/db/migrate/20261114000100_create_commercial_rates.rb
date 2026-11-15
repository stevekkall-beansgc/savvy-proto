class CreateCommercialRates < ActiveRecord::Migration[8.0]
  def up
    enable_extension 'btree_gist'
    create_table :commercial_rates do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.string :configuration_id, null: false
      t.string :external_id, null: false
      t.string :broker_id, null: false
      t.string :component, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.integer :numerator, null: false
      t.integer :denominator, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      t.jsonb :selector, null: false, default: {}
      t.integer :signup_within_days
      t.integer :priority
      t.datetime :recorded_at, null: false
    end
    add_foreign_key :commercial_rates, :demo_scopes, column: %i[tenant_id entity_id], primary_key: %i[tenant_id entity_id]
    add_index :commercial_rates, %i[tenant_id entity_id configuration_id external_id], unique: true, name: 'commercial_rate_identity'
    add_check_constraint :commercial_rates, "component = 'advisor_share' AND kind IN ('standard','promotion','targeted_promotion') AND numerator >= 0 AND denominator BETWEEN 1 AND 1000000 AND numerator <= denominator AND (ends_on IS NULL OR starts_on < ends_on) AND (signup_within_days IS NULL OR signup_within_days BETWEEN 1 AND 365) AND jsonb_typeof(selector) = 'object'", name: 'valid_commercial_rate'
    execute <<~SQL
      ALTER TABLE commercial_rates ADD CONSTRAINT commercial_rate_no_overlap
      EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, configuration_id WITH =, broker_id WITH =, component WITH =, kind WITH =, daterange(starts_on, ends_on, '[)') WITH &&)
      WHERE (kind IN ('standard','promotion'));
      ALTER TABLE commercial_rates ADD CONSTRAINT commercial_target_no_overlap
      EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, configuration_id WITH =, broker_id WITH =, component WITH =, (selector::text) WITH =, (COALESCE(signup_within_days, 0)) WITH =, daterange(starts_on, ends_on, '[)') WITH &&)
      WHERE (kind = 'targeted_promotion');
    SQL
  end
  def down
    drop_table :commercial_rates
  end
end
