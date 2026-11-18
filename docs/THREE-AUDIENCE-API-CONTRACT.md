# Three-audience API contract

15 November 2026. Extends the [medallion contract](MEDALLION-API-CONTRACT.md) and
[exported GraphQL schema](../contracts/schema.graphql). All data is fictional,
local and scoped by the existing simulated identity. This is not production auth.

## Published broker reads

| Query | Contract |
|---|---|
| `audienceSummary(caseId)` | Published run headlines, same-engine comparison and readable dated terms. No full run detail, statement lines or raw pipeline payload. |
| `audienceClients(caseId, search, limit, offset)` | PostgreSQL-filtered account list, total and paging metadata; no whole roster sent to the browser. |
| `audienceClient(caseId, clientId, limit, offset)` | Account-specific assessed results and paged canonical daily observations with `observation_total`. Firm-level amounts are not copied onto every account. |
| `audienceStatement(caseId, limit, offset)` | Published statement header and paged lines, exact basis/terms, underlying account links and internal source-record reference. |

`limit` is 1–100 (default 20); offsets are nonnegative. Monetary values cross the
GraphQL JSON boundary as integer minor-unit strings. The UI displays inclusive
last days; storage/API exclusive interval ends remain unchanged.

`AudienceReadModel#refresh!` publishes from the selected assessed run and existing
statement projection on writes. Reads select only required published JSON portions
in PostgreSQL and never invoke pricing or a full presenter. A baseline command and
its projection refresh share an outer transaction, so refresh failure cannot hide
a committed command. Identical current content reuses its publication. Policy and
read-model publications have separate discriminators; read publications cannot
establish policy chronology or approval.

## Internal evidence

`lineageRecords(caseId, search, limit, offset)` pages all retained scenarios for
that book plus its native billing objects and shared-table rates. The financial
totals never sum alternative scenarios. `lineageRecord(caseId, recordId, limit,
offset)` returns the selected record and paged transitions with `edge_total`,
`edge_limit`, and `edge_offset`.

Medallion record IDs are numeric strings. Native IDs use `obligation:ID`,
`invoice:ID`, `invoice_line:ID`, `instruction:ID`, `accounting:ID` or `rate:ID`.
Each is resolved within the current tenant/entity and book. Edges carry exact
record references, revisions, contracts, service responsibility, completeness and
evidence status. A calculation detail belongs to its run; its output ID is not a
standalone database record ID. Native schemas without a recorded clock report
no clock rather than fabricating one.

## Finance

`financeWorkspace(caseId)` is internal-only. Advisor outbound evidence is kept
separate from the fictional RIA service-invoice context. It never treats advisor
compensation as Savvy revenue. The RIA response has independently sourced payments,
invoice issuance, suggestions, associations, returns, accounting outcomes and
recognition records. Every source/package/schedule/posting keeps its own identity
and clocks.

`financeCommand(action, input, idempotencyKey)` supports:

- `FINANCE_BOOTSTRAP`: operator-only, empty input, isolated authored fixture.
- `FINANCE_ASSOCIATE`: Finance-only; payment/invoice IDs, currency, positive exact
  `amount_minor`, `posting_period` and reason. Requires explicit scoped suggestion,
  valid source timing and available balances on both sides.
- `FINANCE_REVERSE`: Finance-only; exact application ID, reason and unlocked
  posting period no earlier than the association. Does not refund cash or rewrite
  an accounting outcome.
- `FINANCE_MOCK_ACKNOWLEDGE`: Finance-only; exact authored $300 application. The
  retained response must match its source, invoice, active application set and
  known period. It is not a generic accounting calculator.

Cash associations do not change the recognition records. Schedules and independent
posted outcomes are supplied via the mock accounting boundary under explicitly
authored treatment. Missing outcomes remain missing. Changes to commercial terms
continue through the existing versioned-policy commands and shared interpreter.
