select m.id as application_id, m.tenant_id, m.entity_id, m.source_id as receipt_id,
       m.target_id as charge_id, c.customer_id, m.currency, m.minor_units as operational_match_minor,
       m.created_at as observed_match_at
from {{ source('synthetic','operational_matches') }} m
join {{ ref('fct_customer_charge') }} c
  on c.tenant_id=m.tenant_id and c.entity_id=m.entity_id and c.charge_id=m.target_id
