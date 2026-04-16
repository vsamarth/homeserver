#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"

if [[ ! -f .env ]]; then
    echo "Error: .env file not found"
    exit 1
fi

set -a
source .env
export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
set +a

required_vars=("RESTIC_REPOSITORY" "RESTIC_PASSWORD" "B2_ACCOUNT_ID" "B2_ACCOUNT_KEY")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "Error: $var is not set"
        exit 1
    fi
done

if ! command -v restic &> /dev/null; then
    echo "Error: restic is not installed"
    echo "Install with: apt install restic"
    exit 1
fi

echo "❯❯ Checking whether the restic repository is already initialized..."
if restic -r "$RESTIC_REPOSITORY" snapshots &>/dev/null; then
    echo "❯❯ Restic repository is already initialized"
    exit 0
fi

echo "❯❯ Initializing restic repository..."
restic -r "$RESTIC_REPOSITORY" init

echo "❯❯ Restic repository initialized"