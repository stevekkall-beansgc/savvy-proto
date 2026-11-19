# Savvy billing design decisions

Savvy staff and brokers need to be able to explain a fee, adjustment, or payout
from its governing terms and source records. The prototype starts from an amount
someone sees on screen and makes the underlying calculation and evidence
available for review.

## Who we designed for

| Audience | Job | Design |
|---|---|---|
| Brokers under either product | Understand charges, earnings, terms, and payment status | Shared overview, statements, and agreement experience. Show the book first and let the broker drill into a client, account, or invoice line. |
| Internal Product | Explain a result and evaluate a commercial change | Follow records through the actual services. Compare proposed terms using the same inputs, then review and assign the policy through the API. |
| Internal Finance | Match cash and inspect revenue recognition | Follow a native claim through corrections, confirmed cash applications, and supplied mock accounting results. |

The two product examples have different billing parties and terms. The
affiliated advisor example bills the relevant client household. The independent
RIA example bills the firm for platform services, using its accounts as usage
evidence. Compensation is a separate commercial obligation. See the
[three-audience plan](THREE-AUDIENCE-PLAN.md) for the walkthrough feedback and
the decisions it changed.

## Why the system is structured this way

| Decision | Reason and consequence |
|---|---|
| **One engine with API-managed policies** | Both products need consistent monetary, rounding, and allocation rules. Compose rates, periods, eligibility, promotions, floors, and caps from supported operators in versioned policy data. Date assignments and bind review to the exact comparison and document version. Adding a new operator requires engine work. |
| **Retain original evidence, normalize it, bind terms, then calculate** | A later reviewer needs the exact inputs known at the time. Bronze retains source bytes and arrivals. Silver keeps versioned facts and dated policy assignments. Gold keeps detailed results and their input references. Statement and reporting projections summarize selected results at their declared grain. PostgreSQL-backed jobs retain attempts for replay, quarantine, and recovery. |
| **Keep commercial billing records in Savvy** | Invoice lines, credits, and payables need direct links to parties, services, policies, and calculation results so Savvy can explain and correct them. Campfire remains the proposed accounting boundary for mapped packages and supplied recognition outcomes. The CLM remains the proposed legal boundary for governing versions and review. Both are mocked in the prototype. |
| **Separate the commercial amount, confirmed cash, and recognition** | A corrected claim, a cash application, and recognized revenue have different dates, authorities, and evidence. Preserve issued originals and post linked corrections. Use independent cash evidence for applications and refunds. Finance reviews supplied recognition schedules and posting references. |
| **Treat one-time items as governed events** | Charges, credits, and compensation entitlements need the same source, approval, effective date, and calculation lineage as recurring items. An approved correction to an issued claim produces a linked document. A payout request records intent. Settling it requires an eligible payable and independently confirmed cash. Statements present the selected results and applications together. |
| **Make the evidence map work from either end** | A reviewer may only have a journal, invoice, source delivery, or report. The map shows the expected creation path and flags missing or dropped reporting dimensions. A single-record trace uses only the supplied fields and direct references. Related records and confirmed mappings are needed to verify additional links. |

[Ownership analysis](BILLING-OWNERSHIP-DEEP-DIVE.md) reviews when to reuse an
existing invoice model and how to handle a different issuer.
[Disclosure findings](SAVVY-DISCLOSURES-REVIEW-2026-11-16.md) explain why alternate
valuations, advance and arrears billing, and proration are worth testing. The
public disclosures describe client advisory practices. Confirm Savvy’s internal
schema, independent-RIA pricing, and individual commercial terms with Savvy.

## How the work was planned and checked

| Milestone | Scope and evidence |
|---|---|
| Define the product | [Walkthrough feedback](UI-WALKTHROUGH-FEEDBACK-2026-11-15.md) → [three-audience plan](THREE-AUDIENCE-PLAN.md) → [delivered experience and validation](VALIDATION-THREE-AUDIENCE.md). |
| Establish shared billing | [Shared billing plan](FOUR-CAPABILITY-PLAN.md) covers both products, policy composition, common source processing, and native billing documents. |
| Close the four priorities | [Completion contract](FOUR-CAPABILITY-CLOSURE.md) defines end-to-end product paths, commercial composition, durable processing, and corrections. [Closure evidence](FOUR-CAPABILITY-CLOSURE-VALIDATION.md) records the exercised cases and their limits. |
| Review real record shapes | The [evidence map guide](CAMPFIRE-TRACE.md) explains imports, field inference, previews, and the exportable gap list. A reviewer can start with any supported record and confirm links with Savvy. |

For an independent money check, start with the
[Finance worksheet](FINANCE-ACCEPTANCE.md). In the Harbor RIA example,
a $250 invoice and $90 credit yield $160 net billed. The $125 confirmed cash
application leaves $35 outstanding. Recognition is reviewed through its own
mock schedule and journal reference. Savvy Finance sign-off remains pending.

## Open discovery

- Confirm which existing Savvy objects own source facts, terms, invoice identity,
  and issuance. Use a redacted round trip from source through claim, cash, and report.
- Confirm Campfire mappings, recognition treatment, and authoritative journal
  references with Finance. Confirm agreement versions and approval roles with Legal.
- Advisor parent-child ownership and rollups are deferred. The demonstrated scope
  is synthetic and USD-only. Live connectors, production identity, signed
  agreements, and MCP/WebMCP remain future work.
