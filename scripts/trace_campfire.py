#!/usr/bin/env python3
"""Trace redacted JSON from one Campfire or statement object into Savvy billing."""
import argparse
import csv
import io
import json
import re
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path

if __package__:
    from . import trace_discovery
else:
    import trace_discovery

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / 'fixtures/campfire-trace/harbor.json'
PROTOTYPE = ROOT / 'docs/architecture/lifecycle-run.json'
GROUPS = {'invoice': 'invoices', 'payment': 'payments', 'credit_memo': 'credit_memos',
          'debit_memo': 'debit_memos', 'journal': 'journals', 'statement': 'statements'}
LIMIT = 2_000_000
ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}\Z')
MONEY = re.compile(r'-?\d{1,15}(?:\.\d{1,9})?\Z')


class UnknownShape(ValueError):
    pass


def ref(value):
    """Accept scalar aliases, including an explicit related-object ID."""
    if isinstance(value, dict):
        value = value.get('id')
    if type(value) in (str, int) and ID.fullmatch(str(value)):
        return str(value)
    return None


def money(value):
    if type(value) in (str, int, Decimal) and MONEY.fullmatch(str(value)):
        return Decimal(value)
    return None


def day(value):
    if isinstance(value, str) and re.fullmatch(r'\d{4}-\d\d-\d\d', value):
        try:
            return date.fromisoformat(value)
        except ValueError:
            pass
    return None


def currency(record):
    value = record.get('currency')
    return value if isinstance(value, str) and re.fullmatch(r'[A-Z]{3}', value) else None


def records(value):
    if isinstance(value, dict) and 'results' in value:
        value = value['results']
    elif isinstance(value, dict):
        value = [value]
    if not isinstance(value, list) or len(value) > 500 or not all(isinstance(row, dict) for row in value):
        raise ValueError('Expected an object, a list of up to 500 objects, or a results wrapper')
    return value


def infer(row):
    if 'invoice_id' in row and 'payment_type' in row:
        return 'payment'
    if 'invoice_number' in row and ('total_amount' in row or 'lines' in row):
        return 'invoice'
    raise UnknownShape('The record does not use a recognized invoice or payment shape')


def select(rows, identifier):
    matches = rows if identifier is None else [row for row in rows if ref(row.get('id')) == identifier]
    if len(matches) != 1:
        raise ValueError('Select one unique record with --id or the bundle anchor')
    return matches[0]


def input_bundle(payload, kind, identifier):
    if isinstance(payload, dict) and any(group in payload for group in GROUPS.values()):
        anchor = payload.get('anchor', {})
        if not isinstance(anchor, dict):
            raise ValueError('The anchor must be an object')
        kind = kind or anchor.get('kind')
        if not isinstance(kind, str) or kind not in GROUPS:
            raise ValueError('Set anchor.kind to one of: ' + ', '.join(GROUPS))
        identifier = identifier or ref(anchor.get('id'))
        groups = {key: records(payload.get(group, [])) for key, group in GROUPS.items()}
        return payload, groups, kind, select(groups[kind], identifier)
    row = select(records(payload), identifier)
    kind = kind or infer(row)
    return {}, {key: [row] if key == kind else [] for key in GROUPS}, kind, row


def known_shape(payload):
    if isinstance(payload, dict) and isinstance(payload.get('anchor'), dict) and any(group in payload for group in GROUPS.values()):
        return True
    try:
        rows = records(payload)
        if len(rows) != 1:
            return False
        infer(rows[0])
        return True
    except ValueError:
        return False


def match_invoice(kind, anchor, invoices):
    if kind == 'invoice':
        return anchor
    if kind == 'journal':
        identifier = ref(anchor.get('id'))
        candidates = [inv for inv in invoices if identifier and ref(inv.get('journal_entry')) == identifier]
        explicit = ref(anchor.get('invoice_id'))
        if explicit:
            candidates = [inv for inv in candidates if ref(inv.get('id')) == explicit] if candidates else [inv for inv in invoices if ref(inv.get('id')) == explicit]
    else:
        identifier = ref(anchor.get('invoice_id'))
        candidates = [inv for inv in invoices if identifier and ref(inv.get('id')) == identifier]
    if len(candidates) != 1:
        return None
    invoice = candidates[0]
    # Keep equal amounts and names out of identity resolution.
    for key in ['entity', 'invoice_number', 'currency']:
        left, right = ref(anchor.get(key)), ref(invoice.get(key))
        if left and right and left != right:
            return None
    return invoice


