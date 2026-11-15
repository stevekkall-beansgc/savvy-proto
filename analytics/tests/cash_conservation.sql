with used as (
  select tenant_id,entity_id,receipt_id,sum(operational_match_minor) as used_minor
  from {{ ref('fct_customer_cash_application') }} group by 1,2,3
)
select u.* from used u
left join {{ ref('stg_evidence') }} e
  on e.kind='receipt' and e.tenant_id=u.tenant_id and e.entity_id=u.entity_id and e.external_id=u.receipt_id
where e.external_id is null or used_minor>(e.payload->>'amount_minor')::bigint
