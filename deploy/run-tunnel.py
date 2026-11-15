#!/usr/bin/env python3
"""Fetch the existing tunnel credential at runtime; never write it to disk or argv."""
import json
import os
from pathlib import Path
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
BEANLAUNCH = Path.home() / "beans/platform/beanlaunch/bin/bl"


def secret(name):
    # Read the existing recovery mirror; no new Secret Manager versions or stores.
    result = subprocess.run(
        ["/opt/homebrew/bin/bash", str(BEANLAUNCH), "secret:get", name, "--from", "cf"],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode or not result.stdout.strip():
        raise RuntimeError(f"Unable to retrieve existing credential {name}")
    return result.stdout.strip()


def main():
    config = json.loads((ROOT / "deploy/device-host.json").read_text())
    account = secret("shared__CLOUDFLARE_ACCOUNT_ID")
    token = secret("shared__CLOUDFLARE_API_TOKEN")
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/cfd_tunnel/{config['tunnel_id']}/token",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        result = json.load(response)
    if not result.get("success") or not isinstance(result.get("result"), str):
        raise RuntimeError("Unable to retrieve Savvy tunnel token")
    env = {**os.environ, "TUNNEL_TOKEN": result["result"], "TUNNEL_DISABLE_PATH_NORMALIZATION": "false"}
    os.execve("/opt/homebrew/bin/cloudflared", ["cloudflared", "tunnel", "--no-autoupdate", "run"], env)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # HTTP response bodies and credential subprocess output must not reach logs.
        print(f"Savvy tunnel startup failed ({type(error).__name__}); supervisor will retry.", flush=True)
        raise SystemExit(1)
