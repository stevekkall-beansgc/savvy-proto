-- One current invoice per tenant and entity. Application evidence is independent
-- of operational cash matches; no application history means unknown, not zero.
with applications as (
  select tenant_id, entity_id, invoice_id,
         sum(active_minor) as applied_minor, count(*) as application_count
  from {{ ref('fct_invoice_application_history') }}
  group by 1,2,3
)
select i.evidence_key as invoice_key, i.tenant_id, i.entity_id,
       i.external_id as invoice_id, i.payload->>'charge_id' as charge_id,
       i.payload->>'customer_id' as customer_id, i.payload->>'currency' as currency,
       (i.payload->>'amount_minor')::bigint as amount_minor,
       c.service_period_start, c.service_period_end,
       a.applied_minor,
       case when a.application_count is not null then (i.payload->>'amount_minor')::bigint - a.applied_minor end as open_minor,
       case when a.application_count is null then 'unknown' else 'evidenced' end as application_status,
       i.revision as source_revision, i.payload_hash, i.recorded_at
from {{ ref('stg_evidence') }} i
left join {{ ref('fct_customer_charge') }} c
  on c.tenant_id=i.tenant_id and c.entity_id=i.entity_id and c.charge_id=i.payload->>'charge_id'
left join applications a
  on a.tenant_id=i.tenant_id and a.entity_id=i.entity_id and a.invoice_id=i.external_id
where i.kind='invoice'
