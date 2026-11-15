# Revised product plan: broker earnings and commercial terms

14 November 2026. Prepared with Astra following the owner's UI walkthrough, then
authorized by the owner for Terra implementation, independent review and stress
testing. The bounded [final implementation contract](WORKSPACES-IMPLEMENTATION-CONTRACT.md)
is implemented; see [the milestone](WORKSPACES-MILESTONE.md) and
[validation](VALIDATION-WORKSPACES.md). Broader production recommendations in this
plan remain future work. Earlier plans and validation remain historical.

Updated after the billing ownership deep dive: removing accounting workflow screens
does not move Savvy's commercial billing/invoice objects out of its data layer.
See [the evidence and revised architecture](BILLING-OWNERSHIP-DEEP-DIVE.md).

## Product purpose

For brokers: **What am I earning, why, and which agreements govern it?**

For internal teams: **Which commercial terms should apply, what will change, and
has the exact configuration been reviewed?**

The prior milestone surfaced accounting evidence and engineering controls as
primary product screens. The revised plan keeps useful calculation integrity and
history while removing those workflows from the primary demo. A separate Campfire
accounting lifecycle is no longer the next product milestone.

## Two explicit experiences

| Experience | Navigation | Primary job |
|---|---|---|
| Broker | Earnings; Agreements | Understand compensation and governing terms |
| Internal | Advisors; Commercial terms; Approvals | Inspect economics, propose changes and schedule reviewed terms |

Use separate entry points/layouts. A clearly labeled demo experience switch may
let a reviewer explore both; the role picker must no longer explain the product
boundary. Internal support can open a clearly labeled advisor view. Broker scope
must still be enforced by the server; future authentication remains separate work.

### Broker Earnings

Show the selected period, freshness and completeness; eligible earnings; applicable
advance/coverage adjustments; and a provisional guarantee only when configured.
Estimated additional payment appears only when the required basis and balances are
known. A projection must not become a confirmed payment or an unsupported full-month
forecast. The current engine uses supplied eligible fee observations.

Customer rows show eligible fees, selected share, compensation and a friendly
promotion name. A detail drawer explains the applicable rate, eligibility, effective
dates and governing agreement version. Advance balances and opposite-direction
obligations must remain distinct; broker-visible effects come from approved terms
and authoritative balances, without exposing an accounting workbench.

Remove the process subtitle under the customer book. Remove the reproducible
snapshot card, hashes and technical run export from the default broker screen.
Retain only short, relevant calculation explanations and qualifications beside
affected numbers. A useful period/statement history may be shown; engine-run history
belongs behind the scenes. Reproducible inputs remain valuable for support and audit,
but are not a broker-facing product feature by themselves.

### Broker Agreements

Show agreement title/counterparty, document status/version/effective dates, current
standard share, named promotions and relevant guarantee/advance terms. Link the
governing document/version and readable structured calculation terms. Distinguish
current, upcoming approved and historical terms.

Document execution and configuration status are separate. A signed agreement can
await implementation verification; an approved configuration is not proof of a
signed agreement. With no real agreement or CLM access, the demo must use an explicitly
illustrative reference and must not invent signed documents, statuses or working links.

### Internal Commercial terms and Approvals

Use an advisor-specific timeline and change workflow:

1. Inspect existing terms and their agreement reference.
2. Propose rates, dates, eligibility and friendly names.
3. Compare current and proposed outcomes using representative examples.
4. Prepare a proposal for Legal/Finance with structured changes, suggested wording
   when useful, examples and unresolved decisions.
5. Link the reviewed agreement/amendment and decision references.
6. Verify that the exact structured configuration matches the reviewed terms, then
   activate or schedule it under the required approval policy.

Remove the embedded draft-clause editor. Suggested language is an input to Legal's
proposal/CLM workflow, not a permanent legal drafting panel. Remove Review packet as
a standalone navigation item; useful comparison/evidence becomes part of a specific
approval decision. Preparing a proposal does not authorize sending it externally.

Remove the monthly floor subtitle. Keep supported guarantee amount, period, basis
and status in relevant terms detail. Do not expand guarantee mechanisms in this redesign.

## Dated rates and targeted promotions

Use **one PostgreSQL rate table** for standard and promotion rows, with promotions
classified as broker-wide or targeted. Supporting version/approval references may
use existing configuration records; do not create separate standard/promotion tables.

