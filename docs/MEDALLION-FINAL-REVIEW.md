# Final architecture review — 15 November 2026

GPT-6 Astra reviewed the complete medallion plan, sample walkthrough and current
prototype before implementation. No unresolved business decision blocks this
bounded milestone. This review is an implementation contract, not a claim that
the checks below have passed. Validation results belong in the milestone report.

## Required boundaries

- One pure deterministic policy interpreter binds and evaluates both products.
  All legacy evaluation callers translate into it or serve retained results.
  Legacy rounding remains explicit policy semantics, not a second calculator.
- The API owns approved policy lifecycle, dated assignments, exact comparison
  and mock document reviews. Changing supported formulas does not require code.
- Append-only scoped evidence retains raw bytes, source revisions, requests,
  approvals, facts, manifests, results, applications and statement versions.
  JSON bodies do not replace scoped identity/revision/status or shared rate rows.
- Independent RIA identity is denied every legacy internal query and command
  by default. Choosing an experience cannot authorize access to raw/internal or
  another party's data. Identity remains a local simulation.
- Evaluation proposes economics but cannot issue documents, consume a coverage
  right, apply a payment or execute a provider operation.
- One-time events follow the same engine. Compensation entitlement, payout
  instruction, reported payment and allocated payment are separate meanings.
- October statements reference the sealed September balance and linked changes.
  They do not rebook September compensation/advance on each refresh. A bonus
  inside the floor produces +$100 bonus and −$100 guarantee adjustment.
- Source event identity is unique independently of actor/command idempotency.
  Shared capacity and reversals are scope-locked and conserved under concurrency.
- API approval clocks and posting authority come from the server. Historical
  sample clocks are confined to the internal fixture loader. Economic dates
  cannot fabricate earlier knowledge or reopen sealed periods.
- dbt selects retained versions and publishes read-only summaries; it does not
  calculate commercial prices or originate billing objects.
- Campfire and CLM remain mocks. No live provider, payment, signature, new paid
  service or hosted-state change is part of this implementation.

## Acceptance emphasis

Same frozen October 2 inputs must support API-only changes to rates, tiers,
formula structure, rebates and guarantees without a build change. Preserve
current November results and every original record. Show pending/missing evidence
without confirmed dependent totals. Prove exact rounding and conserved allocation,
zero-net bonus adjustments, payment/reversal behavior, duplicate replay, concurrent
capacity claims, sealed-history preservation, role boundaries, schema recovery
and the two external product journeys on desktop and mobile.

Implementation uses the separate `codex/medallion-billing` worktree and the
`savvy-medallion` container project/volume. The original hosted app and retained
database are outside this test boundary.
