select id as application_id, tenant_id, entity_id, source_id as receipt_id,
       target_id as charge_id, currency, minor_units as original_minor,
       case when reversal_id is null then minor_units else 0 end as active_minor,
       case when reversal_id is not null then minor_units else 0 end as released_minor,
       reversal_id, reversal_reason, created_at as applied_at, reversed_at
from {{ source('synthetic','match_history') }}
