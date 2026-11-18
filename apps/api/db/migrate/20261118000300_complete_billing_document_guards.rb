class CompleteBillingDocumentGuards < ActiveRecord::Migration[8.0]
  def up
    change_column :commercial_rates,:numerator,:bigint
    change_column :commercial_rates,:denominator,:bigint
    execute <<~SQL
      ALTER TABLE commercial_rates DROP CONSTRAINT valid_commercial_rate_v2;
      ALTER TABLE commercial_rates ADD CONSTRAINT valid_commercial_rate_v2 CHECK (
        length(component)>0 AND kind IN ('standard','promotion','targeted_promotion') AND numerator>=0 AND denominator>=1
        AND unit IN ('ratio','USD_minor','unit_price') AND (ends_on IS NULL OR starts_on<ends_on)
        AND (signup_within_days IS NULL OR signup_within_days BETWEEN 1 AND 365) AND jsonb_typeof(selector)='object'
        AND ((configuration_id LIKE 'bp-policy-%' AND numerator<=1000000000000000 AND denominator<=1000000000000000)
          OR (denominator<=1000000 AND (unit<>'ratio' OR numerator<=denominator))));
      CREATE OR REPLACE FUNCTION validate_billing_document() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE original billing_invoices%ROWTYPE;
      BEGIN
        IF NEW.external_id LIKE 'bp-doc-%' THEN
          IF NEW.billing_case_id IS NULL OR NEW.billing_case_id NOT IN ('advisor','ria') OR NEW.billing_subject_id IS NULL OR length(NEW.billing_subject_id)=0 OR NEW.calculation_ref IS NULL OR NEW.issued_on IS NULL OR NEW.posting_period IS NULL OR NEW.posting_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR NEW.debtor_id=NEW.creditor_id OR (NEW.due_on IS NOT NULL AND NEW.due_on<NEW.issued_on) THEN RAISE EXCEPTION 'Invalid native document metadata'; END IF;
          IF NEW.document_type<>'invoice' THEN
            SELECT * INTO STRICT original FROM billing_invoices WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.corrects_invoice_id;
            IF original.document_type<>'invoice' OR original.currency<>NEW.currency OR original.billing_case_id IS DISTINCT FROM NEW.billing_case_id OR original.billing_subject_id IS DISTINCT FROM NEW.billing_subject_id THEN RAISE EXCEPTION 'Invalid correction scope'; END IF;
            IF (NEW.document_type='credit_note' AND (NEW.debtor_id<>original.creditor_id OR NEW.creditor_id<>original.debtor_id)) OR (NEW.document_type='debit_note' AND (NEW.debtor_id<>original.debtor_id OR NEW.creditor_id<>original.creditor_id)) THEN RAISE EXCEPTION 'Invalid correction direction'; END IF;
          ELSIF NEW.corrects_invoice_id IS NOT NULL THEN RAISE EXCEPTION 'An invoice cannot correct another invoice'; END IF;
        END IF;
        RETURN NEW;
      END $$;
      CREATE FUNCTION validate_billing_line_correction() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE document billing_invoices%ROWTYPE; previous billing_invoices%ROWTYPE; old_account text; new_account text;
      BEGIN
        IF NEW.corrects_line_id IS NOT NULL THEN
          SELECT * INTO STRICT document FROM billing_invoices WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.billing_invoice_id;
          SELECT h.* INTO STRICT previous FROM billing_invoice_lines l JOIN billing_invoices h ON h.tenant_id=l.tenant_id AND h.entity_id=l.entity_id AND h.id=l.billing_invoice_id WHERE l.tenant_id=NEW.tenant_id AND l.entity_id=NEW.entity_id AND l.id=NEW.corrects_line_id;
          SELECT o.account_id INTO STRICT old_account FROM billing_invoice_lines l JOIN billing_obligations o ON o.tenant_id=l.tenant_id AND o.entity_id=l.entity_id AND o.id=l.billing_obligation_id WHERE l.tenant_id=NEW.tenant_id AND l.entity_id=NEW.entity_id AND l.id=NEW.corrects_line_id;
          SELECT account_id INTO STRICT new_account FROM billing_obligations WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.billing_obligation_id;
          IF document.document_type='invoice' OR previous.document_type='credit_note' OR (previous.id IS DISTINCT FROM document.corrects_invoice_id AND previous.corrects_invoice_id IS DISTINCT FROM document.corrects_invoice_id) OR old_account<>new_account THEN RAISE EXCEPTION 'Correction line must reference its original claim and account'; END IF;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER billing_line_correction BEFORE INSERT ON billing_invoice_lines FOR EACH ROW EXECUTE FUNCTION validate_billing_line_correction();
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Restore the prior database snapshot'
  end
end
