#!/usr/bin/env bash
# OpenClaw Doctor — Diagnose and fix common deployment issues
#
# Usage:
#   ./doctor.sh          # Diagnose only
#   ./doctor.sh --fix    # Diagnose and auto-fix what we can

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
FIX_MODE=false
ISSUES=0
FIXED=0

[[ "${1:-}" == "--fix" ]] && FIX_MODE=true

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; ((ISSUES++)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; ((ISSUES++)); }
info() { echo -e "  ${CYAN}INFO${NC}  $*"; }
fix()  { echo -e "  ${GREEN}FIX ${NC}  $*"; ((FIXED++)); }

echo ""
echo "OpenClaw Doctor"
echo "==============="
echo ""

# ─── 1. Prerequisites ────────────────────────────────────────────────
echo "Prerequisites"
echo "─────────────"

if command -v docker >/dev/null 2>&1; then
  pass "Docker is installed"
else
  fail "Docker is not installed"
fi

if docker compose version >/dev/null 2>&1; then
  pass "Docker Compose v2 is available"
else
  fail "Docker Compose v2 is not available"
fi

echo ""

# ─── 2. Configuration Files ──────────────────────────────────────────
echo "Configuration"
echo "─────────────"

if [[ -f "$COMPOSE_FILE" ]]; then
  pass "docker-compose.yml exists"
else
  fail "docker-compose.yml is missing"
fi

if [[ -f "$ENV_FILE" ]]; then
  pass ".env file exists"
  # Source it for later checks
  set -a
  source "$ENV_FILE"
  set +a
else
  fail ".env file is missing (run ./setup.sh or copy .env.example)"
fi

if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  TOKEN_LEN=${#OPENCLAW_GATEWAY_TOKEN}
  if (( TOKEN_LEN >= 48 )); then
    pass "Gateway token is set (${TOKEN_LEN} chars)"
  else
    warn "Gateway token is short (${TOKEN_LEN} chars, recommend 64)"
  fi
else
  fail "OPENCLAW_GATEWAY_TOKEN is empty"
fi

# Check token consistency between .env and openclaw.json
OPENCLAW_JSON="${CONFIG_DIR:-$HOME/.openclaw}/openclaw.json"
if [[ -f "$OPENCLAW_JSON" ]] && [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  JSON_TOKEN=$(python3 -c "
import json, sys
try:
  with open('$OPENCLAW_JSON') as f: cfg = json.load(f)
  print(cfg.get('gateway',{}).get('auth',{}).get('token',''))
except: pass
" 2>/dev/null)
  if [[ -n "$JSON_TOKEN" ]]; then
    if [[ "$JSON_TOKEN" == "$OPENCLAW_GATEWAY_TOKEN" ]]; then
      pass "Token in .env matches openclaw.json"
    else
      fail "Token MISMATCH: .env and openclaw.json have different tokens"
      info "The .env token (injected by Docker) takes precedence at runtime."
      info "Clients reading openclaw.json directly will fail to authenticate."
      if $FIX_MODE; then
        python3 -c "
import json
with open('$OPENCLAW_JSON','r') as f: cfg = json.load(f)
cfg.setdefault('gateway',{}).setdefault('auth',{})['token'] = '$OPENCLAW_GATEWAY_TOKEN'
with open('$OPENCLAW_JSON','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null && fix "Synced .env token → openclaw.json" || fail "Could not sync token to openclaw.json"
      fi
    fi
  else
    info "Could not read token from openclaw.json (file may not have gateway.auth.token yet)"
  fi
elif [[ ! -f "$OPENCLAW_JSON" ]]; then
  info "openclaw.json not found yet (will be created on first onboarding)"
fi

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
if [[ -d "$CONFIG_DIR" ]]; then
  pass "Config directory exists: $CONFIG_DIR"
else
  warn "Config directory missing: $CONFIG_DIR"
  if $FIX_MODE; then
    mkdir -p "$CONFIG_DIR"
    fix "Created $CONFIG_DIR"
  fi
fi

WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
if [[ -d "$WORKSPACE_DIR" ]]; then
  pass "Workspace directory exists: $WORKSPACE_DIR"
else
  warn "Workspace directory missing: $WORKSPACE_DIR"
  if $FIX_MODE; then
    mkdir -p "$WORKSPACE_DIR"
    fix "Created $WORKSPACE_DIR"
  fi
fi

echo ""

# ─── 3. Docker Compose Validation ────────────────────────────────────
echo "Compose File"
echo "────────────"

if [[ -f "$COMPOSE_FILE" ]]; then
  # Check port binding — must be 127.0.0.1, never 0.0.0.0
  if grep -q '127\.0\.0\.1.*18789' "$COMPOSE_FILE"; then
    pass "Port 18789 bound to 127.0.0.1 (secure)"
  elif grep -q '0\.0\.0\.0.*18789' "$COMPOSE_FILE" || grep -qE '^\s+-\s+"?18789' "$COMPOSE_FILE"; then
    fail "Port 18789 is publicly exposed (0.0.0.0)!"
    info "Fix: change port mapping to '127.0.0.1:\${OPENCLAW_GATEWAY_PORT:-18789}:18789'"
  fi

  # Check CLI uses profiles (not a long-running service)
  if grep -A5 'openclaw-cli' "$COMPOSE_FILE" | grep -q 'profiles'; then
    pass "CLI container uses Docker profile (on-demand only)"
  else
    warn "CLI container has no profile — it will start and exit immediately"
    info "Fix: add 'profiles: [cli]' to the openclaw-cli service"
  fi

  # Check healthcheck exists
  if grep -q 'healthcheck' "$COMPOSE_FILE"; then
    pass "Health check is configured"
  else
    warn "No health check configured for the gateway"
  fi

  # Check log rotation
  if grep -q 'max-size' "$COMPOSE_FILE"; then
    pass "Log rotation is configured"
  else
    warn "No log rotation — logs will grow unbounded"
  fi
fi

echo ""

# ─── 4. Container Status ─────────────────────────────────────────────
echo "Containers"
echo "──────────"

GW_STATE=$(docker inspect --format='{{.State.Status}}' openclaw-gateway 2>/dev/null || echo "missing")
GW_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "unknown")

case "$GW_STATE" in
  running)
    if [[ "$GW_HEALTH" == "healthy" ]]; then
      pass "Gateway is running and healthy"
    elif [[ "$GW_HEALTH" == "starting" ]]; then
      info "Gateway is running (health check starting up)"
    else
      warn "Gateway is running but health check reports: $GW_HEALTH"
    fi
    ;;
  exited)
    fail "Gateway has exited"
    EXIT_CODE=$(docker inspect --format='{{.State.ExitCode}}' openclaw-gateway 2>/dev/null || echo "?")
    info "Exit code: $EXIT_CODE"
    info "Last logs: docker logs --tail 20 openclaw-gateway"
    if $FIX_MODE; then
      info "Attempting restart..."
      if (cd "$ROOT_DIR" && docker compose up -d openclaw-gateway); then
        fix "Gateway restarted"
        # Wait for health check to pass
        info "Waiting for gateway to become healthy (up to 60s)..."
        for i in $(seq 1 12); do
          sleep 5
          HEALTH=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "unknown")
          if [[ "$HEALTH" == "healthy" ]]; then
            pass "Gateway is healthy after restart"
            break
          elif [[ "$i" -eq 12 ]]; then
            warn "Gateway did not become healthy within 60s (current: $HEALTH)"
            info "Check logs: docker logs --tail 30 openclaw-gateway"
          fi
        done
      else
        fail "Could not restart gateway"
      fi
    fi
    ;;
  missing)
    warn "Gateway container does not exist (not started yet)"
    if $FIX_MODE; then
      info "Starting gateway..."
      if (cd "$ROOT_DIR" && docker compose up -d openclaw-gateway); then
        fix "Gateway started"
        info "Waiting for gateway to become healthy (up to 60s)..."
        for i in $(seq 1 12); do
          sleep 5
          HEALTH=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "unknown")
          if [[ "$HEALTH" == "healthy" ]]; then
            pass "Gateway is healthy after start"
            break
          elif [[ "$i" -eq 12 ]]; then
            warn "Gateway did not become healthy within 60s (current: $HEALTH)"
            info "Check logs: docker logs --tail 30 openclaw-gateway"
          fi
        done
      else
        fail "Could not start gateway"
      fi
    fi
    ;;
  *)
    warn "Gateway container state: $GW_STATE"
    ;;
