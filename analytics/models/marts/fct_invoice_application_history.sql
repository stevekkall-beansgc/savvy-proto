-- One immutable application, with an optional full reversal; never infer from a cash match.
with reversals as (
  select tenant_id, entity_id, payload->>'reversal_of_id' as original_id,
         min(external_id) as reversal_id, min(recorded_at) as reversed_at
  from {{ ref('stg_evidence') }} where kind='invoice_application_reversal'
  group by 1,2,3
)
select a.evidence_key as application_key, a.tenant_id, a.entity_id,
       a.external_id as application_id, a.payload->>'invoice_id' as invoice_id,
       a.payload->>'receipt_id' as receipt_id, a.payload->>'currency' as currency,
       (a.payload->>'receipt_revision')::integer as receipt_revision,
       (a.payload->>'receipt_amount_minor')::bigint as receipt_amount_minor,
       a.payload->>'customer_id' as customer_id,
       (a.payload->>'minor_units')::bigint as original_minor,
       case when r.reversal_id is null then (a.payload->>'minor_units')::bigint else 0 end as active_minor,
       r.reversal_id, a.payload->>'business_date' as business_date,
       a.recorded_at, r.reversed_at
from {{ ref('stg_evidence') }} a
left join reversals r on r.tenant_id=a.tenant_id and r.entity_id=a.entity_id and r.original_id=a.external_id
where a.kind='invoice_application'
