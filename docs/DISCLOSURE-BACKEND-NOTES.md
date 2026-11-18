# Disclosure backend scope and limits

This document describes the bounded synthetic disclosure workspace; it is not a
statement of actual Savvy contract terms or accounting policy.

## Implemented

- `disclosureWorkspace` is an audience- and case-scoped read projection. Its
  selected commercial result and later lifecycle observations carry distinct
  knowledge cutoffs. `disclosureCommand` uses the existing locked, idempotent
  operation lane and exposes bootstrap, policy draft, frozen-input comparison,
  Legal and Finance review, publication, dated assignment and evaluation.
  Exact-interval assignment replacement requires an explicit superseded ID;
  partial overlaps are rejected. A changed assessment flags the original bill
  for correction without reissuing or changing it.
- The February Alder group uses retained synthetic terms, a dated household roster,
  January valuations and the shared engine. One positive native invoice has two
  positive native lines and obligations, with explicit run/output binding facts.
  Selected evidence, source revisions, inclusion flags and membership references
  are frozen in each run. Later known corrections are selected on a subsequent
  evaluation; they do not mutate older results or the invoice.
- Named engine-evaluated comparison records cover average daily balance, monthly
  minimum, quarterly, onboarding, arrears, net worth, fixed, hourly and optional
  service. The daily comparison requires every declared member/holding/day and
  does not forward-fill. Exact timesheet and service-day quantities are retained
  evidence. Quarterly uses separately dated December valuation and quarterly
  fictional terms, with January–April service; onboarding uses its partial
  February service interval. Comparisons are not current bills or cash execution.
- The same interpreter computes the termination credit and per-line allocation,
  retained service, refund residual, compensation components, loan balance and
  known direct cost subtotal. Independently retained receipt, refund and loan
  cash observations remain separate from those calculations. Refund validation
  checks scope, identities, links and the remaining credit and original prepaid
  cash across applications. Equity units have no invented value; the embedded
  fund-cost amount remains unknown. The independently observed duplicate of the
  advisory charge is excluded from the direct-cost subtotal.
- Fictional recognition input, supplied treatment/schedule and mock reported
  posting are retained separately. A missing correction posting stays missing;
  changed commercial terms require a new accounting correction rather than
  silently reusing the old treatment. A separate RIA observed-cost fact does
  not change the RIA product's existing economics.
- The engine's `allocate_by` primitive uses exact node-supplied weights and the
  shared largest-remainder algorithm. It rejects incompatible units/bases,
  negative weights and zero total, preserves sign, and breaks ties by stable
  recipient ID. The full disclosure implementation fingerprint includes the
  engine and the source, policy, lifecycle, refund, workbench and read adapters.

## Bounded and deferred

The fixtures cover one February household and a small RIA cost observation.
The expected roster and eligible ADB holding scope are explicitly bounded to
these fixture accounts; a changed ADB roster that this graph cannot represent is
rejected instead of silently reused. The policy assignment path currently
accepts the matching February monthly fixture interval or the January–April
quarterly fixture interval. A quarterly assignment overlapping the retained
February assignment is rejected; replacing a broader schedule would require an
explicit, separately reviewed schedule change. Onboarding and arrears are
comparison records, not independently issued bills. API policy fields cover the
named bounded mechanisms and reject unsupported combinations; they are not an
unrestricted graph editor or general contract-authoring system.

Termination, refund, compensation, timesheet, valuation and accounting examples
are authored fixture ingests. There is no general source-import editor, payment
initiation, payroll execution, loan servicing, equity valuation or tax decision.
Receipt and refund records are synthetic evidence and their local application is
not an accounting posting. Campfire and CLM are mocked. There is no actual
agreement document, signature or authority to infer contractual terms from ADV
or CRS disclosures. The advisor parent–child hierarchy remains deferred.

The relevant tests and retained-preview verification are coordinated separately
by the root workstream; this note does not assert that they passed.