def inspect(payload, kind=None, identifier=None, prototype=None):
    bundle, groups, kind, anchor = input_bundle(payload, kind, identifier)
    invoice = match_invoice(kind, anchor, groups['invoice'])
    report = {'anchor': {'type': kind, 'id': ref(anchor.get('id'))}, 'workflow': [], 'line_reconciliation': []}

    def step(stage, status, details, next_action=None):
        row = {'stage': stage, 'status': status, 'evidence': details}
        if next_action:
            row['ask_for'] = next_action
        report['workflow'].append(row)

    if invoice is None:
        links = {key: value for key in ['invoice_id', 'invoice_number', 'entity', 'currency'] if (value := ref(anchor.get(key)))}
        step('Campfire → native invoice', 'reference only' if links else 'missing', links,
             'The original invoice with its entity, currency and lines. For a journal, look for invoice.journal_entry or a confirmed invoice ID.')
        step('Policy → calculation → source', 'missing', {}, 'Find the invoice before attempting to infer a rate or a balance.')
        return report

    invoice_id = ref(invoice.get('id'))
    requested_line = ref(bundle.get('line_id') or (anchor.get('invoice_line_id') if kind == 'statement' else None))
    lines = records(invoice.get('lines', []))
    if requested_line:
        lines = [line for line in lines if ref(line.get('id')) == requested_line]
    crosswalks = [item for item in records(bundle.get('lineage', [])) if invoice_id and ref(item.get('invoice_id')) == invoice_id]
    step('Campfire → native invoice', 'observed', {
        key: value for key in ['id', 'invoice_number', 'entity', 'currency', 'source', 'source_id', 'contract', 'revenue_contract', 'journal_entry']
        if (value := ref(invoice.get(key)))
    }, 'Confirm the external identity and entity in Savvy. Campfire source_id is a reference, even when it looks like a Savvy ID.')
    dates = {key: value.isoformat() for key in ('invoice_date', 'period_start', 'period_end', 'due_date') if (value := day(invoice.get(key)))}
    line_ids = [ref(line.get('id')) for line in lines]
    statement_lines = [ref(row.get('invoice_line_id')) for row in groups['statement']
                       if 'invoice_line_id' in row and invoice_id and match_invoice('statement', row, [invoice])]
    linked_lines = sorted({line_id for line_id in statement_lines if line_id and line_ids.count(line_id) == 1})
    step('Statement → invoice line', 'linked' if linked_lines else 'observed' if lines else 'missing',
         {'recorded_dates': dates, 'line_ids': line_ids, 'statement_linked_lines': linked_lines},
         'Confirm the line-level statement reference and service-date convention. Invoice issue and accounting posting dates are separate.')
    for line in lines:
        line_id = ref(line.get('id'))
        unique_line = line_id and line_ids.count(line_id) == 1
        matched = [item for item in crosswalks if unique_line and ref(item.get('invoice_line_id')) == line_id]
        crosswalk = matched[0] if len(matched) == 1 else {}
        info = {key: value for key in ['savvy_invoice_line_id', 'calculation_id', 'policy_version_id', 'assignment_id', 'agreement_ref', 'input_manifest_id']
                if (value := ref(crosswalk.get(key)))}
        sources = crosswalk.get('source_record_ids', [])
        if isinstance(sources, list) and (source_ids := [value for raw in sources[:100] if (value := ref(raw))]):
            info['source_record_ids'] = source_ids
        line_ref = {'line_id': line_id, 'recorded_amount': money(line.get('amount')),
                    'tax': money(line.get('tax')), 'invoice_quantity': money(line.get('quantity')),
                    'invoice_rate': money(line.get('rate')), 'currency': currency(line) or currency(invoice),
                    'service_date': day(line['service_date']).isoformat() if day(line.get('service_date')) else None}
        missing = [key for key in ('savvy_invoice_line_id', 'calculation_id', 'policy_version_id', 'assignment_id', 'agreement_ref', 'input_manifest_id', 'source_record_ids') if not info.get(key)]
        status = 'ambiguous supplied links' if len(matched) > 1 or (line_id and not unique_line) else 'supplied crosswalk' if info and not missing else 'partial crosswalk' if crosswalk else 'missing'
        step('Invoice line → calculation → policy → source', status, {**line_ref, **info, 'missing': missing},
             'Follow the supplied IDs to the frozen run, approval, selected policy and raw/network records. ERP line rate and quantity alone are insufficient.')
        independent = money(crosswalk.get('expected_line_amount'))
        if independent is not None and line_ref['recorded_amount'] is not None and currency(crosswalk) == line_ref['currency'] and line_ref['currency']:
            report['line_reconciliation'].append({'line_id': line_id, 'currency': line_ref['currency'],
                'expected_amount': independent, 'observed_amount': line_ref['recorded_amount'],
                'observed_less_expected': line_ref['recorded_amount'] - independent})
    if not lines:
        step('Invoice line → calculation → policy → source', 'missing', {}, 'Request the matching line, effective agreement, policy assignment, dated input records and calculation or source-system trace.')
    related = {key: [row for row in groups[key] if invoice_id and ref(row.get('invoice_id')) == invoice_id]
               for key in ('credit_memo', 'debit_memo', 'payment')}
    step('Invoice → corrections → cash', 'linked' if any(related.values()) else 'missing',
         {key: [{**{field: value for field in ('id', 'external_id', 'payment_type', 'payment_date', 'applied_on', 'voided_date', 'cash_confirmation_id')
                   if (value := ref(row.get(field)))}, 'amount': money(row.get('amount' if key == 'payment' else 'applied_amount')),
                 'currency': currency(row)} for row in values] for key, values in related.items()},
         'Confirm which memo amounts were applied and get processor or bank confirmation for cash applications. A credit memo payment is an adjustment, not cash.')
    journal_ref = ref(invoice.get('journal_entry'))
    journal_candidates = [row for row in groups['journal'] if journal_ref and ref(row.get('id')) == journal_ref]
    journal = journal_candidates[0] if len(journal_candidates) == 1 else None
    if journal and ref(journal.get('invoice_id')) not in {None, invoice_id}:
        journal = None
    step('Invoice → accounting', 'linked' if journal else 'reference only' if journal_ref else 'missing',
         {'journal_ref': journal_ref, 'recognition_schedule_ref': ref(journal.get('schedule_id')) if journal else None,
          'posting_date': ref(journal.get('posting_date')) if journal else None},
         'Confirm the accounting period, recognized and deferred amounts, and any reversal. A posting reference alone is not a recognition schedule.')
    report['invoice_balance'] = balance(bundle, invoice, related)
    if prototype:
        report['prototype'] = compare_prototype(invoice, report['invoice_balance'], prototype)
    return report


