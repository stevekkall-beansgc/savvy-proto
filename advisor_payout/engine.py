"""Deterministic, synthetic advisor-payout model. No network or persistence."""

from __future__ import annotations

from copy import deepcopy
from datetime import date, timedelta
import re

CALCULATION_VERSION = "1.0.0"
FEE_BASIS = "daily_closing_aum_act365_arrears"
MAX_SAFE_INTEGER = 2**53 - 1
MAX_MONEY = 10**13
FEE_DENOMINATOR = 10_000 * 365


def _integer(value, label, minimum=0, maximum=MAX_MONEY):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f"{label} must be an integer from {minimum} to {maximum}")
    return value


def _day(value, label):
    if not isinstance(value, str):
        raise ValueError(f"{label} must be an ISO calendar date")
    try:
        parsed = date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{label} must be an ISO calendar date") from exc
    if parsed.isoformat() != value:
        raise ValueError(f"{label} must use YYYY-MM-DD")
    return parsed


def _identifier(value, label):
    if not isinstance(value, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", value):
        raise ValueError(f"{label} must be a short lowercase identifier")
    return value


def _text(value, label):
    if not isinstance(value, str) or not value or len(value) > 300:
        raise ValueError(f"{label} must be nonempty text of at most 300 characters")
    return value


def _round_ratio(numerator, denominator):
    """Round an exact ratio to an integer, halves away from zero."""
    sign = -1 if numerator < 0 else 1
    return sign * ((2 * abs(numerator) + denominator) // (2 * denominator))


def _allocate(amount, weights):
    """Largest-remainder allocation; ties follow input order; exact cent sum."""
    if not weights:
        if amount:
            raise ValueError("Cannot allocate an amount without recipients")
        return []
    total = sum(weights)
    if total == 0:
        if amount:
            raise ValueError("Cannot allocate new assets without a billable client base")
        return [0] * len(weights)
    sign = -1 if amount < 0 else 1
    divided = [divmod(abs(amount) * weight, total) for weight in weights]
    values = [pair[0] for pair in divided]
    remainder = abs(amount) - sum(values)
    order = sorted(range(len(weights)), key=lambda i: (-divided[i][1], i))
    for index in order[:remainder]:
        values[index] += 1
    return [sign * value for value in values]


def _dates(start, end):
    return [start + timedelta(days=index) for index in range((end - start).days + 1)]


def _safe_tree(value):
    if type(value) is int and abs(value) > MAX_SAFE_INTEGER:
        raise ValueError("An integer exceeds the JSON/JavaScript safe-integer range")
    if isinstance(value, dict):
        for child in value.values():
            _safe_tree(child)
    elif isinstance(value, list):
        for child in value:
            _safe_tree(child)


def _metadata(dataset):
    if not isinstance(dataset, dict):
        raise ValueError("dataset must be an object")
    _safe_tree(dataset)
    if dataset.get("synthetic") is not True:
        raise ValueError("This demo accepts explicitly synthetic data only")
    if dataset.get("currency") != "USD":
        raise ValueError("Only USD is supported")
    if dataset.get("fee_basis") != FEE_BASIS:
        raise ValueError("Unsupported billing basis; this demo supports daily closing AUM, ACT/365, in arrears only")
    start = _day(dataset.get("period_start"), "period_start")
    end = _day(dataset.get("period_end"), "period_end")
    as_of = _day(dataset.get("as_of_date"), "as_of_date")
    payment = _day(dataset.get("next_payout_date"), "next_payout_date")
    if not 1 <= (end - start).days + 1 <= 31 or (start.year, start.month) != (end.year, end.month):
        raise ValueError("Billing period must be 1–31 days within one calendar month")
    if not start <= as_of <= end:
        raise ValueError("as_of_date must be inside the billing period")
    if payment <= end:
        raise ValueError("An arrears payout date must be after the billing period")
    advisors = dataset.get("advisors")
    if not isinstance(advisors, list) or not 1 <= len(advisors) <= 50:
        raise ValueError("advisors must contain 1–50 profiles")
    ids = [_identifier(a.get("id"), "advisor.id") for a in advisors if isinstance(a, dict)]
    if len(ids) != len(advisors) or len(set(ids)) != len(ids):
        raise ValueError("Advisor profiles must be objects with unique IDs")
    return start, end, as_of


def list_advisors(dataset):
    """Return display metadata, without implying validation of unseen financial rows."""
    _metadata(dataset)
    result = []
    for advisor in dataset["advisors"]:
        result.append({
            "id": advisor["id"],
            "name": _text(advisor.get("name"), "advisor.name"),
            "description": _text(advisor.get("description"), "advisor.description"),
            "avatar_initials": advisor.get("avatar_initials", ""),
            "theme": advisor.get("theme", "blue"),
        })
    return result


def _validated_advisor(advisor, start, end, as_of):
    _text(advisor.get("name"), "advisor.name")
    _text(advisor.get("description"), "advisor.description")
    _integer(advisor.get("default_collection_bps"), "default_collection_bps", 0, 10_000)
    clients = advisor.get("clients")
    if not isinstance(clients, list) or not 1 <= len(clients) <= 100:
        raise ValueError("Each advisor requires 1–100 clients")
    actual_dates = [d.isoformat() for d in _dates(start, as_of)]
    client_ids = set()
    rows_by_client = []
    for client in clients:
        if not isinstance(client, dict):
            raise ValueError("Client must be an object")
        client_id = _identifier(client.get("id"), "client.id")
        if client_id in client_ids:
            raise ValueError("Duplicate client ID")
        client_ids.add(client_id)
        _text(client.get("name"), "client.name")
        _integer(client.get("annual_fee_bps"), "annual_fee_bps", 0, 10_000)
        observations = client.get("observations")
        if not isinstance(observations, list) or len(observations) != len(actual_dates):
            raise ValueError(f"Missing or extra daily observations for {client_id}; explicit zero rows are required")
        by_date = {}
        for row in observations:
            if not isinstance(row, dict):
                raise ValueError("Daily observation must be an object")
            key = _day(row.get("date"), "observation.date").isoformat()
            if key in by_date:
                raise ValueError("Duplicate daily observation")
            by_date[key] = row
        if set(by_date) != set(actual_dates):
            raise ValueError(f"Missing or out-of-period daily observations for {client_id}")
        previous = None
        for key in actual_dates:
            row = by_date[key]
            opening = _integer(row.get("opening_aum_cents"), "opening_aum_cents")
            closing = _integer(row.get("aum_cents"), "aum_cents")
            market = _integer(row.get("market_change_cents"), "market_change_cents", -MAX_MONEY)
            flow = _integer(row.get("net_flow_cents"), "net_flow_cents", -MAX_MONEY)
            if opening + market + flow != closing:
                raise ValueError(f"AUM does not reconcile for {client_id} on {key}")
            if previous is not None and opening != previous:
                raise ValueError(f"AUM observations are discontinuous for {client_id} on {key}")
            previous = closing
        rows_by_client.append(by_date)

    contracts = advisor.get("contracts")
    if not isinstance(contracts, list) or not 1 <= len(contracts) <= 31:
        raise ValueError("contracts must contain 1–31 effective-dated terms")
    contract_ids = set()
    normalized = []
    for term in contracts:
        if not isinstance(term, dict):
            raise ValueError("Contract term must be an object")
        identifier = _identifier(term.get("id"), "contract.id")
        if identifier in contract_ids:
            raise ValueError("Duplicate contract ID")
        contract_ids.add(identifier)
        _text(term.get("label"), "contract.label")
        beginning = _day(term.get("effective_from"), "effective_from")
        finish = _day(term.get("effective_to"), "effective_to")
        if beginning > finish:
            raise ValueError("Contract effective dates are reversed")
        _integer(term.get("advisor_share_bps"), "advisor_share_bps", 0, 10_000)
        normalized.append((beginning, finish, term))
    day_terms = []
    for day in _dates(start, end):
        matches = [index for index, (beginning, finish, _) in enumerate(normalized) if beginning <= day <= finish]
        if len(matches) != 1:
            raise ValueError(f"Exactly one contract must cover {day.isoformat()}; gaps and overlaps are unsupported")
        day_terms.append(matches[0])
    if set(day_terms) != set(range(len(contracts))):
        raise ValueError("Every supplied contract must cover at least one billing-period day")

    expenses = advisor.get("expenses")
    if not isinstance(expenses, list) or len(expenses) > 30:
        raise ValueError("expenses must be a list with at most 30 entries")
    expense_ids = set()
    for expense in expenses:
        if not isinstance(expense, dict):
            raise ValueError("Expense must be an object")
        identifier = _identifier(expense.get("id"), "expense.id")
        if identifier in expense_ids:
            raise ValueError("Duplicate expense ID")
        expense_ids.add(identifier)
        _text(expense.get("label"), "expense.label")
        _integer(expense.get("amount_cents"), "expense.amount_cents")
        if expense.get("treatment") not in {"pre_share", "post_share"}:
            raise ValueError("Expense treatment must be pre_share or post_share")
    loan = advisor.get("loan")
    if not isinstance(loan, dict) or set(loan) != {"opening_balance_cents", "scheduled_repayment_cents", "repayment_cap_bps"}:
        raise ValueError("Loan supports opening balance, scheduled repayment, and a percentage cap only")
    _integer(loan["opening_balance_cents"], "opening_balance_cents")
    _integer(loan["scheduled_repayment_cents"], "scheduled_repayment_cents")
    _integer(loan["repayment_cap_bps"], "repayment_cap_bps", 0, 10_000)
    return rows_by_client, day_terms


def _scenario(value, advisor):
    if value is None:
        value = {}
    if not isinstance(value, dict):
        raise ValueError("scenario must be an object")
    unknown = set(value) - {"market_change_bps", "net_flow_cents", "collection_bps"}
    if unknown:
        raise ValueError("Unsupported scenario parameter: " + ", ".join(sorted(unknown)))
    return {
        "market_change_bps": _integer(value.get("market_change_bps", 0), "market_change_bps", -10_000, 10_000),
        "net_flow_cents": _integer(value.get("net_flow_cents", 0), "net_flow_cents", -MAX_MONEY),
        "collection_bps": _integer(value.get("collection_bps", advisor["default_collection_bps"]), "collection_bps", 0, 10_000),
    }


def _waterfall(fees, advisor, day_terms):
    """Apply segment costs/share, then period costs and capped principal repayment."""
    weights = [day_terms.count(index) for index in range(len(fees))]
    pre_requested = sum(e["amount_cents"] for e in advisor["expenses"] if e["treatment"] == "pre_share")
    post_requested = sum(e["amount_cents"] for e in advisor["expenses"] if e["treatment"] == "post_share")
    pre_segments = _allocate(pre_requested, weights)
    pre_applied = 0
    advisor_share = 0
    company_share = 0
    for index, fee in enumerate(fees):
        applied = min(fee, pre_segments[index])
        base = fee - applied
        share = _round_ratio(base * advisor["contracts"][index]["advisor_share_bps"], 10_000)
        pre_applied += applied
        advisor_share += share
        company_share += base - share
    post_applied = min(advisor_share, post_requested)
    available = advisor_share - post_applied
    loan = advisor["loan"]
    repayment = min(available, loan["opening_balance_cents"], loan["scheduled_repayment_cents"],
                    _round_ratio(available * loan["repayment_cap_bps"], 10_000))
    return {
        "pre_applied": pre_applied, "post_applied": post_applied,
        "company_share": company_share, "advisor_share": advisor_share,
        "available": available, "repayment": repayment,
        "payout": available - repayment,
        "loan_remaining": loan["opening_balance_cents"] - repayment,
        "unapplied": pre_requested - pre_applied + post_requested - post_applied,
    }


def _calculate(dataset, advisor, scenario, dates, rows_by_client, day_terms):
    start, end, as_of = dates
    all_days = _dates(start, end)
    clients = advisor["clients"]
    balances = [rows[as_of.isoformat()]["aum_cents"] for rows in rows_by_client]
    current_aum = sum(balances)
    projected_balances = list(balances)
    daily = []
    for day in all_days:
        key = day.isoformat()
        if day <= as_of:
            observations = [rows[key] for rows in rows_by_client]
            amounts = [row["aum_cents"] for row in observations]
            opening = sum(row["opening_aum_cents"] for row in observations)
            market = sum(row["market_change_cents"] for row in observations)
            flow = sum(row["net_flow_cents"] for row in observations)
        else:
            opening = sum(projected_balances)
            market = 0
            flow = 0
            if day == as_of + timedelta(days=1):
                market = _round_ratio(opening * scenario["market_change_bps"], 10_000)
                moves = _allocate(market, projected_balances)
                projected_balances = [amount + move for amount, move in zip(projected_balances, moves)]
                flow = scenario["net_flow_cents"]
                if sum(projected_balances) + flow < 0:
                    raise ValueError("Scenario outflows exceed billable assets after the market move")
                flows = _allocate(flow, projected_balances)
                projected_balances = [amount + move for amount, move in zip(projected_balances, flows)]
            amounts = list(projected_balances)
        numerator = sum(amount * client["annual_fee_bps"] for amount, client in zip(amounts, clients))
        daily.append({"date": key, "opening_aum_cents": opening, "aum_cents": sum(amounts),
                      "market_change_cents": market, "net_flow_cents": flow,
                      "fee_cents": 0, "phase": "actual" if day <= as_of else "projected",
                      "_fee_numerator": numerator})

    segment_fees = []
    earned_fees = 0
    for segment in range(len(advisor["contracts"])):
        indices = [index for index, term in enumerate(day_terms) if term == segment]
        actual = [i for i in indices if daily[i]["phase"] == "actual"]
        future = [i for i in indices if daily[i]["phase"] == "projected"]
        full_fee = _round_ratio(sum(daily[i]["_fee_numerator"] for i in indices), FEE_DENOMINATOR)
        earned = _round_ratio(sum(daily[i]["_fee_numerator"] for i in actual), FEE_DENOMINATOR)
        segment_fees.append(full_fee)
        earned_fees += earned
        # Historical cent allocations never change when future scenario inputs do.
        for group, cents in ((actual, earned), (future, full_fee - earned)):
            allocated = _allocate(cents, [daily[i]["_fee_numerator"] for i in group])
            for index, value in zip(group, allocated):
                daily[index]["fee_cents"] = value
    for row in daily:
        del row["_fee_numerator"]

    projected_fees = sum(segment_fees)
    expected_collections = _round_ratio(projected_fees * scenario["collection_bps"], 10_000)
    cash_segments = _allocate(expected_collections, segment_fees)
    economic = _waterfall(segment_fees, advisor, day_terms)
    cash = _waterfall(cash_segments, advisor, day_terms)
    summary = {
        "current_aum_cents": current_aum,
        "earned_fees_cents": earned_fees,
        "projected_fees_cents": projected_fees,
        "expected_collections_cents": expected_collections,
        "advisor_entitlement_cents": economic["available"],
        "estimated_payout_cents": cash["payout"],
        "unapplied_deductions_cents": cash["unapplied"],
        "loan_repayment_cents": cash["repayment"],
        "loan_remaining_cents": cash["loan_remaining"],
    }
    waterfall = [
        {"id": "collections", "label": "Expected fee collections", "amount_cents": expected_collections, "kind": "revenue"},
        {"id": "pre-share", "label": "Expenses before the revenue split", "amount_cents": -cash["pre_applied"], "kind": "deduction"},
        {"id": "company-share", "label": "Company share", "amount_cents": -cash["company_share"], "kind": "deduction"},
        {"id": "post-share", "label": "Expenses after the revenue split", "amount_cents": -cash["post_applied"], "kind": "deduction"},
        {"id": "loan", "label": "Capped loan repayment", "amount_cents": -cash["repayment"], "kind": "deduction"},
        {"id": "payout", "label": "Estimated advisor payment", "amount_cents": cash["payout"], "kind": "total"},
    ]
    return summary, waterfall, daily, segment_fees


def project(dataset, advisor_id, scenario=None):
    """Calculate one explicitly synthetic advisor forecast as JSON-safe data."""
    dates = _metadata(dataset)
    if not isinstance(advisor_id, str):
        raise ValueError("advisor_id must be a string")
    advisor = next((a for a in dataset["advisors"] if a["id"] == advisor_id), None)
    if advisor is None:
        raise ValueError(f"Unknown advisor: {advisor_id}")
    rows, day_terms = _validated_advisor(advisor, *dates)
    normalized = _scenario(scenario, advisor)
    baseline_scenario = _scenario(None, advisor)
    summary, waterfall, daily, segment_fees = _calculate(dataset, advisor, normalized, dates, rows, day_terms)
    baseline_summary = summary if normalized == baseline_scenario else _calculate(dataset, advisor, baseline_scenario, dates, rows, day_terms)[0]
    summary["baseline_payout_cents"] = baseline_summary["estimated_payout_cents"]
    summary["delta_payout_cents"] = summary["estimated_payout_cents"] - summary["baseline_payout_cents"]
    start, end, as_of = dates
    warnings = [
        "Synthetic demonstration only. These contracts, balances, clients, and assumptions are not Savvy records or verified Savvy rules.",
        "Only daily closing billable AUM / ACT/365 / arrears is implemented. Advance billing, prior-period or period-end valuation bases, tiered fees, and alternative contract conventions are unsupported.",
        "Expected collections are a scenario assumption, not verified cash or an ERP balance. This forecast does not authorize or execute a payment.",
    ]
    if summary["unapplied_deductions_cents"]:
        warnings.append("Some deductions exceed expected available proceeds. They are shown as unapplied, not forgiven; recovery timing and priority require an actual contract.")
    if as_of == end and (normalized["market_change_bps"] or normalized["net_flow_cents"]):
        warnings.append("No projected days remain in this period; market and flow scenario inputs cannot change closed-period observations.")
    result = {
        "advisor": {key: advisor.get(key, "") for key in ("id", "name", "description", "avatar_initials", "theme")},
        "meta": {
            "period_start": start.isoformat(), "period_end": end.isoformat(), "as_of_date": as_of.isoformat(),
            "next_payout_date": dataset["next_payout_date"], "currency": "USD", "synthetic": True,
            "source_mode": "synthetic", "calculation_version": CALCULATION_VERSION, "supported_billing_basis": FEE_BASIS,
        },
        "scenario": normalized, "summary": summary, "waterfall": waterfall, "daily": daily,
        "contracts": [dict(deepcopy(term), projected_fees_cents=segment_fees[i]) for i, term in enumerate(advisor["contracts"])],
        "expenses": deepcopy(advisor["expenses"]), "loan": deepcopy(advisor["loan"]),
        "clients": [{"id": client["id"], "name": client["name"],
                     "aum_cents": rows[i][as_of.isoformat()]["aum_cents"],
                     "annual_fee_bps": client["annual_fee_bps"], "status": client.get("status", "Active"),
                     "event_date": client.get("event_date")}
                    for i, client in enumerate(advisor["clients"])],
        "assumptions": [
            "All amounts are USD. Only explicitly billable closing assets earn fees; annual fee basis points are supplied per client.",
            "Fees accrue each calendar day on ACT/365. Exact rational accruals are rounded once per effective contract segment, half away from zero.",
            "Displayed daily cents reconcile to segment totals. Historical earned cents are fixed; any period-end rounding remainder belongs to projected days.",
            "The baseline holds the last observed asset balance constant. A scenario market move is a one-time shock on the first projected day, followed by net flows that day; subsequent balances are held constant.",
            "Scenario flows are allocated proportionally across the existing billable client base and retain those clients' explicit fee rates. A new client with different terms needs a separate input.",
            "Fixed period expenses apply at the next payout. Pre-share costs are allocated to effective contract segments by calendar days; post-share costs apply after the split.",
            "The next payout uses expected collections by its stated date. Advisor entitlement uses full projected fees before debt repayment; neither amount is a guarantee.",
            "Loan repayments are principal only and capped by available proceeds, scheduled maximum, outstanding balance, and the stated percentage cap. No interest, taxes, or withholding is modeled.",
        ],
        "warnings": warnings,
    }
    _safe_tree(result)
    return result
