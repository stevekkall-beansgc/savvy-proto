# Finalized implementation contract: Savvy workspaces

14 November 2026. Astra finalized this bounded scope after the UI walkthrough and
billing ownership research. The owner authorized Terra implementation, review and
stress testing. Campfire and CLM remain local mocks; no external writes, accounts,
real company data, payments, signatures or publication are authorized.

Implemented and validated: see [milestone](WORKSPACES-MILESTONE.md) and
[validation](VALIDATION-WORKSPACES.md). Implementation refinement: the authoritative
database export is `db/structure.sql`, not `schema.rb`, because the Ruby dump omits
the billing function and deferred triggers. Guarantees are copied unchanged in
proposals; this milestone does not add a floor editor.

## Product acceptance

Default to explicit Broker and Internal experiences. Broker navigation: Earnings,
Agreements. Internal navigation: Advisors, Commercial terms, Approvals. Preserve
Savvy's official public-site logo, fonts and palette. Simulated role headers enforce
the existing local API boundary but must not be the product navigation model.

Remove the customer-book process subtitle, monthly-floor explanatory subtitle,
snapshot/fingerprint/export cards and long technical assumptions from broker views.
Remove embedded clause editing. Sources & Runs, Collections, Settlement desk,
Reconciliation and Review packet are not primary product tabs. Preserve all old
records, APIs and tests; useful proposal examples belong with a specific approval.

Earnings explains fee basis, selected share/friendly promotion, earned compensation,
separate coverage and provisional guarantee, and estimated incremental payment.
Show material incomplete-data qualifications near the affected amount. Customer
detail links the source/version, native Savvy billing line, invoice or custodial
instruction, illustrative agreement and selected rule. No accounting/settlement
status is inferred from a projection.

Agreements shows illustrative document/version/status, effective dates, current,
historical and approved-upcoming terms. Mock references must never claim a real
signature or live CLM connection.

## Labeled synthetic defaults

- USD integer cents; exact rates; service-date attribution/selection.
- Client fee terms and advisor compensation terms are separate. Advisor promotion
  changes do not mutate client invoices.
- Existing eligible fee observations remain the earnings basis. No actual daily
  asset-to-fee integration or unseen full-month forecast is claimed.
- Replacement precedence: targeted promotion, broker-wide promotion, standard.
  Targeted ambiguity needs explicit unique priority or rejection.
- Supported selectors: customer_type, product_type, optional signup window.
  Eligibility: signup_date <= service_date < signup_date + within_days, intersected
  with rate dates; within_days 1–365; required missing signup data blocks that result.
- Half-open dates; ends_on=null means open-ended. Demo business date is 2026-11-13.
  A separately frozen future_signup_example may use November 16 and is hypothetical.
  Do not redate retained source observations.

## Domain storage and ownership

Implement one actual PostgreSQL table `commercial_rates` for standard, promotion
and targeted_promotion rows. Columns include scope, configuration_id, broker_id,
component, kind, name, numerator/denominator, starts_on/nullable ends_on, selector
JSONB, signup_within_days, priority and recorded_at. Supporting immutable configuration
records may use a small typed table or existing evidence. No JSON-only rate storage.

Within one configuration, enforce non-overlap for standard/broker-wide promotion
per scope/broker/component; protect identical targeted eligibility scopes at the DB
and intersecting scopes in the service. A successor to an open-ended row explicitly
ends its predecessor in the new version. Preserve prior versions. Save != approve
!= schedule != effective today. Idempotently bootstrap existing policy versions
without changing their payloads or inventing legal approval.

Savvy owns typed commercial fee obligations, invoice headers/lines and custodial
instructions with source/client-terms/account/customer/assignment lineage. Reuse
existing evidence identities via explicit mappings, not matching by amount. A
commercial invoice has a declared debtor and potentially multiple lines. Campfire
mock records represent accounting facts separately; no second cash or revenue.

## Shared API

Existing commands/API remain compatible. New query:

```graphql
productWorkspace(workspace: String!, brokerId: ID, businessDate: String): JSON!
```

`workspace` accepts broker/internal; it selects presentation, not authorization.
Advisor requests are fixed to Alex and cannot fetch internal/other-advisor data.
Internal controls explicitly identify simulated Finance/Legal actions.

Common JSON response (minor fields are exact decimal strings at GraphQL):

```
schema_version: product-v1
synthetic: true
workspace, business_date
brokers: [{id,name,practice}]
selected_broker_id
earnings: {status,basis,business_date,updated_at,
  earned_minor,coverage_minor,incremental_minor,guarantee_minor,
  lines:[{id,customer_id,customer_name,service_id,eligible_minor,earned_minor,
    coverage_minor,incremental_minor,rate:{id,name,kind,numerator,denominator,reason},
    agreement_id,billing_line_ids,exceptions}]}
agreements: [{id,title,document_version,document_status,effective_from,effective_to,
  illustrative,configuration_id,rates,guarantees}]
billing: BillingCatalog view
```