def balance(bundle, invoice, related):
    total = money(invoice.get('total_amount'))
    observed = money(invoice.get('amount_due'))
    curr = currency(invoice)
    as_of = day(bundle.get('as_of'))
    result = {'currency': curr, 'original_invoice_total': total, 'reported_balance': observed}
    if not as_of or bundle.get('complete_associations') is not True:
        return {**result, 'status': 'insufficient evidence', 'reason': 'Supply all linked applications/corrections and an as-of date for the same invoice and confirm completeness.'}
    issue_date = day(invoice.get('invoice_date'))
    if (not ref(invoice.get('id')) or total is None or not curr or total < 0 or not issue_date or issue_date > as_of
            or invoice.get('voided_date') or invoice.get('is_deleted') or invoice.get('payment_status') == 'draft'):
        return {**result, 'status': 'insufficient evidence', 'reason': 'The original issued invoice, amount, currency or issue date is not established.'}
    amounts = {key: Decimal(0) for key in related}
    for key, rows in related.items():
        seen = set()
        for row in rows:
            ident = ref(row.get('id'))
            entry_day = day(row.get('payment_date' if key == 'payment' else 'applied_on'))
            void = day(row.get('voided_date'))
            if not ident or ident in seen or not entry_day or (row.get('voided_date') and not void):
                return {**result, 'status': 'insufficient evidence', 'reason': 'Missing transaction identity or date, duplicate record, or invalid void date.'}
            seen.add(ident)
            if entry_day > as_of or (void and void <= as_of):
                continue
            if any(ref(row.get(field)) and ref(invoice.get(field)) and ref(row.get(field)) != ref(invoice.get(field)) for field in ('entity', 'invoice_number')):
                return {**result, 'status': 'insufficient evidence', 'reason': 'An associated row has a conflicting entity or invoice number.'}
            value = money(row.get('amount' if key == 'payment' else 'applied_amount'))
            if key == 'payment' and row.get('payment_type') == 'CREDIT_MEMO':
                return {**result, 'status': 'insufficient evidence', 'reason': 'Represent a credit memo application once as an applied credit; remove its duplicate payment representation.'}
            if key == 'payment' and (row.get('application_kind') not in ('receipt', 'refund') or not ref(row.get('cash_confirmation_id'))):
                return {**result, 'status': 'insufficient evidence', 'reason': 'Classify each Campfire payment application as receipt or refund and supply independent cash confirmation.'}
            if value is None or value < 0 or currency(row) != curr:
                return {**result, 'status': 'insufficient evidence', 'reason': 'An associated row has an invalid amount or a different or missing currency.'}
            amounts[key] += -value if key == 'payment' and row.get('application_kind') == 'refund' else value
    net = total + amounts['debit_memo'] - amounts['credit_memo']
    computed = net - amounts['payment']
    variance = observed - computed if observed is not None else None
    return {**result, 'as_of': as_of.isoformat(), 'status': 'matches' if variance == 0 else 'variance' if variance is not None else 'computed only',
            'debit_notes': amounts['debit_memo'], 'credit_notes': amounts['credit_memo'], 'net_billed': net,
            'net_confirmed_cash_applied': amounts['payment'], 'computed_balance': computed, 'observed_less_computed': variance}


