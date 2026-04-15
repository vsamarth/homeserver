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
   docker compose up -d
   ```

## Server Bootstrap

Run this as `root` on a fresh Ubuntu server to fetch and execute `setup-server.sh` in one step:

```bash
curl -fsSL https://raw.githubusercontent.com/vsamarth/homeserver/main/setup-server.sh | bash
```

The script uses `samarth` by default and will reuse the first key in `/root/.ssh/authorized_keys` when run non-interactively.

## Notes

- `.env` should stay local and uncommitted.
- The old `secrets/` files are no longer used by Compose.
