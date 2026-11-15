#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export SAVVY_PUBLIC_ORIGIN="$(python3 -c 'import json; print("https://"+json.load(open("deploy/device-host.json"))["hostname"])')"
docker compose up -d db api
for attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 2 http://127.0.0.1:3101/health >/dev/null; then
    # Prevent automatic system sleep on AC while serving; do not change global settings.
    exec /usr/bin/caffeinate -s npm --prefix apps/web run start
  fi
  sleep 1
done
echo "Savvy API is not ready; launchd will retry." >&2
exit 1
