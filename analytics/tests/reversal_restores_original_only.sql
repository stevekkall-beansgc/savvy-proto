select r.* from {{ ref('fct_entitlement_entry') }} r
left join {{ ref('fct_entitlement_entry') }} o on o.entry_id=r.original_entry_id
where r.kind='reversal' and (o.entry_id is null or o.kind!='consume' or o.minor_units!=r.minor_units
  or o.grant_id!=r.grant_id or o.obligation_id!=r.obligation_id or o.tenant_id!=r.tenant_id
  or o.entity_id!=r.entity_id or o.currency!=r.currency)
