"""Optional browser acceptance check. Requires Playwright and working Chromium.

Run from the experiment root: python3 browser_smoke.py
Use --chromium-path only when selecting an already installed browser.
This gate was blocked by the original executor; see docs/VALIDATION.md.
"""
import argparse
import hashlib
import json
from pathlib import Path
import threading

from advisor_payout.server import ROOT, make_server
from build_preview import build


def main():
    from playwright.sync_api import sync_playwright
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chromium-path")
    args = parser.parse_args()
    artifacts = ROOT / "artifacts"
    preview = build(artifacts / "advisor-payout-preview.html")
    server = make_server(port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    errors = []
    try:
        with sync_playwright() as p:
            options = {"headless": True}
            if args.chromium_path:
                options["executable_path"] = args.chromium_path
            browser = p.chromium.launch(**options)
            page = browser.new_page(viewport={"width":1440,"height":1100})
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(f"http://127.0.0.1:{server.server_port}")
            page.locator("#loading").wait_for(state="hidden")
            assert page.locator("#payout-value").inner_text() == "$6,618.19"
            page.screenshot(path=str(artifacts / "advisor-payout-desktop.png"), full_page=True)
            page.locator('[data-advisor="advisor-jordan"]').click()
            page.wait_for_function('document.querySelector("#payout-value").textContent === "$5,117.26"')
            page.locator('[data-preset="collections"]').click()
            page.wait_for_function('document.querySelector("#payout-value").textContent === "$3,637.82"')
            page.locator("#market-input").press("Home")
            for _ in range(7):
                page.locator("#market-input").press("ArrowRight")
            page.wait_for_function('document.querySelector("#scenario-label").textContent === "Custom scenario"')
            page.locator("#reset-button").click()
            page.wait_for_function('document.querySelector("#payout-value").textContent === "$5,117.26"')
            with page.expect_download() as info:
                page.locator("#export-button").click()
            export_path = artifacts / "browser-export.json"
            info.value.save_as(str(export_path))
            exported = json.loads(export_path.read_text())
            receipt = exported.pop("receipt")
            assert hashlib.sha256(json.dumps(exported, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest() == receipt["sha256"]
            page.locator('.nav-item[data-view="accounting"]').click()
            assert page.locator("#accounting-content").get_by_text("$6,500.00", exact=True).count() >= 1
            page.locator('.nav-item[data-view="research"]').click()
            assert page.locator("#source-list a").count() >= 20
            page.set_viewport_size({"width":390,"height":844})
            page.locator('.nav-item[data-view="forecast"]').click()
            assert not page.evaluate("document.documentElement.scrollWidth > innerWidth")
            page.screenshot(path=str(artifacts / "advisor-payout-mobile.png"), full_page=True)
            external = []
            page.on("request", lambda request: external.append(request.url) if request.url.startswith(("http:","https:")) else None)
            page.goto(preview.resolve().as_uri())
            page.locator("#loading").wait_for(state="hidden")
            assert not page.locator("#live-controls").is_visible()
            page.locator('[data-advisor="advisor-taylor"]').click()
            assert page.locator("#payout-value").inner_text() == "$4,975.17"
            page.locator('[data-preset="growth"]').click()
            assert page.locator("#scenario-label").inner_text() == "New business"
            assert not external, external
            assert not errors, errors
            browser.close()
        print("Browser acceptance passed: profiles, scenarios, custom controls, reset, export checksum, evidence, research, mobile overflow, offline preview.")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    main()
