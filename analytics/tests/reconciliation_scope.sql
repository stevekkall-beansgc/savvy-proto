select a.application_key as evidence_key
from {{ ref('fct_invoice_application_history') }} a
left join {{ ref('fct_invoice_balance') }} i on i.tenant_id=a.tenant_id and i.entity_id=a.entity_id and i.invoice_id=a.invoice_id
left join {{ ref('stg_evidence') }} r on r.tenant_id=a.tenant_id and r.entity_id=a.entity_id and r.kind='receipt' and r.external_id=a.receipt_id
where i.invoice_id is null or r.external_id is null or i.customer_id is distinct from a.customer_id
   or i.currency is distinct from a.currency
union all
select m.membership_key
from {{ ref('bridge_bank_batch_receipt') }} m
left join {{ ref('stg_evidence') }} r on r.tenant_id=m.tenant_id and r.entity_id=m.entity_id and r.kind='receipt' and r.external_id=m.receipt_id
left join {{ ref('fct_bank_batch') }} b on b.tenant_id=m.tenant_id and b.entity_id=m.entity_id and b.batch_id=m.batch_id
where r.external_id is null or b.currency is distinct from m.currency
