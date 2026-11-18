-- One retained run x logical detail. Alternative runs are never additive.
select e.evidence_key || ':' || (d->>'id') as result_key,
       e.tenant_id, e.entity_id, e.case_id, e.scenario_id,
       e.external_id as run_id, e.recorded_at as published_at,
       e.payload->'result'->>'input_manifest_hash' as input_manifest_hash,
       e.payload->'result'->>'policy_manifest_hash' as policy_manifest_hash,
       e.payload->'result'->>'engine_language_version' as engine_language_version,
       e.payload->'result'->>'status' as calculation_status,
       e.payload->'result'->'context' as context,
       d->>'id' as detail_id, d->>'economic_key' as economic_key,
       d->>'component' as component, d->>'role' as output_role,
       d->>'output_class' as output_class,
       d->'dependency_refs' as dependency_refs,
       (e.payload->>'comparison_only')::boolean as comparison_only,
       'nonadditive_component_snapshot'::text as aggregation_semantics,
       d->>'payer' as payer_id, d->>'payee' as payee_id,
       d->>'subject' as subject_id, d->>'currency' as currency,
       d->>'unit' as unit, d->>'basis' as amount_basis,
       d->>'exact_amount' as exact_amount,
       (d->>'assessed_minor')::numeric as assessed_minor,
       d as detail
from {{ ref('stg_medallion_evidence') }} e
cross join lateral jsonb_array_elements(e.payload->'result'->'details') d
where e.kind = 'run'
