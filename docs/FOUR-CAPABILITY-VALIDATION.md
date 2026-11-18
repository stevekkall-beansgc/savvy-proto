# Shared billing foundation validation

Historical foundation milestone. It did not fully complete the four priorities.
Current closure scope and evidence: `FOUR-CAPABILITY-CLOSURE.md` and
`FOUR-CAPABILITY-CLOSURE-VALIDATION.md`. Earlier limits below describe that build.

This milestone implements both product cases through the same source, policy,
engine and native document path. Existing household/book examples remain retained.
The default workspace has two service periods, three client groups and six
accounts per business. Advisor client billing is distinct from compensation;
RIA platform invoices bill the RIA, with custody income separately reported.

## Boundary

Supported terms compose AUM (daily or ending), progressive bands, dated standard,
promotion and targeted rates, fixed, account usage, time, approved one-time
charges/credits/payout entitlements, floors/caps and compensation. A validated
primitive graph can be submitted instead. All monetary evaluation uses the one
Economics::Engine. A new primitive requires engine development; new combinations
of supported primitives and commercial values are API data. USD only; each group
has explicit safety limits, including 100 accounts and 366 days per request.
Books and histories are paged. This preview is not an unbounded production worker.

BillingNormalizeJob is an actual ActiveJob running inline. Mappings, exact
coercions, raw bytes, quarantine and replay are implemented; live provider
connectors and durable job infrastructure remain deferred. Source mapping changes
hide old normalization until replay; old record IDs and issued documents remain
addressable. Mandatory missing balances or time block billing. Optional reported
income can remain unknown without blocking an unrelated platform charge.

Savvy owns invoice, line and obligation records plus linked credit/debit notes.
Corrections are reviewed against the last issued target, with source, schedule,
implementation and posting-period guards. Reallocation can issue both note types
with a zero total difference. Overlapping original service invoices are rejected.
Payments/refunds and mock accounting acknowledgments are separate source evidence;
there is no live cash execution or inferred revenue recognition. Excess credit
cannot silently create a negative invoice; it requires separately governed payout
or refund treatment. Payout entitlements do not imply a payment was sent.

## Validation

Run database suites serially against a dedicated synthetic test database.
The focused shared billing suite exercises both products, policy composition,
progressive and targeted rates, assignment splits, raw graphs, exact conversion,
quarantine/replay/conflicts/withdrawals, old-record drilldown, optional observations,
hourly completeness, immutable native records, invoice overlap, full credit,
repeated and zero-net corrections, stale/closed-period rejection, concurrent
retries and injected atomic rollback. Client reads are exercised with engine
execution disabled and no write-count changes. Scope and role failures are checked.

Browser acceptance: `scripts/billing_platform_ui_check.cjs` is read-only and covers
both products, three audiences, grouped client drilldowns, native invoice dates,
separate income, policy components, actual executions, correction review and
320/390px layouts. Existing household browser and HTTP acceptance remain required.
CI explicitly installs fixtures; page reads and activation never seed.

The reporting layer includes typed/signed native invoice and line projections,
correction direction checks, and `fct_shared_billing_accrual`, which reads exact
daily engine accrual nodes. Accruals and assessed invoices are separate grains.

## Retained-data migration

Do not migrate the currently served retained database. Capture its backup and
old-column fingerprints, restore into a separate retained volume, apply the five
additive migrations, then explicitly install the new synthetic examples. Verify
every prior value before and after seeding and check the original has not changed
before cutover. The prior API and volume remain available for rollback. Activation
only switches the verified frontend/API pair; it does not migrate or seed.

Local proof logs and actual deployment identities are in ignored `.runtime`.
Do not mistake this document or a source pin for a successful deployment receipt.
