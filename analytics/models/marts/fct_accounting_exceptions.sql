select charge_key,tenant_id,entity_id,customer_id,currency,charge_id,
       'ACCOUNTING_EVIDENCE_MISSING'::text as code,
       'Demo controller'::text as owner,
       'Obtain separately authorized invoice application, bank and recognition evidence'::text as next_action
from {{ ref('fct_preinvoice_charge_match') }}
where invoice_applied_minor is null or bank_settled_minor is null or recognized_revenue_minor is null
