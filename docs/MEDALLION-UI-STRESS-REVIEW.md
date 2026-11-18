# Medallion UI and contract stress review

15 November 2026. Independent test against the isolated synthetic test database and the isolated loopback API. No retained November database or live provider was used.

## First run

Command: `docker compose -f compose.medallion.yaml run --rm -e RAILS_ENV=test api bundle exec ruby -Itest test/medallion_contract_stress_test.rb`

Result: **6 runs, 28 assertions, 1 failure, 0 errors, 0 skips.** The RIA role could request its case with an arbitrary `scenarioId` and receive an empty workspace rather than `FORBIDDEN`. A populated private scenario could disclose its contents. The backend owner was notified; rerun after a server-side scope fix.

The other assertions passed in this run: RIA denial of each legacy GraphQL field independently and legacy mutations; denial of cross-case and raw legacy-run access; same-value source revision invalidating a prior comparison; unsupported/cyclic/unit-invalid graph rejection; duplicate event identity with different actors and conflict on changed amount; a forged approval timestamp not backdating the server-stamped decision; and rejection of application of pending payment evidence.

A separate read-only check against the isolated development API confirmed the advisor and RIA can read their own Medallion workspaces and cannot query the other case or internal workspace; the RIA cannot query the legacy internal workspace. RIA summary money values were decimal strings. The advisor had no selected run during that check, so its numeric story was not verified.

## Remaining gates

Do not interpret these checks as full milestone acceptance. Recheck approved-event inclusion and as-known timestamps after backend scenario work, along with immutable historical statements, source corrections and payment/reversal behavior. Desktop and mobile acceptance, the four policy-only demonstrations, and complete isolated regression remain root-coordinated checks.

## Rerun after scope and bootstrap fixes

The same command passed: **6 runs, 29 assertions, 0 failures, 0 errors, 0 skips.** The test creates a populated private scenario and verifies both external roles are denied. The earlier arbitrary-scenario access finding is resolved for this test. One intervening rerun produced a test-only setup error because the new synthetic artifact omitted required original bytes; the fixture was corrected before the passing run.

The tests do not establish end-to-end acceptance of approved event inclusion. Backend validation of the newer `sum_facts` integration and complete scenario coverage is still required, as are the root-coordinated browser and full regression checks.

## Approved-event cutoff rerun

After the governed event and posting-period updates, the same isolated command passed: **7 runs, 31 assertions, 0 failures, 0 errors, 0 skips.** The added test submits and approves a $30 service credit and checks $130 before approval versus $100 after approval using separate as-known cutoffs. One prior attempt omitted the newly required posting period in the test and failed before reaching the pending-payment check; the test and UI were corrected. Full scenario and operational acceptance remain separate gates.