esac

# Check for zombie CLI container (running without profile = exits immediately)
CLI_STATE=$(docker inspect --format='{{.State.Status}}' openclaw-cli 2>/dev/null || echo "missing")
if [[ "$CLI_STATE" == "exited" ]]; then
  CLI_EXIT=$(docker inspect --format='{{.State.ExitCode}}' openclaw-cli 2>/dev/null || echo "?")
  if [[ "$CLI_EXIT" == "1" ]]; then
    warn "CLI container exited (code 1) — likely started without a command"
    info "The CLI should be run on-demand: docker compose --profile cli run --rm openclaw-cli <cmd>"
    if $FIX_MODE; then
      docker rm openclaw-cli >/dev/null 2>&1 && fix "Removed stale CLI container"
    fi
  fi
elif [[ "$CLI_STATE" == "missing" ]]; then
  pass "CLI container is not running (correct — it's on-demand)"
fi

echo ""

# ─── 5. Network Security ─────────────────────────────────────────────
echo "Network Security"
echo "────────────────"

# Check actual port bindings on the host
if command -v ss >/dev/null 2>&1; then
  BIND_18789=$(ss -tlnp 2>/dev/null | grep ':18789' | head -1)
elif command -v netstat >/dev/null 2>&1; then
  BIND_18789=$(netstat -tlnp 2>/dev/null | grep ':18789' | head -1)
else
  BIND_18789=""
fi

