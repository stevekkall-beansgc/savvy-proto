# Work backward from one Campfire record

This local CLI takes one redacted object, finds explicit links in related records
you supply, and shows where the trace reaches or stops in Savvy's workflow. Start
with an invoice that had a correction or partial payment. Keep real exports
outside Git and use consistent aliases across related records. The script uses
Python's standard library and has no network calls, database writes, or posting
capability. Reports contain record IDs and amounts, so handle them like the input.

## Start with an unfamiliar export

Run discovery before assuming a schema. It inspects nested objects or CSV headers
and proposes a record type, field paths and possible invoice lines. It uses the
labels, nesting and shapes of the values as clues. It displays field names and
types without sample values. If nothing looks recognizable, it prints an inventory
of the available fields. Unknown record shapes also enter this mode automatically.

```sh
python3 scripts/trace_campfire.py /path/to/redacted-export.json --discover
python3 scripts/trace_campfire.py /path/to/redacted-export.json \
  --discover --format mapping > /tmp/savvy-trace-mapping.json
```

Review the field paths with Savvy, make any corrections and set `reviewed` to
`true`. Paths are arrays of object keys and zero-based row indexes. For example,
`["batch", "payload", 0, "billingRecord"]` selects one nested record. Field
paths are relative to that record, and line field paths are relative to each line.
Multiple plausible fields are shown and left out of the draft. Use `--kind` as a
hint, or `--record-path '["batch","payload",0,"billingRecord"]'` to inspect an
exact record in a longer export.

```sh
python3 scripts/trace_campfire.py /path/to/redacted-export.json \
  --mapping /tmp/savvy-trace-mapping.json
```

The draft maps one record. A reviewed mapping can include related records when
you have their paths. Add `--format bundle` to produce the normalized local JSON
so you can add related records, completion evidence or an upstream crosswalk as
Savvy shows them. The mapping cannot infer that the export is complete, verify
cash, or identify a policy from an accounting field alone.

Try the [unfamiliar sample](../fixtures/campfire-trace/unfamiliar-export.json)
with `--discover` before the meeting. It demonstrates how the script can extract
a nested invoice and one line once the reviewer confirms the proposed paths.

## Map the workflow from any record

Open the generated HTML in a browser. It works offline. You can start at an
aggregate, source delivery, normalized fact, policy assignment, calculation,
invoice, statement, memo, payment, journal or billing event, and click an upstream or downstream
record to make it the new starting point. The map counts recurring open links by
record type and retains the invoice-level gap summary for financial review.

`Trace your records` accepts one or more JSON or CSV files by drop or file
picker. A single record immediately opens the billing cycle around that point.
Use `Try one rollup` for a synthetic example. The viewer suggests a type from
explicit labels and recognizable fields. If the position is unclear, it shows
possible areas to investigate and updates the cycle when you choose a type.
Choose a different type when needed, or choose `Other event type` and give the
record a name. Savvy's one-time charges, one-time credits, compensation
entitlements and payout requests are available in the type selector. Review the
record ID and reference fields, then choose `Confirm types & build map`. You can
add a relationship between two imported records under `Confirm relationships`
if you established the connection during the walkthrough.

The cycle uses rules based on the prototype's workflow. It shows likely stages
with evidence missing, possible branches, supplied references that still need a
record, and links with records present. Each stage states what to ask for.
Open `Preview record` on the starting point or choose a preview on either side.
The field table separates supplied values, reference IDs and fields to confirm.
Expected records show a blank field checklist based on the prototype. Where
recognized fields are present, invoice lines, rollup members and journal
schedules show up to 12 rows. Previews use the selected record's data.
With one supplied object, the map names it as the sole evidence source.
Related previews identify direct references and their original field paths.
Fields outside the supplied object and separate crosswalk or lineage rows need
their own evidence. To include them, supply the related records and confirm
their links in a batch. The trace-gap chart counts supplied records by type,
with separate bars for upstream gaps, downstream gaps, and record issues.
For an unexplained rollup, start by confirming the measure, grain, period and
basis before choosing between fee results, invoice activity and cash activity.
The browser uses the supplied or confirmed references to trace actual links.
Drop accepts up to 12 files and 2,000 records per
review. Imported data stays in the open page, and `Clear imports` discards it.
For invoice balance and line-amount reconciliation, use the CLI with a
reviewed bundle.

### Review reporting dimensions from any point

Select any record and open `Reporting dimension coverage`. Use `Gaps and
questions` to focus on dimensions that have no typed field in the reviewed
path, dimensions the prototype captures upstream and omits at a later handoff,
and fields that need a definition or mapping. The table identifies what the
prototype already carries, where to assign a dimension, and where to retain its
key or a join at the right grain. The comparison uses reviewed prototype code
and reporting models. It does not inspect a live Savvy or Campfire schema.

