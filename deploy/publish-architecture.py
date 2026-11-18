#!/usr/bin/env python3
"""Publish the static architecture document, with exact-commit CI and no backend."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
PROJECT = 'savvy-architecture'
HOST = 'savvy.beanshop.top'
REPO = 'stevekkall-beansgc/savvy-proto'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wrangler',type=Path,required=True,help='Existing installed Wrangler CLI JavaScript entrypoint.')
    args=parser.parse_args()
    if not args.wrangler.is_file():
        parser.error('Wrangler entrypoint not found.')
    sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    if subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip():
        raise RuntimeError('Commit publication changes before deployment.')
    remote=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/branches/main'],text=True))
    if remote['commit']['sha']!=sha:
        raise RuntimeError('Publication candidate must match remote main.')
    runs=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/commits/{sha}/check-runs'],text=True))['check_runs']
    if not any(r['name']=='architecture-compliance' and r['head_sha']==sha and r['conclusion']=='success' for r in runs):
        raise RuntimeError('Exact-commit architecture CI must pass before deployment.')
    subprocess.run(['python3',str(ROOT/'scripts/package_architecture.py')],cwd=ROOT,check=True)
    spec=importlib.util.spec_from_file_location('runtime_credentials',ROOT/'deploy/run-tunnel.py')
    credentials=importlib.util.module_from_spec(spec);spec.loader.exec_module(credentials)
    account=credentials.secret('shared__CLOUDFLARE_ACCOUNT_ID')
    token=credentials.secret('shared__CLOUDFLARE_API_TOKEN')
    zone=json.loads((ROOT/'deploy/device-host.json').read_text())['zone_id']

    def cf(method,endpoint,payload=None,missing_ok=False):
        body=json.dumps(payload).encode() if payload is not None else None
        request=urllib.request.Request('https://api.cloudflare.com/client/v4/'+endpoint,data=body,method=method,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=30) as response:data=json.load(response)
        except urllib.error.HTTPError as error:
            if error.code==404 and missing_ok:return None
            raise RuntimeError(f'Cloudflare {method} failed with HTTP {error.code}') from None
        if not data.get('success'):raise RuntimeError('Cloudflare request was not successful.')
        return data.get('result')

    base=f'accounts/{account}/pages/projects/{PROJECT}'
    project=cf('GET',base,missing_ok=True)
    if project is None:project=cf('POST',f'accounts/{account}/pages/projects',{'name':PROJECT,'production_branch':'main'})
    records=cf('GET',f'zones/{zone}/dns_records?name={HOST}')
    if records and any(r['type']!='CNAME' or r['content']!=project['subdomain'] for r in records):
        raise RuntimeError('Requested hostname already has an unrelated DNS record.')
    runtime=ROOT/'.runtime/publication';runtime.mkdir(parents=True,exist_ok=True)
    env={**os.environ,'CLOUDFLARE_ACCOUNT_ID':account,'CLOUDFLARE_API_TOKEN':token,'WRANGLER_SEND_METRICS':'false','WRANGLER_LOG_PATH':str(runtime/'wrangler.log')}
    subprocess.run(['node',str(args.wrangler),'pages','deploy',str(runtime/'site'),'--project-name',PROJECT,'--branch','main','--commit-hash',sha,'--commit-message','Publish source-linked Savvy architecture','--commit-dirty=false'],cwd=ROOT,env=env,check=True)
    domains=cf('GET',base+'/domains')
    if not any(d['name']==HOST for d in domains):cf('POST',base+'/domains',{'name':HOST})
    if not records:
        current=cf('GET',f'zones/{zone}/dns_records?name={HOST}')
        if not current:cf('POST',f'zones/{zone}/dns_records',{'type':'CNAME','name':HOST,'content':project['subdomain'],'ttl':1,'proxied':True})
    domain=cf('GET',base+'/domains/'+HOST)
    receipt={'hostname':HOST,'project':PROJECT,'subdomain':project['subdomain'],'commit':sha,'domain_status':domain.get('status'),'static_only':True,'authentication_required':False}
    (runtime/'deployment.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt))


if __name__=='__main__':
    main()
