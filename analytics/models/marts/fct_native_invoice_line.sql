select l.tenant_id || ':' || l.entity_id || ':' || l.external_id as line_key,
       l.tenant_id,l.entity_id,l.external_id as line_id,h.external_id as invoice_id,
       h.revision as invoice_revision,h.debtor_id,h.legacy_invoice_id,
       o.external_id as obligation_id,o.customer_id,o.service_id,o.account_id,o.assignment_id,
       o.source_id,o.source_revision,o.client_terms_ref,l.amount_minor,h.currency
from {{ source('synthetic','billing_invoice_lines') }} l
join {{ source('synthetic','billing_invoices') }} h on h.tenant_id=l.tenant_id and h.entity_id=l.entity_id and h.id=l.billing_invoice_id
join {{ source('synthetic','billing_obligations') }} o on o.tenant_id=l.tenant_id and o.entity_id=l.entity_id and o.id=l.billing_obligation_id
