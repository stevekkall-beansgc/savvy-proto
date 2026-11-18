select r.rollup_key
from {{ ref('fct_medallion_rollup') }} r
join {{ ref('fct_medallion_result_detail') }} d on d.result_key = r.detailed_result_ref
where r.assessed_minor is distinct from d.assessed_minor
   or r.temporal_semantics <> 'snapshot'
   or r.publication_grain not in ('hour', 'day')
