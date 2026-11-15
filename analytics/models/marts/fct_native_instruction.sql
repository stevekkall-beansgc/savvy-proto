-- Instruction grain: execution status is source-reported and may be unknown.
select tenant_id || ':' || entity_id || ':' || external_id as instruction_key,
       tenant_id,entity_id,external_id as instruction_id,revision,amount_minor,status,execution_status
from {{ source('synthetic','billing_instructions') }}
