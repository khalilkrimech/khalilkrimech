# OpenClaw Operations Guide

Production deployment on DigitalOcean Droplet (Ubuntu 24.04).
See [DEPLOY-GUIDE.md](DEPLOY-GUIDE.md) for initial DigitalOcean setup with $200 free credit.

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
| Run diagnostics | `./doctor.sh` |
| Auto-fix issues | `./doctor.sh --fix` |

## Initial Setup

```bash
# 1. Clone and enter the repo
git clone <repo-url> && cd khalilkrimech

# 2. Run the setup script
chmod +x setup.sh
./setup.sh

# 3. From your local machine, open an SSH tunnel
ssh -L 18789:127.0.0.1:18789 openclaw@your-droplet-ip

# 4. Open the dashboard
#    http://localhost:18789/
#    Paste the gateway token from .env into Settings
```

## Diagnostics & Auto-Fix

The `doctor.sh` script checks all critical aspects of the deployment:

```bash
# Diagnose only (no changes)
./doctor.sh

# Diagnose and auto-fix
./doctor.sh --fix
```

**What it checks:**
- Prerequisites (Docker, Compose)
- Config files (.env, openclaw.json, directories)
- Docker Compose correctness (port binding, profiles, health checks, log rotation)
- Container status (gateway running/healthy, stale CLI containers)
- Network security (127.0.0.1 binding, no public exposure)
- Resource usage (disk, memory, Docker disk)
- Recent error patterns in gateway logs

**What `--fix` can auto-repair:**
- Missing config/workspace directories
- Stale CLI containers (removes them)
- Stopped gateway (restarts it)
- Config file permissions (sets to 600)

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

## Common Deployment Issues

### CLI Container Exits Immediately (Exit Code 1)

**Symptom:** `docker ps -a` shows `openclaw-cli` with `Exited (1)`.

**Cause:** The CLI container was started without the `cli` profile, so it ran with no command and printed help text then exited.

**Fix:**
```bash
# Remove the stale container
docker rm openclaw-cli

# Always use --profile cli to run CLI commands:
docker compose --profile cli run --rm openclaw-cli doctor
```

The CLI is an on-demand tool, not a long-running service. It should never appear in `docker ps`.

### Ports Publicly Exposed (0.0.0.0)

**Symptom:** `docker ps` shows `0.0.0.0:18789->18789` instead of `127.0.0.1:18789->18789`.

**Cause:** The docker-compose.yml is using bare port mapping (`"18789:18789"`) instead of binding to localhost.

**Fix:**
```bash
# 1. Stop the current deployment
docker compose down

# 2. Ensure docker-compose.yml has the correct port binding:
#    - "127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}:18789"
#    (This is already correct in the repo — pull latest)

# 3. Redeploy
git pull origin main
docker compose up -d openclaw-gateway
```

**Why this matters:** With `0.0.0.0` binding, the gateway WebSocket is exposed to the entire internet. You'll see "closed before connect" log spam from scanners and bots.

### Gateway Token Mismatch

**Symptom:** Dashboard connects but immediately disconnects, or CLI commands fail with auth errors.

**Cause:** The token in `.env` (used by Docker) differs from the token in `~/.openclaw/openclaw.json`.

**Fix (automatic):**
```bash
# doctor.sh now detects and fixes token mismatches:
./doctor.sh --fix
```

**Fix (manual):**
```bash
# Check what token Docker is using
grep OPENCLAW_GATEWAY_TOKEN .env

# Check what the config file has
grep -A2 '"auth"' ~/.openclaw/openclaw.json

# If they differ, sync the .env token to the config file:
TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN .env | cut -d= -f2)
python3 -c "
import json
with open('$HOME/.openclaw/openclaw.json','r') as f: cfg=json.load(f)
cfg['gateway']['auth']['token']='$TOKEN'
with open('$HOME/.openclaw/openclaw.json','w') as f: json.dump(cfg,f,indent=2)
"

# Then restart:
docker compose restart openclaw-gateway
```

### "fetch failed" Errors in Gateway Logs

**Symptom:** `TypeError: fetch failed` in gateway logs.

**Cause:** The gateway couldn't reach an external API (e.g., moonshot API). Usually transient network issues.

**Fix:** These are non-fatal. The gateway continues running. If persistent:
```bash
# Check DNS resolution inside the container
docker compose exec openclaw-gateway nslookup api.moonshot.ai

# Check connectivity
docker compose exec openclaw-gateway wget -qO- https://api.moonshot.ai/v1/models || echo "unreachable"
```

### WebSocket "closed before connect" Spam

**Symptom:** Repeated `[ws] closed before connect` entries in logs from external IPs.

**Cause:** Internet scanners or bots probing the publicly exposed port.

**Fix:** Ensure ports are bound to `127.0.0.1`. See "Ports Publicly Exposed" above.

## Networking Architecture

```
Your Laptop                     DigitalOcean Droplet
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

## Stability Features

### Log Rotation

Docker log rotation is configured in `docker-compose.yml`:
- Max file size: 10MB
- Max files: 3 (total cap: 30MB)

### Resource Limits

The gateway container is capped at:
- Memory: 2GB (with 256MB reservation)
- CPU: 2 cores

These prevent a runaway process from killing the VPS.

### Health Check

The gateway runs `node dist/index.js health` every 30 seconds:
- Start period: 15s (grace period after boot)
- Timeout: 10s per check
- Retries: 3 (marks unhealthy after 3 consecutive failures)
- Restart policy: `unless-stopped` (Docker restarts unhealthy containers)

### Graceful Shutdown

`stop_grace_period: 30s` gives the gateway time to close WebSocket connections and flush logs before Docker sends SIGKILL.

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

### Redeploying from Scratch

If things are badly broken:

```bash
# 1. Stop and remove everything
docker compose down --remove-orphans

# 2. Remove stale containers
docker rm openclaw-cli openclaw-gateway 2>/dev/null

# 3. Pull latest config
git pull origin main

# 4. Restart
docker compose up -d openclaw-gateway

# 5. Verify
./doctor.sh
```

## Security Checklist

- [ ] Gateway token is a random 64-character hex string
- [ ] Port 18789 is bound to `127.0.0.1` only (not `0.0.0.0`)
- [ ] Dashboard access is through SSH tunnel only
- [ ] `.env` file is not committed to git
- [ ] VPS firewall blocks port 18789 from external access
- [ ] SSH key authentication is enabled (no password auth)
- [ ] Config file permissions are 600 (`chmod 600 ~/.openclaw/openclaw.json`)
