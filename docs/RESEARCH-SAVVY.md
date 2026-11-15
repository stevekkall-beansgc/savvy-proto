# Savvy: public research for an advisor earnings prototype

Research date: **2026-11-13**  
Status: **Public-source research and explicit prototype assumptions; no private-system verification**  
Companion: [Campfire research](RESEARCH-CAMPFIRE.md) · [Source register](SOURCE-REGISTER.json)

## Decision and scope

Build an advisor earnings forecast and explanation layer that combines operational asset data, client billing policies, advisor compensation agreements, and accounting actuals. Preserve the distinction between a projection, a contractual entitlement, an approved payable, a recorded payment, and reconciled cash.

This is discovery research under the repository's research-screening method. The question is which publicly documented business mechanics should shape an independent synthetic prototype. The strongest existing baseline is Savvy's integrated advisor platform plus Campfire's accounting and forecasting capabilities. The disconfirming evidence sought was an existing product capability that would make a new general-purpose forecast redundant, or billing mechanics that invalidate a simple AUM-times-rate formula. Both were found: Campfire already offers forecasting, and Savvy client billing is contract-dependent.

**Disposition:** advance to a bounded synthetic demonstration of advisor-specific calculations and ERP reconciliation. This research does not establish customer demand, forecast accuracy, access to Savvy systems, or production compatibility. The stop condition for this research unit is a source-backed model with explicit gaps, not an invented account configuration.

## Evidence classes

| Class | Meaning here |
| --- | --- |
| Public regulatory disclosure | A Savvy-authored filing or disclosure was retrieved. It describes disclosed practices, not every current individual agreement. |
| Public company statement | Savvy describes its product, workflows, or design practice. Treat performance and adoption claims as company claims. |
| User-provided context | The project owner supplied the fact; public sources did not independently confirm it. |
| Design inference | A proposed product or engineering response to the evidence. |
| Synthetic assumption | Invented values or policies used to make a demo work. |
| Unresolved | Requires an actual contract, mapping, policy, account configuration, or authorized source inspection. |

The project owner's statement that **Savvy uses Campfire ERP** is user-provided context. It is not public verification of the vendor relationship, installed modules, API access, or the contents of that ERP. The original private briefing is not reproduced in this repository.

## 1. Business and platform context

