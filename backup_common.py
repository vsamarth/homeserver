#!/usr/bin/env python3
"""Shared helpers for the Vaultwarden backup scripts."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path


def require_file(path: str | Path) -> None:
    if not Path(path).is_file():
        raise FileNotFoundError(f"Missing required file: {path}")


def require_command(cmd: str) -> None:
    if shutil.which(cmd) is None:
        raise FileNotFoundError(f"Missing required command: {cmd}")


def load_env_file(path: str | Path) -> dict[str, str]:
    env: dict[str, str] = {}
    content = Path(path).read_text(encoding="utf-8")

    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if not key:
            continue

        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in {"'", '"'}
        ):
            value = value[1:-1]
        else:
            # Drop inline comments only for unquoted values.
            value = re.split(r"\s+#", value, maxsplit=1)[0].rstrip()

        env[key] = value

    return env


def load_env_into_process(path: str | Path) -> dict[str, str]:
    env = load_env_file(path)
    os.environ.update(env)
    return env


def run(cmd: list[str], *, check: bool = True, capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture_output,
    )


def docker_container_exists(name: str) -> bool:
    result = subprocess.run(
        ["docker", "inspect", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def docker_container_running(name: str) -> bool:
    result = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Running}}", name],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return result.returncode == 0 and result.stdout.strip() == "true"


def docker_exec(container: str, args: list[str]) -> None:
    run(["docker", "exec", container, *args])


def docker_stop(container: str) -> None:
    run(["docker", "stop", container])


def docker_start(container: str) -> None:
    run(["docker", "start", container])

