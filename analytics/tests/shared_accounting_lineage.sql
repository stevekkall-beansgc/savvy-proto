select a.tenant_id,a.entity_id,a.acceptance_id
from {{ ref('fct_shared_mock_accounting') }} a
left join {{ source('synthetic','medallion_evidence') }} p
 on p.tenant_id=a.tenant_id and p.entity_id=a.entity_id and p.case_id=a.case_id
 and p.scenario_id='billing_platform' and p.kind='accounting_package' and p.external_id=a.input_package_id
where p.id is null or (a.reported_status='posted' and (a.journal_id is null or a.recognized_minor is null or a.deferred_minor is null))
