#!/usr/bin/env python3
"""Read-only local GraphQL boundary checks; rejected commands must not write."""
import json
from pathlib import Path
import urllib.error
import urllib.request

URL = "http://127.0.0.1:3101"
QUERY = '{ reconciliation(periodStart:"2026-11-01",periodEndExclusive:"2026-12-01") }'


def request(path, body=None, role="operator", origin=None, content_type="application/json"):
    headers = {"Content-Type": content_type, "X-Demo-Role": role}
    if origin:
        headers["Origin"] = origin
    payload = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(urllib.request.Request(URL + path, data=payload, headers=headers), timeout=20) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def check(condition, label):
    if not condition:
        raise AssertionError(label)
    results.append(label)


if __name__ == "__main__":
    results = []
    code, health = request("/health")
    check(code == 200 and health["synthetic"] is True and health["connected"] is False, "local synthetic health")
    for role in ["operator", "finance", "legal", "auditor"]:
        code, value = request("/graphql", {"query": QUERY}, role)
        check(code == 200 and value.get("data", {}).get("reconciliation", {}).get("synthetic") is True,
              role + " can read reconciliation")
        totals = value["data"]["reconciliation"]["totals"]
        check(all(amount is None or isinstance(amount, str) for amount in totals.values()), role + " receives exact money strings or unknown")
    code, value = request("/graphql", {"query": QUERY}, "advisor")
    check(value.get("data") is None and value["errors"][0]["extensions"]["code"] == "FORBIDDEN", "advisor cannot read entity bank evidence")
    code, value = request("/graphql", {"query": QUERY}, "administrator")
    check(code == 403, "unsupported simulated role rejected")
    code, value = request("/graphql", {"query": QUERY}, origin="https://example.com")
    check(code == 403 and value["error"] == "LOCAL_ORIGIN_REQUIRED", "foreign origin rejected")
    code, value = request("/graphql", {"query": QUERY}, content_type="text/plain")
    check(code == 415, "non-JSON envelope rejected")
    code, value = request("/graphql", [{"query": QUERY}])
    check(code == 400, "batched envelope rejected")
    mutation = 'mutation($input:JSON!){workbenchCommand(action:CLOSE_RECONCILIATION,input:$input,idempotencyKey:"http-rejected-close"){data errors{code message}}}'
    params = {"query": mutation, "variables": {"input": {"period_start": "2026-11-01", "period_end_exclusive": "2026-12-01", "expected_manifest_hash": "stale", "reason": "HTTP rejection check"}}}
    for role in ["operator", "legal", "advisor", "auditor", "finance"]:
        code, value = request("/graphql", params, role)
        result = value["data"]["workbenchCommand"]
        expected = "HASH_CHANGED" if role == "finance" else "FORBIDDEN"
        check(result["data"] is None and result["errors"][0]["code"] == expected, role + " close guard")
    target = Path(__file__).resolve().parent.parent / "artifacts/cto-readiness/http.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"status": "passed", "checks": results, "accepted_commands": 0}, indent=2) + "\n")
    print(str(len(results)) + " HTTP boundary checks passed; no accepted writes.")