Start with a raw record, billing output, accounting record, or report. A
header-only CSV in the browser or a JSON report with a `columns` or `group_by`
array supplies declared field names. The reader distinguishes those names from
values found in a record. An unfamiliar field in a `dimensions`, `segments`
or custom fields object is queued for review. Supply matching rows from both
sides and confirm the relationship by ID to examine a handoff. A field absent
from a linked downstream sample is a possible omission. Confirm comparable
line grain, export selection and grouping before treating it as a loss.
The review follows nearby supplied records connected by explicit links. Use
`All reviewed dimensions` to see the full catalog from any starting point.
The [dimension walkthrough](../fixtures/campfire-trace/dimension-walkthrough.json)
contains a fictional delivery, calculation, posting and report column list.

Choose `Download gap list (CSV)` to export findings for the current starting
point. It includes relevant reviewed prototype gaps, fields that need a
definition, and a separate row for each possible loss at a linked handoff.
Rows include field paths, the proposed assignment or carry-forward, what to
confirm, and an open status. A display filter does not change the CSV scope.
The export retains record aliases and field paths. Use redacted records for
assessment and keep the resulting CSV with the assessment evidence.

Use actual report columns and the journal-line grain to confirm whether each
dimension matters. Preserve source fields on ingestion. Resolve customer,
custodial account and advisor identity in Silver, then carry the as-of IDs at
obligation or allocation grain. Attach a commercial fee code to the policy
output before Gold aggregates it. Use the Finance posting map for GL accounts
and ledger-only segments, and preserve the returned attributes on the actual
journal lines. Decide who owns a cost center or department before choosing
between Silver and the Finance mapping.

```sh
python3 scripts/trace_workflow_map.py --sample > /tmp/savvy-map.html
python3 scripts/trace_workflow_map.py /path/to/redacted-export.json > /tmp/savvy-review.html
python3 scripts/trace_workflow_map.py /path/to/rollup.json /path/to/related-records.json \
  --format json > /tmp/savvy-review.json
```

Combine files from the same provider account and entity. If an input is
unfamiliar, the map shows its discovery candidates separately. Use a reviewed
`--mapping` to map one unfamiliar file first. For a rollup, use
`trace_campfire.py ... --discover --kind aggregate --format mapping`, review the
paths, then pass the reviewed mapping to `trace_workflow_map.py --mapping`.

For a data extract or rollup, the useful questions are **what does it measure,
what is the grain, which dates and definition apply, what contributes to it,
and what consumes it?** Capture those answers as fields and explicit links:

```json
{
  "aggregates": [
    {
      "id": "oct-observed",
      "measure": "original-invoice-total",
      "grain": "entity/month",
      "basis": "issued-originals",
      "period_start": "2026-10-01",
      "period_end": "2026-10-31",
      "currency": "USD",
      "total_amount": "250.00",
      "members": [{"kind": "invoice", "id": "invoice-A"}]
    }
  ],
  "links": [
    {
      "from": {"kind": "aggregate", "id": "oct-observed"},
      "to": {"kind": "journal", "id": "oct-review-journal"}
    }
  ]
}
```

Add supporting objects as separate files, under the existing invoice/statement/
cash/journal groups, or under `entries` with an explicit `kind` and `id`.
Standalone records with explicit `kind` and `id` work too. Supported kinds
are `source`, `normalized`, `policy`, `calculation`, `aggregate`, `invoice`,
`statement`, `credit_memo`, `debit_memo`, `payment`, `journal`, `event`,
`payable`, `payout`, `accounting_package` and `report`.
For a reviewed `event` entry, add `event_type` to preserve its specific name.
Use `links` with `from` and `to` references for confirmed crosswalks in data-flow
direction. Add `definition_ref`, `manifest_ref`, and `members_complete: true`
once Savvy confirms the relevant rollup definition and members. An amount or
matching date never establishes membership or a join. A referenced object absent
from the supplied files appears as **reference only**. The map asks for likely
upstream and downstream evidence separately from actual references. It does not
reconstruct the rollup amount or assume it appears in a customer statement.

The [multi-record sample](../fixtures/campfire-trace/map-sample.json) starts at a
monthly rollup. It links two invoices and some of their upstream records, flags
a missing downstream review journal, and includes an unexplained total and an
unattached payment. To check an invoice balance in a multi-record map, supply
per-invoice `reconciliations` rows with `invoice_id`, `as_of` and confirmed
`complete_associations`. Completeness is never inferred across files.

## Trace a known or reviewed shape

