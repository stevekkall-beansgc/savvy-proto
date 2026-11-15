# Reconciliation review contract — Terra implementation target

2026-11-13. Astra planning recommendation, accepted for the next local synthetic
milestone. This is an evidence review, not an accounting period close. Preserve
Savvy's existing public-site assets and all prior demo history. No provider writes,
real data, publication, cash movement or production authentication is in scope.

## Interface

GraphQL query `reconciliation(periodStart: String!, periodEndExclusive: String!,
closeId: ID): JSON!` maps to `Workbench#reconciliation(period_start:,
period_end_exclusive:, close_id: nil)`.

Return exact minor-unit strings at GraphQL boundary (integers internally):

```
synthetic: true
period: {start, end_exclusive}
knowledge_cutoff: ISO timestamp
manifest_hash: SHA256 of stable evidence content, excludes volatile current clock
mode: current | frozen
close: null | {id, manifest_hash, closed_at, reason}
invoices: [{id, charge_id, customer_id, currency, amount_minor,
  applied_minor: null|integer, open_minor: null|integer,
  application_status: unknown|evidenced,
  applications: [{id,receipt_id,minor_units,status,recorded_at,reversal_of_id}]}]
bank_batches: [{id,currency,gross_minor,fee_minor,net_minor,receipt_ids,status,recorded_at}]
totals: {invoice_amount_minor,invoice_applied_minor,invoice_open_minor,
  bank_gross_minor,bank_fee_minor,bank_net_minor,recognized_revenue_minor:null}
exceptions: [{code,owner,next_action,evidence_ids}]
later_evidence: [{id,kind,recorded_at,reason}]
closes: [{id,manifest_hash,closed_at,reason}]
```

Finance-only commands through existing `workbenchCommand`:

- `RECORD_INVOICE_APPLICATION`: `{invoice_id,receipt_id,minor_units,business_date,reason}`
- `REVERSE_INVOICE_APPLICATION`: `{application_id,business_date,reason}`
- `RECORD_BANK_BATCH`: `{id,receipt_ids,gross_minor,fee_minor,net_minor,business_date,reason}`
- `REVERSE_BANK_BATCH`: `{batch_id,business_date,reason}`
- `CLOSE_RECONCILIATION`: `{period_start,period_end_exclusive,expected_manifest_hash,reason}`

New command results must contain relevant created `id`, plus `synthetic:true` and
`accounting_posted:false`. Existing transactional idempotency applies.

## Invariants

Invoice applications are independent supplied evidence, not inferred from an
operational cash match or invoice link. Conserve receipt and invoice separately;
scope, USD, customer identity, eligible receipt status and bounded reason required.
Reversals append a full original reversal once; never delete or mutate evidence.

Bank batch gross equals sum of explicitly attributed current eligible receipts;
gross = fee + net; fee <= gross; all nonnegative exact USD. Receipt IDs unique in a
batch and usable in only one active batch. Batch amounts stay at entity grain;
do not invent a customer net deposit or advisor earnings. Receipt reversal does
not silently cancel independent invoice/bank evidence: expose an explicit conflict.

Period boundaries are valid half-open ISO dates, with an explicit business date on
new evidence. Invoice period comes from its linked charge. No activity means
unknown amounts rather than verified zero; incomplete application coverage makes
aggregate applied/open totals unknown. Recognition remains unknown.

The current manifest binds source revisions, active and reversed evidence, period,
and relevant scope. Freeze compares expected manifest under the same scope lock
used for writes. Store exact review content once. Frozen content stays identical
after late corrections; return later evidence separately, with explicit late-change
exceptions. Do not rewrite old results or call this a production close policy.

## Ownership and acceptance

Terra backend: service, GraphQL, optional models/migrations, synthetic fixtures and
domain tests; publish any justified contract refinements immediately. Do not edit UI
or analytics. Add evidence kinds to existing JSONB store if sufficient; a migration
must preserve prior data and test cleanup compatibility.

Terra UI: dedicated typed reconciliation component, main-page integration and
brand-consistent responsive styles. Explicit independent evidence axes, gross/net
bridge, exceptions and frozen-review comparison. No finance actions for other
simulated roles. Current manifest used for freeze. Preserve money exactness.

Terra reporting: dbt source/marts/checks without fanout or unknown-to-zero, plus a
separate reproducible stress harness. Coordinate shared test DB usage; do not reset
main demo data. Independently attack backend concurrency, replay conflicts, rollback,
cross-customer/scoped evidence, unsupported states, and immutable frozen snapshots.

After integration, each Terra reviews another lane. Root resolves findings and
verifies fresh setup, backup/restore, complete regression suite, dbt and browser
desktop/mobile flows. Report measured results and remaining production gates.
