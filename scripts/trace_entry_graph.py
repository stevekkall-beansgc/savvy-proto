"""Link explicit references and report the evidence expected around any entry."""
from collections import Counter, defaultdict, deque

if __package__:
    from . import trace_campfire as trace
else:
    import trace_campfire as trace

TYPES = {
    'source': 'Original source delivery', 'normalized': 'Normalized fact', 'policy': 'Policy assignment',
    'calculation': 'Calculation', 'aggregate': 'Billing aggregate', 'invoice': 'Invoice',
    'statement': 'Statement', 'credit_memo': 'Credit memo', 'debit_memo': 'Debit memo',
    'payment': 'Payment application', 'journal': 'Journal or schedule', 'event': 'Billing event',
    'payable': 'Advisor payable', 'payout': 'Payout or settlement', 'accounting_package': 'Accounting package',
    'report': 'Report or export', 'unmapped': 'Unmapped record',
}
GRAPH_GROUPS = {**trace.GROUPS, 'aggregate': 'aggregates'}
EXPECTED = {
    'source': (None, 'Which normalization run accepted, rejected or superseded this source?'),
    'normalized': ('Which original record, revision and mapping produced this fact?', 'Which frozen calculation selected it?'),
    'policy': ('Which approved agreement and scope establish this assignment?', 'Which calculations used this exact policy version?'),
    'calculation': ('Which normalized facts, policy assignment and manifest were pinned?', 'Which issued bill, payable or rollup consumed the result?'),
    'aggregate': ('Show the measure definition, grain, period and exact contributing records or query manifest.',
                  'Which report, statement, invoice or Finance process consumes the total? Confirm if it is internal only.'),
    'invoice': ('Which calculation issued this document and its lines?', 'Which statement, correction, payment or accounting record refers to it?'),
    'statement': ('Which issued document and exact line populate this statement?', None),
    'credit_memo': ('Which original invoice and reviewed change does the memo correct?', 'Was the credit applied, carried or refunded?'),
    'debit_memo': ('Which original invoice and reviewed change does the memo correct?', 'Which cash or accounting records reflect this debit?'),
    'payment': ('Which invoice and independently confirmed money movement support the application?', 'Where is application, reversal or settlement reflected?'),
    'journal': ('Which invoice, adjustment, posting package or schedule generated this entry?', None),
    'event': ('Which source, approval or original event supports this record?', 'Which calculation, billing document or payout consumes it?'),
    'payable': ('Which earnings, entitlement or calculation created this payable?', 'Which confirmed payout or statement refers to it?'),
    'payout': ('Which approved request and payable does this settle?', 'Which statement or accounting record reflects confirmed settlement?'),
    'accounting_package': ('Which scoped documents, lines and treatment were packaged?', 'Which posting or schedule accepted the package?'),
    'report': ('Which selected rows, period, grouping keys and publication feed this report?', None),
    'unmapped': ('Confirm the record type and reference fields from the export.', 'Identify where the record is used after its mapping is confirmed.'),
}
IDENTIFIERS = ('entity', 'source', 'source_id', 'invoice_id', 'invoice_number', 'invoice_line_id', 'period_start', 'period_end',
               'definition_ref', 'manifest_ref', 'journal_entry', 'schedule_id', 'posting_date', 'cash_confirmation_id',
               'agreement_ref', 'assignment_id', 'input_manifest_id', 'economic_date', 'posting_period', 'original_id', 'revision')
DESCRIPTORS = ('measure', 'grain', 'basis', 'event_type')
MEASURES = ('total_amount', 'amount', 'amount_due', 'applied_amount', 'record_count', 'amount_minor')


def key(reference):
    if not isinstance(reference, dict) or not isinstance(reference.get('kind'), str) or reference['kind'] not in TYPES:
        return None
    alias = trace.ref(reference.get('id'))
    return (reference['kind'], alias) if alias else None


def explicit_links(payload):
    if not isinstance(payload, dict):
        return []
    return trace.records(payload.get('links', []))


def dimension_fields(record):
    """Keep field paths for the coverage review without copying their values."""
    fields = set()
    pending = [((), record)]
    for _ in range(6000):
        if not pending:
            break
        path, value = pending.pop()
        if isinstance(value, dict) and len(path) < 7:
            pending.extend(((*path, key[:120]), child) for key, child in reversed(list(value.items())[:160]))
        elif isinstance(value, list) and len(path) < 7:
            pending.extend(((*path, '[]'), child) for child in reversed(value[:100]))
        elif value is not None and not isinstance(value, (dict, list)) and str(value).strip() and path and len(fields) < 250:
            fields.add(path)
    return [list(path) for path in sorted(fields)]


def declared_dimensions(record):
    fields = ('columns', 'group_by', 'groupBy', 'report_dimensions', 'dimension_keys')
    return list(dict.fromkeys(
        value.strip()[:120] for field in fields if isinstance(record.get(field), list)
        for value in record[field][:100] if isinstance(value, str) and value.strip()
    ))[:100]