if [[ -n "$BIND_18789" ]]; then
  if echo "$BIND_18789" | grep -q '127\.0\.0\.1'; then
    pass "Port 18789 bound to localhost only"
  elif echo "$BIND_18789" | grep -q '0\.0\.0\.0\|:::'; then
    fail "Port 18789 is publicly exposed on the host!"
    info "Your docker-compose.yml must use '127.0.0.1:18789:18789'"
    info "Redeploy with: docker compose down && docker compose up -d openclaw-gateway"
  fi
else
  info "Port 18789 is not currently bound (gateway not running?)"
fi

# Check for exposed secrets in config
OPENCLAW_CONFIG="${CONFIG_DIR}/openclaw.json"
if [[ -f "$OPENCLAW_CONFIG" ]]; then
  if grep -q 'botToken' "$OPENCLAW_CONFIG"; then
    warn "Telegram bot token is stored in openclaw.json (normal, but keep the file protected)"
    # Check file permissions
    CONFIG_PERMS=$(stat -c '%a' "$OPENCLAW_CONFIG" 2>/dev/null || stat -f '%A' "$OPENCLAW_CONFIG" 2>/dev/null || echo "unknown")
    if [[ "$CONFIG_PERMS" == "600" || "$CONFIG_PERMS" == "400" ]]; then
      pass "Config file permissions are restrictive ($CONFIG_PERMS)"
    elif [[ "$CONFIG_PERMS" != "unknown" ]]; then
      warn "Config file permissions are $CONFIG_PERMS (recommend 600)"
      if $FIX_MODE; then
        chmod 600 "$OPENCLAW_CONFIG" && fix "Set $OPENCLAW_CONFIG to 600"
      fi
    fi
  fi
fi

echo ""

# ─── 6. Resource Usage ───────────────────────────────────────────────
echo "Resources"
echo "─────────"

# Disk usage
DISK_USE=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
if [[ -n "$DISK_USE" ]]; then
  if (( DISK_USE < 80 )); then
    pass "Disk usage: ${DISK_USE}%"
  elif (( DISK_USE < 90 )); then
    warn "Disk usage: ${DISK_USE}% (getting full)"
  else
    fail "Disk usage: ${DISK_USE}% (critical!)"
  fi
fi

# Memory
MEM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
if [[ -n "$MEM_AVAIL" ]]; then
  if (( MEM_AVAIL > 512 )); then
    pass "Available memory: ${MEM_AVAIL}MB"
  elif (( MEM_AVAIL > 256 )); then
    warn "Available memory: ${MEM_AVAIL}MB (low)"
  else
    fail "Available memory: ${MEM_AVAIL}MB (critical!)"
  fi
fi

# Docker disk usage
DOCKER_DISK=$(docker system df 2>/dev/null | awk '/Images/ {print $4}')
if [[ -n "$DOCKER_DISK" ]]; then
  info "Docker reclaimable space: $DOCKER_DISK"
fi

echo ""

# ─── 7. Gateway Logs Check ───────────────────────────────────────────
echo "Recent Issues"
echo "─────────────"

if [[ "$GW_STATE" == "running" ]]; then
  # Check for recent errors in last 100 lines
  RECENT_ERRORS=$(docker logs --tail 100 openclaw-gateway 2>&1 | grep -ci 'error\|fatal\|crash\|ECONNREFUSED\|ENOTFOUND' || true)
  if (( RECENT_ERRORS == 0 )); then
    pass "No errors in recent gateway logs"
  else
    warn "$RECENT_ERRORS error(s) found in recent gateway logs"
    info "Review with: docker logs --tail 50 openclaw-gateway 2>&1 | grep -i error"
  fi

  # Check for fetch failures (API connectivity)
  FETCH_FAILS=$(docker logs --tail 200 openclaw-gateway 2>&1 | grep -c 'fetch failed' || true)
  if (( FETCH_FAILS > 0 )); then
    warn "$FETCH_FAILS 'fetch failed' error(s) — check API connectivity (moonshot API reachable?)"
  fi

  # Check for WS "closed before connect" spam
  WS_DROPS=$(docker logs --tail 200 openclaw-gateway 2>&1 | grep -c 'closed before connect' || true)
  if (( WS_DROPS > 5 )); then
    warn "$WS_DROPS WebSocket 'closed before connect' events — possible port scanning or misconfigured client"
    info "If ports are publicly exposed, this is expected from internet scanners"
  elif (( WS_DROPS > 0 )); then
    info "$WS_DROPS WebSocket connection drop(s) (normal)"
  else
    pass "No WebSocket connection issues"
  fi
fi

echo ""

# ─── Summary ─────────────────────────────────────────────────────────
echo "Summary"
echo "───────"

if (( ISSUES == 0 )); then
  echo -e "  ${GREEN}All checks passed.${NC}"
else
  echo -e "  ${YELLOW}${ISSUES} issue(s) found.${NC}"
  if $FIX_MODE && (( FIXED > 0 )); then
    echo -e "  ${GREEN}${FIXED} issue(s) auto-fixed.${NC}"
  elif ! $FIX_MODE && (( ISSUES > 0 )); then
    echo -e "  Run ${CYAN}./doctor.sh --fix${NC} to auto-fix what we can."
  fi
fi

echo ""
exit $(( ISSUES - FIXED > 0 ? 1 : 0 ))
