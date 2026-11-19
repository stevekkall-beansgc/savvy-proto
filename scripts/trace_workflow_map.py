#!/usr/bin/env python3
"""Build a coverage map from one or many local, redacted billing records."""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

if __package__:
    from . import trace_campfire as trace, trace_discovery, trace_entry_graph
else:
    import trace_campfire as trace
    import trace_discovery
    import trace_entry_graph

TEMPLATE = Path(__file__).resolve().with_name('trace_workflow_map.html')
SAMPLE = trace.SAMPLE.with_name('map-sample.json')
STAGES = {
    'raw': ('Raw & Bronze', 'Source records', 'Data', 'Show the original delivery or observation IDs, their revisions and the receipt date.'),
    'silver': ('Silver', 'Normalized facts', 'Data', 'Show the normalized records and the mapping or normalization run that produced them.'),
    'policy': ('Silver', 'Terms & assignment', 'Product / Legal', 'Show the signed terms, policy version and assignment effective on the service dates.'),
    'gold': ('Gold', 'Calculation', 'Product', 'Show the calculation ID and frozen input manifest for the selected bill line.'),
    'invoice': ('Savvy billing', 'Native invoice', 'Billing', 'Show the Savvy document and line IDs and the scoped mapping to the Campfire invoice.'),
    'statement': ('Client', 'Statement', 'Billing', 'Show the client statement and the exact invoice line it references.'),
    'cash': ('Finance', 'Corrections & cash', 'Finance', 'Show the original and applied memos, payment applications and independent cash confirmations.'),
    'accounting': ('Campfire', 'Accounting', 'Finance', 'Show the journal, posting period and the recognition schedule or reversal that supports it.'),
}


def collect(sources, hint=None):
    groups = {kind: [] for kind in trace.GROUPS}
    lineage, snapshots, inventory, reconciliations = [], [], [], []
    for number, payload in enumerate(sources, start=1):
        grouped = isinstance(payload, dict) and 'id' not in payload and any(key in payload for key in trace.GROUPS.values())
        counts = Counter()
        unknown = []
        if isinstance(payload, dict) and 'reconciliations' in payload:
            reconciliations.extend(trace.records(payload['reconciliations']))
        if grouped:
            for kind, group in trace.GROUPS.items():
                rows = trace.records(payload.get(group, []))
                counts[kind] += len(rows)
                groups[kind].extend(rows)
            lineage.extend(trace.records(payload.get('lineage', [])))
            snapshots.append(payload)
        elif isinstance(payload, dict) and any(key in payload for key in ('lineage', 'reconciliations', 'entries', 'aggregates', 'links')):
            lineage.extend(trace.records(payload.get('lineage', [])))
        else:
            try:
                rows = trace.records(payload)
            except ValueError:
                rows = [payload]
            for row in rows:
                try:
                    kind = (hint or trace.infer(row)) if isinstance(row, dict) else None
                except trace.UnknownShape:
                    kind = None
                if kind:
                    groups[kind].append(row)
                    counts[kind] += 1
                else:
                    unknown.append(row)
        if isinstance(payload, dict):
            for name in ('entries', 'aggregates'):
                if name in payload:
                    counts[name] += len(trace.records(payload[name]))
        entry = {'input': number, 'recognized': dict(counts), 'unmapped_count': len(unknown)}
        if unknown:
            found = trace_discovery.discover(payload, hint)
            entry['discovery'] = [{key: candidate[key] for key in ('record_path', 'proposed_kind')}
                                  for candidate in found['candidates']]
            entry['fields_seen'] = found['shape_inventory'][:3]
        inventory.append(entry)
    if sum(len(rows) for rows in groups.values()) + len(lineage) > 2000:
        raise ValueError('Map accepts at most 2,000 records per review')
    if len(groups['invoice']) > 150:
        raise ValueError('Narrow this assessment to at most 150 invoices')
    # Copying or combining records never implicitly attests that a snapshot is complete.
    if len(sources) == 1 and len(snapshots) == 1 and len(groups['invoice']) == 1 and not reconciliations:
        reconciliations = [{**snapshots[0], 'invoice_id': groups['invoice'][0].get('id')}]
    metadata = {}
    reconciliation_counts = Counter(trace.ref(row.get('invoice_id')) for row in reconciliations)
    for row in reconciliations:
        identity = trace.ref(row.get('invoice_id'))
        if identity and reconciliation_counts[identity] == 1:
            metadata[identity] = {key: row[key] for key in ('as_of', 'complete_associations') if key in row}
    return groups, lineage, inventory, metadata


