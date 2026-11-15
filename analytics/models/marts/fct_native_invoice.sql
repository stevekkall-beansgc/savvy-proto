-- Header grain: never sum after joining to lines.
select tenant_id || ':' || entity_id || ':' || external_id as invoice_key,
       tenant_id,entity_id,external_id as invoice_id,revision,debtor_id,
       legacy_invoice_id,currency,amount_minor,status
from {{ source('synthetic','billing_invoices') }}
