# Disclosure-informed billing API

`disclosure/v1` is an additive local synthetic contract over the existing Rails
GraphQL endpoint. `contracts/schema.graphql` is the authoritative SDL. Identities
remain simulated; tenant/entity scope comes from the server. Campfire and CLM
remain mocked. Public disclosures are not governing agreements.

## Reads

`disclosureWorkspace(caseId: ID!, audience: String!, limit: Int, offset: Int)`
returns `contract_version`, `available`, `case_id`, `audience`, `context`,
`summary`, `sections`, `page` and `exceptions`. Audiences are `client`, `product`
and `finance`. Advisor/RIA identities can read only their own client case;
requesting another audience cannot elevate identity. Internal reads are scoped
and role-checked. Reads never bootstrap, evaluate, publish or write.

Sections are `billing`, `valuation`, `terms`, `lifecycle`, `compensation`, `costs`,
`recognition`, `policy_options` and `changes`. Pagination is a deterministic global
slice across those lists, default 20/max 100, with the combined total. Client
projections omit internal record IDs, graphs, review records and raw source bytes.
The RIA sample is a separately observed cost; it does not establish platform prices.

Minor amounts are decimal integer strings in GraphQL. Unknown amounts are null;
units, loan principal, forgiveness, entitlements, observed cash and assessed fees
remain distinct. Internal detail uses existing scoped `lineageRecords` and
`lineageRecord`. Recorded execution requires exact source evidence plus actual
interpreter binding/result references; a parent/source reference alone is a link.

## Writes

`disclosureCommand(action: String!, input: JSON!, idempotencyKey: String!)`
returns `{data, errors {code, message, path}}`. Allowed actions:

| Action | Input and role |
| --- | --- |
| BOOTSTRAP | Empty object, operator; append the fictional source deliveries, policies, runs, native billing and accounting observations idempotently |
| SAVE_POLICY | case_id, base_policy_id, policy, effective_from, effective_to, reason; operator |
| COMPARE_POLICY | case_id, policy_id, baseline_run_id; operator; freeze the exact edited treatment's baseline evidence |
| REVIEW_POLICY | case_id, comparison_id, decision (approve/reject), reason; Legal or Finance |
| PUBLISH_POLICY | case_id, policy_id, comparison_id; operator; both current exact approvals required |
| ASSIGN_POLICY | case_id, policy_id, subject_id, effective_from, effective_to, reason; operator; explicit supersedes_assignment_id for exact-interval replacement |
| EVALUATE | case_id, knowledge_cutoff; operator; select known assignments/evidence, retain a new result/publication; never silently reissue the original invoice |

Policies carry exact annual-rate rationals and typed minor-unit parameters.
Supported editor mechanisms include monthly/quarterly ending value, monthly ADB,
net worth, fixed service, hourly planning and accepted optional service. A monthly
ending-value minimum applies once to the group. Fields include `basis`, `cadence`,
`annual_rate`, `minimum_minor`, `fixed_amount_minor`, `hourly_rate_minor`,
`optional_amount_minor`, `optional_service` and `service_mode` as applicable.
Unknown fields, unsupported combinations, malformed/excessive numbers and
incompatible source/assignment periods are rejected. Integer money strings are
normalized once; no binary floating-point fee calculation runs in the UI.

Policy builders construct data graphs; Economics::Engine is the sole evaluator.
Reviews bind the comparison, policy, baseline manifest/run, terms and full
interpreter/adapter fingerprint. Publication does not assign; assignment does not
bill; a changed already-billed period produces a correction requirement. Repeating
comparison updates the one current request while previous comparisons stay retained.

Source ingestion beyond BOOTSTRAP, general household membership administration,
quarterly replacement of an overlapping monthly schedule, payment execution and
production authentication are outside this bounded milestone. See
[backend scope](DISCLOSURE-BACKEND-NOTES.md) for exact limits.