def compare_prototype(invoice, reconciliation, proof):
    if proof.get('schema') != 'billing-lifecycle-proof/v1' or proof.get('synthetic') is not True:
        raise ValueError('Expected the synthetic Savvy lifecycle export as prototype reference')
    document_id = ref(invoice.get('source_id')) if invoice.get('source') == 'savvy' else None
    cases = [case for case in proof['cases'] if document_id and case['billing']['target_id'] == document_id]
    if len(cases) != 1:
        return {'status': 'unmatched', 'reason': 'No unique Savvy document ID in the supplied synthetic lifecycle reference.'}
    billed = Decimal(cases[0]['billing']['assessed_minor']) / 100
    reference = {'status': 'exact recorded ID', 'case': cases[0]['case_id'], 'currency': 'USD', 'recorded_net_billed': billed}
    if reconciliation.get('currency') == 'USD' and 'net_billed' in reconciliation:
        reference['net_billed_variance'] = reconciliation['net_billed'] - billed
    return reference


def load(handle, *, is_csv=False, columns=()):
    text = handle.read(LIMIT + 1)
    if len(text) > LIMIT:
        raise ValueError('Input exceeds the two-million-character review limit')
    if is_csv:
        reader = csv.DictReader(io.StringIO(text))
        headers = reader.fieldnames or []
        if not headers or len(set(headers)) != len(headers):
            raise ValueError('CSV needs unique column headers')
        mapping = {}
        for column in columns:
            field, separator, header = column.partition('=')
            if not separator or not ref(field) or header not in headers or field in mapping:
                raise ValueError('Use one --column field=Exact CSV Header per mapped field')
            mapping[field] = header
        rows = []
        for row in reader:
            if len(rows) == 500 or None in row or any(value is None for value in row.values()):
                raise ValueError('CSV needs consistent columns and at most 500 data rows')
            rows.append({**row, **{field: row[header] for field, header in mapping.items()}})
        return rows
    def unique_fields(pairs):
        result = dict(pairs)
        if len(result) != len(pairs):
            raise ValueError('JSON contains a duplicate field name')
        return result
    return json.loads(text, parse_float=Decimal, parse_constant=lambda _: None, object_pairs_hook=unique_fields)


