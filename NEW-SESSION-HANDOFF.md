# Savvy execution handoff

## Shared billing milestone — 18 November 2026

Read `docs/FOUR-CAPABILITY-PLAN.md` and `docs/FOUR-CAPABILITY-VALIDATION.md`.
The default workspace now uses shared source mappings, normalization jobs, policy
composition/typed graphs, dated schedules, one engine and native invoices plus
reviewed credit/debit corrections for both product cases. The earlier examples
remain available under Demo identity. Campfire and CLM remain mocked.

This milestone adds five migrations. Never run them on the currently served old
database. Candidate database is `savvy-platform-preview-db` / volume
`savvy-platform-preview-data`, loopback 55440, restored from the prior retained DB
and verified against old-column fingerprints before/after explicit fixture install.
Original DB `savvy-medallion-db-1` / 55438 is retained. Consult the actual activation
receipt and API container PGHOST before assuming which database is serving.
The intended new pair is candidate-b / API3109; actual success must be verified in
`.runtime/hosting/activation.json`. Do not rebuild an active slot.


## Eight-issue corrective milestone — 18 November 2026

Read `docs/EIGHT-ISSUE-FIX-PLAN.md` and `docs/EIGHT-ISSUE-VALIDATION.md` first.
Billing corrections compare native invoice/line economics, assignments enforce
policy validity, Finance sees review work and evidenced receipt/refund/loan cash,
and histories are bounded before loading. The single engine and API policy model
remain intact; Campfire and CLM remain mocked. No schema migration is needed.

Deployment now uses explicit inactive candidate slots and a source-immutable,
read-only API image. Follow `docs/DEMO-PREVIEW.md`; do not rebuild the active slot
or replace an API by loading live source. Actual activation/publication SHAs live
in `.runtime/hosting/activation.json` and `.runtime/publication/deployment.json`.
Verify them before claiming the working tree is the hosted version. The baseline
API on 3102 and older frontends are retained for rollback. Page reads and activation
never seed retained history. Existing comparisons become stale when implementation
bindings change; Product must explicitly compare again before review/publication.


## OpenAPI and GraphQL reference — 18 November 2026

Public API reference: `https://savvy.beanshop.top/api/`; YAML at
`/api/openapi.yaml`; authoritative SDL download at `/api/schema.graphql`.
The architecture header links to the reference. This is documentation for the
implemented GraphQL transport, all 21 fields and command families, with 10 typed
command examples. It does not add REST endpoints, MCP/WebMCP, production identity
or live execution controls. Billing behavior and retained app state are unchanged.

`docs/api/build.py` builds the YAML/page from SDL and verified source metadata.
Install `docs/api/requirements.txt`, then run `scripts/api_contract_check.py`
(`--live` sends only three reads to loopback). Architecture CI checks generation,
OpenAPI, GraphQL query/variable validity, command examples and action drift; its
browser suite covers filtering, expansion, downloads, mobile and read-only scope.
Publication includes only the API HTML/YAML/SDL alongside architecture assets.
Check `.runtime/publication/deployment.json` and public build metadata for the
actual published commit.

## Functional demo alignment — 18 November 2026

The February 2027 household is now the default example across Client, Product and
Finance. Broker compensation stays distinct from client billing. Product leads
with the four-step engine explanation and linked record modals. The historical
business book and operations examples remain under Demo identity rather than
being appended to every page. Real disclosures and the empty agreement viewer
are retained. No calculation, policy or retained-data behavior changed.

Read `docs/DEMO-PREVIEW.md` for locations and the guarded preview activation. The
new build slot is `.next-presentation`; do not rebuild a live slot.
`deploy/activate-preview.py` requires clean source, remote main and green exact-
commit CI, retains Cloudflare Access, and writes the actual activation commit to
`.runtime/hosting/activation.json`. Verify that receipt before claiming a
specific hosted version. Earlier deployment descriptions below are historical.

Acceptance: 29 read-only desktop/mobile browser checks, 102 disclosure HTTP
checks, 50 audience checks, 66 disclosure/document checks, optimized build and
49 reference tests plus four mocked deployment rollback/ownership/restart tests pass. Browser acceptance now runs in Prototype checks.
Synthetic fresh setup explicitly installs presentation examples; page reads and
preview activation never seed. Campfire and CLM remain mocked, and the original
deployment/data are retained for rollback.

## Public architecture publication — 18 November 2026

