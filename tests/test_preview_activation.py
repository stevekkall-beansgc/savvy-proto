"""Preview deployment guard/rollback; all services and credentials are synthetic mocks."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
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
        (root / 'apps/web/.next-presentation').mkdir(parents=True)
        (root / 'apps/web/.next-presentation/BUILD_ID').write_text('synthetic-build')
        self.sha = 'a' * 40
        (self.app.RUNTIME / 'presentation-build.json').write_text(json.dumps({'commit': self.sha, 'build_id': 'synthetic-build'}))
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
        return json.dumps({'check_runs': [{'name': 'check', 'status': 'completed', 'conclusion': 'success'}]})

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
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request', request), patch.object(self.app, 'restart', restart):
            with self.assertRaises(urllib.error.HTTPError): self.app.main(True)
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
        with patch.object(self.app, 'run', self.run_command), patch.object(self.app, 'request') as remote:
            with self.assertRaisesRegex(AssertionError, 'Unowned'): self.app.main(True)
            remote.assert_not_called()
        self.assertEqual(unowned, plistlib.loads(self.app.PLIST.read_bytes()))

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
