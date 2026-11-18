# Disclosure-informed prototype implementation plan

16 November 2026. Planning lead: Astra. This is the bounded next implementation
milestone, not a statement that the features below are already delivered.

Read with `SAVVY-DISCLOSURES-REVIEW-2026-11-16.md`,
`THREE-AUDIENCE-PLAN.md`, `MEDALLION-ENGINE-CONTRACT.md` and
`THREE-AUDIENCE-API-CONTRACT.md`. Public ADV/CRS findings identify capabilities to
model. They do not establish the fictional prices below, authorize actual fees,
or supply an individual agreement or Finance accounting policy.

## Outcome and fixed boundaries

Extend the existing Client, Internal Product and Internal Finance workspaces with
one linked February 2027 household billing story and a small set of alternative
commercial treatments. The user can explain an amount, inspect its source,
change a supported policy through the API, compare frozen inputs, review the
exact change, and inspect the resulting billing and independently sourced cash
and recognition evidence. This is an integrated extension, not another scenario
runner, selector, calculator or standalone dashboard.

- `Economics::Engine` remains the only typed commercial interpreter. Fee, credit,
  allocation, compensation entitlement and residual amounts must reference engine
  outputs. Normalizers validate/select facts; presenters and dbt do not price.
- Policies, scope, dates, basis, cadence, rates, minimums and supported formulas
  are versioned API data. A new supported policy needs no deployment. Existing
  primitive operators should suffice; any genuinely needed generic operator must
  extend the same interpreter and its tests, never a product calculator.
- Retain original source bytes, every arrival, revisions, assignments, runs,
  publications, reviews and historical billing. The namespace is
  `disclosure_2027`, with prefixed external IDs. Existing baseline and
  `finance_timing_2027` records and amounts are untouched.
- Savvy owns obligations, invoices and lines. Campfire/CLM remain explicit mocks.
  No production integration, real data, payroll execution, payment initiation,
  release, hosted deployment or new spend is included.
- Household fee groups are dated sets of underlying client accounts for one
  pricing/allocation decision. They are not advisor parents, permission ancestors,
  business ownership or inherited policy. Advisor hierarchy remains deferred.
- Keep the March 2026 real ADV/CRS viewer, original bytes, manifest and source
  links. A disclosure never substitutes for an agreement. The empty agreement
  file registry stays empty. Fictional terms evidence is a record, not a fabricated
  agreement PDF or a claim that an actual agreement has been supplied.

## Delivery status at planning time

Already implemented: one interpreter; immutable medallion evidence; exact money;
API policy/review lifecycle; canonical positive billing objects; shared client
shell; paged internal lineage; cash matching; supplied recognition evidence; and
the real disclosure viewer. Current billing fixtures do not prove all the
capabilities in this plan.

Required in this milestone: persisted and exercised alternative billing bases,
fee-group allocation, onboarding/termination calculation, separate credit/refund
facts, typed compensation, cost coverage, linked recognition evidence, supported
policy editor and new traceable records. A static label or precomputed fixture
answer is not implementation of those calculations.

Deferred: production source authority, actual agreement ingestion/signature,
real Campfire/CLM adapters, cross-currency groups, an unrestricted formula builder,
complete tax/payroll/equity valuation/vesting administration, real loan servicing,
all possible transfer/rebalance rules, automatic disclosure refresh, and the
advisor hierarchy. Unsupported combinations must be rejected or marked unresolved;
they must not silently reuse a nearby treatment.

## Exact acceptance fixtures

All identities, terms, holdings and accounting records are authored fictional
fixtures in USD. Money below is in dollars for readability; API amounts are exact
minor-unit strings and engine accruals retain rationals until assessment.
February is `[2027-02-01, 2027-03-01)`, 28 calendar days. Display the last included
day. These deliberately chosen fixture terms use annual rate / 12 for a full
monthly charge, then actual service days / 28 for a partial month. This is not an
inference about Savvy's actual day-count convention.

