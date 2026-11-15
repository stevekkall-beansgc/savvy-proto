select * from {{ ref('fct_broker_economics') }}
where earned_minor != coverage_minor + incremental_cash_minor
   or coverage_minor < 0 or incremental_cash_minor < 0 or currency!='USD'
