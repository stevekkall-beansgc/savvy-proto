SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: commercial_rates_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.commercial_rates_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN RAISE EXCEPTION 'commercial rate history is append-only'; END;
$$;


--
-- Name: medallion_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medallion_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN RAISE EXCEPTION 'medallion evidence is append-only'; END;
$$;


--
-- Name: native_billing_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.native_billing_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN RAISE EXCEPTION 'Native billing documents and obligations are immutable'; END $$;


--
-- Name: validate_billing_document(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_billing_document() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
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
END $_$;


--
-- Name: validate_billing_line_correction(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_billing_line_correction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: validate_native_payable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_native_payable() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
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
END $_$;


--
-- Name: validate_synthetic_billing_conservation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_synthetic_billing_conservation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM billing_invoices h LEFT JOIN billing_invoice_lines l ON l.tenant_id=h.tenant_id AND l.entity_id=h.entity_id AND l.billing_invoice_id=h.id GROUP BY h.id HAVING count(l.id)=0 OR coalesce(sum(l.amount_minor),0) <> h.amount_minor)
    OR EXISTS (SELECT 1 FROM billing_instructions h LEFT JOIN billing_instruction_items i ON i.tenant_id=h.tenant_id AND i.entity_id=h.entity_id AND i.billing_instruction_id=h.id GROUP BY h.id HAVING count(i.id)=0 OR coalesce(sum(i.amount_minor),0) <> h.amount_minor)
    OR EXISTS (SELECT 1 FROM billing_invoice_lines l JOIN billing_obligations o ON o.tenant_id=l.tenant_id AND o.entity_id=l.entity_id AND o.id=l.billing_obligation_id JOIN billing_invoices h ON h.tenant_id=l.tenant_id AND h.entity_id=l.entity_id AND h.id=l.billing_invoice_id WHERE o.route <> 'invoice' OR o.amount_minor <> l.amount_minor OR o.currency <> h.currency)
    OR EXISTS (SELECT 1 FROM billing_instruction_items i JOIN billing_obligations o ON o.tenant_id=i.tenant_id AND o.entity_id=i.entity_id AND o.id=i.billing_obligation_id WHERE o.route <> 'custodial' OR o.amount_minor <> i.amount_minor)
    OR EXISTS (SELECT 1 FROM billing_obligations o WHERE (o.route='invoice' AND NOT EXISTS (SELECT 1 FROM billing_invoice_lines l WHERE l.tenant_id=o.tenant_id AND l.entity_id=o.entity_id AND l.billing_obligation_id=o.id)) OR (o.route='custodial' AND NOT EXISTS (SELECT 1 FROM billing_instruction_items i WHERE i.tenant_id=o.tenant_id AND i.entity_id=o.entity_id AND i.billing_obligation_id=o.id)))
  THEN RAISE EXCEPTION 'Synthetic billing conservation violated' USING ERRCODE='23514'; END IF;
  RETURN NULL;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: demo_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demo_records (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    kind character varying NOT NULL,
    external_id character varying NOT NULL,
    revision integer NOT NULL,
    synthetic boolean DEFAULT true NOT NULL,
    payload_hash character varying NOT NULL,
    payload jsonb NOT NULL,
    recorded_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT synthetic_only_records CHECK (((synthetic = true) AND (revision > 0)))
);


--
-- Name: medallion_evidence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medallion_evidence (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    case_id character varying NOT NULL,
    kind character varying NOT NULL,
    external_id character varying NOT NULL,
    revision integer DEFAULT 1 NOT NULL,
    status character varying NOT NULL,
    subject_id character varying,
    parent_id bigint,
    payload_hash character varying NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    original_bytes bytea,
    recorded_at timestamp(6) without time zone NOT NULL,
    scenario_id character varying DEFAULT 'baseline'::character varying NOT NULL,
    product_id character varying,
    starts_on date,
    ends_on date,
    schedule_version integer DEFAULT 1 NOT NULL,
    CONSTRAINT medallion_assignment_interval CHECK ((((kind)::text <> 'assignment'::text) OR ((subject_id IS NOT NULL) AND (product_id IS NOT NULL) AND (starts_on IS NOT NULL) AND ((ends_on IS NULL) OR (starts_on < ends_on))))),
    CONSTRAINT medallion_evidence_kind CHECK ((((kind)::text = ANY (ARRAY[('artifact'::character varying)::text, ('delivery'::character varying)::text, ('fact'::character varying)::text, ('policy'::character varying)::text, ('assignment'::character varying)::text, ('comparison'::character varying)::text, ('review'::character varying)::text, ('publication'::character varying)::text, ('event'::character varying)::text, ('event_review'::character varying)::text, ('payment'::character varying)::text, ('application'::character varying)::text, ('application_reversal'::character varying)::text, ('run'::character varying)::text, ('statement'::character varying)::text, ('period_lock'::character varying)::text, ('funding'::character varying)::text, ('coverage_right'::character varying)::text, ('receipt'::character varying)::text, ('receipt_allocation'::character varying)::text, ('netting_authority'::character varying)::text, ('receipt_reversal'::character varying)::text, ('funding_reversal'::character varying)::text, ('adjustment_intent'::character varying)::text])) OR (((scenario_id)::text = 'billing_platform'::text) AND ((kind)::text = ANY (ARRAY[('source'::character varying)::text, ('normalized'::character varying)::text, ('normalization'::character varying)::text, ('policy_review'::character varying)::text, ('policy_publication'::character varying)::text, ('calculation'::character varying)::text, ('document'::character varying)::text, ('correction_proposal'::character varying)::text, ('correction_review'::character varying)::text, ('correction_issue'::character varying)::text, ('period_close'::character varying)::text]))) OR (((scenario_id)::text = 'billing_platform'::text) AND ((kind)::text = 'calculation_attempt'::text)) OR (((scenario_id)::text = 'billing_platform'::text) AND ((kind)::text = ANY ((ARRAY['cash_application'::character varying, 'cash_reversal'::character varying, 'refund_request'::character varying, 'accounting_package'::character varying, 'accounting_acceptance'::character varying, 'payable'::character varying, 'payable_review'::character varying, 'payable_issue'::character varying, 'work_attempt'::character varying, 'billing_batch'::character varying])::text[]))))),
    CONSTRAINT medallion_evidence_status CHECK ((((status)::text = ANY (ARRAY[('retained'::character varying)::text, ('accepted'::character varying)::text, ('draft'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('published'::character varying)::text, ('confirmed'::character varying)::text, ('pending'::character varying)::text, ('reversed'::character varying)::text, ('completed'::character varying)::text, ('blocked'::character varying)::text, ('sealed'::character varying)::text, ('locked'::character varying)::text])) OR (((scenario_id)::text = 'billing_platform'::text) AND ((status)::text = ANY (ARRAY[('active'::character varying)::text, ('quarantined'::character varying)::text, ('issued'::character varying)::text, ('closed'::character varying)::text, ('proposed'::character varying)::text, ('unchanged'::character varying)::text]))))),
    CONSTRAINT medallion_original_bytes CHECK (((((kind)::text = 'artifact'::text) AND (original_bytes IS NOT NULL)) OR (((kind)::text <> 'artifact'::text) AND (original_bytes IS NULL)))),
    CONSTRAINT medallion_scenario_body CHECK ((((scenario_id)::text ~ '^[a-zA-Z0-9_-]{1,100}$'::text) AND (jsonb_typeof(payload) = 'object'::text))),
    CONSTRAINT medallion_schedule_version CHECK ((schedule_version > 0)),
    CONSTRAINT medallion_scope_contract CHECK (((revision > 0) AND (length((payload_hash)::text) = 64) AND ((case_id)::text = ANY (ARRAY[('advisor'::character varying)::text, ('ria'::character varying)::text]))))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: billing_accounting_facts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_accounting_facts (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    external_id character varying NOT NULL,
    billing_invoice_id bigint,
    billing_instruction_id bigint,
    commercial_revision integer NOT NULL,
    reported_status character varying,
    applied_minor bigint,
    ar_minor bigint,
    recognized_minor bigint,
    observed_at timestamp(6) without time zone NOT NULL,
    mocked boolean DEFAULT true NOT NULL,
    CONSTRAINT billing_accounting_mock_values CHECK ((mocked AND (commercial_revision > 0) AND ((billing_invoice_id IS NULL) <> (billing_instruction_id IS NULL)) AND ((applied_minor IS NULL) OR (applied_minor >= 0)) AND ((ar_minor IS NULL) OR (ar_minor >= 0)) AND ((recognized_minor IS NULL) OR (recognized_minor >= 0))))
);


--
-- Name: billing_accounting_facts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_accounting_facts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_accounting_facts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_accounting_facts_id_seq OWNED BY public.billing_accounting_facts.id;


--
-- Name: billing_instruction_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_instruction_items (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    billing_instruction_id bigint NOT NULL,
    billing_obligation_id bigint NOT NULL,
    amount_minor bigint NOT NULL,
    CONSTRAINT billing_item_positive CHECK ((amount_minor > 0))
);


--
-- Name: billing_instruction_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_instruction_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_instruction_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_instruction_items_id_seq OWNED BY public.billing_instruction_items.id;


--
-- Name: billing_instructions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_instructions (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    external_id character varying NOT NULL,
    revision integer NOT NULL,
    amount_minor bigint NOT NULL,
    status character varying NOT NULL,
    execution_status character varying,
    debtor_id character varying,
    creditor_id character varying,
    billing_case_id character varying,
    billing_subject_id character varying,
    currency character varying,
    calculation_ref character varying,
    posting_period character varying,
    corrects_instruction_id bigint,
    CONSTRAINT billing_instruction_values CHECK (((amount_minor > 0) AND (revision > 0))),
    CONSTRAINT native_payable_required_metadata CHECK ((((external_id)::text !~~ 'bp-payable-%'::text) OR ((debtor_id IS NOT NULL) AND (creditor_id IS NOT NULL) AND ((debtor_id)::text <> (creditor_id)::text) AND (billing_case_id IS NOT NULL) AND (billing_subject_id IS NOT NULL) AND (currency IS NOT NULL) AND (calculation_ref IS NOT NULL) AND (posting_period IS NOT NULL))))
);


--
-- Name: billing_instructions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_instructions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_instructions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_instructions_id_seq OWNED BY public.billing_instructions.id;


--
-- Name: billing_invoice_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_invoice_lines (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    external_id character varying NOT NULL,
    billing_invoice_id bigint NOT NULL,
    billing_obligation_id bigint NOT NULL,
    amount_minor bigint NOT NULL,
    corrects_line_id bigint,
    CONSTRAINT billing_line_positive CHECK ((amount_minor > 0))
);


--
-- Name: billing_invoice_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_invoice_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_invoice_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_invoice_lines_id_seq OWNED BY public.billing_invoice_lines.id;


--
-- Name: billing_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_invoices (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    external_id character varying NOT NULL,
    revision integer NOT NULL,
    debtor_id character varying NOT NULL,
    amount_minor bigint NOT NULL,
    currency character varying NOT NULL,
    status character varying NOT NULL,
    legacy_invoice_id character varying,
    document_type character varying DEFAULT 'invoice'::character varying NOT NULL,
    corrects_invoice_id bigint,
    creditor_id character varying DEFAULT 'firm-demo'::character varying NOT NULL,
    billing_case_id character varying,
    billing_subject_id character varying,
    issued_on date,
    due_on date,
    posting_period character varying,
    calculation_ref character varying,
    CONSTRAINT billing_document_type CHECK (((document_type)::text = ANY (ARRAY[('invoice'::character varying)::text, ('credit_note'::character varying)::text, ('debit_note'::character varying)::text]))),
    CONSTRAINT billing_invoice_values CHECK (((amount_minor > 0) AND ((currency)::text = 'USD'::text) AND (revision > 0)))
);


--
-- Name: billing_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_invoices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_invoices_id_seq OWNED BY public.billing_invoices.id;


--
-- Name: billing_obligations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_obligations (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    external_id character varying NOT NULL,
    revision integer NOT NULL,
    customer_id character varying NOT NULL,
    service_id character varying NOT NULL,
    broker_id character varying NOT NULL,
    account_id character varying NOT NULL,
    assignment_id character varying NOT NULL,
    client_terms_ref character varying NOT NULL,
    source_id character varying NOT NULL,
    source_revision integer NOT NULL,
    legacy_charge_id character varying,
    route character varying NOT NULL,
    currency character varying NOT NULL,
    amount_minor bigint NOT NULL,
    service_period_start date NOT NULL,
    service_period_end date NOT NULL,
    CONSTRAINT billing_obligation_values CHECK (((amount_minor > 0) AND ((currency)::text = 'USD'::text) AND (revision > 0) AND (source_revision > 0) AND (service_period_start < service_period_end) AND ((route)::text = ANY (ARRAY[('invoice'::character varying)::text, ('custodial'::character varying)::text]))))
);


--
-- Name: billing_obligations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_obligations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_obligations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_obligations_id_seq OWNED BY public.billing_obligations.id;


--
-- Name: billing_work_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_work_items (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    case_id character varying NOT NULL,
    job_id character varying NOT NULL,
    job_class character varying NOT NULL,
    status character varying NOT NULL,
    job_data jsonb NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    leased_until timestamp(6) without time zone,
    lease_token character varying,
    batch_id character varying,
    last_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT billing_work_state CHECK ((((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying, 'completed'::character varying, 'quarantined'::character varying, 'failed'::character varying])::text[])) AND (attempts >= 0) AND ((max_attempts >= 1) AND (max_attempts <= 10)) AND ((case_id)::text = ANY ((ARRAY['advisor'::character varying, 'ria'::character varying])::text[]))))
);


--
-- Name: billing_work_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_work_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_work_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_work_items_id_seq OWNED BY public.billing_work_items.id;


--
-- Name: commercial_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commercial_rates (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    configuration_id character varying NOT NULL,
    external_id character varying NOT NULL,
    broker_id character varying NOT NULL,
    component character varying NOT NULL,
    kind character varying NOT NULL,
    name character varying NOT NULL,
    numerator bigint NOT NULL,
    denominator bigint NOT NULL,
    starts_on date NOT NULL,
    ends_on date,
    selector jsonb DEFAULT '{}'::jsonb NOT NULL,
    signup_within_days integer,
    priority integer,
    recorded_at timestamp(6) without time zone NOT NULL,
    unit character varying DEFAULT 'ratio'::character varying NOT NULL,
    payer_id character varying,
    payee_id character varying,
    commercial_group character varying,
    CONSTRAINT valid_commercial_rate_v2 CHECK (((length((component)::text) > 0) AND ((kind)::text = ANY (ARRAY[('standard'::character varying)::text, ('promotion'::character varying)::text, ('targeted_promotion'::character varying)::text])) AND (numerator >= 0) AND (denominator >= 1) AND ((unit)::text = ANY (ARRAY[('ratio'::character varying)::text, ('USD_minor'::character varying)::text, ('unit_price'::character varying)::text])) AND ((ends_on IS NULL) OR (starts_on < ends_on)) AND ((signup_within_days IS NULL) OR ((signup_within_days >= 1) AND (signup_within_days <= 365))) AND (jsonb_typeof(selector) = 'object'::text) AND ((((configuration_id)::text ~~ 'bp-policy-%'::text) AND (numerator <= '1000000000000000'::bigint) AND (denominator <= '1000000000000000'::bigint)) OR ((denominator <= 1000000) AND (((unit)::text <> 'ratio'::text) OR (numerator <= denominator))))))
);


--
-- Name: commercial_rates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.commercial_rates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: commercial_rates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.commercial_rates_id_seq OWNED BY public.commercial_rates.id;


--
-- Name: demo_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demo_allocations (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    kind character varying NOT NULL,
    source_id character varying NOT NULL,
    target_id character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    minor_units bigint NOT NULL,
    idempotency_key character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT positive_usd_allocation CHECK (((minor_units > 0) AND ((currency)::text = 'USD'::text)))
);


--
-- Name: demo_allocations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.demo_allocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: demo_allocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.demo_allocations_id_seq OWNED BY public.demo_allocations.id;


--
-- Name: demo_entitlement_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demo_entitlement_entries (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    grant_id character varying NOT NULL,
    obligation_id character varying NOT NULL,
    kind character varying NOT NULL,
    minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    original_entry_id bigint,
    actor_id character varying NOT NULL,
    reason character varying NOT NULL,
    business_date date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT entitlement_entry_kind CHECK (((((kind)::text = 'consume'::text) AND (original_entry_id IS NULL)) OR (((kind)::text = 'reversal'::text) AND (original_entry_id IS NOT NULL)))),
    CONSTRAINT positive_entitlement_usd CHECK (((minor_units > 0) AND ((currency)::text = 'USD'::text)))
);


--
-- Name: demo_entitlement_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.demo_entitlement_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: demo_entitlement_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.demo_entitlement_entries_id_seq OWNED BY public.demo_entitlement_entries.id;


--
-- Name: demo_match_reversals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demo_match_reversals (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    allocation_id bigint NOT NULL,
    actor_id character varying NOT NULL,
    reason character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: demo_match_reversals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.demo_match_reversals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: demo_match_reversals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.demo_match_reversals_id_seq OWNED BY public.demo_match_reversals.id;


--
-- Name: demo_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demo_operations (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    actor_id character varying NOT NULL,
    operation character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    request_hash character varying NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: demo_operations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.demo_operations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: demo_operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.demo_operations_id_seq OWNED BY public.demo_operations.id;


--
-- Name: demo_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.demo_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: demo_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.demo_records_id_seq OWNED BY public.demo_records.id;


--
-- Name: demo_scopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.demo_scopes (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    synthetic boolean DEFAULT true NOT NULL,
    CONSTRAINT synthetic_only_scope CHECK ((synthetic = true))
);


--
-- Name: demo_scopes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.demo_scopes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: demo_scopes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.demo_scopes_id_seq OWNED BY public.demo_scopes.id;


--
-- Name: medallion_evidence_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.medallion_evidence_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: medallion_evidence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.medallion_evidence_id_seq OWNED BY public.medallion_evidence.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: billing_accounting_facts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_accounting_facts ALTER COLUMN id SET DEFAULT nextval('public.billing_accounting_facts_id_seq'::regclass);


--
-- Name: billing_instruction_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instruction_items ALTER COLUMN id SET DEFAULT nextval('public.billing_instruction_items_id_seq'::regclass);


--
-- Name: billing_instructions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instructions ALTER COLUMN id SET DEFAULT nextval('public.billing_instructions_id_seq'::regclass);


--
-- Name: billing_invoice_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoice_lines ALTER COLUMN id SET DEFAULT nextval('public.billing_invoice_lines_id_seq'::regclass);


--
-- Name: billing_invoices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices ALTER COLUMN id SET DEFAULT nextval('public.billing_invoices_id_seq'::regclass);


--
-- Name: billing_obligations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_obligations ALTER COLUMN id SET DEFAULT nextval('public.billing_obligations_id_seq'::regclass);


--
-- Name: billing_work_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_work_items ALTER COLUMN id SET DEFAULT nextval('public.billing_work_items_id_seq'::regclass);


--
-- Name: commercial_rates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_rates ALTER COLUMN id SET DEFAULT nextval('public.commercial_rates_id_seq'::regclass);


--
-- Name: demo_allocations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_allocations ALTER COLUMN id SET DEFAULT nextval('public.demo_allocations_id_seq'::regclass);


--
-- Name: demo_entitlement_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_entitlement_entries ALTER COLUMN id SET DEFAULT nextval('public.demo_entitlement_entries_id_seq'::regclass);


--
-- Name: demo_match_reversals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_match_reversals ALTER COLUMN id SET DEFAULT nextval('public.demo_match_reversals_id_seq'::regclass);


--
-- Name: demo_operations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_operations ALTER COLUMN id SET DEFAULT nextval('public.demo_operations_id_seq'::regclass);


--
-- Name: demo_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_records ALTER COLUMN id SET DEFAULT nextval('public.demo_records_id_seq'::regclass);


--
-- Name: demo_scopes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_scopes ALTER COLUMN id SET DEFAULT nextval('public.demo_scopes_id_seq'::regclass);


--
-- Name: medallion_evidence id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medallion_evidence ALTER COLUMN id SET DEFAULT nextval('public.medallion_evidence_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: billing_accounting_facts billing_accounting_facts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_accounting_facts
    ADD CONSTRAINT billing_accounting_facts_pkey PRIMARY KEY (id);


--
-- Name: billing_instruction_items billing_instruction_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instruction_items
    ADD CONSTRAINT billing_instruction_items_pkey PRIMARY KEY (id);


--
-- Name: billing_instructions billing_instructions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instructions
    ADD CONSTRAINT billing_instructions_pkey PRIMARY KEY (id);


--
-- Name: billing_invoice_lines billing_invoice_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoice_lines
    ADD CONSTRAINT billing_invoice_lines_pkey PRIMARY KEY (id);


--
-- Name: billing_invoices billing_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT billing_invoices_pkey PRIMARY KEY (id);


--
-- Name: billing_obligations billing_obligations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_obligations
    ADD CONSTRAINT billing_obligations_pkey PRIMARY KEY (id);


--
-- Name: billing_work_items billing_work_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_work_items
    ADD CONSTRAINT billing_work_items_pkey PRIMARY KEY (id);


--
-- Name: commercial_rates commercial_rate_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_rates
    ADD CONSTRAINT commercial_rate_no_overlap EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, configuration_id WITH =, broker_id WITH =, component WITH =, kind WITH =, daterange(starts_on, ends_on, '[)'::text) WITH &&) WHERE (((kind)::text = ANY (ARRAY[('standard'::character varying)::text, ('promotion'::character varying)::text])));


--
-- Name: commercial_rates commercial_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_rates
    ADD CONSTRAINT commercial_rates_pkey PRIMARY KEY (id);


--
-- Name: commercial_rates commercial_target_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_rates
    ADD CONSTRAINT commercial_target_no_overlap EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, configuration_id WITH =, broker_id WITH =, component WITH =, ((selector)::text) WITH =, COALESCE(signup_within_days, 0) WITH =, daterange(starts_on, ends_on, '[)'::text) WITH &&) WHERE (((kind)::text = 'targeted_promotion'::text));


--
-- Name: demo_allocations demo_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_allocations
    ADD CONSTRAINT demo_allocations_pkey PRIMARY KEY (id);


--
-- Name: demo_entitlement_entries demo_entitlement_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_entitlement_entries
    ADD CONSTRAINT demo_entitlement_entries_pkey PRIMARY KEY (id);


--
-- Name: demo_match_reversals demo_match_reversals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_match_reversals
    ADD CONSTRAINT demo_match_reversals_pkey PRIMARY KEY (id);


--
-- Name: demo_operations demo_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_operations
    ADD CONSTRAINT demo_operations_pkey PRIMARY KEY (id);


--
-- Name: demo_records demo_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_records
    ADD CONSTRAINT demo_records_pkey PRIMARY KEY (id);


--
-- Name: demo_scopes demo_scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_scopes
    ADD CONSTRAINT demo_scopes_pkey PRIMARY KEY (id);


--
-- Name: medallion_evidence medallion_assignment_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medallion_evidence
    ADD CONSTRAINT medallion_assignment_no_overlap EXCLUDE USING gist (tenant_id WITH =, entity_id WITH =, case_id WITH =, scenario_id WITH =, schedule_version WITH =, subject_id WITH =, product_id WITH =, daterange(starts_on, ends_on, '[)'::text) WITH &&) WHERE (((kind)::text = 'assignment'::text));


--
-- Name: medallion_evidence medallion_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medallion_evidence
    ADD CONSTRAINT medallion_evidence_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: allocation_scoped_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX allocation_scoped_id ON public.demo_allocations USING btree (tenant_id, entity_id, id);


--
-- Name: allocation_source_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX allocation_source_scope ON public.demo_allocations USING btree (tenant_id, entity_id, kind, source_id);


--
-- Name: billing_accounting_facts_scoped_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_accounting_facts_scoped_external ON public.billing_accounting_facts USING btree (tenant_id, entity_id, external_id);


--
-- Name: billing_accounting_facts_scoped_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_accounting_facts_scoped_pk ON public.billing_accounting_facts USING btree (tenant_id, entity_id, id);


--
-- Name: billing_instruction_items_scoped_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_instruction_items_scoped_pk ON public.billing_instruction_items USING btree (tenant_id, entity_id, id);


--
-- Name: billing_instructions_scoped_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_instructions_scoped_external ON public.billing_instructions USING btree (tenant_id, entity_id, external_id);


--
-- Name: billing_instructions_scoped_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_instructions_scoped_pk ON public.billing_instructions USING btree (tenant_id, entity_id, id);


--
-- Name: billing_invoice_lines_scoped_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_invoice_lines_scoped_external ON public.billing_invoice_lines USING btree (tenant_id, entity_id, external_id);


--
-- Name: billing_invoice_lines_scoped_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_invoice_lines_scoped_pk ON public.billing_invoice_lines USING btree (tenant_id, entity_id, id);


--
-- Name: billing_invoices_scoped_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_invoices_scoped_external ON public.billing_invoices USING btree (tenant_id, entity_id, external_id);


--
-- Name: billing_invoices_scoped_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_invoices_scoped_pk ON public.billing_invoices USING btree (tenant_id, entity_id, id);


--
-- Name: billing_obligations_scoped_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_obligations_scoped_external ON public.billing_obligations USING btree (tenant_id, entity_id, external_id);


--
-- Name: billing_obligations_scoped_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX billing_obligations_scoped_pk ON public.billing_obligations USING btree (tenant_id, entity_id, id);


--
-- Name: billing_work_ready; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX billing_work_ready ON public.billing_work_items USING btree (status, run_at, leased_until);


--
-- Name: billing_work_scope_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX billing_work_scope_batch ON public.billing_work_items USING btree (tenant_id, entity_id, case_id, batch_id);


--
-- Name: commercial_rate_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX commercial_rate_identity ON public.commercial_rates USING btree (tenant_id, entity_id, configuration_id, external_id);


--
-- Name: entitlement_grant_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX entitlement_grant_scope ON public.demo_entitlement_entries USING btree (tenant_id, entity_id, grant_id);


--
-- Name: entitlement_scoped_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entitlement_scoped_id ON public.demo_entitlement_entries USING btree (tenant_id, entity_id, id);


--
-- Name: index_billing_work_items_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_billing_work_items_on_job_id ON public.billing_work_items USING btree (job_id);


--
-- Name: index_demo_match_reversals_on_allocation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_demo_match_reversals_on_allocation_id ON public.demo_match_reversals USING btree (allocation_id);


--
-- Name: index_demo_scopes_on_tenant_id_and_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_demo_scopes_on_tenant_id_and_entity_id ON public.demo_scopes USING btree (tenant_id, entity_id);


--
-- Name: medallion_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medallion_history ON public.medallion_evidence USING btree (tenant_id, entity_id, case_id, kind, recorded_at);


--
-- Name: medallion_scoped_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX medallion_scoped_id ON public.medallion_evidence USING btree (tenant_id, entity_id, case_id, scenario_id, id);


--
-- Name: medallion_version_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX medallion_version_identity ON public.medallion_evidence USING btree (tenant_id, entity_id, case_id, scenario_id, kind, external_id, revision);


--
-- Name: one_entitlement_reversal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_entitlement_reversal ON public.demo_entitlement_entries USING btree (original_entry_id) WHERE ((kind)::text = 'reversal'::text);


--
-- Name: one_instruction_item_per_obligation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_instruction_item_per_obligation ON public.billing_instruction_items USING btree (tenant_id, entity_id, billing_obligation_id);


--
-- Name: one_invoice_line_per_obligation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_invoice_line_per_obligation ON public.billing_invoice_lines USING btree (tenant_id, entity_id, billing_obligation_id);


--
-- Name: scoped_operation_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX scoped_operation_idempotency ON public.demo_operations USING btree (tenant_id, entity_id, actor_id, operation, idempotency_key);


--
-- Name: synthetic_scope_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX synthetic_scope_history ON public.demo_records USING btree (tenant_id, entity_id, kind, recorded_at);


--
-- Name: unique_allocation_request; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_allocation_request ON public.demo_allocations USING btree (tenant_id, entity_id, kind, idempotency_key);


--
-- Name: unique_synthetic_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_synthetic_revision ON public.demo_records USING btree (tenant_id, entity_id, kind, external_id, revision);


--
-- Name: billing_invoices billing_document_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_document_metadata BEFORE INSERT ON public.billing_invoices FOR EACH ROW EXECUTE FUNCTION public.validate_billing_document();


--
-- Name: billing_instruction_items billing_instruction_items_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_instruction_items_append_only BEFORE DELETE OR UPDATE ON public.billing_instruction_items FOR EACH ROW EXECUTE FUNCTION public.native_billing_append_only();


--
-- Name: billing_instruction_items billing_instruction_items_conservation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER billing_instruction_items_conservation AFTER INSERT OR DELETE OR UPDATE ON public.billing_instruction_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_synthetic_billing_conservation();


--
-- Name: billing_instructions billing_instructions_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_instructions_append_only BEFORE DELETE OR UPDATE ON public.billing_instructions FOR EACH ROW EXECUTE FUNCTION public.native_billing_append_only();


--
-- Name: billing_instructions billing_instructions_conservation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER billing_instructions_conservation AFTER INSERT OR DELETE OR UPDATE ON public.billing_instructions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_synthetic_billing_conservation();


--
-- Name: billing_invoice_lines billing_invoice_lines_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_invoice_lines_append_only BEFORE DELETE OR UPDATE ON public.billing_invoice_lines FOR EACH ROW EXECUTE FUNCTION public.native_billing_append_only();


--
-- Name: billing_invoice_lines billing_invoice_lines_conservation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER billing_invoice_lines_conservation AFTER INSERT OR DELETE OR UPDATE ON public.billing_invoice_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_synthetic_billing_conservation();


--
-- Name: billing_invoices billing_invoices_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_invoices_append_only BEFORE DELETE OR UPDATE ON public.billing_invoices FOR EACH ROW EXECUTE FUNCTION public.native_billing_append_only();


--
-- Name: billing_invoices billing_invoices_conservation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER billing_invoices_conservation AFTER INSERT OR DELETE OR UPDATE ON public.billing_invoices DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_synthetic_billing_conservation();


--
-- Name: billing_invoice_lines billing_line_correction; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_line_correction BEFORE INSERT ON public.billing_invoice_lines FOR EACH ROW EXECUTE FUNCTION public.validate_billing_line_correction();


--
-- Name: billing_obligations billing_obligations_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER billing_obligations_append_only BEFORE DELETE OR UPDATE ON public.billing_obligations FOR EACH ROW EXECUTE FUNCTION public.native_billing_append_only();


--
-- Name: billing_obligations billing_obligations_conservation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER billing_obligations_conservation AFTER INSERT OR DELETE OR UPDATE ON public.billing_obligations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_synthetic_billing_conservation();


--
-- Name: commercial_rates commercial_rates_no_update_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER commercial_rates_no_update_delete BEFORE DELETE OR UPDATE ON public.commercial_rates FOR EACH ROW EXECUTE FUNCTION public.commercial_rates_append_only();


--
-- Name: medallion_evidence medallion_no_update_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medallion_no_update_delete BEFORE DELETE OR UPDATE ON public.medallion_evidence FOR EACH ROW EXECUTE FUNCTION public.medallion_append_only();


--
-- Name: billing_instructions native_payable_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER native_payable_metadata BEFORE INSERT ON public.billing_instructions FOR EACH ROW EXECUTE FUNCTION public.validate_native_payable();


--
-- Name: billing_invoices billing_document_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT billing_document_parent FOREIGN KEY (tenant_id, entity_id, corrects_invoice_id) REFERENCES public.billing_invoices(tenant_id, entity_id, id);


--
-- Name: billing_invoice_lines billing_line_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoice_lines
    ADD CONSTRAINT billing_line_parent FOREIGN KEY (tenant_id, entity_id, corrects_line_id) REFERENCES public.billing_invoice_lines(tenant_id, entity_id, id);


--
-- Name: billing_instructions billing_payable_scoped_original; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instructions
    ADD CONSTRAINT billing_payable_scoped_original FOREIGN KEY (tenant_id, entity_id, corrects_instruction_id) REFERENCES public.billing_instructions(tenant_id, entity_id, id);


--
-- Name: demo_entitlement_entries entitlement_reversal_same_scope; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_entitlement_entries
    ADD CONSTRAINT entitlement_reversal_same_scope FOREIGN KEY (tenant_id, entity_id, original_entry_id) REFERENCES public.demo_entitlement_entries(tenant_id, entity_id, id);


--
-- Name: billing_accounting_facts fk_billing_accounting_facts_billing_instruction_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_accounting_facts
    ADD CONSTRAINT fk_billing_accounting_facts_billing_instruction_id FOREIGN KEY (tenant_id, entity_id, billing_instruction_id) REFERENCES public.billing_instructions(tenant_id, entity_id, id);


--
-- Name: billing_accounting_facts fk_billing_accounting_facts_billing_invoice_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_accounting_facts
    ADD CONSTRAINT fk_billing_accounting_facts_billing_invoice_id FOREIGN KEY (tenant_id, entity_id, billing_invoice_id) REFERENCES public.billing_invoices(tenant_id, entity_id, id);


--
-- Name: billing_instruction_items fk_billing_instruction_items_billing_instruction_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instruction_items
    ADD CONSTRAINT fk_billing_instruction_items_billing_instruction_id FOREIGN KEY (tenant_id, entity_id, billing_instruction_id) REFERENCES public.billing_instructions(tenant_id, entity_id, id);


--
-- Name: billing_instruction_items fk_billing_instruction_items_billing_obligation_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instruction_items
    ADD CONSTRAINT fk_billing_instruction_items_billing_obligation_id FOREIGN KEY (tenant_id, entity_id, billing_obligation_id) REFERENCES public.billing_obligations(tenant_id, entity_id, id);


--
-- Name: billing_invoice_lines fk_billing_invoice_lines_billing_invoice_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoice_lines
    ADD CONSTRAINT fk_billing_invoice_lines_billing_invoice_id FOREIGN KEY (tenant_id, entity_id, billing_invoice_id) REFERENCES public.billing_invoices(tenant_id, entity_id, id);


--
-- Name: billing_invoice_lines fk_billing_invoice_lines_billing_obligation_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoice_lines
    ADD CONSTRAINT fk_billing_invoice_lines_billing_obligation_id FOREIGN KEY (tenant_id, entity_id, billing_obligation_id) REFERENCES public.billing_obligations(tenant_id, entity_id, id);


--
-- Name: medallion_evidence fk_rails_00ef76fc97; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medallion_evidence
    ADD CONSTRAINT fk_rails_00ef76fc97 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: billing_invoice_lines fk_rails_143e5eed28; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoice_lines
    ADD CONSTRAINT fk_rails_143e5eed28 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: demo_records fk_rails_158407786f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_records
    ADD CONSTRAINT fk_rails_158407786f FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: demo_operations fk_rails_23f0b875c3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_operations
    ADD CONSTRAINT fk_rails_23f0b875c3 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: billing_invoices fk_rails_291e737780; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT fk_rails_291e737780 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: demo_allocations fk_rails_32de1dbee4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_allocations
    ADD CONSTRAINT fk_rails_32de1dbee4 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: commercial_rates fk_rails_3eda098c61; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commercial_rates
    ADD CONSTRAINT fk_rails_3eda098c61 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: demo_match_reversals fk_rails_48c7608b8e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_match_reversals
    ADD CONSTRAINT fk_rails_48c7608b8e FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: billing_instruction_items fk_rails_aa2e7404b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instruction_items
    ADD CONSTRAINT fk_rails_aa2e7404b5 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: billing_obligations fk_rails_c00c076219; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_obligations
    ADD CONSTRAINT fk_rails_c00c076219 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: billing_instructions fk_rails_c417a06255; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_instructions
    ADD CONSTRAINT fk_rails_c417a06255 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: demo_entitlement_entries fk_rails_c7bc5b23a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_entitlement_entries
    ADD CONSTRAINT fk_rails_c7bc5b23a0 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: billing_accounting_facts fk_rails_d5f9c33ba4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_accounting_facts
    ADD CONSTRAINT fk_rails_d5f9c33ba4 FOREIGN KEY (tenant_id, entity_id) REFERENCES public.demo_scopes(tenant_id, entity_id);


--
-- Name: demo_match_reversals match_reversal_same_scope; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.demo_match_reversals
    ADD CONSTRAINT match_reversal_same_scope FOREIGN KEY (tenant_id, entity_id, allocation_id) REFERENCES public.demo_allocations(tenant_id, entity_id, id);


--
-- Name: medallion_evidence medallion_parent_scope; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medallion_evidence
    ADD CONSTRAINT medallion_parent_scope FOREIGN KEY (tenant_id, entity_id, case_id, scenario_id, parent_id) REFERENCES public.medallion_evidence(tenant_id, entity_id, case_id, scenario_id, id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261118000800'),
('20261118000700'),
('20261118000600'),
('20261118000500'),
('20261118000400'),
('20261118000300'),
('20261118000200'),
('20261118000100'),
('20261115000900'),
('20261115000800'),
('20261115000700'),
('20261115000600'),
('20261115000500'),
('20261115000400'),
('20261115000300'),
('20261115000200'),
('20261115000100'),
('20261114000200'),
('20261114000100'),
('20261113000200'),
('20261113000100');

