-- One executed accrual node/day/account-policy segment. These are exact accruals,
-- not additional assessed invoices. Never sum this with fct_native_invoice.
select e.tenant_id,e.entity_id,e.case_id,e.external_id as calculation_id,
       e.payload->>'subject_id' as billing_subject_id,
       s.value->>'policy_id' as policy_id,d.value->>'id' as node_id,
       d.value->>'component' as component,
       (d.value->'interval'->>'start')::date as service_date,
       d.value->>'exact_amount' as exact_minor_rational,
       d.value->'source_refs' as source_refs
from {{ source('synthetic','medallion_evidence') }} e
cross join lateral jsonb_array_elements(e.payload->'segments') s(value)
cross join lateral jsonb_array_elements(s.value->'result'->'details') d(value)
where e.scenario_id='billing_platform' and e.kind='calculation'
  and d.value->>'basis'='exact_accrual'
  and d.value->>'explanation' like 'Accrual for %'
