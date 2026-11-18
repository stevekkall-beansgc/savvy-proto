# Three-audience independent stress review

Integrated completion: [final validation](VALIDATION-THREE-AUDIENCE.md) records
the full regression, reporting, browser and running-preview checks. Draft handoff
items below are retained as review history, not current unresolved blockers.

15 November 2026. Acceptance is against `THREE-AUDIENCE-PLAN.md`; all examples are fictional. This is a working review, not evidence that checks have passed.

## Risk-based acceptance

- Cash matching must require the same tenant, legal entity, currency, counterparty and applicable source identity; equal amounts alone cannot authorize an association. Independent observations of one movement must not add to cash twice. Bound allocations to available cash and invoice balances, preserve cents across partial and multiple allocations and reversals, and reject changed payload reuse under an idempotency key. A local association cannot assert an accounting application, posted journal or executed transfer.
- Recognition must distinguish missing evidence from zero; proposed, scheduled and source-reported outcomes from independently posted accounting outcomes. An input package binds the exact commercial line revisions, amounts, entity/currency and treatment. A returned schedule bound to a different package or treatment must not be attributed to it. Supersession, credits and reversals retain prior evidence. Cash matching cannot change recognition under unchanged treatment.
- Replay, repeated seed and refresh must not duplicate a movement, commercial result, invoice, application or posting. Estimates and replacements do not add to their superseded versions.
- Internal record search must traverse every page without duplicates or omissions and retrieve a non-featured record with its actual provenance, including exceptional states. Client identities must not access raw internal records or internal writes, including by direct API invocation or by changing an identifier.
- Both product experiences must use the same billing interpreter and scoped API. Mock provider evidence must be identified as mock, and architectural expectations must not be presented as observed execution.

## Validation constraints

The existing reconciliation and Rails suites clear the synthetic test database. Run them only with explicit coordination, never concurrently, and verify the disposable database guard first. Do not reset retained data or restart the owner's preview. A read-only HTTP check can inspect the running API if its current version is known; a running preview cannot prove unbuilt local changes.

## Results

Pending implementation and coordinated validation. No destructive suite has been run by this reviewer.

## Initial implementation review

The first read-model draft builds the summary with `MedallionWorkbench#view` before removing its detail, and filters that same full view for a client drilldown. Bounded JSON alone does not establish bounded database reads or memory use. Its lineage list initially restricts records to the baseline scenario and caps offsets at 100,000. These observations were sent to the implementation lane; verify the final implementation against full-book and complete-evidence requirements.

The independently written `three_audience_stress_test.rb` adds exact-cent partial, replay and reversal checks; cross-customer and role denial; GraphQL pagination and access tests. Its database guard targets only the disposable synthetic database. Syntax was checked, but execution remains pending coordinated permission.

Coordinated isolated test run: 4 tests, 61 assertions, 0 failures/errors/skips (seed 4080). The first run's baseline-only count assertion became stale when the implementation expanded to all scoped scenarios; the assertion was corrected to include every scoped case record and the suite passed on rerun. No retained database was reset.

Extended GraphQL and accounting lifecycle run: 6 tests, 146 assertions, 0 failures/errors/skips (seed 62667). Verified cash conservation, retry conflict, separate mock accounting acknowledgment, reversal correction exception and unchanged recognition; role and scope rejection; run revision/hash linkage and separately recorded unbilled/reclassification outcomes. The test uses only the guarded disposable Compose database. Initial draft concerns about lineage scope and acknowledgment reversal were addressed during review; bounded database work on summaries remains under review. A separate outbound Finance view was added, but its baseline-only payment query was flagged because the existing confirmed-payment fixture belongs to a separate scenario.

## Remaining review items at handoff

- The current summary and client detail implementation constructs a full medallion view before trimming or filtering it, so bounded response size does not prove bounded work. Root is reviewing the read model.
- The outbound Finance view initially read only baseline records, while the confirmed outbound payment fixture is in a separate scenario. Verify that the final view shows the payment with its scenario and does not add alternate scenarios together.
- The initial Finance UI assumes the RIA shape and labels even when the advisor Finance response is selected. This can dereference a missing commercial object and presents inappropriate inbound actions; the UI lane is addressing it.
- Complete the final independent product walkthrough and full regression after the implementation settles. The passing tests above do not establish end-to-end UI acceptance, sustained-load behavior, or a live accounting integration.

Final read-model stress run: 11 tests, 173 assertions, 0 failures/errors/skips (seed 36927), in the isolated guarded test DB. It compares every paginated lineage record with scoped medallion and supported native billing records; checks native invoice links and client denial, complete edge pages, statement and observation paging, assignment date boundaries, and published reads while the engine and full presenter are blocked. Identical publication refresh adds no evidence. An earlier run exposed missing timestamp columns in native listing and invoice detail; the implementation was corrected and the checks passed on rerun. These checks do not measure sustained load or replace final browser acceptance.

The earlier handoff items describe the draft at that time. Published summary and paginated detail checks now pass as described above; the outbound scenario and UI walkthrough remain for integrated acceptance by root.
