select * from {{ ref('fct_entitlement_balance') }}
where remaining_minor<0 or remaining_minor>opening_minor
   or opening_minor!=net_applied_minor+remaining_minor or currency!='USD'
