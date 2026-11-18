select tenant_id || ':' || entity_id || ':' || case_id || ':' || scenario_id || ':' || kind || ':' ||
       external_id || ':' || revision::text as evidence_key,
       id, tenant_id, entity_id, case_id, scenario_id, kind, external_id, revision, status,
       subject_id, parent_id, payload_hash, payload, recorded_at
from {{ source('synthetic', 'medallion_evidence') }}
