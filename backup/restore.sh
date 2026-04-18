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

VAULTWARDEN_SERVICE="${VAULTWARDEN_SERVICE:-vaultwarden}"
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-vaultwarden_data}"
VAULTWARDEN_RESTORE_DIR="${VAULTWARDEN_RESTORE_DIR:-vaultwarden_backup}"
SNAPSHOT_ID="${1:-latest}"

if [[ "$SNAPSHOT_ID" == "latest" ]]; then
    echo "❯❯ Restoring the latest snapshot..."
else
    echo "❯❯ Restoring snapshot: $SNAPSHOT_ID"
fi

if docker ps --format '{{.Names}}' | grep -q "^${VAULTWARDEN_SERVICE}$"; then
    echo "❯❯ Stopping Vaultwarden..."
    docker stop "$VAULTWARDEN_SERVICE"
else
    echo "❯❯ Vaultwarden is not running; restoring offline."
fi

RESTORE_DIR=$(mktemp -d)
trap "rm -rf $RESTORE_DIR" EXIT

echo "❯❯ Restoring from restic..."
restic -r "$RESTIC_REPOSITORY" restore "$SNAPSHOT_ID" --target "$RESTORE_DIR" --include "vaultwarden_data/attachments" --include "vaultwarden_data/sends" --include "vaultwarden_data/rsa_key.pem" --include "vaultwarden_data/db_backup.sqlite3"

echo "❯❯ Restoring to $VAULTWARDEN_RESTORE_DIR..."
if [[ -d "$VAULTWARDEN_RESTORE_DIR" ]]; then
    rm -rf "$VAULTWARDEN_RESTORE_DIR"
fi
mkdir -p "$VAULTWARDEN_RESTORE_DIR"
for item in attachments sends rsa_key.pem db_backup.sqlite3; do
    if [[ -e "$RESTORE_DIR/vaultwarden_data/$item" ]]; then
        cp -r "$RESTORE_DIR/vaultwarden_data/$item" "$VAULTWARDEN_RESTORE_DIR/"
    elif [[ -e "$RESTORE_DIR/$item" ]]; then
        cp -r "$RESTORE_DIR/$item" "$VAULTWARDEN_RESTORE_DIR/"
    fi
done

if docker ps -a --format '{{.Names}}' | grep -q "^${VAULTWARDEN_SERVICE}$"; then
    echo "❯❯ Starting Vaultwarden..."
    docker start "$VAULTWARDEN_SERVICE"
else
    echo "❯❯ Vaultwarden container does not exist; start the stack separately."
fi

echo "❯❯ Vaultwarden restore completed"