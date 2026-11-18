select p.publication_key
from {{ ref('fct_medallion_publication') }} p
left join {{ ref('stg_medallion_evidence') }} e
  on e.tenant_id = p.tenant_id
 and e.entity_id = p.entity_id
 and e.case_id = p.case_id
 and e.scenario_id = p.scenario_id
 and e.external_id = p.selected_run_id
 and e.kind = 'run'
where e.id is null
   or p.input_manifest_hash is distinct from e.payload->'result'->>'input_manifest_hash'
   or p.policy_manifest_hash is distinct from e.payload->'result'->>'policy_manifest_hash'
