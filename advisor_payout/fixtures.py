"""Fictional fixtures, generated locally without external data."""

from datetime import date, timedelta


def _client(identifier, name, opening, fee_bps, *, markets=None, flows=None, status="Active", event_date=None):
    markets = markets or {}
    flows = flows or {}
    observations = []
    balance = opening
    for index in range(13):
        day = (date(2026, 11, 1) + timedelta(days=index)).isoformat()
        market = markets.get(index + 1, 0)
        flow = flows.get(index + 1, 0)
        observations.append({"date": day, "opening_aum_cents": balance,
                             "market_change_cents": market, "net_flow_cents": flow,
                             "aum_cents": balance + market + flow})
        balance += market + flow
    return {"id": identifier, "name": name, "annual_fee_bps": fee_bps,
            "status": status, "event_date": event_date, "observations": observations}


def _contract(identifier, label, share_bps, beginning="2026-11-01", ending="2026-11-30"):
    return {"id": identifier, "label": label, "advisor_share_bps": share_bps,
            "effective_from": beginning, "effective_to": ending}


def _no_loan():
    return {"opening_balance_cents": 0, "scheduled_repayment_cents": 0, "repayment_cap_bps": 10_000}


def demo_dataset():
    """Return a fresh, explicitly synthetic November 2026 data set."""
    return {
        "schema_version": "advisor-payout-demo/v1", "synthetic": True, "currency": "USD",
        "fee_basis": "daily_closing_aum_act365_arrears",
        "period_start": "2026-11-01", "period_end": "2026-11-30", "as_of_date": "2026-11-13",
        "next_payout_date": "2026-12-05",
        "advisors": [
            {
                "id": "advisor-alex", "name": "Alex Morgan", "avatar_initials": "AM", "theme": "blue",
                "description": "Simple 80/20 split · daily billable assets · no expense deductions",
                "default_collection_bps": 10_000,
                "clients": [
                    _client("alex-household-a", "Sample household A", 600_000_000, 100,
                            markets={2: 1_200_000, 5: -600_000, 9: 900_000, 12: -300_000}, flows={7: 10_000_000}),
                    _client("alex-household-b", "Sample household B", 400_000_000, 100,
                            markets={2: 800_000, 5: -400_000, 9: 600_000, 12: -200_000}, flows={11: -5_000_000}),
                ],
                "contracts": [_contract("alex-standard", "Advisor 80% / company 20%", 8_000)],
                "expenses": [], "loan": _no_loan(),
            },
            {
                "id": "advisor-jordan", "name": "Jordan Ellis", "avatar_initials": "JE", "theme": "purple",
                "description": "75/25 split · rent and support · marketing · capped loan repayment",
                "default_collection_bps": 10_000,
                "clients": [
                    _client("jordan-household-a", "Sample household C", 1_200_000_000, 75),
                    _client("jordan-household-b", "Sample household D", 800_000_000, 75),
                ],
                "contracts": [_contract("jordan-standard", "Advisor 75% / company 25%", 7_500)],
                "expenses": [
                    {"id": "rent", "label": "Office rent", "amount_cents": 120_000, "treatment": "pre_share"},
                    {"id": "support", "label": "Support staff allocation", "amount_cents": 180_000, "treatment": "pre_share"},
                    {"id": "marketing", "label": "Marketing spend", "amount_cents": 60_000, "treatment": "post_share"},
                ],
                "loan": {"opening_balance_cents": 250_000, "scheduled_repayment_cents": 200_000, "repayment_cap_bps": 2_000},
            },
            {
                "id": "advisor-taylor", "name": "Taylor Chen", "avatar_initials": "TC", "theme": "teal",
                "description": "Share changes on November 16 · one new client and one departing client",
                "default_collection_bps": 9_500,
                "clients": [
                    _client("taylor-household-a", "Sample household E", 700_000_000, 100,
                            markets={3: 700_000, 6: -350_000, 10: 1_050_000}),
                    _client("taylor-household-new", "Sample household F", 0, 100, flows={8: 150_000_000},
                            status="New this month", event_date="2026-11-08"),
                    _client("taylor-household-departed", "Sample household G", 100_000_000, 100, flows={11: -100_000_000},
                            status="Departed", event_date="2026-11-11"),
                ],
                "contracts": [
                    _contract("taylor-initial", "Advisor 70% through November 15", 7_000, ending="2026-11-15"),
                    _contract("taylor-updated", "Advisor 80% from November 16", 8_000, beginning="2026-11-16"),
                ],
                "expenses": [], "loan": _no_loan(),
            },
        ],
    }
