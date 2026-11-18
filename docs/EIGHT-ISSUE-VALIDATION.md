# Eight-issue validation and review

18 November 2026. Astra planned the changes; three Terra lanes implemented,
cross-reviewed and added independent stress coverage. Root serialized database
tests on the separate `savvy-eight-validation` cluster. Retained preview data was
backed up and fingerprinted before freezing its baseline API; no schema change,
reset or retained seed is required.

| Finding | Fix and evidence |
|---|---|
| Same-total allocation changes | Native invoice, account-bound lines, currency, parties, dates and output contracts are checked. Independent stress shifts allocations by one cent through $399.99, mutates identity, duplicates/removes outputs and exercises nonallocated alternatives. Originals remain retained. |
| Future policy assignment | Assignment must fit policy validity at assignment and evaluation. Tests cover future policies, boundaries, null ends and retained invalid assignment evidence. Hypothetical comparisons remain possible. |
| Editable hosted API | Source-only image from exact committed archive; no source mount or reloader; read-only filesystem, stdout logs and temporary space. Health exposes source identity. Candidate preflight verifies image/configuration. |
| Missing Finance reviews | Finance receives the same comparison identity/amounts and Finance-only decisions. Changed implementation bindings are explicitly stale and blocked until Product compares again. |
| Missing Finance cash | Original receipt, outbound refund and confirmed loan advance have separate evidence. Approved credit and confirmed/matching cash sources are required. Negative tests exclude pending receipts/refunds/credits and mismatched loan terms. Entitlements and supplied recognition stay separate. |
| Optional end date drift | JSON contracts require the effective_to key. Saved policy can be open-ended; assignment requires a valid finite date. Negative contract checks cover omitted, null and malformed dates. |
| Unused/unbounded reads | Household navigation skips baseline loads. Medallion histories and disclosure request pages are limited in SQL, selected/applied policy remains available, financial context stays stable across request pages. Independent presenter reads use repeatable-read without the entity write lock. |
| Unsafe fixed build directory | Explicit inactive candidate slots, ownership guards, shared operation lock, exact source/asset/image proof and both exact-commit CI gates. Offline stress rejects tamper during validation, source drift, active slots and failed readiness; rollback restores the prior pair/receipt even if the remote rollback fails. |

## Observed local checks before candidate publication

- Ruby/PostgreSQL regression: 208 tests, 12,294 assertions, zero failures/errors/skips.
- Python reference and deployment tests: 63 pass.
- Reporting: 23 models and 69 data tests; all 92 steps pass on disposable data.
- TypeScript and Rails eager loading pass.

Runtime/browser acceptance, exact-commit CI, public document hashes and retained
fingerprint comparison are recorded in `.runtime/eight-fixes/results` and the
activation/publication receipts. Receipts, not this source document, establish
which candidate is actually served. No tests send real provider writes.

## Review corrections and limits

Cross-review caught stale mocks, a historical assignment fixture conflict,
unconfirmed source evidence, request histories sliced after loading, and an
artifact mutation window during validation and runtime page-cache writes. These were corrected and checked. Next runtime cache remains in memory; served build files stay covered by the artifact hash.

This is a bounded synthetic prototype. The existing RIA cost-only disclosure,
parent-child account modeling and production identity remain outside this fix.
The Product treatment catalogue retains the selected treatment plus at most 100
alternatives and visibly reports truncation; it is not an unbounded editor.
Full selected-run economic evidence is intentionally retained for calculations;
paging histories must never change a statement. These tests establish bounded
correctness/races, not production throughput capacity. Campfire and CLM stay
mocked, and one Economics::Engine remains the sole evaluator.
