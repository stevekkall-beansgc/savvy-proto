#!/usr/bin/env python3
"""Read-only acceptance for the isolated disclosure API and local preview."""
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
API = 'http://127.0.0.1:3102/graphql'
PREVIEW = os.environ.get('SAVVY_PREVIEW_ORIGIN', 'http://127.0.0.1:3104')
if PREVIEW not in {'http://127.0.0.1:3103', 'http://127.0.0.1:3104'}:
    raise ValueError('Acceptance only targets isolated local previews')
checks = []

def check(condition, label):
    if not condition:
        raise AssertionError(label)
    checks.append(label)

def request(role, query, endpoint=API, origin=None):
    headers = {'Content-Type': 'application/json', 'X-Demo-Role': role}
    if origin:
        headers['Origin'] = origin
    req = urllib.request.Request(endpoint, data=json.dumps({'query': query}).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        try:
            return error.code, json.load(error)
        except (ValueError, UnicodeDecodeError):
            return error.code, {}

def read(role, field, endpoint=API):
    status, response = request(role, '{' + field + '}', endpoint)
    check(status == 200 and not response.get('errors'), f'{role} can read {field}')
    return next(iter(response['data'].values()))

def view(role, case, audience, limit=100, offset=0, endpoint=API):
    return read(role, f'disclosureWorkspace(caseId:"{case}",audience:"{audience}",limit:{limit},offset:{offset})', endpoint)

def by_id(items):
    return {item['id']: item for item in items}

def main():
    counts_before = {case: read('operator', f'lineageRecords(caseId:"{case}",limit:1)')['total'] for case in ('advisor', 'ria')}
    client = view('advisor', 'advisor', 'client')
    check(client['available'] and client['contract_version'] == 'disclosure/v1', 'Advisor disclosure is available')
    check(view('advisor', 'advisor', 'client', endpoint=PREVIEW + '/api/graphql') == client, 'Preview proxy returns the same scoped view')
    sections = client['sections']
    bill = by_id(sections['billing'])
    for key, amount in [('disclosure-charge', 100000), ('disclosure-line_a', 60000), ('disclosure-line_b', 40000)]:
        check(int(bill[key]['amount_minor']) == amount, f'{key} preserves native billed amount')
    values = by_id(sections['valuation'])
    for key, amount in [('disclosure-reported', 125000000), ('disclosure-excluded', 25000000), ('disclosure-eligible', 100000000)]:
        check(int(values[key]['amount_minor']) == amount, f'{key} preserves household value')
    life = by_id(sections['lifecycle'])
    for key, amount in [('disclosure-credit', 50000), ('disclosure-refund', 30000), ('disclosure-refund-remaining', 20000)]:
        check(int(life[key]['amount_minor']) == amount, f'{key} has distinct evidenced amount')
    comp = by_id(sections['compensation'])
    for key, amount in [('disclosure-salary-entitlement',500000), ('disclosure-bonus-entitlement',100000), ('disclosure-loan-entitlement',1200000), ('disclosure-loan-cash',1200000), ('disclosure-forgiveness-entitlement',100000), ('disclosure-loan-outstanding',1100000)]:
        check(int(comp[key]['amount_minor']) == amount, f'{key} stays separately classified')
    check(comp['disclosure-equity']['amount_minor'] is None and '100' in str(comp['disclosure-equity']['quantity']), 'Equity is units without invented dollar value')
    costs = by_id(sections['costs'])
    check(int(costs['disclosure-known-direct']['amount_minor']) == 102500, 'Known direct charges total $1,025')
    duplicate = costs['disclosure-custodian-advisory-observation']
    check(int(duplicate['amount_minor']) == 100000 and duplicate['included_in_subtotal'] is False and duplicate['classification'] == 'observed_duplicate_of_assessed_charge', 'Repeated advisory observation is explicitly excluded')
    check(costs['disclosure-fund-cost']['amount_minor'] is None, 'Embedded fund cost stays unknown')
    check('record_id' not in json.dumps(client), 'Client view omits internal record IDs')
    product = view('operator', 'advisor', 'product')
    options = by_id(product['sections']['policy_options'])
    expected = {'average-daily-balance':110000, 'quarterly':300000, 'onboarding':50000, 'arrears':100000, 'net-worth':50000, 'fixed':20000, 'hourly':70000, 'optional-service':10000, 'monthly-minimum':125000}
    for name, amount in expected.items():
        row = options['disclosure-option-' + name]
        check(row['comparison_only'] is True and int(row['amount_minor']) == amount, f'{name} is the exact separate comparison')
    finance = view('finance', 'advisor', 'finance')
    recognition = by_id(finance['sections']['recognition'])
    check(int(recognition['disclosure-recognition-posted']['amount_minor']) == 50000, 'Recognition is supplied independently')
    check(recognition['disclosure-recognition-missing']['amount_minor'] is None, 'Missing accounting posting remains missing')
    ria = view('ria', 'ria', 'client')
    check(ria['available'] and len(ria['sections']['costs']) == 1 and not ria['sections']['billing'], 'RIA gets cost-only disclosure')
    check(int(ria['sections']['costs'][0]['amount_minor']) == 2500 and 'record_id' not in ria['sections']['costs'][0], 'RIA cost remains scoped and observed')
    for role, case, audience in [('ria','advisor','client'),('advisor','ria','client'),('advisor','advisor','product'),('advisor','advisor','finance')]:
        _, denied = request(role, f'{{disclosureWorkspace(caseId:"{case}",audience:"{audience}")}}')
        check(any(e.get('extensions', {}).get('code') == 'FORBIDDEN' for e in denied.get('errors', [])), f'{role} denied {case}/{audience}')
    total = product['page']['total']
    full = []
    for offset in range(0,total,100):
        page = view('operator','advisor','product',100,offset)
        full += [(section,item['id']) for section,items in page['sections'].items() for item in items]
    singles = []
    for offset in range(total):
        page = view('operator','advisor','product',1,offset)
        singles += [(section,item['id']) for section,items in page['sections'].items() for item in items]
    check(len(full) == total and full == singles and len(set(singles)) == total, 'First, last and intermediate global pages have no omissions or duplicates')
    matches = read('operator', 'lineageRecords(caseId:"advisor",search:"disclosure-adb-a-14",limit:10)')['items']
    check(len(matches) == 1, 'Ordinary daily source is discoverable')
    record = read('operator', f'lineageRecord(caseId:"advisor",recordId:"{matches[0]["id"]}",limit:100)')
    check(record['record']['external_id'] == 'disclosure-adb-a-14' and record['edge_total'] > 0, 'Daily observation opens linked lineage')
    check(any(edge['execution_status']=='recorded_execution' and edge['output'].get('external_id')=='disclosure-option-run-average-daily-balance' for edge in record['edges']), 'Daily fact opens its actual engine execution')
    check(any(edge['input'].get('external_id')=='disclosure-alternative-source' for edge in record['edges']), 'Daily fact retains original artifact linkage')
    for case, balance in [('advisor','230000'),('ria','13000')]:
        statement=read(case, f'audienceStatement(caseId:"{case}",limit:1)')
        check(statement['balance_minor'] == balance, f'{case} legacy statement balance unchanged')
    old_finance=read('finance', 'financeWorkspace(caseId:"ria")')
    check([old_finance['cash'][k] for k in ('amount_minor','associated_minor','unapplied_minor')] == ['90000','60000','30000'], 'Existing Finance cash amounts unchanged')
    status, _ = request('operator', '{disclosureWorkspace(caseId:"advisor",audience:"product")}', origin='https://foreign.invalid')
    check(status == 403, 'Foreign origin is rejected')
    counts_after = {case: read('operator', f'lineageRecords(caseId:"{case}",limit:1)')['total'] for case in ('advisor','ria')}
    check(counts_before == counts_after, 'All acceptance reads leave record counts unchanged')
    target=ROOT / 'artifacts/disclosure/disclosure-http.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({'status':'passed','mutation_requests':0,'checks':checks},indent=2)+'\n')
    print(f'{len(checks)} disclosure HTTP checks passed; no mutations sent.')

if __name__ == '__main__':
    main()
