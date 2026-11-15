select id as entry_id,tenant_id,entity_id,grant_id,obligation_id,kind,minor_units,
       case when kind='consume' then minor_units else -minor_units end as signed_application_minor,
       currency,original_entry_id,reason,actor_id,business_date,created_at as recorded_at
from {{ source('synthetic','entitlement_entries') }}
