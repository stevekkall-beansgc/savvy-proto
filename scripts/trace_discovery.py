"""Offer explainable field guesses for an unfamiliar export. No external calls."""
import json
import re
from datetime import date
from decimal import Decimal

# Only the names on the left are used by the trace. Alternatives are search clues.
COMMON_FIELDS = {'id', 'invoice_id', 'invoice_number', 'entity', 'currency', 'voided_date'}
FIELDS = {
    'invoice': ('total_amount', 'amount_due', 'invoice_date', 'due_date', 'period_start', 'period_end',
                'source', 'source_id', 'contract', 'revenue_contract', 'journal_entry', 'payment_status', 'is_deleted'),
    'payment': ('amount', 'payment_date', 'payment_type', 'external_id', 'application_kind', 'cash_confirmation_id'),
    'credit_memo': ('applied_amount', 'applied_on'),
    'debit_memo': ('applied_amount', 'applied_on'),
    'journal': ('posting_date', 'schedule_id'),
    'statement': ('invoice_line_id',),
    'aggregate': ('measure', 'grain', 'basis', 'definition_ref', 'manifest_ref', 'period_start', 'period_end', 'total_amount'),
}

# Match whole labels. For example, a generic amount does not establish a gross invoice total.
ALIASES = {
    'id': 'id|identifier|record id|record key|object id|uid',
    'invoice_id': 'invoice id|invoice key|invoice reference|bill id|billing document id',
    'invoice_number': 'invoice number|invoice no|bill number|document number',
    'entity': 'entity|entity id|legal entity id|company id|subsidiary id',
    'currency': 'currency|currency code|iso currency|transaction currency',
    'voided_date': 'voided date|void date|voided on',
    'total_amount': 'total amount|invoice total|invoice amount|grand total|gross amount',
    'amount_due': 'amount due|open balance|outstanding amount|remaining balance|balance due',
    'invoice_date': 'invoice date|issued on|issued date|issue date',
    'due_date': 'due date|due on', 'period_start': 'period start|service period start|service start|coverage start',
    'period_end': 'period end|service period end|service end|coverage end',
    'source': 'source|source system|origin system', 'source_id': 'source id|upstream id|origin record id|source record id',
    'contract': 'contract|contract id|agreement id|agreement reference', 'revenue_contract': 'revenue contract|revenue contract id',
    'journal_entry': 'journal entry|journal entry id|journal id|ledger entry id|posting id', 'payment_status': 'payment status|invoice status',
    'is_deleted': 'is deleted|deleted', 'amount': 'amount|payment amount|paid amount|applied amount|receipt amount',
    'payment_date': 'payment date|paid on|receipt date|received on', 'payment_type': 'payment type|tender type|payment method',
    'external_id': 'external id|source id|processor reference', 'application_kind': 'application kind|cash application kind',
    'cash_confirmation_id': 'cash confirmation id|bank confirmation id|settlement reference',
    'applied_amount': 'applied amount|credit applied|applied credit|debit applied|applied debit',
    'applied_on': 'applied on|application date|credit applied date|debit applied date',
    'posting_date': 'posting date|posted on|ledger date', 'schedule_id': 'schedule id|recognition schedule id|revenue schedule id',
    'invoice_line_id': 'invoice line id|invoice item id|bill line id',
    'measure': 'measure|metric|measure name|metric name', 'grain': 'grain|aggregation grain|grouped by',
    'basis': 'basis|amount basis|measure basis|total basis', 'definition_ref': 'definition ref|query id|metric definition id',
    'manifest_ref': 'manifest ref|manifest id|contributor manifest id',
}
RECORD_IDS = {
    'invoice': 'invoice id|bill id|document id', 'payment': 'payment id|receipt id|application id',
    'credit_memo': 'credit memo id|credit note id|memo id', 'debit_memo': 'debit memo id|debit note id|memo id',
    'journal': 'journal id|journal entry id|ledger entry id|posting id', 'statement': 'statement id|client statement id|statement entry id',
    'aggregate': 'aggregate id|rollup id|report id',
}
LINE_ALIASES = { 'id': 'id|line id|invoice line id|item id|entry key|line key',
    'amount': 'amount|line amount|extended amount|line total|charge amount', 'tax': 'tax|tax amount|line tax',
    'quantity': 'quantity|units|unit count', 'rate': 'rate|unit price|unit rate',
    'currency': ALIASES['currency'], 'service_date': 'service date|charge date|service on'}
