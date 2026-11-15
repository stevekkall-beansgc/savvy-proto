# Synthetic advisor payment calculation contract

Calculation version: **1.0.0**. Python standard library only. No network calls,
database writes, payment execution, or access to company/client records.

## Purpose and boundaries

This is a working demonstration of transparent financial calculations, effective
contract dates, scenario comparison, and a product handoff. All advisor names,
clients, contracts, assets, and costs are fictional. The supplied invitation is
problem context, not a specification of Savvy's actual billing or payout rules.

The implemented billing basis is **daily closing billable AUM, ACT/365, billed in
arrears**. The model explicitly rejects other basis identifiers. It does not
implement advance billing, a prior-period or period-end valuation basis, tiered
fees, household discounts, fee exclusions inferred from raw AUM, holidays,
interest, taxes, withholding, clawbacks, contract parsing, or receivables aging.
Those are specification questions, not silently approximated features. Any
publicly described company convention requires its own mapping and validation
before this calculator could be used for real work.

## Public API and ownership

- `demo_dataset() -> dict` returns a fresh synthetic November 2026 dataset.
- `list_advisors(dataset) -> list` returns profile display metadata.
- `project(dataset, advisor_id, scenario=None) -> dict` validates the selected
  advisor and computes a JSON-serializable result without mutating its inputs.
- Invalid data raises `ValueError`; missing observed days never become zeros.

This core owns calculation semantics. It has no ERP coupling. A separate
read-only adapter may display settlement evidence beside this estimate, but an
ERP amount does not establish a forecast's billing basis or collection rate.

The fixture's observed period is November 1–13, 2026, inclusive; projected dates
are November 14–30. The explicit next payout date is December 5, 2026. Dates are
calendar dates, and the as-of date means its completed closing observation.

## Asset and fee ledger

Each client has an explicit annual management-fee rate in basis points and a
complete daily sequence of **billable** asset observations. Total portfolio AUM
is not automatically treated as billable. Each row satisfies:

`closing billable assets = opening billable assets + market movement + net flows`

Opening assets must equal the previous day's closing assets. An arrival has
explicit zero observations before its inflow. A departure is an outflow, with
zero closing assets afterward. Neither is described as investment performance.

The exact daily fee is:

`billable closing assets in cents × annual fee basis points ÷ (10,000 × 365)`

All intermediate numerators are Python integers. No binary floating-point money
arithmetic is used. The denominator is constant under this supported basis.
Daily amounts are accumulated before rounding; **fees round once per effective
contract segment**, to the nearest cent with ties away from zero.

For display, each segment's integer cents are allocated to its daily rows by
largest remainder, with chronological ties. Earned fees through the as-of date
are independently rounded and fixed. The projected portion receives the
remaining segment cents. Thus a changed future scenario cannot alter displayed
historical earnings, and displayed daily cents reconcile to the period total.

## Future scenarios

Only three scenario parameters are supported:

| Parameter | Meaning | Accepted values |
| --- | --- | --- |
| `market_change_bps` | One-time market move on the first projected date | Integer, −10,000 to +10,000 |
| `net_flow_cents` | One-time net flow after that market move | Integer cents within model bounds; cannot make assets negative |
| `collection_bps` | Projected period fees expected collected by the payout date | Integer, 0 to 10,000 |

Market movement is allocated across current client balances. Net flow is then
allocated across the remaining balances, retaining each client's supplied fee
rate. Future balances are held constant after that date. This is a transparent
what-if assumption, not a probabilistic market forecast. A new client with a
different fee needs a separate client record; net flow does not invent its
commercial terms. Positive flows into an empty billable client base are rejected
because there is no fee basis to assign to them.

With no scenario, future assets remain at the last observed balance and the
advisor's explicit default collection assumption applies. A closed period has
no projected asset days; market/flow inputs have no effect and generate a
warning. Collection assumptions can still change expected future cash.

## Revenue, entitlement, and cash are distinct

`earned_fees_cents` is gross fee accrual through the as-of date.
`projected_fees_cents` is gross fee accrual across the complete billing period.
`advisor_entitlement_cents` applies full-period contract economics and expenses
to those fees **before loan repayment**.

`expected_collections_cents` applies the collection assumption to full projected
period fees. It is not verified cash or a current ERP receivable. Expected
collections are allocated across effective-contract segments in proportion to
their fee amounts, with exact cent reconciliation.

`estimated_payout_cents` uses those expected collections, the following cost
waterfall, and the capped loan repayment. Scaling a net entitlement by a
collection percentage would incorrectly scale fixed costs, so this calculator
does not do that.

## Cost and loan waterfall

