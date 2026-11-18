-- Context snapshots are not bills. Keep actual selected runs even when a later
-- un-published retry has the same context, and retain every publication stream.
with ranked as (
  select *, row_number() over (
    partition by tenant_id, entity_id, case_id, scenario_id,
                 payload->'result'->>'input_manifest_hash',
                 payload->'result'->>'policy_manifest_hash',
                 payload->'result'->'context'
    order by recorded_at desc, id desc
  ) as selection_rank
  from {{ ref('stg_medallion_evidence') }} where kind = 'run'
), publications as (
  select *,
    coalesce(payload->>'run_id', payload->>'source_run_id') as published_run_id,
    coalesce(payload->>'run_hash', payload->>'source_run_hash') as published_run_hash,
    row_number() over (
      partition by tenant_id, entity_id, case_id, scenario_id,
                   coalesce(payload->>'projection_type', payload->>'publication_type', 'untyped')
      order by id desc
    ) as publication_rank
  from {{ ref('stg_medallion_evidence') }}
  where kind = 'publication' and status = 'published'
    and coalesce(payload->>'run_id', payload->>'source_run_id') is not null
    and coalesce(payload->>'run_hash', payload->>'source_run_hash') is not null
)
select r.evidence_key as publication_key, r.tenant_id, r.entity_id, r.case_id, r.scenario_id,
       r.external_id as selected_run_id,
       r.payload->'result'->'context' as context,
       r.payload->'result'->>'status' as calculation_status,
       r.payload->'result'->>'input_manifest_hash' as input_manifest_hash,
       r.payload->'result'->>'policy_manifest_hash' as policy_manifest_hash,
       r.recorded_at as retained_at,
       p.actual_published_at,
       r.recorded_at as published_at,
       'retained_run_clock'::text as snapshot_clock_basis,
       date_trunc('hour', r.recorded_at) as publication_hour,
       date_trunc('day', r.recorded_at) as publication_day,
       (r.payload->>'comparison_only')::boolean as comparison_only,
       case when (r.payload->>'comparison_only')::boolean is true then 'comparison_not_billed'
            else 'unproven_at_component_grain' end as billing_evidence_status,
       p.publication_evidence_ref, p.publication_evidence_rank,
       coalesce(p.publication_proofs, '[]'::jsonb) as publication_proofs,
       case when (r.payload->>'comparison_only')::boolean is true then false
            when p.publication_evidence_ref is null then null
            else p.has_current_publication end as selected_for_current_publication,
       'retained_context_snapshot'::text as selection_semantics
from ranked r
left join lateral (
  select (array_agg(p.evidence_key order by (p.publication_rank = 1) desc, p.id desc))[1] as publication_evidence_ref,
         (array_agg(p.publication_rank order by (p.publication_rank = 1) desc, p.id desc))[1] as publication_evidence_rank,
         bool_or(p.publication_rank = 1) as has_current_publication,
         max(p.recorded_at) as actual_published_at,
         jsonb_agg(jsonb_build_object('evidence_ref', p.evidence_key,
           'is_current', p.publication_rank = 1) order by p.id) as publication_proofs
  from publications p
  where p.tenant_id = r.tenant_id and p.entity_id = r.entity_id
    and p.case_id = r.case_id and p.scenario_id = r.scenario_id
    and p.published_run_id = r.external_id and p.published_run_hash = r.payload_hash
) p on true
where r.selection_rank = 1 or p.has_current_publication is true
