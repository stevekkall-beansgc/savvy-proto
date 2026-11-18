# Medallion local API contract

Version 0.6.0 · 15 November 2026

This describes the isolated synthetic implementation in this checkout, not a
Savvy API or a production authentication, billing, accounting, payment, CLM or
provider integration. The authoritative GraphQL names and types are in
[the exported schema](../contracts/schema.graphql). The JSON contracts below are
bounded by the current service; an accepted field is not a promise that a broader
commercial mechanism is implemented. All examples and identities are fictional.

## Transport and identities

`POST /graphql` accepts `application/json` with `{query, variables,
operationName?}`. The local controller limits the body to 1 MiB, query text to
50,000 bytes, GraphQL depth to 10 and complexity to 150. The isolated Compose
project exposes Rails on `127.0.0.1:3102` and PostgreSQL on `127.0.0.1:55438`.
The frontend proxy is configured separately. `GET /health` reports contract and
engine versions; this is not a provider connection check.

`X-Demo-Role` selects one simulated role: `operator`, `finance`, `legal`,
`auditor`, `advisor`, or `ria`. These headers are a local demonstration boundary,
not authentication. The server fixes the demo tenant and entity. The `ria` role
cannot call retained November GraphQL queries or `workbenchCommand`, nor read
legacy Workbench records directly. The `advisor` and `ria` roles cannot use
internal Medallion views or commands, or select the other case. Operator, Finance,
Legal and Auditor may read internal views; write roles are listed below. Selecting a
workspace is presentation, not a grant of authority.

External scenario access is explicit:

| Case and external role | Shared scenario IDs |
| --- | --- |
| `advisor` | `baseline`, `correction`, `bonus_outside`, `bonus_inside`, `pending_payment`, `confirmed_payment` |
| `ria` | `baseline`, `service_credit` |

An external request for a private or unknown scenario is forbidden before its
records are read. Internal requests are also scope-bound. A missing run or
statement is not a verified zero.

## Query and projections

```graphql
query Medallion($workspace: String!, $caseId: ID!, $scenarioId: ID, $runId: ID) {
  medallionWorkspace(workspace: $workspace, caseId: $caseId,
                     scenarioId: $scenarioId, runId: $runId)
}
```

`workspace` is `advisor`, `ria`, or `internal`; `caseId` is `advisor` or `ria`;
`scenarioId` defaults to `baseline`. Omit `runId` for the latest retained run in
that case and scenario, or provide its ID for that historical run. Latest-run
statements use the current server knowledge time for payment applications; an
explicit historical run uses that run's knowledge cutoff. The common JSON shape
is:

```text
case_id, scenario_id, workspace
run: null | {id, status, period_start, period_end, knowledge_cutoff,
  summary: [item], detail: [item], comparison: null | comparison, exceptions, coverage}
terms: [{title, version, status, period_start, period_end, items, document_ref}]
statement: null | {status, run_id, obligation_key, as_of, currency,
  previous_statement_id, opening_balance_minor, before_payment_minor,
  application_refs, component_values, lines, balance_minor,
  service_start, service_end_exclusive, detail_refs}
```

An `item` carries `output_id`, `detail_refs`, `run_id`, `label`, `minor`,
`currency`, `basis` when available, `description`, `category` and `status`.
`minor` is a decimal integer string or null. The comparison includes baseline and
selected amounts, benefits, run ID and detail references; it is absent when the
program has no corresponding outputs. Statement lines retain signed effects,
result and application references and, for adjustments, original result
references. A statement can instead return `needs_review`, no balance and a
reason. A negative RIA balance is a credit balance, not evidence of a refund.

