#!/usr/bin/env bash
# This entire check uses the separate medallion containers and data volume.
set -euo pipefail
cd "$(dirname "$0")/.."
export COMPOSE_FILE="$PWD/compose.medallion.yaml"
export COMPOSE_PROJECT_NAME=savvy-medallion
export SAVVY_ANALYTICS_PORT=55438
export SAVVY_API_ORIGIN=http://127.0.0.1:3102
mkdir -p artifacts/medallion
docker compose config --quiet
./scripts/check.sh 2>&1 | tee artifacts/medallion/regression.txt
./scripts/analytics.sh 2>&1 | tee artifacts/medallion/dbt.txt
python3 scripts/product_http_check.py
python3 scripts/medallion_http_check.py
python3 scripts/recovery_check.py --output artifacts/medallion/recovery.json
