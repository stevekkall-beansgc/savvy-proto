#!/usr/bin/env python3
"""Read-only origin and product checks against the device-hosted frontend proxy."""
import json
import urllib.error
import urllib.request

QUERY = {"query": '{ productWorkspace(workspace:"broker") }'}


def check(origin, expected):
    request = urllib.request.Request("http://127.0.0.1:3100/api/graphql",
        data=json.dumps(QUERY).encode(), headers={"Content-Type": "application/json",
        "Origin": origin, "X-Demo-Role": "advisor"})
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        assert response.status == expected, (origin, response.status)
        body = json.load(response)
    if expected == 200:
        workspace = body['data']['productWorkspace']
        assert workspace['selected_broker_id'] == 'broker-alex'
        assert 'configuration' not in workspace and 'proposals' not in workspace
        assert workspace['earnings']['earned_minor'] == '175000'
    print(f"PASS {origin}: {expected}")


if __name__ == '__main__':
    for origin in ('http://127.0.0.1:3100', 'http://localhost:3100', 'https://savvy-proto.beanshop.top'):
        check(origin, 200)
    for origin in ('https://unrelated.example', 'https://savvy-proto.beanshop.top.evil.example', 'http://savvy-proto.beanshop.top'):
        check(origin, 403)
