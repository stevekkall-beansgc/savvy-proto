#!/usr/bin/env python3
"""Verify the revised UI's transport and PDF assets without mutations."""
import hashlib
import json
import urllib.error
from pathlib import Path
import urllib.request

ORIGIN='http://127.0.0.1:3104'
checks=[]

def check(value,label):
    if not value: raise AssertionError(label)
    checks.append(label)

for case in ['advisor','ria']:
    query='{audienceStatement(caseId:"'+case+'",limit:100)}'
    req=urllib.request.Request(ORIGIN+'/api/graphql',data=json.dumps({'query':query}).encode(),headers={'Content-Type':'application/json','Origin':ORIGIN,'X-Demo-Role':case})
    with urllib.request.urlopen(req,timeout=30) as response: result=json.load(response)
    check(not result.get('errors'),case+' reads through the new preview proxy')
    statement=result['data']['audienceStatement']
    check(statement['total']==len(statement['lines']),case+' retains all small-book statement lines')
    for line in statement['lines']:
        item=line['invoice_line']
        check(item['amount_minor']==line['minor'],case+' preserves exact signed amount')
        check(item['service_period_start']=='2026-09-01' and item['service_period_end_exclusive']=='2026-10-01',case+' has explicit service interval')
        check(item['quantity'] is None and item['unit_amount_minor'] is None,case+' does not invent quantity or price')

root=Path(__file__).resolve().parent.parent
manifest=json.loads((root/'apps/web/public/disclosures/manifest.json').read_text())
for document in manifest:
    slug=document['slug']
    with urllib.request.urlopen(ORIGIN+'/disclosures/'+slug+'.pdf',timeout=30) as response:
        content=response.read()
        check(response.headers.get_content_type()=='application/pdf',slug+' is a PDF')
        check(content.startswith(b'%PDF-'),slug+' has a PDF signature')
        check(hashlib.sha256(content).hexdigest()==document['sha256'],slug+' matches the unmodified source snapshot')
    for page in range(1,document['pages']+1):
        with urllib.request.urlopen(ORIGIN+f'/disclosures/{slug}-{page:02}.png',timeout=30) as response:
            check(response.headers.get_content_type()=='image/png' and response.read().startswith(b'\x89PNG'),f'{slug} page {page} preview is available')
for slug in ['advisor-fixture-document-v1','ria-fixture-document-v1']:
    for suffix in ['pdf','png']:
        try:
            urllib.request.urlopen(ORIGIN+f'/agreements/{slug}.{suffix}',timeout=30)
            raise AssertionError('Generated sample agreement is still served')
        except urllib.error.HTTPError as error:
            check(error.code==404,slug+' generated '+suffix+' removed')

req=urllib.request.Request(ORIGIN+'/api/graphql',data=b'{"query":"{audienceSummary(caseId:\"advisor\")}"}',headers={'Content-Type':'application/json','Origin':'https://invalid.example'})
try:
    urllib.request.urlopen(req,timeout=30)
    raise AssertionError('Foreign origin was accepted')
except urllib.error.HTTPError as error:
    check(error.code==403,'Foreign proxy origin remains forbidden')

target=Path(__file__).resolve().parent.parent/'artifacts/medallion/clarity-http.json'
target.write_text(json.dumps({'status':'passed','mutation_requests':0,'checks':checks},indent=2)+'\n')
print(f'{len(checks)} clarity HTTP checks passed; no mutations sent.')
