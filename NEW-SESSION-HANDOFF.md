# Savvy execution handoff

## Full device-hosted application — 15 November 2026

Live: https://savvy-proto.beanshop.top/ behind owner-only Cloudflare Access.
Private source: https://github.com/stevekkall-beansgc/savvy-proto (main).
The owner explicitly chose this Mac as the host using existing Cloudflare/GCP
infrastructure and no new spend. Read docs/HOSTING.md before operating it.
Two Savvy LaunchAgents own the frontend and dedicated Tunnel, restarting after
login/exit. API/PostgreSQL stay in the retained Docker stack with restart policies.
Credentials are runtime-fetched, not stored in source or login-service files.
Only the dedicated subdomain/tunnel/Access app were added; no existing route was
replaced. The Sites placeholder remains unpublished and unused.

Mac must stay powered, connected and logged in, with Docker available. An AC-only
sleep assertion runs with the app. Manual sleep/lid closure/logout can interrupt
availability. Source backup is not a backup of the live DB volume. The exact
public HTTPS origin is allowlisted; API/database ports stay loopback-only.
Campfire/CLM remain mocked. Local port 3100 still works, but do not start a
competing frontend while its LaunchAgent owns that port.

## Product copy cleanup — 15 November 2026

The owner requested product-facing language without repeated “illustrative”, demo
warnings or “end exclusive”. The current web UI removes that scaffolding across
Earnings, Agreements, Commercial terms and Approvals, hides mock accounting history,
and moves document identifiers into details. Provider integrations remain mocked;
no underlying records, review semantics or accounting behavior changed.

Displayed date ranges now show the last included day. The “Last day (optional)”
editor converts back to the API's exclusive end date; storage/calculations retain
their original boundaries. Next build/TypeScript passed. Browser checks confirmed
agreement/rate dates, date editing and clearing, unchanged earnings and scheduled
reviews. The frontend was restarted at http://127.0.0.1:3100. The November 14 ZIP
and screenshots are historical; the current source contains this later cleanup.

## Current milestone — 14 November 2026

Start with `docs/WORKSPACES-MILESTONE.md`, `docs/VALIDATION-WORKSPACES.md`,
`docs/WORKSPACES-IMPLEMENTATION-CONTRACT.md`, `docs/REVISED-PRODUCT-PLAN.md` and
`docs/BILLING-OWNERSHIP-DEEP-DIVE.md` in advisor-payout-explorer. The owner authorized
Astra to finalize the plan and Terra agents to implement, cross-review and stress
test it. That bounded milestone is complete. Earlier sections below are historical.

Primary navigation is now Broker: Earnings/Agreements and Internal:
Advisors/Commercial terms/Approvals. The UI walkthrough feedback is mapped in the
milestone. Official Savvy public-site branding remains. The commercial domain has
one real commercial_rates PostgreSQL table with immutable versions, optional rate
ends, targeted/signup promotions and exact comparison/document-bound mock reviews
and scheduling. Savvy owns typed fee obligations, invoices/lines and custodial
instructions. Campfire accounting and CLM documents/reviews remain local mocks.
Legacy accounting/settlement screens are absent from primary navigation, while old
APIs, evidence and tests remain intact. Contract 0.5.0.

Validation: 49 Python tests; 93 Ruby tests/1,491 assertions; 19 dbt models/53 data
tests; 21 actual product HTTP checks; bounded concurrent/rollback stress checks;
desktop/mobile acceptance; fresh SQL schema constraints; migration rehearsal;
exact 15-table restore and unchanged prior rows. The stress tests are included
within the 93 Ruby tests. `db/structure.sql` is authoritative; no schema.rb should
be regenerated because it loses the billing function and deferred triggers.

The main DB/API/frontend are RUNNING for review at http://127.0.0.1:3100.
The retained volume has scheduled proposal
`proposal-77c0b64f-1f9b-4ecc-aeaf-c7f6104948d3`, effective November 16, with mock
Legal/Finance reviews. Its independent signup example compares $850 to $950.
Current business date remains November 13: $1,750 earned/$1,000 coverage/$750
incremental. The prior $1,770 policy-v2 projection is unchanged in history;
that draft was never activated, so new product baseline selection uses v1.
Future actual earnings block without matching dated source evidence.

Portable archive: `savvy-workspaces-prototype.zip`, source and evidence only, no
Docker data volume. Fresh setup seeds baseline; existing local volume retains
reviewed proposals and all prior history. No real provider, data, payment,
signature, publication, external message or production connection was added.

## Original recovery instructions (historical)

Start a new Codex session with GPT-6.1 Sol, high reasoning. Read docs/EXECUTION-PLAN.md, docs/TECHNICAL-SPECIFICATION.md, docs/EVIDENCE-AND-SCOPE.md, and docs/CODEX-HANDOFF.md.

