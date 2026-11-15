select tenant_id || ':' || entity_id || ':' || external_id as obligation_key,
       tenant_id,entity_id,id as obligation_pk,external_id as obligation_id,revision,
       customer_id,service_id,broker_id,account_id,assignment_id,client_terms_ref,
       source_id,source_revision,legacy_charge_id,route,currency,amount_minor,
       service_period_start,service_period_end
from {{ source('synthetic','billing_obligations') }}
