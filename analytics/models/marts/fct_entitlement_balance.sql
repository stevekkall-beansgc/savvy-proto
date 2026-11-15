with applied as (
  select tenant_id,entity_id,grant_id,sum(signed_application_minor) as net_applied_minor
  from {{ ref('fct_entitlement_entry') }} group by 1,2,3
)
select e.evidence_key as grant_key,e.tenant_id,e.entity_id,e.external_id as grant_id,
       e.payload->>'payer' as payer,e.payload->>'payee' as payee,e.payload->>'component' as component,
       e.payload->>'currency' as currency,(e.payload->>'opening_minor')::bigint as opening_minor,
       coalesce(a.net_applied_minor,0) as net_applied_minor,
       (e.payload->>'opening_minor')::bigint-coalesce(a.net_applied_minor,0) as remaining_minor
from {{ ref('stg_evidence') }} e
left join applied a on a.tenant_id=e.tenant_id and a.entity_id=e.entity_id and a.grant_id=e.external_id
where e.kind='grant'
