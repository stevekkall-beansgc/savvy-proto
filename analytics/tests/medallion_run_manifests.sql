select evidence_key
from {{ ref('stg_medallion_evidence') }}
where kind = 'run'
  and (
    length(coalesce(payload->'result'->>'input_manifest_hash', '')) <> 64
    or length(coalesce(payload->'result'->>'policy_manifest_hash', '')) <> 64
    or payload->'result'->'context'->>'tenant_id' is distinct from tenant_id
    or payload->'result'->'context'->>'entity_id' is distinct from entity_id
    or jsonb_typeof(payload->'result'->'details') is distinct from 'array'
    or jsonb_typeof(payload->'result'->'bindings') is distinct from 'array'
    or jsonb_typeof(payload->'result'->'exceptions') is distinct from 'array'
  )
