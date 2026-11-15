select * from {{ ref('fct_preinvoice_charge_match') }}
where charge_minor != matched_minor + unmatched_charge_minor
   or matched_minor < 0 or unmatched_charge_minor < 0 or matched_minor > charge_minor