The internal projection additionally exposes `parties`, `subjects`, `products`,
`assignments`, `scenarios`, `event_kinds`, `event_policies`, `policies`,
`comparisons`, `reviews`, `events`, `payments`, `payment_applications`,
`statements`, `runs`, and `pipeline`. Pipeline stages include retained artifact and
delivery samples, selected Silver facts and bindings, Gold detail, exceptions,
and publication context. The raw engine result is internal-only. Its manifest
contains scoped fact/assignment evidence and hashes; result details distinguish
intermediate, terminal and summary roles, exact rational values, assessed minor
units, source and dependency references. A rollup must not add a summary to its
children. See [the engine contract](MEDALLION-ENGINE-CONTRACT.md) for the actual
graph vocabulary and validation boundaries.

## Command envelope

```graphql
mutation Command($action: MedallionCommand!, $input: JSON!, $key: String!) {
  medallionCommand(action: $action, input: $input, idempotencyKey: $key) {
    data
    errors { code message path }
  }
}
```

The key must match `[A-Za-z0-9_-]{1,100}`. Commands run under the demo-entity
scope lock with transactional idempotency: same role, action, key and input replay
the saved result; changed input with the same key conflicts. `scenario_id` below
is optional and defaults to `baseline`; `case_id` is required except for
`BOOTSTRAP`. IDs use the same bounded character set. Reasons use 3–300 characters.
ISO dates are half-open; ISO timestamps require `Z` or an explicit offset. The
current Medallion evaluation context is the fictional September 2026 service
period. GraphQL recursively serializes `_minor`, `minor_units`, `threshold` and
`measure` integers as decimal strings, and accepts bounded decimal integer strings
for corresponding input keys. Do not send floating-point money.

### Policies and assignments

| Action and roles | JSON input |
| --- | --- |
| `BOOTSTRAP` — operator | `{}`. Loads the isolated fictional artifacts, scoped facts, mock policies, proof records, scenario events and historical statement fixtures. |
| `SAVE_POLICY_VERSION` — operator or finance | `{case_id, scenario_id?, base_id, expected_base_hash, policy, rates?, reason}`. `policy` is the declarative `{version, nodes}` graph; client-supplied `rate_rows` are rejected. `rates` is an array of rate changes/additions. |
| `COMPARE_POLICIES` — operator or finance | `{case_id, scenario_id?, baseline_policy_id, proposed_policy_id, knowledge_cutoff}`. Uses the same source manifest for both policies, with a separate policy-knowledge cutoff and `hypothetical: true`. |
| `REVIEW_POLICY` — finance or legal | `{case_id, scenario_id?, policy_id, comparison_id, document_ref, decision:'approved_for_demo'}`. `document_ref` must be exactly `{system:'mock_clm', document_id, version, status:'reviewed_for_demo'}`. |
| `PUBLISH_POLICY` — finance | `{case_id, scenario_id?, policy_id, comparison_id, effective_from}`. Requires matching Finance and Legal reviews, unchanged code and dependencies, current source evidence and a non-stale published base. |
| `ASSIGN_POLICY` — finance | `{case_id, scenario_id?, policy_id, policy_hash, subject_id, product_id, starts_on, ends_on?, supersedes_assignment_id?, expected_assignment_hash?}`. Publication and assignment are separate. |
| `EVALUATE_CASE` — operator or finance | `{case_id, scenario_id?, policy_id, knowledge_cutoff}`. An actual run requires a published policy and the unique matching assignment known at cutoff. |

A `rates` entry accepts `id`, `numerator`, `denominator` and, when adding or
changing metadata, `name`, `kind`, `starts_on`, `ends_on`, `selector`,
`signup_within_days`, `priority`, `component`, `payer_id`, `payee_id`,
`broker_id`, and `commercial_group`. Existing rows are copied into a new
configuration; old rows remain immutable. The currently accepted authored rate
unit is a ratio with numerator/denominator bounded by 1,000,000 and numerator no
greater than denominator. Kinds are `standard`, `promotion`, and
`targeted_promotion`; selectors are bounded to `customer_type` and `product_type`.
Signup windows are 1–365 days. `commercial_rates` is the shared scoped store;
policy graphs reference its rows instead of accepting a client `rate_rows` map.
Fixed money and per-unit parameters are represented in the supported graph.

