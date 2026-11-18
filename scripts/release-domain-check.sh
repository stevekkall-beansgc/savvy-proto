#!/usr/bin/env bash
# Exact-checkout integration checks; only a separate synthetic test database.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .runtime/release-check/buildx
export BUILDX_CONFIG="${BUILDX_CONFIG:-$PWD/.runtime/release-check/buildx}"
dc=(docker compose -f compose.release-check.yaml -p savvy-release-check)
cleanup() { "${dc[@]}" down -v; }
trap cleanup EXIT
"${dc[@]}" build api
"${dc[@]}" up -d db
"${dc[@]}" run --rm api bundle exec rails db:prepare
"${dc[@]}" run --rm api bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
"${dc[@]}" run --rm api bundle exec rails zeitwerk:check
