# Legume Labs reuse and source boundaries

This is an independent, synthetic advisor-payout prototype. It contains no
Savvy source code, private advisor contracts, customer financial data, Campfire
credentials, or live account connection. It does not represent a finished
Savvy integration, a production billing engine, or an approved payout.

## Source versions inspected

| Source | Inspected revision | How it informs this prototype |
| --- | --- | --- |
| [Legume Labs Core](https://github.com/stevekkall-beansgc/legume-labs-core/tree/db1339068fb50d3f62b630099b90ab7a248b559c) | `db1339068fb50d3f62b630099b90ab7a248b559c` | Direct reuse of the shared design-token distribution; isolated, deterministic experiment structure |
| [Bean Finance Library](https://github.com/stevekkall-beansgc/bean-finance-library/tree/618ef7b4b9fb52cf0332851c45aadd72cc7d7e62) | `618ef7b4b9fb52cf0332851c45aadd72cc7d7e62` | Knowledge and worked-fixture patterns for source coverage, contract versions, cash versus billing, and forecast assumptions |
| [Bean Counter](https://github.com/stevekkall-beansgc/bean-counter/tree/9342c46cf89a11a005f8f768985e18fc7a98036e) | `9342c46cf89a11a005f8f768985e18fc7a98036e` | Architectural reference for exact money, a pure calculation core, retained source evidence, and corrections |

The repository heads above were read through the connected GitHub account on
November 13, 2026. Their existing test results and release claims do not become
test results for this prototype.

## Direct assets versus design influence

Core's `shared/design-system/tokens.json` and `tokens.css` are version **1.0.1**;
`primitives.css` supplies optional native-HTML primitives. Their `--bl-` token
names and semantic meaning are preserved. The assets remain together at the
pinned source version. Application styles use those tokens and may add scoped
layout rules. The Core design-system contract and validator remain the sources
of truth for shared assets.

The forecast logic and Campfire adapter are new application code. They do not
call Bean Counter or copy its Rust implementation. Bean Counter's documented
local CLI profile has its own supported billing semantics and frozen guards;
it is not a general advisor-fee API. A future engine integration needs an actual
adapter, a pinned supported profile and executed reconciliation tests. No
Bean Counter integration has been validated here.

The Finance Library's relevant files are:

- `capabilities/contract-to-cash-synthetic-starter.md`: keep contract terms,
  invoices, revenue, collections and cash distinct; retain source identities.
- `capabilities/cash-forecast-synthetic-starter.md`: version assumptions and
  snapshots, distinguish actuals from projections, and expose missing coverage.
- `docs/operating-calendar-policy.md`: preserve contractual dates separately
  from processing dates; do not invent a payout calendar from weekdays.
- `docs/source-assessment-and-reuse.md`: record evidence, access, rights,
  maturity and applicability separately.

These are design notes and synthetic examples, not an executable library or
approval of Savvy's accounting, fee or advisor-contract policies.

## Campfire adapter boundary

The adapter reads `fixtures/campfire-sample.json` and produces an advisor-scoped
JSON view through `sample_erp_status(advisor_id)`. The visible status remains
`source_mode: synthetic` and `connection: not_connected`. The fixture contains
three invented advisors and uses an explicit invoice/client/advisor crosswalk.
It neither looks up a person by name nor assumes a customer is an advisor.

Campfire's [invoice-payment documentation](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoice-payments)
documents stable payment IDs, modification timestamps, `voided_date`, and a
`CREDIT_MEMO` example. The retrieved page did not establish a complete cash-type
enum. The fixture therefore uses `SYNTHETIC_CASH`, explicitly allowed only by
fixture policy. Unknown types stay unclassified; credit memos never become cash.

The current projection selects the latest supplied revision of each stable
payment ID and retains all distinct supplied versions. Repeated delivery of one
revision adds no cash. Conflicting facts at the same revision fail validation.
A later payment void removes that payment from current cash rather than adding
a second negative or positive payment. An invoice void alone does not erase an
active cash record: it flags the allocation for review. The raw input remains
unchanged. Decimal source
amounts become USD integer cents only after exact validation; no FX or rounding
of unsupported fractional cents is inferred.

`reconcile_cash_forecast` compares observed cash through the cutoff with a
forecast for the same currency and service period plus an explicit separate
collection target date. Its gap is a progress comparison. Final variance stays
unknown; unclassified payments, unresolved allocations or an unspecified
collection horizon withhold the gap. Posting stays disabled. Credits and
invoices are displayed separately. ERP collections do not establish an
advisor's contractual entitlement or payroll/payment authorization.

`plan_read_requests(since)` returns a plan for the documented invoice and
invoice-payment GET endpoints. It executes no request, loads no credential and
creates no webhook. The [invoice documentation](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoices)
says `download=true` starts an email export, so this parameter is absent from
all planned requests. Payment reads retain voids. A future importer must follow
pagination, validate next-link origin/path, retain source versions, review
cash classifications, and establish actual tenant/entity/source coverage.

Current limitations include one advisor per invoice, USD only, and a single
explicit invoice service-period cohort. Split-advisor allocation, cash applied
to other service periods, refunds outside the documented void representation,
real contract mappings, accrual policy, bank reconciliation and production
access control require separate implementation and evidence.

## Verification and authority

The focused adapter gate is:

```sh
python3 -m unittest discover -s tests -p 'test_campfire.py' -v
```

It checks cash/credit separation, repeated delivery, out-of-order updates,
later voids, conflicting revisions, scope mappings, money precision, cutoff
handling, and the inert GET request plan. Running it verifies those synthetic
cases only. It does not exercise Campfire, Savvy's data, or a production payout.

The inspected Core operating agreement is
`BEANA-NIGHTSHIFT-2026-10-15-r10`. Current user-started scope governs this work;
historical windows do not provide new authority. This prototype changes no
live Legume Labs service, domain, billing record or payout instruction.
