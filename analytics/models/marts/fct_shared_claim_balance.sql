-- Native claim grain, independently applied cash. Billing, cash and recognition
-- remain separate measures; this projection never calculates a commercial fee.
with claims as (
 select e.tenant_id,e.entity_id,e.case_id,
        coalesce(e.payload->>'original_document_id',e.external_id) as root_id,
        h.amount_minor * case when h.document_type='credit_note' then -1 else 1 end as signed_minor
 from {{ source('synthetic','medallion_evidence') }} e
 join {{ source('synthetic','billing_invoices') }} h
   on h.tenant_id=e.tenant_id and h.entity_id=e.entity_id and h.id=(e.payload->>'native_invoice_id')::bigint
 where e.scenario_id='billing_platform' and e.kind='document'
), applied as (
 select a.tenant_id,a.entity_id,a.case_id,a.payload->>'target_id' as root_id,
        sum((a.payload->>'effect_minor')::bigint) as applied_minor
 from {{ source('synthetic','medallion_evidence') }} a
 where a.scenario_id='billing_platform' and a.kind='cash_application'
 and not exists (select 1 from {{ source('synthetic','medallion_evidence') }} r
   where r.tenant_id=a.tenant_id and r.entity_id=a.entity_id and r.case_id=a.case_id
     and r.scenario_id=a.scenario_id and r.kind='cash_reversal' and r.parent_id=a.id)
 group by 1,2,3,4
)
select c.tenant_id,c.entity_id,c.case_id,c.root_id,
       sum(c.signed_minor) as net_billed_minor,coalesce(a.applied_minor,0) as applied_minor,
       sum(c.signed_minor)-coalesce(a.applied_minor,0) as balance_minor
from claims c left join applied a using(tenant_id,entity_id,case_id,root_id)
group by c.tenant_id,c.entity_id,c.case_id,c.root_id,a.applied_minor
