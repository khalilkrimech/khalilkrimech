# OpenClaw Operations Guide

Production deployment on Hetzner VPS (Ubuntu 24.04).

## Quick Reference

| Action | Command |
|--------|---------|
| Start gateway | `docker compose up -d openclaw-gateway` |
| Stop gateway | `docker compose down` |
| View logs | `docker compose logs -f openclaw-gateway` |
| Health check | `docker compose exec openclaw-gateway node dist/index.js health` |
| Run CLI command | `docker compose --profile cli run --rm openclaw-cli <cmd>` |
| List devices | `docker compose --profile cli run --rm openclaw-cli devices list` |
| Approve device | `docker compose --profile cli run --rm openclaw-cli devices approve <ID>` |
| Add Telegram | `docker compose --profile cli run --rm openclaw-cli channels add --channel telegram --token "<TOKEN>"` |

## Initial Setup

```bash
# 1. Clone and enter the repo
git clone <repo-url> && cd khalilkrimech

# 2. Run the setup script
chmod +x setup.sh
./setup.sh

# 3. From your local machine, open an SSH tunnel
ssh -L 18789:127.0.0.1:18789 user@your-vps-ip

# 4. Open the dashboard
#    http://localhost:18789/
#    Paste the gateway token from .env into Settings
```

## Device Pairing (Fixing "1008: pairing required")

When you first open the dashboard in your browser, the gateway sees an unrecognized device.
The WebSocket connection will close with code 1008 (pairing required).

**Fix it from the CLI:**

```bash
# Step 1: List pending device requests
docker compose --profile cli run --rm openclaw-cli devices list

# Step 2: Approve the device by its request ID
docker compose --profile cli run --rm openclaw-cli devices approve <requestId>

# Step 3: Refresh your browser — the dashboard should now connect
```

## Understanding the Error Codes

### 1006 — Abnormal Closure

The WebSocket connection was dropped without a proper close handshake. Common causes:

| Cause | Fix |
|-------|-----|
| CLI container targeting `127.0.0.1` | Set `OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789` in docker-compose.yml (already configured) |
| Gateway not running | `docker compose up -d openclaw-gateway` |
| Token mismatch | Verify `.env` token matches what the dashboard is using |
| Gateway bind set to `loopback` | Change to `lan` in `.env` |

### 1008 — Policy Violation (Pairing Required)

The gateway recognized the connection but the device is not approved. See "Device Pairing" above.

## Networking Architecture

```
Your Laptop                     Hetzner VPS
┌──────────────┐     SSH       ┌─────────────────────────────────┐
│ Browser      │────tunnel────▶│ 127.0.0.1:18789                 │
│ localhost:   │               │      │                           │
│ 18789        │               │      ▼ (Docker port mapping)     │
└──────────────┘               │ ┌─────────────────────────┐     │
                               │ │ openclaw-gateway        │     │
                               │ │ 0.0.0.0:18789 (--bind   │     │
                               │ │ lan, inside container)  │     │
                               │ └────────┬────────────────┘     │
                               │          │ Docker DNS            │
                               │ ┌────────▼────────────────┐     │
                               │ │ openclaw-cli             │     │
                               │ │ ws://openclaw-gateway:   │     │
                               │ │ 18789                    │     │
                               │ └─────────────────────────┘     │
                               │                                  │
                               │ Telegram Bot API ◀── outbound    │
                               └─────────────────────────────────┘
```

**Key design decisions:**

1. **Port binding is `127.0.0.1` on the host** — the gateway is never publicly accessible. All access goes through SSH tunnel.

2. **Gateway `--bind lan` inside the container** — this is NOT the same as exposing to the internet. It binds to all interfaces *inside the container*, which is required for Docker's port mapping and inter-container DNS to work.

3. **CLI uses Docker service DNS** — `OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789` resolves through Docker's built-in DNS, not localhost.

4. **CLI runs in a `cli` profile** — it's not a long-running service. You invoke it on-demand with `docker compose --profile cli run --rm openclaw-cli <command>`.

## Telegram Bot Setup

```bash
# 1. Create a bot via @BotFather on Telegram
#    Copy the bot token

# 2. Add the channel
docker compose --profile cli run --rm openclaw-cli channels add \
  --channel telegram --token "YOUR_BOT_TOKEN"

# 3. Verify it's connected
docker compose logs -f openclaw-gateway | grep -i telegram
```

## Model Configuration (moonshot/kimi-k2.5)

After onboarding, configure your model provider. Edit the config:

```bash
# Open the config file
nano ~/.openclaw/config.json

# Or use the CLI
docker compose --profile cli run --rm openclaw-cli config set \
  providers.default.model "moonshot/kimi-k2.5"
```

## Maintenance

### Updating OpenClaw

```bash
# Pull latest source / image
git pull origin main
docker compose build openclaw-gateway

# Restart with zero downtime
docker compose up -d openclaw-gateway
```

### Backup

```bash
# Back up config and workspace
tar czf openclaw-backup-$(date +%Y%m%d).tar.gz \
  ~/.openclaw/ \
  docker-compose.yml \
  .env
```

### Log Rotation

Docker handles log rotation via its logging driver. To limit log size:

```bash
# Add to docker-compose.yml under openclaw-gateway:
#   logging:
#     driver: json-file
#     options:
#       max-size: "10m"
#       max-file: "3"
```

## Security Checklist

- [ ] Gateway token is a random 64-character hex string
- [ ] Port 18789 is bound to `127.0.0.1` only (not `0.0.0.0`)
- [ ] Dashboard access is through SSH tunnel only
- [ ] `.env` file is not committed to git
- [ ] VPS firewall blocks port 18789 from external access
- [ ] SSH key authentication is enabled (no password auth)
