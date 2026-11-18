# Four-capability completion contract

The earlier milestone completed a shared calculation-to-invoice foundation. It did
not close the four requested priorities. This is the completion checklist for the
synthetic prototype, before unrelated scope is reopened.

1. Both products: native billing/corrections, payment applications and refunds,
   outstanding/credit balances, governed earnings/payable and confirmed payout
   visibility, and versioned mock accounting packages/outcomes share the same
   scoped workspace. Legacy examples are retained, not substituted for these paths.
2. Commercial optionality: API-only composed and primitive policies; named proofs
   of advance/arrears valuation, membership proration, termination/unearned credit,
   excess credit and subsequent recovery. Earnings use the same engine. Common
   policy controls expose timing, valuation, proration and floors/caps; graph JSON
   remains an advanced capability, not the only path to the named examples.
3. General pipeline: database-backed scheduled work, lease/claim, bounded retries,
   retained attempt receipts, quarantine/manual retry, batch evaluation and
   crash/restart/concurrent-worker verification. Existing local PostgreSQL and a
   worker process only. No new spend or live provider connector.
4. Corrections: native signed claim conservation, repeated and standalone credits,
   scoped confirmed-cash applications/reversal, credit balances, refund handoff and
   independent refund evidence, plus versioned mocked accounting replacement/
   reversal evidence. No payment request implies money moved; no receipt implies
   recognized revenue. Originals remain immutable.

Acceptance uses both existing cases and reusable synthetic cases. Tests must prove
money conservation, original preservation, stale/revised evidence rejection,
independent role checks, repeated/concurrent retries, worker restart recovery and
representative paged-book processing. No production scale guarantee is inferred.
Campfire and CLM stay mocked. Production identity, live connections, hierarchy and
MCP/WebMCP remain deferred.

The internal architecture document must then match actual service/class, storage,
worker, policy, billing, cash and accounting responsibilities. Diagram claims link
to exact committed code and executed sample results. Public documentation, API,
preview and final report must identify the same tested candidate. Any uncompleted
acceptance item remains explicitly open; do not call all four complete by narrowing
their meaning to the invoice path.

Keep the current candidate-b/API3109/database55440 preview serving. Use disposable
validation at 55439 without starting its API on the occupied port. Rehearse schema
changes on a fresh clone of the active retained database, compare every prior row's
old columns before/after fixture installation, and promote inactive candidate-a /
API3108 only after exact-commit CI and recorded acceptance. Preserve the current
pair and its database for rollback. Reads and activation never seed or price.
