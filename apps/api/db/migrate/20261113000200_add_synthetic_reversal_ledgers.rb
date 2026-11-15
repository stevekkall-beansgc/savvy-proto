class AddSyntheticReversalLedgers < ActiveRecord::Migration[8.0]
  def change
    create_table :demo_entitlement_entries do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.string :grant_id, null: false
      t.string :obligation_id, null: false
      t.string :kind, null: false
      t.bigint :minor_units, null: false
      t.string :currency, null: false, default: 'USD'
      t.bigint :original_entry_id
      t.string :actor_id, null: false
      t.string :reason, null: false
      t.date :business_date, null: false
      t.datetime :created_at, null: false
    end
    add_index :demo_entitlement_entries, %i[tenant_id entity_id id], unique: true, name: 'entitlement_scoped_id'
    add_index :demo_entitlement_entries, %i[tenant_id entity_id grant_id], name: 'entitlement_grant_scope'
    add_index :demo_entitlement_entries, :original_entry_id, unique: true, where: "kind = 'reversal'", name: 'one_entitlement_reversal'
    add_foreign_key :demo_entitlement_entries, :demo_scopes, column: %i[tenant_id entity_id], primary_key: %i[tenant_id entity_id]
    add_foreign_key :demo_entitlement_entries, :demo_entitlement_entries, column: %i[tenant_id entity_id original_entry_id], primary_key: %i[tenant_id entity_id id], name: 'entitlement_reversal_same_scope'
    add_check_constraint :demo_entitlement_entries, "minor_units > 0 AND currency = 'USD'", name: 'positive_entitlement_usd'
    add_check_constraint :demo_entitlement_entries, "(kind = 'consume' AND original_entry_id IS NULL) OR (kind = 'reversal' AND original_entry_id IS NOT NULL)", name: 'entitlement_entry_kind'
    create_table :demo_match_reversals do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.bigint :allocation_id, null: false
      t.string :actor_id, null: false
      t.string :reason, null: false
      t.datetime :created_at, null: false
    end
    add_index :demo_allocations, %i[tenant_id entity_id id], unique: true, name: 'allocation_scoped_id'
    add_index :demo_match_reversals, :allocation_id, unique: true
    add_foreign_key :demo_match_reversals, :demo_allocations, column: %i[tenant_id entity_id allocation_id], primary_key: %i[tenant_id entity_id id], name: 'match_reversal_same_scope'
    add_foreign_key :demo_match_reversals, :demo_scopes, column: %i[tenant_id entity_id], primary_key: %i[tenant_id entity_id]
  end
end
