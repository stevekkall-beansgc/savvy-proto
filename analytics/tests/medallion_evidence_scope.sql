select child.evidence_key
from {{ ref('stg_medallion_evidence') }} child
left join {{ ref('stg_medallion_evidence') }} parent
  on parent.id = child.parent_id
 and parent.tenant_id = child.tenant_id
 and parent.entity_id = child.entity_id
 and parent.case_id = child.case_id
 and parent.scenario_id = child.scenario_id
where (child.parent_id is not null and parent.id is null)
   or child.revision < 1
   or length(child.payload_hash) <> 64
