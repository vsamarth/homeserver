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
    restic_tag = os.environ.get("RESTIC_TAG", "vaultwarden")
    backup_dir = Path(os.environ.get("BACKUP_DIR", "backups"))
    backup_name = os.environ.get(
        "BACKUP_NAME",
        f"vaultwarden-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz.age",
    )

    vaultwarden_data_path = repo_root / vaultwarden_data_dir
    if not vaultwarden_data_path.is_dir():
        raise RuntimeError(f"Missing Vaultwarden data directory: {vaultwarden_data_dir}")

    backup_dir.mkdir(parents=True, exist_ok=True)

    if docker_container_running(vaultwarden_service):
        print("❯❯ Creating a Vaultwarden database backup inside the container...")
        docker_exec(vaultwarden_service, ["/vaultwarden", "backup"])
        print("❯❯ Normalizing Vaultwarden database backup files inside the container...")
        backup_pattern = re.compile(r"db_\d{8}_\d{6}\.sqlite3$")
        backup_files = sorted(
            (file for file in vaultwarden_data_dir.glob("db_*.sqlite3") if backup_pattern.fullmatch(file.name)),
            key=lambda file: file.name,
        )
        if backup_files:
            latest_backup = backup_files[-1]
            docker_exec(vaultwarden_service, ["mv", "-f", f"/data/{latest_backup.name}", "/data/db_backup.sqlite3"])
            for stale_backup in backup_files[:-1]:
                docker_exec(vaultwarden_service, ["rm", "-f", f"/data/{stale_backup.name}"])
    else:
        print("❯❯ Vaultwarden is not running; proceeding with filesystem backup only.")

    print("❯❯ Uploading Vaultwarden data to restic...")
    run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{vaultwarden_data_path}:/source:ro",
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

    print("❯❯ Vaultwarden backup completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
