# Product walkthrough feedback — queued, 15 November 2026

Implementation outcome: [Three-audience milestone](THREE-AUDIENCE-MILESTONE.md).
The queued status below is the historical feedback record, now superseded by the
authorized implementation and validation.

Status: feedback and proposed revision only. No application, data, policy,
permission or running-service change accompanies this document. The current
preview remains available for the walkthrough.

The current integrated plan, reviewed with Astra and Sol, is
[Three audiences](THREE-AUDIENCE-PLAN.md). It adds explicit Internal Product and
Internal Finance jobs to this queued feedback; it is not implemented yet.

## User direction

| Feedback | Required direction |
|---|---|
| Build for Clients, Internal Product and Internal Finance | Shared broker experience; polished configuration and record/service proof for Product; focused cash matching and revenue recognition for Finance. |
| Affiliated advisor and independent RIA should have the same experience | One external workspace and navigation. Commercial relationship and enabled products are account data, not separate experiences. |
| Each may have many clients; don't show every client by default | Book-level overview first. Searchable, paginated client/account detail opens on demand. |
| Multiple related advisor accounts may need parent–child relationships | Deferred at the user's request. Do not choose a hierarchy or implement inheritance/aggregation yet. |
| “Case” duplicates “Choose experience” | Remove fixture/case selection from normal product navigation. Separate access context from the account being inspected. |
| Data pipeline should prove records and the services between them | Replace scenario execution controls with a record-level evidence explorer and explicit processing/service handoffs. |
| Commercial Terms is hard to follow | Start with readable current, scheduled and historical business terms. Put graph configuration in advanced internal detail. |
| Approvals makes no sense | Show review as a stage of a concrete proposed change, with its reason, scope, impact and required reviewers. |
| Adjustments is confusing | Start a contextual one-time-item request from the relevant account/statement. Show its business meaning and resulting statement impact. |

The earlier single-engine, API-policy, Savvy-owned billing and mocked
Campfire/CLM requirements remain in force.

## Proposed shared advisor experience

Both commercial models use the same shell: **Overview, Clients, Statements,
Agreements**. These navigation names are a proposal, not a newly approved design.

The overview summarizes the selected business/account and period: amounts due to
the user, amounts due from the user, payment status, material changes and value
under the selected terms. Only applicable metrics appear. Compensation,
platform charges, rebates and one-time items have understandable labels within
this common structure. A product/relationship difference does not require a
different navigation model.

Preserve legal counterparties, direction and currency. A common experience must
not create a universal net balance across unrelated obligations, entities or
currencies. The same account may eventually use more than one product; pricing
programs remain components of the shared engine.

Remove the initial Cedar/Maple list and daily balance tables from the overview.
The user can drill from a book metric or search Clients, open a client/account,
then inspect charges, earnings, applicable terms, statement items and calculation
basis. Daily observations belong inside that last level. Lists need server-side
pagination/filtering and totals with a clear scope; rendering every client is
not an acceptable large-book design.

For the prototype, any Advisor/Internal switch belongs to a restrained presenter
control. An actual user's access comes from identity and membership. Account
selection chooses a real business context; it must not double as selecting a
test fixture or granting an internal role. The November fixture and other QA
presets can remain available in development tools outside normal navigation.

## Hierarchy — explicitly deferred

The user asked to put the parent–child question on hold. Unresolved examples are
a firm/team with several advisors and a master billing account with advisor
subaccounts. Do not adopt either, combine them into a tree, or make permissions,
rates, guarantees, invoices, payouts or reporting inherit from a parent.

Existing client/account relationships can support drilldown. The deferred
advisor-account hierarchy must not block the remaining interface revision.
Future hierarchy work needs an explicit decision about membership, reporting
rollup, contractual scope and billing responsibility; those relationships must
not be inferred from visual nesting.

## Proposed internal workflow

Organize internal work around **Accounts**, a **Work queue**, **Finance**, and **Data lineage**,
with the architecture/service map available as supporting internal context.
These labels are proposed and can be refined during the walkthrough.

An account opens its overview, agreements/terms and billing activity. Operations
begin with that account and the intended business action, rather than a policy
ID, case selector or generic adjustment form.

### Terms

Lead with the current agreed terms, future scheduled changes and history.
Explain the fee basis, rates/tiers, dates, eligibility, promotion combination,
caps/floors, receipt prerequisites and settlement direction in business language.
Client advisory-fee terms and the advisor's compensation terms remain distinct.

“Propose a change” guides the user through selecting the affected component,
editing its supported parameters, choosing dates/scope, stating a reason and
previewing the effect. Preview uses the same frozen facts and engine on each
side. Show unchanged headline amounts alongside any changed components, such as
a bonus offset by a lower guarantee.

The underlying graph and exact versions remain inspectable in advanced detail.
Simplifying the default form must not narrow commercial optionality, introduce
pricing formulas in the UI or replace API-authored policy versions with code.
Supported schemas/templates drive authoring; unsupported treatment fails clearly.

