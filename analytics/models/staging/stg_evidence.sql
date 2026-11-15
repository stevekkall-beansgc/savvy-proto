select distinct on (tenant_id, entity_id, kind, external_id)
    tenant_id || ':' || entity_id || ':' || kind || ':' || external_id as evidence_key,
    tenant_id, entity_id, kind, external_id, revision, payload_hash, payload, recorded_at
from {{ source('synthetic','records') }}
order by tenant_id, entity_id, kind, external_id, revision desc, recorded_at desc
