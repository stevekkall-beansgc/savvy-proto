"""Financial and mapping boundaries for the offline Campfire-shaped fixture."""

from copy import deepcopy
from decimal import Decimal
import json
import unittest

from advisor_payout.campfire import (
    CampfireError,
    load_sample_snapshot,
    normalize_invoice_payments,
    plan_read_requests,
    reconcile_cash_forecast,
    sample_erp_status,
    summarize_snapshot,
)


class CampfireBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.sample = load_sample_snapshot()
        self.mapping = {str(row["invoice_id"]): row["advisor_id"] for row in self.sample["invoice_advisor_mappings"]}

    def normalize(self, records, **kwargs):
        return normalize_invoice_payments(records, self.mapping, cash_payment_types=["SYNTHETIC_CASH"], **kwargs)

    def compare(self, status, amount=827274, **overrides):
        args = {"period_start": "2026-11-01", "period_end": "2026-11-30", "currency": "USD", "collection_through_date": "2026-12-05"}
        args.update(overrides)
        return reconcile_cash_forecast(status, amount, **args)

    def test_cash_credits_and_repeated_delivery_remain_distinct(self):
        status = sample_erp_status("advisor-alex")
        self.assertEqual(status["summary"]["cash_collected_cents"], 350000)
        self.assertEqual(status["summary"]["credits_applied_cents"], 50000)
        self.assertEqual(status["summary"]["invoiced_cents"], 700000)
        self.assertEqual(status["summary"]["outstanding_invoice_cents"], 300000)
        self.assertEqual(status["summary"]["duplicate_observations_ignored"], 1)
        self.assertEqual(len(status["payments"]), 2)
        self.assertEqual(status["source_mode"], "synthetic")
        self.assertEqual(status["connection"], "not_connected")
        json.dumps(status)  # No Decimal, datetime or credential objects leak into the UI contract.

    def test_later_void_removes_cash_and_keeps_superseded_source_evidence(self):
        status = sample_erp_status("advisor-jordan")
        self.assertEqual(status["summary"]["cash_collected_cents"], 650000)
        self.assertEqual(status["summary"]["voided_or_reversed_cents"], 200000)
        self.assertEqual(status["summary"]["superseded_versions_retained"], 1)
        self.assertEqual(len(status["payments"]), 2)
        old_and_new = [row for row in status["payment_versions"] if row["id"] == "2202"]
        self.assertEqual([row["state"] for row in old_and_new], ["active", "voided_or_reversed"])
        self.assertFalse(next(row for row in status["payments"] if row["id"] == "2202")["included_in_observed_totals"])

    def test_source_arrival_order_cannot_change_cash(self):
        original = summarize_snapshot(self.sample, "advisor-jordan")
        self.sample["invoice_payments"].reverse()
        reversed_input = summarize_snapshot(self.sample, "advisor-jordan")
        self.assertEqual(original, reversed_input)

    def test_conflicting_facts_at_the_same_revision_are_rejected(self):
        original = self.sample["invoice_payments"][0]
        changed = {**original, "amount": Decimal("3501.00")}
        with self.assertRaisesRegex(CampfireError, "conflicting source facts"):
            self.normalize([original, changed])

    def test_payment_id_cannot_move_to_another_advisor_invoice(self):
        original = self.sample["invoice_payments"][0]
        changed = {**original, "invoice_id": 1102, "last_modified_at": "2026-11-12T12:00:00Z"}
        with self.assertRaisesRegex(CampfireError, "changed its mapped scope"):
            self.normalize([original, changed])

    def test_unknown_payment_types_are_not_cash_without_explicit_policy(self):
        records = [self.sample["invoice_payments"][0]]
        result = normalize_invoice_payments(records, self.mapping)
        self.assertEqual(result["payments"][0]["classification"], "unclassified")
        self.sample["cash_payment_types"] = []
        status = summarize_snapshot(self.sample, "advisor-alex")
        self.assertEqual(status["summary"]["cash_collected_cents"], 0)
        self.assertEqual(status["summary"]["unclassified_payments_cents"], 350000)
        self.assertFalse(status["summary"]["cash_classification_complete"])
        comparison = self.compare(status)
        self.assertIsNone(comparison["gap_to_full_period_forecast_cents"])
        self.assertEqual(comparison["status"], "classification_incomplete")

    def test_credit_memo_cannot_be_reclassified_as_cash(self):
        with self.assertRaisesRegex(CampfireError, "cannot be classified as cash"):
            normalize_invoice_payments([], self.mapping, cash_payment_types=["CREDIT_MEMO"])

    def test_missing_and_ambiguous_invoice_mapping_are_errors(self):
        self.sample["invoice_advisor_mappings"].pop(0)
        with self.assertRaisesRegex(CampfireError, "no reviewed advisor mapping"):
            summarize_snapshot(self.sample, "advisor-alex")
        self.sample = load_sample_snapshot()
        self.sample["invoice_advisor_mappings"].append(deepcopy(self.sample["invoice_advisor_mappings"][0]))
        with self.assertRaisesRegex(CampfireError, "more than one advisor mapping"):
            summarize_snapshot(self.sample, "advisor-alex")

    def test_client_identity_is_checked_before_mapping_an_invoice(self):
        self.sample["invoices"][0]["client"] = 99999
        with self.assertRaisesRegex(CampfireError, "client does not match"):
            summarize_snapshot(self.sample, "advisor-alex")

    def test_scope_is_advisor_specific(self):
        status = sample_erp_status("advisor-taylor")
        self.assertEqual(status["summary"]["cash_collected_cents"], 300000)
        self.assertEqual(status["summary"]["credits_applied_cents"], 50000)
        self.assertTrue(all(row["advisor_id"] == "advisor-taylor" for row in status["payments"]))
        self.assertTrue(all(row["advisor_id"] == "advisor-taylor" for row in status["payment_versions"]))
        with self.assertRaisesRegex(CampfireError, "unknown advisor"):
            sample_erp_status("someone-else")

    def test_amounts_are_exact_and_currency_is_not_silently_converted(self):
        record = self.sample["invoice_payments"][0]
        for bad_amount in (1.25, True, Decimal("1.001"), Decimal("1.00000000000000000000000000000001"), Decimal("NaN"), Decimal("-1.00")):
            with self.subTest(amount=bad_amount), self.assertRaises(CampfireError):
                self.normalize([{**record, "amount": bad_amount}])
        exact = self.normalize([{**record, "amount": Decimal("0.29")}])
        self.assertEqual(exact["payments"][0]["amount_cents"], 29)
        with self.assertRaisesRegex(CampfireError, "USD only"):
            self.normalize([{**record, "currency": "EUR"}])

    def test_void_state_and_source_cutoff_cannot_be_inferred(self):
        record = dict(self.sample["invoice_payments"][0])
        del record["voided_date"]
        with self.assertRaisesRegex(CampfireError, "missing voided_date"):
            self.normalize([record])
        self.sample["invoice_payments"][0]["last_modified_at"] = "2026-12-01T12:00:00Z"
        with self.assertRaisesRegex(CampfireError, "beyond its stated cutoff"):
            summarize_snapshot(self.sample, "advisor-alex")

    def test_invoice_void_is_not_a_cash_reversal(self):
        self.sample["invoices"][0]["voided_date"] = "2026-11-11"
        status = summarize_snapshot(self.sample, "advisor-alex")
        self.assertEqual(status["summary"]["cash_collected_cents"], 350000)
        self.assertEqual(status["summary"]["invoiced_cents"], 0)
        self.assertTrue(status["summary"]["allocation_review_required"])
        self.assertTrue(all(row["allocation_status"] == "inactive_invoice_requires_review" for row in status["payments"]))
        comparison = self.compare(status)
        self.assertIsNone(comparison["gap_to_full_period_forecast_cents"])
        self.assertEqual(comparison["status"], "allocation_review_required")

    def test_reconciliation_reports_progress_not_final_variance(self):
        comparison = self.compare(sample_erp_status("advisor-alex"))
        self.assertEqual(comparison["observed_cash_cents"], 350000)
        self.assertEqual(comparison["gap_to_full_period_forecast_cents"], 477274)
        self.assertIsNone(comparison["final_variance_cents"])
        self.assertFalse(comparison["posting_enabled"])
        self.assertEqual(comparison["comparison"], "observed_to_date_vs_forecast_collection_target")
        self.assertEqual(comparison["collection_through_date"], "2026-12-05")
        for overrides in ({"currency": "EUR"}, {"period_end": "2026-12-31"}):
            with self.subTest(overrides=overrides), self.assertRaisesRegex(CampfireError, "scopes do not match"):
                self.compare(sample_erp_status("advisor-alex"), **overrides)

    def test_missing_or_past_collection_horizon_prevents_a_complete_comparison(self):
        status = sample_erp_status("advisor-alex")
        comparison = self.compare(status, collection_through_date=None)
        self.assertIsNone(comparison["gap_to_full_period_forecast_cents"])
        self.assertEqual(comparison["status"], "collection_horizon_required")
        with self.assertRaisesRegex(CampfireError, "cannot precede"):
            self.compare(status, collection_through_date="2026-11-01")

    def test_non_synthetic_snapshot_is_outside_this_prototype_boundary(self):
        self.sample["source_mode"] = "live"
        with self.assertRaisesRegex(CampfireError, "synthetic snapshot contract only"):
            summarize_snapshot(self.sample, "advisor-alex")

    def test_documented_read_plan_has_no_email_export_or_write(self):
        plan = plan_read_requests("2026-11-12T12:30:00-05:00")
        self.assertFalse(plan["network_execution"])
        self.assertEqual(plan["connection"], "not_connected")
        self.assertEqual({row["method"] for row in plan["requests"]}, {"GET"})
        invoices, payments = plan["requests"]
        self.assertEqual(invoices["path"], "/coa/api/v1/invoice")
        self.assertEqual(payments["path"], "/coa/api/v1/invoice-payments")
        self.assertEqual(payments["params"]["last_modified_at__gte"], "2026-11-12T17:30:00Z")
        self.assertEqual(payments["params"]["cursor"], "")
        for request in plan["requests"]:
            self.assertNotIn("download", request["params"])
            self.assertNotIn("voided", request["params"])
        self.assertNotIn("last_modified_at__gte", invoices["params"])
        for invalid in ("2026-02-30", "2026-11-12T12:30:00", "https://evil.example", 1):
            with self.subTest(since=invalid), self.assertRaises(CampfireError):
                plan_read_requests(invalid)


if __name__ == "__main__":
    unittest.main()
