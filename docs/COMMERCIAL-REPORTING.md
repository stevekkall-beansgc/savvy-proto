# Commercial terms and daily reporting: first vertical slice

This independent synthetic prototype explores a reusable contract-to-reporting layer. It is not Savvy's system, an accounting ledger, a production billing engine, or an ERP integration.

## Target architecture

Savvy's published engineering roles describe Rails, React/Next.js, PostgreSQL and GraphQL. A possible future architecture is React/Next.js for review and reporting; a Rails/GraphQL service for authorized contract and report access; PostgreSQL for versioned contracts, immutable source evidence, input and run records; and a background scheduler/worker for daily batches. These are design options, not an inspection of Savvy’s actual repository or a decision to implement them. This repository currently implements the experiment in Python and SQLite; those production components have not been built or tested. Source: https://jobs.ashbyhq.com/savvy/adc5d0c4-0944-49a0-8cf4-aaf573dda8cb

1. **Receive:** retain the original source configuration and identity, without claiming that arbitrary file formats or documents are automatically parsed.
2. **Map and review:** attach client-specific display text to each clause and explicitly map it to a supported, versioned commercial mechanism and parameters. Unknown mechanisms are retained as `review_required` and cannot be projected. Human approval, document extraction and a mapping UI are future work.
3. **Version:** bind each reporting run to an immutable contract version, effective period, clause, source and hash. A change creates a new version. This slice requires an explicit version covering the full reporting period; it does not automatically resolve amendments spanning a period.
4. **Project:** run a daily batch using a dated input snapshot and create separate output rows for each clause. The implemented mechanisms are a fixed period charge and basis points of an explicitly provided period basis. A rate is not inherently annualized, prorated, an AUM fee, or an advisor share. Scenarios are estimates, not invoices.
5. **Realize:** retain revised invoice, credit and cash observations by source, ID, revision and observation date. A dated actuals batch classifies invoice and credit activity as billing and cash separately. A voided invoice is not proof of a cash refund. Events are synthetic input records, not authoritative accounting data.
6. **Report:** stable dimensions include contract, clause, period, currency, source, version, as-of date and classification. Forecast and actuals remain separate snapshots. Actuals are not fed back into contractual terms automatically: reconciliation, finance approval and explicit contract amendments are needed before any configuration changes.

## Run

`python3 -m unittest discover -s tests -v` executes the reporting and original forecast tests. `commercial_reporting.store.Store` accepts a SQLite file path for persistence; default is an in-memory database. `Store.project` and `Store.actuals` perform explicit batches. There is no scheduler or import UI. Run IDs are idempotent for identical input and reject changes; a refreshed snapshot requires a new run ID.

## Boundaries and next steps

- Design and validate real ingestion adapters (structured files, contracts, billing platforms), extraction provenance, review approvals, effective-dated amendments, bitemporal history and a mechanism registry. Unknown source fields remain in the source snapshot and are never inferred as rules.
- A full reporting pipeline requires durable job orchestration, database transactions and concurrency controls, tenant isolation, role-based authorization, encryption, observability, completeness checks, late-arrival/correction policy, reproducible code and input versions, data retention and deployment operations. SQLite demo is not a substitute.
- Add a reconciliation model for projections versus actual billing with explicit mapping and line-level variance reasons, then validate against a finance-approved historical example. No production accuracy or enterprise readiness is claimed.
- Source documents and client-specific language can be sensitive. The demo uses synthetic inputs; do not enter actual contracts in a public preview.
