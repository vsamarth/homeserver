#!/bin/bash
# Start the homeserver Compose stack from the repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}❯❯${NC} $1"
}

print_info() {
    echo -e "${BLUE}❯❯${NC} $1"
}

print_error() {
    echo -e "${RED}❯❯${NC} $1" >&2
}

run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [[ ! -f .env ]]; then
    print_error "Missing .env"
    print_error "Copy your real secrets into ./.env before starting the stack."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker is not installed or not on PATH."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    print_error "Docker Compose plugin is not available."
    exit 1
fi

configure_docker_daemon() {
    local daemon_file="/etc/docker/daemon.json"
    local tmp_file
    tmp_file="$(mktemp)"

    print_info "Checking Docker daemon settings..."
    if python3 - "$daemon_file" <<'PY' >"$tmp_file"
import json
import os
import sys

daemon_file = sys.argv[1]

defaults = {
    "live-restore": True,
    "log-driver": "json-file",
    "log-opts": {
        "max-file": "3",
        "max-size": "100m",
    },
}

config = {}
if os.path.exists(daemon_file):
    with open(daemon_file, "r", encoding="utf-8") as handle:
        content = handle.read().strip()
        if content:
            config = json.loads(content)

changed = False

if config.get("live-restore") is not True:
    config["live-restore"] = True
    changed = True

if config.get("log-driver") != "json-file":
    config["log-driver"] = "json-file"
    changed = True

log_opts = config.get("log-opts")
if not isinstance(log_opts, dict):
    config["log-opts"] = dict(defaults["log-opts"])
    changed = True
else:
    for key, value in defaults["log-opts"].items():
        if log_opts.get(key) != value:
            log_opts[key] = value
            changed = True

if changed:
    json.dump(config, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    sys.exit(0)

sys.exit(3)
PY
    then
        local backup_file="${daemon_file}.bak.$(date +%Y%m%d%H%M%S)"
        if [[ -f "$daemon_file" ]]; then
            run_as_root cp "$daemon_file" "$backup_file"
            print_info "Backed up existing Docker config to $backup_file"
        fi

        run_as_root install -m 0644 "$tmp_file" "$daemon_file"
        print_info "Applied Docker daemon defaults"
        print_info "Restarting Docker to load new settings..."
        run_as_root systemctl restart docker
    else
        local status=$?
        if [[ $status -eq 3 ]]; then
            print_success "Docker daemon settings already include the recommended defaults"
        else
            print_error "Failed to inspect or update /etc/docker/daemon.json"
            rm -f "$tmp_file"
            exit 1
        fi
    fi

    rm -f "$tmp_file"
}

configure_docker_daemon

mkdir -p \
    caddy/data \
    caddy/config \
    beszel_data \
    beszel_socket \
    beszel_agent_data \
    vaultwarden_data

print_info "Pulling images..."
docker compose pull

print_info "Starting services..."
docker compose up -d

print_info "Waiting for container status..."
docker compose ps

print_success "Homeserver stack started"
