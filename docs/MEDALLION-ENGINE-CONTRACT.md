# Medallion engine contract

`Economics::Engine#validate(policy:)` validates a bounded graph independently of
available facts. `#evaluate(policy_bundle:, input_manifest:, context:)` evaluates
that graph. The legacy positional `evaluate(snapshot, policy, date:, cutoff:)`
translates the complete request into one graph, including ordered coverage and
monthly floor or ceiling, and uses the same interpreter. `CommercialEngine` is a
compatibility adapter for its historical envelope.

A policy bundle contains `policy`, `policy_id`, the 64-character `policy_hash`,
and `approved`. Actual runs require approval; hypothetical comparisons may bind a
draft and specify `hypothetical: true` and `policy_knowledge_cutoff` in context.
Context otherwise contains `tenant_id`, `entity_id`, `scenario`, `service_start`,
`service_end_exclusive`, and `knowledge_cutoff`. The separate policy clock never
changes the source cutoff. `input_manifest.facts` is a map of typed facts, each
with source `id`, positive `revision`, `tenant_id`, `entity_id`, `recorded_at`,
`approved`, and `currency` for currency amounts. Negotiated scalar rate rows are
part of `policy.rate_rows`, with the same scope and identity, approval and
`valid_from`/`valid_to`; they cannot be shadowed by manifest facts. Observed
rates are source facts. The wrapper validates scope, approval, cutoff and basic
effective intervals. The caller must establish authorized source, event,
funding and payment relationships; matching metadata alone is not proof.

A policy has `version` and `nodes`. Each node has a unique `id`, `op`, `role`
(`intermediate`, `terminal`, `summary`), `unit`, and `basis` (`exact_accrual`,
`assessed`, `source_reported`, `scalar`). References are node IDs. Amounts are
minor units and exact numeric values use integers or `numerator/denominator`
strings. `assessed` values must be whole minor units. Results serialize exact
rationals as numerator/denominator strings. Outputs reference terminal or summary
details, so parents and children are not implicitly added together. Every public
monetary output declares `output_class`; obligation and net-balance outputs
require payer, payee and currency. Net balances require the explicit `net`
operator. Static direction lineage prevents hiding an opposing-obligation
subtraction behind anonymous intermediate nodes.

Operators include `literal`, `fact`, `sum_facts`, `add`, `subtract`, `multiply`,
`accrue`, `min`, `max`, `assess` (explicit half-up), authorized `net`, progressive `bands`, dated
`select`, conserved `allocate`, `allocate_by`, and `distribute` (largest remainder). `allocate_by` uses an assessed group amount and a recipient-to-weight-node map; all weight nodes have a common non-scalar unit and basis, nonnegative exact values, and a positive total. It uses the same stable recipient-ID tie break as `allocate`, preserves the input sign, and rejects zero total or mismatched units. The language version is `primitive-graph/0.4` and the interpreter version is `economics-ruby/0.5.0`. A
`net` requires opposing declared payer/payee and currency plus a separately evidenced, effective `authority_fact`; missing authority blocks the net while independent obligations remain available. A `sum_facts` node declares `collection`, an exact-match `selector`, explicit
`allow_empty`, and `period` (`service` or `all`). Each selected fact remains a
separate source with its own provenance. Output bindings list selected keys;
future, out-of-period and nonmatching events are not included. Empty required
collections and other missing evidence block dependent outputs; independent
completed outputs remain available.

The result includes schema/language versions, status, frozen context and hashes,
bindings, details, output references, coverage and exceptions. Details include
economic identity, component, role, parties where declared, interval, currency,
exact/assessed amount, direct dependencies and source references. `interval_fact`
provides an explicit dated fact for a daily node. The fixtures' named
`comparison_baseline`, `comparison_selected`, benefit and network component
nodes are policy outputs; consumers display these without computing alternatives.

The pure `evaluate_program` entry is a primitive test harness and does not
replace the manifest authorization boundary. The surrounding pipeline still
must enforce complete source coverage, assignment applicability, independent
funding/coverage-right and confirmed-payment linkage, immutable approvals and
statement lifecycle. Fixture programs and this contract do not alone establish
that the milestone's end-to-end acceptance criteria are met.
