-- Membership only; batch amounts stay in fct_bank_batch at entity/batch grain.
select b.tenant_id, b.entity_id, b.external_id as batch_id, m.receipt_id,
       b.evidence_key || ':' || m.receipt_id as membership_key,
       (captured.value->>'revision')::integer as receipt_revision,
       (captured.value->>'amount_minor')::bigint as receipt_amount_minor,
       captured.value->>'customer_id' as customer_id, captured.value->>'currency' as currency
from {{ ref('stg_evidence') }} b
cross join lateral jsonb_array_elements_text(b.payload->'receipt_ids') as m(receipt_id)
left join lateral jsonb_array_elements(coalesce(b.payload->'receipt_evidence','[]'::jsonb)) captured(value)
  on captured.value->>'id'=m.receipt_id
where b.kind='bank_batch'
