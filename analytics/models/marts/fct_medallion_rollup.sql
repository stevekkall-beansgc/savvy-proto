-- Selected component snapshots, independently published hourly or daily.
-- No commercial formula runs here. Never sum snapshots, alternate policies,
-- or a summary and its child components as additional earnings.
select p.publication_key || ':' || d.detail_id || ':' || cadence.grain as rollup_key,
       p.tenant_id, p.entity_id, p.case_id, p.scenario_id, p.selected_run_id,
       p.input_manifest_hash, p.policy_manifest_hash, p.calculation_status,
       p.comparison_only, p.publication_evidence_ref, p.publication_proofs,
       p.retained_at, p.actual_published_at, p.snapshot_clock_basis,
       p.selected_for_current_publication, p.billing_evidence_status, p.selection_semantics,
       cadence.grain as publication_grain,
       case cadence.grain when 'hour' then p.publication_hour else p.publication_day end as publication_bucket,
       d.context->>'service_start' as service_start,
       d.context->>'service_end_exclusive' as service_end_exclusive,
       d.economic_key, d.component, d.output_role, d.output_class, d.dependency_refs,
       d.aggregation_semantics, d.payer_id, d.payee_id,
       d.subject_id, d.currency, d.unit, d.assessed_minor,
       'snapshot'::text as temporal_semantics,
       d.result_key as detailed_result_ref
from {{ ref('fct_medallion_publication') }} p
join {{ ref('fct_medallion_result_detail') }} d
  on d.tenant_id = p.tenant_id and d.entity_id = p.entity_id
 and d.case_id = p.case_id and d.scenario_id = p.scenario_id
 and d.run_id = p.selected_run_id
cross join (values ('hour'), ('day')) as cadence(grain)
where d.output_role in ('terminal', 'summary')
  and d.amount_basis = 'assessed'
  and d.assessed_minor is not null
