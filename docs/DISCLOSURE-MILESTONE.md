# Disclosure-informed billing milestone

Completed 16 November 2026 in the isolated `codex/medallion-billing` worktree.
Astra revised the [implementation plan](DISCLOSURE-IMPLEMENTATION-PLAN.md);
Terra implemented backend/UI and independently reviewed/stress-tested the work.
Root coordinated integration, retained-data checks, reporting, build and browser
acceptance. Current local preview: **http://127.0.0.1:3104/**.

## Delivered behavior

The existing three-audience shell remains. Client overview stays compact and
opens the February household statement on demand. The statement uses traditional
invoice rows and evidenced issue/due/service dates. Product explains evidence →
eligible value → terms → invoice and supports ordinary percent/dollar policy
editing, frozen impact comparison, exact Legal/Finance reviews, publication and
explicit dated assignment. Finance separates commercial credit/refund evidence
from supplied recognition treatment and independently reported postings. Its
outstanding refund balance and readable schedule amounts are visible.

The new namespace is `disclosure_2027`; September and existing Finance samples
remain separate. Real ADV/CRS view/download/source links remain; there is no
sample agreement PDF, and the actual agreement viewer remains unpopulated.

| Retained proof | Exact result |
| --- | --- |
| Reported / excluded / eligible assets | $1,250,000 / $250,000 / $1,000,000, valuation January 31 |
| Original monthly advisory invoice | $1,000, native lines/obligations $600 and $400 |
| Mid-month termination | $500 retained service; separate $500 credit, allocated $300/$200 |
| Independently evidenced refund | $300 confirmed; $200 still outstanding; original receipt/invoice retained |
| Daily-average comparison | $1,100, allocated $650/$450 from all expected member/day observations |
| Monthly minimum / quarterly / onboarding | $1,250 / $3,000 / $500, separate comparisons |
| Net-worth / fixed partial service / hourly / elected service | $500 / $200 / $700 / $100, separate comparisons |
| Compensation types | $5,000 salary, $1,000 bonus, $12,000 loan principal/independent advance, $1,000 forgiveness, $11,000 remaining principal; 100 equity units with unknown value |
| Known direct charges | $1,025; duplicate $1,000 custodian observation excluded; embedded cost unknown |
| Supplied recognition | $500 reported recognized; scheduled credit correction remains unposted |
| Browser draft | 1.2% → 1.32%, $1,000 → $1,100 on frozen facts; unassigned, unpublished and awaiting reviews |

All commercial arithmetic uses Economics::Engine. The generic `allocate_by`
operator adds exact evidenced proportional allocation to the same interpreter;
there is no second calculator in the UI, read projections or dbt. Supported rates,
amounts, mechanisms and cadence are API policy data. Inputs and policies retain
exact scope, revision, effective and knowledge clocks. Source/membership revisions
are selected as-known; missing or incompatible coverage blocks affected results.

Commercial credit, receipt, refund application, loan cash, entitlements, outside
costs and accounting observations are separate records. Native positive invoice
constraints were retained. No new payment execution, accounting inference or
contract authority was introduced. Recomparison leaves one current request per
policy and retains earlier comparison evidence in lineage.

Internal record navigation reaches actual consumed facts and raw arrivals.
Execution edges require exact scoped identity/revision/hash, actual interpreter
binding and matching result references; unused inputs are not claimed executions.
Reporting preserves explicit comparison flags, unknown legacy classifications,
nonadditive components and exact publication proofs across streams. A later
unpublished retry cannot hide the currently published result. Retained and actual
publication clocks are distinguished; billing is not inferred from a run.

## Validation

| Gate | Final result / evidence |
| --- | --- |
| Full guarded Ruby regression | **191 tests / 12,139 assertions**, no failures/errors/skips; artifacts/disclosure/full-regression.txt |
| Final frozen lineage/audience subset | **16 tests / 233 assertions**, no failures/errors/skips; final-lineage-tests.txt |
| Reference suite | **49 tests pass**; reference-tests.txt |
| Reporting | **23 models / 69 data tests, 92 passing steps**; dbt.txt; analytics source UPDATE privilege false |
| Constructed publication-proof regression | **10 checks**, no DB writes; analytics-proof.json |
| New real HTTP acceptance | **102 read-only checks**; disclosure-http.json |
| Retained HTTP/asset acceptance | **66 disclosure/statement + 50 audience + 695 medallion + 21 product checks** |
| Frontend | Optimized production build and TypeScript pass; next-build.txt |
| Rails loading | Eager loading passes; eager-load.txt |
| Retained history | All pre-existing row hashes preserved across **16 tables**; retained-history.json |
| Independent review | [Findings and corrections](DISCLOSURE-INDEPENDENT-REVIEW.md), including temporal, scope, cash, review binding, concurrent retries and reporting regressions |

Counts above are separate gates, not additive test-case counts. The full Ruby
suite includes the disclosure stress/property tests. The final focused subset
was rerun after the last lineage refinement. Existing dependency resource/string
freezing warnings remain; they did not cause failures.

Browser acceptance used the running full application: compact overview/drilldown,
traditional invoice, valuation/exclusion explanations, readable parties, Product
flow, real API draft/comparison, modal validation error, Finance refund balance,
supplied schedule and missing posting, scoped RIA cost, ordinary daily record →
actual ADB run → original source, and real CRS page navigation. At 390px the
Finance and client cost views had document width 390px; viewport override was
reset. Browser warning/error logs were empty. Captures are under
`artifacts/disclosure`, including `finance-summary.jpg`, `finance-schedule-mobile.jpg`
and `ria-cost-mobile.jpg`. The browser was retained on Internal Finance.

## Preview and remaining limits

LaunchAgent `com.beanlabs.savvy-clarity.preview` serves port 3104 with
`SAVVY_BUILD_DIRECTORY=evidence-final` and `.next-evidence-final`. Port 3103/.next
remained available throughout development. Builds alternated inactive named slots;
never rebuild an active directory. The plist is in the user's LaunchAgents, with
workspace copy/logs in `.runtime`; the app remains independent of the coding
terminal. API3102/database55438 remain loopback-only. No hosted deployment,
GitHub push, release, new infrastructure spend, retained reset or provider write.

This remains a bounded synthetic prototype: one defined household roster, dated
fixture periods and a small RIA cost observation. Quarterly replacement of an
overlapping monthly schedule, arbitrary membership administration, unrestricted
formula/contract editing and general source-ingest UI are deferred. Onboarding
and arrears are comparison records. Real authentication, payment execution,
payroll/equity/loan servicing and accounting policy selection are not supplied.
Campfire and CLM remain mocked; the advisor parent–child hierarchy remains deferred.
See [API contract](DISCLOSURE-API-CONTRACT.md) and
[backend scope/limits](DISCLOSURE-BACKEND-NOTES.md).