def build_entry_graph(groups, sources, input_findings, lineage):
    items = [(kind, row) for kind, rows in groups.items() for row in rows]
    for payload in sources:
        if isinstance(payload, dict) and 'entries' in payload:
            for row in trace.records(payload['entries']):
                kind = row.get('kind')
                if not isinstance(kind, str) or kind not in TYPES or kind == 'unmapped':
                    raise ValueError('Choose a supported kind for each reviewed entry')
                items.append((kind, row))
        if isinstance(payload, dict) and 'aggregates' in payload:
            items.extend(('aggregate', row) for row in trace.records(payload['aggregates']))
    for finding in input_findings:
        if finding['unmapped_count']:
            items.append(('unmapped', {'id': f'input-{finding["input"]}', 'record_count': finding['unmapped_count']}))
    if len(items) > 2000:
        raise ValueError('Narrow the assessment to 2,000 or fewer records')
    counts = Counter((kind, trace.ref(row.get('id'))) for kind, row in items)
    by_identity = {(kind, trace.ref(row.get('id'))): row for kind, row in items}
    nodes, edges, gaps = {}, {}, []

    for index, (kind, row) in enumerate(items):
        alias = trace.ref(row.get('id'))
        node_key = (kind, alias) if alias and counts[(kind, alias)] == 1 else (kind, f'[unresolved {index + 1}]')
        evidence = {name: value for name in IDENTIFIERS if (value := trace.ref(row.get(name)))}
        for name in DESCRIPTORS:
            value = row.get(name)
            if isinstance(value, str) and value.strip():
                evidence[name] = value.strip()[:120]
        evidence.update({name: str(value) for name in MEASURES if (value := trace.money(row.get(name))) is not None})
        if currency := trace.currency(row):
            evidence['currency'] = currency
        node = {'type': kind, 'id': alias, 'label': TYPES[kind], 'state': 'record present', 'evidence': evidence, 'gaps': []}
        if kind != 'unmapped':
            node['observed_fields'] = dimension_fields(row)
        if kind in ('report', 'aggregate'):
            node['declared_dimensions'] = declared_dimensions(row)
        if not alias or counts[(kind, alias)] > 1:
            node['state'] = 'ambiguous identity'
            node['gaps'].append('A stable and unique record ID is required to link this entry.')
        nodes[node_key] = node

    def link(before, after, basis):
        if not before or not after or before == after:
            return
        if any(counts[ref] > 1 for ref in (before, after)):
            gaps.append('A reference points to a duplicate ID. Review versions and entity before linking.')
            return
        for kind, ident in (before, after):
            if (kind, ident) not in nodes:
                nodes[(kind, ident)] = {'type': kind, 'id': ident, 'label': TYPES[kind], 'state': 'reference only', 'evidence': {},
                                       'gaps': ['Retrieve the referenced record and confirm the ID and scope.']}
        left, right = nodes[before]['evidence'], nodes[after]['evidence']
        scope_fields = ['entity', 'currency']
        if before[0] == 'invoice' and after[0] in ('payment', 'credit_memo', 'debit_memo', 'statement', 'journal'):
            scope_fields.append('invoice_number')
        if any(left.get(scope) and right.get(scope) and left[scope] != right[scope] for scope in scope_fields):
            note = 'A proposed link has conflicting entity, currency or invoice number.'
            for reference in (before, after):
                if note not in nodes[reference]['gaps']:
                    nodes[reference]['gaps'].append(note)
            return
        edges[(before, after)] = basis

    for kind, row in items:
        identity = (kind, trace.ref(row.get('id')))
        if identity not in nodes:
            continue
        if kind in ('payment', 'credit_memo', 'debit_memo', 'statement', 'journal') and (invoice_id := trace.ref(row.get('invoice_id'))):
            link(('invoice', invoice_id), identity, 'Recorded invoice ID')
        if kind == 'invoice' and (journal_id := trace.ref(row.get('journal_entry'))):
            journal = by_identity.get(('journal', journal_id), {})
            if trace.ref(journal.get('invoice_id')) not in {None, identity[1]}:
                nodes[identity]['gaps'].append('Invoice and journal point to different invoice IDs.')
            else:
                link(identity, ('journal', journal_id), 'Recorded journal ID')
        if kind == 'aggregate':
            members = row.get('members', [])
            if not isinstance(members, list) or len(members) > 500:
                raise ValueError('Provide a list of up to 500 aggregate members')
            known_members = set()
            for member in members:
                reference = key(member)
                if not reference:
                    nodes[identity]['gaps'].append('A contributing record is missing its kind or stable ID.')
                elif reference in known_members:
                    nodes[identity]['gaps'].append('A contributing record appears more than once. Confirm whether the grain allows repeats.')
                else:
                    known_members.add(reference)
                    link(reference, identity, 'Supplied contributor reference')
            definition = nodes[identity]['evidence']
            missing = [name.replace('_', ' ') for name in ('measure', 'grain', 'period_start', 'period_end', 'basis') if not definition.get(name)]
            if missing:
                nodes[identity]['gaps'].append('Aggregate definition missing ' + ', '.join(missing) + '.')
            if not members and not definition.get('manifest_ref'):
                nodes[identity]['gaps'].append('No contributor list or query manifest supplied. The total cannot establish its membership.')
            elif row.get('members_complete') is not True:
                nodes[identity]['gaps'].append('Contributor completeness has not been confirmed for this measure and period.')
    for payload in sources:
        for row in explicit_links(payload):
            before, after = key(row.get('from')), key(row.get('to'))
            if before and after:
                link(before, after, 'Reviewer-supplied crosswalk')
            else:
                gaps.append('A supplied relationship is missing a supported record type or stable ID.')
    crosswalk_counts = Counter((trace.ref(row.get('invoice_id')), trace.ref(row.get('invoice_line_id'))) for row in lineage)
    for row in lineage:
        invoice, calc = trace.ref(row.get('invoice_id')), trace.ref(row.get('calculation_id'))
        if not (invoice and calc) or counts[('invoice', invoice)] != 1:
            continue
        invoice_row = by_identity[('invoice', invoice)]
        line_id = trace.ref(row.get('invoice_line_id'))
        known_lines = trace.records(invoice_row.get('lines', []))
        if not line_id or sum(trace.ref(line.get('id')) == line_id for line in known_lines) != 1:
            continue
        if crosswalk_counts[(invoice, line_id)] != 1:
            note = 'Multiple crosswalks claim the same invoice line. Confirm the exact version before linking.'
            if note not in nodes[('invoice', invoice)]['gaps']:
                nodes[('invoice', invoice)]['gaps'].append(note)
            continue
        if any(trace.ref(row.get(scope)) and trace.ref(invoice_row.get(scope)) and
               trace.ref(row[scope]) != trace.ref(invoice_row[scope]) for scope in ('entity', 'currency')):
            nodes[('invoice', invoice)]['gaps'].append('An invoice-line crosswalk conflicts on entity or currency.')
            continue
        link(('calculation', calc), ('invoice', invoice), 'Supplied invoice-line crosswalk')
        if policy := trace.ref(row.get('assignment_id')):
            link(('policy', policy), ('calculation', calc), 'Supplied policy assignment reference')
        normalized = row.get('normalized_record_ids', [])
        if isinstance(normalized, list):
            for value in normalized[:100]:
                if fact := trace.ref(value):
                    link(('normalized', fact), ('calculation', calc), 'Supplied selected fact reference')
    if len(nodes) > 3000 or len(edges) > 6000:
        raise ValueError('Narrow the evidence map or review it in smaller batches')
    return pack(nodes, edges, gaps)


