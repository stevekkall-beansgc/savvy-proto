"""Independent monetary references and contractual invariants for the demo."""

from copy import deepcopy
from datetime import date, timedelta
import json
import unittest

from advisor_payout.engine import project, list_advisors
from advisor_payout.fixtures import demo_dataset


def constant_clients(advisor, balances):
    for client, balance in zip(advisor["clients"], balances):
        for row in client["observations"]:
            row.update(opening_aum_cents=balance, aum_cents=balance,
                       market_change_cents=0, net_flow_cents=0)


class FinancialReferenceTests(unittest.TestCase):
    def setUp(self):
        self.dataset = demo_dataset()

    def test_simple_reference_is_independent_of_daily_cent_rounding(self):
        # $10m * 1% * 30/365 = $8,219.18; 80% = $6,575.34.
        constant_clients(self.dataset["advisors"][0], [600_000_000, 400_000_000])
        result = project(self.dataset, "advisor-alex")
        self.assertEqual(result["summary"]["projected_fees_cents"], 821_918)
        self.assertEqual(result["summary"]["estimated_payout_cents"], 657_534)
        self.assertEqual(sum(row["fee_cents"] for row in result["daily"]), 821_918)

    def test_expense_and_loan_reference(self):
        # $20m * .75% * 30/365 = 12,328.77; less 3,000; *75%;
        # less 600 => 6,396.58. Rounded 20% principal cap is 1,279.32.
        summary = project(self.dataset, "advisor-jordan")["summary"]
        expected = {"projected_fees_cents": 1_232_877, "advisor_entitlement_cents": 639_658,
                    "loan_repayment_cents": 127_932, "estimated_payout_cents": 511_726,
                    "loan_remaining_cents": 122_068}
        for key, value in expected.items():
            self.assertEqual(summary[key], value, key)

    def test_lower_collections_use_the_cash_waterfall_not_scaled_net_entitlement(self):
        # 80% collected = 9,863.02; fixed expenses stay 3,000 + 600;
        # 75% split gives 4,547.27 before loan; 909.45 repayment => 3,637.82.
        result = project(self.dataset, "advisor-jordan", {"collection_bps": 8_000})
        summary = result["summary"]
        self.assertEqual(summary["expected_collections_cents"], 986_302)
        self.assertEqual(summary["advisor_entitlement_cents"], 639_658)
        self.assertEqual(summary["estimated_payout_cents"], 363_782)
        self.assertEqual(summary["loan_repayment_cents"], 90_945)
        self.assertEqual(summary["loan_remaining_cents"], 159_055)

    def test_expense_before_vs_after_split_changes_the_burden(self):
        advisor = self.dataset["advisors"][0]
        constant_clients(advisor, [600_000_000, 400_000_000])
        baseline = project(self.dataset, advisor["id"])["summary"]["estimated_payout_cents"]
        advisor["expenses"] = [{"id": "cost", "label": "Synthetic cost", "amount_cents": 100_000, "treatment": "pre_share"}]
        before = project(self.dataset, advisor["id"])["summary"]["estimated_payout_cents"]
        advisor["expenses"][0]["treatment"] = "post_share"
        after = project(self.dataset, advisor["id"])["summary"]["estimated_payout_cents"]
        self.assertEqual(baseline - before, 80_000)
        self.assertEqual(baseline - after, 100_000)

    def test_effective_contract_boundary_has_an_independent_reference(self):
        # Each half-month earns $4,109.59. 70% => $2,876.71;
        # 80% => $3,287.67; sum $6,164.38 (segment rounding is explicit).
        advisor = self.dataset["advisors"][2]
        constant_clients(advisor, [1_000_000_000, 0, 0])
        advisor["default_collection_bps"] = 10_000
        result = project(self.dataset, advisor["id"])
        self.assertEqual([term["projected_fees_cents"] for term in result["contracts"]], [410_959, 410_959])
        self.assertEqual(result["summary"]["estimated_payout_cents"], 616_438)

    def test_loan_respects_balance_and_schedule_and_zero_cap(self):
        advisor = self.dataset["advisors"][1]
        advisor["loan"]["opening_balance_cents"] = 10_000
        summary = project(self.dataset, advisor["id"])["summary"]
        self.assertEqual(summary["loan_repayment_cents"], 10_000)
        self.assertEqual(summary["loan_remaining_cents"], 0)
        advisor["loan"]["opening_balance_cents"] = 250_000
        advisor["loan"]["scheduled_repayment_cents"] = 12_345
        self.assertEqual(project(self.dataset, advisor["id"])["summary"]["loan_repayment_cents"], 12_345)
        advisor["loan"]["repayment_cap_bps"] = 0
        self.assertEqual(project(self.dataset, advisor["id"])["summary"]["loan_repayment_cents"], 0)

    def test_no_collections_neither_forgive_costs_nor_repay_debt(self):
        result = project(self.dataset, "advisor-jordan", {"collection_bps": 0})
        summary = result["summary"]
        self.assertEqual(summary["estimated_payout_cents"], 0)
        self.assertEqual(summary["unapplied_deductions_cents"], 360_000)
        self.assertEqual(summary["loan_remaining_cents"], 250_000)
        self.assertEqual(summary["loan_repayment_cents"], 0)
        self.assertTrue(any("not forgiven" in warning for warning in result["warnings"]))


