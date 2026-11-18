-- Every actual current publication survives a later unpublished context retry.
-- Multiple streams for the same run must retain all proof references.
with current_publications as (
  select *, row_number() over (
    partition by tenant_id, entity_id, case_id, scenario_id,
      coalesce(payload->>'projection_type', payload->>'publication_type', 'untyped')
    order by id desc) as selection_rank
  from {{ ref('stg_medallion_evidence') }}
  where kind = 'publication' and status = 'published'
    and coalesce(payload->>'run_id', payload->>'source_run_id') is not null
    and coalesce(payload->>'run_hash', payload->>'source_run_hash') is not null
)
select e.evidence_key
from current_publications e
join {{ ref('stg_medallion_evidence') }} run
  on run.kind = 'run' and run.tenant_id = e.tenant_id and run.entity_id = e.entity_id
 and run.case_id = e.case_id and run.scenario_id = e.scenario_id
 and run.external_id = coalesce(e.payload->>'run_id', e.payload->>'source_run_id')
 and run.payload_hash = coalesce(e.payload->>'run_hash', e.payload->>'source_run_hash')
where e.selection_rank = 1 and (run.payload->>'comparison_only')::boolean is not true
  and not exists (
    select 1 from {{ ref('fct_medallion_publication') }} p
    cross join lateral jsonb_array_elements(p.publication_proofs) proof
    where p.tenant_id = e.tenant_id and p.entity_id = e.entity_id
      and p.case_id = e.case_id and p.scenario_id = e.scenario_id
      and p.selected_run_id = run.external_id and p.selected_for_current_publication is true
      and proof->>'evidence_ref' = e.evidence_key and (proof->>'is_current')::boolean is true
  )
