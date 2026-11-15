-- Run only in the isolated synthetic compose database, never an employer database.
DO $$ BEGIN
  IF current_database() != 'advisor_economics_synthetic' THEN
    RAISE EXCEPTION 'Synthetic database required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='savvy_analytics') THEN
    CREATE ROLE savvy_analytics LOGIN;
  END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS raw_demo;
CREATE SCHEMA IF NOT EXISTS analytics AUTHORIZATION savvy_analytics;
CREATE OR REPLACE VIEW raw_demo.records AS
  SELECT tenant_id, entity_id, kind, external_id, revision, payload_hash, payload, recorded_at
  FROM public.demo_records WHERE synthetic = true;
CREATE OR REPLACE VIEW raw_demo.operational_matches AS
  SELECT tenant_id, entity_id, source_id, target_id, currency, minor_units, id, created_at
  FROM public.demo_allocations a WHERE kind='operational_match' AND NOT EXISTS (SELECT 1 FROM public.demo_match_reversals r WHERE r.allocation_id=a.id AND r.tenant_id=a.tenant_id AND r.entity_id=a.entity_id);
GRANT USAGE ON SCHEMA raw_demo TO savvy_analytics;
GRANT SELECT ON ALL TABLES IN SCHEMA raw_demo TO savvy_analytics;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM savvy_analytics;

CREATE OR REPLACE VIEW raw_demo.match_history AS
  SELECT a.*,r.id AS reversal_id,r.reason AS reversal_reason,r.created_at AS reversed_at
  FROM public.demo_allocations a LEFT JOIN public.demo_match_reversals r ON r.allocation_id=a.id AND r.tenant_id=a.tenant_id AND r.entity_id=a.entity_id
  WHERE a.kind='operational_match';
CREATE OR REPLACE VIEW raw_demo.entitlement_entries AS SELECT * FROM public.demo_entitlement_entries;
GRANT USAGE,CREATE ON SCHEMA analytics TO savvy_analytics;
GRANT SELECT ON ALL TABLES IN SCHEMA raw_demo TO savvy_analytics;
-- Native synthetic commercial evidence; these are independent of mock accounting.
CREATE OR REPLACE VIEW raw_demo.billing_obligations AS SELECT * FROM public.billing_obligations;
CREATE OR REPLACE VIEW raw_demo.billing_invoices AS SELECT * FROM public.billing_invoices;
CREATE OR REPLACE VIEW raw_demo.billing_invoice_lines AS SELECT * FROM public.billing_invoice_lines;
CREATE OR REPLACE VIEW raw_demo.billing_instructions AS SELECT * FROM public.billing_instructions;
CREATE OR REPLACE VIEW raw_demo.billing_instruction_items AS SELECT * FROM public.billing_instruction_items;
CREATE OR REPLACE VIEW raw_demo.billing_accounting_facts AS SELECT * FROM public.billing_accounting_facts;
GRANT SELECT ON ALL TABLES IN SCHEMA raw_demo TO savvy_analytics;
