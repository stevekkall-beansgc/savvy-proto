#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose stop
printf 'Stopped this prototype’s containers. Its named synthetic data volume is retained. Stop the frontend with Ctrl+C in its terminal.\n'
