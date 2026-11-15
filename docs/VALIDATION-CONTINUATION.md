# Continuation validation — 13 November 2026

Scope: local synthetic Rails/Next/PostgreSQL vertical slice. The original archive
contained commit label `1daac22` but no Git history. No new remote repository or
CI run exists; use the source checksums in the continuation bundle for the exact
local snapshot. No live or company accounting accuracy is claimed.

## Executed checks

| Check | Result |
|---|---|
| Original `python3 -m unittest discover -s tests -q` | 49 passed; original SQLite ResourceWarnings remain |
| Ruby domain + real PostgreSQL/service/GraphQL tests | **37 tests, 925 assertions, zero failures/errors/skips** |
| `rails zeitwerk:check` | Passed; includes GraphQL namespace loading |
| `npm --prefix apps/web run build` | Passed; TypeScript and optimized Next.js build |
| dbt build on fictional operational records | **6 models and 18 data tests passed** (24 nodes) |
| Fresh disposable PostgreSQL database, schema, seed, initial projection | Passed; $1,000 opening grant applied at most $1,000; disposable volume removed |
| Analytics permissions | SELECT on approved raw view = true; UPDATE on operational source = false |
| Browser interactions | Desktop and mobile checks described below passed |

The final check output is saved in `artifacts/continuation-checks.txt`.
The documented `scripts/check.sh` completed all checks; an enclosing interactive
shell output wrapper then used zsh's read-only `status` variable and exited with
an error. This wrapper was corrected by inspecting and asserting the complete
log. It was not a test, source, setup-script or build failure.

Environment: Ruby 3.4.12 (pinned official Docker image), Rails 8.0.5.2,
GraphQL Ruby 2.6.15, PostgreSQL 17, Node 22.23.2, Next.js 16.4.6,
Python 3.14.7 for the original suite; Python 3.13.14 / dbt-core 1.12.7 /
dbt-postgres 1.11.0 for analytics. Exact dependency locks are retained.

The first isolated fresh-database attempt hit the host Docker network-pool
limit. A disposable database on this prototype's existing network passed;
no unrelated network or database was changed. Next development-mode file
watching was unavailable under this host's execution restrictions; the optimized
local build and start path were used and verified. Neither limits the verified
Docker database tests or the production-style local frontend build.

## Regression coverage

The interrupted shared-advance defect was reproduced before changes: 175,000
cents ($1,750) were covered from a 100,000-cent ($1,000) grant. The corrected
engine uses a copied balance shared across source lines. Tests verify purity,
repeatability, stable ordering and no partial source fact leakage.

Coverage includes exact rate precedence and promo boundaries; incomparable
rules; required/unknown dimensions; forbidden rate operations; scope mismatch;
duplicates; late knowledge; stale/incomplete envelopes; negative/duplicate broker
weights; direction/expiry; unit coverage; scoped monthly guarantees and deltas;
unsupported count-to-money conversion; deterministic penny allocation and 200
seeded conservation cases; immutable prior runs; idempotent operations; cross-batch
source revision conflicts; hash-bound dual reviews and activation; pre-invoice
cash matching, invoice variance, concurrency, composite database scope, simulated
advisor restrictions, typed GraphQL money, malformed/oversized requests, external
origin rejection and schema reload behavior.

## Browser acceptance

Checked through the local browser interface, not a remote deployed Site:

- Baseline overview: Alex earned $1,750, coverage $1,000, incremental cash $750.
  Customer drilldown shows the source revision, assignment and winning rule.
- Policy editor: promotion 85% → 87%, November broker floor $0 → $1,800 and
  matching draft wording saved as policy-v2, without code changes.
- New projection: earned $1,770; coverage $1,000; incremental cash $770; separate
  provisional monthly floor top-up $30. The original run remains retained.
- Customer Cedar: $600 operational match to a $1,000 charge; $400 unmatched.
  Maple: $1,000 operational match to a $1,000 charge. Linking Cedar's fictional
  invoice preserves the one $600 receipt and leaves accounting application,
  bank settlement, AR and recognition unknown.
- Simulated Finance review and frozen packet generation succeeded. The packet
  includes the exact clause text and policy/run fingerprints; not a signature.
- Simulated advisor identity exposes only Alex's broker choice and own results;
  projection/edit actions are disabled and API denial is separately tested.
- 1280 px desktop and 390 × 844 mobile layouts inspected. Mobile page width
  equaled viewport width (390 px); the customer table scrolls within its region.

The screen captures in `artifacts/` are supporting evidence, not an automated
browser test suite. Original `browser_smoke.py` was not re-run; it targets the
separate Python interface. Browser actions are manual acceptance through the
connected browser tool. No claim of complete WCAG or production security audit.

## Analytics observed result

Source/customer scope (USD cents): Cedar charge 100000 / matched 60000 /
unmatched 40000; Maple 100000 / 100000 / 0; Birch 50000 / 0 / 50000.
Invoice-applied and recognized amounts are NULL. Tests verify no fanout, no
cross-customer matching, no overapplication, preserved unknowns, source readiness,
projection conservation and grant opening bounds. Read-only source permissions
were checked independently in PostgreSQL. No bank or GL posting was created.

Current analytics models are candidate tables over immutable current evidence,
not an approved warehouse close or frozen publication. Changing source data
requires another manual dbt build. All 30 original acceptance scenarios remain a
future completeness target; only the implemented slice is claimed here.

## Delivery boundary

No Campfire/Savvy account, live API, actual customer records, cloud credentials,
external message, GitHub write, provider signup, published Site, domain change,
finance posting, bank transfer or signature. Production auth, restore drills,
actual entitlement settlement/reversal, bank evidence and full accounting/dbt
lifecycle remain unimplemented, as detailed in CONTINUATION-STATUS.md.
