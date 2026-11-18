class CompleteBillingLifecycle < ActiveRecord::Migration[8.0]
  def up
    definition=select_value("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='medallion_evidence_kind'").delete_prefix('CHECK (').delete_suffix(')')
    execute 'ALTER TABLE medallion_evidence DROP CONSTRAINT medallion_evidence_kind'
    kinds=%w[cash_application cash_reversal refund_request accounting_package accounting_acceptance payable payable_review payable_issue work_attempt billing_batch]
    execute "ALTER TABLE medallion_evidence ADD CONSTRAINT medallion_evidence_kind CHECK ((#{definition}) OR (scenario_id='billing_platform' AND kind IN (#{kinds.map { |k| connection.quote(k) }.join(',')})))"
    create_table :billing_work_items do |t|
      t.string :tenant_id,:entity_id,:case_id,:job_id,:job_class,:status,null:false
      t.jsonb :job_data,null:false
      t.jsonb :result,null:false,default:{}
      t.integer :attempts,null:false,default:0
      t.integer :max_attempts,null:false,default:3
      t.datetime :run_at,null:false
      t.datetime :leased_until
      t.string :lease_token,:batch_id,:last_error
      t.timestamps
    end
    add_index :billing_work_items,:job_id,unique:true
    add_index :billing_work_items,[:status,:run_at,:leased_until],name:'billing_work_ready'
    add_index :billing_work_items,[:tenant_id,:entity_id,:case_id,:batch_id],name:'billing_work_scope_batch'
    add_check_constraint :billing_work_items,"status IN ('queued','running','completed','quarantined','failed') AND attempts>=0 AND max_attempts BETWEEN 1 AND 10 AND case_id IN ('advisor','ria')",name:'billing_work_state'
    %i[debtor_id creditor_id billing_case_id billing_subject_id currency calculation_ref posting_period].each { |name| add_column :billing_instructions,name,:string }
    add_column :billing_instructions,:corrects_instruction_id,:bigint
    add_foreign_key :billing_instructions,:billing_instructions,column: :corrects_instruction_id
    execute <<~SQL
      CREATE TRIGGER billing_instructions_append_only BEFORE DELETE OR UPDATE ON billing_instructions FOR EACH ROW EXECUTE FUNCTION native_billing_append_only();
      CREATE TRIGGER billing_instruction_items_append_only BEFORE DELETE OR UPDATE ON billing_instruction_items FOR EACH ROW EXECUTE FUNCTION native_billing_append_only();
      CREATE OR REPLACE FUNCTION validate_billing_document() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE original billing_invoices%ROWTYPE;
      BEGIN
        IF NEW.external_id LIKE 'bp-doc-%' THEN
          IF NEW.billing_case_id IS NULL OR NEW.billing_case_id NOT IN ('advisor','ria') OR NEW.billing_subject_id IS NULL OR length(NEW.billing_subject_id)=0 OR NEW.calculation_ref IS NULL OR NEW.issued_on IS NULL OR NEW.posting_period IS NULL OR NEW.posting_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR NEW.debtor_id=NEW.creditor_id OR (NEW.due_on IS NOT NULL AND NEW.due_on<NEW.issued_on) THEN RAISE EXCEPTION 'Invalid native document metadata'; END IF;
          IF (NEW.document_type='credit_note' AND (NEW.debtor_id<>'firm-demo' OR NEW.creditor_id<>NEW.billing_subject_id)) OR (NEW.document_type<>'credit_note' AND (NEW.debtor_id<>NEW.billing_subject_id OR NEW.creditor_id<>'firm-demo')) THEN RAISE EXCEPTION 'Invalid native direction'; END IF;
          IF NEW.corrects_invoice_id IS NOT NULL THEN
            SELECT * INTO STRICT original FROM billing_invoices WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.corrects_invoice_id;
            IF original.corrects_invoice_id IS NOT NULL OR original.currency<>NEW.currency OR original.billing_case_id IS DISTINCT FROM NEW.billing_case_id OR original.billing_subject_id IS DISTINCT FROM NEW.billing_subject_id OR NEW.document_type='invoice' THEN RAISE EXCEPTION 'Invalid correction scope'; END IF;
          ELSIF NEW.document_type='debit_note' THEN RAISE EXCEPTION 'Debit note requires an original claim'; END IF;
        END IF;
        RETURN NEW;
      END $$;
      CREATE OR REPLACE FUNCTION validate_billing_line_correction() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE document billing_invoices%ROWTYPE; previous billing_invoices%ROWTYPE; old_account text; new_account text;
      BEGIN
        IF NEW.corrects_line_id IS NOT NULL THEN
          SELECT * INTO STRICT document FROM billing_invoices WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.billing_invoice_id;
          SELECT h.* INTO STRICT previous FROM billing_invoice_lines l JOIN billing_invoices h ON h.tenant_id=l.tenant_id AND h.entity_id=l.entity_id AND h.id=l.billing_invoice_id WHERE l.tenant_id=NEW.tenant_id AND l.entity_id=NEW.entity_id AND l.id=NEW.corrects_line_id;
          SELECT o.account_id INTO STRICT old_account FROM billing_invoice_lines l JOIN billing_obligations o ON o.tenant_id=l.tenant_id AND o.entity_id=l.entity_id AND o.id=l.billing_obligation_id WHERE l.tenant_id=NEW.tenant_id AND l.entity_id=NEW.entity_id AND l.id=NEW.corrects_line_id;
          SELECT account_id INTO STRICT new_account FROM billing_obligations WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.billing_obligation_id;
          IF document.corrects_invoice_id IS NULL OR (previous.id IS DISTINCT FROM document.corrects_invoice_id AND previous.corrects_invoice_id IS DISTINCT FROM document.corrects_invoice_id) OR old_account<>new_account THEN RAISE EXCEPTION 'Correction line must reference its original claim and account'; END IF;
        END IF;
        RETURN NEW;
      END $$;
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Restore the prior retained database snapshot'
  end
end