From the repository root:

```sh
python3 scripts/trace_campfire.py --sample
python3 scripts/trace_campfire.py /path/to/redacted-invoice.json
python3 scripts/trace_campfire.py /path/to/redacted-list.json --kind invoice --id invoice-alias
python3 scripts/trace_campfire.py /path/to/redacted-bundle.json --format json
```

Use `-` in place of a path to read pasted JSON from standard input. A single
Campfire invoice or payment object, list, or `results` response works directly.
For a journal, memo or statement, supply `--kind journal`, `--kind credit_memo`,
`--kind debit_memo`, or `--kind statement`, or use a typed bundle as below. An
invoice line from a PDF needs to be transcribed to the `statements` shape. Set
`invoice_id` and `invoice_line_id` only if the link was actually established.

A CSV export can start the trace too. Use the exact headers in your file and
plain decimal amounts. Add line and linked records in a JSON bundle as needed.

```sh
python3 scripts/trace_campfire.py /path/to/redacted-export.csv --kind invoice \
  --id inv-A --column 'id=Invoice ID' --column 'invoice_number=Invoice Number' \
  --column 'total_amount=Total' --column 'currency=Currency'
```

## Which fields to grab

| Object | Minimum useful evidence | Savvy workflow |
| --- | --- | --- |
| Invoice | `id`, `entity`, `invoice_number`, `source`, `source_id`, `currency`, `invoice_date`, `period_start`, `period_end`, `total_amount`, `amount_due`, `lines[].id`, `lines[].amount` | Native invoice and line, statement period, recorded amount |
| Statement | `id`, `invoice_id`, `invoice_line_id` | Client statement link to the issued line |
| Payment | `id`, `invoice_id`, `amount`, `currency`, `payment_date`, `payment_type`, `external_id`, `voided_date` | Application evidence. Confirm the separate processor, custodian or bank record |
| Credit/debit memo | `id`, `invoice_id`, `currency`, `applied_amount`, `applied_on`, `voided_date` when relevant | Linked correction and amount applied to this invoice |
| Journal | `id` matching `invoice.journal_entry` or a confirmed `invoice_id`, plus `posting_date` and `schedule_id` when available | Accounting handoff and a reference to supplied recognition evidence |
| Upstream crosswalk | Invoice and line IDs, Savvy line ID, calculation ID, policy version and assignment IDs, agreement reference, input manifest ID, source record IDs | Gold calculation, Silver assignment and facts, retained original observations |

The invoice and payment field names come from the [Campfire invoice listing](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoices)
and [invoice payment listing](https://docs.campfire.ai/api-reference/accounts-receivable/list-invoice-payments).
The statement, applied memo, journal and lineage fields above are a **local review
format**. Confirm Savvy's actual object shapes and link semantics in the meeting.

## Add evidence as it becomes available

Copy the [fictional Harbor bundle](../fixtures/campfire-trace/harbor.json) outside
the repo and replace its contents with redacted records. Set
`complete_associations` to `false` until Finance confirms the record set. Its `anchor` picks the
starting object. The arrays can be added as you go. Set `line_id` to focus on one
invoice line. Add `lineage` records only for confirmed invoice and line aliases.
`expected_line_amount` and its currency are optional and should come from an
independent calculation on the same basis as the invoice line's recorded `amount`.

- **Observed** means the field is in the supplied record. **Linked** means the
  identifiers match within the supplied bundle. **Supplied crosswalk** means the
  reviewer entered upstream IDs. Open the underlying records to validate their
  scope, revision and effective dates. An ERP line's rate and quantity do not
  establish the signed terms or underlying balance observations.
- Amounts are in currency units, such as `"250.00"` for USD 250. The balance test
  requires `as_of` and `complete_associations: true`, an original issued invoice
  and the full set of debit/credit applications and confirmed cash for that same
  balance snapshot. Add `application_kind: "receipt"` or `"refund"` and a
  `cash_confirmation_id` to reviewed payment applications. Enter an applied credit
  once in `credit_memos`; omit its `CREDIT_MEMO` payment representation from the
  bundle. Keep uncertain, additional settlement, tax, FX and write-off effects
  open for Finance review.
- `--prototype docs/architecture/lifecycle-run.json` compares against the existing
  synthetic records only when an invoice explicitly labeled `source: "savvy"`
  carries an exact recorded document ID. This checks the packaged sample, not a
  match between a real record and a fictional one.

The sample starts at a journal, finds its invoice and statement line, ties
$250 original − $90 applied credit − $125 confirmed cash to $35 open, and
matches the prototype's $160 net bill. It also asks for calculation, policy
assignment and source evidence because the accounting export cannot supply them.
