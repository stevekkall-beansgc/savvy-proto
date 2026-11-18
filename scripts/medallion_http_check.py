#!/usr/bin/env python3
"""Read-only acceptance through the isolated app's actual GraphQL transport."""
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

ORIGIN = os.environ.get("SAVVY_API_ORIGIN", "http://127.0.0.1:3102")
if ORIGIN != "http://127.0.0.1:3102":
    raise ValueError("Medallion acceptance targets the isolated API on port 3102")
ROOT = Path(__file__).resolve().parent.parent
QUERY = """query($workspace:String!,$caseId:ID!,$scenarioId:ID){
  medallionWorkspace(workspace:$workspace,caseId:$caseId,scenarioId:$scenarioId)
}"""


def request(role, query, variables=None):
    req = urllib.request.Request(ORIGIN + "/graphql",
        data=json.dumps({"query": query, "variables": variables or {}}).encode(),
        headers={"Content-Type": "application/json", "X-Demo-Role": role})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def workspace(role, case, scenario="baseline", experience=None):
    return request(role, QUERY, {"workspace": experience or role,
        "caseId": case, "scenarioId": scenario})


def main():
    checks = []

    def check(condition, description):
        if not condition:
            raise AssertionError(description)
        checks.append(description)

    def denied(result, description):
        check(any(e.get("extensions", {}).get("code") == "FORBIDDEN"
                  for e in result.get("errors", [])), description)

    def product(role, case, scenario, expected):
        result = workspace(role, case, scenario)
        check(not result.get("errors"), role + "/" + scenario + " is readable")
        data = result["data"]["medallionWorkspace"]
        run = data["run"]
        check(run and run["status"] == "completed", case + "/" + scenario + " is complete")
        rows = {row["output_id"]: row for row in run["summary"] + run["detail"]}
        for key, amount in expected.items():
            check(rows[key]["minor"] == str(amount), case + "/" + scenario + ": " + key)
            check(bool(rows[key]["detail_refs"]) and rows[key]["run_id"] == run["id"],
                  case + "/" + scenario + ": " + key + " references retained detail")
        private = {"input_manifest", "original_bytes", "nodes", "rate_rows", "pipeline", "policies", "events", "source_evidence"}

        def inspect(value):
            if isinstance(value, dict):
                check(not private.intersection(value), case + "/" + scenario + " omits internal payload fields")
                for child in value.values():
                    inspect(child)
            elif isinstance(value, list):
                for child in value:
                    inspect(child)

        inspect(data)
        check(bool(run["comparison"]) and run["comparison"]["run_id"] == run["id"],
              case + "/" + scenario + " value comparison uses same retained run")
        return data

    advisor = product("advisor", "advisor", "baseline",
                      {"compensation": 330000, "coverage": 100000, "payable": 230000})
    ria = product("ria", "ria", "baseline", {"net": 13000, "charge": 25000, "rebate": 12000})
    check(advisor["run"]["comparison"]["benefit"]["minor"] == "26000", "advisor value benefit is $260")
    check(ria["run"]["comparison"]["benefit"]["minor"] == "13000", "RIA value benefit is $130")
    for role, case, scenario, expected in [
        ("advisor", "advisor", "bonus_outside", {"compensation": 340000, "payable": 240000}),
        ("advisor", "advisor", "bonus_inside", {"compensation": 330000, "payable": 230000}),
        ("ria", "ria", "service_credit", {"net": 10000, "rebate": 12000}),
        ("advisor", "advisor", "correction", {"fees": 380800, "compensation": 330000, "payable": 230000}),
        ("advisor", "advisor", "pending_payment", {"compensation": 330000, "payable": 230000}),
        ("advisor", "advisor", "confirmed_payment", {"compensation": 330000, "statement_balance": 180000}),
    ]:
        data = product(role, case, scenario, expected)
        if scenario == "confirmed_payment":
            check(data["statement"]["balance_minor"] == "180000", "confirmed payment produces $1,800 statement balance")
            outstanding = next(row for row in data["run"]["summary"] if row["output_id"] == "statement_balance")
            check(outstanding["source_kind"] == "statement_projection" and outstanding["application_refs"],
                  "outstanding headline retains obligation and independent payment provenance")
        if scenario == "pending_payment":
            check(any(row["minor"] == "50000" and row["status"] in {"requested", "pending_review"}
                      for row in data["statement"]["pending_items"]),
                  "requested $500 payout remains visible separately without reducing the $2,300 payable")

    for role, case in [("advisor", "advisor"), ("ria", "ria")]:
        denied(workspace(role, case, experience="internal"), role + " cannot enter internal workspace")
        denied(workspace(role, "ria" if case == "advisor" else "advisor"), role + " cannot change party scope")
        denied(workspace(role, case, "private-internal-review"), role + " cannot guess a private scenario")
    # Each field is a separate request: GraphQL non-null propagation must not
    # conceal a later field that was never actually executed.
    for field in ["workbench", "collections", "productWorkspace(workspace:\"internal\")",
                  "entitlementLedger", "reconciliation(periodStart:\"2026-09-01\",periodEndExclusive:\"2026-10-01\")",
                  "run(id:\"private-run\"){id}", "reviewPacket(runId:\"private-run\")",
                  "brokerBook(brokerId:\"broker-alex\"){id}"]:
        denied(request("ria", "{" + field + "}"), "RIA legacy field denied: " + field)
    for case in ["advisor", "ria"]:
        internal = workspace("operator", case, experience="internal")["data"]["medallionWorkspace"]
        check(len(internal["pipeline"]["stages"]) >= 4, case + " has internal layer walkthrough")
        check(bool(internal["pipeline"]["result"]["bindings"]), case + " has actual term bindings")
    report = {"status": "passed", "mutation_requests": 0, "checks": checks}
    target = ROOT / "artifacts/medallion/http.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(checks)} read-only Medallion HTTP assertions passed.")


if __name__ == "__main__":
    main()
