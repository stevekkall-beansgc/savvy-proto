# Savvy demo and architecture: three audiences

Delivered implementation: [milestone](THREE-AUDIENCE-MILESTONE.md),
[validation](VALIDATION-THREE-AUDIENCE.md) and
[independent review](THREE-AUDIENCE-FINAL-REVIEW.md). The plan below retains its
original review-stage wording; the later implementation authorization supersedes it.

Implementation authorization — 15 November 2026: the owner subsequently requested
Terra implementation, independent review and stress testing, with the preview on.
The planning-only text below records this document's original review boundary;
it no longer prevents the authorized implementation. Completion and validation
must be recorded separately rather than inferred from this plan.

15 November 2026. Reconciled by root after independent Astra and Sol reviews.
Planning only: no application, policy, data, permission, provider or runtime
changes are authorized or performed by this document.

This is the current audience and experience contract. It incorporates the
[walkthrough feedback](UI-WALKTHROUGH-FEEDBACK-2026-11-15.md). Earlier technical
plans remain useful for calculation/history invariants; their separate external
product experiences, generic Internal audience, scenario-runner pipeline and
blanket exclusion of Finance workflows are superseded here.

## Who we are building for

“Clients” in this audience definition means brokers/firm users under either
product. Their own customers are called **underlying clients/accounts** below.

| Audience | Core job | Demo success |
|---|---|---|
| Clients: brokers under each product | Understand their business's economics, governing terms, money due to/from them and payment status | One clear book overview; deliberate drilldown to a statement line, underlying client/account and readable calculation basis. Identical navigation under both products. |
| Internal Product | Understand and explain the system, demonstrate commercial flexibility and see a polished product | Follow an actual result through records/services; propose an ordinary deal change through the API; explain its impact without showing code or inventing execution history. |
| Internal Finance | Match expected economics to cash operations and understand revenue recognition | Find unresolved cash/application items and recognition exceptions; inspect linked evidence, authoritative outcomes and the next required action in one context. |

Product and Finance are distinct internal jobs and permissions over shared
records. They do not get separate pricing implementations or separate copies of
commercial truth.

## Experience and navigation

**Client shell:** Overview, Clients, Statements, Agreements. Product subscriptions
and the commercial relationship change applicable content, not the shell.
Overview is book-level; it does not expand every underlying client or balance
record. Search and server-side pagination lead to detailed accounts and history.
Amounts due in different directions, entities or currencies remain distinct.

**Internal shell:** Accounts, Work queue, Finance, Data lineage. Product normally
starts with an account and its business terms; Finance starts with its period and
exception queue. The architecture/service map lives with Data lineage as useful
explanatory context. These are proposed labels, not four new independent systems.

Every relevant page carries a consistent business/account, legal entity, product,
period, currency and freshness context. Account selection means a business being
inspected. Case/Scenario/November controls and selectable demo roles stay outside
normal navigation. Presenter controls do not grant real permissions.

The advisor parent–child account model remains explicitly **deferred**. Do not
derive legal responsibility, rate inheritance, guarantees, access or billing
rollups from a visual tree. This decision is not a prerequisite for the other work.

## Client experience

Lead with the applicable economics and next action: compensation, charges,
qualified credits, amounts due, confirmed applications and pending items. The
same components support either product and a business using multiple products.
Client advisory fees and advisor compensation are separate agreements/economics.
Internal accounting recognition is not another client balance or compensation
eligibility rule unless the commercial agreement explicitly makes it relevant.

Keep agreed, scheduled and historical terms understandable. Each statement line
can explain its service period, selected terms, basis and changes. Detailed daily
balances and per-client amounts open only on demand. Value comparisons use the
same engine and frozen facts, name their baseline and exclude payment execution
as a fabricated commercial benefit.

Design acceptance includes consistent hierarchy, meaningful labels, useful loading/
empty/error states, accessible controls, mobile layouts and complete drilldowns.
Stage counts, raw identifiers and large tables are not substitutes for product
clarity. Preserve Savvy branding and inclusive displayed dates.

## Internal Product: understandable configuration and proof