KIND_HINTS = {'invoice': ('invoice', 'bill'), 'payment': ('payment', 'receipt', 'remittance'),
              'credit_memo': ('credit memo', 'credit note'), 'debit_memo': ('debit memo', 'debit note'),
              'journal': ('journal', 'ledger entry'), 'statement': ('statement',), 'aggregate': ('aggregate', 'rollup', 'summary')}


def words(key):
    return ' '.join(re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', key).lower().replace('_', ' ').replace('-', ' ').split())


def shape(value):
    if value is None:
        return 'empty'
    if isinstance(value, bool):
        return 'boolean'
    if isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
        try:
            date.fromisoformat(value)
            return 'date'
        except ValueError:
            pass
    if isinstance(value, str) and re.fullmatch(r'[A-Z]{3}', value):
        return 'three uppercase letters'
    if isinstance(value, (int, Decimal)) or (isinstance(value, str) and re.fullmatch(r'-?\d+(\.\d+)?', value)):
        return 'number'
    return 'text'


def compatible(field, value):
    actual = shape(value)
    if field in {'amount', 'total_amount', 'amount_due', 'applied_amount', 'tax', 'rate', 'quantity'}:
        return actual == 'number'
    if field == 'currency':
        return actual == 'three uppercase letters'
    if field.endswith(('_date', '_on', '_start', '_end')):
        return actual in ('date', 'empty')
    if field == 'is_deleted':
        return actual == 'boolean'
    return actual not in ('boolean', 'empty')


def leaves(obj, prefix=(), depth=0):
    for name, value in list(obj.items())[:120]:
        path = (*prefix, name)
        if isinstance(value, dict) and depth < 3:
            yield from leaves(value, path, depth + 1)
        elif not isinstance(value, (list, dict)):
            yield path, value


def field_guesses(row, aliases):
    choices = {}
    values = list(leaves(row))
    for field, names in aliases.items():
        labels = set(names.split('|')) | {field.replace('_', ' ')}
        found = []
        for path, value in values:
            name = words(path[-1])
            # A nested identifier is only a record ID when its enclosing name
            # establishes the meaning (e.g. agreement.id → agreement id).
            enclosing = words(path[-2]) + ' ' + name if len(path) > 1 else ''
            direct = name in labels and (len(path) == 1 or name != 'id')
            qualified = enclosing in labels
            if (direct or qualified) and compatible(field, value):
                score = (4 if len(path) == 1 else 3) if direct else 2
                if field == 'id' and name not in ALIASES['id'].split('|'):
                    score += 1
                found.append((score, {'path': list(path), 'shape': shape(value),
                                      'reason': 'field name match' if direct else 'related object and field names match'}))
        found.sort(key=lambda pair: -pair[0])
        if found:
            choices[field] = [option for _, option in found[:5]]
    return choices


def objects(payload):
    """Inspect a bounded sample, showing exact paths to the records considered."""
    pending = [((), payload)]
    for _ in range(100):
        if not pending:
            return
        path, item = pending.pop(0)
        if len(path) > 6:
            continue
        if isinstance(item, dict):
            yield path, item
            pending.extend(((*path, key), child) for key, child in list(item.items())[:35] if isinstance(child, (list, dict)))
        elif isinstance(item, list):
            pending.extend(((*path, index), child) for index, child in enumerate(item[:3]) if isinstance(child, (list, dict)))


def aliases_for(kind):
    allowed = COMMON_FIELDS | set(FIELDS[kind])
    if kind in ('invoice', 'aggregate'):
        allowed.remove('invoice_id')  # Map these record identifiers to their own id.
    aliases = {field: ALIASES[field] for field in sorted(allowed)}
    aliases['id'] += '|' + RECORD_IDS[kind]
    return aliases


def kind_signals(row, path, kind, choices):
    signals = []
    names = [words(key) for key in path if isinstance(key, str)]
    names.extend(words(row[key]) for key in ('type', 'kind', 'objectType', 'documentType') if isinstance(row.get(key), str))
    if any(re.search(r'\b' + re.escape(hint) + r'(?:s)?\b', name) for hint in KIND_HINTS[kind] for name in names):
        signals.append('container or type label')
    if any(words(option['path'][-1]) in RECORD_IDS[kind].split('|') for option in choices.get('id', [])):
        signals.append('type-specific ID field')
    signals.extend(field.replace('_', ' ') for field in FIELDS[kind] if field not in COMMON_FIELDS and field in choices)
    if kind == 'invoice' and 'invoice_number' in choices and 'invoice_id' not in choices:
        signals.append('invoice number without a separate parent invoice reference')
    return signals


def line_arrays(row):
    candidates = []
    for path, value in objects(row):
        if not path or type(path[-1]) is not int or path[-1] != 0:
            continue
        label = path[-2] if len(path) > 1 else ''
        if not isinstance(label, str) or not set(words(label).split()) & {'lines', 'line', 'items', 'item', 'entries', 'charges', 'details', 'detail'}:
            continue
        fields = field_guesses(value, LINE_ALIASES)
        if fields:
            candidates.append({'path': list(path[:-1]), 'fields': fields})
    return candidates[:3]


def one_path_fields(options):
    proposed = {field: alternatives[0]['path'] for field, alternatives in options.items() if len(alternatives) == 1}
    # A path reused for two meanings remains a review decision.
    return {field: path for field, path in proposed.items() if list(proposed.values()).count(path) == 1}


def discover(payload, kind=None, record_path=None):
    ranked = []
    inventory = []
    selected = at(payload, record_path) if record_path is not None else None
    if record_path is not None and not isinstance(selected, dict):
        raise ValueError('The selected discovery path must point to a record object')
    candidates_to_scan = objects(payload) if selected is None else [(record_path, selected)]
    for path, row in candidates_to_scan:
        if len(inventory) < 10:
            leaf_paths = [{'path': list(field), 'shape': shape(value)} for field, value in list(leaves(row))[:20]]
            if leaf_paths:
                inventory.append({'record_path': list(path), 'fields': leaf_paths})
        options = []
        for name in [kind] if kind else FIELDS:
            guesses = field_guesses(row, aliases_for(name))
            signals = kind_signals(row, path, name, guesses)
            if signals or (kind and guesses):
                options.append({'kind': name, 'signals': signals, 'fields': guesses})
        options.sort(key=lambda option: -len(option['signals']))
        if options:
            strongest = options[0]
            determined = bool(kind) or (len(strongest['signals']) >= 2 and
                (len(options) == 1 or len(strongest['signals']) > len(options[1]['signals'])))
            field_depth = sum(len(choices[0]['path']) for choices in strongest['fields'].values()) / max(1, len(strongest['fields']))
            ranked.append((len(strongest['signals']), field_depth, {'record_path': list(path),
                'proposed_kind': strongest['kind'] if determined else None, 'options': options[:3],
                'line_arrays': line_arrays(row) if strongest['kind'] == 'invoice' else []}))
    ranked.sort(key=lambda item: (-item[0], item[1]))
    candidates = [candidate for _, _, candidate in ranked[:5]]
    return {'status': 'proposed, requires review', 'candidates': candidates,
            'shape_inventory': inventory, 'draft_mapping': draft(candidates)}


def draft(candidates):
    config = {'reviewed': False, 'mappings': []}
    if not candidates:
        return config
    best = candidates[0]
    mapping = {'kind': best['proposed_kind'], 'path': best['record_path'],
               'fields': one_path_fields(best['options'][0]['fields'])}
    if len(best['line_arrays']) == 1:
        lines = best['line_arrays'][0]
        mapping['lines'] = {'path': lines['path'], 'fields': one_path_fields(lines['fields'])}
    config['mappings'].append(mapping)
    return config


def at(value, path):
    if not isinstance(path, list) or len(path) > 12:
        raise ValueError('Use a bounded JSON path array, such as ["records", 0]')
    for section in path:
        if isinstance(value, dict) and isinstance(section, str) and section in value:
            value = value[section]
        elif isinstance(value, list) and type(section) is int and 0 <= section < len(value):
            value = value[section]
        else:
            raise ValueError('Reviewed source path is missing: ' + json.dumps(path))
    return value


def mapped_fields(obj, fields, allowed):
    if not isinstance(obj, dict) or not isinstance(fields, dict) or not set(fields) <= allowed:
        raise ValueError('Mapped fields must use canonical names for the selected record type')
    output = {field: at(obj, path) for field, path in fields.items()}
    if any(isinstance(value, (dict, list)) for value in output.values()):
        raise ValueError('Map to scalar fields, not whole objects')
    return output


def apply_mapping(payload, config, groups):
    if not isinstance(config, dict) or config.get('reviewed') is not True:
        raise ValueError('Confirm the field paths and set reviewed to true before applying the mapping')
    mappings = config.get('mappings')
    if not isinstance(mappings, list) or not 1 <= len(mappings) <= 20:
        raise ValueError('Provide one to twenty reviewed record mappings')
    result = {key: [] for key in groups.values()}
    for mapping in mappings:
        if not isinstance(mapping, dict):
            raise ValueError('Each reviewed record mapping must be an object')
        kind = mapping.get('kind')
        if not isinstance(kind, str) or kind not in groups:
            raise ValueError('Choose a supported kind for every reviewed record mapping')
        source = at(payload, mapping.get('path'))
        record = mapped_fields(source, mapping.get('fields'), set(aliases_for(kind)))
        if 'lines' in mapping:
            if kind != 'invoice':
                raise ValueError('Only an invoice mapping can include lines')
            spec = mapping['lines']
            if not isinstance(spec, dict):
                raise ValueError('The lines mapping must be an object')
            lines = at(source, spec.get('path'))
            if not isinstance(lines, list) or len(lines) > 500:
                raise ValueError('Invoice lines must be an array of up to 500 rows')
            record['lines'] = [mapped_fields(line, spec.get('fields'), set(LINE_ALIASES)) for line in lines]
        result[groups[kind]].append(record)
    # Discovery establishes neither completeness nor independent cash confirmation.
    result['anchor'] = config.get('anchor', {'kind': mappings[0]['kind']})
    return result


def markdown(report):
    lines = ['# Export discovery', '', 'Proposals only. Confirm the fields before tracing.', '']
    if not report['candidates']:
        lines.extend(['No recognizable billing fields. Ask for the export column definitions.', ''])
        for item in report['shape_inventory']:
            lines.append('## Record ' + json.dumps(item['record_path']))
            lines.extend('- ' + json.dumps(field['path']) + ' (' + field['shape'] + ')' for field in item['fields'])
        return '\n'.join(lines)
    for item in report['candidates'][:3]:
        lines.append('## Record ' + json.dumps(item['record_path']))
        lines.append('Proposed type: ' + (item['proposed_kind'] or 'uncertain'))
        for option in item['options']:
            lines.extend(['', f"{option['kind']}: " + (', '.join(option['signals']) or 'reviewer hint')])
            for field, choices in option['fields'].items():
                details = ', '.join(json.dumps(choice['path']) + ' (' + choice['shape'] + ')' for choice in choices)
                lines.append(f'- {field}: {details}' + (' — ambiguous' if len(choices) > 1 else ''))
        for option in item['line_arrays']:
            lines.append(f"- Possible invoice lines: {json.dumps(option['path'])}")
        lines.append('')
    lines.append('Use --discover --format mapping to make an editable draft.')
    return '\n'.join(lines)