This archive contains tracked files at commit 1daac22 plus an uncommitted apps/ directory from an interrupted agent. The apps/ work is incomplete and unverified; review it before using it. The original project has no configured Git remote. This archive does not include Git history.

Use synthetic data. Do not contact third parties, connect to production, deploy or publish without appropriate authorization. Do not alter beanshop.top. Preserve distinctions between established facts, assumptions and unverified Campfire capabilities. The previous environment lacked Ruby, Rails, PostgreSQL and Docker; verify what is available in the new environment.

## Local continuation recovered on 13 November 2026

The archive has been restored to `/Users/stephenkall/beans/labs/savvy-prototype/advisor-payout-explorer`. Start with `docs/CONTINUATION-STATUS.md`, `docs/INTERRUPTED-WORK-REVIEW.md` and `docs/VALIDATION-CONTINUATION.md`. The Rails/Next/Postgres/GraphQL vertical slice is now runnable; the full original execution plan is not complete. Setup: `./scripts/setup.sh`, then `npm --prefix apps/web run start` (local port 3100). Optional dbt: `./scripts/analytics.sh`. No remote, publication, live provider connection, real data or accounting posting was created.

## Latest milestone: Savvy branding and recorded settlement

Use `docs/SETTLEMENT-MILESTONE.md`, `docs/VALIDATION-SAVVY-SETTLEMENT.md` and
`docs/SAVVY-BRAND-REFERENCE.md` for the current state. The owner said to use the
public Savvy site as the visual reference; no internal guide was provided.

Official logo/colors/type are applied to the current Next.js interface. The
Settlement desk now supports recorded directional coverage and full original
reversals. Collections supports receipt-source reversals, match-only reversals
and a prior as-known view. The new API contract is 0.3.0. There are 49 passing
Ruby tests and 29 passing dbt checks across nine models, plus verified desktop
and mobile flows. Original Python code remains a separate reference.

The retained local data includes two reversed advisor applications, one $750
broker prepurchase application, and Cedar receipt revision 2 (reversed); earlier
versions remain. Final saved book projection is still $1,770 earned / $1,000
coverage / $770 incremental, with a separate provisional $30 guarantee. These
are fictional examples, not real advisor entitlements or accounting evidence.

Next: independent invoice application and bank settlement evidence/gross-to-net
bridge, closed-period correction rules, then the separate Ruby Campfire offline
accounting lifecycle. No live accounts, private company data, external messages,
provider writes, publication or changes to beanshop.top are authorized.

The portable ZIP contains source, captures and JSON evidence, not the Docker data
volume. Fresh setup seeds the baseline examples; the existing local volume keeps
the reviewed policy-v2 and reversal history. Re-running setup retains existing
runs. Start locally with `./scripts/start.sh` after setup.

## Latest: Astra plan and Terra reconciliation team

The owner requested Astra planning followed by Terra implementation, independent
review and stress testing. Read `docs/CTO-READINESS-PLAN.md`,
`docs/RECONCILIATION-MILESTONE.md`, `docs/VALIDATION-CTO-RECONCILIATION.md` and
`docs/CTO-STRESS-REPORT.md` first. The new reconciliation view records independent
invoice applications, whole-receipt bank gross/fee/net batches, exact reversals
and immutable review snapshots with separate later-evidence overlays. This is a
review close, not an accounting period lock. Savvy's public-site branding remains.

Contract 0.4.0; 65 Ruby tests/1,203 assertions, 49 original Python tests, 14 dbt
models/41 data tests, 19 HTTP checks, exact logical restore and desktop/mobile
acceptance passed. Concurrent retry, bounded claim, correction/write and freeze
races plus rollback injection were independently tested. All original retained
rows are unchanged. Services are stopped and the local volume remains.

Main local history now includes Maple's invoice, a $1,000 independent application
and full reversal, and a separate $1,000 gross/$10 fee/$990 net bank batch. Saved
review `close-bad7a0de-9291-4b16-bc4a-95a69e21aaa8` retains the original application
and shows its later reversal separately. The old Cedar reversal, entitlement
entries, policy versions and $1,770 projection are unchanged. The canonical
$1,600/$30/$1,570 case runs only in disposable fixtures using
`./scripts/reconciliation-check.sh`; it does not reset main history.

Portable source archive: `savvy-cto-reconciliation-prototype.zip`. It contains
source, screenshots and JSON validation evidence, not the local data volume.
Next gates remain actual accounting period/correction rules, offline accounting
lifecycle, and the production controls listed in the CTO plan. No external
provider, real data, publication or payment authorization has been added.