def pack(nodes, edges, gaps):
    node_ids = {reference: index for index, reference in enumerate(nodes)}
    ordered = list(nodes.values())
    to, from_ = defaultdict(list), defaultdict(list)
    for (before, after), basis in edges.items():
        to[before].append((after, basis))
        from_[after].append((before, basis))

    def walk(start, graph):
        visited = {start}
        queue = deque([(start, 0)])
        result = []
        while queue and len(result) < 30:
            reference, distance = queue.popleft()
            for neighbor, basis in graph[reference] if distance < 5 else ():
                if neighbor in visited:
                    continue
                visited.add(neighbor)
                result.append({'node': node_ids[neighbor], 'distance': distance + 1, 'basis': basis})
                queue.append((neighbor, distance + 1))
                if len(result) == 30:
                    break
        return result

    packed = []
    coverage = {}
    for reference, item in nodes.items():
        upstream, downstream = walk(reference, from_), walk(reference, to)
        expected_upstream, expected_downstream = EXPECTED[item['type']]
        guidance = []
        for direction, connected, question in [('Upstream', upstream, expected_upstream), ('Downstream', downstream, expected_downstream)]:
            if question:
                unresolved = [row for row in connected if row['distance'] == 1 and ordered[row['node']]['state'] != 'record present']
                state = 'No direct link supplied' if not connected else 'Referenced record missing' if unresolved else 'Confirm evidence'
                guidance.append({'direction': direction, 'state': state, 'ask_for': question})
        if item['state'] != 'reference only':
            row = coverage.setdefault(item['type'], {'type': item['label'], 'records': 0, 'upstream_gaps': 0, 'downstream_gaps': 0, 'record_gaps': 0})
            row['records'] += 1
            row['record_gaps'] += bool(item['gaps'])
            for clue in guidance:
                row[clue['direction'].lower() + '_gaps'] += clue['state'] != 'Confirm evidence'
        packed.append({**item, 'node': node_ids[reference], 'upstream': upstream, 'downstream': downstream, 'guidance': guidance})
    return {'entries': packed, 'links': len(edges), 'link_gaps': sorted(set(gaps)), 'coverage': list(coverage.values())}
