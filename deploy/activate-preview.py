#!/usr/bin/env python3
"""Switch the owned preview and its existing Access-protected route; never touch data."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / '.runtime/hosting'
LABEL = 'com.beanlabs.savvy-clarity.preview'
PLIST = Path.home() / f'Library/LaunchAgents/{LABEL}.plist'
HOST = 'https://savvy-proto.beanshop.top'
ORIGIN = 'http://127.0.0.1:3104'


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def request(url, body=None, headers=None, method=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def probe():
    with urllib.request.urlopen(ORIGIN, timeout=10) as response:
        assert response.status == 200
    body = {'query': '{disclosureWorkspace(caseId:"advisor",audience:"client")}'}
    data = request(ORIGIN + '/api/graphql', body, {
        'Content-Type': 'application/json', 'Origin': HOST, 'X-Demo-Role': 'advisor'})
    assert not data.get('errors')
    billing = data['data']['disclosureWorkspace']['sections']['billing']
    charge = next(x for x in billing if x['id'] == 'disclosure-charge')
    assert charge['amount_minor'] == '100000'
    try:
        request(ORIGIN + '/api/graphql', body, {
            'Content-Type': 'application/json', 'Origin': 'https://unrelated.example'})
    except urllib.error.HTTPError as error:
        assert error.code == 403
    else:
        raise RuntimeError('Foreign origin was accepted')


def restart(verify_hosted=True):
    target = f'gui/{os.getuid()}/{LABEL}'
    loaded = subprocess.run(['launchctl', 'print', target], capture_output=True)
    if loaded.returncode == 0:
        subprocess.run(['launchctl', 'bootout', target], check=True, capture_output=True)
    # launchd can acknowledge bootout before it releases the service label.
    for attempt in range(10):
        try:
            subprocess.run(['launchctl', 'bootstrap', f'gui/{os.getuid()}', str(PLIST)], check=True, capture_output=True)
            break
        except subprocess.CalledProcessError as error:
            if error.returncode != 5 or attempt == 9:
                raise
            time.sleep(1)
    for _ in range(20):
        try:
            if verify_hosted:
                probe()
            else:
                with urllib.request.urlopen(ORIGIN, timeout=10) as response:
                    assert response.status == 200
            return
        except (OSError, AssertionError, ValueError, KeyError, StopIteration):
            time.sleep(1)
    raise RuntimeError('Preview did not pass readiness checks')


def main(apply):
    spec = importlib.util.spec_from_file_location('preview_control', ROOT / 'deploy/preview-control.py')
    control = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(control)
    with control.locked():
        return activate(apply, control)


def activate(apply, control):
    assert not run('git', 'status', '--porcelain'), 'Commit reviewed changes first'
    sha = run('git', 'rev-parse', 'HEAD')
    assert run('gh', 'api', 'user', '--jq', '.login') == 'stevekkall-beansgc'
    remote = run('git', 'ls-remote', 'origin', 'refs/heads/main').split()[0]
    assert remote == sha, 'Remote main differs from this candidate'
    checks = json.loads(run('gh', 'api', f'repos/stevekkall-beansgc/savvy-proto/commits/{sha}/check-runs'))['check_runs']
    for required in ('check', 'architecture-compliance'):
        matching = [c for c in checks if c['name'] == required]
        latest = max(matching, key=lambda c: c.get('started_at') or '') if matching else None
        assert latest and latest['conclusion'] == 'success' and latest['status'] == 'completed', f'Exact-commit {required} CI is required'
    build_proof = json.loads((RUNTIME / 'candidate-build.json').read_text())
    slot = build_proof['slot']
    path = control.inactive(slot)
    assert build_proof['commit'] == sha, 'Build commit mismatch'
    assert build_proof['build_id'] == (path / 'BUILD_ID').read_text().strip(), 'Build identity changed'
    assert build_proof['asset_hash'] == control.tree_hash(path), 'Build assets changed'
    assert build_proof['validation'] == ['presentation_ui_check', 'billing_platform_ui_check', 'billing_lifecycle_ui_check', 'product_http_check'], 'Candidate validation missing'
    endpoint = build_proof['api_endpoint']
    assert control.image_identity(build_proof['api_container'], endpoint, sha) == build_proof['api_image_id'], 'API image changed'
    with urllib.request.urlopen('http://127.0.0.1:3106/api/preview-health', timeout=10) as response:
        stage = json.load(response)
    assert stage.get('api') == endpoint and stage.get('slot') == slot and stage.get('health', {}).get('source_revision') == sha, 'Staged pair changed'
    previous_bytes = PLIST.read_bytes()
    previous = plistlib.loads(previous_bytes)
    assert previous['Label'] == LABEL
    assert previous['WorkingDirectory'] == str(ROOT / 'apps/web'), 'Unowned preview service'
    args = previous['ProgramArguments']
    assert args[-4:] == ['--hostname', '127.0.0.1', '--port', '3104']
    next_plist = copy.deepcopy(previous)
    env = next_plist['EnvironmentVariables']
    env.update(SAVVY_API_URL=endpoint, SAVVY_BUILD_DIRECTORY=slot, SAVVY_PUBLIC_ORIGIN=HOST)
    spec = importlib.util.spec_from_file_location('savvy_tunnel', ROOT / 'deploy/run-tunnel.py')
    tunnel = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tunnel)
    account = tunnel.secret('shared__CLOUDFLARE_ACCOUNT_ID')
    token = tunnel.secret('shared__CLOUDFLARE_API_TOKEN')
    cfg = json.loads((ROOT / 'deploy/device-host.json').read_text())
    tunnel_endpoint = f'https://api.cloudflare.com/client/v4/accounts/{account}/cfd_tunnel/{cfg["tunnel_id"]}/configurations'
    auth = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    before = request(tunnel_endpoint, headers=auth)
    assert before['success']
    original = before['result']['config']
    updated = copy.deepcopy(original)
    routes = [r for r in updated['ingress'] if r.get('hostname') == cfg['hostname']]
    assert len(routes) == 1
    route = routes[0]
    assert route['service'] in ['http://127.0.0.1:3100', ORIGIN]
    access = route['originRequest']['access']
    assert access['required'] is True and access['teamName'] == cfg['access_team'] and access['audTag'] == [cfg['access_aud']]
    route['service'] = ORIGIN
    print(json.dumps({'commit': sha, 'origin': ORIGIN, 'access_preserved': True, 'apply': apply}))
    if not apply:
        return
    RUNTIME.mkdir(parents=True, exist_ok=True)
    (RUNTIME / 'preview-before.plist').write_bytes(previous_bytes)
    (RUNTIME / 'tunnel-before-activation.json').write_text(json.dumps(original, indent=2))
    receipt_path = RUNTIME / 'activation.json'
    previous_receipt = receipt_path.read_bytes() if receipt_path.exists() else None
    tunnel_attempted = False
    assert build_proof['build_id'] == (path / 'BUILD_ID').read_text().strip() and build_proof['asset_hash'] == control.tree_hash(path), 'Build assets changed before activation'
    assert control.image_identity(build_proof['api_container'], endpoint, sha) == build_proof['api_image_id'], 'API image changed before activation'
    try:
        PLIST.write_bytes(plistlib.dumps(next_plist))
        PLIST.chmod(0o600)
        restart()
        with urllib.request.urlopen(ORIGIN + '/api/preview-health', timeout=10) as response:
            live = json.load(response)
        assert live.get('api') == endpoint and live.get('slot') == slot and live.get('health', {}).get('source_revision') == sha, 'Promoted pair mismatch'
        assert build_proof['build_id'] == (path / 'BUILD_ID').read_text().strip() and build_proof['asset_hash'] == control.tree_hash(path), 'Build assets changed during activation'
        assert control.image_identity(build_proof['api_container'], endpoint, sha) == build_proof['api_image_id'], 'API image changed during activation'
        if updated != original:
            tunnel_attempted = True
            outcome = request(tunnel_endpoint, {'config': updated}, auth, 'PUT')
            assert outcome['success']
            after = request(tunnel_endpoint, headers=auth)
            assert after['success'] and after['result']['config'] == updated
        # Identify our own health checker; the zone rejects Python's generic UA.
        public_probe = urllib.request.Request(HOST, headers={'User-Agent': 'Savvy-Prototype-Preview-Check/1.0'})
        with urllib.request.urlopen(public_probe, timeout=30) as response:
            assert response.url.startswith('https://' + cfg['access_team'] + '.cloudflareaccess.com/'), 'Access must still protect the app'
        receipt = {**build_proof, 'commit': sha, 'host': HOST, 'origin': ORIGIN, 'access_preserved': True,
                   'data_mutations': 0, 'old_origin': next(r['service'] for r in original['ingress'] if r.get('hostname') == cfg['hostname'])}
        (RUNTIME / 'activation.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print('Preview activated; hosted route verified; Access retained.')
    except Exception:
        try:
            if tunnel_attempted:
                restored = request(tunnel_endpoint, {'config': original}, auth, 'PUT')
                assert restored['success'], 'Tunnel rollback failed'
        finally:
            # Local rollback must still run if the remote API is unavailable.
            PLIST.write_bytes(previous_bytes)
            if previous_receipt is None:
                receipt_path.unlink(missing_ok=True)
            else:
                receipt_path.write_bytes(previous_receipt)
            restart(verify_hosted=False)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    try:
        main(parser.parse_args().apply)
    except Exception as error:
        # Do not print Cloudflare/credential response bodies.
        print(f'Preview activation stopped: {type(error).__name__}: {str(error) if isinstance(error, AssertionError) else "see local preflight checks"}')
        raise SystemExit(1)
