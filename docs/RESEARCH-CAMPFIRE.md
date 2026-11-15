# Campfire: platform and integration research

Research date: **2026-11-13**  
Status: **Official documentation reviewed; no credentials, account access, or live API validation**  
Companion: [Savvy research](RESEARCH-SAVVY.md) · [Source register](SOURCE-REGISTER.json)

## 1. What is known, and why it matters

The project owner reports that Savvy uses Campfire ERP. That is **user-provided context**, not independently verified public evidence of the relationship. The selected modules, tenant, chart of accounts, data coverage, permissions, and integration configuration remain unknown.

Public Campfire documentation supports an integration design that reads accounting evidence while a separate deterministic engine handles advisor-specific earnings rules. The useful distinction is projected fees, advisor entitlement, approved payable, recorded payment, and bank-confirmed cash. A generic invoice total, an amount marked paid, and recognized revenue are not interchangeable inputs.

This is discovery research, not a live integration report. Its bounded result is a verified public interface map, explicit data-model assumptions, and a safe offline adapter design. The strongest baseline includes Campfire's existing forecasting and revenue automation products; a prototype must add advisor-specific value rather than claim those capabilities are absent.

## 2. Capability map

| Area | Publicly documented capability | Relevance and limit |
| --- | --- | --- |
| Core accounting | General ledger, entities, currencies, approvals, audit history, reports and drill-down. | Read posted accounting facts; do not infer Savvy's enabled modules or policy. |
| AP | Bills, vendors, expense accounts, dimensions, payments and voids. | Potential cost/approved-payable evidence; exact advisor mapping is unknown. |
| AR | Customers, invoices, products, optional revenue contracts, payments and credit memos. | Read actual billings and allocation evidence without conflating them with cash. |
| Revenue automation | Revenue contracts and schedules across several billing models. | Relevant to client revenue if used; not necessarily advisor compensation contracts. |
| Cash/reconciliation | Bank transactions and reconciliation reports/matches. | Possible corroboration of payment settlement, separate from invoice state. |
| Reporting | Financial statements, dimensions, budgets, custom reports and aging. | Useful for totals and completeness controls; avoid posting duplicate accounting. |
| Forecast | Posted actuals, scheduled commitments, and estimates with explanations. | Existing company-level functionality; advisor contract/AUM forecasting remains a distinct domain. |