Terms start with **Current, Scheduled, History**. An account's “Propose a change”
action guides the user through the affected component, supported parameters,
effective dates/scope, reason and same-input financial impact. The graph is
advanced detail. Simplifying the form does not narrow commercial optionality or
introduce pricing formulas in the UI.

The proposal joins the Work queue. Its detail contains old/new terms, component
effects, required reviewers, linked document and next action. Reviews bind exact
policy, comparison, source, document and interpreter versions. Publication and
assignment remain explicit stages. A bonus offset by a lower guarantee must show
both component changes even when the final total is unchanged.

“Add one-time item” begins on an account, statement or original line. Purpose,
available published treatment and account context determine the parties and
relevant fields. Show service and statement/posting periods, amount, reason,
linked correction and previewed effect. It uses the same Work queue. Standalone
generic Approvals and Adjustments destinations are removed from the proposed UX.

## Internal Finance: two related jobs

### Cash matching

Present independent cash evidence alongside eligible invoices, obligations and
instructions. Support inbound client/network money and outbound advisor payments
with explicit direction. Show suggestions, confirmed operational associations,
provider-reported accounting applications, residuals and exceptions as distinct
states. A suggestion is not an application; an application is not a bank transfer.

The focused workflow is inspect → propose/confirm a scoped allocation → see
handoff/acknowledgment and remaining exceptions. Support partial and multiple
applications, unmatched cash, gross/fee/net evidence, returns and linked reversals.
Multiple observations of the same payment are linked rather than counted again.
Source IDs, legal counterparties and currency constrain matching; amount equality
alone is not sufficient proof.

An operator's local association must not directly set Campfire AR, mark a bank
transfer executed or create a journal. Any accounting application/acknowledgment
in the demo comes from an explicitly mocked accounting response. No payment
initiation, bank-feed administration or general collections suite is introduced.

### Revenue recognition

Finance gets its own view of recognition inputs, supplied treatment/schedules,
reported outcomes and exceptions. Use separate measures for commercial estimates,
assessed amounts, invoices, cash, applications, recognition schedules and posted
recognition. Name whose “earned” amount is being shown. Advisor compensation
payable is not Savvy revenue; fee minus compensation is not automatically revenue
or profit.

Finance defines recognition timing, allocation, gross/net presentation, mapping,
credit/amendment treatment and posting/closed-period rules. The demo does not
select an accounting policy from the product name, invoice date or cash receipt.
Unbilled/deferred amounts and roll-forwards appear only when the required treatment
and evidence are supplied; otherwise they remain unknown or need review.

Use three linked contracts:

| Contract | Required proof |
|---|---|
| Recognition input package | Stable ID/revision; entity/currency; selected commercial result and invoice/credit line references; exact allocated amounts; service/performance evidence and periods; agreement/policy version; Finance treatment/mapping reference; cutoff and missing decisions. |
| Recognition schedule/result evidence | Source and mock marker; ID/revision; input-package reference; treatment version; recognition periods and exact amounts; proposed/scheduled/reported classification; effective/as-of/received clocks; supersession/correction links. |
| Posted accounting outcome | Independent source-reported journal/posting identity, accounting period, entity/currency, exact amounts and status; result/input references; revision, timestamps and reversal/replacement links. |

Schedules/results are supplied through the mock accounting boundary under an
explicitly authored fictional Finance treatment. No new recognition calculator
in the UI, dbt or a product-specific service is introduced. The single billing
engine supplies commercial economics; a returned recognition schedule does not
recalculate that pricing or overwrite it. A proposed handoff or acknowledgment
alone cannot be displayed as posted recognition.

This restores a useful Finance workflow while keeping Campfire's intended
accounting role. It does not reinstate the earlier broad settlement/reconciliation
desks, a journal editor, accounting close tooling or an ERP replacement.

## Shared architecture and service responsibility

Keep the existing stack. A named service below is a responsibility and contract,
not a requirement for a new deployment or paid microservice.

