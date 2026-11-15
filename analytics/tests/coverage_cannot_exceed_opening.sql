with applied as (
  select e.tenant_id,e.entity_id,e.external_id as run_id,a->>'grant_id' as grant_id,
         sum((a->>'applied_minor')::bigint) as applied_minor
  from {{ ref('stg_evidence') }} e
  cross join lateral jsonb_array_elements(e.payload->'lines') l
  cross join lateral jsonb_array_elements(l->'coverage'->'allocations') a
  where e.kind='run' group by 1,2,3,4
), opening as (
  select e.tenant_id,e.entity_id,e.external_id as run_id,g->>'id' as grant_id,(g->>'remaining_minor')::bigint as opening_minor
  from {{ ref('stg_evidence') }} e
  cross join lateral jsonb_array_elements(e.payload->'inputs'->'snapshot'->'grants') g where e.kind='run'
)
select a.* from applied a left join opening o using(tenant_id,entity_id,run_id,grant_id)
where o.grant_id is null or a.applied_minor>o.opening_minor
