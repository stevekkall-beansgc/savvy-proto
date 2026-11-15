-- Entity-grain bank evidence. Do not join this measure-bearing table to receipt
-- membership before summing: membership is available separately without amounts.
with reversals as (
  select tenant_id, entity_id, payload->>'reversal_of_id' as original_id,
         min(external_id) as reversal_id, min(recorded_at) as reversed_at
  from {{ ref('stg_evidence') }} where kind='bank_batch_reversal'
  group by 1,2,3
)
select b.evidence_key as batch_key, b.tenant_id, b.entity_id, b.external_id as batch_id,
       b.payload->>'currency' as currency, (b.payload->>'gross_minor')::bigint as gross_minor,
       (b.payload->>'fee_minor')::bigint as fee_minor, (b.payload->>'net_minor')::bigint as net_minor,
       b.payload->>'business_date' as business_date, b.recorded_at,
       r.reversal_id, r.reversed_at,
       case when r.reversal_id is null then 'active' else 'reversed' end as status
from {{ ref('stg_evidence') }} b
left join reversals r on r.tenant_id=b.tenant_id and r.entity_id=b.entity_id and r.original_id=b.external_id
where b.kind='bank_batch'