User requested GitHub-only code links, a public static walkthrough on
`https://savvy.beanshop.top/`, and public source. The GitHub repository is now
PUBLIC under verified account `stevekkall-beansgc`. All four reachable commits
(420 historical blobs) were screened for credentials and literal secrets; no
matches or credential-file paths were found. Existing fixtures are synthetic.

The engine view now leads with three inputs and four concrete steps: determine
billable assets, apply the agreed rate, assess the charge, allocate the same
charge. Invoice issuance, confirmed cash and recognition remain separate. The
operator catalogue and all 33 retained policy nodes are expandable technical
detail. All local-file/loopback links were removed from the HTML. Local acceptance
passes 237 checks. No calculation or billing behavior changed.

Static packaging publishes only the HTML, a 404 page, security headers, robots
and build metadata. No server or source-viewing endpoint is deployed. Read
`docs/PUBLIC-ARCHITECTURE.md` for exact-commit CI/deployment requirements and
verify the live `/build-metadata.json` against GitHub main before claiming a
specific version is published. Existing full app previews and the separate
owner-authenticated `savvy-proto.beanshop.top` route are not this public document.

## Interactive architecture and source checkpoints — 18 November 2026

Prototype source checkpoint `3ce278b` is committed and pushed to
`origin/codex/medallion-billing` in private `stevekkall-beansgc/savvy-proto`.
GitHub CLI account is verified as `stevekkall-beansgc`; commit identity matches.
The hosted main deployment remains on its existing version. Fresh TypeScript and
102 read-only disclosure HTTP checks pass; the previously validated 179-file
fingerprint was reviewed before commit. A generated build-slot import was
returned to its portable default and trailing CSS whitespace was removed.

Interactive architecture: **http://127.0.0.1:3105/**, separate from the full app
preview at **http://127.0.0.1:3104/**. Read `docs/architecture/README.md`.
The self-contained `docs/architecture/index.html` provides three views, 34
component modals, source links pinned to `3ce278b`, local read-only source viewing,
and all 33 policy nodes from a retained synthetic result. CLM/Campfire remain
mocked; workers, object storage and runtime AI agents remain planned. This is an
architecture document, not a replacement application or a new monetary authority.

The documentation preview runs `scripts/architecture_preview.py` on loopback;
PID/log are in `.runtime/architecture`. Restart with the documented command if
needed. It does not depend on Rails or the database. Downloaded HTML works offline;
local-code links require this preview server. The builder verifies code anchors
against exact pinned source bytes. Browser acceptance passes 199 checks, covering
all modals/nodes/source targets, keyboard, mobile, offline/print and read-only
boundaries. Screenshots/report are under `.runtime/architecture`.

## Disclosure-informed milestone complete — 16 November 2026

