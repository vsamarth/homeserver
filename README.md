# Homeserver Compose Setup

This stack now uses a simple `.env` file for secrets.

## Setup

1. Fill in the real values in `.env` for:
   - `CLOUDFLARE_API_TOKEN`
   - `BESZEL_AGENT_TOKEN`
   - `BESZEL_AGENT_KEY`
   - `VAULTWARDEN_ADMIN_TOKEN`
2. Start the stack:
   ```bash
   ./start-services.sh
   ```

   If you prefer to run Compose directly:
   ```bash
   docker compose up -d
   ```
   The script also checks and applies a couple of Docker daemon defaults if they are missing, including `100m` log rotation and `live-restore`.

## Server Bootstrap

Run this as `root` on a fresh Ubuntu server to fetch and execute `setup-server.sh` in one step:

```bash
curl -fsSL https://raw.githubusercontent.com/vsamarth/homeserver/main/setup-server.sh | bash
```

The script uses `samarth` by default and will reuse the first key in `/root/.ssh/authorized_keys` when run non-interactively.

## Local Start

On a server where Docker is already installed and the `.env` file is present, use:

```bash
./start-services.sh
```

This script creates the bind-mounted data directories, checks Docker daemon settings, pulls images, and starts the Compose stack.

## Vaultwarden Backup

These scripts back up and restore only `vaultwarden_data/`.

1. Add the Backblaze and restic values to `.env`.

   The backup section in `.env` should include:
   - `RESTIC_REPOSITORY`
   - `RESTIC_PASSWORD`
   - `B2_ACCOUNT_ID`
   - `B2_ACCOUNT_KEY`
   - quote values that contain spaces or `$`

   Run the one-time initializer before the first backup:
   ```bash
   ./backup/init-backup-repo.py
   ```

2. Run a backup:
   ```bash
   ./backup/backup.py
   ```

3. Restore the latest snapshot:
   ```bash
   ./backup/restore.py
   ```

   Or restore a specific snapshot:
   ```bash
   ./backup/restore.py <snapshot-id>
   ```

The backup script runs Vaultwarden’s own database backup command first, then uploads `vaultwarden_data/` to restic in Backblaze B2.

## Scheduling

Use the systemd units to automate backups and pruning:

```bash
./backup/install-backup-timers.py
```

It will use `sudo` for the systemd install if you are not already root.

The backup timer runs daily. The prune timer runs weekly and keeps:
- 7 daily snapshots
- 4 weekly snapshots
- 12 monthly snapshots

## Notes

- `.env` should stay local and uncommitted.
- The old `secrets/` files are no longer used by Compose.
