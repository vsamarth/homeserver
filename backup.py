#!/usr/bin/env python3
"""Back up Vaultwarden data to a restic repository in Backblaze B2."""

from __future__ import annotations

import os
import re
from datetime import datetime
from pathlib import Path

from backup_common import (
    docker_container_running,
    docker_exec,
    load_env_into_process,
    require_command,
    require_file,
    run,
)


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

    vaultwarden_service = os.environ.get("VAULTWARDEN_SERVICE", "vaultwarden")
    vaultwarden_data_dir = Path(os.environ.get("VAULTWARDEN_DATA_DIR", "vaultwarden_data"))
    restic_image = os.environ.get("RESTIC_IMAGE", "restic/restic:latest")
    restic_tag = os.environ.get("RESTIC_TAG", "vaultwarden")
    backup_dir = Path(os.environ.get("BACKUP_DIR", "backups"))
    backup_name = os.environ.get(
        "BACKUP_NAME",
        f"vaultwarden-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz.age",
    )

    if not vaultwarden_data_dir.is_dir():
        raise RuntimeError(f"Missing Vaultwarden data directory: {vaultwarden_data_dir}")

    backup_dir.mkdir(parents=True, exist_ok=True)

    if docker_container_running(vaultwarden_service):
        print("❯❯ Creating a Vaultwarden database backup inside the container...")
        docker_exec(vaultwarden_service, ["/vaultwarden", "backup"])
    else:
        print("❯❯ Vaultwarden is not running; proceeding with filesystem backup only.")

    print("❯❯ Uploading Vaultwarden data to restic...")
    run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{script_dir / vaultwarden_data_dir}:/source:ro",
            "-e",
            "RESTIC_REPOSITORY",
            "-e",
            "RESTIC_PASSWORD",
            "-e",
            "B2_ACCOUNT_ID",
            "-e",
            "B2_ACCOUNT_KEY",
            restic_image,
            "backup",
            "/source",
            "--tag",
            restic_tag,
        ]
    )

    print("❯❯ Cleaning up generated Vaultwarden database backups...")
    if docker_container_running(vaultwarden_service):
        for backup_file in vaultwarden_data_dir.glob("db_*.sqlite3"):
            if re.fullmatch(r"db_\d{8}_\d{6}\.sqlite3", backup_file.name):
                docker_exec(vaultwarden_service, ["rm", "-f", f"/data/{backup_file.name}"])
    else:
        print("❯❯ Vaultwarden is not running; no generated database backup files to clean up.")

    print("❯❯ Vaultwarden backup completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
