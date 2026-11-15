with used as (
  select tenant_id,entity_id,obligation_id,sum(signed_application_minor) as applied_minor
  from {{ ref('fct_entitlement_entry') }} group by 1,2,3
)
select u.* from used u left join {{ ref('stg_evidence') }} o
  on o.kind='obligation' and o.tenant_id=u.tenant_id and o.entity_id=u.entity_id and o.external_id=u.obligation_id
where o.external_id is null or u.applied_minor<0 or u.applied_minor>(o.payload->>'amount_minor')::bigint