### Main client and household path

Use two fictional accounts, `disclosure-alder-a` and `disclosure-alder-b`, within
one `disclosure-alder-household`, in the advisor business. Their billed debtor is
one fictional household. Two separate customer/debtor permissions are not being
combined. Membership, eligibility and allocation method have effective intervals,
source identities and knowledge clocks.

The ending-value evidence selected for advance billing is 31 January 2027,
received before invoice issuance. Account A has $600,000 eligible assets plus
$150,000 private assets explicitly excluded by the fictional terms; account B has
$400,000 eligible assets plus $100,000 held-away assets explicitly excluded.
Reported assets are $1,250,000, excluded assets $250,000, eligible basis $1,000,000.
These classifications are terms-dependent, not a universal rule that all private
or held-away holdings are unbillable. Each exclusion names its evidence and reason.

| Proof | Required result |
|---|---|
| Ending-value monthly fee at 1.2% annual | $1,000 assessed, using $1,000,000 × 0.012 / 12 |
| Household allocation | $600 to A, $400 to B; group and children never summed together |
| Native billing | One positive $1,000 invoice, two positive $600/$400 invoice lines and corresponding obligations; same run/output references |
| Advance versus arrears | Same full-period $1,000 with unchanged basis/terms; advance invoice Feb 1, arrears invoice Mar 1 in a comparison only; invoice/due/service/cash clocks distinct |
| Quarterly cadence comparison | $3,000 for Jan 1–Apr 1 at the same annual rate and explicit 1/4 period factor; separate comparison, not added to monthly billing |
| Onboarding on Feb 15 | Fourteen service days through Feb 28: $500 total, $300/$200 allocated; separate comparison, not another live bill |
| Termination effective Feb 15 | Fourteen used and fourteen unused days: $500 service charge retained; $500 credit entitlement, allocated $300/$200 against the original lines |
| Refund evidence | Original prepaid receipt $1,000 remains; separate confirmed outbound refund $300; credit $500, confirmed refund $300, remaining refund obligation $200 |

The termination recalculation selects the approved termination fact and the
original billed basis/terms, not a replacement period-end market value. It retains
the original $1,000 invoice and full-term assessment. An earlier as-known view
before termination evidence shows no credit. The credit is a distinct commercial
record; an approved credit or refund request is not proof of cash movement. An
independent refund-source observation plus a scoped application supplies $300.
For the fixture, invoice issuance/due date and original receipt are Feb 1;
termination is effective Feb 15 and received Feb 16; the commercial credit is
approved Feb 16; independent outbound refund evidence is effective/received Feb
18. The refund application references the exact original receipt and credit
allocation and cannot exceed either effective remaining credit or refundable
original cash. A purported refund without those links is an exception, not a
completed payment. Local credit approval is never called an accounting posting.

Native tables currently enforce positive amounts and exact header/line/obligation
conservation. Reuse them for the original invoice. Represent credits as typed
immutable evidence with original invoice/line/output references and positive
credit magnitude plus explicit reverse direction. Do not insert negative invoice
lines, weaken existing constraints, or call an evidence row a native credit-note
table. A new credit table is unnecessary for this prototype. Read models must show
this distinction honestly.

### Supported alternatives through the same policy API

Persist these as named policy/evidence examples, with actual engine runs and
comparisons. They are discoverable under Product's terms and the relevant account;
only the selected assigned treatment contributes to the published bill.

