select o.tenant_id,o.entity_id,o.external_id
from {{ source('synthetic','billing_obligations') }} o
left join {{ source('synthetic','billing_invoice_lines') }} l on l.tenant_id=o.tenant_id and l.entity_id=o.entity_id and l.billing_obligation_id=o.id
left join {{ source('synthetic','billing_instruction_items') }} i on i.tenant_id=o.tenant_id and i.entity_id=o.entity_id and i.billing_obligation_id=o.id
where (o.route='invoice' and (l.id is null or i.id is not null or l.amount_minor<>o.amount_minor))
   or (o.route='custodial' and (i.id is null or l.id is not null or i.amount_minor<>o.amount_minor))
