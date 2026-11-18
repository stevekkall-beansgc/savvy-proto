# Savvy Proto

Private source repository for the Savvy advisor workspace prototype. Maintained
by Stephen Kall / Legume Labs. GitHub Releases are the versioned changelog;
the development API contract is currently 0.6.0. Source backup does not include the
retained Docker database volume. Current handoff: [NEW-SESSION-HANDOFF.md](NEW-SESSION-HANDOFF.md).

**Live private app:** https://savvy-proto.beanshop.top/ — the full application runs
on the owner's Mac behind Cloudflare Access. Sign in with the owner's existing
Google account or email code. See [hosting and recovery](docs/HOSTING.md).

The full application requires Next.js, Rails and PostgreSQL. The historical
`dist/` directory is an older Python-reference preview, not a deployment of the
current application. Hosting status and supported behavior belong in
[the hosting record](docs/HOSTING.md).

An independent Legume Labs prototype for explaining an advisor's next expected
payment from billable assets, effective contract terms, expenses, collections
and loan repayment. It includes an interactive local application, deterministic
financial calculations, synthetic Campfire-shaped accounting evidence, and
primary-source research notes.

**All advisors, clients, contracts, assets and accounting records are fictional.**
The application is not connected to Savvy or Campfire. Forecasts do not create
accounting entries, alter a loan, approve a payable, or execute a payment.


## Latest milestone

The [disclosure-informed milestone](docs/DISCLOSURE-MILESTONE.md), planned with
Astra and implemented/reviewed/stress-tested by Terra, adds engine-backed household
billing, governed policy alternatives, separate credit/refund and compensation
evidence, cost completeness and supplied recognition. Try the current local
revision at **http://127.0.0.1:3104/**. The hosted app above is an earlier revision;
port3103 stays available separately. Real Savvy disclosures have view/download
controls; the agreement viewer awaits an actual agreement document.

The [three-audience milestone](docs/THREE-AUDIENCE-MILESTONE.md) implements the
walkthrough plan reviewed with Astra and Sol: a shared broker experience, Internal
Product workflows and record proof, and Internal Finance cash matching plus
revenue-recognition visibility. Terra agents implemented, independently reviewed
and stress tested it. See [validation](docs/VALIDATION-THREE-AUDIENCE.md).

The [medallion milestone](docs/MEDALLION-MILESTONE.md) adds two product experiences,
an internal architecture/pipeline walkthrough, and one policy-driven billing
interpreter for recurring and one-time economics. Astra reviewed the complete
plan; Terra agents implemented, reviewed and stress-tested the changes.
Commercial formulas and terms change through the versioned API. Campfire and CLM
remain mocked. See the [sample calculations](docs/MEDALLION-SAMPLE-WALKTHROUGH.md),
[API contract](docs/MEDALLION-API-CONTRACT.md) and [validation](docs/VALIDATION-MEDALLION.md).

This milestone is isolated from the hosted app. Its local preview uses
http://127.0.0.1:3103, API port 3102 and database port 55438 in the separate
`savvy-medallion` container project/volume. Start it with
`./scripts/medallion-preview.sh` after the documented fixture setup. Validate it
with `./scripts/medallion-check.sh`. Do not use the default Compose project for
this milestone's development or destructive tests. The existing hosted version
has not been replaced.

The Astra-planned, Terra-built [workspace milestone](docs/WORKSPACES-MILESTONE.md)
separates Broker earnings/agreements from Internal advisors/commercial terms/approvals.
Savvy owns billing obligations, invoices and custodial instructions in PostgreSQL;
Campfire accounting and CLM document/review references remain local mocks. Read the
[finalized contract](docs/WORKSPACES-IMPLEMENTATION-CONTRACT.md),
[billing ownership research](docs/BILLING-OWNERSHIP-DEEP-DIVE.md) and
[current validation](docs/VALIDATION-WORKSPACES.md).

The prototype now uses Savvy's official public-site logo, colors and typography.
See [brand provenance](docs/SAVVY-BRAND-REFERENCE.md). Earlier settlement and
reconciliation APIs, evidence and tests remain retained outside the primary navigation.
Nothing moves real cash.

## Interactive architecture walkthrough

Open the source-linked [architecture walkthrough](docs/architecture/README.md):
`python3 scripts/architecture_preview.py`, then `http://127.0.0.1:3105/`.
The three views cover the mental model, complete technical architecture and
shared policy engine. Component modals link to exact GitHub source lines;
all 33 nodes of the retained sample calculation are inspectable. The standalone
HTML works offline. This documentation preview is separate from the full app.

## Continued Rails / Next.js prototype

The interrupted rewrite has been reviewed and extended into a runnable local
vertical slice. Read [current status](docs/CONTINUATION-STATUS.md),
[interrupted-work review](docs/INTERRUPTED-WORK-REVIEW.md) and
[earlier settlement validation](docs/VALIDATION-SAVVY-SETTLEMENT.md). The broader execution
plan is still a phased target, not an implemented product.