Essential fields: broker, entity, compensation component, configuration/agreement
version, rate kind, friendly name, exact rate, start date, optional end date,
eligibility conditions, explicit precedence and approval/publication references.

Recommended uniqueness grain: broker + entity + compensation component. Within the
selected published schedule, allow at most one effective standard and one effective
broker-wide promotion on any date. Confirm that grain against actual business rules.
Approved future rows may coexist with current rows when their effective intervals
do not overlap. Draft status is not the same as being effective today.

Use half-open effective dates. An omitted end date is open-ended; scheduling its
successor must explicitly end the preceding interval in the new schedule version.
Preserve older published versions and earlier results. Do not overwrite historical
rates or let the new version retroactively change old calculations.

Replace Managed service override with **Targeted promotions**. Recommended
replacement precedence: eligible targeted promotion, then eligible broker-wide
promotion, then standard. Rates do not silently add together. Two targeted scopes
can overlap even when their selector labels differ: require reviewed precedence or
reject ambiguity. Temporal and eligibility conflicts need database/application
validation, not a winner chosen by row order.

Begin with a controlled set of dimensions/events. For example, a new-customer offer
may apply during `[signup date, signup date + X days)`, intersected with the offer's
effective window. Requiring signup during the campaign is a separate condition.
Identify the authoritative signup source; missing/conflicting evidence must create
an explicit eligibility exception, not silently qualify or disqualify a customer.

## Ownership: this app, Campfire and the CLM

These are proposed responsibilities, not verified vendor or tenant capabilities.
No CLM vendor, real source schema or live integration has been established.
Savvy publicly places billing in its unified data layer. Reuse its existing billing
domain before designing new objects. This prototype is not the authority for the
actual Savvy schema. UI location, commercial object ownership and accounting field
authority are separate decisions.

| Responsibility | Intended authority/workspace | This application's role |
|---|---|---|
| Business facts, identities, assignments and signup events | Existing authorized internal source systems | Consume scoped, dated facts and retain provenance |
| Client fee terms, calculations and approved billing obligations | Existing Savvy billing domain | Reuse canonical objects and provisional calculation logic; keep separate from advisor-share rules |
| Commercial invoices and invoice lines, when applicable | Savvy billing domain | Retain approved amounts, debtor, service period, terms version, attribution, document reference and revision history |
| Custodial fee instructions | Approved Savvy billing/execution workflow | Retain instruction identity and approved amount; consume returned execution evidence |
| Compensation rules, rate selection, projections and explanations | This application | Own structured configuration, calculation and approval linkage |
| Operational agreement record and structured interpretation | Savvy, verified against Legal's document | Parties, effective configuration and exact document/version mapping |
| Negotiated language, legal review, executed documents, amendments and signatures | Legal process / CLM if present | Prepare proposals; reference document/version/status; consume reviewed outcomes |
| Accounting invoice representation, AR application/credits, journals, recognition and accounting close | Campfire or verified finance system/process | Consume separately evidenced accounting facts with source IDs and freshness; do not replace Savvy commercial identity |
| Commercial coverage rights and consumption | Savvy compensation/commercial domain | Own directional eligibility and remaining entitlement backed by an approved funding/credit basis; application is not new cash |
| Actual funding, loan carrying balance, payment and bank settlement | Named authoritative finance/execution source, to be confirmed | Use evidence-backed balances and links; do not create a second independently writable cash ledger |
| Actual payment initiation/execution | Existing approved payables/payment rail, to be confirmed | Explain estimated/confirmed amounts; do not execute payments |
| Calculation inputs, historical results and diagnostics | This application | Retain reproducibility and restricted support access |

Authoritative flow: internal business facts + reviewed client fee terms → Savvy fee
calculation/billable obligation → invoice or custodial fee instruction when applicable.
Those billing lines plus reviewed advisor terms feed compensation → broker explanation.
Client pricing and advisor revenue-share rules are separate commercial agreements.
Prospective compensation can use an explicitly provisional billing calculation
before invoice completion; it does not issue an invoice or accounting entry.

Separately: Campfire/finance evidence → validated read model → relevant actual
accounting/payment status. A calculated obligation may eventually become a reviewed
integration proposal to the accounting owner; that requires a separately specified
and authorized mapping. A calculation does not create accounting facts, and a finance
status does not silently change contract interpretation.

