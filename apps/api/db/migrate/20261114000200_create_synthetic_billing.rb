class CreateSyntheticBilling < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_obligations do |t|
      t.string :tenant_id, null: false; t.string :entity_id, null: false
      t.string :external_id, null: false; t.integer :revision, null: false
      t.string :customer_id, null: false; t.string :service_id, null: false; t.string :broker_id, null: false
      t.string :account_id, null: false; t.string :assignment_id, null: false
      t.string :client_terms_ref, null: false; t.string :source_id, null: false; t.integer :source_revision, null: false
      t.string :legacy_charge_id, null: false; t.string :route, null: false; t.string :currency, null: false
      t.bigint :amount_minor, null: false; t.date :service_period_start, null: false; t.date :service_period_end, null: false
    end
    create_table :billing_invoices do |t|
      t.string :tenant_id, null: false; t.string :entity_id, null: false; t.string :external_id, null: false
      t.integer :revision, null: false; t.string :debtor_id, null: false; t.bigint :amount_minor, null: false
      t.string :currency, null: false; t.string :status, null: false; t.string :legacy_invoice_id, null: false
    end
    create_table :billing_invoice_lines do |t|
      t.string :tenant_id, null: false; t.string :entity_id, null: false; t.string :external_id, null: false
      t.bigint :billing_invoice_id, null: false; t.bigint :billing_obligation_id, null: false; t.bigint :amount_minor, null: false
    end
    create_table :billing_instructions do |t|
      t.string :tenant_id, null: false; t.string :entity_id, null: false; t.string :external_id, null: false
      t.integer :revision, null: false; t.bigint :amount_minor, null: false; t.string :status, null: false; t.string :execution_status
    end
    create_table :billing_instruction_items do |t|
      t.string :tenant_id, null: false; t.string :entity_id, null: false
      t.bigint :billing_instruction_id, null: false; t.bigint :billing_obligation_id, null: false; t.bigint :amount_minor, null: false
    end
    create_table :billing_accounting_facts do |t|
      t.string :tenant_id, null: false; t.string :entity_id, null: false; t.string :external_id, null: false
      t.bigint :billing_invoice_id; t.bigint :billing_instruction_id; t.integer :commercial_revision, null: false
      t.string :reported_status; t.bigint :applied_minor; t.bigint :ar_minor; t.bigint :recognized_minor
      t.datetime :observed_at, null: false; t.boolean :mocked, default: true, null: false
    end
    %i[billing_obligations billing_invoices billing_invoice_lines billing_instructions billing_instruction_items billing_accounting_facts].each do |table|
      add_index table, [:tenant_id, :entity_id, :id], unique: true, name: "#{table}_scoped_pk"
      add_foreign_key table, :demo_scopes, column: [:tenant_id, :entity_id], primary_key: [:tenant_id, :entity_id]
    end
    %i[billing_obligations billing_invoices billing_invoice_lines billing_instructions billing_accounting_facts].each do |table|
      add_index table, [:tenant_id, :entity_id, :external_id], unique: true, name: "#{table}_scoped_external"
    end
    [[:billing_invoice_lines,:billing_invoices,:billing_invoice_id], [:billing_invoice_lines,:billing_obligations,:billing_obligation_id],
     [:billing_instruction_items,:billing_instructions,:billing_instruction_id], [:billing_instruction_items,:billing_obligations,:billing_obligation_id],
     [:billing_accounting_facts,:billing_invoices,:billing_invoice_id], [:billing_accounting_facts,:billing_instructions,:billing_instruction_id]].each do |from,to,column|
      add_foreign_key from, to, column: [:tenant_id,:entity_id,column], primary_key: [:tenant_id,:entity_id,:id], name: "fk_#{from}_#{column}"
    end
    add_index :billing_invoice_lines, [:tenant_id,:entity_id,:billing_obligation_id], unique: true, name: 'one_invoice_line_per_obligation'
    add_index :billing_instruction_items, [:tenant_id,:entity_id,:billing_obligation_id], unique: true, name: 'one_instruction_item_per_obligation'
    add_check_constraint :billing_obligations, "amount_minor > 0 AND currency = 'USD' AND revision > 0 AND source_revision > 0 AND service_period_start < service_period_end AND route IN ('invoice','custodial')", name: 'billing_obligation_values'
    add_check_constraint :billing_invoices, "amount_minor > 0 AND currency = 'USD' AND revision > 0", name: 'billing_invoice_values'
    add_check_constraint :billing_invoice_lines, 'amount_minor > 0', name: 'billing_line_positive'
    add_check_constraint :billing_instructions, 'amount_minor > 0 AND revision > 0', name: 'billing_instruction_values'
    add_check_constraint :billing_instruction_items, 'amount_minor > 0', name: 'billing_item_positive'
    add_check_constraint :billing_accounting_facts, "mocked AND commercial_revision > 0 AND ((billing_invoice_id IS NULL) <> (billing_instruction_id IS NULL)) AND (applied_minor IS NULL OR applied_minor >= 0) AND (ar_minor IS NULL OR ar_minor >= 0) AND (recognized_minor IS NULL OR recognized_minor >= 0)", name: 'billing_accounting_mock_values'
    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE FUNCTION validate_synthetic_billing_conservation() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF EXISTS (SELECT 1 FROM billing_invoices h LEFT JOIN billing_invoice_lines l ON l.tenant_id=h.tenant_id AND l.entity_id=h.entity_id AND l.billing_invoice_id=h.id GROUP BY h.id HAVING count(l.id)=0 OR coalesce(sum(l.amount_minor),0) <> h.amount_minor)
              OR EXISTS (SELECT 1 FROM billing_instructions h LEFT JOIN billing_instruction_items i ON i.tenant_id=h.tenant_id AND i.entity_id=h.entity_id AND i.billing_instruction_id=h.id GROUP BY h.id HAVING count(i.id)=0 OR coalesce(sum(i.amount_minor),0) <> h.amount_minor)
              OR EXISTS (SELECT 1 FROM billing_invoice_lines l JOIN billing_obligations o ON o.tenant_id=l.tenant_id AND o.entity_id=l.entity_id AND o.id=l.billing_obligation_id JOIN billing_invoices h ON h.tenant_id=l.tenant_id AND h.entity_id=l.entity_id AND h.id=l.billing_invoice_id WHERE o.route <> 'invoice' OR o.amount_minor <> l.amount_minor OR o.currency <> h.currency)
              OR EXISTS (SELECT 1 FROM billing_instruction_items i JOIN billing_obligations o ON o.tenant_id=i.tenant_id AND o.entity_id=i.entity_id AND o.id=i.billing_obligation_id WHERE o.route <> 'custodial' OR o.amount_minor <> i.amount_minor)
              OR EXISTS (SELECT 1 FROM billing_obligations o WHERE (o.route='invoice' AND NOT EXISTS (SELECT 1 FROM billing_invoice_lines l WHERE l.tenant_id=o.tenant_id AND l.entity_id=o.entity_id AND l.billing_obligation_id=o.id)) OR (o.route='custodial' AND NOT EXISTS (SELECT 1 FROM billing_instruction_items i WHERE i.tenant_id=o.tenant_id AND i.entity_id=o.entity_id AND i.billing_obligation_id=o.id)))
            THEN RAISE EXCEPTION 'Synthetic billing conservation violated' USING ERRCODE='23514'; END IF;
            RETURN NULL;
          END $$;
        SQL
        %w[billing_obligations billing_invoices billing_invoice_lines billing_instructions billing_instruction_items].each do |table|
          execute "CREATE CONSTRAINT TRIGGER #{table}_conservation AFTER INSERT OR UPDATE OR DELETE ON #{table} DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_synthetic_billing_conservation()"
        end
      end
      direction.down do
        %w[billing_obligations billing_invoices billing_invoice_lines billing_instructions billing_instruction_items].each do |table|
          execute "DROP TRIGGER IF EXISTS #{table}_conservation ON #{table}"
        end
        execute 'DROP FUNCTION IF EXISTS validate_synthetic_billing_conservation()'
      end
    end
  end
end
