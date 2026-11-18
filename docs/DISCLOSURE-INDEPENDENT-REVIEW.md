# Final integration closure — 16 November 2026

Root verified the final forward daily-fact→actual ADB-run link and original source
in the running browser. Final full regression:191 tests/12,139 assertions. The
frozen lineage/audience subset16tests/233assertions passed after the last proof
refinement. New HTTP acceptance102checks passed; reporting92steps, constructed
publicationproof10 and retained history16tables pass. A repeated comparison now
updates one current request while retaining old evidence. Finance visibly shows
its $200 remaining refund and the four supplied schedule amounts separately from
posted outcomes. Desktop/mobile/browser acceptance is complete; no known blocking
finding remains within the bounded milestone. See [final milestone](DISCLOSURE-MILESTONE.md)
for scope, evidence paths and production limits. This closure supplements the
independent Terra review below; it does not claim live integrations or capacity testing.

# Disclosure independent review

Status: **one final lineage check pending**. The backend is adding the exact forward link from an ordinary daily valuation fact to the ADB run that consumed it. The coordinator must verify that link after the fix; the results below do not claim it has passed.

## Review findings and resolutions

- Source selection now resolves known revisions before filtering dates, so a correction that moves an observation cannot resurrect its earlier value. Daily completeness uses an expected holdings roster; ADB selection uses effective membership evidence and scoped source families, including revisions from a new artifact. Unsupported membership changes are rejected rather than silently omitted.
- The shared `allocate_by` interpreter operation uses typed weight dependencies, deterministic largest-remainder allocation and signed conservation. Seeded stress checks covered 1,000 signed allocations, one-cent ties and invalid weights.
- The governance flow binds reviews to the comparison, policy, frozen inputs, terms and implementation. Stress checks covered later rejection, stale bindings, wrong policy/comparison pairing, idempotent and concurrent replay, partial-overlap rejection and atomic rollback. Publishing alone did not change billing; assignment and evaluation left the original native invoice intact and raised a correction requirement.
- Lifecycle evidence is retained through separately dated sources and deliveries. Credit, original receipt, refund application and loan cash remain distinct. Tests covered before-termination knowledge, delayed arrivals, forged or missing refund applications, independently accumulated credit and prepaid-cash caps, compensation classifications and unvalued equity. The duplicate custodian observation of the advisory charge is explicitly excluded from the $1,025 known-direct subtotal; the unobserved embedded fund cost remains unknown.
- Client and internal audience checks enforce case and role boundaries. Queries were tested with the interpreter disabled and for unchanged record counts. Detail requests invalidate stale responses on context or selection changes. Global pagination was traversed without omissions or duplicates.
- Reporting retains actual current publication proofs, including multiple publication streams and a published run followed by an identical unselected retry. Comparison classification can remain unknown for legacy records; retained and actual publication clocks are distinct. Component rows are marked nonadditive, and the reporting layer does not infer billing from a calculation.

## Executed evidence

- Final guarded full Ruby regression: **190 tests, 12,131 assertions**, no failures or errors. All reset-using tests ran against the disposable synthetic test database, serially. The retained main database was not reset.
- Seeded independent property suite: **3 tests, 9,746 assertions**, covering source revisions and completeness, allocation conservation and independent refund caps. It ran without database access.
- Reporting: **92 dbt steps** passed (23 models and 69 tests), plus **10 SQL publication-proof checks**. The analytics role could read reporting views but could not update source data.
- Read-only HTTP acceptance: **100 disclosure checks**, **66 disclosure-asset checks**, **50 audience checks**, **695 medallion checks**, and **21 product checks** passed. The reference suite passed **49 checks**. Before/after hashes of 16 retained tables were unchanged by bootstrap.
- Browser checks covered the Product $1,000 to $1,100 draft comparison, an unsupported-rate error shown in the editor, Finance's $200 refund balance and four supplied schedule amounts, and Finance and RIA client layouts at 390 pixels without horizontal overflow. A lineage leaf exposed its raw source but did not yet show the forward daily-fact-to-ADB-run link; that is the outstanding check above.

Detailed command output is retained under `artifacts/disclosure/`, including `review-tests.txt`, `full-regression.txt`, `dbt.txt`, `analytics-proof.json`, `disclosure-http.json` and `retained-history.json`. The prototype uses fictional data and mocked provider/accounting interactions; these checks do not establish actual Savvy contractual or accounting correctness.