| Alternative | Inputs and exact acceptance |
|---|---|
| Average daily balance | 28 daily observations: first 14 days A $600k/B $400k; final 14 days A $700k/B $500k. Group ADB $1.1m; 1.2% /12 gives $1,100; pro-rata assessed lines $650/$450. Requires every expected day and both members; no forward-fill invented by UI. |
| Monthly minimum | Ending-value fee $1,000 with $1,250 group minimum gives $1,250, allocated $750/$500. Apply minimum once to group, not once per account. |
| Net-worth basis | Separately evidenced assets $6m and liabilities $1m, eligible net worth $5m; 0.12% annual /12 gives $500. Preserve asset/liability source references and classification, without mixing this alternative into AUM. |
| Fixed monthly service | $400 monthly; a fourteen-day service portion gives $200 under the explicit prorating policy. |
| Hourly planning | Approved timesheet 7/2 hours × $200/hour gives $700; hour quantity is exact, not floating point. |
| Optional service | Explicit accepted service election and effective terms produce $100; absent election blocks that dependent charge, rather than assuming enrollment. |
| Policy edit | Change ending-value annual rate from 1.2% (`3/250`) to 1.32% (`33/2500`) against frozen $1m inputs: $1,000 → $1,100, lines $600/$400 → $660/$440. Preview has no billing effect; exact reviewed publication plus explicit assignment/evaluation creates a superseding published result. |

If ADB or eligibility selection needs normalized summaries, store a normalized
fact with every contributing observation/revision and completeness evidence.
Averaging, money arithmetic, assessment and final allocation still happen in the
engine graph. Calendar day counting/interval intersection may be normalization;
its declared basis and evidence must be stored, and its scalar result consumed by
the engine. Do not store the expected fee as a source fact.

A January ending valuation and February ADB are different source requirements.
Missing data blocks the affected alternative, not the independent valid ending-
value bill. A late revised valuation is retained and changes a later as-known
comparison; it cannot retroactively mutate a published run or its invoice.

### Compensation and cost evidence

One linked fictional advisor compensation panel demonstrates the following
separate meanings. These are not an inferred compensation package from the CRS.

| Type | Fixture acceptance and exclusion |
|---|---|
| Salary entitlement | $5,000 for the stated period from approved fictional employment terms; $0 confirmed payout until separately evidenced |
| Discretionary bonus | $1,000 approved event; distinct entitlement and payment status |
| Transition loan principal | $12,000 disbursement obligation and separately evidenced $12,000 cash advance; not fee revenue or salary/bonus |
| Forgiveness | Separate approved $1,000 forgiveness event reduces outstanding principal from $12,000 to $11,000; not another cash payment; accounting/tax treatment remains independently supplied or unknown |
| Equity award | 100 units, award identity and date; no dollar value without valuation evidence, no addition to monetary payables |

Salary/bonus/loan/forgiveness calculations and balances reference typed engine
outputs. Units or non-cash observations may be typed source evidence. Do not
force these into the existing guarantee/coverage event assumptions. Extend a
bounded typed event treatment or separate adapter feeding the same engine.
No aggregate that calls salary + loan cash + forgiveness + equity “earnings” is
permitted. Strategy/referral compensation can be represented with a source and
component classification; a general incentive/payroll platform is deferred.

Cost presentation distinguishes the $1,000 assessed advisory charge from a
separate $25 custodian charge observed on an independently sourced statement.
An embedded fund-cost category is known to exist but has no complete monetary
observation. Show “Known direct charges: $1,025” only as the sum of two distinct
identified charges, and “Total costs: incomplete” with missing category/period.
Do not count the custodian's observation of the same advisory charge again.
Each line declares charger, recipient/earner, payer, category, assessed/observed/
embedded classification, currency, period, source, and whether it enters a named
subtotal. Unknown cost is null, never zero. Outside costs do not become Savvy
invoices or compensation. A small RIA-context observed-cost fixture can exercise
the shared classification/read contract without reinterpreting the ADV as RIA
platform pricing or changing the existing RIA economics.

### Finance treatment and outcomes

Link the exact original $1,000 invoice and $500 credit to a fictional Finance
input package, authored treatment/version, supplied schedule and separately
identified mock postings. Example authored outcomes: initial prepaid invoice
$1,000 deferred; through Feb 14, $500 reported recognized and $500 deferred;
approved $500 termination credit with supplied correction clears that $500
deferred. The later $300 refund changes cash and refund settlement, not the
$500 reported recognition under this unchanged treatment.

