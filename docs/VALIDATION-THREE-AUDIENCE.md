# Three-audience validation

15 November 2026. Checks use the isolated `savvy-medallion` stack. Destructive
tests run sequentially against the guarded `advisor_economics_synthetic_test`
database. The retained database is never reset.

| Check | Result | Evidence |
|---|---|---|
| Full Ruby regression | 159 tests, 2,011 assertions; no failures/errors/skips | artifacts/medallion/three-audience-regression.txt |
| Reference regression | 49 tests pass | artifacts/medallion/three-audience-python.txt |
| Reporting | 23 models and 66 tests; 89 passing steps; analytics cannot update source | artifacts/medallion/three-audience-dbt.txt |
| Three-audience HTTP and preview proxy | 50 non-mutating checks | artifacts/medallion/three-audience-http.json |
| Existing medallion HTTP | 695 read-only assertions pass | artifacts/medallion/http.json |
| Retained workspace HTTP | 21 read-only checks pass | artifacts/workspaces/http.json |
| Rails load | Eager loading succeeds | executed after the full regression |
| Retained history | Every prior row fingerprint preserved across 14 source tables | artifacts/medallion/three-audience-history.json |
| Policy/publication integration | API save, compare, review and publish succeeds with client read publications present | artifacts/medallion/three-audience-policy-lifecycle.txt |

The complete Ruby run includes independent audience/Finance and read-model stress
tests. They exercise scope/role denial, exact-cent partial and multiple matches,
replay/idempotency conflicts, reversal conservation, posting periods, supplied
acknowledgment clocks, recognition invariance and source/package/posting binding.
Published reads are tested with full-workspace loading and engine evaluation
disabled, and verified not to create evidence. Record, transition, statement and
observation pagination are traversed without omissions or duplicates.

The independent review found and verified fixes for stale detail responses,
hardcoded client projections, missing native clocks, missing statement basis,
non-navigable lineage, truncated observations, advisor Finance response mismatch,
missing posting-period inputs, unlinked accounting confirmation and recognition
timing/source evidence. See [the final review](THREE-AUDIENCE-FINAL-REVIEW.md) and
[the stress report](THREE-AUDIENCE-STRESS-REVIEW.md).

## Browser acceptance and build

The optimized Next.js build and TypeScript pass. The running local app was used to
verify shared broker navigation, the 30-account RIA roster including a non-featured
account, complete 30-day observation paging, statement agreement/basis drilldown,
and the scoped Finance cash/recognition views.

A $1 synthetic allocation from the second payment to the second invoice was
created through the UI and reversed through its linked action. The residual
returned to $100, and the original $600 application/$600 AR/$400 recognition/$800
deferred evidence remained unchanged. Those acceptance records remain in history.

A draft changed the standard advisor share from 80% to 82% through the API and
compared frozen facts. Share compensation increased from $3,135 to $3,181 while
the guarantee adjustment fell from $165 to $119; total compensation stayed
$3,300 and remaining payable stayed $2,300. The draft/comparison remain reviewable;
they were not published or assigned.

The final optimized build is in `artifacts/medallion/three-audience-next-build.txt`.
Desktop 1280×900 and mobile 390×844 were exercised; the mobile broker overview,
lineage and Finance views had document width 390px with no page overflow. Navigating
run → exact selected fact, request-based comparison, supplied recognition schedule
and paged daily observations succeeded. Browser error/warning logs were empty.
The temporary viewport was reset and the preview tab retained on the broker
overview. The existing LaunchAgent is running independently of the coding terminal.
This document does not claim production authentication,
real accounting integrations, capacity benchmarking or exact-commit remote CI.

## Reproduce

Use `COMPOSE_FILE=compose.medallion.yaml COMPOSE_PROJECT_NAME=savvy-medallion`
for all container checks. Prepare the guarded test DB, then run all Ruby tests
sequentially as in `scripts/check.sh`. Run `scripts/analytics.sh` with
`SAVVY_ANALYTICS_PORT=55438`. Run `python3 scripts/three_audience_http_check.py`
against the populated API and running preview; it sends no mutations.

On a freshly populated local stack, evaluate each baseline using the documented
medallion API before publishing its audience projection. Existing retained runs
can be published without reassessment using
`AudienceReadModel.new(Workbench.new).refresh!(case_id)` from a local Rails runner.
Initialize the isolated Finance fixture with `FINANCE_BOOTSTRAP` as the simulated
operator. Repeated setup preserves existing identities and source bytes.

Stop only `com.beanlabs.savvy-medallion.preview` before building Next.js, then
bootstrap the same LaunchAgent again. Leave it running at port 3103. Do not build
against a live `.next` directory or start a competing preview process.