Read [the latest milestone](docs/DISCLOSURE-MILESTONE.md),
[Astra's revised plan](docs/DISCLOSURE-IMPLEMENTATION-PLAN.md),
[API contract](docs/DISCLOSURE-API-CONTRACT.md),
[independent review](docs/DISCLOSURE-INDEPENDENT-REVIEW.md) and
[bounded backend scope](docs/DISCLOSURE-BACKEND-NOTES.md).

**Preview ON: http://127.0.0.1:3104/**, retained on Internal Finance. The existing
clarity LaunchAgent now uses `SAVVY_BUILD_DIRECTORY=evidence-final` /
`.next-evidence-final`; `.next-evidence` is an inactive rollback/build slot.
Port3103/.next remains running and unchanged. Never build into the active slot.

One engine, API policies, Savvy-owned native billing, mocked Campfire/CLM and
real disclosure viewers are preserved. Household valuation/fee allocation,
alternative treatments, termination credit/independent refund, typed compensation,
cost completeness and supplied recognition are persisted in `disclosure_2027`.
The original invoice is $1,000 ($600/$400); credit $500, refund $300, remaining $200.
An unassigned 1.32% draft/current comparison ($1,000→$1,100) is available in the
household Product work queue; no reviews, publication or assignment were made.
Historical comparisons remain in lineage. No original economics were changed.

Final full regression: 191 tests / 12,139 assertions; final lineage/audience
subset: 16 tests / 233 assertions; reference suite: 49 tests; dbt: 23 models /
69 tests (92 steps); new HTTP: 102 checks; existing HTTP: 66+50+695+21 checks;
publication proof: 10 checks. Build, typecheck, eager loading and desktop/mobile
acceptance pass. All original row hashes across 16 tables remain intact. Raw logs/JSON/screenshots
are under `artifacts/disclosure`. No retained reset, external provider write,
hosted deployment, GitHub push, release or new infrastructure spend occurred.
This is a bounded fixture milestone; parent–child advisor hierarchy stays deferred.

## Real Savvy disclosures — 16 November 2026

Latest preview remains **http://127.0.0.1:3104/**, left on Agreements & terms.
Read `docs/SAVVY-DISCLOSURES-REVIEW-2026-11-16.md` for research and current gaps.
Generated sample agreement PDFs/PNGs/output copies and generator are removed.
Real, unchanged March 2026 Savvy Advisors ADV/CRS PDFs are available under separate
Savvy disclosures cards with paged view, original-PDF link and download options.
Agreement viewer remains document/version matched with an empty registry until
an actual agreement is supplied. No source disclosure is treated as an agreement
or as authorization to change the demo's terms. Retained DB references/history stay.

The clarity LaunchAgent now selects `SAVVY_BUILD_DIRECTORY=disclosures` and serves
`.next-disclosures`. Earlier `.next-clarity` is a rollback build; `.next`/port3103
remain untouched. Build into an inactive directory before activating a revision.
Production build/typecheck, 66 document/statement HTTP checks and 50 scoped audience
HTTP checks pass. All 33 public disclosure pages render; PDF hashes match the
recorded originals and generated document URLs return 404. Browser confirmed first/
last page controls, CRS navigation, download links, Escape/focus return and no
horizontal overflow at the current viewport. Campfire/CLM remain mocked; no pricing,
accounting, provider, database or hosted deployment changes were made.

## Current clarity revision — 16 November 2026

Read [the clarity milestone](docs/CLARITY-REVISION-2026-11-16.md).
The latest preview is http://127.0.0.1:3104/ and was left open on the visual
Internal Product workspace. It has agreement PDF view/download modals, dated
invoice-style statement lines, and clickable Product/Finance workflows and
recognition timelines. The single engine/API policy model and mocked Campfire/CLM
remain intact; no hierarchy decision was introduced.

The original port-3103 preview is still running. Automatic review rejected
interrupting it, so a separate `.next-clarity` build and user LaunchAgent
`com.beanlabs.savvy-clarity.preview` serve port 3104 using the existing API 3102.
Build with `SAVVY_BUILD_DIRECTORY=clarity`; never overwrite a live build directory.
Config/log copies are under `.runtime`, and the plist is in `~/Library/LaunchAgents`.
Both services use only loopback interfaces and existing infrastructure.

Full regression: 160 Ruby tests/2,077 assertions pass. New HTTP/PDF checks 35,
existing three-audience HTTP 50, and medallion HTTP 695 pass. Production build,
desktop/mobile, sample PDF rendering and local match/reversal checks pass.
The original $600/$600/$400/$800 accounting values are unchanged. No retained
database reset, provider write, hosted deployment, commit or release was made.

## Three-audience implementation complete — 15 November 2026

The user explicitly authorized Terra implementation, independent review and stress
testing of [the revised plan](docs/THREE-AUDIENCE-PLAN.md), with the local preview
left running. This supersedes the planning-only boundary in the preceding review.
Read [the delivered milestone](docs/THREE-AUDIENCE-MILESTONE.md),
[validation](docs/VALIDATION-THREE-AUDIENCE.md),
[API contract](docs/THREE-AUDIENCE-API-CONTRACT.md) and
[independent review](docs/THREE-AUDIENCE-FINAL-REVIEW.md).
Implementation and independent stress/review are complete in this isolated
worktree. The optimized preview is running under the existing LaunchAgent at
http://127.0.0.1:3103/ and was left open on the broker overview. No release, push
or replacement of the original hosted app occurred.
Keep one engine, API-driven policies, Savvy billing objects and mocked Campfire/CLM.
The parent–child advisor-account model remains deferred. Root coordinates test
database resets and the port-3103 production build/restart to avoid competing jobs.

Broker navigation is shared; Product has contextual changes and a request-based
work queue; Finance has scoped inbound/outbound cash and supplied recognition
evidence. Search and drilldowns are paged; overview reads a published projection.
The new Finance sample occupies `finance_timing_2027`, separate from September
and November records. Source originals and all prior row fingerprints are retained.
An acceptance-only $1 allocation was created and reversed. A standard-share 82%
draft/comparison remains unassigned and unpublished for review; it changes no
current earnings. Demo identities remain explicitly simulated, not authentication.

The planning status in the historical sections below is superseded by this
completion record.

## Current audience plan reviewed with Astra and Sol — 15 November 2026

Read [Three audiences](docs/THREE-AUDIENCE-PLAN.md) before further development.
It integrates the queued walkthrough feedback and defines Clients (brokers under
both products), Internal Product and Internal Finance as distinct audience jobs.
Finance requires focused cash matching PLUS recognition inputs, supplied schedules
and independently reported posted outcomes. Recognition is planned, not delivered.
Both reviewers found no blocking ambiguity in the integrated plan.

This review changed planning documents only. No app, data, policy, permission,
provider or runtime change was made. Keep the preview running. One engine,
API-driven policy, Savvy billing ownership and mocked Campfire/CLM remain required.
The advisor-account parent–child hierarchy remains explicitly deferred.
Earlier screen exclusions are superseded only to allow this focused Finance scope.

## New walkthrough feedback queued — 15 November 2026

Read docs/UI-WALKTHROUGH-FEEDBACK-2026-11-15.md before further interface work.
The user wants one affiliated-advisor/independent-RIA experience, book-level
overview with client drilldown, removal of overlapping Case/experience selectors,
record/service lineage rather than a scenario runner, and understandable
terms/review/one-time-item journeys. Proposed navigation and workflows are queued
for review; no application or runtime changes were made for this feedback.
The user explicitly deferred the advisor-account parent–child hierarchy. Do not
choose or implement parent ownership, billing rollup or inherited permissions.

## Medallion implementation — 15 November 2026

Preview availability fix: the frontend now runs as the user LaunchAgent
`com.beanlabs.savvy-medallion.preview`, with RunAtLoad/KeepAlive and its plist in
`~/Library/LaunchAgents`. Runtime logs/config copy are in `.runtime/preview.*`
and `.runtime/com.beanlabs.savvy-medallion.preview.plist`. It no longer depends on
the coding session's terminal. The isolated API now clears its own container-local
PID file on startup; a stale bind-mounted server.pid had caused a restart loop.
API restart and browser rendering were verified without resetting data. Stop this
specific LaunchAgent before rebuilding Next.js; do not start a competing frontend.

The user authorized Astra's final full-plan review, then Terra implementation,
independent review and stress testing. That authorization supersedes the earlier
planning-only phase below. Read docs/MEDALLION-MILESTONE.md,
docs/VALIDATION-MEDALLION.md and docs/MEDALLION-API-CONTRACT.md for current status.

Implementation lives in the isolated `codex/medallion-billing` worktree at
`/Users/stephenkall/beans/labs/savvy-medallion-development`. Preview 3103/API 3102/DB
55438 use the separate savvy-medallion project and volume. Original hosted code,
services, policies and retained records are unchanged. Do not copy changes into
the running original checkout or restart its services as a development shortcut.

Both product cases and legacy evaluations use the shared typed graph interpreter.
Policies/rates/assignments are versioned API data. Bronze retains original bytes
and arrivals; Silver selects known source facts/terms; Gold retains exact results;
dbt selects publications without pricing. One-time event policies, approvals,
payment applications, reversals and sealed statement roll-forwards stay distinct.
Campfire/CLM remain mocks and no execution or real provider write was added.

The local data is fictional and this remains a bounded prototype. Use the new
validation record for passed checks and explicit capability limits. No release,
GitHub push or replacement of the existing hosted app is part of this milestone.

## Next milestone planned with Astra — 15 November 2026

Read docs/MEDALLION-PROTOTYPE-PLAN.md and docs/MEDALLION-SAMPLE-WALKTHROUGH.md.
These are planning documents and independently checked target figures, not
implemented pipeline behavior. User requested preparation, retaining the explicit
no-code-change boundary. No runtime or policy changes were made for this plan.

Hard requirement: one billing engine for both affiliated-RIA and independent-RIA
custodial products. Commercial terms/formulas/assignments change via versioned API
policies without product-specific code or redeployment. Bronze original evidence,
Silver normalized facts and same-engine policy binding, Gold detailed results and
separate hourly/daily rollups. dbt never becomes a second fee calculator. Add
internal-only Architecture/Data pipeline explanation and two external value stories
using the same outputs. Keep providers mocked and preserve existing history.

Include one-time/ad hoc/post hoc charges, credits and compensation entitlements
through a governed event register feeding the same medallion path and engine.
Keep payment requests distinct from independently evidenced payment applications.
Statements are derived unified views, not an alternative writable amount source.
The walkthrough adds bonus/guarantee, payment and service-credit cases, with exact
approval/knowledge/posting boundaries and preserved historical statement fixtures.

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
