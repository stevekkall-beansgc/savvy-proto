"""Offline negative and contention checks for preview slot controls."""
import importlib.util
import json
from io import BytesIO
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('preview_control', Path(__file__).resolve().parents[1] / 'deploy/preview-control.py')
control = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control)

class PreviewControlTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.web = self.root / 'apps/web'
        self.web.mkdir(parents=True)
        self.agents = self.root / 'Library/LaunchAgents'
        self.agents.mkdir(parents=True)
        for label, active, port in zip(control.LABELS, ['presentation', ''], ['3104', '3103']):
            (self.agents / (label + '.plist')).write_bytes(plistlib.dumps({'Label': label, 'WorkingDirectory': str(self.web), 'ProgramArguments': ['--hostname', '127.0.0.1', '--port', port], 'EnvironmentVariables': {'SAVVY_BUILD_DIRECTORY': active}}))
        self.patches = [patch.object(control, 'WEB', self.web), patch.object(control, 'RUNTIME', self.root / 'runtime'), patch.object(Path, 'home', return_value=self.root)]
        for p in self.patches: p.start(); self.addCleanup(p.stop)

    def test_unknown_traversal_and_symlinks_are_rejected(self):
        for value in ['', '../candidate-a', 'presentation', 'candidate-a/../candidate-b']:
            with self.subTest(value=value), self.assertRaises(ValueError): control.slot_path(value)
        (self.web / '.next-candidate-a').symlink_to(self.root)
        with self.assertRaises(ValueError): control.slot_path('candidate-a')

    def test_secondary_active_slot_and_unknown_configuration_are_rejected(self):
        plist = self.agents / (control.LABELS[1] + '.plist')
        for active in ['candidate-a', '../unknown']:
            spec = plistlib.loads(plist.read_bytes())
            spec['EnvironmentVariables']['SAVVY_BUILD_DIRECTORY'] = active
            plist.write_bytes(plistlib.dumps(spec))
            with self.assertRaises(ValueError): control.inactive('candidate-a')

    def test_concurrent_build_or_activation_is_rejected(self):
        with control.locked():
            for _ in range(100):
                with self.assertRaises(BlockingIOError):
                    with control.locked(): pass

    def test_build_restores_only_expected_next_environment_change(self):
        env_file = self.web / 'next-env.d.ts'
        original = b'import "./.next/types/routes.d.ts";\n'
        env_file.write_bytes(original)
        path = self.web / '.next-candidate-a'
        path.mkdir()
        (path / 'BUILD_ID').write_text('candidate')
        def next_build(*args, **kwargs):
            env_file.write_bytes(original.replace(b'./.next/', b'./.next-candidate-a/'))
        with patch.object(control, 'clean_sha', return_value='a' * 40), patch.object(control.subprocess, 'run', side_effect=next_build):
            control.build('candidate-a')
        self.assertEqual(original, env_file.read_bytes())
        def unexpected(*args, **kwargs):
            env_file.write_bytes(b'arbitrary source edit')
        with patch.object(control, 'clean_sha', return_value='a' * 40), patch.object(control.subprocess, 'run', side_effect=unexpected):
            with self.assertRaisesRegex(ValueError, 'Unexpected next-env'):
                control.build('candidate-a')
        self.assertEqual(b'arbitrary source edit', env_file.read_bytes())

    def test_build_rejects_unrelated_dirty_source_after_build(self):
        env_file = self.web / 'next-env.d.ts'
        original = b'import "./.next/types/routes.d.ts";\n'
        env_file.write_bytes(original)
        def clean_then_dirty(*args):
            if args[:2] == ('git', 'status'):
                clean_then_dirty.calls += 1
                return '' if clean_then_dirty.calls == 1 else ' M apps/api/app.rb'
            return 'a' * 40
        clean_then_dirty.calls = 0
        with patch.object(control, 'command', side_effect=clean_then_dirty), patch.object(control.subprocess, 'run'):
            with self.assertRaisesRegex(ValueError, 'Commit changes'):
                control.build('candidate-a')
        self.assertFalse((control.RUNTIME / 'candidate-build-source.json').exists())

    def test_record_rejects_changed_assets_and_image_after_validation(self):
        path = self.web / '.next-candidate-a'
        path.mkdir()
        (path/'BUILD_ID').write_text('candidate')
        asset = path/'asset'
        asset.write_text('reviewed')
        sha = 'a' * 40
        control.RUNTIME.mkdir(parents=True)
        built = {'commit': sha, 'slot': 'candidate-a', 'build_id': 'candidate', 'asset_hash': control.tree_hash(path)}
        (control.RUNTIME/'candidate-build-source.json').write_text(json.dumps(built))
        stage = {'api': 'http://127.0.0.1:3108', 'slot': 'candidate-a', 'health': {'source_revision': sha}}
        def stage_response(*args, **kwargs): return BytesIO(json.dumps(stage).encode())
        def change_asset(*args, **kwargs): asset.write_text('modified during checks')
        with patch.object(control, 'clean_sha', return_value=sha), patch.object(control, 'image_identity', return_value='image'), patch.object(control.urllib.request, 'urlopen', stage_response), patch.object(control.subprocess, 'run', side_effect=change_asset):
            with self.assertRaisesRegex(ValueError, 'assets changed during validation'):
                control.record('candidate-a', stage['api'], 'candidate')
        self.assertFalse((control.RUNTIME/'candidate-build.json').exists())
        asset.write_text('reviewed')
        with patch.object(control, 'clean_sha', return_value=sha), patch.object(control, 'image_identity', side_effect=['image', 'changed-image']), patch.object(control.urllib.request, 'urlopen', stage_response), patch.object(control.subprocess, 'run'):
            with self.assertRaisesRegex(ValueError, 'API changed during validation'):
                control.record('candidate-a', stage['api'], 'candidate')
        self.assertFalse((control.RUNTIME/'candidate-build.json').exists())

    def test_served_route_cache_is_hashed(self):
        path = self.web / '.next-candidate-a'
        route = path / 'server/route-cache/APP_PAGE'
        route.mkdir(parents=True)
        (route/'index.html').write_text('original')
        before = control.tree_hash(path)
        (route/'index.html').write_text('changed')
        self.assertNotEqual(before, control.tree_hash(path))
        (route/'index.rsc').write_text('new served data')
        self.assertNotEqual(before, control.tree_hash(path))

    def test_hash_tracks_asset_changes(self):
        path = self.web / '.next-candidate-a'
        path.mkdir()
        (path/'asset').write_text('first')
        before = control.tree_hash(path)
        (path/'asset').write_text('second')
        self.assertNotEqual(before, control.tree_hash(path))

if __name__ == '__main__': unittest.main()
