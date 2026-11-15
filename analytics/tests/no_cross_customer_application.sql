select a.* from {{ ref('fct_customer_cash_application') }} a
left join {{ ref('stg_evidence') }} r
  on r.kind='receipt' and r.tenant_id=a.tenant_id and r.entity_id=a.entity_id and r.external_id=a.receipt_id
where r.external_id is null or r.payload->>'customer_id' != a.customer_id
   or r.payload->>'currency' != a.currency or r.payload->>'status' != 'verified_cash'
