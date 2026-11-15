-- All active applications count, including older revisions. A later source
-- correction may lower the amount; that is an exception, not corrupt history.
select min(a.application_key) as evidence_key
from {{ ref('fct_invoice_application_history') }} a
group by a.tenant_id,a.entity_id,a.receipt_id
having sum(a.active_minor) > max(a.receipt_amount_minor)
