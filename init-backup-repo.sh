#!/bin/bash
# Initialize the restic repository in Backblaze B2.

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

RESTIC_IMAGE="${RESTIC_IMAGE:-restic/restic:latest}"

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

print_info "Checking whether the restic repository is already initialized..."
if docker run --rm \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e B2_ACCOUNT_ID \
    -e B2_ACCOUNT_KEY \
    "$RESTIC_IMAGE" \
    snapshots >/dev/null 2>&1; then
    print_success "Restic repository is already initialized"
    exit 0
fi

print_info "Initializing restic repository..."
docker run --rm \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e B2_ACCOUNT_ID \
    -e B2_ACCOUNT_KEY \
    "$RESTIC_IMAGE" \
    init

print_success "Restic repository initialized"
