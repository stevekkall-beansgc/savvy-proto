#!/usr/bin/env python3
"""Open only the explicitly configured synthetic demo, retaining rollback evidence."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
POLICY_NAME = 'Savvy public synthetic demo'
HOST = 'savvy-proto.beanshop.top'


def origin_plan(cfg, config):
    assert cfg['hostname'] == HOST and cfg.get('access_mode') == 'public_demo', 'Explicit public demo configuration required'
    updated = copy.deepcopy(config)
    routes = [r for r in updated['ingress'] if r.get('hostname') == HOST]
    assert len(routes) == 1 and routes[0]['service'] == 'http://127.0.0.1:3104', 'Unexpected demo origin'
    assert updated['ingress'][-1] == {'service': 'http_status:404'}, 'Unexpected catchall'
    access = routes[0]['originRequest']['access']
    assert access['teamName'] == cfg['access_team'] and access['audTag'] == [cfg['access_aud']] and type(access['required']) is bool, 'Unowned origin authentication'
    access['required'] = False
    return updated


def plan(cfg, app, config, policies):
    updated = origin_plan(cfg, config)
    assert app['domain'] == HOST and app['id'] == cfg['access_app_id'] and app['aud'] == cfg['access_aud'], 'Unowned Access application'
    found = [p for p in policies if p.get('name') == POLICY_NAME]
    assert len(found) <= 1, 'Duplicate public policy'
    if found:
        assert found[0]['decision'] == 'bypass' and found[0]['include'] == [{'everyone': {}}] and not found[0].get('require') and not found[0].get('exclude'), 'Unexpected public policy'
    policy = {'name': POLICY_NAME, 'decision': 'bypass', 'include': [{'everyone': {}}], 'require': [], 'exclude': [], 'precedence': 1}
    return updated, found[0] if found else None, policy


def main(apply=False, origin_only=False):
    cfg = json.loads((ROOT/'deploy/device-host.json').read_text())
    spec = importlib.util.spec_from_file_location('savvy_tunnel', ROOT/'deploy/run-tunnel.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    account = helper.secret('shared__CLOUDFLARE_ACCOUNT_ID')
    token = helper.secret('shared__CLOUDFLARE_API_TOKEN')
    base = f'https://api.cloudflare.com/client/v4/accounts/{account}'

    def api(path, method='GET', body=None):
        req = urllib.request.Request(base+path, method=method, data=None if body is None else json.dumps(body).encode(), headers={'Authorization': 'Bearer '+token, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=30) as response: result = json.load(response)
        if not result.get('success'): raise RuntimeError('Cloudflare operation failed')
        return result.get('result')

    app_path = f'/access/apps/{cfg["access_app_id"]}'
    tunnel_path = f'/cfd_tunnel/{cfg["tunnel_id"]}/configurations'
    original = api(tunnel_path)['config']
    if origin_only:
        # For a credential scoped to Tunnel only, configure the app bypass in
        # the dashboard first. Anonymous HTTPS is still required before success.
        updated, existing, policy = origin_plan(cfg, original), None, None
    else:
        updated, existing, policy = plan(cfg, api(app_path), original, api(app_path+'/policies'))
    if not apply:
        print(json.dumps({'hostname': HOST, 'public_demo': True, 'apply': False})); return
    runtime = ROOT/'.runtime/hosting'; runtime.mkdir(parents=True, exist_ok=True)
    backup = runtime/'public-access-before.json'
    if not backup.exists():
        backup.write_text(json.dumps({'config': original, 'existing_public_policy': existing}, indent=2)+'\n'); backup.chmod(0o600)
    created = None
    changed = False
    try:
        if not existing and not origin_only: created = api(app_path+'/policies', 'POST', policy)['id']
        if original != updated:
            changed = True
            api(tunnel_path, 'PUT', {'config': updated})
        assert api(tunnel_path)['config'] == updated
        for attempt in range(20):
            try:
                req = urllib.request.Request('https://'+HOST+'/', headers={'User-Agent': 'Savvy-Prototype-Preview-Check/1.0'})
                with urllib.request.urlopen(req, timeout=15) as response:
                    assert response.status == 200 and response.url.rstrip('/') == 'https://'+HOST
                    assert b'__next' in response.read(), 'Expected application HTML'
                break
            except (OSError, AssertionError):
                if attempt == 19: raise
                time.sleep(1)
        receipt = {'hostname': HOST, 'public_demo': True, 'anonymous_verified': True, 'public_policy_id': created or (existing['id'] if existing else None), 'access_policy_managed': 'dashboard' if origin_only else 'api', 'other_routes_changed': False}
        (runtime/'public-access.json').write_text(json.dumps(receipt, indent=2)+'\n')
        print(json.dumps(receipt))
    except Exception:
        try:
            if changed: api(tunnel_path, 'PUT', {'config': original})
        finally:
            if created: api(app_path+'/policies/'+created, 'DELETE')
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--origin-only', action='store_true', help='Use an existing app bypass configured in the dashboard; requires anonymous HTTPS proof.')
    args = parser.parse_args()
    try: main(args.apply, args.origin_only)
    except Exception as error:
        print(f'Public demo update stopped ({type(error).__name__}); credentials and provider responses omitted.')
        raise SystemExit(1)
