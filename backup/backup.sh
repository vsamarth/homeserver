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

VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-vaultwarden_data}"
RESTIC_TAG="${RESTIC_TAG:-vaultwarden}"
CLEANUP_SUDO="${CLEANUP_SUDO:-sudo}"

if ! docker ps --format '{{.Names}}' | grep -q "^vaultwarden$"; then
    echo "❯❯ Vaultwarden is not running; proceeding with filesystem backup only."
else
    echo "❯❯ Creating a Vaultwarden database backup inside the container..."
    docker exec vaultwarden /vaultwarden backup

    echo "❯❯ Normalizing Vaultwarden database backup files inside the container..."
    LATEST_BACKUP=$(docker exec vaultwarden ls -1 /data/db_*.sqlite3 2>/dev/null | sort | tail -1)
    if [[ -n "$LATEST_BACKUP" ]]; then
        BACKUP_NAME=$(basename "$LATEST_BACKUP")
        docker exec vaultwarden mv -f "/data/$BACKUP_NAME" /data/db_backup.sqlite3
    fi
fi

echo "❯❯ Uploading Vaultwarden to restic..."
restic -r "$RESTIC_REPOSITORY" backup "$REPO_ROOT/$VAULTWARDEN_DATA_DIR/attachments" --tag "$RESTIC_TAG"
restic -r "$RESTIC_REPOSITORY" backup "$REPO_ROOT/$VAULTWARDEN_DATA_DIR/sends" --tag "$RESTIC_TAG"
restic -r "$RESTIC_REPOSITORY" backup "$REPO_ROOT/$VAULTWARDEN_DATA_DIR/rsa_key.pem" --tag "$RESTIC_TAG"
restic -r "$RESTIC_REPOSITORY" backup "$REPO_ROOT/$VAULTWARDEN_DATA_DIR/db_backup.sqlite3" --tag "$RESTIC_TAG"

echo "❯❯ Vaultwarden backup completed"

$CLEANUP_SUDO rm -f "$VAULTWARDEN_DATA_DIR/db_*.sqlite3"
