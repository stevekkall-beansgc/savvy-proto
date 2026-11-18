class GuardNativePayableScope < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :billing_instructions,column: :corrects_instruction_id
    add_foreign_key :billing_instructions,:billing_instructions,column:[:tenant_id,:entity_id,:corrects_instruction_id],primary_key:[:tenant_id,:entity_id,:id],name:'billing_payable_scoped_original'
    execute <<~SQL
      CREATE FUNCTION validate_native_payable() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE original billing_instructions%ROWTYPE;
      BEGIN
        IF NEW.external_id LIKE 'bp-payable-%' THEN
          IF NEW.billing_case_id IS NULL OR NEW.billing_case_id NOT IN ('advisor','ria') OR NEW.billing_subject_id IS NULL OR NEW.currency IS DISTINCT FROM 'USD' OR NEW.calculation_ref IS NULL OR NEW.posting_period IS NULL OR NEW.posting_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR NEW.execution_status IS DISTINCT FROM 'not_sent' OR NOT ((NEW.debtor_id='firm-demo' AND NEW.creditor_id=NEW.billing_subject_id) OR (NEW.creditor_id='firm-demo' AND NEW.debtor_id=NEW.billing_subject_id)) OR NEW.debtor_id=NEW.creditor_id THEN RAISE EXCEPTION 'Invalid native payable metadata'; END IF;
          IF NEW.corrects_instruction_id IS NOT NULL THEN
            SELECT * INTO STRICT original FROM billing_instructions WHERE tenant_id=NEW.tenant_id AND entity_id=NEW.entity_id AND id=NEW.corrects_instruction_id;
            IF original.corrects_instruction_id IS NOT NULL OR original.billing_case_id IS DISTINCT FROM NEW.billing_case_id OR original.billing_subject_id IS DISTINCT FROM NEW.billing_subject_id OR original.currency IS DISTINCT FROM NEW.currency THEN RAISE EXCEPTION 'Invalid payable correction scope'; END IF;
          END IF;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER native_payable_metadata BEFORE INSERT ON billing_instructions FOR EACH ROW EXECUTE FUNCTION validate_native_payable();
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Restore the prior database snapshot'
  end
end
