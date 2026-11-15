with members as (
 select m.tenant_id,m.entity_id,m.batch_id,sum(m.receipt_amount_minor) as receipt_total
 from {{ ref('bridge_bank_batch_receipt') }} m
 group by 1,2,3
)
select b.batch_key from {{ ref('fct_bank_batch') }} b
left join members m on m.tenant_id=b.tenant_id and m.entity_id=b.entity_id and m.batch_id=b.batch_id
where m.receipt_total is null or b.gross_minor <> m.receipt_total
union all
select min(b.batch_key) from {{ ref('fct_bank_batch') }} b
join {{ ref('bridge_bank_batch_receipt') }} m on m.tenant_id=b.tenant_id and m.entity_id=b.entity_id and m.batch_id=b.batch_id
where b.status='active' group by m.tenant_id,m.entity_id,m.receipt_id having count(*) > 1
