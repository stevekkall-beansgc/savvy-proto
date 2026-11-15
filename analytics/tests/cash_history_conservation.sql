select * from {{ ref('fct_cash_match_history') }}
where original_minor!=active_minor+released_minor or active_minor<0 or released_minor<0
