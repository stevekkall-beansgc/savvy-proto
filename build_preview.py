"""Build a portable, network-free HTML preview from exact engine results.

The preview supports each advisor and four named scenarios. Arbitrary scenario
inputs remain available in the Python server; no finance logic is duplicated in JS.
"""
from pathlib import Path
import argparse
import json

from advisor_payout.server import CORE_ROOT, ROOT, WEB, PRESETS, bootstrap, envelope


def build(destination: Path) -> Path:
    data = bootstrap()
    snapshots = {a["id"]: {key: envelope(a["id"], preset["scenario"])
                 for key, preset in PRESETS.items()} for a in data["advisors"]}
    payload = json.dumps({"bootstrap": data, "snapshots": snapshots}, ensure_ascii=True, separators=(",", ":")).replace("</", "<\\/")
    html = (WEB / "index.html").read_text()
    for url, path in [
        ("/shared/design-system/tokens.css", CORE_ROOT / "shared/design-system/tokens.css"),
        ("/shared/design-system/primitives.css", CORE_ROOT / "shared/design-system/primitives.css"),
        ("/styles.css", WEB / "styles.css"),
    ]:
        html = html.replace(f'<link rel="stylesheet" href="{url}">', "<style>" + path.read_text() + "</style>")
    html = html.replace('<script src="/app.js" defer></script>', "")
    script = (WEB / "app.js").read_text().replace("</script", "<\\/script")
    html = html.replace("</body>", f"<script>window.__ADVISOR_PREVIEW__={payload};</script>\n<script>{script}</script>\n</body>")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(html, encoding="utf-8")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/advisor-payout-preview.html")
    args = parser.parse_args()
    print(build(args.output))
