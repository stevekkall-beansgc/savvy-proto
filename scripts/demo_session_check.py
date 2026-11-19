#!/usr/bin/env python3
"""Exercise workspace isolation through the frontend on a disposable demo only."""
import http.cookiejar
import json
import os
import urllib.error
import urllib.request
import uuid

ORIGIN = os.environ.get('SAVVY_DEMO_TEST_ORIGIN', 'http://127.0.0.1:3100')
assert ORIGIN in ('http://127.0.0.1:3100', 'http://127.0.0.1:3106')
assert os.environ.get('SAVVY_DISPOSABLE_UI_WRITES') == '1', 'Use a disposable database'
READ = 'query($section:String!){billingWorkspace(caseId:"advisor",audience:"product",section:$section,serviceStart:"2026-10-01",serviceEndExclusive:"2026-11-01")}'
MUTATION = 'mutation Save($action:String!,$input:JSON!,$key:String!){billingCommand(caseId:"advisor",action:$action,input:$input,idempotencyKey:$key){data errors{code message}}}'


class Browser:
    def __init__(self):
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def request(self, path, method='GET', body=None, status=200, origin=ORIGIN, extra=None):
        headers = {'Content-Type': 'application/json', 'Origin': origin, **(extra or {})}
        payload = None if body is None else json.dumps(body).encode()
        try:
            response = self.opener.open(urllib.request.Request(ORIGIN + path, data=payload, method=method, headers=headers), timeout=40)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = json.load(response)
            assert response.status == status, (status, response.status, data)
            assert 'no-store' in response.headers['Cache-Control']
            return data

    def read(self, section):
        result = self.request('/api/graphql', 'POST', {'query': READ, 'variables': {'section': section}})
        assert not result.get('errors'), result
        return result['data']['billingWorkspace']

    def command(self, action, inputs, status=200, extra=None):
        data = self.request('/api/graphql', 'POST', {'query': MUTATION,
            'variables': {'action': action, 'input': inputs, 'key': str(uuid.uuid4())}}, status=status, extra=extra)
        if status != 200:
            assert data['errors'][0]['extensions']['code'] == 'DEMO_WORKSPACE_REQUIRED', data
            return None
        result = data['data']['billingCommand']
        assert not result['errors'], result
        return result['data']


def main():
    sample, first, second = Browser(), Browser(), Browser()
    original = sample.read('overview')['summary']
    assert original['original_billed_minor'] + original['debit_minor'] - original['credit_minor'] == original['corrected_billed_minor']
    sample.command('SAVE_POLICY', {}, status=403, extra={'X-Savvy-Public-Demo': '0'})
    first.request('/api/demo-session', 'POST', status=403, origin='https://example.invalid')
    try:
        for browser in [first, second]:
            assert browser.request('/api/demo-session', 'POST') == {'active': True}
            cookie, = browser.cookies
            assert cookie.has_nonstandard_attr('HttpOnly')
        base = first.read('terms')['policies'][0]
        config = base['config']
        config['version'] = 'visitor-planning-fee'
        next(c for c in config['components'] if c['id'] == 'planning')['amount_minor'] = 6500
        draft = first.command('SAVE_POLICY', {'policy': config, 'effective_from':'2026-09-01',
            'effective_to':'2026-11-01', 'reason':'Compare an isolated planning fee change'})['policy_id']
        compared = first.command('COMPARE_POLICY', {'policy_id':draft, 'baseline_policy_id':base['id'],
            'subject_id':'alder-household','service_start':'2026-10-01','service_end_exclusive':'2026-11-01'})
        assert (compared['before_minor'], compared['after_minor']) == (106918, 108418), compared
        for browser, visible in [(first, True), (second, False), (sample, False)]:
            assert (draft in [item['id'] for item in browser.read('queue')['requests']]) == visible
            assert browser.read('overview')['summary'] == original
        saved_cookie, = first.cookies
        assert first.request('/api/demo-session', 'DELETE') == {'active': False}
        assert not list(first.cookies)
        first.cookies.set_cookie(saved_cookie)
        first.command('SAVE_POLICY', {}, status=403)
        assert draft not in [item['id'] for item in first.read('queue')['requests']]
    finally:
        first.request('/api/demo-session', 'DELETE')
        second.request('/api/demo-session', 'DELETE')
    print('Visitor isolation verified: independent sessions, exact policy comparison, unchanged samples, scope revocation.')


if __name__ == '__main__':
    main()
