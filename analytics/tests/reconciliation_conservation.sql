select invoice_key as evidence_key from {{ ref('fct_invoice_balance') }}
where (application_status='unknown' and (applied_minor is not null or open_minor is not null))
   or (application_status='evidenced' and (applied_minor is null or open_minor is null or applied_minor < 0 or open_minor < 0 or amount_minor <> applied_minor + open_minor))
union all
select batch_key from {{ ref('fct_bank_batch') }}
where gross_minor < 0 or fee_minor < 0 or net_minor < 0 or gross_minor <> fee_minor + net_minor