The typed assignment row has a schedule version, half-open interval and scoped
policy reference. A backdated replacement currently supports the complete
**single-interval** schedule only: supply its exact ID and hash and the identical
interval. It appends the next version. Older knowledge cutoffs continue to select
the older version. Multi-interval schedule replacement is explicitly unsupported;
non-overlap is enforced within each selected schedule version.

### Event intake and posting

| Action and roles | JSON input |
| --- | --- |
| `SUBMIT_EVENT` — operator or finance | `{case_id, scenario_id?, event:{id, revision, kind, amount_minor, currency, debtor_id, creditor_id, subject_id, reason, economic_date, posting_period, policy_id, event_policy_id?, original_id?, original_revision?, original_hash?, reason_code?}}` |
| `REVIEW_EVENT` — finance | `{case_id, scenario_id?, event_id, revision, expected_hash, decision:'approved'|'rejected'}` |
| `LOCK_POSTING_PERIOD` — finance | `{case_id, scenario_id?, posting_period, reason}` |

Supported event kinds are `compensation_entitlement` and `payout_request` for the
advisor direction `firm-demo` → `advisor-demo`, and `one_time_charge` and
`one_time_credit` in the appropriate opposite directions between `ria-harbor` and
`firm-demo`. Subject is respectively `advisor-demo` or `ria-harbor`; currency is
USD, amount positive and economic date within September 2026. Posting period is
`YYYY-MM`. Except for payout requests, choose `event_policy_id` from the published
policy's `event_policies`; it determines the approved inclusion group. A caller
cannot set a free-form inclusion group. Replacements require the original ID,
revision and hash and a new exact-event approval. Drafts and rejections remain
retained; only approval known by the cutoff makes an economic event eligible.
A payout request alone does not reduce payable.

Locks are checked across the demo tenant/entity, including other scenarios, when
submitting/reviewing events, applying/reversing payments and sealing statements.
A lock does not issue a document or claim an external accounting close. The
supported event compositions and selectors are deliberately bounded; unsupported
or disconnected treatment fails closed rather than silently dropping an approved
amount.

### Source deliveries and proof reversals

`INGEST_DELIVERY` — operator or finance:

```text
{case_id, scenario_id?, source_kind, source_id, revision, raw_json}
```

`source_kind` is `balance`, `signup`, or `network_report`. `raw_json` is a
1–262,144 byte UTF-8 JSON string whose exact bytes are retained. Its decoded
object must contain exactly:

```json
{"synthetic":true,"source_id":"balances","revision":2,
 "records":[{"name":"cedar_30","value":"401500000"}]}
```

The outer and inner source ID and revision must agree. Each record has exactly
`name` and `value`; 1–100 records are allowed. Balance names are existing
`cedar_NN`/`maple_NN` advisor facts, signup is the existing `signup` fact and its
value is an ISO date, and network reports are the existing allowlisted RIA report
fields. Numeric values are bounded nonnegative decimal integer strings. Unknown
facts, fields and sources are rejected; this is not a general source adapter or a
URL fetcher. The server assigns receipt/knowledge time. New facts must advance the
existing fact revision. Raw artifacts and separate delivery outcomes are retained
for accepted, duplicate, rejected and conflicting arrivals; a duplicate has no
second economic effect. The response is `{id, artifact_id, status, reason_code,
synthetic}` with status `accepted`, `duplicate`, or `rejected`.

`REVERSE_SOURCE_RECEIPT` — finance: `{case_id, scenario_id?, receipt_id, revision,
expected_hash, reason}`. `REVERSE_FUNDING` — finance: `{case_id, scenario_id?,
funding_id, revision, expected_hash, reason}`. Each appends a linked reversal
once. Earlier as-known inputs and runs remain unchanged; current eligibility is
removed after the reversal is known. A receipt reversal can append a linked draft
rebate adjustment intent from an existing assessed result. Neither command proves
a refund. The sample coverage right is linked to independent confirmed funding;
the qualifying RIA receipt is linked to three scoped allocations reconciled to
individual reported lines. The account-month quantity is validated against the
retained scoped roster: IDs must be unique, and only eligible accounts active for
the entire period count. Missing, partial, mismatched or unproven roster evidence
blocks the quantity rather than assuming 30. Netting separately requires retained
authority for the parties, currency and interval.