Internal-only: `configuration:{id,hash,broker_id,effective_from,status,agreement_id,
document_ref,rates,guarantees}` and `proposals:[{id,hash,status,effective_from,
comparison,reviews}]`. Broker payloads must omit internal proposal contents.

Use the existing workbenchCommand envelope/idempotency with these additions:

- SAVE_TERMS_PROPOSAL: broker_id, base_configuration_id, expected_base_hash,
  effective_from, rates[], reason. Rates use fields above and friendly names.
- COMPARE_TERMS_PROPOSAL: proposal_id, expected_hash, example_id. Allowlisted
  current_book or future_signup_example only.
- REVIEW_TERMS_PROPOSAL: proposal_id, expected_hash, comparison_hash, document_ref,
  decision=approved_for_demo. Finance/Legal separately bind exact version/examples.
- SCHEDULE_TERMS_PROPOSAL: proposal_id, expected_hash, comparison_hash. Recheck base
  and both reviews atomically. Changed terms create another version, not reused review.

Comparison: `{id,hash,example_id,business_date,hypothetical,baseline_configuration_id,
proposal_id,baseline:{status,earned_minor,lines,exceptions},proposed:{status,
earned_minor,lines,exceptions},delta_minor}`. Blocked comparison cannot be approved.

Mock document reference: `{system:mock_clm,document_id,version,status:reviewed_for_demo}`.
No arbitrary URLs or signature claims. Suggested wording is a local proposal
artifact, not an embedded permanent editor. Existing guarantees are copied unchanged
unless the supported floor editor is explicitly retained and bound in proposal hash.

## Billing lane interface

```
BillingCatalog.new(workbench).seed!
BillingCatalog.new(workbench).view(broker_id:,business_date:)
```

```
obligations:[{id,revision,customer_id,service_id,amount_minor,currency,
  service_period_start,service_period_end,client_terms_ref,source:{id,revision},route}]
invoices:[{id,revision,debtor_id,amount_minor,currency,status,
  lines:[{id,obligation_id,amount_minor,account_ids,assignment_ids}],accounting_ref}]
instructions:[{id,revision,obligation_ids,account_ids,amount_minor,status,execution_status}]
accounting:[{id,provider:mock_campfire,commercial_id,commercial_revision,
  reported_status,applied_minor,ar_minor,recognized_minor,observed_at,mocked:true}]
```

Billing exposes stable source/fact-to-line matching so lane A can populate
earnings.billing_line_ids; coordinate additional account/customer labels directly.
At least one invoice-backed path and one custodial path. Preserve client amounts
when compensation or mock accounting status changes. Unknown reported facts are null.
No HTTP client, credentials or webhook needed.

## Team ownership and validation

- Terra A: commercial rates/configurations/proposals/mock CLM, engine adapter,
  ProductWorkspace service and sole Workbench/GraphQL integration; new domain tests.
  Migration 20261114000100. Do not edit billing lane/UI/analytics.
- Terra B: apps/web only; workspace UI, forms/types, earnings/agreement details and
  scoped styles. Preserve existing brand. No Rails/analytics changes.
- Terra C: BillingCatalog, billing models/fixtures/migration 20261114000200,
  billing tests and dbt. No Workbench/GraphQL edits. Then independent integrated
  stress harness and review of commercial domain after initial implementation.
- Root: shared test reset, db/schema.rb, contract/status docs, backup/recovery,
  integration and browser acceptance. Own existing test reset callsites.

All new migration tables are scope-bound. Root test reset is strictly guarded to
advisor_economics_synthetic_test; new tests should require test/support/synthetic_reset
and call SyntheticReset.call. Coordinate exclusive destructive-suite access. Do not
reset main history. Do not concurrently dump schema.rb or export GraphQL SDL.

Cross-review after implementation: A reviews UI, B reviews billing/reporting, C
reviews rates/proposals/API and attacks concurrency/rollback. Authors resolve findings.
Root verifies full Python/Ruby/dbt regression, eager loading, optimized Next build,
desktop/mobile, actual HTTP broker isolation, canonical billing lineage, mocked-only
integrations, safe migration/restore and unchanged historical main rows/runs.

Retain prior $1,770 earned run and all existing grant/cash/reversal evidence. A new
calculation must not rewrite them. Stop only when the coherent broker and internal
journeys work, rate/date/event boundaries and approval races are tested, and review
findings are resolved or explicitly documented with practical limits.
