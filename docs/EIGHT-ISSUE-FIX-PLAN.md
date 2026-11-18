# Eight-issue corrective milestone

18 November 2026. The owner authorized Astra planning followed by Terra
implementation, independent review and stress testing. The eight findings are
from the skeptical review of source checkpoint `25d4d5b`.

## Invariants

- Economics::Engine remains the sole billing evaluator. Supported commercial
  changes remain versioned policy data through the API.
- Savvy owns obligations, invoices and lines. Original monetary records,
  comparison/review history and source evidence remain retained.
- Campfire and CLM remain mocked. This milestone does not introduce production
  identity, MCP/WebMCP, live providers or parent-child account administration.
- Retained preview data is never seeded, reset or migrated during activation.
  The old preview stays available while candidate tests use disposable data.

## Implementation lanes

| Lane | Findings | Required behavior |
|---|---|---|
| Terra A | 1, 2, 6 | Compare scoped native invoice and bound line economics, flag equal-total reallocations, reject malformed output contracts, preserve valid nonallocated treatments. Enforce reviewed policy validity on assignment and evaluation. Require effective_to in published input contracts, nullable on save and finite on assignment. |
| Terra B | 4, 5, 7 | Finance sees the same pending comparison and its own review controls, confirmed inbound receipt/refund/loan cash with evidence, and separate entitlements and accounting facts. Remove unused household/other-view baseline loads. Bound internal histories in SQL, preserve selected policy and full economic calculations, use a consistent independent read snapshot without taking the write lock. |
| Terra C | 3, 8 | Source-immutable, no-reload API image from committed runtime files. Explicit inactive frontend slots, shared build/activation lock, artifact and API-image proof, staged pair validation, safe promotion and rollback with Cloudflare Access preserved. |
| Root | Integration | Freeze baseline before edits, run all database suites serially on a disposable project, build/stage final source, regenerate pinned public documentation, require exact-commit CI and perform the owned cutover. |

Each Terra lane reviews another lane. New stress cases are separate from the
implementation's existing positive examples. Root is the sole database-test
runner to avoid concurrent reset races.

## Acceptance and stress cases

1. A $1,000 result whose account lines move from $600/$400 to $700/$300 requires
   correction. Identical economics and reordered details remain unchanged.
   One-cent changes, duplicates, missing monetary identity, malformed units,
   currencies, classes and intervals fail closed. Supported hourly/fixed and
   other nonallocated treatments remain evaluable and cannot silently reuse the
   original account allocation. No original invoice, line or obligation changes.
2. A February 2028 policy cannot be assigned to February 2027. Test exact
   boundaries, one-day overhang, open-ended policy validity, null assignment ends,
   historical invalid assignments, repeated intent and supersession. Hypothetical
   comparisons remain possible. Rejection commits no new assignment/publication.
3. Finance and Product see identical comparison identities and amounts. Finance
   receives Finance review actions, clients receive no internal queue and stale
   implementation bindings require recompare. The retained comparison is not
   rehashed, approved or replaced automatically.
4. Confirmed receipt $1,000, refund $300 and loan advance $12,000 are separate cash
   records with parties and source proof. Credit $500, residual $200, salary/bonus
   entitlements and supplied recognition remain distinct. Unconfirmed/mismatched
   payment evidence is never shown as confirmed cash.
5. Page through a large disposable history with bounded SQL materialization.
   Preserve selected historical run/current policy and statement balance across
   pages. A reader does not take the entity write lock; independent multi-query
   reads use a repeatable snapshot, while publication refresh reuses its existing
   locked write transaction. Default household navigation makes no unused baseline
   workspace requests.
6. Omitted, null, malformed and valid effective_to inputs agree between the
   published schema and command handler. Regenerate the OpenAPI and SDL reference.
7. Reject active/unknown/aliased slots, concurrent activations, tampered served
   assets, wrong source/image identities, writable or source-mounted API
   containers, stale CI and failed readiness. Candidate frontend/API identities
   must match. Rollback restores the prior pair, route and receipt.

## Runtime and validation isolation

The root first captures all retained public-table fingerprints and a logical
backup, freezes checkpoint `25d4d5b` in a read-only source image, and removes the
served API's source mount. Existing loopback API 3102 and preview 3104 remain the
rollback pair. A candidate uses API 3108/3109 and frontend staging 3106; the
promoted frontend remains 3104. Legacy preview 3103 is reserved.

Full regression runs in `savvy-eight-validation`, its own PostgreSQL volume and
network, not either retained application database. Root confirms DB/container
identity before tests. Candidate read-only HTTP checks explicitly name the
candidate origin. All write/review/reversal/browser stress is restricted to the
disposable database. No retained migration or reset is required.

Commit reviewed runtime source and SDL before regenerating source-pinned
architecture/API artifacts. Build the final frontend in a verified inactive slot
and the final API from the same committed source. Complete exact-commit
Prototype and Architecture checks before promotion; verify retained fingerprints,
public documentation hashes, Access protection and the final browser flow.
