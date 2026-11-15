with matches as (
  select tenant_id,entity_id,charge_id,sum(operational_match_minor) as matched_minor
  from {{ ref('fct_customer_cash_application') }} group by 1,2,3
), receipts as (
  select tenant_id,entity_id,payload->>'customer_id' as customer_id,payload->>'currency' as currency,
         sum(case when payload->>'status'='verified_cash' then (payload->>'amount_minor')::bigint else 0 end) as observed_cash_minor,
         sum(case when payload->>'status'='reversed' then (payload->>'amount_minor')::bigint else 0 end) as reversed_receipt_minor
  from {{ ref('stg_evidence') }} where kind='receipt' and payload->>'status' in ('verified_cash','reversed')
  group by 1,2,3,4
), invoices as (
  select tenant_id,entity_id,payload->>'charge_id' as charge_id,count(*) as linked_invoice_count
  from {{ ref('stg_evidence') }} where kind='invoice' group by 1,2,3
)
select c.*, coalesce(m.matched_minor,0) as matched_minor,
       c.charge_minor-coalesce(m.matched_minor,0) as unmatched_charge_minor,
       r.observed_cash_minor as customer_cash_context_minor,
       r.reversed_receipt_minor as customer_reversed_receipt_minor,
       coalesce(i.linked_invoice_count,0) as linked_invoice_count,
       null::bigint as invoice_applied_minor, null::bigint as bank_settled_minor,
       null::bigint as recognized_revenue_minor, null::bigint as accounting_ar_minor,
       'unknown_accounting_evidence'::text as accounting_status
from {{ ref('fct_customer_charge') }} c
left join matches m using(tenant_id,entity_id,charge_id)
left join receipts r using(tenant_id,entity_id,customer_id,currency)
left join invoices i using(tenant_id,entity_id,charge_id)