def canonical(payload):
    """Use explicit types on standalone records without requiring a bundle."""
    rows = payload if isinstance(payload, list) else [payload]
    if not rows or not all(isinstance(row, dict) and isinstance(row.get('kind'), str) and
                           row['kind'] in trace_entry_graph.TYPES and row['kind'] != 'unmapped' and
                           trace.ref(row.get('id')) for row in rows):
        return payload
    grouped = {}
    for row in rows:
        kind = row['kind']
        name = trace_entry_graph.GRAPH_GROUPS.get(kind, 'entries')
        grouped.setdefault(name, []).append(row)
    return grouped


def evidence_rows(reports, fields):
    return [{key: row['evidence'][key] for key in ('line_id', *fields) if row['evidence'].get(key)}
            for row in reports if any(row['evidence'].get(key) for key in fields)]


def stage(key, state, evidence, gaps=()):
    group, title, owner, action = STAGES[key]
    return {'id': key, 'group': group, 'title': title, 'state': state,
            'owner': owner, 'ask_for': action, 'evidence': evidence, 'gaps': list(gaps)}


def covered_stage(key, rows, keys, lines, label):
    evidence = evidence_rows(rows, keys)
    total = len(lines)
    populated = [row for row in rows if row['evidence'].get('line_id') and row['evidence']['line_id'] in lines and
                 row['status'] != 'ambiguous supplied links' and all(row['evidence'].get(field) for field in keys)]
    complete = total > 0 and len(populated) == total
    state = 'references' if complete else 'partial' if evidence else 'missing'
    gaps = [] if complete else [f'{label} for {total - len(populated)} of {total} lines' if total else 'No identified invoice lines to trace']
    return stage(key, state, evidence, gaps)


def line_mappings(rows, invoice, lines):
    identifier = trace.ref(invoice.get('id'))
    return [row for row in rows if identifier and trace.ref(row.get('invoice_id')) == identifier and
            trace.ref(row.get('invoice_line_id')) and trace.ref(row.get('invoice_line_id')) in lines and
            all(not trace.ref(row.get(field)) or not trace.ref(invoice.get(field)) or
                trace.ref(row[field]) == trace.ref(invoice[field]) for field in ('entity', 'currency'))]