class ProjectionInvariantTests(unittest.TestCase):
    def setUp(self):
        self.dataset = demo_dataset()

    def test_future_scenario_never_rewrites_observations_or_earned_fees(self):
        for advisor in self.dataset["advisors"]:
            with self.subTest(advisor=advisor["id"]):
                baseline = project(self.dataset, advisor["id"])
                scenario = project(self.dataset, advisor["id"], {"market_change_bps": 777, "net_flow_cents": 10_000_000, "collection_bps": 8_000})
                self.assertEqual([r for r in baseline["daily"] if r["phase"] == "actual"],
                                 [r for r in scenario["daily"] if r["phase"] == "actual"])
                self.assertEqual(baseline["summary"]["earned_fees_cents"], scenario["summary"]["earned_fees_cents"])
                self.assertEqual(scenario["summary"]["baseline_payout_cents"], baseline["summary"]["estimated_payout_cents"])

    def test_one_time_market_move_precedes_flow_then_balances_hold(self):
        result = project(self.dataset, "advisor-jordan", {"market_change_bps": -1_000, "net_flow_cents": 100_000_000})
        future = [row for row in result["daily"] if row["phase"] == "projected"]
        self.assertEqual(future[0]["date"], "2026-11-14")
        self.assertEqual(future[0]["market_change_cents"], -200_000_000)
        self.assertEqual(future[0]["net_flow_cents"], 100_000_000)
        self.assertTrue(all(row["aum_cents"] == 1_900_000_000 for row in future))
        self.assertTrue(all(row["market_change_cents"] == row["net_flow_cents"] == 0 for row in future[1:]))

    def test_every_day_and_every_cash_waterfall_reconciles(self):
        for advisor in self.dataset["advisors"]:
            for scenario in ({}, {"market_change_bps": -2_000, "net_flow_cents": -5_000_000, "collection_bps": 4_000}):
                result = project(self.dataset, advisor["id"], scenario)
                for row in result["daily"]:
                    self.assertEqual(row["opening_aum_cents"] + row["market_change_cents"] + row["net_flow_cents"], row["aum_cents"])
                self.assertEqual(sum(row["fee_cents"] for row in result["daily"]), result["summary"]["projected_fees_cents"])
                self.assertEqual(sum(row["fee_cents"] for row in result["daily"] if row["phase"] == "actual"), result["summary"]["earned_fees_cents"])
                self.assertEqual(sum(row["amount_cents"] for row in result["waterfall"] if row["kind"] != "total"), result["summary"]["estimated_payout_cents"])
                self.assertEqual(result["summary"]["loan_remaining_cents"] + result["summary"]["loan_repayment_cents"], advisor["loan"]["opening_balance_cents"])

    def test_arrival_and_departure_are_flows_not_market_returns(self):
        daily = {row["date"]: row for row in project(self.dataset, "advisor-taylor")["daily"]}
        self.assertEqual(daily["2026-11-08"]["net_flow_cents"], 150_000_000)
        self.assertEqual(daily["2026-11-08"]["market_change_cents"], 0)
        self.assertEqual(daily["2026-11-11"]["net_flow_cents"], -100_000_000)
        self.assertEqual(daily["2026-11-11"]["market_change_cents"], 0)

    def test_tiny_balances_do_not_go_negative_from_separate_rounding(self):
        advisor = self.dataset["advisors"][0]
        constant_clients(advisor, [1, 1])
        result = project(self.dataset, advisor["id"], {"market_change_bps": -5_000, "net_flow_cents": -1})
        self.assertTrue(all(row["aum_cents"] == 0 for row in result["daily"] if row["phase"] == "projected"))

    def test_end_of_period_has_no_forecast_and_cannot_rewrite_assets(self):
        advisor = self.dataset["advisors"][1]
        self.dataset["as_of_date"] = "2026-11-30"
        for client in advisor["clients"]:
            last = client["observations"][-1]
            for day in range(14, 31):
                client["observations"].append(dict(last, date=f"2026-11-{day:02d}", market_change_cents=0, net_flow_cents=0))
        result = project(self.dataset, advisor["id"], {"market_change_bps": 500})
        self.assertTrue(all(row["phase"] == "actual" for row in result["daily"]))
        self.assertEqual(result["summary"]["projected_fees_cents"], result["summary"]["earned_fees_cents"])
        self.assertEqual(result["summary"]["delta_payout_cents"], 0)

    def test_result_is_deterministic_json_and_does_not_mutate_inputs(self):
        before = deepcopy(self.dataset)
        scenario = {"market_change_bps": 250, "collection_bps": 9_000}
        first = project(self.dataset, "advisor-jordan", scenario)
        self.assertEqual(first, project(self.dataset, "advisor-jordan", scenario))
        self.assertEqual(self.dataset, before)
        self.assertEqual(scenario, {"market_change_bps": 250, "collection_bps": 9_000})
        self.assertEqual(json.loads(json.dumps(first, allow_nan=False)), first)
        first["expenses"][0]["amount_cents"] = 0
        self.assertEqual(self.dataset, before)
        self.assertEqual(len(list_advisors(self.dataset)), 3)


