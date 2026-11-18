# Medallion validation — 15 November 2026

Validation used the isolated `savvy-medallion` stack and guarded disposable test
database. No suite reset the retained hosted database. Source changes are local
on `codex/medallion-billing`; no exact-commit remote CI or release is claimed.

## Passing gates

| Gate | Observed result | Evidence under artifacts/medallion |
|---|---|---|
| Integrated regression | 49 Python reference tests; 142 Ruby tests / 1,772 assertions; zero failures/errors/skips; Rails eager loading | regression.txt |
| Frontend | Optimized Next.js production build and TypeScript pass | regression.txt, next-build.txt |
| Reporting on populated cases | 23 dbt models + 66 data tests = 89 passing steps; analytics cannot update source tables | dbt.txt |
| Actual new API | Both products and all named economic scenarios; exact amounts and retained references; external scope/internal-payload restrictions; pending payout separate from payable | http.json |
| Retained workspace API | 21 existing HTTP checks pass against the isolated API | ../workspaces/http.json |
| Independent engine stress | Graph/rounding/source/event/netting cases, whole-request legacy translation and one-interpreter invocation | medallion_program_test.rb and engine_test.rb; included in integrated total |
| Independent backend stress | Source conflicts, pending/wrong-direction cash, two competing applications, exact reversal and source/assignment/review changes | medallion_stress_test.rb, medallion_contract_stress_test.rb, medallion_workbench_test.rb; included in total |
| Independent statement review | Sealed history, inside/outside bonus, credit, payment/reversal, sequential seals, credit balance, missing receipt, cutoff, provenance and posting locks | medallion_statement_test.rb; included in total |
| Fresh SQL schema | Seed/bootstrap succeeds from structure.sql; SQL rejects evidence/rate mutation and overlapping rate/assignment intervals | fresh-schema.json |
| Migration rehearsal | Restore of the original hosted baseline into an isolated scratch DB; migrate through 009; all original column values unchanged across 14 non-migration tables | migration.json, migration.txt |
| Logical restore | All 16 public tables match a consistent exported source snapshot after restore into a unique scratch database | recovery.json |
| Hosted history preservation | All 15 original public tables have identical before/after row fingerprints | live-history.json |

The API assertion count varies with the size of the authorized explanation fields;
the named checks and cases, not a larger count, define its scope. Concurrency is
bounded local contention testing, not a capacity benchmark. Existing Python
SQLite resource warnings and a Rack future-string warning remain non-failing.

## Exact sample outcomes

| Independent case | Compensation / charges | Remaining balance |
|---|---:|---:|
| Advisor baseline | $3,300 compensation, $1,000 advance | $2,300 |
| Late Cedar correction | $3,808 client fees; $3,141.40 share; $158.60 guarantee; compensation still $3,300 | $2,300 |
| $100 bonus outside guarantee | $3,400 compensation | $2,400 |
| $100 bonus within guarantee | $3,300 compensation; +$100 bonus / −$100 guarantee adjustment | $2,300 |
| $500 payout request | Compensation unchanged; request separately visible | $2,300 |
| Confirmed and applied $500 payout | Compensation unchanged | $1,800 |
| Harbor baseline | $250 capped charge − $120 qualified credit | $130 |
| Harbor service credit | Baseline economics plus $30 credit | $100 |

The October 1 receipt-missing case leaves dependent rebate/net outputs unknown,
preserving known gross charges. Source/funding reversal changes eligibility only
after its known time. Earlier runs and sealed statements remain unchanged.
Account-count proof rejects duplicate, partial, mis-scoped or inconsistent rosters.

Four versioned API-only policy comparisons assert identical input manifests and
the required $100/$180/$60/$2,400 outcomes. A same-value source revision invalidates
review; an offsetting guarantee does not make changed policy/evidence invisible.

## Browser acceptance

The optimized app was exercised in Chrome at its normal desktop size and a
390×844 mobile override. Document width was 390px on mobile for advisor earnings,
expanded balance history, RIA economics, Agreements, Architecture and populated
Approvals. The internal architecture table scrolls within its own container.
The temporary viewport override was reset afterward.

Verified: advisor $3,300/$1,000/$2,300; 30 dated Cedar balance rows; governing
annual rates, inclusive dates, signup window, tier limit and day basis; separated
RIA charges/network/investor context; both value stories; architecture grains and
Campfire/CLM boundaries; pipeline/scenario selectors and real stage rows;
assignment controls/history; and the retained November $1,750/$1,000/$750 view.

Two actual UI commands were exercised in the isolated development state: a $1
test entitlement was submitted and rejected, retaining its request/review without
changing earnings; and an unchanged-policy comparison was saved successfully.
These acceptance records remain as audit history. No production or hosted record
was touched. The browser was left on the new advisor preview at port 3103.

## Findings corrected during review

Independent reviews caught and corrected RIA access to legacy APIs/private
scenarios; payment bounds that could be reset by rerun or payment revision;
historical statement cutoffs that admitted future results; source timestamps and
manifest ordering; unapproved netting; missing directional metadata; dropped or
duplicated approved event paths; a $50 charge in an alternate rather than
authoritative output; and a policy-literal account count instead of source usage.
Test fixtures were updated for required posting-period fields and scoped counts;
no failed test was suppressed or skipped.

## Reproduce

From the isolated worktree, use `./scripts/medallion-check.sh`. It pins the separate
Compose project, ports and analytics profile. Stop only the port-3103 frontend
before a full check, because Next.js writes its build directory; restart it with
`./scripts/medallion-preview.sh` afterward. Do not run destructive suites
concurrently against its one test database. Additional gates:

- `COMPOSE_FILE=compose.medallion.yaml SAVVY_ANALYTICS_PORT=55438 ./scripts/reconciliation-check.sh`
- `python3 scripts/medallion_migration_check.py --source-root /path/to/retained/original/checkout`
- Fixture bootstrap and the nine retained result commands are documented in the
  [API contract](MEDALLION-API-CONTRACT.md).

The [milestone](MEDALLION-MILESTONE.md) records production and capability limits.
