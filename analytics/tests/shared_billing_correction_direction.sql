select tenant_id,entity_id,invoice_id
from {{ ref('fct_native_invoice') }}
where (document_type='credit_note' and signed_billed_minor<>-amount_minor)
   or (document_type<>'credit_note' and signed_billed_minor<>amount_minor)
   or (document_type in ('credit_note','debit_note') and corrects_invoice_id is null)
