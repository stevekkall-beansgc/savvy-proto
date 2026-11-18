"""Public exposure stays confined to the explicitly authorized synthetic hostname."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('public_demo', Path(__file__).resolve().parents[1]/'deploy/public-demo.py')
app = importlib.util.module_from_spec(spec); spec.loader.exec_module(app)


class PublicDemoTest(unittest.TestCase):
    def setUp(self):
        self.cfg = dict(hostname=app.HOST, access_mode='public_demo', access_app_id='app', access_aud='aud', access_team='team')
        self.application = dict(domain=app.HOST, id='app', aud='aud')
        self.config = {'ingress': [{'hostname': app.HOST, 'service': 'http://127.0.0.1:3104', 'originRequest': {'access': dict(required=True, teamName='team', audTag=['aud'])}}, {'hostname': 'other.example', 'service': 'http://other'}, {'service':'http_status:404'}]}

    def test_only_authorized_host_changes_and_original_is_preserved(self):
        before = copy.deepcopy(self.config)
        updated, existing, policy = app.plan(self.cfg, self.application, self.config, [])
        self.assertEqual(before, self.config)
        self.assertEqual(before['ingress'][1:], updated['ingress'][1:])
        self.assertFalse(updated['ingress'][0]['originRequest']['access']['required'])
        self.assertIsNone(existing)
        self.assertEqual([{'everyone': {}}], policy['include'])
        self.assertEqual('bypass', policy['decision'])

    def test_missing_authorization_wrong_origin_or_wrong_application_is_rejected(self):
        for kind in ['mode', 'host', 'origin', 'audience', 'catchall']:
            cfg, application, config = copy.deepcopy((self.cfg,self.application,self.config))
            if kind == 'mode': cfg.pop('access_mode')
            if kind == 'host': application['domain'] = 'other.example'
            if kind == 'origin': config['ingress'][0]['service'] = 'http://127.0.0.1:3100'
            if kind == 'audience': application['aud'] = 'other'
            if kind == 'catchall': config['ingress'][-1] = {'service':'http://other'}
            with self.subTest(kind=kind), self.assertRaises(AssertionError): app.plan(cfg,application,config,[])

    def test_existing_policy_is_idempotent_but_different_permissions_are_rejected(self):
        _, _, policy = app.plan(self.cfg,self.application,self.config,[])
        policy['id'] = 'existing'
        self.assertEqual('existing', app.plan(self.cfg,self.application,self.config,[policy])[1]['id'])
        policy['decision'] = 'allow'
        with self.assertRaises(AssertionError): app.plan(self.cfg,self.application,self.config,[policy])
