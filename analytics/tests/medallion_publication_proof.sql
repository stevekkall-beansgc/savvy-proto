-- No comparison or unproven context snapshot can masquerade as a selected bill.
select p.publication_key
from {{ ref('fct_medallion_publication') }} p
left join {{ ref('stg_medallion_evidence') }} e
  on e.evidence_key = p.publication_evidence_ref
left join {{ ref('stg_medallion_evidence') }} r
  on r.tenant_id = p.tenant_id and r.entity_id = p.entity_id
 and r.case_id = p.case_id and r.scenario_id = p.scenario_id
 and r.kind = 'run' and r.external_id = p.selected_run_id
where (p.comparison_only and (p.selected_for_current_publication is distinct from false
                             or p.billing_evidence_status <> 'comparison_not_billed'))
   or (p.selected_for_current_publication is true and
       (e.id is null or e.kind <> 'publication' or e.status <> 'published'
        or p.publication_evidence_rank <> 1
        or e.tenant_id <> p.tenant_id or e.entity_id <> p.entity_id
        or e.case_id <> p.case_id or e.scenario_id <> p.scenario_id
        or coalesce(e.payload->>'run_id', e.payload->>'source_run_id') <> r.external_id
        or coalesce(e.payload->>'run_hash', e.payload->>'source_run_hash') <> r.payload_hash))
