#!/usr/bin/env python3
"""Initialize the restic repository in Backblaze B2."""

from __future__ import annotations

import os
from pathlib import Path

from backup_common import load_env_into_process, require_command, require_file, run


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    os.chdir(script_dir)

    require_file(".env")
    require_command("docker")

    load_env_into_process(".env")

    required_env = [
        "RESTIC_REPOSITORY",
        "RESTIC_PASSWORD",
        "B2_ACCOUNT_ID",
        "B2_ACCOUNT_KEY",
    ]
    missing = [name for name in required_env if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing required env vars in .env: {', '.join(missing)}")

    restic_image = os.environ.get("RESTIC_IMAGE", "restic/restic:latest")

    print("❯❯ Checking whether the restic repository is already initialized...")
    probe = run(
        [
            "docker",
            "run",
            "--rm",
            "-e",
            "RESTIC_REPOSITORY",
            "-e",
            "RESTIC_PASSWORD",
            "-e",
            "B2_ACCOUNT_ID",
            "-e",
            "B2_ACCOUNT_KEY",
            restic_image,
            "snapshots",
        ],
        check=False,
    )
    if probe.returncode == 0:
        print("❯❯ Restic repository is already initialized")
        return 0

    print("❯❯ Initializing restic repository...")
    run(
        [
            "docker",
            "run",
            "--rm",
            "-e",
            "RESTIC_REPOSITORY",
            "-e",
            "RESTIC_PASSWORD",
            "-e",
            "B2_ACCOUNT_ID",
            "-e",
            "B2_ACCOUNT_KEY",
            restic_image,
            "init",
        ]
    )

    print("❯❯ Restic repository initialized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
