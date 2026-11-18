select result_key
from {{ ref('fct_medallion_result_detail') }}
where economic_key is null or detail_id is null
   or output_role not in ('intermediate', 'terminal', 'summary')
   or (amount_basis <> 'assessed' and assessed_minor is not null)
