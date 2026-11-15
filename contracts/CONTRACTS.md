# Local synthetic API 0.5.0

## Current product additions

`productWorkspace(workspace: String!, brokerId: ID, businessDate: String): JSON!`
returns the Broker or Internal presentation under the existing simulated identity.
The advisor is fixed to Alex, cannot select Internal or another advisor, and never
receives internal configuration/proposal fields. Workspace selection does not grant
access. Internal readers can inspect the advisor directory and selected economics.

`SAVE_TERMS_PROPOSAL`, `COMPARE_TERMS_PROPOSAL`, `REVIEW_TERMS_PROPOSAL` and
`SCHEDULE_TERMS_PROPOSAL` use the existing structured command/idempotency envelope.
Immutable proposals bind exact rates, effective date, base configuration and reason.
Comparisons bind source/policy/template manifests; separate Finance and Legal mock
reviews bind the comparison and mock document version. Scheduling rechecks both
reviews and current inputs atomically. A draft does not become current automatically.

`commercial_rates` is the actual scoped PostgreSQL table for standard, promotion
and targeted promotion rows, with retained versions and half-open optional end
dates. Savvy-owned billing tables retain obligations, invoice headers/lines,
custodial instructions/items and separately mocked accounting observations.
Compensation edits never alter client invoice amounts. Unknown accounting facts
remain null. No provider credentials, calls, signatures or accounting writes exist.

See [the finalized JSON and command contract](../docs/WORKSPACES-IMPLEMENTATION-CONTRACT.md)
and [implemented boundaries](../docs/WORKSPACES-MILESTONE.md). The SQL schema is
authoritative for database constraints/triggers. The earlier APIs below are retained
for compatibility and evidence; they are not primary navigation.

## Retained API and transport

`schema.graphql` is exported from the running Rails schema. It is not a Savvy API.
`POST /graphql` accepts JSON `{query, variables, operationName?}`, one operation
per request, at most 1 MiB and 50 KB of query text. Maximum depth 10, complexity
150. Same-origin frontend proxy at `http://127.0.0.1:3100/api/graphql` points only
to the local Rails service. No caller-supplied URL or provider credential.

`X-Demo-Role`: operator, finance, legal, advisor or auditor. Roles are selectable
fictional identities; this is NOT authentication. Tenant/entity scope is fixed
by the server. The advisor identity is limited to Alex's book. These controls
are a tested local simulation, not production-grade authorization.

Read operations: `workbench`, `brokerBook(brokerId, runId?)`, `collections`,
`run(id)`, `reviewPacket(runId)`, `entitlementLedger(brokerId?)`.
`reconciliation(periodStart, periodEndExclusive, closeId?)` supplies independent
invoice/bank evidence and frozen review snapshots; it excludes the advisor role.
`collections` optionally accepts `knowledgeCutoff` for a retained as-known view. Mutations use `workbenchCommand` with an
allowlisted action, structured input and required idempotency key. Domain failures
are `errors {code,message,path}` with null data. Transport/parse failures are
separate. No payment, ledger posting or live-provider mutation exists.

- PROJECT: `policy_id`, `snapshot_id`, optional `business_date` and ISO
  `knowledge_cutoff`. Inputs must be explicitly pinned. Result/inputs/hashes
  retained atomically. Projection never spends an actual grant.
- SAVE_POLICY: full supported `policy`, `expected_hash`. Creates a draft version;
  immutable old versions remain accessible. Supported selector dimensions are
  the fictional customer_type/product_type registry. Conflict checks cover its
  finite value combinations and effective boundaries. No arbitrary code/SQL.
- IMPORT_SNAPSHOT: full fictional `snapshot` with fixed synthetic adapter source,
  known directory IDs and optional `knowledge_cutoff`. Same source fact/revision
  cannot be rewritten by a different batch ID. Conflicts retain a quarantine
  record, hash, owner and next action. Incomplete/stale envelopes are rejected;
  accepted row-level quality failures remain visible and block a projection.
- MATCH: `charge_id`, `receipt_id`, `minor_units`. Internal approved operational
  match, not invoice application. Scoped database lock and conservation checks.
- LINK_INVOICE: `charge_id`, `invoice` (synthetic scope/customer/id/amount/status).
  Requires simulated finance role. One equal-value invoice per charge in this
  first slice; discrepancies/split invoices require an extension/review. No new
  receipt, AR application or recognition is created.
- REVIEW: `policy_id`, `policy_hash`. Requires separate simulated finance/legal
  roles. Binds wording, structured policy, source and examples hashes.