### Payment evidence and statements

| Action and role | JSON input |
| --- | --- |
| `RECORD_PAYMENT` — finance | `{case_id, scenario_id?, payment:{id, revision, amount_minor, currency, debtor_id, creditor_id, status:'pending'|'confirmed', observed_at}}` |
| `APPLY_PAYMENT` — finance | `{case_id, scenario_id?, payment_id, payment_revision, run_id, output_id, amount_minor, posting_period, reason}` |
| `REVERSE_PAYMENT_APPLICATION` — finance | `{case_id, scenario_id?, application_id, posting_period, reason}` |
| `SEAL_STATEMENT` — finance | `{case_id, scenario_id?, run_id, posting_period, reason, historical_as_of?}` |

Payments are independently reported mock evidence, not requests or earnings.
Only confirmed same-direction USD evidence may be applied, and only to the latest
completed scoped obligation (`payable` for advisor, `net` for RIA). Application
bounds conserve both the receipt and the stable economic obligation across reruns;
reversal appends a linked record and does not assert a refund. A second revision
of an existing payment ID currently fails closed pending an explicit correction
workflow. Statements derive their opening balance, selected component differences
and eligible application changes through the shared engine. Sealing retains the
snapshot; it does not issue a document. Explicit `historical_as_of` is checked
against server time and run cutoff. A nonhistorical seal requires the latest
completed run.

## Isolated fixture reproduction

Use only the `savvy-medallion` Compose project and its disposable volume. Do not
run these commands against the retained November/live project or the default
Compose file. The commands below migrate and seed; they do **not** reset a database.
The existing `Workbench#seed!` retains the separate November demo, while the
Medallion bootstrap adds the fictional September namespace and its sealed October 2
scenario snapshots. Repeating the exact bootstrap key replays its result.

```sh
docker compose -f compose.medallion.yaml up -d db
docker compose -f compose.medallion.yaml run --rm api bundle exec rails db:migrate
docker compose -f compose.medallion.yaml run --rm api bundle exec ruby -e 'require_relative "config/environment"; w=Workbench.new; w.seed!; p w.medallion.bootstrap({},"medallion-fixture-v1")'
```

The following creates the nine selected example runs using stable case, scenario,
policy and cutoff inputs. Run IDs are generated and therefore are not stable;
reusing each exact idempotency key replays its original result. The Oct 1 RIA run
has incomplete receipt-dependent outputs. The six October 3 branches are
independent, not cumulative.

```sh
docker compose -f compose.medallion.yaml run --rm api bundle exec ruby -e 'require_relative "config/environment"; w=Workbench.new; cases=[["advisor","baseline","advisor-policy-v1","2026-10-02T23:00:00Z"],["ria","baseline","ria-policy-v1","2026-10-01T23:00:00Z"],["ria","baseline","ria-policy-v1","2026-10-02T23:00:00Z"],*["correction","bonus_outside","bonus_inside","pending_payment","confirmed_payment"].map{|s|["advisor",s,"#{s}-policy-v1","2026-10-03T23:00:00Z"]},["ria","service_credit","service_credit-policy-v1","2026-10-03T23:00:00Z"]]; cases.each_with_index{|(c,s,p,t),i| r=w.medallion.evaluate_case({"case_id"=>c,"scenario_id"=>s,"policy_id"=>p,"knowledge_cutoff"=>t},"fixture-run-#{i}"); puts "#{c}/#{s}/#{t}: #{r["status"]} #{r["id"]}" }'
```

Fixture bytes are retained and SHA-256 identified. For this frozen source state,
the following base artifact hashes can be checked with `shasum -a 256`:

