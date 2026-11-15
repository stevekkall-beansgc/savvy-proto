with latest as (
  select payload from {{ source('synthetic','records') }} where kind='snapshot'
  order by recorded_at desc limit 1
)
select payload from latest
where (payload->>'complete')::boolean is distinct from true
  or jsonb_array_length(payload->'facts')=0
  or (payload->>'watermark')::timestamptz < (payload->>'minimum_watermark')::timestamptz
