select h.tenant_id,h.entity_id,h.external_id
from {{ source('synthetic','billing_invoices') }} h
left join {{ source('synthetic','billing_invoice_lines') }} l on l.tenant_id=h.tenant_id and l.entity_id=h.entity_id and l.billing_invoice_id=h.id
group by h.tenant_id,h.entity_id,h.external_id,h.amount_minor
having count(l.id)=0 or sum(l.amount_minor)<>h.amount_minor
union all
select h.tenant_id,h.entity_id,h.external_id
from {{ source('synthetic','billing_instructions') }} h
left join {{ source('synthetic','billing_instruction_items') }} i on i.tenant_id=h.tenant_id and i.entity_id=h.entity_id and i.billing_instruction_id=h.id
group by h.tenant_id,h.entity_id,h.external_id,h.amount_minor
having count(i.id)=0 or sum(i.amount_minor)<>h.amount_minor
