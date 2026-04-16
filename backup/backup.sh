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

VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-vaultwarden_data}"
VAULTWARDEN_ATTACHMENTS_DIR="attachments"
RESTIC_IMAGE="${RESTIC_IMAGE:-restic/restic:latest}"
RESTIC_TAG="${RESTIC_TAG:-vaultwarden}"

# if ! docker ps --format '{{.Names}}' | grep -q "^vaultwarden$"; then
#     echo "❯❯ Vaultwarden is not running; proceeding with filesystem backup only."
# else
#     echo "❯❯ Creating a Vaultwarden database backup inside the container..."
#     docker exec vaultwarden /vaultwarden backup
#
#     echo "❯❯ Normalizing Vaultwarden database backup files inside the container..."
#     LATEST_BACKUP=$(docker exec vaultwarden ls -1 /data/db_*.sqlite3 2>/dev/null | sort | tail -1)
#     if [[ -n "$LATEST_BACKUP" ]]; then
#         BACKUP_NAME=$(basename "$LATEST_BACKUP")
#         docker exec vaultwarden mv -f "/data/$BACKUP_NAME" /data/db_backup.sqlite3
#         docker exec vaultwarden rm -f /data/db_*.sqlite3
#     fi
# fi

echo "❯❯ Uploading Vaultwarden attachments to restic..."
docker run --rm \
    -v "$REPO_ROOT/$VAULTWARDEN_DATA_DIR/attachments:/source:ro" \
    -e RESTIC_REPOSITORY \
    -e RESTIC_PASSWORD \
    -e B2_ACCOUNT_ID \
    -e B2_ACCOUNT_KEY \
    "$RESTIC_IMAGE" backup /source --tag "$RESTIC_TAG"

echo "❯❯ Vaultwarden attachments backup completed"