class InvalidInputTests(unittest.TestCase):
    def setUp(self):
        self.dataset = demo_dataset()

    def test_missing_daily_data_is_not_silently_zero_filled(self):
        self.dataset["advisors"][0]["clients"][0]["observations"].pop(4)
        with self.assertRaisesRegex(ValueError, "Missing"):
            project(self.dataset, "advisor-alex")

    def test_aum_identity_and_continuity_are_required(self):
        row = self.dataset["advisors"][0]["clients"][0]["observations"][4]
        row["aum_cents"] += 1
        with self.assertRaisesRegex(ValueError, "reconcile"):
            project(self.dataset, "advisor-alex")
        row["opening_aum_cents"] += 1
        with self.assertRaisesRegex(ValueError, "discontinuous"):
            project(self.dataset, "advisor-alex")

    def test_contract_gap_and_overlap_fail(self):
        term = self.dataset["advisors"][2]["contracts"][1]
        for beginning in ("2026-11-15", "2026-11-17"):
            term["effective_from"] = beginning
            with self.assertRaisesRegex(ValueError, "Exactly one contract"):
                project(self.dataset, "advisor-taylor")

    def test_unsupported_parameters_and_non_integer_scenarios_fail(self):
        invalid = [{"interest_rate_bps": 1}, {"collection_bps": True}, {"market_change_bps": 1.2},
                   {"net_flow_cents": "100"}, {"collection_bps": 10_001}, {"market_change_bps": -10_001},
                   {"net_flow_cents": 2**53}]
        for scenario in invalid:
            with self.subTest(scenario=scenario), self.assertRaises(ValueError):
                project(self.dataset, "advisor-alex", scenario)

    def test_unknown_fee_basis_and_non_synthetic_data_fail(self):
        self.dataset["fee_basis"] = "prior_period_end_aum_advance"
        with self.assertRaisesRegex(ValueError, "Unsupported billing basis"):
            project(self.dataset, "advisor-alex")
        self.dataset = demo_dataset()
        self.dataset["synthetic"] = False
        with self.assertRaisesRegex(ValueError, "synthetic"):
            project(self.dataset, "advisor-alex")

    def test_outflows_cannot_exceed_remaining_assets(self):
        with self.assertRaisesRegex(ValueError, "outflows exceed"):
            project(self.dataset, "advisor-jordan", {"net_flow_cents": -2_000_000_001})

    def test_unsafe_json_integer_and_invalid_period_fail(self):
        self.dataset["advisors"][0]["clients"][0]["observations"][0]["aum_cents"] = 2**53
        with self.assertRaisesRegex(ValueError, "safe-integer"):
            project(self.dataset, "advisor-alex")
        self.dataset = demo_dataset()
        self.dataset["period_end"] = "2026-12-02"
        with self.assertRaisesRegex(ValueError, "1–31 days"):
            project(self.dataset, "advisor-alex")

    def test_loan_interest_is_not_silently_ignored(self):
        self.dataset["advisors"][1]["loan"]["interest_rate_bps"] = 300
        with self.assertRaisesRegex(ValueError, "Loan supports"):
            project(self.dataset, "advisor-jordan")


if __name__ == "__main__":
    unittest.main()