These are supplied accounting facts. The engine computes the commercial charge
and credit; it does not invent recognition from elapsed days, invoice issuance or
cash. One missing posted outcome remains visibly missing. A changed commercial
policy/credit with no matching treatment opens a correction exception rather than
reusing the old schedule. Preserve the existing $600 AR/$600 applied/$400
recognized/$800 deferred Finance fixture and its acknowledgment flow unchanged.

## Shared data and API contract

Use retained `MedallionEvidence` artifact/delivery/fact/policy/assignment/run/event/
payment/application/publication records and native positive billing tables.
Prefer a new cohesive `DisclosureWorkbench` service and read presenter, with
minimal existing routing integration. A service is not a new deployment.

Every persisted payload has `contract_version: disclosure/v1`, `synthetic: true`,
kind/classification, stable ID/revision, tenant/entity/case, business subject,
currency when monetary, effective service interval, recorded/received clocks,
and provenance references. Source references include record ID, external ID,
revision and hash. Runs freeze manifest, policy, assignment and implementation
hashes and preserve exact result/dependency references. Rows that have no actual
execution evidence say so. Identity equality or an amount match alone is not a
lineage edge.
The implementation fingerprint covers the shared engine plus the new source
normalization, selection, lifecycle and publication adapters. The unchanged
legacy engine-only fingerprint alone is insufficient for these review bindings.

### Query shape

Add `disclosureWorkspace(caseId: ID!, audience: String!, limit: Int, offset: Int)`
returning JSON; audience is `client`, `product` or `finance`. It uses the existing
business context, never a new Case selector. Server authorizes both case and
audience: external advisor/RIA identities may request only their own client
view; operator may inspect all authorized views; Finance gets its authorized
Finance view; auditor is read-only. A requested audience cannot elevate identity.

Common response fields:

```
contract_version, available, case_id, audience,
context: {namespace, currency, service_start, service_end_exclusive, knowledge_cutoff},
summary: {selected_policy_id, selected_run_id, publication_id, status},
sections: {...audience-specific projections...},
page: {limit, offset, total}, exceptions: [...]
```

`sections` uses stable names agreed before UI implementation: `billing`,
`valuation`, `terms`, `lifecycle`, `compensation`, `costs`, `recognition`,
`policy_options`, `changes`. Client receives readable amounts/basis/terms and
its own scoped status; raw artifacts, internal reviews, policy graphs and service
execution details are omitted. Product receives configuration, comparisons,
lineage links and requests; Finance receives commercial objects, credit/refund
status, cost provenance and treatment/schedule/posting evidence.

Each financial item includes `id`, `label`, `classification`, `amount_minor`
(or `exact`/non-money quantity), `currency`, `payer`, `payee`, `service_start`,
`service_end_exclusive`, `run_id`, `output_id`, and source/record links appropriate
to audience. Missing values are null with reason. Alternatives have explicit
`comparison_only: true` and never enter selected monetary totals.

Lists are bounded (default 20, max 100). A whole raw ledger or book is not sent to
the client. Reuse existing paged `lineageRecords`/`lineageRecord` for internal
record traversal; extend only enough to include the new reference edges/native
records. List pagination never defines household aggregation membership.

### Command shape and governance

Add `disclosureCommand(action: String!, input: JSON!, idempotencyKey: String!)`
with the existing `{data, errors}` payload convention. Reject unknown actions,
fields, ambiguous numeric input, bad intervals, missing identities and unsupported
combinations. All money input is integer minor units; rational rates/hours are
exact strings. Role checks, scope locks, atomic write/publication and idempotency
follow existing workbench patterns. Same key/same input returns the same result;
same key/different input fails. No read endpoint evaluates or bootstraps.

Bounded actions:

