#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null
command -v node >/dev/null
node -e 'if(Number(process.versions.node.split(".")[0])<22)throw Error("Use Node 22 or newer for the pinned frontend")'
docker compose build api
docker compose up -d db
docker compose run --rm api bundle exec rails db:prepare
docker compose run --rm api bundle exec rails db:seed
docker compose run --rm api bundle exec rails runner 's=Workbench.new; if s.records("run").exists?; puts "Existing synthetic runs retained"; else; s.project({"policy_id"=>"policy-v1","snapshot_id"=>"source-20261113-r1"},"setup-baseline-v021"); puts "Initial synthetic projection retained"; end'
for fixture in presentation billing_platform billing_closure; do
  docker compose run --rm api bundle exec rails runner "script/seed_${fixture}.rb"
done
docker compose up -d api
npm ci --prefix apps/web --cache "$PWD/.runtime/npm-cache" --no-audit --no-fund
npm --prefix apps/web run build
printf '\nReady. Start the local frontend with: SAVVY_DEMO_SESSIONS=1 npm --prefix apps/web run start\n'
printf 'Open http://127.0.0.1:3100\n'
