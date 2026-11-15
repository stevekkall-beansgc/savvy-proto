#!/usr/bin/env python3
"""Read-only acceptance checks through the actual local product GraphQL boundary."""
import json
from pathlib import Path
import urllib.request

QUERY = "query($workspace:String!,$broker:ID){productWorkspace(workspace:$workspace,brokerId:$broker)}"
ROOT = Path(__file__).resolve().parent.parent


def query(role, workspace, broker="broker-alex"):
    body = {"query": QUERY, "variables": {"workspace": workspace, "broker": broker}}
    request = urllib.request.Request("http://127.0.0.1:3101/graphql", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "X-Demo-Role": role})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def main():
    checks = []

    def check(condition, description):
        if not condition:
            raise AssertionError(description)
        checks.append(description)

    result = query("advisor", "broker")
    broker = result["data"]["productWorkspace"]
    check(broker["schema_version"] == "product-v1" and broker["synthetic"], "synthetic product contract")
    check([b["id"] for b in broker["brokers"]] == ["broker-alex"], "broker identity scoped by server")
    check("configuration" not in broker and "proposals" not in broker, "internal proposal contents omitted from broker payload")
    check("broker-jordan" not in json.dumps(broker) and "customer-birch" not in json.dumps(broker), "other advisor and customer omitted")
    check(all(broker["earnings"][k] is None or isinstance(broker["earnings"][k], str)
              for k in ["earned_minor", "coverage_minor", "incremental_minor", "guarantee_minor"]), "money uses strings or explicit unknown")
    check(all(a["illustrative"] for a in broker["agreements"]), "agreement evidence labeled illustrative")
    check(all(line["billing_obligation_ids"] for line in broker["earnings"]["lines"]), "earnings linked to native billing obligations")
    for invoice in broker["billing"]["invoices"]:
        check(sum(int(line["amount_minor"]) for line in invoice["lines"]) == int(invoice["amount_minor"]), "native invoice line conservation: " + invoice["id"])
    for role in ["operator", "finance", "legal", "auditor"]:
        response = query(role, "internal")
        check(response.get("errors") is None and "configuration" in response["data"]["productWorkspace"], role + " can inspect internal terms")
    for workspace, identity in [("internal", "broker-alex"), ("broker", "broker-jordan")]:
        response = query("advisor", workspace, identity)
        check(response.get("data") is None and response["errors"][0]["extensions"]["code"] == "FORBIDDEN", "advisor denied " + workspace + "/" + identity)
    response = query("operator", "unsupported")
    check(response["errors"][0]["extensions"]["code"] == "VALIDATION_ERROR", "unsupported workspace rejected")
    jordan = query("operator", "internal", "broker-jordan")["data"]["productWorkspace"]
    check(bool(jordan["billing"]["instructions"]), "custodial billing route present")
    for data in [broker, jordan]:
        check(all(a["mocked"] and a["provider"] == "mock_campfire" for a in data["billing"]["accounting"]), "accounting observations explicitly mocked for " + data["selected_broker_id"])
        check(all(a["document_ref"]["system"] == "mock_clm" for a in data["agreements"]), "document references explicitly mocked for " + data["selected_broker_id"])
    target = ROOT / "artifacts/workspaces/http.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"status": "passed", "checks": checks, "mutation_requests": 0}, indent=2) + "\n")
    print(str(len(checks)) + " product HTTP checks passed; read-only requests only.")


if __name__ == "__main__":
    main()