Requirements: Docker daemon, Node 22+, npm, Python 3.11+; uv for optional dbt checks.
The pinned Ruby runtime runs in Docker, so the Mac's system Ruby is not used.
From this directory:

```sh
./scripts/setup.sh
./scripts/start.sh
```

Open **http://127.0.0.1:3100**. The frontend and Rails API use loopback ports
3100/3101; the isolated synthetic PostgreSQL database uses loopback 55437.
These are local services, not a deployment. The Docker database uses trust auth
for fictional data only. `./scripts/stop.sh` stops its containers and retains
its own named data volume; stop the frontend in its terminal with Ctrl+C.

Start in **Broker → Earnings**, expand a customer, then open **Agreements**.
Switch to **Internal → Advisors → Commercial terms** to prepare dated standard,
advisor-wide or targeted promotions. In **Approvals**, compare the current book
or a separate hypothetical future signup, simulate Legal and Finance review of
the exact mock document version, then schedule the reviewed terms. Saved drafts
do not become current. The demo business date is November 13, 2026.
The experience switch and simulated review roles are not production authentication.

```sh
./scripts/check.sh      # Legacy tests, Ruby/Postgres/API tests, loading and UI build
./scripts/analytics.sh  # Optional locked dbt build and reconciliation checks
./scripts/reconciliation-check.sh # Populated canonical proof in disposable test DB
python3 scripts/http_check.py     # Actual local API access/envelope checks
python3 scripts/product_http_check.py # Broker/internal product and billing boundaries
python3 scripts/recovery_check.py # Consistent logical restore into a disposable DB
```

Setup and test commands affect only this prototype's named database. The test
suite clears its own `_test` database tables. Setup is repeatable and preserves
existing draft versions and runs. No real accounts or credentials are needed.
The original Python application below remains available independently on 8766.
No two monetary engines drive the same screen.

The authoritative Rails database schema is `apps/api/db/structure.sql`. It retains
PostgreSQL exclusion constraints, deferred billing conservation triggers and their
function; a Ruby schema dump would lose those protections. Fresh databases load
that SQL schema. Setup also backfills the new workspace and billing fixtures on
existing volumes without replacing prior policies, operations or runs.

## Original Python reference

## Local preview and standalone source

This repository is independent of Legume Labs Core. `dist/index.html` is a precomputed static preview; this copy has not been published. Regenerate it with `python3 build_preview.py --output dist/index.html` after changing the app or fixtures. The local application below offers custom scenarios; the hosted preview offers four presets per advisor.

## Execution plan

The detailed [execution plan](docs/EXECUTION-PLAN.md) defines the proposed Rails/Next.js/PostgreSQL/GraphQL rewrite, customer-level collection, accounting boundaries, Campfire integration, dbt models, acceptance tests and build gates. The current vertical slice is described above; the remaining plan and integrations are not complete.

## Evidence and current scope

See [Evidence, requirements and prototype scope](docs/EVIDENCE-AND-SCOPE.md) for what is known, what the owner requested, what remains unknown, and what the current experiments actually implement. That historical scope describes the Python reference. See CONTINUATION-STATUS.md for supported Ruby policy, coverage, guarantee and review behavior; live feeds and full integrations remain unimplemented.

## Run the application

Use Python **3.11 or newer**. Runtime dependencies are Python standard library
only; no API key, package installation, Docker, database or external service is
needed.

From this directory:

```sh
python3 -m advisor_payout
```

Open **http://127.0.0.1:8766**. Stop the server with `Ctrl+C`. If the port is in
use, run `python3 -m advisor_payout --port 8767` and use that port instead.

Keep the default loopback binding. The server is a local demonstration, without
production authentication, tenant authorization, deployment or operational
recovery controls.

### What to try

1. Choose Alex, Jordan or Taylor to compare a simple split, an expense/loan
   arrangement, and effective-dated terms with client-book changes.
2. Select a preset or use the market, net-flow and collection sliders. The
   Python engine recalculates supported custom scenarios and the baseline.
3. Inspect the fee-to-payout waterfall, daily calculation rows, contract
   segments, cost treatment, remaining loan and model assumptions.
4. Open Accounting evidence to see invoices, cash, credit memos and reversed
   payment records from the separate synthetic Campfire fixture.
5. Export a JSON snapshot containing the result, assumptions, source evidence
   and deterministic receipt. This export is a calculation record, not a
   payment instruction.

The sample observes November 1–13, 2026 and projects November 14–30. Its assumed
collection/payout date is December 5, 2026. The service period, observation
cutoff and collection target are separate dates.

## Portable offline preview

The integration-owned preview builder produces one standalone HTML artifact:

```sh
python3 build_preview.py
```

Output: `artifacts/advisor-payout-preview.html`.

