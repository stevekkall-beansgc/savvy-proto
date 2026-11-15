select a.tenant_id || ':' || a.entity_id || ':' || a.external_id as accounting_key,
       a.tenant_id,a.entity_id,a.external_id as accounting_id,'mock_campfire'::text as provider,
       coalesce(h.external_id,i.external_id) as commercial_id,a.commercial_revision,
       a.reported_status,a.applied_minor,a.ar_minor,a.recognized_minor,a.observed_at,a.mocked
from {{ source('synthetic','billing_accounting_facts') }} a
left join {{ source('synthetic','billing_invoices') }} h on h.tenant_id=a.tenant_id and h.entity_id=a.entity_id and h.id=a.billing_invoice_id
left join {{ source('synthetic','billing_instructions') }} i on i.tenant_id=a.tenant_id and i.entity_id=a.entity_id and i.id=a.billing_instruction_id
