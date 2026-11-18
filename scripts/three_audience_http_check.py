#!/usr/bin/env python3
"""Non-mutating checks of the isolated three-audience API and preview proxy."""
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
API = "http://127.0.0.1:3102/graphql"
PREVIEW = os.environ.get("SAVVY_PREVIEW_ORIGIN", "http://127.0.0.1:3103")
if PREVIEW not in {"http://127.0.0.1:3103", "http://127.0.0.1:3104"}:
    raise ValueError("Acceptance only targets the isolated local previews")
PROXY = PREVIEW + "/api/graphql"


def request(role, query, variables=None, endpoint=API):
    req = urllib.request.Request(endpoint,
        data=json.dumps({"query": query, "variables": variables or {}}).encode(),
        headers={"Content-Type": "application/json", "X-Demo-Role": role})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def main():
    checks = []

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        checks.append(label)

    def read(role, field, variables=None, endpoint=API):
        result = request(role, "{" + field + "}", variables, endpoint)
        check(not result.get("errors"), role + ": " + field + " readable")
        return next(iter(result["data"].values()))

    for case, balance in [("advisor", "230000"), ("ria", "13000")]:
        summary = read(case, f'audienceSummary(caseId:"{case}")')
        check(summary["run"] is not None, case + " has published result")
        check("detail" not in summary["run"] and "statement" not in summary,
              case + " overview excludes book detail")
        statement = read(case, f'audienceStatement(caseId:"{case}",limit:1,offset:0)')
        check(statement["balance_minor"] == balance, case + " exact statement balance")
        check(len(statement["lines"]) == 1 and statement["total"] > 1,
              case + " statement detail is paged")
        check(statement["lines"][0]["basis"] and statement["lines"][0]["governing_terms"],
              case + " statement has linked basis and agreement")
        proxy = read(case, f'audienceSummary(caseId:"{case}")', endpoint=PROXY)
        check(proxy == summary, case + " preview proxy preserves scoped published data")
        ids, offset = [], 0
        while True:
            page = read(case, f'audienceClients(caseId:"{case}",limit:7,offset:{offset})')
            ids.extend(row["id"] for row in page["items"])
            if len(ids) >= page["total"]:
                break
            check(bool(page["items"]), case + " account pages make progress")
            offset += len(page["items"])
        check(len(ids) == len(set(ids)) == page["total"], case + " complete account pagination")
        if case == "ria":
            check(len(ids) == 30, "RIA roster contains 30 separately retrievable accounts")
            account = read(case, f'audienceClient(caseId:"ria",clientId:"{ids[-1]}")')
            check(account["account"]["id"] == ids[-1], "Non-featured RIA account is accessible")
        for field in [f'lineageRecords(caseId:"{case}")', f'financeWorkspace(caseId:"{case}")']:
            denied = request(case, "{" + field + "}")
            check(any(e.get("extensions", {}).get("code") == "FORBIDDEN"
                      for e in denied.get("errors", [])), case + " cannot access " + field)

    finance = read("finance", 'financeWorkspace(caseId:"ria")')
    check([finance["cash"][k] for k in ["amount_minor", "associated_minor", "unapplied_minor"]]
          == ["90000", "60000", "30000"], "Original Finance cash remains $900/$600/$300")
    records = {r["record_id"]: r for r in finance["recognition"]["records"]}
    check(records["journal-advance-2027-01-v1"]["recognized_minor"] == "40000",
          "Independent January recognition is $400")
    check(records["journal-unbilled-2027-01"]["unbilled_minor"] == "10000"
          and records["journal-unbilled-reclass-2027-02"]["recognized_minor"] == "0",
          "Unbilled timing reclassifies without duplicate revenue")
    check(finance["recognition"]["missing_outcome"]["status"] == "missing",
          "Missing posted outcome remains missing")
    advisor = read("finance", 'financeWorkspace(caseId:"advisor")')
    check(advisor["cash"]["direction"] == "outbound_advisor"
          and "finance-cash-900" not in json.dumps(advisor), "Outbound advisor context excludes RIA cash")

    ids, offset = [], 0
    while True:
        page = read("operator", f'lineageRecords(caseId:"ria",limit:100,offset:{offset})')
        ids.extend(item["id"] for item in page["items"])
        if len(ids) >= page["total"]:
            break
        check(bool(page["items"]), "Lineage pages make progress")
        offset += len(page["items"])
    check(len(ids) == len(set(ids)) == page["total"], "All retained and native lineage records are paged")
    record = read("operator", f'lineageRecord(caseId:"ria",recordId:"{ids[-1]}",limit:1)')
    check(record["record"]["id"] == ids[-1] and record["edge_total"] >= len(record["edges"]),
          "Non-featured record exposes scoped paged transitions")
    target = ROOT / "artifacts/medallion/three-audience-http.json"
    target.write_text(json.dumps({"status": "passed", "mutation_requests": 0,
                                  "checks": checks}, indent=2) + "\n")
    print(f"{len(checks)} three-audience HTTP checks passed; no mutations sent.")


if __name__ == "__main__":
    main()