- `BOOTSTRAP`: operator, empty input. Retain fixture originals/arrivals, approved
  fictional terms/evidence, initial selected run, alternative comparisons,
  original native billing, lifecycle and mock accounting records, all idempotent.
  No baseline reset or blanket reseeding.
- `SAVE_POLICY`: operator, `{case_id, base_policy_id, policy, effective_from,
  effective_to, reason}`. Validate graph/metadata and create an immutable draft.
  Supported editor parameters include basis, cadence, annual rate, minimum, fixed
  amount and optional-service treatment; unsupported parameters fail explicitly.
- `COMPARE_POLICY`: operator, `{case_id, policy_id, baseline_run_id}`. Freeze and
  use the baseline manifest/source cutoff. Return old/new component amounts and
  source, policy, document/terms and implementation hashes; do not bind or issue.
- `REVIEW_POLICY`: authorized Legal or Finance role, `{case_id, comparison_id,
  decision, reason}`. Bind exact comparison, both policies, sources, synthetic
  terms/document reference+version and interpreter hash. Required roles are
  returned by the proposal; both Legal and Finance approvals are required here.
- `PUBLISH_POLICY`: operator, `{case_id, policy_id, comparison_id}`. Reject missing,
  denied or stale exact reviews. Makes the policy available, not assigned.
- `ASSIGN_POLICY`: operator, `{case_id, policy_id, subject_id, effective_from,
  effective_to, reason}`. Explicit dated assignment in this namespace. Reject
  overlap/ambiguous precedence. Never select it because a disclosure changed.
- `EVALUATE`: operator, `{case_id, knowledge_cutoff}`. Use approved assignment and
  eligible source evidence; persist immutable result and selected publication.
  Historical billed invoices remain historical. Changed billed periods create a
  review/correction requirement, not silently reissued invoices.

Existing medallion governance may be factored/reused if it can bind this namespace
and its manifest without invoking hard-coded baseline adapters. Otherwise implement
these same invariants in the new adapter; do not weaken existing checks. The UI
may expose only the ordinary supported controls; the API graph contract remains
available for tested policy configurations.

For this bounded milestone, source revisions, termination, refund and compensation
observations can be authored fixture ingests via `BOOTSTRAP`; their calculations,
selection, typed identities and state transitions must nevertheless be real and
tested. A general end-user import editor or arbitrary bank/refund command is not
required. Test the same source normalization/selection path with missing, duplicate,
revised, future and conflicting evidence.

## Integrated interface

Client: a compact “Household billing” card in existing overview and relevant
statement/account context opens the February statement and its two allocated
lines. Explain reported/eligible/excluded value, selected date/basis, fee group,
terms and service dates. Put termination credit and refund progress beside the
original bill with distinct direction/status. Compensation is a separate advisor
panel; outside/embedded costs have explicit completeness. Existing September
book totals retain their period and are never merged with February.

Product: add an account-context section in Accounts/terms for this billing group,
with “Propose a change,” supported fields, old/new component comparison, required
reviews and next action. Requests appear in the contextual work queue; an
inline queue is acceptable if clearly linked from the existing Work queue.
Use named treatments, not a scenario dropdown. Existing Data lineage opens actual
new records and dependencies, including an ordinary non-featured observation.

Finance: add a clearly dated, linked household billing section in existing
Finance. Show original invoice → commercial credit and independent refund
allocation as separate records, then input package → supplied schedule → reported
postings. Every arrow opens evidence; missing evidence has a meaningful reason.
Cash and recognition are not interchangeable steps of one progress bar.

Preserve Savvy branding and inclusive dates. Keep IDs and hashes in detail views,
not the primary explanation. Provide loading/empty/error/retry states, keyboard
controls/focus, small-screen layout and no horizontal overflow. Client cannot see
internal raw records even by constructing query arguments directly.

## Work ownership and acceptance gates