| Responsibility | Owner / boundary | Records and output |
|---|---|---|
| Intake and original evidence | Savvy adapters; network/external, payment and accounting inputs remain separately sourced | Bronze originals, every arrival, rejected/duplicate/revised evidence and source clocks |
| Normalize, map and validate | Savvy normalization/validation services | Scoped Silver facts, identities, units, completeness and original links |
| Commercial policy lifecycle | Savvy API; linked mock CLM references | Versioned terms, rates, assignments, proposals and exact reviews |
| Bind and calculate | One deterministic billing interpreter | Applicable terms, exact commercial components, assessment and dependencies |
| Persist and publish | Savvy Gold store; read-only dbt jobs | Immutable detailed results and selected hourly/daily publications; no pricing or issuance in dbt |
| Commercial billing and statements | Savvy's data layer and APIs | Obligations, invoices/credit lines, custodial/payout instructions and derived statement versions |
| Cash association/application visibility | Savvy Finance read model and governed association workflow; execution/accounting source retains authority | Suggestions, allocations, provider acknowledgment, residuals and reversal history |
| Recognition handoff and returned evidence | Finance-approved input package → mocked accounting adapter | Supplied schedule/result and independent accounting outcomes linked to Savvy commercial lines |
| Product and Finance presentation | Scoped APIs over those same records | Shared broker experience, Product proof/configuration, Finance matching/recognition |

The medallion path includes accounting and cash observations as independently
sourced facts with provenance. Joining them to commercial results does not make
invoicing, cash and recognition sequentially equivalent states. They are separate
timelines linked by identity and explicit allocations.

CLM and Campfire remain mocked. Do not claim their tenant configuration or live
behavior has been verified. Reuse actual Savvy billing objects and integration
owners when discovered; this prototype's schema is not proof of Savvy's schema.

## Data lineage: proof of every record

Replace the scenario runner with a searchable, paginated internal record explorer
reachable from an authorized internal/support view of a relevant client statement
line, billing item or Finance exception. External users receive readable explanations
without access to the raw internal explorer.
Trace raw delivery → canonical fact → term assignment → calculation → publication
→ commercial object, with branches to cash applications and accounting/recognition
evidence where applicable.

Every edge shows input/output identities and revisions, contract/schema version,
responsible service, validation/completeness and actual execution evidence when
recorded. Mark implemented local processing, mock handoff, expected production
responsibility and missing evidence distinctly. An architectural arrow is not
proof a job ran.

The explorer includes rejected, duplicate, reversed and superseded evidence with
appropriate scope. Complete pagination must permit inspecting a non-featured
record; sampled JSON and success counters do not satisfy this requirement.
Historical/as-known views remain read-only. Policy previews belong to a change;
QA replay tools remain outside the normal product.

Overview reads published summaries and fetches bounded detail on demand. It must
not load or recalculate the whole book on each page view. Calculation partitioning
must preserve cross-account caps/floors, exact basis and assessment boundaries;
a screen's pagination must never define a financial aggregation group.

## A coherent demo and acceptance story

1. **Client:** open a book overview, search for one underlying client/account and
   explain a statement line, terms and payment status. Open the other product's
   broker business in the identical shell; applicable economics change.
2. **Product:** open that exact line internally and follow its records/services.
   Select a non-featured record to prove the explorer is complete.
3. **Product:** propose a supported API-only term change, inspect same-input
   impact, review/document binding and scheduling/assignment. Show an offsetting
   bonus/guarantee example. No deployment or UI pricing formula changes the deal.
4. **Finance cash:** follow the linked commercial object to received or paid cash,
   inspect a partial/multiple application and unresolved residual, then a reversal.
   Confirm which state is local and which is returned by the accounting mock.
5. **Finance recognition:** inspect the same commercial inputs, the supplied
   treatment/period schedule and independent posted outcome. Show one missing
   outcome and a linked credit requiring treatment rather than silently rewriting
   recognition. Return to the broker statement without exposing internal tools.