Savvy's public [RIA platform page](https://www.savvywealth.com/ria-platform) describes an in-house technology platform combined with compliance, billing, custodial relationships, operations, and marketing. It describes advisor payout economics as dependent on the advisor's book, without publishing a universal split. Its [independence page](https://www.savvywealth.com/independence) describes a revenue-sharing model, advisor control over client fee structure, and the ability to bring support staff. [SAVVY-01, SAVVY-02]

**Design inference:** model the practice, advisor compensation agreement, client fee agreement, household, and account as distinct records. A generic 80% share is a demonstration parameter, not a verified Savvy-wide rate. Similarly, support services being included in an offering does not establish whether a particular cost is firm-funded, reimbursed, or deducted from an advisor.

Savvy's [technology page](https://www.savvywealth.com/solutions/technology) describes an advisor dashboard, household reporting, CRM, client portal, documents, and service workflows. The platform is described as operating above custodians with a multi-custodian architecture. [SAVVY-05]

**Design inference:** earnings belong in an advisor/practice experience with household/account drill-down. Preserve the operational client identifier alongside any custodian account ID. Do not assume every household, account, custodian, and ERP customer has a one-to-one relationship.

The [disclosures page](https://www.savvywealth.com/disclosure) distinguishes the technology parent, Savvy Wealth Inc., from Savvy Advisors, Inc., the investment adviser. It also explains that some advisors use separate marketing trade names. [SAVVY-09]

**Design inference:** an advisor's display name or practice brand is not a reliable accounting entity key. Accounting entity and advisor/practice identifiers must be mapped explicitly.

## 2. Client billing mechanics that affect forecasts

The SEC-hosted [March 2026 Form CRS](https://reports.adviserinfo.sec.gov/crs/crs_318493.pdf) describes negotiated client investment-management fees generally between 0.3% and 1.9% annually, monthly or quarterly billing, advance or arrears timing, and agreement-dependent valuation bases. It also describes fixed and planning/consulting fees. These are **client fee terms, not advisor compensation percentages**. [SAVVY-03]

The [Form ADV brochure linked by Savvy](https://info.savvywealth.com/hubfs/Form%20ADV%20%2B%20CRS/Savvy-Advisors-ADV.pdf), dated March 31, 2026, adds household aggregation, prior-month/quarter ending balances or average daily balances, negotiated minimums, prorating of account starts/terminations, and return of unearned advance fees. Individual investment-management agreements govern the specific calculation. [SAVVY-04]

| Mechanic | Consequence for the prototype |
| --- | --- |
| Negotiated client fee | Store a versioned client fee policy; do not infer it from AUM alone. |
| Monthly or quarterly billing | Keep service period, invoice date, and expected cash date separate. |
| Advance or arrears | Today's market movement may affect a different billing period from the next payout. |
| Prior-period ending value or average balance | Implement only explicitly supported valuation bases and label others unsupported. |
| Household aggregation | Account-level fees may depend on a household total; avoid accidental double counting. |
| Starts and terminations | Use effective dates and a documented day-count policy. |
| Refund of unearned advance fees | Represent negative adjustments or credits without silently rewriting the original forecast. |
| Fixed/planning fees | Keep non-AUM revenue as a distinct supported input or explicitly exclude it. |

These implications are proposed modeling decisions. Public filings do not reveal which of these methods the intended prototype population uses, the exact day-count convention, tier structure, rounding policy, or when advisor entitlement becomes payable.

### Two different agreements

1. **Client fee agreement:** how the client is charged for advisory services.
2. **Advisor compensation agreement:** how eligible revenue and specified adjustments become advisor earnings.

Do not load a public client fee schedule as the advisor's split. Do not assume a Campfire revenue-recognition contract represents the advisor compensation agreement. Those relationships require evidence and mapping.

## 3. Public design and engineering guidance

Savvy's September 9, 2026 [design principles article](https://www.savvywealth.com/builders-blog-posts/the-5-principles-that-guide-design-at-savvy) emphasizes the complete service experience, clear human ownership in uncertain financial workflows, role-specific attention, consistent patterns, and contextual learning. It explicitly notes a move to neutral blue charts because green could imply positive financial performance. [SAVVY-06]

**Proposed UI decisions:**

- Lead with expected earnings, the covered period, and the date of the latest source data.
- Use a blue forecast chart; use color sparingly for explicit statuses and issues.
- Explain the path from client fees to advisor share to adjustments to expected payout.
- Let advisors inspect their own practice while finance sees mappings, exclusions, and reconciliation issues.
- Show who owns the next action when a fee rule or adjustment needs review.
- Use progressive disclosure for formula details rather than requiring the advisor to read a technical guide.

These choices align with public guidance; they are not a reproduction of an inspected private design system or advisor interface.

The September 10, 2026 [World Builders article](https://www.savvywealth.com/builders-blog-posts/savvy-world-builders) describes internal governed tools and server-side identity resolution for user-specific analytics. [SAVVY-07]

**Proposed implementation:** authorize the advisor/practice scope before returning data or calculating results. An AI explanation should receive the authorized calculation output, assumptions, and evidence references. A user-entered advisor ID or a natural-language claim about identity must not determine access.

An official [software engineering job listing](https://jobs.ashbyhq.com/savvy/c3589bc5-04c0-470d-a50d-2d38d4828710) advertises Rails, TypeScript, Next.js/React, SQL, GraphQL, and automated testing preferences. Search retrieved the listing text, while a direct open returned its JavaScript shell. [SAVVY-08]

**Limit:** this is a stack clue, not verification of the intended repository. A portable TypeScript or Python calculation core with explicit input/output contracts is more defensible than claiming exact codebase compatibility.

## 4. Proposed domain model

The following is a design inference, not a documented Savvy schema.

| Record | Required distinction |
| --- | --- |
| Advisor/practice | Stable internal identity, display identity, and authorized access scope. |
| Compensation-agreement version | Effective dates, eligible revenue basis, split, cost treatment, loan policy, payout cadence. |
| Client fee-agreement version | Valuation basis, rates, billing frequency, service scope, effective dates. |
| Household/account relationship | Ownership and assignment over time, including transfers between advisors. |
| Daily asset observation | Account, observed date, source, currency, value, and freshness. |
| Billing actual | Invoice/line identity, eligible fee amount, service period, accounting date, status. |
| Collection evidence | Payment allocation, cash versus non-cash classification, date, reversal/void state. |
| Expense/adjustment | Source evidence, service period, contract treatment, amount, approval state. |
| Loan schedule | Opening balance, principal/interest policy, payments, remaining balance. |
| Forecast snapshot | Input versions, scenario, as-of time, calculation version, result and exclusions. |

### Required amount/state distinctions

- **Projected client fees:** calculated from supported client billing rules and observed/future assumptions.
- **Projected advisor entitlement:** share and adjustments under an explicit compensation policy.
- **Approved payable:** finance approval exists; this is not implied by a successful calculation.
- **Recorded payment:** a source accounting payment entry exists.
- **Reconciled cash:** corroborating settlement/reconciliation evidence exists.

The UI may show these together, but they must not be summed as separate earnings or silently treated as synonyms.

### Expense policy

Every expense allocation should state one of: firm-funded, deducted before sharing, deducted after sharing, reimbursed separately, or unresolved. The policy determines the calculation. A vague description that a platform covers rent or staffing does not establish a chargeback rule. Avoid counting both a recurring forecast expense and its newly arrived ERP actual.

### Loan policy

Separate principal repayment, interest, opening balance, and remaining balance. A cash deduction is not automatically a reduction in recognized revenue. Any amortization, cap, floor, or carry-forward is a synthetic choice until the actual contract and accounting policy are known.

## 5. Safe synthetic demonstration

Use invented people, practices, accounts, contracts, and dollar amounts. Do not combine public advisor names with fabricated private economics.

| Scenario | Demonstration purpose |
| --- | --- |
| Simple percentage share | Show an illustrative split with an explainable fee-to-payout calculation. |
| Expense and loan arrangement | Show that cost ordering and principal repayment affect cash differently. |
| Different billing cadence | Show that current AUM changes and next payment timing are not interchangeable. |
| Actuals reconciliation | Compare a frozen estimate with billing, partial collection, credits, and revised costs. |
| Missing/stale input | Return a visible partial estimate or unresolved result instead of false precision. |

Suggested default assumptions must be visibly labeled: USD-only, explicitly supported billing bases, no market return in the base scenario beyond observed data, no automatic production posting, and loan/expense rules chosen only for demonstration. Scenario market changes are illustrative inputs, not investment predictions or calibrated confidence intervals.

## 6. Acceptance evidence for the bounded prototype

- Identical frozen inputs produce the same answer.
- The explanation reconciles arithmetically to the displayed payout.
- Before-split and after-split expenses produce the correct distinct answers.
- Effective dates and supported period boundaries are honored.
- Credits, partial payments, and voids do not inflate cash collections.
- Forecast and actual representations of the same fee/cost are not double counted.
- Unsupported fee methods and missing mappings are visible.
- AUM freshness, ERP freshness, and contract version are independently traceable.
- No successful synthetic test is labeled a completed Savvy or Campfire integration.

No forecast accuracy, economic uplift, or customer adoption claim follows from these checks. Such claims require a separately defined evaluation using authorized real observations and a held-out comparison.

## 7. Questions for eventual authorized discovery

1. Is the share based on earned fees, invoiced fees, collections, or another measure?
2. Where are client agreements and advisor compensation amendments maintained?
3. How are accounts/households assigned to advisors over time?
4. Which costs are funded by the firm, deducted, capped, or reimbursed?
5. What are the payout cadence, holdbacks, negative-balance and true-up policies?
6. How are loans tracked and reconciled?
7. Where does client billing originate, and what is mirrored to Campfire?
8. Does Campfire record advisor compensation through AP, payroll, journals, or a mixture?
9. Which dimensions identify advisor/practice and which mappings are missing?
10. What freshness and approval state is necessary before an advisor relies on the estimate?

## Source and review limitations

Sources were retrieved on 2026-11-13. Company pages can change and may contain marketing assertions. The regulatory disclosures are dated documents and do not replace individual agreements or establish every later business change. No private account, repository, client record, financial balance, or compensation contract was accessed. This report contains no hiring-negotiation material or copy of the private briefing.

The source register supplies ordinary URLs, publishers, retrieval dates, and claim classifications. The report preserves the evidence-to-design boundary; it is ready for implementation review, not owner acceptance or production qualification.
