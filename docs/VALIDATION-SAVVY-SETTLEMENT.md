# Savvy brand and settlement validation — 13 November 2026

This is the current validation record. VALIDATION-CONTINUATION.md describes the
previous milestone; the new functional scope is SETTLEMENT-MILESTONE.md.

## Passed

| Check | Result |
|---|---|
| Ruby domain / PostgreSQL / GraphQL suite | 49 tests, 996 assertions, 0 failures, 0 errors, 0 skips |
| New settlement and cash lifecycle coverage | 12 added tests, including concurrent $600 claims on one $1,000 grant, exact reversals, direction separation, receipt revision conflicts, as-known reconstruction and GraphQL string money |
| Next.js optimized build and TypeScript | Passed after the final UI changes |
| Rails eager loading | `rails zeitwerk:check`: passed |
| dbt on the retained demo database | 9 models, 29 data tests: all passed |
| Fresh disposable database | New schema + seed + consume/reverse + receipt match/reverse + projection: passed |
| dbt on that fresh database | 9 models, 29 data tests: all passed; fresh schema permissions validated |
| Browser | Desktop at 1280 px and mobile at 390 × 844; working flows and captures below |

The original 49 Python tests passed in the previous milestone, and its code and
fixtures remain unchanged. They are separate from the 49 Ruby tests. The old
SQLite ResourceWarnings are historical and are not claimed fixed.

Commands used for the new checks:

```
docker compose run --rm -e RAILS_ENV=test api bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
docker compose exec -T api bundle exec rails zeitwerk:check
npm --prefix apps/web run build
DBT_SEND_ANONYMOUS_USAGE_STATS=false .runtime/dbt/bin/dbt build --project-dir analytics --profiles-dir analytics
```

The clean database ran under a separate `savvy-clean-check` Compose project,
using its own disposable volume and loopback port 55438. Its dbt build used a
separate temporary profile/target. Only that test volume was removed afterward;
the working demo database and all earlier evidence remain retained. Both builds
used an analytics role with SELECT on approved raw views and writes restricted
to the analytics schema. The initializer now grants schema CREATE/USAGE even when
Rails schema loading has already created the empty analytics schema.

Logs: artifacts/savvy-settlement-dbt.txt and
artifacts/savvy-clean-settlement-dbt.txt. No CI/GitHub run or deployment is claimed.

## Browser observations

1. Official Savvy wordmark loads locally without alteration; Caslon/Diatype and
   public-site color tokens load from local files. No invented internal guide.
2. Operator can inspect the Settlement desk; recording controls require the
   simulated Finance role and a reason. This remains a local role simulation.
3. Finance applied $600 to Cedar and the remaining $400 to Maple from a $1,000
   advance. The UI showed $0 remaining, Maple $200 uncovered, and no additional
   coverage available. A new projection showed earned $1,770, coverage $0,
   incremental cash $1,770; the previous run stayed retained.
4. Linked $600 and $400 reversals restored exactly $1,000. Original applications
   remain with their reversal references, and cannot be reversed a second time.
5. A separate broker-to-firm $750 prepurchase was applied to a $1,000 obligation,
   showing $250 uncovered. It did not change the opposite-direction advance.
6. Cedar's $600 receipt source was reversed to revision 2. Current active receipts
   and matches became $0, unmatched charge $1,000; revision 1 and the original
   $600 match remained. Bank refund, accounting application and recognition were
   not inferred or executed.
7. “View before reversal” returned revision 1, $600 matched and $400 unmatched,
   with write controls disabled in that historical view. The invoice link remained
   independent of receipt evidence.
8. A final projection after restoring the advance showed $1,770 earned, $1,000
   projected coverage, $770 incremental cash and separate provisional guarantee
   $30. It pins the recorded-entry manifest; no ledger entry was created by it.
9. The mobile Settlement desk had page width 390 equal to viewport width 390;
   its tables scroll inside their regions. The viewport override was reset.

Captures: artifacts/savvy-branded-overview.jpg,
artifacts/savvy-settlement-desktop.jpg, artifacts/savvy-settlement-mobile.jpg.

## Observed reporting values (USD cents)

- grant-alex: opening 100000, net recorded 0, remaining 100000, with two original
  applications and two exact reversals retained.
- grant-broker-prepay: opening 75000, net recorded 75000, remaining 0. Opposite
  payer/payee direction, not combined with advisor advances.
- Cedar: matched 0, unmatched charge 100000, active receipt context 0,
  explicitly source-reversed receipt 60000. Earlier as-known $600 match preserved.
- Maple: matched 100000, unmatched 0, active receipt context 100000.
- Birch: no receipt evidence; cash context remains NULL.

## Limits

All data, approvals and obligations are fictional. Only USD monetary coverage and
full original-entry reversals are implemented. Worked settlement obligations are
independent examples, not actualizations of the current projection's fee lines.
No live Campfire connector, bank refund, bank bridge, accounting application,
recognition, posting, signature, production auth, automated schedule, restore
certification, warehouse close or all-S01–S30 completion is claimed. Publication
remains paused. Font/wordmark ownership and official source URLs are documented
in SAVVY-BRAND-REFERENCE.md; no internal Savvy design system was accessed.
