# General billing milestone

Scope: both products end to end, commercial composition through policy data,
general source processing, and issued billing corrections. Finance operations,
actual agreements/CLM, production identity, MCP/WebMCP and advisor hierarchy stay
outside this milestone. Campfire and CLM remain mocked. One Economics::Engine is
the sole monetary evaluator; reporting and the browser never price a contract.

## Shared path

Versioned source mapping → retained delivery bytes → normalization job and
quarantine → dated accounts, balances, time and one-time events → reviewed policy
and dated assignment → exact engine calculation → native invoice and lines →
reviewed credit/debit corrections → the same scoped client statement.

Use a new `billing_platform` namespace; retain all existing examples. Both product
cases use identical services, commands and client navigation. Product differences
are policy and input data. Independent RIA platform invoices bill the RIA firm;
underlying client/account information is usage evidence, not a second client fee.
Affiliated advisor invoices bill the relevant client household. Compensation is a
separate engine output and is never added to client charges.

## Commercial policy data

Accept either a composable policy specification or a validated primitive graph.
The common component compiler supplies annual AUM charges, fixed service, account
usage, time, approved one-time charges/credits, dated rates, bands, floors/caps and
separate compensation. Graph mode exposes the existing typed operations without
requiring a new pricing implementation for each combination. Exact money and
explicit assessment/allocation remain mandatory. Unsupported types, ambiguous
rates, missing sources and resource-limit violations fail closed.

Saving, frozen-input comparison, independent mock Legal/Finance reviews,
publication, dated assignment, evaluation and document issue are separate API
commands. Reviews bind source/policy/implementation hashes. A new rate or supported
composition requires API data, not a release. Date windows are generic; there are
no hardcoded February or September assignment intervals. Requested periods that
cross assignment boundaries must be split into explicit service segments and
rolled up through the same engine; fixed/minimum proration is declared policy.

## Source processing

Source definitions contain versioned field mappings and source ownership. Raw
JSON/NDJSON and unsupported bytes are retained before validation. Normalization
runs as an actual ActiveJob; the preview's adapter remains inline and is labelled
as such. No durable-worker claim or new paid queue is introduced.

Store execution receipts, quarantine reasons, mapping versions, original identity,
source revision, internal receipt time and upstream observation time. Replay
retains new execution evidence and deduplicates identical source revisions;
conflicting revisions are quarantined. Latest-known revision selection happens
before service-date filtering, so moved or withdrawn observations cannot resurrect
older values. Membership and daily completeness are checked before pricing.
One-time events use the same intake and require a separate Finance decision.

Gold results retain frozen manifests, graph/output/source references and daily
accrual/period assessment. A missing day blocks the affected group; it must not
create a partial invoice. Client lists and internal histories are paged in SQL.

## Native documents and corrections

Extend existing native invoice/line objects with typed document identity,
original-document links, parties and issue/due/posting dates. Positive stored
amounts retain their meaning through explicit invoice/debit/credit type; originals
are immutable. Do not create a competing writable statement amount table.

Issuance copies only completed, approved, source-fresh engine outputs, conserving
lines and amount. Subsequent source or policy changes produce a correction
proposal against the last issued target. Engine-computed per-account differences
create credit and/or debit notes, including zero-net reallocations. Finance must
approve the exact proposal before atomic issue. Repeated issue/idempotent retries
cannot create duplicate correction documents. A later correction compares against
the latest issued target rather than charging the original difference twice.
Closed service periods remain closed; corrections name an open posting period.
No correction implies cash movement or recognition. Refunds and supplied mock
accounting outcomes remain separately evidenced.

## Acceptance

- Both products: several clients/accounts, two billing periods, generic service
  dates, policy comparison/review/assignment, actual native invoices and matching
  client statements with allocation and source drilldowns.
- API-only policy change: combine mechanisms, tiers and dated promotions; compare
  identical frozen inputs; confirm source/implementation changes invalidate review.
- Intake: differently named source fields, late revisions, duplicated deliveries,
  conflicting identity, missing days, quarantine, replay, membership changes and
  one-time event review. No page read runs or seeds the pipeline.
- Corrections: increases/decreases, one-cent changes, zero-net reallocations,
  repeat correction, closed periods, wrong scope/parties/currency, stale approvals,
  concurrent retries and injected rollback. Original documents never change.
- Native SQL conservation, scoped references and append-only enforcement survive
  schema export/restore. Existing rows are preserved by comparing old columns.
- Desktop/mobile client, Product and billing-correction Finance journeys; actual
  job/record lineage and API reference match implemented behavior.

## Runtime isolation and activation

Current API 3108 and candidate-a/3104 remain immutable and serving during work.
Use disposable tests (55439) and a restored retained-data clone for migration
rehearsal and candidate API 3109. Never migrate/reset the current served database.
Capture retained state again before activation and refuse an out-of-date clone.
Build candidate-b only, require exact final Prototype and Architecture CI, then
activate through the owned preview guard. Preserve the previous pair and database
for rollback. Publish updated architecture/API documentation and keep preview on.