def build_invoice(invoice, groups, lineage, metadata):
    ident = trace.ref(invoice.get('id'))
    grouped = {'invoices': [invoice], 'anchor': {'kind': 'invoice'}, **metadata.get(ident, {})}
    for kind, name in trace.GROUPS.items():
        if kind != 'invoice':
            grouped[name] = [row for row in groups[kind] if trace.match_invoice(kind, row, [invoice]) is invoice]
    # If an associated row conflicts on scope, skip the tie-out and expose it to the reviewer.
    conflicts = sum(1 for kind in ('payment', 'credit_memo', 'debit_memo', 'statement', 'journal')
                    for row in groups[kind] if ident and trace.ref(row.get('invoice_id')) == ident and
                    trace.match_invoice(kind, row, [invoice]) is None)
    if conflicts:
        grouped.pop('complete_associations', None)
    line_ids = [trace.ref(row.get('id')) for row in trace.records(invoice.get('lines', []))]
    scoped_lineage = line_mappings(lineage, invoice, line_ids)
    grouped['lineage'] = scoped_lineage
    report = trace.inspect(grouped)
    line_rows = [row for row in report['workflow'] if row['stage'].startswith('Invoice line →')]
    normalized = []
    for row in scoped_lineage:
        line = trace.ref(row['invoice_line_id'])
        # This is reviewer-supplied provenance. A duplicate mapping is unresolved.
        if sum(trace.ref(item.get('invoice_line_id')) == line for item in scoped_lineage) != 1 or line_ids.count(line) != 1:
            continue
        item = {'status': 'supplied', 'evidence': {'line_id': line}}
        if run := trace.ref(row.get('normalization_run_id')):
            item['evidence']['normalization_run_id'] = run
        values = row.get('normalized_record_ids', [])
        if isinstance(values, list):
            item['evidence']['normalized_record_ids'] = [value for raw in values[:100] if (value := trace.ref(raw))]
        normalized.append(item)
    stages = [
        covered_stage('raw', line_rows, ('source_record_ids',), line_ids, 'Original source references missing'),
        covered_stage('silver', normalized, ('normalization_run_id', 'normalized_record_ids'), line_ids, 'Normalization provenance missing'),
        covered_stage('policy', line_rows, ('policy_version_id', 'assignment_id', 'agreement_ref'), line_ids, 'Terms or assignment missing'),
        covered_stage('gold', line_rows, ('calculation_id', 'input_manifest_id'), line_ids, 'Calculation or frozen manifest missing'),
    ]
    line_mismatches = [check for check in report['line_reconciliation'] if check['observed_less_expected'] != 0]
    if line_mismatches:
        gold = stages[-1]
        gold['state'] = 'variance'
        gold['gaps'].append(f'{len(line_mismatches)} line amounts differ from the supplied independent calculation')
        gold['evidence'].extend(line_mismatches)
    header = report['workflow'][0]['evidence']
    line_links = evidence_rows(line_rows, ('savvy_invoice_line_id',))
    invoice_gaps = []
    if not ident or not header.get('entity') or not header.get('currency'):
        invoice_gaps.append('Invoice ID, entity or currency is missing')
    if not header.get('source_id') or not header.get('source') or not line_ids or None in line_ids or len(line_links) != len(line_ids):
        invoice_gaps.append('Savvy document or line mapping needs confirmation')
    if len(line_ids) != len(set(line_ids)):
        invoice_gaps.append('Invoice line IDs are ambiguous')
    stages.append(stage('invoice', 'partial' if invoice_gaps else 'references', [header, *line_links], invoice_gaps))
    statement = report['workflow'][1]['evidence']
    statement_count = len(statement['statement_linked_lines'])
    statement_complete = bool(line_ids) and statement_count == len(line_ids)
    stages.append(stage('statement', 'linked' if statement_complete else 'partial' if statement_count else 'missing',
                        [statement], [] if statement_complete else ['Exact statement links missing for one or more invoice lines']))
    recon = report['invoice_balance']
    cash = next(row['evidence'] for row in report['workflow'] if row['stage'] == 'Invoice → corrections → cash')
    cash_gaps = [] if recon['status'] == 'matches' else [recon.get('reason', 'Confirm the observed open balance and investigate any variance')]
    if conflicts:
        cash_gaps.append(f'{conflicts} related records had conflicting scope or identity')
    cash_state = 'tied out' if not cash_gaps else 'variance' if recon['status'] == 'variance' else 'partial' if any(cash.values()) else 'missing'
    stages.append(stage('cash', cash_state, [recon, cash], cash_gaps))
    accounting = next(row for row in report['workflow'] if row['stage'] == 'Invoice → accounting')
    accounting_evidence = accounting['evidence']
    linked = accounting['status'] == 'linked'
    schedule = linked and accounting_evidence.get('recognition_schedule_ref')
    accounting_gaps = [] if schedule else ['Show the linked journal and recognition schedule or confirm applicability']
    stages.append(stage('accounting', 'references' if schedule else 'partial' if accounting_evidence.get('journal_ref') else 'missing',
                        [accounting_evidence], accounting_gaps))
    return {'invoice_id': ident, 'label': trace.ref(invoice.get('invoice_number')) or ident or 'Invoice without ID',
            'entity': trace.ref(invoice.get('entity')), 'currency': trace.currency(invoice), 'stages': stages,
            'line_checks': report['line_reconciliation']}


