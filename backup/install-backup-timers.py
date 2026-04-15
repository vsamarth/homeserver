#!/usr/bin/env python3
"""Install and enable the Vaultwarden backup systemd timers."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from backup_common import require_command, require_file


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, text=True)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    os.chdir(script_dir)

    require_command("systemctl")
    use_sudo = os.geteuid() != 0
    if use_sudo:
        require_command("sudo")

    unit_files = [
        "vaultwarden-backup.service",
        "vaultwarden-backup.timer",
        "vaultwarden-prune.service",
        "vaultwarden-prune.timer",
    ]
    for unit_file in unit_files:
        require_file(unit_file)

    systemd_dir = Path("/etc/systemd/system")
    if not systemd_dir.is_dir():
        raise RuntimeError(f"Missing systemd directory: {systemd_dir}")

    print("❯❯ Installing Vaultwarden backup timers...")
    for unit_file in unit_files:
        source = script_dir / unit_file
        target = systemd_dir / unit_file
        if use_sudo:
            run(["sudo", "install", "-m", "0644", str(source), str(target)])
        else:
            shutil.copy2(source, target)

    systemctl_prefix = ["sudo"] if use_sudo else []
    run([*systemctl_prefix, "systemctl", "daemon-reload"])
    run([*systemctl_prefix, "systemctl", "enable", "--now", "vaultwarden-backup.timer", "vaultwarden-prune.timer"])

    print("❯❯ Vaultwarden backup timers installed and enabled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
