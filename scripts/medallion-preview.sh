#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f compose.medallion.yaml -p savvy-medallion up -d db api
if [[ "$(uname -s)" == Darwin ]] && launchctl print "gui/$(id -u)/com.beanlabs.savvy-medallion.preview" >/dev/null 2>&1; then
  launchctl kickstart "gui/$(id -u)/com.beanlabs.savvy-medallion.preview"
  printf 'Savvy preview is managed in the background at http://127.0.0.1:3103\n'
  exit 0
fi
if [[ ! -f apps/web/.next/BUILD_ID ]]; then
  npm --prefix apps/web run build
fi
export SAVVY_API_URL=http://127.0.0.1:3102
cd apps/web
exec ./node_modules/.bin/next start --hostname 127.0.0.1 --port 3103