### Review

Replace the detached Approvals page with a work queue of requests needing action.
A request explains who/what is affected, why, before/after terms, service and
posting dates, financial impact, the linked document and the next required step.
Legal and Finance review states belong on that request. Exact policy/comparison/
source/document/version binding remains enforced behind the interface.

Scheduling/publishing and assignment remain explicit steps, not an automatic
side effect of saving a draft or recording a review. CLM supplies a mocked
document/review handoff; the application does not become a clause editor.

### One-time items

Use a contextual “Add one-time item” action on an account or statement. Start
with its purpose: charge, service credit, compensation item, payout request, or
correction of a prior item. Resolve counterparties and available treatments from
the account context; do not make an operator guess raw debtor/creditor/subject IDs.

Show the amount, reason, service period, statement/posting period, applicable
published treatment, linked original item and previewed impact. Submit the item
to the same work queue. Keep draft, reviewed, scheduled/posted and payment
evidence states understandable and distinct.

A payout request does not reduce payable. A credit is not a cash refund. Source
payment evidence comes through an adapter and a valid allocation; a free-form
“confirmed” checkbox must not stand in for execution evidence. The internal
prototype can retain explicit mock controls in development tools.

### Finance

Finance has two related jobs: cash matching and revenue-recognition visibility.
Show suggestions, operational associations, accounting applications and actual
cash execution separately. Recognition inputs, supplied treatment/schedules and
independent posted outcomes remain separate evidence. The full contracts and
linked synthetic examples are in [the integrated plan](THREE-AUDIENCE-PLAN.md).
This focused workflow supersedes earlier blanket exclusions of Finance screens;
Campfire/CLM stay mocked and Savvy continues to own commercial billing objects.

## Record proof and service lineage

Data lineage is a read-only operational evidence tool. Its entry points are a
source record, client/account, billing/statement line or processing issue. Search
and filters can include source, record type, service period, receipt time and
validation state. Every returned record must be inspectable; stage counts and a
handful of sample rows are not sufficient.

Opening a record traces upstream and downstream links:

| Step | Record proof | Service responsibility |
|---|---|---|
| Delivery / Bronze | Original bytes, source identity, arrival, revision, hash and accepted/rejected status | Network/external reporting adapter and immutable intake store |
| Normalization / Silver | Canonical observation or event, units, currency, subject mapping and raw parent reference | Ingestion/normalization and validation services |
| Terms / Silver | Dated assignment, candidates, selected rate/policy, eligibility reason and document version | Savvy policy API and binding phase of the shared engine |
| Calculation / Gold | Exact basis, assessment/rounding, dependencies, component result and completeness | The one deterministic billing interpreter |
| Publication | Selected result version, economic period and hourly/daily publication timestamp | Read-only dbt/reporting job; refresh does not add earnings |
| Billing / presentation | Obligation/invoice/credit or instruction reference, statement version, linked differences and independent payment application | Savvy billing and statement projection APIs |

For each edge, show which service owns the transition, its input/output contract,
validation outcome and available execution evidence. Distinguish a responsibility
or expected production service from a transition actually recorded by this
prototype. Do not invent job timestamps, successful integration calls or provider
confirmations. Missing execution evidence should be stated as missing.

The current local implementation uses Rails adapters/services, PostgreSQL,
the Ruby interpreter, dbt and the product API. Campfire remains a mocked accounting
handoff and CLM a mocked document/review link. Production service/deployment choices
are not decided by drawing the lineage map; no new spend is authorized.

Remove scenario selection, policy selection and “Evaluate selected evidence” from
this tool. Policy impact preview belongs to a proposed change; QA replay belongs
to development tools. Historical evidence/version selection can remain as a
clearly labeled as-known view, without pretending to create new billing activity.

## Acceptance for a later implementation

- Both commercial models use the same navigation and component system; applicable
  terms and money direction change the content.
- Overview has no automatically expanded client list. Large-book drilldown is
  searchable/paginated and does not require loading all records into the browser.
- No normal navigation control is named Case, Scenario or November workspace.
- No advisor-account hierarchy or inheritance is implemented while deferred.
- Terms can be understood without reading a graph. A change's scope, financial
  impact, reviewers and next action are visible together.
- One-time items are account-contextual and show their effect on the statement
  without confusing obligation creation with payment execution.
- Any displayed financial item can be traced to its underlying records and
  service responsibilities; history and missing evidence remain visible.
- Existing exact-money, versioning, cutoff, scope, review, source-reversal,
  concurrency and statement-conservation protections continue to pass.
- One engine/API policy changes, Savvy billing ownership, branding, inclusive UI
  dates and mocked Campfire/CLM boundaries remain intact.

Next step is to finish reviewing this information architecture and the primary
account/change journeys. This document does not authorize an automatic rebuild or
change the running prototype during the walkthrough.
