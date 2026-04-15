#!/usr/bin/env python3
"""Restore Vaultwarden data from a restic repository in Backblaze B2."""

from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

from backup_common import (
    docker_container_exists,
    docker_container_running,
    docker_start,
    docker_stop,
    load_env_into_process,
    require_command,
    require_file,
    run,
)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    require_file(repo_root / ".env")
    require_command("docker")

    load_env_into_process(repo_root / ".env")

    required_env = [
        "RESTIC_REPOSITORY",
        "RESTIC_PASSWORD",
        "B2_ACCOUNT_ID",
        "B2_ACCOUNT_KEY",
    ]
    missing = [name for name in required_env if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing required env vars in .env: {', '.join(missing)}")

    vaultwarden_service = os.environ.get("VAULTWARDEN_SERVICE", "vaultwarden")
    vaultwarden_data_dir = Path(os.environ.get("VAULTWARDEN_DATA_DIR", "vaultwarden_data"))
    restic_image = os.environ.get("RESTIC_IMAGE", "restic/restic:latest")
    snapshot_id = sys.argv[1] if len(sys.argv) > 1 else "latest"
    vaultwarden_data_path = repo_root / vaultwarden_data_dir

    restore_root = Path(tempfile.mkdtemp(prefix="vaultwarden-restore-"))
    try:
        if docker_container_running(vaultwarden_service):
            print("❯❯ Stopping Vaultwarden...")
            docker_stop(vaultwarden_service)
        else:
            print("❯❯ Vaultwarden is not running; restoring offline.")

        if snapshot_id == "latest":
            print("❯❯ Restoring the latest snapshot...")
        else:
            print(f"❯❯ Restoring snapshot: {snapshot_id}")

        run(
            [
                "docker",
                "run",
                "--rm",
                "-v",
                f"{restore_root}:/restore",
                "-e",
                "RESTIC_REPOSITORY",
                "-e",
                "RESTIC_PASSWORD",
                "-e",
                "B2_ACCOUNT_ID",
                "-e",
                "B2_ACCOUNT_KEY",
                restic_image,
                "restore",
                snapshot_id,
                "--target",
                "/restore",
            ]
        )

        restored_source = restore_root / "source"
        if not restored_source.is_dir():
            raise RuntimeError(f"Restored data was not found at {restored_source}")

        print("❯❯ Replacing current Vaultwarden data directory...")
        if vaultwarden_data_path.exists():
            shutil.rmtree(vaultwarden_data_path)
        vaultwarden_data_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(restored_source, vaultwarden_data_path)

        if docker_container_exists(vaultwarden_service):
            print("❯❯ Starting Vaultwarden...")
            docker_start(vaultwarden_service)
        else:
            print("❯❯ Vaultwarden container does not exist; start the stack separately.")

        print("❯❯ Vaultwarden restore completed")
        return 0
    finally:
        shutil.rmtree(restore_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