Keep stable Savvy commercial identity and approved line amounts while linking a
mapped Campfire representation and returned accounting/execution facts. Retain
line-level account/household/advisor attribution even if accounting receives
summarized lines. An invoice can cover multiple accounts/services; payments and
invoices can have multiple applications. Avoid one dual-writable status/paid flag.
Use one numbering/delivery owner and one posting path per event; a version change
must not blindly create a second invoice, cash event or journal.

The CLM does not automatically compile a signed document into executable rules.
Human review must link the document version to the exact configuration. Which
changes require an amendment/signature versus an operational approval is a Legal
decision, not a universal assumption in the app.

Confirm Campfire support for required objects, identifiers, balances, read access,
statuses and side effects before promising integration. If a capability is missing,
document the gap and select a narrow ownership/integration solution. Do not default
to rebuilding the finance workspace in this app. Campfire accounting records also
must not be mistaken for proof that a payment rail initiated or settled a transfer.

## Treatment of current screens and evidence

| Current area | Proposed treatment |
|---|---|
| Book Overview | Become broker Earnings, with a clearly labeled internal support view |
| Policy Studio | Become internal Commercial terms and proposal workflow |
| Sources & Runs | Remove from primary demo; restricted support diagnostics only if needed |
| Collections | Remove general workbench; retain contextual Savvy billing/invoice and independently sourced collection evidence inside earnings/support views |
| Settlement desk | Remove standalone product UI; retain Savvy commercial coverage/compensation records and explicit external funding/payment authority |
| Reconciliation | Accounting reconciliation remains in Finance's workspace; keep Savvy-to-accounting mapping and exceptions behind internal support |
| Review packet | Proposal/decision attachment within Approvals or CLM handoff |

Preserve all existing evidence, worked examples and regression tests. Demoting UI
does not delete records, reverse examples or reset the retained database. Existing
accounting simulations can remain offline fixtures/restricted diagnostics; their
existence does not justify a product navigation item. Integration placeholders must
remain clearly synthetic rather than imply a live Campfire/CLM connection.

## Proposed implementation sequence — not started

| Stage | Deliverable | Acceptance |
|---|---|---|
| 0. Existing model mapping | Walk one Savvy billing cycle and identify canonical objects, compensation basis and present accounting integration | Reuse plan identifies fee lines, invoice/instruction paths, IDs and single posting owner; no invented duplicate model |
| A. Product separation | Broker Earnings/Agreements; narrow internal navigation; remove identified clutter | Broker can understand one customer's earnings and locate governing terms without an operations screen; history remains intact |
| B. Dated commercial terms | One rate table; historical/current/future schedules; friendly and targeted promotions | Future/adjacent/open-ended intervals work; ambiguous rates fail; missing events are explicit; historical results remain reproducible |
| C. Proposal to activation | Version-specific comparison, proposal, Legal/Finance references and scheduled activation | Changed terms invalidate affected approval; only exact reviewed configuration activates; document status stays distinct |
| D. Focused demo | One broker journey and one internal change journey, with billing lineage | Show earnings before completed billing, agreement terms, future promotion, invoice/instruction-backed lineage and simulated approval/scheduling without accounting tabs |

Retain exact-money, scope, conservation and historical invariants. New validation
focuses on temporal overlap, event boundaries, precedence and approval-to-activation
consistency. Live integrations follow authorized discovery, not this UI redesign.

## Decisions for confirmation before implementation

- Rate uniqueness grain and compensation basis: earned fees, invoiced, collected or
  another basis. Keep the current labeled fee-observation basis until confirmed.
- Authoritative signup event and correction semantics.
- Targeted versus broad promotion precedence; replacement is the recommended default.
- Agreement repository/CLM, access boundaries and approvals needed for each change type.
- Existing Savvy billing objects, client-fee versus advisor-share rules, invoice versus
  custodial instruction paths, and current Campfire integration/posting ownership.
- Campfire accounting records and execution-source balances/statuses available for
  compensation actuals, including draft/finalization, safe retry and correction semantics.
- Useful and permitted broker-visible customer/payment detail. Begin with compensation
  explanation; add actual payment status only when separately evidenced.

Non-goals: a new accounting workbench, expanded reconciliation, inline legal drafting,
arbitrary rule programming, real data, provider writes, payment execution or publication.
Production authentication remains a later gate, not implied by separating demo views.
Preserve Savvy branding. This is a planning-only revision; the running prototype
and its data remain unchanged.