- ACTIVATE: same IDs/hash; operator role. Requires both reviews of current
  examples. Does not execute a contract. All projections remain simulations.

Money fields are integer USD cents in persisted snapshots, String in GraphQL
Money and nested JSON `_minor`/`minor_units`/`threshold` fields. Command input
accepts exact base-10 integer strings as well as integers, never binary decimal
money. The USD form parses two decimal places as a unit conversion only.
`null` means missing evidence. Zero means a computed or observed zero under the
specified scope. Dates are half-open; timezone America/New_York, service-date
rate/assignment. Exact weighted shares are rounded half-up once per source fee
line, then distributed by largest remainder with stable broker ID ties.

The first Ruby engine consumes fixed eligible fee observations. The retained
Python reference handles daily AUM-based fees; they are separate financial paths.
Neither proves actual company rules. Broader typed GraphQL domain coverage,
pagination, bitemporal warehouse publication and the rest of the plan remain
future work; the JSON payload fields are the explicit initial contract.

## Recorded settlement and reversal additions

CONSUME_ENTITLEMENT: `grant_id`, `obligation_id`, exact positive `minor_units`,
`reason` (3–300 characters). Finance only. Appends a consume entry in the scoped
transaction and rejects incompatible directions, scope or exhausted balance.

REVERSE_ENTITLEMENT: original `entry_id`, `reason`. Finance only. Exact full
original reversal, once, restoring its grant and obligation. Original survives.

REVERSE_MATCH: `allocation_id`, `reason`. Finance only. Releases an internal
operational match; it does not reverse receipt evidence or issue a refund.

REVERSE_RECEIPT: `receipt_id`, integer `expected_revision`, `reason`. Finance only.
Appends the next immutable receipt revision and internal match reversals atomically.
Returns a prior-view cutoff; it neither verifies nor sends a bank refund.

The grant ledger is separate from a hypothetical projection. New runs bind an
as-known entry manifest and derived balance to their frozen inputs. Source grant
openings cannot be reset through a snapshot import. Arbitrary grant/obligation
creation and partial-original reversals remain outside the initial contract.

## Reconciliation review additions

All new writes require the simulated Finance role, an idempotency key and a
3–300 character reason. Evidence writes also require an ISO `business_date`.

- RECORD_INVOICE_APPLICATION: `invoice_id`, `receipt_id`, positive `minor_units`.
  Independently supplied application evidence; same scoped customer and USD,
  verified receipt, conserved receipt/invoice bounds. Source revision/amount are
  captured. Operational matching does not spend the independent application bound.
- REVERSE_INVOICE_APPLICATION: `application_id`. Appends the full original reversal
  once. No deletion, additional cash or provider application is created.
- RECORD_BANK_BATCH: unique `id`, unique whole `receipt_ids`, nonnegative
  `gross_minor`, `fee_minor`, `net_minor`. Gross equals attributed receipt amounts
  and fee plus net. A receipt belongs to at most one active batch. Source receipt
  identity/revision/amount are retained. Net/fees remain entity/batch measures.
- REVERSE_BANK_BATCH: `batch_id`. Appends an exact original reversal once, releasing
  membership for a subsequent separately evidenced batch.
- CLOSE_RECONCILIATION: `period_start`, `period_end_exclusive`,
  `expected_manifest_hash`, `reason`. Compares and freezes the review under the
  same scope lock as evidence writes. This is a review snapshot, not an accounting
  close or period lock.

Invoices are included by their charge's service-period start in the requested
half-open interval; bank batches use their explicit business date. These are
different populations and are not automatically reconciled by equal totals.
Unknown invoice applications make aggregate applied/open amounts unknown. Full
reversal can establish evidenced zero. Derived invoice open is not confirmed AR;
recognized revenue stays unknown. Receipt corrections preserve independent
application/bank records and surface conflicts against captured source provenance.

Frozen review content remains unchanged; `later_evidence` and `late_exceptions`
are separate overlays. The manifest conservatively covers all relevant evidence
kinds across the entity, including other periods. Another period's change can
invalidate a pending freeze or appear in the late overlay. Current read views are
also scope-locked to prevent a mixed manifest and balance snapshot.

The detailed additive JSON envelope is recorded in
`docs/CTO-RECONCILIATION-CONTRACT.md`; the exported SDL remains authoritative for
GraphQL names and types. The JSON payloads do not constitute the full proposed
typed production domain schema.
