select (select count(*) from {{ source('synthetic','operational_matches') }}) as original_count,
       (select count(*) from {{ ref('fct_customer_cash_application') }}) as modeled_count
where (select count(*) from {{ source('synthetic','operational_matches') }}) !=
      (select count(*) from {{ ref('fct_customer_cash_application') }})
