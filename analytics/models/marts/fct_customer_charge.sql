select evidence_key as charge_key, tenant_id, entity_id, external_id as charge_id,
       payload->>'customer_id' as customer_id, payload->>'currency' as currency,
       (payload->>'amount_minor')::bigint as charge_minor,
       payload->>'service_period_start' as service_period_start,
       payload->>'service_period_end' as service_period_end,
       revision as source_revision, payload_hash, recorded_at
from {{ ref('stg_evidence') }}
where kind='charge' and payload->>'status'='approved_for_collection'
