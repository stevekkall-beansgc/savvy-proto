# Workspace validation — 14 November 2026

The Astra contract was implemented by three Terra lanes with cross-review. Domain
review of the interface, interface review of billing/reporting and an independent
domain/API stress review produced corrections before this integrated acceptance.
All exercised data and decisions are synthetic. Main history was backed up before
migration; tests used guarded disposable databases, not a main-history reset.

## Passing checks

| Check | Observed result | Evidence under artifacts/workspaces |
|---|---|---|
| Full regression | 49 original Python tests; 93 Ruby tests, 1,491 assertions, no failures/errors/skips; Rails eager loading | regression.txt |
| Final interface build | Optimized Next.js build and TypeScript pass after final copy/disclosure changes | next-build.txt |
| Native billing | 4 tests/53 assertions, including source lineage, invoice identity, split lines, custodial route, scoped FKs and conservation | WORKSPACES-STRESS-REPORT.md and test/billing_catalog_test.rb |
| Independent stress | 15 tests/190 assertions, seed 9315, at most four threads | WORKSPACES-STRESS-REPORT.md and test/workspace_stress_test.rb |
| Reporting | 19 dbt models + 53 data tests = 72 passing steps | dbt.txt |
| Canonical legacy reconciliation | Retained invoice/application totals and $1,600/$30/$1,570 bank case; 72 dbt steps pass | legacy-canonical-reporting.txt |
| Actual HTTP | 21 broker/internal identity, money, proposal omission, billing and mock-boundary checks pass | http.json |
| Migration rehearsal | Restored pre-milestone database on a separate cluster, migrated and seeded | migration-rehearsal.txt |
| Fresh schema | New test DB loaded from SQL, seeded; 5 triggers/2 exclusions present; inconsistent invoice and overlapping standard rejected | fresh-sql-schema.txt, fresh-constraints.txt |
| Existing history | Exact prior rows unchanged across six original operational tables, including 34 records and 25 operations | history-preservation.json |
| Recovery | Consistent logical restore of 15 public tables with matching row fingerprints; scratch DB dropped | recovery.json |
| Repeated seed | Existing volume backfill/replay succeeds without replacing retained state | seed-replay.txt |

Stress checks include repeated same-key races, competing schedules, stale review and
document manifests, SQL date boundaries, targeted intersections and priorities,
signup days 0/6/7/missing, blocked inputs, immutable historical runs/comparisons,
all five simulated roles, same-amount changed-source invalidation and injected
transaction rollback. The [independent report](WORKSPACES-STRESS-REPORT.md) records
exact scope and corrected findings. These 15 tests are included in the 93-test
suite, not an additional 15 tests in that total. Assertion counts can vary with
which competing worker wins.

Legacy Python emitted SQLite resource warnings; Rails emitted a dependency warning
about future string freezing. Both suites passed. No new failure was suppressed.

## Browser acceptance

The actual optimized local application was exercised through its UI at desktop
1280×900 and mobile 390×844. Mobile document width matched viewport width on
Earnings, Agreements and expanded internal customer billing context. The temporary
viewport override was reset and the existing tab was left on Broker → Earnings.

Verified: explicit experiences; customer income detail and billing lineage;
current/upcoming agreement visibility; optional end date clearing; friendly dated
promotions and a first-seven-days targeted promotion; saved proposal; independent
future comparison ($850 → $950); exact mock Legal and Finance approvals; scheduling
for November 16; current November 13 result unchanged; Jordan/Birch custodial context
with unavailable execution and collapsed mock accounting history. Future actual
workspace query correctly blocks rather than manufacturing future fee observations.

Captures and read-only JSON responses:

- broker-earnings-desktop.jpg and broker-earnings-mobile.jpg
- agreements-mobile.jpg
- internal-terms-mobile.jpg
- internal-approvals-desktop.jpg
- workspace-2026-11-13.json and workspace-2026-11-16.json

## Reproduce and retain

From the project root, use `./scripts/setup.sh`, then `./scripts/start.sh`.
`./scripts/check.sh` runs regression, eager loading and the optimized build.
`./scripts/analytics.sh` checks reporting. `./scripts/reconciliation-check.sh`
loads the canonical case into the disposable test DB. Do not run destructive test
suites concurrently against that same database. `python3 scripts/product_http_check.py`
is read-only against the running local API. `python3 scripts/recovery_check.py`
restores to a uniquely named scratch database and removes that scratch database.

The main local DB/API/frontend remain running for the owner's review on ports
55437/3101/3100, all loopback-only. The separate migration rehearsal cluster is
removed after validation. The source archive includes structure.sql, source,
contracts, documentation and evidence; it does not include the retained Docker
data volume. Fresh setup seeds baseline examples; the existing volume retains
the scheduled demonstration proposal and all prior review history.

No real Savvy models/data, live provider behavior, financial posting, payment,
signature, production authorization or sustained load capacity is established.
See [milestone limits](WORKSPACES-MILESTONE.md) before extending the prototype.
