# Homeserver Compose Setup

This stack now uses a simple `.env` file for secrets.

## Setup

1. Copy `.env.example` to `.env`.
2. Fill in the real values for:
   - `CLOUDFLARE_API_TOKEN`
   - `BESZEL_AGENT_TOKEN`
   - `BESZEL_AGENT_KEY`
   - `VAULTWARDEN_ADMIN_TOKEN`
3. Start the stack:
   ```bash
   docker compose up -d
   ```

## Notes

- `.env` is ignored by git.
- The old `secrets/` files are no longer used by Compose.
