#!/usr/bin/env python3
"""Install two user login services; no passwords/tokens are stored in the plists."""
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
AGENTS = Path.home() / "Library/LaunchAgents"
LOGS = ROOT / ".runtime/hosting"
JOBS = {
    "com.beanlabs.savvy-proto.app": ["/bin/bash", str(ROOT / "deploy/start-device.sh")],
    "com.beanlabs.savvy-proto.tunnel": ["/opt/homebrew/bin/python3", str(ROOT / "deploy/run-tunnel.py")],
}


def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    AGENTS.mkdir(parents=True, exist_ok=True)
    for label, command in JOBS.items():
        path = AGENTS / f"{label}.plist"
        target = f"gui/{os.getuid()}/{label}"
        config = {
            "Label": label, "ProgramArguments": command,
            "WorkingDirectory": str(ROOT), "RunAtLoad": True, "KeepAlive": True,
            "ThrottleInterval": 30,
            "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"},
            "StandardOutPath": str(LOGS / f"{label}.out.log"),
            "StandardErrorPath": str(LOGS / f"{label}.err.log"),
        }
        if path.exists():
            previous = plistlib.loads(path.read_bytes())
            if previous.get("WorkingDirectory") != str(ROOT):
                raise RuntimeError(f"Refusing to replace unowned service {label}")
            subprocess.run(["launchctl", "bootout", target], capture_output=True)
        path.write_bytes(plistlib.dumps(config))
        path.chmod(0o600)
        subprocess.run(["plutil", "-lint", str(path)], check=True)
        subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(path)], check=True)
        print(f"Installed {label}")


if __name__ == "__main__":
    main()