1. Allocate fixed period pre-share expenses across effective-contract segments
   by calendar days. Apply each segment's expenses only up to its available fee
   revenue. There is no invented cross-segment deficit recovery policy.
2. Apply that segment's advisor-share percentage to the remainder, rounded to
   cents. The company receives the exact remainder of the split.
3. Aggregate advisor share and apply fixed post-share expenses up to available
   advisor proceeds.
4. Loan repayment is the minimum of available proceeds, opening principal,
   scheduled repayment maximum, and the percentage cap on positive proceeds.
   The percentage cap is rounded to the nearest cent using the same ties-away
   rule. This is an explicit demo convention.
5. The remaining proceeds form the estimated payment. Remaining principal is
   opening principal minus the hypothetical repayment.

The cash waterfall's signed rows sum to the estimated payout; the final total
row is a presentation total and is not added a second time. Pre-share and
post-share costs have different economics and are labeled separately.

Deductions that cannot be applied are exposed in `unapplied_deductions_cents`
with a warning. They are **not forgiven**. Their recovery timing and priority
require the actual contract and are not guessed. Outstanding loan principal
always remains visible. No estimate mutates a real loan or payment ledger.

## Result fields

The result contains `advisor`, `meta`, `scenario`, `summary`, `waterfall`,
`daily`, `contracts`, `expenses`, `loan`, `clients`, `assumptions`, and `warnings`.
`meta` includes `source_mode: "synthetic"`, calculation version, supported billing
basis, currency, and all period dates.

Summary fields are integer USD cents:

- `current_aum_cents`
- `earned_fees_cents`
- `projected_fees_cents`
- `expected_collections_cents`
- `advisor_entitlement_cents`
- `estimated_payout_cents`
- `unapplied_deductions_cents`
- `loan_repayment_cents`
- `loan_remaining_cents`
- `baseline_payout_cents`
- `delta_payout_cents`

The baseline always uses zero future market shock, zero future net flow, and the
advisor's default collection assumption. Delta is scenario payout minus that
baseline. The current AUM and earned-fee fields remain historical observations.

## Independent reference calculations

These are arithmetic references using constant synthetic balances, not claims
of agreement with an existing company spreadsheet.

| Reference | Calculation | Expected amount |
| --- | --- | ---: |
| Simple gross fees | $10,000,000 × 1% × 30 / 365 | $8,219.18 |
| Simple advisor payment | Rounded fees × 80% | $6,575.34 |
| Expense/loan gross fees | $20,000,000 × 0.75% × 30 / 365 | $12,328.77 |
| Split base | $12,328.77 − $3,000.00 | $9,328.77 |
| Advisor share | Split base × 75%, rounded | $6,996.58 |
| Proceeds before loan | $6,996.58 − $600.00 | $6,396.58 |
| Loan repayment | Minimum of $2,500 balance, $2,000 schedule, 20% rounded cap | $1,279.32 |
| Expense/loan payment | $6,396.58 − $1,279.32 | $5,117.26 |
| Remaining loan | $2,500.00 − $1,279.32 | $1,220.68 |

At 80% expected collection, the expense/loan case produces $9,863.02 collected,
$4,547.27 after fixed expenses and the split, a $909.45 loan repayment, and a
**$3,637.82** payment. Full-period entitlement before debt remains **$6,396.58**.

A $10 million, 1% example with 70% share for November 1–15 and 80% for November
16–30 produces segment fees of $4,109.59 each. The independently rounded advisor
amounts are $2,876.71 and $3,287.67, totaling **$6,164.38**. Segment rounding is
deliberate; using an average share and a different rounding boundary can differ
by a cent.

## Validation and evidence

The unit tests cover independent monetary references, expense treatment, loan
caps and balances, cash shortfalls, effective-date boundaries, observed AUM
reconciliation, historical immutability under scenarios, client flows versus
market changes, exact waterfall reconciliation, and missing/unsupported inputs.

Inputs are bounded to 1–31 days within one calendar month, 50 advisor profiles,
100 clients per selected advisor, 31 contract terms, and 30 expenses. Input and
output integers must remain JSON/JavaScript-safe. Each monetary input is also
bounded to 10 trillion cents. Booleans, fractional values, and numeric strings
are rejected where integers are required. Unsupported scenario fields, fee
bases, expense treatments, and loan parameters fail explicitly.

These tests demonstrate the implemented synthetic contract. They do not validate
an actual Savvy contract, integration, security configuration, production load,
or payment. Human acceptance and company rule confirmation remain distinct from
passing local tests.

Repository operating agreement read: **BEANA-NIGHTSHIFT-2026-10-15-r10**. The
current user-authorized prototype is the scope; historical work windows do not
supply execution authority. This file records calculation decisions only and
does not authorize publication, deployment, or third-party delivery.
