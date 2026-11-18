# Two products, one billing engine — delivered milestone

15 November 2026. Astra reviewed the complete plan and sample walkthrough before
implementation. Three Terra lanes built the interpreter, persistence/API and UI;
they independently reviewed the changes and added adversarial tests. Root
integrated reporting, statement roll-forwards and presentation, then exercised the
actual API and desktop/mobile product. All examples and records are fictional.

## Try the new version

Open http://127.0.0.1:3103. The preview is in the separate
`/Users/stephenkall/beans/labs/savvy-medallion-development` worktree on
`codex/medallion-billing`. API 3102 and database 55438 use the separate
`savvy-medallion` container project and volume. Restart the preview with
`./scripts/medallion-preview.sh`; setup/fixture commands are in the
[API contract](MEDALLION-API-CONTRACT.md).

On this Mac, the frontend is now managed by the dedicated user LaunchAgent
`com.beanlabs.savvy-medallion.preview`, which starts at login and restarts on exit.
The API uses a container-local PID file cleared on startup, so a Docker restart
does not leave it trapped behind a stale server.pid. These changes preserve the
existing database and the separate hosted application.

The existing device-hosted app, original checkout and retained database were not
replaced. Exact row fingerprints of all 15 original public tables match the
before-development baseline. The new source is local and has not been pushed,
released or deployed to the existing hosted address.

## Product journeys

| Experience | Delivered behavior |
|---|---|
| Affiliated advisor | Compensation, prior advance and remaining payment; separate client-fee and advisor-compensation detail; daily balance history; applicable rates, dates and signup conditions; same-input value comparison; statement/payment activity. |
| Independent RIA | Platform charge, qualified credits and amount due; separate platform charges, network economics and investor activity; reported allocations; terms/cap/rebate value; statement and credit balances. |
| Internal team | Architecture with authority/grains/clocks; original deliveries, normalized facts, selected terms and detailed results; hourly/daily publication snapshots; policy authoring/comparison/mock reviews/assignment; one-time events and payment evidence/application/reversal. |
| November workspace | Earlier workspace remains available, with $1,750 earned, $1,000 coverage and $750 remaining in the fresh isolated baseline. The original hosted history remains untouched. |

Product-facing screens keep Savvy's existing public-site branding and ordinary
inclusive dates. Technical identifiers and raw evidence stay in the internal
experience. The old Sources/Runs, Collections, Settlement, Reconciliation and
Review packet navigation was not revived. No clause editor was introduced.

## One engine and API-driven policies

Both products use the same pure, bounded graph interpreter. Legacy requests also
compile their complete allocation/share/coverage/guarantee request into one graph
and execute it once. `CommercialEngine` is a compatibility facade; the Python
reference stays offline. There is no second UI, dbt or product calculator.

Policy versions contain supported formulas, tiers, selection/eligibility,
aggregation, caps, guarantees, event groups and netting. Negotiated rates are
versioned rows in the shared `commercial_rates` table. Separate assignments carry
effective intervals and known-time schedule versions. Exact comparisons and mock
Legal/Finance reviews bind the policy, source manifest, document and interpreter
build. Publication and assignment are separate actions.

The four policy-only demonstrations use the same source manifest and unchanged
interpreter: rebate 40%→50% produces $100 due; adding $50 outside the capped group
produces $180; balance-based platform pricing produces $60; a $3,400 advisor floor
produces $2,400 remaining after the advance. These are graph/rate changes through
the API, not new Ruby pricing classes or frontend deployments.

## Evidence, events and statements

Bronze retains original bytes and each delivery, including duplicate, rejected
and conflicting arrivals. Silver keeps scoped, versioned facts and approved
events. Account usage comes from a retained roster rather than a policy constant.
Funding rights, receipts, receipt allocations and netting authority have separate
evidence. Gold results retain exact amounts, assessment, dependencies and source
references. Read-only dbt models select result versions and publish component
snapshots; repeated hourly/daily publication is not additional accrual.

One-time charges, credits and compensation use approved event treatments in the
same engine. Requests, approvals, service dates, knowledge and posting dates are
separate. Payout intent is not payment evidence. Only confirmed, allocated payment
evidence reduces an outstanding obligation; pending/unapplied activity is shown
separately. Credits can create a credit balance without inventing a refund.

Statements reference selected results and applications. After a sealed statement,
the next projection starts with its opening balance and appends component/payment
differences. A $100 bonus within the guarantee shows +$100 bonus and −$100 guarantee
adjustment, keeping $2,300 payable. Outside the guarantee, the same bonus leaves
$2,400. A confirmed $500 payout leaves $1,800; a $30 Harbor credit leaves $100.
Original statements, applications and evidence are never rewritten.

Savvy retains billing obligations, invoice/credit representations and payout
intent close to its data layer. This proof produces retained results and billing/
statement previews. Campfire accounting and CLM documents/reviews remain mocked;
there is no real signature, invoice issuance, accounting post or money execution.

## Practical boundaries

This is the agreed bounded prototype, not production financial infrastructure.
Identity is simulated and the executable cases are allowlisted. The current
period fixtures use USD and explicit ACT/365 conventions. No live network feed,
provider behavior, real client data, authentication integration or sustained load
capacity is established. Richer FX, rolling guarantees, amortizing loans and other
untested compositions fail explicitly or remain capability work.

Synthetic delivery intake is bounded to the existing fixture field contracts;
unknown/rejected payloads are retained, not silently promoted into facts. Exact
single-interval backdated assignment replacement is supported; broader schedule
replacement is intentionally rejected. Event-policy validation supports the
tested floor/coverage compositions rather than accepting every equivalent graph.
Extending these adapters/controls must preserve the one-engine contract.

See [validation](VALIDATION-MEDALLION.md), the
[final architecture review](MEDALLION-FINAL-REVIEW.md),
[engine contract](MEDALLION-ENGINE-CONTRACT.md) and
[API contract](MEDALLION-API-CONTRACT.md).