def markdown(report):
    def v(value):
        if isinstance(value, dict):
            return '; '.join(f'{k.replace("_", " ")} {v(item)}' for k, item in value.items() if item is not None) or '—'
        if isinstance(value, list):
            return ', '.join(v(item) for item in value) or '—'
        return '—' if value is None else str(value)

    output = ['# Savvy workflow trace', '', 'Anchor: ' + v(report['anchor']), '']
    for section in report['workflow']:
        output.extend([f"## {section['stage']} · {section['status']}", '', v(section['evidence']), '', f"Next evidence: {section['ask_for']}", ''])
    for key in ['line_reconciliation', 'invoice_balance', 'prototype']:
        if report.get(key):
            output.extend([f'## {key.replace("_", " ").capitalize()}', '', v(report[key]), ''])
    return '\n'.join(output)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', nargs='?', help='Redacted JSON or CSV file, or - to paste JSON on stdin')
    parser.add_argument('--sample', action='store_true', help='Run the fictional Harbor RIA example')
    parser.add_argument('--kind', choices=(*GROUPS, 'aggregate'))
    parser.add_argument('--id', help='Select one exact anchor ID from a list')
    parser.add_argument('--column', action='append', default=[], metavar='FIELD=HEADER', help='Map a CSV header to an explicit field')
    parser.add_argument('--prototype', type=Path, help='Compare by document ID with a synthetic Savvy lifecycle export')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--discover', action='store_true', help='Propose types and field paths for an unfamiliar export')
    mode.add_argument('--mapping', type=Path, help='Use a reviewed field mapping before tracing')
    parser.add_argument('--record-path', help='Focus discovery on a JSON path array, such as ["rows", 0]')
    parser.add_argument('--format', choices=('markdown', 'json', 'mapping', 'bundle'), default='markdown')
    args = parser.parse_args(argv)
    if bool(args.input) == args.sample:
        parser.error('Choose one input file, - or --sample')
    is_csv = bool(args.input and Path(args.input).suffix.lower() == '.csv')
    if args.column and not is_csv:
        parser.error('--column applies to CSV exports')
    if args.format == 'mapping' and not args.discover:
        parser.error('--format mapping requires --discover')
    if args.format == 'bundle' and not args.mapping:
        parser.error('--format bundle requires a reviewed --mapping')
    if args.record_path and not args.discover:
        parser.error('--record-path requires --discover')
    if args.kind == 'aggregate' and not args.discover:
        parser.error('Use --discover for aggregate fields and trace_workflow_map.py for the trace')
    try:
        if args.input == '-':
            payload = load(sys.stdin)
        else:
            with (SAMPLE if args.sample else Path(args.input)).open(encoding='utf-8-sig') as handle:
                payload = load(handle, is_csv=is_csv, columns=args.column)
        if args.discover:
            path = json.loads(args.record_path) if args.record_path else None
            if args.record_path and not isinstance(path, list):
                raise ValueError('Use a JSON path array for --record-path')
            emit_discovery(payload, args.kind, args.format, path)
            return
        if args.mapping:
            with args.mapping.open(encoding='utf-8-sig') as handle:
                payload = trace_discovery.apply_mapping(payload, load(handle), GROUPS)
            if args.format == 'bundle':
                print(json.dumps(payload, indent=2, default=str))
                return
        elif not args.kind and not args.id and not known_shape(payload):
            emit_discovery(payload, None, args.format)
            return
        prototype = None
        if args.prototype or args.sample:
            with (args.prototype or PROTOTYPE).open(encoding='utf-8') as handle:
                prototype = load(handle)
        report = inspect(payload, args.kind, args.id, prototype)
    except UnknownShape:
        emit_discovery(payload, args.kind, args.format)
        return
    except (ValueError, OSError, KeyError, TypeError, RecursionError, csv.Error) as error:
        parser.exit(2, f'Trace stopped: {error}\n')
    print(json.dumps(report, indent=2, default=str) if args.format == 'json' else markdown(report))


def emit_discovery(payload, kind, output_format, record_path=None):
    report = trace_discovery.discover(payload, kind, record_path)
    if output_format == 'json':
        print(json.dumps(report, indent=2))
    elif output_format == 'mapping':
        print(json.dumps(report['draft_mapping'], indent=2))
    else:
        print(trace_discovery.markdown(report))


if __name__ == '__main__':
    main()
