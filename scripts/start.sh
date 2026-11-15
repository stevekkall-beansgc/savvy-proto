#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose up -d db api
for savvy_attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:3101/health >/dev/null; then
    exec npm --prefix apps/web run start
  fi
  sleep 1
done
printf 'The local Rails service did not become ready. Check docker compose logs api.\n' >&2
exit 1
