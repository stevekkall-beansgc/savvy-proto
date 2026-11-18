class AddNativeBillingDocuments < ActiveRecord::Migration[8.0]
  def up
    add_column :billing_invoices,:document_type,:string,null:false,default:'invoice'
    add_column :billing_invoices,:corrects_invoice_id,:bigint
    add_column :billing_invoices,:creditor_id,:string,null:false,default:'firm-demo'
    add_column :billing_invoices,:billing_case_id,:string
    add_column :billing_invoices,:billing_subject_id,:string
    add_column :billing_invoices,:issued_on,:date
    add_column :billing_invoices,:due_on,:date
    add_column :billing_invoices,:posting_period,:string
    add_column :billing_invoices,:calculation_ref,:string
    add_column :billing_invoice_lines,:corrects_line_id,:bigint
    execute <<~SQL
      ALTER TABLE billing_invoices ADD CONSTRAINT billing_document_type CHECK (document_type IN ('invoice','credit_note','debit_note'));
      ALTER TABLE billing_invoices ADD CONSTRAINT billing_document_parent FOREIGN KEY (tenant_id,entity_id,corrects_invoice_id) REFERENCES billing_invoices(tenant_id,entity_id,id);
      ALTER TABLE billing_invoice_lines ADD CONSTRAINT billing_line_parent FOREIGN KEY (tenant_id,entity_id,corrects_line_id) REFERENCES billing_invoice_lines(tenant_id,entity_id,id);
      CREATE FUNCTION validate_billing_document() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE original billing_invoices%ROWTYPE;
      BEGIN
        IF NEW.external_id LIKE 'bp-doc-%' THEN
          IF NEW.billing_case_id NOT IN ('advisor','ria') OR NEW.billing_subject_id IS NULL OR NEW.calculation_ref IS NULL OR NEW.issued_on IS NULL OR NEW.posting_period IS NULL OR NEW.posting_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR NEW.debtor_id=NEW.creditor_id OR (NEW.due_on IS NOT NULL AND NEW.due_on<NEW.issued_on) THEN RAISE EXCEPTION 'Invalid native document metadata'; END IF;
          IF NEW.document_type<>'invoice' THEN
            SELECT * INTO STRICT original FROM billing_invoices WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.corrects_invoice_id;
            IF original.document_type<>'invoice' OR original.currency<>NEW.currency OR original.billing_case_id<>NEW.billing_case_id OR original.billing_subject_id<>NEW.billing_subject_id THEN RAISE EXCEPTION 'Invalid correction scope'; END IF;
            IF (NEW.document_type='credit_note' AND (NEW.debtor_id<>original.creditor_id OR NEW.creditor_id<>original.debtor_id)) OR (NEW.document_type='debit_note' AND (NEW.debtor_id<>original.debtor_id OR NEW.creditor_id<>original.creditor_id)) THEN RAISE EXCEPTION 'Invalid correction direction'; END IF;
          ELSIF NEW.corrects_invoice_id IS NOT NULL THEN RAISE EXCEPTION 'An invoice cannot correct another invoice'; END IF;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER billing_document_metadata BEFORE INSERT ON billing_invoices FOR EACH ROW EXECUTE FUNCTION validate_billing_document();
      CREATE FUNCTION native_billing_append_only() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Native billing documents and obligations are immutable'; END $$;
      CREATE TRIGGER billing_invoices_append_only BEFORE UPDATE OR DELETE ON billing_invoices FOR EACH ROW EXECUTE FUNCTION native_billing_append_only();
      CREATE TRIGGER billing_invoice_lines_append_only BEFORE UPDATE OR DELETE ON billing_invoice_lines FOR EACH ROW EXECUTE FUNCTION native_billing_append_only();
      CREATE TRIGGER billing_obligations_append_only BEFORE UPDATE OR DELETE ON billing_obligations FOR EACH ROW EXECUTE FUNCTION native_billing_append_only();
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Restore the prior database snapshot; never rewrite issued documents'
  end
end
