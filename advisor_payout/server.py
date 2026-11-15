"""Loopback-first demo server; calculation is pure and data is synthetic.

No Campfire credentials, outbound requests, mutations, or payment execution.
"""
from __future__ import annotations

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
from urllib.parse import urlparse

from . import __version__
from .engine import list_advisors, project
from .fixtures import demo_dataset
from .campfire import sample_erp_status, reconcile_cash_forecast

ROOT = Path(__file__).resolve().parents[1]
CORE_ROOT = ROOT
WEB = ROOT / "web"
PRESETS = {
    "baseline": {"label": "Current outlook", "description": "Hold the latest balances steady.", "scenario": {}},
    "growth": {"label": "New business", "description": "+3% market move and $2.5m in new assets.", "scenario": {"market_change_bps": 300, "net_flow_cents": 250_000_000}},
    "downside": {"label": "Market pullback", "description": "−5% market move and $1m in outflows.", "scenario": {"market_change_bps": -500, "net_flow_cents": -100_000_000}},
    "collections": {"label": "Slower collections", "description": "80% of fees collected by the payout date.", "scenario": {"collection_bps": 8000}},
}
MAX_BODY = 32_768
ALLOWED_SCENARIO = {"market_change_bps", "net_flow_cents", "collection_bps"}


def source_register() -> list:
    path = ROOT / "docs" / "SOURCE-REGISTER.json"
    if not path.is_file():
        return []
    data = json.loads(path.read_text())
    return data if isinstance(data, list) else data.get("sources", [])


def envelope(advisor_id: str, scenario: dict | None = None) -> dict:
    dataset = demo_dataset()
    forecast = project(dataset, advisor_id, scenario)
    baseline = project(dataset, advisor_id)
    erp = sample_erp_status(advisor_id)
    reconciliation = reconcile_cash_forecast(erp, forecast["summary"]["expected_collections_cents"],
        period_start=forecast["meta"]["period_start"], period_end=forecast["meta"]["period_end"], currency=forecast["meta"]["currency"],
        collection_through_date=forecast["meta"]["next_payout_date"])
    request = {"advisor_id": advisor_id, "scenario": forecast["scenario"]}
    payload = {"forecast": forecast, "baseline": baseline, "erp": erp, "reconciliation": reconciliation}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    return {
        **payload,
        "receipt": {"schema_version": "legume.advisor-payout/v1", "app_version": __version__, "sha256": hashlib.sha256(canonical).hexdigest(),
            "hash_scope": "All top-level fields except receipt; Python json.dumps(sort_keys=True, separators=(',', ':'), ensure_ascii=True), UTF-8",
            "input": request, "source_mode": "synthetic", "accounting_write": False},
    }


def bootstrap() -> dict:
    advisors = list_advisors(demo_dataset())
    return {"app_version": __version__, "advisors": advisors, "presets": PRESETS, "sources": source_register(), "initial": envelope(advisors[0]["id"])}


class Handler(BaseHTTPRequestHandler):
    server_version = "LegumeAdvisorPreview/0.1"

    def log_message(self, fmt: str, *args) -> None:
        # Do not log request bodies, cookies, authorization headers or financial inputs.
        if getattr(self.server, "verbose", False):
            super().log_message(fmt, *args)

    def _send(self, status: int, content: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(content)

    def _json(self, status: int, value: dict) -> None:
        self._send(status, json.dumps(value, ensure_ascii=False).encode(), "application/json; charset=utf-8")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            return self._json(200, {"status": "ok", "mode": "synthetic", "version": __version__, "campfire_connected": False})
        if path == "/api/bootstrap":
            return self._json(200, bootstrap())
        if path == "/api/sources":
            return self._json(200, {"sources": source_register()})
        # Deliberate file allowlist: never serve arbitrary repository or runtime paths.
        assets = {
            "/": (WEB / "index.html", "text/html; charset=utf-8"),
            "/index.html": (WEB / "index.html", "text/html; charset=utf-8"),
            "/app.js": (WEB / "app.js", "text/javascript; charset=utf-8"),
            "/styles.css": (WEB / "styles.css", "text/css; charset=utf-8"),
            "/shared/design-system/tokens.css": (CORE_ROOT / "shared/design-system/tokens.css", "text/css; charset=utf-8"),
            "/shared/design-system/primitives.css": (CORE_ROOT / "shared/design-system/primitives.css", "text/css; charset=utf-8"),
        }
        if path not in assets or not assets[path][0].is_file():
            return self._json(404, {"error": "Not found"})
        file, mime = assets[path]
        return self._send(200, file.read_bytes(), mime)

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/api/forecast":
            return self._json(404, {"error": "Not found"})
        if self.headers.get_content_type() != "application/json":
            return self._json(415, {"error": "Send application/json."})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                return self._json(413, {"error": "Request must be between 1 and 32768 bytes."})
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict) or set(body) - {"advisor_id", "scenario"}:
                raise ValueError("Use advisor_id and scenario only.")
            advisor_id, scenario = body.get("advisor_id"), body.get("scenario", {})
            if not isinstance(advisor_id, str) or advisor_id not in {a["id"] for a in list_advisors(demo_dataset())}:
                raise ValueError("Choose an available sample advisor.")
            if not isinstance(scenario, dict) or set(scenario) - ALLOWED_SCENARIO:
                raise ValueError("Use supported scenario fields only.")
            if any(type(v) is not int for v in scenario.values()):
                raise ValueError("Scenario fields must be integers.")
            return self._json(200, envelope(advisor_id, scenario))
        except (ValueError, TypeError, KeyError, OverflowError) as exc:
            return self._json(422, {"error": str(exc)[:240]})


def make_server(host: str = "127.0.0.1", port: int = 8766) -> ThreadingHTTPServer:
    return ThreadingHTTPServer((host, port), Handler)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the synthetic advisor payout preview.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8766, type=int)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    server = make_server(args.host, args.port)
    server.verbose = args.verbose
    print(f"Advisor payout preview: http://{args.host}:{server.server_port} (synthetic data; Campfire not connected)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
