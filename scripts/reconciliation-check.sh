#!/usr/bin/env bash
# Destructive to demo rows in the disposable Rails test database only.
set -euo pipefail
cd "$(dirname "$0")/.."
readonly test_database=advisor_economics_synthetic_test
readonly log_file="$PWD/artifacts/cto-readiness/reconciliation-check.log"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/savvy-reconciliation-check.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$(dirname "$log_file")" "$tmp_dir/profiles" "$tmp_dir/target" "$tmp_dir/logs"
main() {

# Fail before the fixture clears anything if the configured Rails database differs.
docker compose run --rm -e RAILS_ENV=test api bundle exec ruby -e \
  "require './config/environment'; abort 'Expected disposable test database' unless ActiveRecord::Base.connection_db_config.database == '$test_database'"
docker compose run --rm -e RAILS_ENV=test api bundle exec ruby test/reconciliation_stress_test.rb --name test_canonical_populated_reporting_fixture

# Generate test-only inputs. Never alter the checked-in bootstrap or profile.
python3 - "$tmp_dir" <<'PY'
from pathlib import Path
import sys
root = Path.cwd()
tmp = Path(sys.argv[1])
bootstrap = (root / 'analytics/bootstrap.sql').read_text()
old = "current_database() != 'advisor_economics_synthetic'"
new = "current_database() != 'advisor_economics_synthetic_test'"
if bootstrap.count(old) != 1:
    raise SystemExit('Unexpected bootstrap database guard; refusing to proceed')
(tmp / 'bootstrap.sql').write_text(bootstrap.replace(old, new))
profile = (root / 'analytics/profiles.yml').read_text()
old = 'dbname: advisor_economics_synthetic\n'
new = 'dbname: advisor_economics_synthetic_test\n'
if profile.count(old) != 1:
    raise SystemExit('Unexpected dbt profile database; refusing to proceed')
(tmp / 'profiles/profiles.yml').write_text(profile.replace(old, new))
PY
docker compose exec -T db psql -X -U savvy_demo -d "$test_database" -v ON_ERROR_STOP=1 < "$tmp_dir/bootstrap.sql"
if [[ ! -x .runtime/dbt/bin/dbt ]]; then
  command -v uv >/dev/null
  uv venv .runtime/dbt --allow-existing --cache-dir "$PWD/.runtime/uv-cache"
  uv pip sync --python .runtime/dbt/bin/python --cache-dir "$PWD/.runtime/uv-cache" analytics/requirements.lock
fi
DBT_SEND_ANONYMOUS_USAGE_STATS=false DBT_TARGET_PATH="$tmp_dir/target" DBT_LOG_PATH="$tmp_dir/logs" \
  .runtime/dbt/bin/dbt build --project-dir analytics --profiles-dir "$tmp_dir/profiles"
docker compose exec -T db psql -X -U savvy_demo -d "$test_database" -v ON_ERROR_STOP=1 < analytics/assert_canonical_reconciliation.sql
printf 'Canonical reconciliation reporting check passed.\n'
}
main 2>&1 | tee "$log_file"
