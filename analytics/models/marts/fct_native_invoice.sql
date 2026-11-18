-- Header grain: never sum after joining to lines.
select tenant_id || ':' || entity_id || ':' || external_id as invoice_key,
       tenant_id,entity_id,external_id as invoice_id,revision,debtor_id,
       legacy_invoice_id,currency,amount_minor,status,document_type,corrects_invoice_id,
       creditor_id,billing_case_id,billing_subject_id,issued_on,due_on,posting_period,calculation_ref,
       case when document_type='credit_note' then -amount_minor else amount_minor end as signed_billed_minor
from {{ source('synthetic','billing_invoices') }}
