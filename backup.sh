#!/bin/bash
# Back up Vaultwarden data to a restic repository in Backblaze B2.

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

if [[ ! -d "$VAULTWARDEN_DATA_DIR" ]]; then
    print_error "Missing Vaultwarden data directory: $VAULTWARDEN_DATA_DIR"
    exit 1
fi

vaultwarden_container_id="$(docker compose ps -q "$VAULTWARDEN_SERVICE" 2>/dev/null || true)"
if [[ -n "$vaultwarden_container_id" ]] && \
   docker inspect -f '{{.State.Running}}' "$vaultwarden_container_id" 2>/dev/null | grep -qx true; then
    print_info "Creating a Vaultwarden database backup inside the container..."
    docker compose exec -T "$VAULTWARDEN_SERVICE" /vaultwarden backup
else
    print_info "Vaultwarden is not running; proceeding with filesystem backup only."
fi

print_info "Uploading Vaultwarden data to restic..."
docker run --rm \
    -v "$PWD/$VAULTWARDEN_DATA_DIR:/source:ro" \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e B2_ACCOUNT_ID \
    -e B2_ACCOUNT_KEY \
    "$RESTIC_IMAGE" \
    backup /source \
    --tag "$RESTIC_TAG"

print_success "Vaultwarden backup completed"
