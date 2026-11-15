select * from {{ ref('fct_preinvoice_charge_match') }}
where invoice_applied_minor is not null or bank_settled_minor is not null
   or recognized_revenue_minor is not null or accounting_ar_minor is not null
