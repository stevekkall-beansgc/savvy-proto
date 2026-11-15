#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -q
docker compose run --rm -e RAILS_ENV=test api bundle exec rails db:prepare
docker compose run --rm -e RAILS_ENV=test api bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
docker compose run --rm api bundle exec rails zeitwerk:check
npm --prefix apps/web run build
