-- Source-reported mock outcomes, not recognition derived from billing or cash.
select tenant_id,entity_id,case_id,external_id as acceptance_id,
       payload->>'target_id' as root_id,payload->>'package_id' as input_package_id,
       payload->>'reported_status' as reported_status,payload->>'journal_id' as journal_id,
       (payload->>'recognized_minor')::bigint as recognized_minor,
       (payload->>'deferred_minor')::bigint as deferred_minor,
       (payload->>'reported_ar_minor')::bigint as reported_ar_minor,
       payload->>'replaces_record_id' as replaces_record_id,
       payload->>'reversal_journal_id' as reversal_journal_id,
       payload->>'ledger_hash' as ledger_hash,recorded_at
from {{ source('synthetic','medallion_evidence') }}
where scenario_id='billing_platform' and kind='accounting_acceptance'
