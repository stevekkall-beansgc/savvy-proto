select e.tenant_id, e.entity_id, e.external_id as run_id,
       e.external_id || ':' || (l->>'id') as line_key,
       l->>'source_id' as source_id, l->>'source_revision' as source_revision,
       l->>'customer_id' as customer_id, l->>'broker_id' as broker_id,
       l->>'relationship_id' as relationship_id, l->>'currency' as currency,
       (l->>'eligible_minor')::bigint as eligible_minor,
       (l->>'earned_minor')::bigint as earned_minor,
       (l->'coverage'->>'coverage_minor')::bigint as coverage_minor,
       (l->'coverage'->>'incremental_cash_minor')::bigint as incremental_cash_minor,
       l->'trace'->>'winner' as winning_rule,
       e.payload->>'status' as completeness, e.payload->>'business_date' as business_date,
       e.payload->>'knowledge_cutoff' as knowledge_cutoff, e.payload->>'input_hash' as input_hash,
       e.payload->>'policy_hash' as policy_hash, e.payload->>'engine_version' as engine_version,
       e.payload_hash as run_payload_hash
from {{ ref('stg_evidence') }} e
cross join lateral jsonb_array_elements(e.payload->'lines') l
where e.kind='run'
