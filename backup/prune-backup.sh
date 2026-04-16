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

echo "❯❯ Pruning old Vaultwarden snapshots..."
restic -r "$RESTIC_REPOSITORY" forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune

echo "❯❯ Vaultwarden snapshot pruning completed"