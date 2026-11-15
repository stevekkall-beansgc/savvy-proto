"""Boundary checks for the actual HTTP interface and portable artifact."""
import hashlib
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest

from advisor_payout.server import make_server, envelope, PRESETS
from advisor_payout.engine import list_advisors
from advisor_payout.fixtures import demo_dataset
from build_preview import build


class ServerBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server(port=0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def request(self, method, path, data=None, raw=None, content_type="application/json"):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        body = json.dumps(data).encode() if data is not None else raw
        connection.request(method, path, body=body, headers={"Content-Type":content_type})
        response = connection.getresponse()
        result = (response.status, dict(response.getheaders()), response.read())
        connection.close()
        return result

    def test_actual_http_calculation_and_scope(self):
        code, _, raw = self.request("POST", "/api/forecast", {"advisor_id":"advisor-jordan","scenario":{"collection_bps":8000}})
        self.assertEqual(code, 200)
        data = json.loads(raw)
        self.assertEqual(data["forecast"]["summary"]["estimated_payout_cents"], 363782)
        self.assertEqual(data["erp"]["connection"], "not_connected")
        self.assertEqual(data["reconciliation"]["final_variance_cents"], None)
        self.assertEqual(data["reconciliation"]["observed_cash_cents"], 650000)
        self.assertEqual(data["reconciliation"]["collection_through_date"], "2026-12-05")
        self.assertIsNotNone(data["reconciliation"]["gap_to_full_period_forecast_cents"])

    def test_invalid_or_unsupported_input_is_not_success(self):
        cases = [{"advisor_id":"unknown"}, {"advisor_id":"advisor-alex","scenario":{"collection_bps":True}},
                 {"advisor_id":"advisor-alex","scenario":{"market_change_bps":100000}},
                 {"advisor_id":"advisor-alex","scenario":{"tax_rate":10}},
                 {"advisor_id":"advisor-alex","campfire_token":"not-a-token"}]
        for body in cases:
            with self.subTest(body=body):
                self.assertEqual(self.request("POST", "/api/forecast", body)[0], 422)
        self.assertEqual(self.request("POST", "/api/forecast", raw=b"{")[0], 422)
        self.assertEqual(self.request("POST", "/api/forecast", raw=b"{}", content_type="text/plain")[0], 415)
        self.assertEqual(self.request("POST", "/api/forecast", raw=b"x"*32769)[0], 413)

    def test_repository_paths_are_not_exposed(self):
        for path in ["/../AGENTS.md", "/.env", "/advisor_payout/fixtures.py", "/api/campfire/connect"]:
            self.assertEqual(self.request("GET", path)[0], 404)
        self.assertEqual(self.request("POST", "/api/pay", {})[0], 404)
        code, headers, body = self.request("GET", "/")
        self.assertEqual(code, 200)
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        self.assertIn(b"Sample data", body)

    def test_export_receipt_covers_every_payload_field(self):
        a = envelope("advisor-alex")
        b = envelope("advisor-alex")
        self.assertEqual(a, b)
        receipt = a.pop("receipt")
        expected = hashlib.sha256(json.dumps(a, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest()
        self.assertEqual(receipt["sha256"], expected)
        self.assertNotEqual(receipt["sha256"], envelope("advisor-alex", {"collection_bps":8000})["receipt"]["sha256"])

    def test_all_advisor_presets_are_supported_and_coherent(self):
        for advisor in list_advisors(demo_dataset()):
            for preset in PRESETS.values():
                result = envelope(advisor["id"], preset["scenario"])
                self.assertEqual(result["reconciliation"]["advisor_id"], advisor["id"])
                self.assertGreaterEqual(result["forecast"]["summary"]["estimated_payout_cents"], 0)
                self.assertEqual(sum(x["amount_cents"] for x in result["forecast"]["waterfall"] if x["kind"] != "total"), result["forecast"]["summary"]["estimated_payout_cents"])

    def test_portable_preview_has_no_external_runtime_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            path = build(Path(directory) / "preview.html")
            html = path.read_text()
            self.assertIn("window.__ADVISOR_PREVIEW__=", html)
            self.assertNotIn('<script src=', html)
            self.assertNotIn('<link rel="stylesheet"', html)
            self.assertIn('"connection":"not_connected"', html)


if __name__ == "__main__":
    unittest.main()
