# Continuation status — 14 November 2026

> Current: [Broker and Internal workspaces](WORKSPACES-MILESTONE.md) implement the
> owner's UI walkthrough, dated commercial rates, exact proposal review/scheduling,
> and native Savvy billing objects. Campfire and CLM are local mocks. Read
> [current validation](VALIDATION-WORKSPACES.md) and the
> [finalized Astra contract](WORKSPACES-IMPLEMENTATION-CONTRACT.md) first.
> Contract 0.5.0; 93 Ruby tests, 49 Python tests, 19 dbt models/53 data tests,
> independent bounded stress checks and desktop/mobile acceptance passed.
> Main local services are running at http://127.0.0.1:3100 for review.
>
> The sections below are historical descriptions of earlier slices. Primary
> navigation is now Broker: Earnings/Agreements; Internal: Advisors/Commercial
> terms/Approvals. Collections/settlement/reconciliation remain legacy APIs and
> evidence, not product tabs. Native invoices now support multiple lines. The
> current product baseline is $1,750 earned/$1,000 coverage/$750 incremental;
> the earlier $1,770 draft-policy run remains unchanged in history.

The handoff ZIP was retrieved from the prior ChatGPT Library artifact and
extracted locally under `labs/savvy-prototype/advisor-payout-explorer`. Read
`INTERRUPTED-WORK-REVIEW.md` for the review completed before extending `apps/`.
The original Python, web, commercial-reporting and offline-preview files are
retained; the new path is Rails → GraphQL → Next.js with PostgreSQL.

> Updated: Savvy public-site branding, recorded coverage and receipt reversals are now implemented. See [the new milestone](SETTLEMENT-MILESTONE.md) and [brand provenance](SAVVY-BRAND-REFERENCE.md).

> Latest: Astra planning and a Terra execution/review/stress team completed
> [independent reconciliation evidence and frozen reviews](RECONCILIATION-MILESTONE.md).
> [Current validation](VALIDATION-CTO-RECONCILIATION.md): 65 Ruby tests, 14 dbt models
> and 41 data tests, HTTP checks, restore rehearsal and desktop/mobile verification.
> API contract is now 0.4.0. The earlier sections below describe the prior slices.

## Working local vertical slice

- Reproducible Docker Ruby/Rails/Postgres runtime; locked gems and frontend/dbt
  dependencies; isolated named synthetic database; loopback-only published ports.
- Scoped, immutable application snapshots, source record revisions, idempotent
  operations and transactional cash matches. Composite tenant/entity FKs.
- Pure Ruby policy selection: standard/promotion/override, containment and
  explicit priorities, half-open dates, cutoff checks, dimension validation,
  source-fact atomicity, exact weighted rates and reconciled cent allocation.
- Shared projected advance balance across customer facts, correct direction,
  expiry and no mutation of actual balances. Monetary-credit projection only;
  recorded directional applications and exact original-grant reversals now have a separate Finance-only settlement book.
- Exclusive broker monthly same-currency earnings floor/ceiling in the domain;
  floor in the UI. Provisional on supplied earnings, not an unseen monthly forecast.
- Broker book, customer trace, configuration editor, source upload, retained run
  history, internal cash matching, later equal-value invoice evidence link,
  simulated hash-bound Finance/Legal review and review-packet JSON export.
- Nine dbt models over read-only source views; current-state reports and
  SQL reconciliation checks, not an independent financial ledger.

The implementation intentionally uses a small generic immutable JSONB evidence
store. It does not implement every operational table in the proposed schema.
GraphQL exposes typed run/book/money/error envelopes and explicitly JSON data
payloads, not the full planned typed domain API.

## Verified worked path

Baseline Alex: customer fees $1,000 + $1,000; managed override 90% and active
promotion 85% → advisor earned $1,750. One $1,000 advance can cover only $1,000;
$750 incremental cash before guarantee. Inputs retain the $1,000 opening balance.

Through the UI, changing promotion to 87% and adding an exclusive November
$1,800 floor creates policy-v2: earned $1,770, coverage $1,000, incremental cash
$770 and separate provisional guarantee $30. The original run remains retained.
The clause text was edited to match these fictional choices.

Customer Cedar charge $1,000, receipt $600 → internal operational match $600,
unmatched charge $400. Maple $1,000 receipt matches its own $1,000 charge. A
later invoice link does not create another receipt. Bank settlement, accounting
application, AR and recognition remain null without their own evidence. A
customer without supplied receipt evidence is unknown rather than assumed zero.

## Execution plan gates

This is a tested first vertical slice, not completion of phases 0–10.

| Plan area | Status |
|---|---|
| Foundation | Runnable local stack, locks, setup, health, tests. No remote repo or CI runner created. |
| Relationships | Supplied fictional dated compensation assignments and shares; no relationship editing UI or full party/account graph. |
| Policy | Supported rates and finite dimensions implemented; arbitrary AST/metric catalogs remain unsupported. |
| Ingestion/runs | Manual synthetic batches, revisions, quarantine and frozen inputs; no schedule or background job backend. |
| Charges/collections | Pre-invoice matching, invoice links, receipt revisions/reversals and as-known views; separate independent application/bank bridge and frozen review added. Split invoices and accounting period locks remain future work. |
| Prepay/guarantees | Projected monetary credits and scoped earnings floors; recorded consumption/reversal ledger added; no nested guarantees or general metric conversion. |
| Legal/review | Simulated role decisions, version hashes and frozen packet; not authentication, legal approval or execution. |
| Campfire/accounting | Original offline Python adapter retained separately. Ruby Campfire recognition/accounting lifecycle remains unbuilt. |
| dbt | Fourteen current-state models with 41 data tests, including invoice application/bank evidence and conflicts; no complete warehouse, historical publication or Campfire replicas. |
| Private deliverable | Local review UI; no hosting, publication, external sharing or production readiness claim. |

All S01–S30 are still an acceptance TARGET, not a claim that 30 cases are fully
implemented end to end. Independent invoice applications, bank evidence and
gross-to-net bridges are now implemented in RECONCILIATION-MILESTONE.md. Genuine
accounting period locks/corrections and the offline Ruby accounting lifecycle
remain future work. Directional recorded entitlement allocations/reversals and
receipt-source reversals are implemented in SETTLEMENT-MILESTONE.md.

Use `VALIDATION-SAVVY-SETTLEMENT.md` for current checks and limits; `VALIDATION-CONTINUATION.md` is the earlier record. Existing evidence,
research and original validation documents remain historical; this file is the
current implementation status. No actual Savvy or Campfire data, code, credentials,
company policies or tenant features have been inspected. Publication stays paused.