The offline file embeds the Python engine's exact precomputed results for the
three sample advisors and supported presets. It supports navigating those
snapshots, inspecting evidence and exporting the selected result. It does not
run the Python engine or calculate arbitrary slider combinations in JavaScript.
Use the local server for custom scenarios. Regenerate the preview after changes
to code, fixtures, UI assets or source notes.

## Architecture

| Component | Responsibility |
| --- | --- |
| `advisor_payout/engine.py` | Pure validation and integer financial calculations; no ERP or network coupling |
| `advisor_payout/fixtures.py` | Fresh fictional daily billable-asset observations and advisor terms |
| `advisor_payout/campfire.py` | Offline invoice/payment normalization, source revision handling, explicit mapping and reconciliation boundary |
| `advisor_payout/server.py` | Loopback HTTP transport, input limits, static file allowlist and result envelopes |
| `web/` | Native HTML/CSS/JavaScript presentation and scenario controls |
| `fixtures/campfire-sample.json` | Independent fictional ERP-shaped snapshot |
| `tests/` | Engine, adapter and integration checks |
| `docs/` | Calculation contract, source register, research and development handoff |

The UI includes a standalone copy of Legume's shared design tokens and primitives. The pure forecast engine is newly implemented. Bean Counter informed
the exact-money and retained-evidence architecture; this application does not
invoke Bean Counter. See [reuse provenance](docs/LEGUME-REUSE.md).

### Local HTTP API

| Route | Purpose |
| --- | --- |
| `GET /health` | Local health and explicit synthetic/not-connected status |
| `GET /api/bootstrap` | Sample advisors, presets, sources and initial result |
| `GET /api/sources` | Research source register |
| `POST /api/forecast` | Calculate a supported scenario; changes no persisted or external record |

Example request body:

```json
{
  "advisor_id": "advisor-jordan",
  "scenario": {
    "market_change_bps": -300,
    "net_flow_cents": 100000000,
    "collection_bps": 9000
  }
}
```

Scenario values are integers. Basis points use 10,000 for 100%; monetary inputs
are USD cents. Unsupported fields and invalid values fail validation rather
than acquiring an inferred financial meaning.

## Financial scope

The implemented fee convention is daily closing **billable** AUM, ACT/365,
monthly arrears. Fees are calculated with integer ratios and explicit cent
rounding. Effective contract segments must cover the period without gaps or
overlap. Pre-share and post-share expenses have distinct economics. Loan
repayment is bounded by remaining principal, the agreed schedule, available
proceeds and the configured percentage cap.

Gross fee accrual, full-period advisor entitlement before debt, expected
collections and estimated payout remain distinct. A future market scenario
cannot rewrite the observed daily balances or historical earned fees. Costs
that cannot be deducted remain visible rather than being silently forgiven.

The Campfire boundary keeps credit memos out of cash. Repeated source records
do not duplicate cash; a later payment void updates the current projection and
retains the earlier supplied version. Voiding an invoice alone does not prove
a refund: active cash stays observed and its allocation is flagged for review.
Unknown payment types, unresolved mappings and missing collection horizons
prevent a complete comparison.

Read the [calculation contract](docs/CALCULATION-CONTRACT.md) for exact formulas,
rounding boundaries, independent arithmetic examples and rejected inputs.

### Material limits

This prototype does not establish Savvy's actual fee basis, contract waterfalls,
advisor ownership mappings, bank settlement or Campfire configuration. It does
not implement advance billing, tiered fees, household discounts, all fee
exclusions, taxes, loan interest, clawbacks, multi-currency conversion,
split-advisor invoices, live imports or a production ledger.

The synthetic cash-type allowlist is explicitly fixture policy. The official
API material retrieved documents `CREDIT_MEMO` but did not establish a full
cash-payment enum. No live connection, webhook, invoice-email export or ERP
write is implemented.

## Validate

Run the local unit/integration suite:

```sh
python3 -m unittest discover -s tests -v
```

The focused adapter gate is:

```sh
python3 -m unittest discover -s tests -p 'test_campfire.py' -v
```

At the adapter handoff, its **17 tests passed**, including exact decimal
precision, stable-ID retries, later voids, cash versus credits, mapping scope
and the separate collection horizon. The integration owner records final full
suite, HTTP, preview and browser evidence in `docs/VALIDATION.md`. A documented
command is not itself a passing result.

Playwright is an optional development tool for browser interaction, responsive
layout and screenshot checks. It is not a runtime dependency. No production
data validation, Campfire tenant test or company acceptance is claimed.

## Continue development

Use [CODEX-HANDOFF.md](docs/CODEX-HANDOFF.md) for the next bounded implementation
step and the questions that must be answered before adapting real inputs.
The attempted automatic Codex fork failed with a read-only-filesystem error;
the prototype was built in the current workspace and this handoff was prepared.
No native Codex fork is claimed to have started.

Research: [Savvy context](docs/RESEARCH-SAVVY.md),
[Campfire API boundary](docs/RESEARCH-CAMPFIRE.md),
[source register](docs/SOURCE-REGISTER.json).
