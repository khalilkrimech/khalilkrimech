#!/usr/bin/env bash
# DigitalOcean Post-Deploy Bootstrap
# Run this ONCE after SSH-ing into your new droplet.
#
# Usage:
#   ssh root@<droplet-ip>
#   curl -fsSL https://raw.githubusercontent.com/khalilkrimech/khalilkrimech/main/do-bootstrap.sh | bash
#   # OR: clone the repo first, then ./do-bootstrap.sh
#
# What this does:
#   1. Updates the system
#   2. Installs Docker + Docker Compose v2
#   3. Creates a non-root user (openclaw)
#   4. Configures UFW firewall (SSH only)
#   5. Clones the repo
#   6. Runs setup.sh
#   7. Prints connection instructions

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ─── Must be root ────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || fail "Run this script as root (ssh root@droplet-ip)"

DROPLET_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenClaw — DigitalOcean Bootstrap"
echo "  Droplet IP: $DROPLET_IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── 1. System Update ────────────────────────────────────────────────
info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
ok "System updated."

# ─── 2. Install Docker ──────────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
  ok "Docker already installed: $(docker --version)"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  ok "Docker installed: $(docker --version)"
fi

if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose v2 available."
else
  fail "Docker Compose v2 not available after Docker install."
fi

# ─── 3. Create non-root user ────────────────────────────────────────
OC_USER="openclaw"
if id "$OC_USER" &>/dev/null; then
  ok "User '$OC_USER' already exists."
else
  info "Creating user '$OC_USER'..."
  useradd -m -s /bin/bash "$OC_USER"
  usermod -aG docker "$OC_USER"
  # Copy root's SSH authorized_keys so you can SSH as openclaw too
  if [[ -f /root/.ssh/authorized_keys ]]; then
    mkdir -p /home/$OC_USER/.ssh
    cp /root/.ssh/authorized_keys /home/$OC_USER/.ssh/
    chown -R $OC_USER:$OC_USER /home/$OC_USER/.ssh
    chmod 700 /home/$OC_USER/.ssh
    chmod 600 /home/$OC_USER/.ssh/authorized_keys
  fi
  ok "User '$OC_USER' created with Docker access."
fi

# ─── 4. Firewall ────────────────────────────────────────────────────
info "Configuring UFW firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
# DO NOT open port 18789 — access via SSH tunnel only
ufw --force enable >/dev/null
ok "Firewall active: SSH only. Port 18789 is NOT exposed (SSH tunnel only)."

# ─── 5. Clone repo ──────────────────────────────────────────────────
DEPLOY_DIR="/home/$OC_USER/khalilkrimech"
if [[ -d "$DEPLOY_DIR" ]]; then
  ok "Repo already exists at $DEPLOY_DIR"
  cd "$DEPLOY_DIR"
  sudo -u "$OC_USER" git pull origin main 2>/dev/null || true
else
  info "Cloning repository..."
  sudo -u "$OC_USER" git clone https://github.com/khalilkrimech/khalilkrimech.git "$DEPLOY_DIR"
  ok "Repo cloned to $DEPLOY_DIR"
fi

cd "$DEPLOY_DIR"
chown -R $OC_USER:$OC_USER "$DEPLOY_DIR"

# ─── 6. Run setup ───────────────────────────────────────────────────
info "Running OpenClaw setup..."
chmod +x setup.sh doctor.sh
sudo -u "$OC_USER" bash setup.sh

# ─── 7. Summary ─────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  OpenClaw est deploye sur DigitalOcean !"
echo ""
echo "  Droplet IP: $DROPLET_IP"
echo ""
echo "  ETAPE SUIVANTE — depuis ton PC local, ouvre le tunnel SSH :"
echo ""
echo "    ssh -L 18789:127.0.0.1:18789 $OC_USER@$DROPLET_IP"
echo ""
echo "  Puis ouvre dans ton navigateur :"
echo "    http://localhost:18789/"
echo ""
echo "  Le token gateway est dans : $DEPLOY_DIR/.env"
echo "  Pour le voir : grep OPENCLAW_GATEWAY_TOKEN $DEPLOY_DIR/.env"
echo ""
echo "  Commandes utiles :"
echo "    cd $DEPLOY_DIR"
echo "    docker compose logs -f openclaw-gateway"
echo "    docker compose ps"
echo "    ./doctor.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
