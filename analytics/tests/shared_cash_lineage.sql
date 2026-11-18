-- Independent source/claim identity and direction checks at application grain.
select a.tenant_id,a.entity_id,a.external_id
from {{ source('synthetic','medallion_evidence') }} a
left join {{ source('synthetic','medallion_evidence') }} s
 on s.tenant_id=a.tenant_id and s.entity_id=a.entity_id and s.case_id=a.case_id
 and s.scenario_id=a.scenario_id and s.id=a.parent_id and s.kind='normalized'
left join {{ source('synthetic','medallion_evidence') }} t
 on t.tenant_id=a.tenant_id and t.entity_id=a.entity_id and t.case_id=a.case_id
 and t.scenario_id=a.scenario_id and t.external_id=a.payload->>'target_id'
 and t.kind in ('document','payable')
where a.scenario_id='billing_platform' and a.kind='cash_application'
 and (s.id is null or t.id is null or s.payload_hash<>a.payload->>'cash_hash'
 or s.payload->'record'->>'type'<>'cash' or s.payload->'record'->>'status'<>'confirmed'
 or s.payload->'record'->>'billing_subject_id'<>t.payload->>'subject_id'
 or abs((a.payload->>'effect_minor')::bigint)<>(a.payload->>'amount_minor')::bigint
 or ((a.payload->>'effect_minor')::bigint>0) is distinct from
    ((t.kind='document' and s.payload->'record'->>'direction'='inbound')
      or (t.kind='payable' and s.payload->'record'->>'direction'='outbound')))
