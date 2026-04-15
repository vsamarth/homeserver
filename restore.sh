#!/bin/bash
# Restore Vaultwarden data from a restic repository in Backblaze B2.

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

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        print_error "Missing required file: $path"
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "Missing required command: $cmd"
        exit 1
    fi
}

VAULTWARDEN_SERVICE="${VAULTWARDEN_SERVICE:-vaultwarden}"
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-vaultwarden_data}"
RESTIC_IMAGE="${RESTIC_IMAGE:-restic/restic:latest}"
RESTIC_TAG="${RESTIC_TAG:-vaultwarden}"
SNAPSHOT_ID="${1:-latest}"

require_file ".env"
require_command docker

if ! docker compose version >/dev/null 2>&1; then
    print_error "Docker Compose plugin is not available."
    exit 1
fi

set -a
# shellcheck disable=SC1091
source ".env"
set +a

if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    print_error "RESTIC_REPOSITORY is not set in .env"
    exit 1
fi

if [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    print_error "RESTIC_PASSWORD is not set in .env"
    exit 1
fi

if [[ -z "${B2_ACCOUNT_ID:-}" || -z "${B2_ACCOUNT_KEY:-}" ]]; then
    print_error "B2_ACCOUNT_ID and B2_ACCOUNT_KEY must be set in .env"
    exit 1
fi

restore_root="$(mktemp -d)"
cleanup() {
    rm -rf "$restore_root"
}
trap cleanup EXIT

print_info "Stopping Vaultwarden..."
docker compose stop "$VAULTWARDEN_SERVICE"

if [[ "$SNAPSHOT_ID" == "latest" ]]; then
    print_info "Restoring the latest snapshot..."
else
    print_info "Restoring snapshot: $SNAPSHOT_ID"
fi

docker run --rm \
    -v "$restore_root:/restore" \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e B2_ACCOUNT_ID \
    -e B2_ACCOUNT_KEY \
    "$RESTIC_IMAGE" \
    restore "$SNAPSHOT_ID" \
    --target /restore

if [[ ! -d "$restore_root/source" ]]; then
    print_error "Restored data was not found at $restore_root/source"
    exit 1
fi

print_info "Replacing current Vaultwarden data directory..."
rm -rf "$VAULTWARDEN_DATA_DIR"
mkdir -p "$VAULTWARDEN_DATA_DIR"
cp -a "$restore_root/source/." "$VAULTWARDEN_DATA_DIR/"

print_info "Starting Vaultwarden..."
docker compose start "$VAULTWARDEN_SERVICE"

print_success "Vaultwarden restore completed"