def build(sources, hint=None):
    sources = [canonical(payload) for payload in sources]
    groups, lineage, inventory, metadata = collect(sources, hint)
    invoice_counts = Counter(trace.ref(row.get('id')) for row in groups['invoice'])
    duplicates = sorted([identity for identity, count in invoice_counts.items() if identity and count > 1])
    eligible = [row for row in groups['invoice'] if trace.ref(row.get('id')) not in duplicates]
    invoices = [build_invoice(row, groups, lineage, metadata) for row in eligible]
    unattached = []
    for kind, rows in groups.items():
        if kind == 'invoice':
            continue
        for row in rows:
            if trace.match_invoice(kind, row, eligible) is None:
                unattached.append({'kind': kind, 'record_id': trace.ref(row.get('id')), 'invoice_ref': trace.ref(row.get('invoice_id'))})
    for row in lineage:
        ident = trace.ref(row.get('invoice_id'))
        line = trace.ref(row.get('invoice_line_id'))
        if not any(ident and trace.ref(invoice.get('id')) == ident and line_mappings([row], invoice, [trace.ref(item.get('id')) for item in trace.records(invoice.get('lines', [])) if trace.ref(item.get('id'))]) for invoice in eligible):
            unattached.append({'kind': 'lineage', 'record_id': line, 'invoice_ref': ident})
    coverage = []
    for key in STAGES:
        rows = [next(node for node in invoice['stages'] if node['id'] == key) for invoice in invoices]
        needs_review = sum(bool(node['gaps']) for node in rows)
        coverage.append({'stage': key, 'title': STAGES[key][1], 'owner': STAGES[key][2],
                         'needs_review': needs_review, 'total': len(rows), 'ask_for': STAGES[key][3]})
    return {'schema': 'savvy-workflow-map/v1', 'input_count': len(sources), 'invoices': invoices, 'coverage': coverage,
            'unattached': unattached, 'duplicate_invoice_ids': duplicates, 'inputs': inventory,
            'graph': trace_entry_graph.build_entry_graph(groups, sources, inventory, lineage)}


def render(report):
    def embedded(value):
        return json.dumps(value, default=str, ensure_ascii=True).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')

    config = {'types': trace_entry_graph.TYPES, 'expected': trace_entry_graph.EXPECTED, 'groups': trace_entry_graph.GRAPH_GROUPS,
              'identifiers': trace_entry_graph.IDENTIFIERS, 'descriptors': trace_entry_graph.DESCRIPTORS,
              'measures': trace_entry_graph.MEASURES, 'aliases': trace_discovery.ALIASES,
              'record_ids': trace_discovery.RECORD_IDS, 'kind_hints': trace_discovery.KIND_HINTS}
    template = TEMPLATE.read_text(encoding='utf-8').replace('@@GENERATED@@', 'ready')
    head, _, body = template.split('<!-- TEMPLATE_NOTICE -->')
    template = head + body
    for name in ('cycle', 'dimensions', 'import', 'import_ui'):
        source = TEMPLATE.with_name(f'trace_workflow_{name}.js').read_text(encoding='utf-8')
        template = template.replace(f'/*@@{name.upper()}_JS@@*/', source)
    return template.replace('@@MAP_CONFIG@@', embedded(config)).replace('@@MAP_DATA@@', embedded(report))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', nargs='*', help='Redacted JSON/CSV files from one account and entity, or - for JSON stdin')
    parser.add_argument('--sample', action='store_true', help='Map two fictional invoices and one unattached payment')
    parser.add_argument('--kind', choices=trace.GROUPS, help='Classify a flat single-kind export with known canonical field names')
    parser.add_argument('--mapping', type=Path, help='Apply a reviewed mapping to one input before mapping its workflow')
    parser.add_argument('--format', choices=('html', 'json'), default='html')
    parser.add_argument('--output', type=Path, help='Write the report to a new file; defaults to stdout')
    args = parser.parse_args(argv)
    if bool(args.inputs) == args.sample or len(args.inputs) > 12 or args.inputs.count('-') > 1:
        parser.error('Use --sample or provide one to twelve redacted input files')
    try:
        sources = []
        for item in [str(SAMPLE)] if args.sample else args.inputs:
            if item == '-':
                sources.append(trace.load(sys.stdin))
            else:
                path = Path(item)
                with path.open(encoding='utf-8-sig') as handle:
                    sources.append(trace.load(handle, is_csv=path.suffix.lower() == '.csv'))
        if args.mapping:
            if len(sources) != 1:
                raise ValueError('Apply a mapping to one input at a time; then combine reviewed bundles')
            with args.mapping.open(encoding='utf-8-sig') as handle:
                sources[0] = trace_discovery.apply_mapping(sources[0], trace.load(handle), trace_entry_graph.GRAPH_GROUPS)
        report = build(sources, args.kind)
        output = render(report) if args.format == 'html' else json.dumps(report, indent=2, default=str) + '\n'
        if args.output:
            with args.output.open('x', encoding='utf-8') as handle:
                handle.write(output)
        else:
            print(output, end='')
    except (ValueError, OSError, TypeError, KeyError, RecursionError) as error:
        parser.exit(2, f'Map stopped: {error}\n')


if __name__ == '__main__':
    main()
