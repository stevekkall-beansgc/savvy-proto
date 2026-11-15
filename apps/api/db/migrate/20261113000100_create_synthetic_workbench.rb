class CreateSyntheticWorkbench < ActiveRecord::Migration[8.0]
  def change
    create_table :demo_scopes do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.boolean :synthetic, null: false, default: true
    end
    add_index :demo_scopes, %i[tenant_id entity_id], unique: true
    add_check_constraint :demo_scopes, 'synthetic = true', name: 'synthetic_only_scope'
    create_table :demo_records do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.string :kind, null: false
      t.string :external_id, null: false
      t.integer :revision, null: false
      t.boolean :synthetic, null: false, default: true
      t.string :payload_hash, null: false
      t.jsonb :payload, null: false
      t.datetime :recorded_at, null: false
    end
    add_index :demo_records, %i[tenant_id entity_id kind external_id revision], unique: true, name: 'unique_synthetic_revision'
    add_index :demo_records, %i[tenant_id entity_id kind recorded_at], name: 'synthetic_scope_history'
    add_check_constraint :demo_records, 'synthetic = true AND revision > 0', name: 'synthetic_only_records'
    create_table :demo_operations do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.string :actor_id, null: false
      t.string :operation, null: false
      t.string :idempotency_key, null: false
      t.string :request_hash, null: false
      t.jsonb :result, null: false
      t.datetime :created_at, null: false
    end
    add_index :demo_operations, %i[tenant_id entity_id actor_id operation idempotency_key], unique: true, name: 'scoped_operation_idempotency'
    create_table :demo_allocations do |t|
      t.string :tenant_id, null: false
      t.string :entity_id, null: false
      t.string :kind, null: false
      t.string :source_id, null: false
      t.string :target_id, null: false
      t.string :currency, null: false, default: 'USD'
      t.bigint :minor_units, null: false
      t.string :idempotency_key, null: false
      t.datetime :created_at, null: false
    end
    %i[demo_records demo_operations demo_allocations].each do |table|
      add_foreign_key table, :demo_scopes, column: %i[tenant_id entity_id], primary_key: %i[tenant_id entity_id]
    end
    add_check_constraint :demo_allocations, "minor_units > 0 AND currency = 'USD'", name: 'positive_usd_allocation'
    add_index :demo_allocations, %i[tenant_id entity_id kind idempotency_key], unique: true, name: 'unique_allocation_request'
    add_index :demo_allocations, %i[tenant_id entity_id kind source_id], name: 'allocation_source_scope'
  end
end