A compact additional Finance fixture should make timing differences obvious.
For example, **only under a fixture-authored Finance treatment**, a $1,200
billed-in-advance service invoice has a supplied three-period $400/$400/$400
schedule. Assume one debtor, legal entity and currency, no other receivables,
credits or adjustments, and an independently mocked initially posted $1,200
invoice. A $900 cash
receipt has $600 applied and $300 unapplied; reported AR is $600 at that point.
The accounting mock reports first-period recognition $400 and deferred $800.
Applying the remaining $300, followed by a mock accounting response confirming
the application and reported AR, makes
reported AR $300 while cash remains $900 and recognition remains $400. A later
credit opens a treatment/correction exception and preserves prior journal evidence.
These are synthetic supplied accounting facts, not a recommended recognition
policy or a schedule computed from cash by the prototype.

A separate supplied unbilled fixture uses an explicit fictional treatment with
$100 reported recognized before invoicing and $100 reported unbilled. Later billing
reclassifies the supplied balances without creating another $100 of revenue.
The accounting mock supplies both periods' outcomes; the prototype does not infer
them from billing dates.

The fixture must link the same commercial, cash and accounting identities across
the views. It belongs in a new isolated namespace/period; existing September and
November proofs are retained. Recognition unknown stays unknown; billed-in-advance
and unbilled/service timing cases need distinct expected outcomes when supplied.

## Acceptance gates by audience

- **Clients:** identical shell for both products; book-first landing; bounded
  search/drilldown; readable terms/calculation basis; distinct money directions;
  no internal record/run controls or a client list loaded wholesale.
- **Product:** supported ordinary terms change via API data and one engine;
  same-input impact and stale-review rejection; exact source/result/service proof;
  polished desktop/mobile and useful empty/error states.
- **Finance cash:** partial/multiple matching, unapplied cash and reversals conserve
  amounts; suggestions/associations/applications/execution remain distinguishable;
  no cross-entity/currency leakage or duplicate counting of one movement.
- **Finance recognition:** input package, supplied treatment/schedule and posted
  evidence are separate; billed-in-advance and unbilled timing examples and one
  missing outcome are visible;
  cash matching does not change recognition under the fixture's unchanged treatment;
  corrections preserve history and obey the declared posting-period decision.
- **Shared:** refresh/replay creates no extra earnings, invoice, cash or journal;
  estimates and finalized results supersede rather than add; no summed duplicate
  representations; billing stays in Savvy; Campfire/CLM remain mocks; no new spend.
- **Deferred:** no advisor-account parent–child model or inheritance is implemented.

## Implementation sequence and decisions

1. Confirm these audience jobs and shared account context; sketch overview,
   account detail, change request, Finance and record-detail journeys.
2. Define scoped summary/drilldown, record/edge and Finance read-model contracts.
   Keep accounting treatment fields explicit and preserve current engine contracts.
3. Build the shared client shell and contextual terms/change workflow.
4. Build complete record/service lineage and the focused Finance matching and
   recognition views using the linked synthetic fixtures.
5. Review design with each audience's walkthrough; rerun financial, permission,
   source/correction, history and large-book paging checks before any rollout.

Actual recognition policy, principal/agent gross-versus-net treatment, source
authority, posting route and production matching permissions need Finance/system
owner discovery before real integration. They do not block a clearly authored
mock demonstration. The deferred hierarchy is not reopened as a prerequisite.

## Review findings and public-source boundary

Both Astra and Sol identified the same gaps: shared client UX, a conflated Internal
audience, incomplete record-level proof and missing recognition functionality.
Both reviewed this integrated plan and found no blocking ambiguity. Their final
refinements clarify the Finance fixture, explicit accounting confirmation, internal
lineage access and the supplied unbilled timing example.
The current implementation has accounting observation fields but no complete
recognition package/schedule/outcome lifecycle. This plan does not mark it delivered.

Campfire's public API documentation separately describes invoice-payment records
and revenue transactions, including period and recognition fields. This supports
investigating distinct adapter contracts, not assuming identical status semantics
or a verified Savvy integration. See [List Invoice Payments](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoice-payments)
and [List Revenue Transactions](https://docs.campfire.ai/api-reference/revenue-recognition/list-revenue-transactions),
checked 15 November 2026. No authenticated tenant call or provider write was made.