1. Backend Terra: `apps/api/app/services/disclosure_workbench.rb` and optional
   `disclosure_read_model.rb`, `fixtures/disclosures/`, focused Ruby tests;
   minimal routing in `workbench.rb`/`graphql/demo_graph.rb`, schema export and
   evidence-link integration. Own arithmetic/authorization/contracts and native
   billing persistence. Coordinate any change to the engine before making it.
2. Frontend Terra: `apps/web/app/DisclosureWorkspace.tsx`, dedicated styles and
   minimal hooks in existing page/Product/Finance components. Own existing-shell
   integration, supported policy editor, query/actions and accessible presentation.
   Do not change public disclosure files, registry or historical statement logic.
3. Root: contract coordination, serialized database checks, retained bootstrap,
   independent review/stress, inactive production build, browser checks and
   activation. Root owns database reset access, all service operations and preview
   build/activation; agents never reset the test DB or operate/rebuild services.

Backend gates: exact values above; native invoice conservation; every displayed
computed amount maps to an engine output; rational hours/rounding; rounding-tie
allocation conservation (e.g. a one-cent group fee split 50/50 has exactly one
cent allocated, deterministic winner); group membership/source date coverage;
policy edit/review/stale denial; duplicate idempotency/source conflict; missing
ADB day; excluded holding correction; before/after knowledge cutoff; overlapping
membership; cross-case/entity/currency denial; zero-total weights and invalid
interval rejection; independent salary/loan/equity treatment; unknown costs;
credit/refund conservation; missing recognition outcome; historical hashes intact.

HTTP/UI gates: real read/mutation API flows, not mocked frontend replies; both
business contexts remain accessible; scoped direct queries; a complete exact
policy draft → comparison → reviews → publish → assign/evaluate proof; no preview
fee changes before assignment; no silent rebill after assignment; ordinary
source record and raw-arrival linkage; keyboard/mobile walkthrough; ADV/CRS view,
source/download and agreement-empty behavior preserved. API action permissions
must remain real even if demo review identities are deliberately simulated.

Regression: root runs the existing Ruby suites and appropriate
`./scripts/check.sh`, `./scripts/analytics.sh`, reconciliation/product checks and
existing audience/disclosure HTTP checks serially as their DB needs require.
Root verifies retained row fingerprints before/after bootstrap. No destructive
suite runs against retained data or concurrently with another destructive suite.

Both port 3103 baseline and port 3104 current preview stay running throughout
implementation. Build into a fresh inactive directory, never `.next` or current
`.next-disclosures`; root verifies then switches only the authorized 3104 preview
and retains rollback. Completion requires implemented-versus-deferred notes,
exact test results and limitations, linked review findings/fixes, updated handoff
and a working local preview. No claim of live provider integration or actual
Savvy contractual/accounting correctness is made.

## Coordinated implementation refinements

Root, 16 November 2026: dynamic allocation of an assessed group minimum/fixed fee
needs evidenced member weights. Add the generic `allocate_by` primitive to the
existing interpreter, reusing exact largest-remainder allocation. Do not add a
separate calculator or unnecessary ratio operator. Validate typed referenced
weights, nonnegative weights/positive total, whole assessed amount, deterministic
recipient-ID ties, dependencies and direction lineage. Bump implementation/language
versions and bind the full adapter/interpreter fingerprint to review evidence.

An assignment replacement must explicitly name `supersedes_assignment_id` and
exactly match the active interval; append a new schedule version and retain the
previous assignment ID/hash. Reject partial or ambiguous overlaps. This is the
explicit correction to the earlier blanket overlap wording. The UI supplies the
current assignment reference from the response; it does not guess an identity.
The changed selected calculation is distinct from the original issued invoice,
and a changed billed period requires correction review rather than reissuance.

Form inputs may send exact decimal digit strings for money in minor units; the
API normalizes them once and rejects decimals, malformed values and out-of-range
integers. Rates and hours remain bounded exact rationals. Frontend percent/dollar
format conversion is presentation only; no fee arithmetic runs in the UI.