Sources: [Core accounting](https://campfire.ai/core-accounting) [CF-01], [Revenue automation](https://campfire.ai/revenue-automation) [CF-02], [Forecast](https://campfire.ai/forecast) [CF-03], [official API index](https://docs.campfire.ai/llms.txt) [CF-04]. Product pages describe vendor capability and are not evidence of account-specific implementation.

### Forecast is already a product

Campfire's [Forecast page](https://campfire.ai/forecast) separates posted GL facts, future amounts committed by subledgers, and the estimated remainder. The page says assumptions can be inspected. It does not establish that this feature calculates advisor revenue shares, that Savvy uses it, or that it is exposed through a public Forecast endpoint. No such endpoint was identified in the index reviewed. [CF-03]

**Design inference:** build the domain calculation and reconciliation layer; preserve the same distinction between actuals and assumptions. An advisor's current asset base and negotiated share need not be represented in the ERP's forecast model.

## 3. Data model and mapping

The [AP guide](https://docs.campfire.ai/guides/accounts-payable) links bills to vendors, entities, expense accounts and optional departments/dimensions. The [AR guide](https://docs.campfire.ai/guides/accounts-receivable) links invoices to customers, entities, products and optional contracts. The [journal guide](https://docs.campfire.ai/guides/journal-entries) describes journal transactions with accounts, entity/currency, debit/credit amounts and optional dimensions. [CF-07, CF-08, CF-09]

The prototype should maintain explicit cross-system mappings rather than equate similar names:

| Operational concept | Possible Campfire representation | Status |
| --- | --- | --- |
| Client/household | Customer and possibly invoice-level attribution | Mapping assumption; must be verified. |
| Advisor/practice | Vendor/payee, department, tag or a combination | Mapping assumption; do not pick silently. |
| Client fee agreement | Revenue contract if that module contains it | Possible mapping, not automatic. |
| Advisor compensation agreement | External versioned rule set, unless evidence shows otherwise | Keep distinct from revenue contracts. |
| Advisor-attributable costs | Bill/GL line with verified dimension mapping | Must avoid double counting bill and GL representations. |
| Approved compensation payable | Bill, payroll liability or journal, depending on policy | Unknown for Savvy. |
| Payment | Allocation record plus corroborating cash evidence | Recorded payment alone is not bank settlement proof. |

Store source IDs as strings in the normalized domain, names as display fields, and currency with every amount. Use decimal arithmetic and explicitly convert currency amounts to internal minor units if needed. The documentation does not establish that all raw monetary fields are integer cents; some schema/examples use numbers or strings.

## 4. Authentication, authorization, and limits

The [quickstart](https://docs.campfire.ai/quickstart) requires an active Campfire account to create API users and keys. Direct API-key authentication is `Authorization: Token <key>`. API-user roles are admin (all APIs), clerk (read plus draft-entry capability), and view only (GET APIs). The published limit is **10 requests per second per API user**, shared across endpoints. A `429` supplies `Retry-After`. [CF-05]

For a future internal reader, use an authorized view-only identity and keep the key on the server. For this prototype, the adapter stays offline with synthetic source payloads. An interface matching a provider does not establish a connection to that provider.

The [OAuth app guide](https://docs.campfire.ai/guides/oauth-apps) describes admin app registration, user/workspace consent, scoped Bearer tokens, one-hour access tokens and 30-day refresh tokens. Effective access is the intersection of user permissions and granted scopes. Rate limits are 10 requests/second per connection. OAuth app availability may need enabling for a workspace. [CF-06]

**Design inference:** OAuth is relevant to a reusable multi-customer product; a small read-only internal adapter can use an API key. Do not implement either authentication flow merely to demonstrate synthetic calculations. No account or consent was created during this research.

### GET-only is not a sufficient side-effect boundary

The [invoice list reference](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoices) documents `download=true` as an async export workflow that sends email. A read adapter must allowlist both paths and parameters. Omit export/download flags and any route that generates or sends communications. [CF-12]

## 5. Verified public read paths

Base used by official examples: `https://api.meetcampfire.com`.

| Operation | GET path | Official reference |
| --- | --- | --- |
| GL transactions | `/coa/api/transaction` | [List Chart Transactions](https://docs.campfire.ai/api-reference/core-accounting/list-chart-transactions) [CF-10] |
| Journals | `/coa/api/journal_entry` | [List Journal Entries](https://docs.campfire.ai/api-reference/core-accounting/list-journal-entries) [CF-11] |
| Invoices | `/coa/api/v1/invoice` | [List Invoices](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoices) [CF-12] |
| Invoice allocations | `/coa/api/v1/invoice-payments` | [List Invoice Payments](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoice-payments) [CF-13] |
| Bills | `/coa/api/v1/bill` | [List Accounting Bills](https://docs.campfire.ai/api-reference/accounts-payable/list-accounting-bills) [CF-14] |
| Bill allocations | `/coa/api/v1/bill-payments` | [List Bill Payments](https://docs.campfire.ai/api-reference/accounts-payable/list-bill-payments) [CF-15] |
| Revenue contracts | `/rr/api/v1/contracts` | [List Contracts](https://docs.campfire.ai/api-reference/revenue-recognition/list-contracts) [CF-16] |
| Reconciliation reports | `/coa/api/v2/reconciliation` | [List Bank Reconciliation Reports](https://docs.campfire.ai/api-reference/bank-reconciliation/list-bank-reconciliation-reports) [CF-17] |

These paths were documented, not called with credentials. Verify version-specific payloads against the actual tenant before implementation beyond a mock. Avoid constructing unverified endpoints from naming patterns.

## 6. Exact payment fields and cash classification

The invoice-payment reference shows a paginated envelope with `count`, `results`, `next`, and `previous`. Its example record contains the following fields. [CF-13]

| Field | Normalization use |
| --- | --- |
| `id` | Source allocation identity; namespace with tenant/provider. |
| `invoice_id`, `invoice_number` | Invoice linkage and human-readable reference. |
| `amount`, `currency` | Decimal allocation amount and currency. |
| `payment_date` | Allocation/payment date; distinct from data availability. |
| `payment_type` | Preserve verbatim; classification requires explicit mapping. |
| `source`, `external_id` | Provenance and upstream correlation. |
| `voided_date` | Set for voided allocations; do not count them as active collections. |
| `created_at`, `last_modified_at` | Source timestamps for sync and reproducibility. |

The retrieved official example contains `payment_type: CREDIT_MEMO`; a complete enum, including a definitive `CASH` value/meaning, was **not verified**. Unknown types must not default to cash. A synthetic fixture may have a configured internal cash classification, but it must not claim that classification is a validated provider enum.

Bill-payment examples use `id`, `bill_id`, `bill_number`, `amount`, `currency`, `payment_date`, `source`, `source_id`, `voided_date`, `created_at`, and `last_modified_at`. [CF-15]

**Design inference:** represent three independent concepts: allocation recorded, economic classification established, and settlement corroborated. A credit memo can reduce an invoice balance without new cash. Even an allocation classified as cash does not by itself demonstrate bank settlement. A void removes an active allocation; preserve its history rather than deleting the evidence silently.

For collections-based advisor policies, compute eligible cash from explicit allocations and exclusions. Never infer collections by adding an invoice's cumulative paid amount to its payment rows, and never treat invoice face value as collected.

## 7. Pagination, incremental sync, and deletions

### GL

The GL list supports `limit`/`offset`, with default limit 100 and documented maximum 10,000, date/dimension filters, and `last_modified_at__gte`/`last_modified_at__lte`. `include_deleted=true` returns **only deleted records**, not active plus deleted. Process separate active and tombstone streams. The documented default start date is six months ago, so choose the intended history explicitly. [CF-10]

### Invoice and bill payments

Payment references support cursor mode: send `cursor=` first and follow the opaque `next` URL. Incremental filters use source modification timestamps, including `last_modified_at__gte`. Omitted void filtering includes active and voided payments; `voided_date` identifies reversals. Invoice payments are documented as ordered by modification time and ID. [CF-13, CF-15]

### Invoices

The invoice reference supports limit/offset pagination, entity/client/contract filters, invoice-date filters, paid-date filters, and line tags. Do not assume every list has the same cursor or change-tracking contract. [CF-12]

### Proposed reader behavior

These are implementation recommendations:

1. Freeze an extraction cutoff and page through a bounded request.
2. Namespace records by tenant, provider, object type and source ID.
3. Persist a watermark only after all relevant pages commit successfully.
4. Overlap incremental windows and upsert to handle equal timestamps or retries.
5. Follow pagination links only on the permitted origin/path; retain opaque cursors.
6. Rate-limit with bounded concurrency and honor `Retry-After`.
7. Keep voids/deletions and re-run impacted periods.
8. Record fetched-at and source-modified-at separately.
9. Check totals against a relevant source report; a successful HTTP response is not proof of complete data.

## 8. Webhooks

The [official webhook guide](https://docs.campfire.ai/guides/webhooks) covers invoices, bills, journal entries, contracts, and credit/debit memos. Admin access is needed to manage subscriptions. Payment increases, including partials, produce `.payment`; full-payment transitions produce both `.payment` and `.paid`, without an additional `.updated`. Deliveries can duplicate or arrive out of order. [CF-18]

Payloads carry topic, object state, changes, and a subscription UUID. Deleted-object payloads contain the ID. The UUID identifies the subscription, not a unique event. HMAC-SHA256 signs timestamp plus raw body; the guide recommends a five-minute replay tolerance. Failed deliveries retry up to five times, except 404. [CF-18]

**Proposed handling:** verify raw bytes, enqueue promptly, and refresh/upsert the authoritative object. Do not increment money once per event. Persist processing evidence and use periodic reconciliation polling to recover missed or out-of-order events. The current offline prototype does not register any webhook or expose a live receiver.

## 9. Reports, revenue schedules, and reconciliation

The official index lists balance sheet, income statement, cash flow, trial balance, general-ledger and custom-report APIs, plus reconciliation and revenue-schedule resources. The [MCP guide](https://docs.campfire.ai/guides/ai-integration) also describes report, budget, contract and aging access. [CF-04, CF-19]

**Design inference:** use report totals as completeness controls, and source lines as calculation evidence. A financial statement's recognized revenue may differ from billed, collected, and eligible-for-share amounts. If a fee is represented as an invoice and a journal, link the representations; do not sum them as two revenues. Likewise, a bill and its GL expense are not two costs.

A reconciliation report can support cash verification only if the relevant payment is traceably matched. The existence of a report for a period does not prove a particular advisor was paid. No source reviewed establishes Savvy's actual settlement process or how it distinguishes payroll from contractor/AP payments.

## 10. OpenAPI, SDK, MCP, and environment gaps

### OpenAPI

The [official documentation index](https://docs.campfire.ai/llms.txt) publishes this schema location:

`https://api.meetcampfire.com/api/schema?format=json`

The browsing tool could not retrieve that schema during this research. The URL is documented; the bytes/version were not downloaded or validated. The endpoint reference pages were accessible. [CF-04]

### SDK

No official maintained Python or TypeScript SDK was verified in the reviewed official sources. Search results include unrelated Campfire products and third-party API descriptions. Do not use Basecamp Campfire chat documentation, campfire-net agent tooling, or a third-party OpenAPI collection as this ERP's official contract. A small typed adapter is sufficient until the actual schema and license are verified.

### MCP

Campfire documents a hosted endpoint, `https://api.meetcampfire.com/mcp`, with tools for accounts, transactions, company objects, statements, budgets, contracts and aging. It describes authenticated organization-scoped calls. [CF-19]

The [MCP store announcement](https://campfire.ai/blog/campfire-is-the-first-erp-with-an-mcp-store) concerns tools available to Ember inside Campfire. That is distinct from an external assistant accessing Campfire's hosted MCP server. [CF-20]

**Design inference:** keep arithmetic and contract application deterministic. An optional assistant can explain governed results or help investigate mappings, but should not silently create accounting entries or infer missing contractual rules.

### Sandbox

A self-service sandbox signup, a separate sandbox API host, and tenant-specific test credentials were not verified in reviewed official documentation. Availability remains an access question. Sample payloads and a local mock are not a Campfire sandbox. No authenticated endpoint call, write, export, email, or payment action occurred in this research.

## 11. Recommended adapter boundary

Keep the provider adapter separate from the forecast engine:

- **Inputs:** supplied synthetic Campfire-shaped records or, later, authorized read results.
- **Responsibilities:** schema normalization, provenance, mapping, active/void state, decimal conversion, pagination metadata and explicit unknown classifications.
- **Outputs:** immutable billing facts, payment allocations, attributed costs and source-quality issues.
- **Excluded responsibilities:** defining advisor agreements, authorizing users, posting forecasts, marking invoices paid, executing payments, modifying reports, or sending exports.

The adapter should reject or quarantine unmapped currencies, ambiguous payment types, missing source IDs, inconsistent invoice links, or unsupported amount representations. Synthetic normalization checks establish only local behavior.

## 12. Remaining discovery questions

1. Which Campfire tenant/entities/modules are relevant?
2. Is client billing native, imported, or summarized through journals?
3. Are advisors vendors, employees, dimensions, or several representations?
4. Which fields reliably identify practice, household and service period?
5. What payment types and void behavior appear in actual authorized responses?
6. How is settlement reconciled to accounting allocations?
7. Are API scopes, webhooks, OAuth apps, and a sandbox available?
8. What historical coverage and close/reopening policies apply?
9. Does the existing Campfire Forecast feature already satisfy part of the intended experience?
10. Who approves the boundary between estimate, approved entitlement and payable?

These questions define the gap between a working synthetic prototype and a supported live integration. They do not prevent the local demonstration from being built and reviewed.
