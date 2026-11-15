#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null
uv venv .runtime/dbt --allow-existing --cache-dir "$PWD/.runtime/uv-cache"
uv pip sync --python .runtime/dbt/bin/python --cache-dir "$PWD/.runtime/uv-cache" analytics/requirements.lock
docker compose exec -T db psql -U savvy_demo -d advisor_economics_synthetic -v ON_ERROR_STOP=1 < analytics/bootstrap.sql
DBT_SEND_ANONYMOUS_USAGE_STATS=false .runtime/dbt/bin/dbt build --project-dir analytics --profiles-dir analytics
docker compose exec -T db psql -U savvy_demo -d advisor_economics_synthetic -v ON_ERROR_STOP=1 -c "SELECT has_table_privilege('savvy_analytics','public.demo_records','UPDATE') AS analytics_can_update_source, has_table_privilege('savvy_analytics','raw_demo.records','SELECT') AS analytics_can_read_view;"