| Fixture | SHA-256 |
| --- | --- |
| `advisor-policy.json` | `2c95094bfedfda31c984eaa16e852e339f2b843523780d9d8255b2730e4a587f` |
| `advisor-facts.json` | `6405264cff568dfd756ef76c743f994b6dbe6246e0663cbf9d8204554f033b79` |
| `advisor-funding.json` | `9f97601eab7b4b9b2c546eea34317557a05c4769d42165f553c2f6968fcd478f` |
| `ria-policy.json` | `441f99d9e58d99b9ebaf7952ebaec3d067e83f4ef8c9ecdbffd8f6d8efb8ce97` |
| `ria-facts.json` | `4f80c6f39e6558b2942a6056cccff94f2b25b3e217599a8ef3280310f91ecc6b` |
| `ria-receipt.json` | `85342f603b98d0d074ed19fb46a7c28982206be99e0e9c412cd440cf447b2204` |
| `ria-netting.json` | `d93802652d8da4507ea81f5d7755ae32f761e53e7ac8fb4f8b7a0c346bcb0fa0` |
| `advisor-payment.json` | `a8f0f19a6225c6e9f09429ad4e59953e9ef0dd5d58ee7022c78230ba4063246c` |
| `ria-account-roster.json` | `0cbe270226748b051a6410422b6a246cd022c43e008261788b13b11390fedacf` |

The implementation digest in runs and reviews combines the Ruby engine, graph
interpreter and legacy commercial adapter. Source, policy, assignment and
comparison hashes bind the corresponding immutable inputs; a changed dependency
requires a fresh comparison and review even if a headline amount is unchanged.

## Three-audience projections and Finance timing fixture

The new JSON GraphQL fields `audienceSummary(caseId:)`,
`audienceClients(caseId:, search:, limit:, offset:)`, and
`audienceClient(caseId:, clientId:)` use the existing case-based simulated
roles. Lists have `items`, `total`, `limit` and `offset`; limits are 1–100.
The internal-only `lineageRecords(caseId:, search:, limit:, offset:)` includes
all retained scenarios, and `lineageRecord(caseId:, recordId:)` returns the
selected record and its available retained links. A service responsibility is
not execution proof; execution and missing evidence are distinguished.

`financeWorkspace(caseId:)` is available only to operator, finance and auditor.
Advisor context reads the baseline outbound funding and payment/application
records and never treats compensation as Savvy revenue. RIA context uses the
separate `finance_timing_2027` fixture; before initialization it reports
`available: false`. It exposes commercial invoice/line identities, cash and
local association state, independent mock accounting observations, recognition
input/schedule/posted records and exceptions. There is no live provider call.

`financeCommand(action:, input:, idempotencyKey:)` returns the same `data` and
`errors` envelope as other commands. Supported actions:

| Action | Role | Input |
| --- | --- | --- |
| `FINANCE_BOOTSTRAP` | operator | `{}`; idempotently initializes the isolated fixture and its engine-assessed commercial invoice. |
| `FINANCE_ASSOCIATE` | finance | `{payment_id, invoice_id, currency, amount_minor, posting_period, reason}`; a scoped local association, not a transfer or accounting posting. |
| `FINANCE_REVERSE` | finance | `{application_id, posting_period, reason}`; appends a reversal, not a cash refund or accounting reversal. |
| `FINANCE_MOCK_ACKNOWLEDGE` | finance | `{application_id}`; returns the separately authored mock response for the fixture's eligible $300 association. |

Inputs reject extra fields. Amounts are integer minor-unit strings, bounded by
both the payment and invoice. A scope lock and idempotency keys serialize writes.
The mock acknowledgment is not inferred from an association. A later reversal
preserves the reported outcome and raises a correction exception. The fixture's
future-dated clocks and posted outcomes are authored synthetic evidence, not
current accounting events. The unbilled January input excludes its February
invoice; a later input revision links that invoice and the independently supplied
reclassification outcome. Recognition is supplied evidence, never a pricing or
recognition calculator. Actual Finance policies and production integrations
remain undecided.
