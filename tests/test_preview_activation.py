"""Preview deployment guard/rollback; all services and credentials are synthetic mocks."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
from types import SimpleNamespace
from io import BytesIO
import unittest
from unittest.mock import patch
import urllib.error

SOURCE = Path(__file__).resolve().parents[1] / 'deploy/activate-preview.py'


class PreviewActivationTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('preview_activation', SOURCE)
        self.app = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.app)
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        root = Path(self.scratch.name)
        self.app.ROOT = root
        self.app.RUNTIME = root / '.runtime/hosting'
        self.app.RUNTIME.mkdir(parents=True)
        self.app.PLIST = root / 'preview.plist'
        (root / 'deploy').mkdir()
        (root / 'apps/web/.next-candidate-a').mkdir(parents=True)
        (root / 'apps/web/.next-candidate-a/BUILD_ID').write_text('synthetic-build')
        self.sha = 'a' * 40
        (self.app.RUNTIME / 'candidate-build.json').write_text(json.dumps({'commit': self.sha, 'build_id': 'synthetic-build', 'slot': 'candidate-a', 'asset_hash': 'hash', 'api_endpoint': 'http://127.0.0.1:3108', 'api_container': 'candidate', 'api_image_id': 'image', 'validation': ['presentation_ui_check', 'billing_platform_ui_check', 'billing_lifecycle_ui_check', 'product_http_check']}))
        self.control = SimpleNamespace(inactive=lambda slot: root / 'apps/web/.next-candidate-a', tree_hash=lambda path: 'hash', image_identity=lambda *args: 'image')
        stage = json.dumps({'api': 'http://127.0.0.1:3108', 'slot': 'candidate-a', 'health': {'source_revision': self.sha}}).encode()
        self.stage = lambda *args, **kwargs: BytesIO(stage)
        self.cfg = {'hostname': 'savvy-proto.beanshop.top', 'tunnel_id': 'synthetic-tunnel', 'access_team': 'synthetic-team', 'access_aud': 'synthetic-audience'}
        (root / 'deploy/device-host.json').write_text(json.dumps(self.cfg))
        (root / 'deploy/run-tunnel.py').write_text("def secret(name): return 'synthetic-test-value'\n")
        self.before = {'Label': self.app.LABEL, 'WorkingDirectory': str(root / 'apps/web'),
            'ProgramArguments': ['node', 'next', 'start', '--hostname', '127.0.0.1', '--port', '3104'],
            'EnvironmentVariables': {'SAVVY_BUILD_DIRECTORY': 'evidence-final'}}
        self.original_bytes = plistlib.dumps(self.before)
        self.app.PLIST.write_bytes(self.original_bytes)
        self.config = {'ingress': [{'hostname': self.cfg['hostname'], 'service': 'http://127.0.0.1:3100',
            'originRequest': {'access': {'required': True, 'teamName': self.cfg['access_team'], 'audTag': [self.cfg['access_aud']]}}},
            {'service': 'http_status:404'}], 'warp-routing': {'enabled': False}}

    def run_command(self, *args):
        if args[:2] == ('git', 'status'): return ''
        if args[:2] == ('git', 'rev-parse'): return self.sha
        if args[:2] == ('git', 'ls-remote'): return self.sha + '\trefs/heads/main'
        if args[:3] == ('gh', 'api', 'user'): return 'stevekkall-beansgc'
        return json.dumps({'check_runs': [{'name': name, 'status': 'completed', 'conclusion': 'success'} for name in ['check', 'architecture-compliance']]})

    def test_shared_billing_acceptance_is_required_before_any_switch(self):
        proof=self.app.RUNTIME / 'candidate-build.json'
        data=json.loads(proof.read_text())
        data['validation'].remove('billing_platform_ui_check')
        proof.write_text(json.dumps(data))
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request') as remote:
            with self.assertRaisesRegex(AssertionError, 'Candidate validation missing'):
                self.app.activate(True, self.control)
            remote.assert_not_called()
        self.assertEqual(self.original_bytes,self.app.PLIST.read_bytes())

    def test_both_latest_exact_commit_checks_must_succeed(self):
        for checks in [
            [{'name':'check','status':'completed','conclusion':'success'}],
            [{'name':'check','status':'completed','conclusion':'success'}, {'name':'architecture-compliance','status':'completed','conclusion':'failure'}],
            [{'name':'check','status':'completed','conclusion':'success'}, {'name':'architecture-compliance','status':'completed','conclusion':'success','started_at':'1'}, {'name':'architecture-compliance','status':'in_progress','conclusion':None,'started_at':'2'}],
        ]:
            def command(*args):
                if args[:2] == ('gh','api') and args[2].startswith('repos/'):
                    return json.dumps({'check_runs':checks})
                return self.run_command(*args)
            with self.subTest(checks=checks), patch.object(self.app, 'run', command), patch.object(self.app, 'request') as remote:
                with self.assertRaisesRegex(AssertionError, 'architecture-compliance'):
                    self.app.activate(True, self.control)
                remote.assert_not_called()

    def test_remote_failure_restores_local_service_even_when_remote_rollback_fails(self):
        requests = []
        restarts = []
        def request(url, body=None, headers=None, method=None):
            if method == 'PUT':
                requests.append(body['config'])
                error = urllib.error.HTTPError(url, 403, 'Synthetic denial', None, None)
                self.addCleanup(error.close)
                raise error
            return {'success': True, 'result': {'config': self.config}}
        def restart(verify_hosted=True):
            restarts.append((verify_hosted, plistlib.loads(self.app.PLIST.read_bytes())))
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request', request), patch.object(self.app, 'restart', restart), patch.object(self.app.urllib.request, 'urlopen', self.stage):
            with self.assertRaises(urllib.error.HTTPError): self.app.activate(True, self.control)
        self.assertEqual(self.original_bytes, self.app.PLIST.read_bytes())
        self.assertEqual([True, False], [verify for verify, _ in restarts])
        self.assertEqual(self.before, restarts[-1][1])
        self.assertEqual('http://127.0.0.1:3104', requests[0]['ingress'][0]['service'])
        self.assertEqual(self.config, requests[1])
        self.assertEqual(self.config['ingress'][0]['originRequest'], requests[0]['ingress'][0]['originRequest'])
        self.assertFalse((self.app.RUNTIME / 'activation.json').exists())

    def test_unowned_service_stops_before_external_access(self):
        unowned = {**self.before, 'WorkingDirectory': '/another-project'}
        self.app.PLIST.write_bytes(plistlib.dumps(unowned))
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request') as remote, patch.object(self.app.urllib.request, 'urlopen', self.stage):
            with self.assertRaisesRegex(AssertionError, 'Unowned'): self.app.activate(True, self.control)
            remote.assert_not_called()
        self.assertEqual(unowned, plistlib.loads(self.app.PLIST.read_bytes()))

    def test_existing_route_skips_write_and_failure_restores_receipt(self):
        self.config['ingress'][0]['service'] = self.app.ORIGIN
        receipt = self.app.RUNTIME / 'activation.json'
        receipt.write_text('previous receipt')
        calls = []
        def request(url, body=None, headers=None, method=None):
            calls.append(method)
            return {'success': True, 'result': {'config': self.config}}
        def fail_after_restart(*args, **kwargs):
            raise RuntimeError('injected after service switch')
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request', request), patch.object(self.app, 'restart', side_effect=fail_after_restart), patch.object(self.app.urllib.request, 'urlopen', self.stage):
            with self.assertRaises(RuntimeError): self.app.activate(True, self.control)
        self.assertNotIn('PUT', calls)
        self.assertEqual('previous receipt', receipt.read_text())
        self.assertEqual(self.original_bytes, self.app.PLIST.read_bytes())

    def test_service_bootstrap_retries_transient_unload_error(self):
        ok = subprocess.CompletedProcess([], 0)
        transient = subprocess.CalledProcessError(5, ['launchctl', 'bootstrap'])
        with patch.object(self.app.subprocess, 'run', side_effect=[ok, ok, transient, ok]) as run, patch.object(self.app, 'probe') as probe, patch.object(self.app.time, 'sleep') as sleep:
            self.app.restart()
        self.assertEqual(4, run.call_count)
        sleep.assert_called_once_with(1)
        probe.assert_called_once()

    def test_service_bootstrap_does_not_retry_other_errors(self):
        ok = subprocess.CompletedProcess([], 0)
        fatal = subprocess.CalledProcessError(1, ['launchctl', 'bootstrap'])
        with patch.object(self.app.subprocess, 'run', side_effect=[ok, ok, fatal]), patch.object(self.app.time, 'sleep') as sleep:
            with self.assertRaises(subprocess.CalledProcessError): self.app.restart()
        sleep.assert_not_called()

    def test_public_mode_requires_matching_origin_access_before_switch(self):
        self.cfg['access_mode'] = 'public_demo'
        (self.app.ROOT/'deploy/device-host.json').write_text(json.dumps(self.cfg))
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request', return_value={'success':True,'result':{'config':self.config}}), patch.object(self.app, 'restart') as restart, patch.object(self.app.urllib.request, 'urlopen', self.stage):
            with self.assertRaisesRegex(AssertionError, 'declared mode'): self.app.activate(True, self.control)
            restart.assert_not_called()
        self.assertEqual(self.original_bytes, self.app.PLIST.read_bytes())

    def test_public_activation_verifies_anonymous_html_and_records_mode(self):
        self.cfg['access_mode'] = 'public_demo'
        (self.app.ROOT/'deploy/device-host.json').write_text(json.dumps(self.cfg))
        self.config['ingress'][0]['service'] = self.app.ORIGIN
        self.config['ingress'][0]['originRequest']['access']['required'] = False
        for public_url in [self.app.HOST+'/', 'https://synthetic-team.cloudflareaccess.com/login']:
            def fetch(req, **kwargs):
                if isinstance(req, str): return self.stage()
                response = BytesIO(b'synthetic application')
                response.status = 200
                response.url = public_url
                return response
            with self.subTest(url=public_url), patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request', return_value={'success':True,'result':{'config':self.config}}), patch.object(self.app, 'restart'), patch.object(self.app.urllib.request, 'urlopen', fetch):
                if public_url.startswith(self.app.HOST):
                    self.app.activate(True, self.control)
                    receipt = json.loads((self.app.RUNTIME/'activation.json').read_text())
                    self.assertEqual('public_demo',receipt['access_mode'])
                    self.assertFalse(receipt['access_preserved'])
                else:
                    with self.assertRaisesRegex(AssertionError, 'without login'): self.app.activate(True, self.control)
