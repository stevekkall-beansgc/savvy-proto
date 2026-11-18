# Three-audience prototype milestone

15 November 2026. The owner authorized Terra implementation, independent review
and stress testing of [the three-audience plan](THREE-AUDIENCE-PLAN.md). Work is
local in the isolated medallion worktree; it is not a release or hosted-app update.

## Delivered experience

| Audience | Behavior |
|---|---|
| Clients: brokers under both products | Shared Overview, Clients, Statements and Agreements. Book totals and same-engine value comparisons lead to server-paged underlying accounts, observations and statement explanations. |
| Internal Product | Account terms, contextual change and one-time-item requests, exact policy comparisons and reviews, and record/service evidence. Supported commercial changes remain versioned API policy data. |
| Internal Finance | Separate cash-matching and recognition views. Inbound cash, partial/multiple associations, residuals, returns and independently supplied accounting outcomes remain distinct; outbound advisor evidence has its own context. |

The overview reads an immutable published projection, not a calculation or a
whole-book detail response. Baseline API writes refresh the projection in the
same transaction. Statement lines and daily observations load only on drilldown.
Repeated equivalent refreshes reuse the current publication and create no money.

The internal explorer searches and pages retained medallion evidence plus scoped
Savvy obligations, invoices/lines, custodial instructions, accounting observations
and commercial rates. Transitions are navigable and paginated. It distinguishes
retained links, observed engine execution, mocked handoffs and missing evidence.
An absent timestamp or payout instruction remains absent.

## Finance proof

An isolated, fictional 2027 service example assesses its commercial amounts with
the existing interpreter and stores obligations and invoice lines in Savvy's data
layer. Original fixture/policy bytes, delivery hashes, assignments and exact run
references are retained.

- A $1,200 billed-in-advance invoice has $900 received, $600 locally associated
  and $300 unapplied. The accounting mock independently reports $600 applied,
  $600 receivable, $400 recognized and $800 deferred.
- Another $200 net payment carries $210 gross/$10 fee evidence. A $50 returned
  payment cannot be matched. Explicit source/counterparty mappings support
  multiple payments and invoices; amount equality is not authorization.
- A further $300 association can receive the authored accounting confirmation,
  subject to its exact source, application and supplied evidence clock. Local
  matching alone changes neither reported AR nor recognition.
- A separate $100 unbilled input has an independently supplied January posting.
  February invoice issuance and a revised input link to a separate reclassification
  posting with no additional recognized revenue. Missing later outcomes stay missing.
- Reversals preserve previous observations and require an accounting correction
  when a confirmed association has been reversed. Earlier/locked posting periods
  and acknowledgment before the association are rejected.

Recognition timing and gross/net treatment are authored fictional Finance inputs,
not inferred rules or a new recognition calculator. Input packages, schedules and
posted outcomes have separate identities and evidence.

## Boundaries

One billing interpreter remains authoritative. The UI, reporting jobs and
recognition read models do not price deals. Existing exact-money, source history,
comparison/document binding, publication and assignment protections remain.
Campfire and CLM are mocked; no money moves, documents are signed or provider
calls are made. Demo identities simulate access for fictional records and are
not production authentication. The hierarchy decision remains deferred.

Matching suggestions and accounting responses are bounded, explicitly authored
examples, not production bank-feed automation. Production recognition policy,
source authority, permissions and real adapters still require owner discovery.

## Try it

Local preview: http://127.0.0.1:3103/ . Use **Business** to inspect either broker
business in the same shell. **Demo identity** opens Internal Product or Internal
Finance. Finance has its own clearly displayed service/evidence context.

The existing user LaunchAgent keeps this preview running independently of the
coding terminal. Ports remain preview 3103, API 3102 and database 55438, using
only the `savvy-medallion` project/volume. The original hosted app is unchanged.
See [validation](VALIDATION-THREE-AUDIENCE.md) and
[independent review](THREE-AUDIENCE-FINAL-REVIEW.md).
