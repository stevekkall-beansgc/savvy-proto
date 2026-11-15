select e.* from {{ ref('fct_entitlement_entry') }} e
left join {{ ref('stg_evidence') }} g on g.kind='grant' and g.tenant_id=e.tenant_id and g.entity_id=e.entity_id and g.external_id=e.grant_id
left join {{ ref('stg_evidence') }} o on o.kind='obligation' and o.tenant_id=e.tenant_id and o.entity_id=e.entity_id and o.external_id=e.obligation_id
where g.external_id is null or o.external_id is null or g.payload->>'payer'!=o.payload->>'payer'
  or g.payload->>'payee'!=o.payload->>'payee' or g.payload->>'component'!=o.payload->>'component'
  or g.payload->>'currency'!=e.currency or o.payload->>'currency'!=e.currency
