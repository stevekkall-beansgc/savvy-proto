#!/usr/bin/env python3
"""Guard inactive preview builds and bind staged validation to their artifacts."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / 'apps/web'
RUNTIME = ROOT / '.runtime/hosting'
SLOTS = {'candidate-a': '.next-candidate-a', 'candidate-b': '.next-candidate-b'}
API_ENDPOINTS = {'http://127.0.0.1:3108', 'http://127.0.0.1:3109'}
LABELS = ('com.beanlabs.savvy-clarity.preview', 'com.beanlabs.savvy-medallion.preview')

@contextlib.contextmanager
def locked():
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with (RUNTIME / 'preview.lock').open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield

def slot_path(slot):
    if slot not in SLOTS:
        raise ValueError('Explicit candidate-a or candidate-b slot required')
    path = WEB / SLOTS[slot]
    if WEB.is_symlink() or path.is_symlink() or path.resolve().parent != WEB.resolve():
        raise ValueError('Build slot must be a direct non-symlink directory')
    if path.exists() and any(p.is_symlink() for p in path.rglob('*')):
        raise ValueError('Build slot contains symlinks')
    return path

def inactive(slot):
    path = slot_path(slot)
    for label in LABELS:
        plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
        if not plist.is_file():
            raise ValueError('Cannot establish active preview slots')
        spec = plistlib.loads(plist.read_bytes())
        active = spec.get('EnvironmentVariables', {}).get('SAVVY_BUILD_DIRECTORY', '')
        expected_port = '3104' if label == LABELS[0] else '3103'
        if spec.get('Label') != label or spec.get('WorkingDirectory') != str(WEB) or spec.get('ProgramArguments', [])[-4:] != ['--hostname', '127.0.0.1', '--port', expected_port]:
            raise ValueError('Unowned preview service')
        # The legacy service without an explicit slot uses .next.
        if not active and label != LABELS[1]:
            raise ValueError('Unknown active slot')
        if active == slot:
            raise ValueError('Candidate slot is active')
        if active and active not in (*SLOTS, 'presentation', 'clarity', 'disclosures', 'evidence', 'evidence-final'):
            raise ValueError('Unknown active slot')
    return path

def tree_hash(path):
    digest = hashlib.sha256()
    for file in sorted(path.rglob('*')):
        if file.relative_to(path).parts[0] == 'cache': continue
        if file.is_symlink(): raise ValueError('Symlink in build output')
        if file.is_file():
            digest.update(file.relative_to(path).as_posix().encode() + b'\0')
            digest.update(hashlib.sha256(file.read_bytes()).digest())
    return digest.hexdigest()

def command(*args, **kw):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kw).strip()

def clean_sha():
    if command('git', 'status', '--porcelain'): raise ValueError('Commit changes before building')
    return command('git', 'rev-parse', 'HEAD')

def build(slot):
    with locked():
        inactive(slot)
        sha = clean_sha()
        env = dict(os.environ, SAVVY_BUILD_DIRECTORY=slot)
        next_env = WEB / 'next-env.d.ts'
        original_env = next_env.read_bytes()
        try:
            subprocess.run(['npm', '--prefix', 'apps/web', 'run', 'build'], cwd=ROOT, env=env, check=True)
        finally:
            generated_env = next_env.read_bytes()
            expected_env = original_env.replace(b'./.next/', ('./' + SLOTS[slot] + '/').encode())
            if generated_env == expected_env:
                next_env.write_bytes(original_env)
            elif generated_env != original_env:
                raise ValueError('Unexpected next-env change; inspect manually')
        if clean_sha() != sha: raise ValueError('Source changed during build')
        proof = {'commit': sha, 'slot': slot, 'build_id': (slot_path(slot)/'BUILD_ID').read_text().strip(), 'asset_hash': tree_hash(slot_path(slot))}
        (RUNTIME/'candidate-build-source.json').write_text(json.dumps(proof) + '\n')
        print(json.dumps(proof))

def image_identity(container, endpoint, sha):
    if endpoint not in API_ENDPOINTS: raise ValueError('Invalid candidate API endpoint')
    details = json.loads(command('docker', 'inspect', container))[0]
    if not details['State']['Running'] or details['Mounts'] or not details['HostConfig']['ReadonlyRootfs']:
        raise ValueError('Candidate API must be running read-only without mounts')
    binding = details['NetworkSettings']['Ports'].get('3101/tcp') or []
    if binding != [{'HostIp': '127.0.0.1', 'HostPort': endpoint.rsplit(':', 1)[1]}]:
        raise ValueError('Candidate API is not bound to the requested loopback port')
    image = details['Image']
    label = command('docker', 'image', 'inspect', image, '--format', '{{ index .Config.Labels "org.opencontainers.image.revision" }}')
    if label != sha: raise ValueError('Candidate image revision mismatch')
    with urllib.request.urlopen(endpoint + '/health', timeout=10) as response:
        health = json.load(response)
    if health.get('source_revision') != sha or health.get('immutable_preview') is not True or health.get('eager_load') is not True or health.get('reloading_enabled') is not False:
        raise ValueError('Candidate API revision or immutable configuration mismatch')
    return image

def record(slot, endpoint, container):
    with locked():
        path = inactive(slot)
        sha = clean_sha()
        image = image_identity(container, endpoint, sha)
        built = json.loads((RUNTIME/'candidate-build-source.json').read_text())
        expected = {'commit': sha, 'slot': slot, 'build_id': (path/'BUILD_ID').read_text().strip(), 'asset_hash': tree_hash(path)}
        if built != expected: raise ValueError('Build source proof mismatch')
        with urllib.request.urlopen('http://127.0.0.1:3106/api/preview-health', timeout=10) as response:
            stage = json.load(response)
        if stage.get('api') != endpoint or stage.get('slot') != slot or stage.get('health', {}).get('source_revision') != sha:
            raise ValueError('Staged frontend/API pair mismatch')
        env = dict(os.environ, SAVVY_PREVIEW_ORIGIN='http://127.0.0.1:3106', SAVVY_API_ORIGIN=endpoint)
        subprocess.run(['node', 'scripts/presentation_ui_check.cjs'], cwd=ROOT, env=env, check=True)
        subprocess.run(['node', 'scripts/billing_platform_ui_check.cjs'], cwd=ROOT, env=env, check=True)
        subprocess.run(['python3', 'scripts/product_http_check.py'], cwd=ROOT, env=env, check=True)
        if clean_sha() != sha: raise ValueError('Source changed during validation')
        if (path/'BUILD_ID').read_text().strip() != built['build_id'] or tree_hash(path) != built['asset_hash']:
            raise ValueError('Build assets changed during validation')
        if image_identity(container, endpoint, sha) != image:
            raise ValueError('Candidate API changed during validation')
        proof = {'commit': sha, 'slot': slot, 'build_id': built['build_id'],
                 'asset_hash': built['asset_hash'], 'api_image_id': image, 'api_endpoint': endpoint,
                 'api_container': container, 'frontend_endpoint': 'http://127.0.0.1:3106',
                 'validation': ['presentation_ui_check', 'billing_platform_ui_check', 'product_http_check']}
        (RUNTIME/'candidate-build.json').write_text(json.dumps(proof, indent=2) + '\n')
        print(json.dumps(proof))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('slot', choices=sorted(SLOTS))
    parser.add_argument('--record', action='store_true')
    parser.add_argument('--api')
    parser.add_argument('--container')
    args = parser.parse_args()
    if args.record:
        if not args.api or not args.container: parser.error('--record requires --api and --container')
        record(args.slot, args.api, args.container)
    else:
        build(args.slot)

if __name__ == '__main__': main()
