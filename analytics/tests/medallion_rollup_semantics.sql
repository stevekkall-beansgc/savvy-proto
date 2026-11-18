select r.rollup_key
from {{ ref('fct_medallion_rollup') }} r
join {{ ref('fct_medallion_result_detail') }} d on d.result_key = r.detailed_result_ref
join {{ ref('fct_medallion_publication') }} p
  on p.tenant_id = r.tenant_id and p.entity_id = r.entity_id
 and p.case_id = r.case_id and p.scenario_id = r.scenario_id
 and p.selected_run_id = r.selected_run_id
where r.comparison_only is distinct from d.comparison_only
   or r.selected_for_current_publication is distinct from p.selected_for_current_publication
   or r.publication_evidence_ref is distinct from p.publication_evidence_ref
   or r.output_class is distinct from d.output_class
   or r.aggregation_semantics <> 'nonadditive_component_snapshot'
   or (r.comparison_only and r.selected_for_current_publication is distinct from false)
