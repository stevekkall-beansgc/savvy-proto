-- Explicit independent-evidence conflicts. A receipt correction does not reverse
-- an application or a bank batch, and neither constitutes accounting recognition.
select a.tenant_id,a.entity_id,'REVERSED_RECEIPT_INVOICE_APPLICATION'::text as code,
       'Demo controller'::text as owner,'Review and reverse or correct independent invoice evidence'::text as next_action,
       a.application_id as evidence_id,a.receipt_id
from {{ ref('fct_invoice_application_history') }} a
left join {{ ref('stg_evidence') }} r on r.tenant_id=a.tenant_id and r.entity_id=a.entity_id
  and r.kind='receipt' and r.external_id=a.receipt_id
where a.reversal_id is null and (r.external_id is null or r.payload->>'status' is distinct from 'verified_cash'
  or r.revision is distinct from a.receipt_revision or (r.payload->>'amount_minor')::bigint is distinct from a.receipt_amount_minor
  or r.payload->>'customer_id' is distinct from a.customer_id or r.payload->>'currency' is distinct from a.currency)
union all
select m.tenant_id,m.entity_id,'REVERSED_RECEIPT_BANK_BATCH',
       'Demo controller','Review and reverse or correct independent bank evidence',m.batch_id,m.receipt_id
from {{ ref('bridge_bank_batch_receipt') }} m
join {{ ref('fct_bank_batch') }} b on b.tenant_id=m.tenant_id and b.entity_id=m.entity_id and b.batch_id=m.batch_id
left join {{ ref('stg_evidence') }} r on r.tenant_id=m.tenant_id and r.entity_id=m.entity_id
  and r.kind='receipt' and r.external_id=m.receipt_id
where b.status='active' and (r.external_id is null or r.payload->>'status' is distinct from 'verified_cash'
  or r.revision is distinct from m.receipt_revision or (r.payload->>'amount_minor')::bigint is distinct from m.receipt_amount_minor
  or r.payload->>'customer_id' is distinct from m.customer_id or r.payload->>'currency' is distinct from m.currency)
union all
select i.tenant_id,i.entity_id,'INVOICE_APPLICATION_UNKNOWN',
       'Demo controller','Obtain independent invoice application evidence',i.invoice_id,null::text
from {{ ref('fct_invoice_balance') }} i where i.application_status='unknown'
union all
select e.tenant_id,e.entity_id,'BANK_SETTLEMENT_UNKNOWN',
       'Demo controller','Obtain independent bank batch evidence',null::text,null::text
from (select distinct tenant_id,entity_id from {{ ref('stg_evidence') }} where kind in ('charge','invoice','receipt')) e
where not exists (select 1 from {{ ref('fct_bank_batch') }} b where b.tenant_id=e.tenant_id and b.entity_id=e.entity_id)
union all
select e.tenant_id,e.entity_id,'RECOGNITION_UNKNOWN',
       'Demo controller','Obtain separate recognition evidence',null::text,null::text
from (select distinct tenant_id,entity_id from {{ ref('stg_evidence') }} where kind in ('charge','invoice','receipt')) e
