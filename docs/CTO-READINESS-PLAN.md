# CTO readiness plan

13 November 2026. The owner requested Astra planning followed by a Terra team for
implementation, independent review and stress testing. Astra reviewed the handoff,
plans, working services and tests before recommending this bounded milestone.

## Product outcome

Make the synthetic financial explanation coherent from approved charge through
invoice application and bank gross/fee/net evidence, with a frozen review that
survives later corrections. Preserve all existing projection, policy and settlement
history. Keep Savvy's official public-site branding.

Invoice links and internal cash matches currently exist, but neither proves an
invoice application or a bank settlement. `Workbench#collections` explicitly left
these axes unknown. This milestone supplies independent synthetic evidence for
those facts, without creating another receipt or inferring advisor compensation,
accounting AR, recognized revenue or a payment.

## Quality bar

1. Exact integer money and separate populations: invoice balances at invoice grain,
   bank fees/net at batch grain, and customer receipts counted once. Missing evidence
   stays unknown. Contradictions produce visible exceptions with an owner and next action.
2. Writes conserve each eligible receipt, invoice and bank membership under the
   existing database scope lock. Retried commands return their original result;
   changed requests using an old key fail. Reversals append evidence once.
3. A reconciliation review freezes a consistent manifest and view after an optimistic
   hash check. Later evidence remains visible separately and never rewrites the
   stored review. This is a review close, not an accounting period lock.
4. Finance controls are distinct from read-only simulated roles. Entity-level bank
   information is excluded from the advisor view. Role simulation remains visibly
   separate from actual authentication.
5. Domain, HTTP, reporting and browser checks agree. Independent concurrency,
   rollback, malformed-input, conflict and recovery checks have recorded outcomes.

## Team execution

The shared interface and invariants are in
[CTO-RECONCILIATION-CONTRACT.md](CTO-RECONCILIATION-CONTRACT.md).

| Lane | Owner | Deliverable |
|---|---|---|
| Architecture and prioritization | Astra | Evidence-based scope and acceptance/stress recommendations |
| Financial domain and API | Terra backend | Independent invoice/bank evidence, reversals, frozen reviews and tests |
| Product experience | Terra interface | Savvy-branded reconciliation view, Finance forms, frozen/current review |
| Reporting and adversarial verification | Terra reporting/stress | dbt marts/checks, concurrent/failure tests and independent backend review |
| Integration and recovery | Root | Backups, restore rehearsal, cross-lane review resolution, browser verification and portable handoff |

Each implementer reviews another lane after integration. Shared test-database
resets run sequentially. Main demo history is preserved; destructive stress cases
use the test database or disposable databases. The source baseline and a logical
database dump were preserved before team edits.

## Canonical proof

On isolated synthetic fixtures, two $1,000 invoices with $600 and $1,000 receipts
produce $1,600 independently evidenced application and $400 derived open invoice.
A bank batch proves $1,600 gross = $30 fees + $1,570 net. Net remains at entity/batch
grain. A later correction changes the current view and appears beside a frozen
review while its stored content/hash remains unchanged.

Independently test simultaneous claims, same-key retries and conflicts, duplicate
batch membership, receipt reversal with independent application/bank evidence,
close/write races, injected rollback, guessed scope/role access, unsupported source
states and exact-money input failures. Restore a consistent logical snapshot into
a uniquely named disposable database and compare all public-table fingerprints;
never restore over the original database.

## Production gates beyond this milestone

The product remains a local synthetic prototype. A production proposal still needs
real identity/access and segregation of duties, approved contract/accounting policy,
verified provider semantics and data mapping, accounting close/correction policy,
database privileges and audit/retention enforcement, CI and deployment controls,
observability, realistic workload testing and a production recovery strategy.

The generic JSONB evidence store and entity-wide write lock are deliberate local
tradeoffs. No tamper-proof ledger, full S01–S30 completion, Campfire integration or
production readiness is claimed. A separate offline Ruby accounting lifecycle is a
later milestone. Publication remains paused.
