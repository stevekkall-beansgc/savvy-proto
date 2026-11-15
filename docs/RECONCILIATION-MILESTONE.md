# Reconciliation evidence and frozen review milestone

13 November 2026. Astra planned the milestone; three Terra agents implemented the
backend, interface and reporting, reviewed other lanes, and stress-tested the
integrated result. The root session resolved findings, verified the browser flow
and rehearsed recovery. Read [the plan](CTO-READINESS-PLAN.md) and
[validation](VALIDATION-CTO-RECONCILIATION.md).

## Working product

The new Savvy-branded Reconciliation view separates independently supplied invoice
applications, entity-level bank batches and unknown accounting evidence. Finance
selects invoices and verified customer receipts, enters exact dollar amounts and
records a reason/business date. Bank receipts are selected explicitly; gross and
net use exact integer cents. No provider call, cash movement or posting occurs.

Applications conserve each invoice and receipt separately from operational cash
matching. A whole receipt can belong to only one active bank batch. Bank gross
must equal both attributed receipts and fees plus net; net/fees are not allocated
to customers or advisors. Full-original reversals append evidence once.

Source revision, customer, amount and currency are captured with the evidence.
A later receipt correction preserves independent applications and batches, while
surfacing conflicts rather than silently cancelling those facts. Unknown invoice
applications make aggregate applied/open balances unknown. A full reversal can
establish an evidenced zero. Derived invoice open is not confirmed accounting AR.

A saved review compares the current stable evidence manifest under the same
database scope lock as writes, then freezes the review content. Later evidence
appears separately. Current reads are also locked, preventing a mixed manifest
and balance view. Saved reviews are read-only; entity-level reconciliation is
excluded from the simulated advisor role.

This is a reconciliation review snapshot, not an accounting close or a period
lock. The manifest conservatively includes relevant evidence kinds across the
entity; changes in another period can invalidate a pending freeze or appear in
the late-evidence overlay. Invoices enter the requested half-open period by their
charge service-period start; bank batches use their business date. Different
populations are not proven reconciled merely because totals happen to equal.

## Retained local examples

Earlier policy versions, six projections, Cedar's receipt revision/reversal,
operational matching history and all five entitlement entries remain unchanged.
The current projection remains $1,770 earned / $1,000 projected coverage / $770
incremental cash, with a separate provisional $30 guarantee.

Browser verification added Maple's invoice link, an independent $1,000 application
and a $1,000 gross / $10 fee / $990 net bank batch. It saved review
`close-bad7a0de-9291-4b16-bc4a-95a69e21aaa8`, then reversed the application. Current
Maple application is evidenced $0 with $1,000 derived open invoice; the saved review
still shows its original $1,000 application and separate late reversal. Cedar's
application remains unknown, so aggregate application/open amounts remain unknown.
The bank batch remains independently evidenced. No recognition or accounting AR
was inferred. These browser entries use the initial form's November 1 business
date; the final form defaults to the demo's November 13 date.

The canonical $1,600 gross / $30 fee / $1,570 net example is exercised separately
on disposable fixtures by `scripts/reconciliation-check.sh`. It does not reset
retained demo history.

## Portable workflow and next gates

Fresh setup seeds the original baseline, not the retained local Docker volume.
In the simulated Finance role, use Collections to link invoice evidence, then
Reconciliation to record independent applications, a bank batch and a review.
The portable archive includes source, screenshots and JSON evidence, not database
backups or a volume. Existing local history stays in the named volume.

Remaining production gates are in the CTO plan: real identity and segregation of
duties, actual accounting/provider semantics, genuine period locks and correction
policy, database privilege/audit enforcement, CI, monitoring, workload testing and
production recovery. The separate offline Ruby Campfire accounting lifecycle is
still future work. Publication stays paused.
