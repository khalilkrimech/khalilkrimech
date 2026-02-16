# OpenClaw Deployment Guide — Options du plus cheap au plus cher

## TL;DR — Quelle option choisir ?

| Option | Prix/mois | Difficulte | Fiabilite | Recommandation |
|--------|-----------|------------|-----------|----------------|
| **Kimi Claw** | ~0$ (beta) | Aucune | Moyenne | Tester d'abord si tu as acces |
| **Oracle Cloud Free** | 0$ | Moyenne | Risquee* | Budget zero, OK pour tester |
| **Hetzner CX11** | ~3.49EUR | Facile | Excellente | **Meilleur rapport qualite/prix** |
| **Vultr** | ~2.50$ | Facile | Bonne | Alternative si Hetzner refuse |
| **DigitalOcean** | ~4$ | Facile | Excellente | Code promo OPENCLAW = 200$ credit |

*Oracle peut supprimer les instances inactives sans prevenir.

---

## Option 1 : Kimi Claw (0$ — pas de VPS)

Kimi Claw est la version cloud d'OpenClaw hebergee par Moonshot AI (kimi.ai). Pas besoin de VPS, tout tourne dans le navigateur.

### Etapes :
1. Va sur **kimi.com/bot**
2. Cree un compte Kimi.ai
3. Upgrade en **Allegretto** (requis pour la beta)
4. OpenClaw tourne directement — zero config serveur

### Avantages :
- Zero configuration serveur
- 5000+ skills via ClawHub
- 40GB stockage cloud
- Modele Kimi K2.5 integre (rival de Claude Opus, 8x moins cher)

### Inconvenients :
- Acces beta (Allegretto minimum)
- Donnees hebergees en Chine (Moonshot AI)
- Moins de controle qu'un self-host

---

## Option 2 : Oracle Cloud Free Tier (0$/mois)

Le free tier le plus genereux : jusqu'a 4 OCPU ARM + 24GB RAM + 200GB stockage.

### Etapes :
```bash
# 1. Cree un compte sur cloud.oracle.com
#    IMPORTANT : Upgrade en "Pay As You Go" (PAYG) pour eviter
#    la suppression automatique des instances inactives.
#    Tu ne paies rien tant que tu restes sur les ressources "Always Free".

# 2. Cree une instance ARM (Ampere A1)
#    - Shape: VM.Standard.A1.Flex
#    - OCPUs: 2 (ou jusqu'a 4 gratuitement)
#    - RAM: 12GB (ou jusqu'a 24GB)
#    - OS: Ubuntu 22.04 ou 24.04
#    - Stockage: 100GB (gratuit jusqu'a 200GB)

# 3. SSH dans l'instance
ssh ubuntu@<ton-ip-oracle>

# 4. Installe Docker
sudo apt update && sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER
# Deconnecte et reconnecte pour appliquer le groupe docker

# 5. Clone ton repo et lance le setup
git clone <ton-repo-url> && cd khalilkrimech
chmod +x setup.sh
./setup.sh

# 6. Depuis ton PC local, ouvre le tunnel SSH
ssh -L 18789:127.0.0.1:18789 ubuntu@<ton-ip-oracle>
# Puis ouvre http://localhost:18789/
```

### Risques Oracle :
- Sans upgrade PAYG, Oracle peut supprimer les instances "idle"
- Mets une alerte budget a 1$ pour etre prevenu
- Les instances ARM sont souvent "out of capacity" — il faut retenter plusieurs fois

---

## Option 3 : Hetzner CX11 (~3.49EUR/mois) — RECOMMANDE

Le meilleur rapport qualite/prix. Stable, fiable, rapide.

### Etapes :
```bash
# 1. Cree un compte sur hetzner.com/cloud
#    Note: verification d'identite possible (passeport/carte d'identite)

# 2. Cree un serveur cloud :
#    - Location: Falkenstein ou Helsinki (moins cher)
#    - Image: Ubuntu 24.04
#    - Type: CX11 (1 vCPU, 2GB RAM, 20GB SSD) = 3.49EUR/mois
#    Ou CX22 (2 vCPU, 4GB RAM, 40GB SSD) = 5.49EUR/mois pour plus de marge

# 3. Ajoute ta cle SSH (ou utilise le mot de passe fourni)

# 4. SSH dans le serveur
ssh root@<ton-ip-hetzner>

# 5. Installe Docker
curl -fsSL https://get.docker.com | sh
# Docker Compose v2 est inclus

# 6. Clone et lance
git clone <ton-repo-url> && cd khalilkrimech
chmod +x setup.sh
./setup.sh

# 7. Depuis ton PC local
ssh -L 18789:127.0.0.1:18789 root@<ton-ip-hetzner>
# Ouvre http://localhost:18789/
```

### Pourquoi Hetzner :
- 20TB de bande passante inclus
- Disques NVMe rapides
- Facturation a l'heure (tu paies au prorata si tu supprimes avant la fin du mois)
- Datacenters EU + US

---

## Option 4 : Vultr (~2.50$/mois)

Moins cher que Hetzner en entree de gamme, 32+ datacenters dans le monde.

### Etapes :
```bash
# 1. Cree un compte sur vultr.com

# 2. Deploy New Instance :
#    - Cloud Compute (Regular Performance)
#    - Location: la plus proche de toi
#    - OS: Ubuntu 24.04
#    - Plan: 25GB SSD, 1 vCPU, 1GB RAM = 5$/mois
#    Ou le plan a 2.50$/mois (512MB RAM — juste pour OpenClaw)

# 3-7. Meme procedure que Hetzner (SSH, Docker, clone, setup)
```

---

## Option 5 : DigitalOcean (~4$/mois + 200$ credit)

Code promo **OPENCLAW** donne 200$ de credit gratuit.

### Etapes :
```bash
# 1. Cree un compte sur digitalocean.com
#    Utilise le code promo OPENCLAW pour 200$ de credit

# 2. Create Droplet :
#    - Image: Ubuntu 24.04
#    - Plan: Basic, Regular, 1GB RAM, 25GB SSD = 6$/mois
#    Ou : 1-Click App "OpenClaw" (si disponible dans le marketplace)

# 3-7. Meme procedure
```

---

## Configuration du modele (economiser sur les tokens)

Apres le deploiement, configure un modele pas cher :

```bash
# Option A : Kimi K2.5 (le plus rentable — 8x moins cher que Claude)
# Output tokens : 3$/million vs 25$/million pour Claude Opus
docker compose --profile cli run --rm openclaw-cli config set \
  providers.default.model "moonshot/kimi-k2.5"

# Option B : GPT-4.1-mini (bon rapport qualite/prix)
docker compose --profile cli run --rm openclaw-cli config set \
  providers.default.model "openai/gpt-4.1-mini"

# Option C : DeepSeek V3 (tres cheap, open-source)
docker compose --profile cli run --rm openclaw-cli config set \
  providers.default.model "deepseek/deepseek-chat"

# Option D : Ollama local (0$ en tokens, mais besoin de plus de RAM)
# Necessite au minimum 8GB RAM sur le VPS
```

---

## Comparaison des couts mensuels totaux

| Setup | VPS | Tokens (usage leger) | Total |
|-------|-----|---------------------|-------|
| Oracle + Kimi K2.5 | 0$ | ~1-3$ | **~1-3$/mois** |
| Hetzner + Kimi K2.5 | 3.49EUR | ~1-3$ | **~5-7$/mois** |
| Hetzner + GPT-4.1-mini | 3.49EUR | ~3-5$ | **~7-9$/mois** |
| DO (avec promo) + Kimi K2.5 | 0$ (credit) | ~1-3$ | **~1-3$/mois** |

---

## Checklist rapide apres deploiement

```bash
# Verifie que tout fonctionne
./doctor.sh

# Verifie que les ports ne sont pas exposes publiquement
docker ps  # Doit afficher 127.0.0.1:18789, PAS 0.0.0.0:18789

# Configure le firewall (UFW)
sudo ufw allow OpenSSH
sudo ufw enable
# NE PAS ouvrir le port 18789 dans le firewall

# Teste le tunnel SSH depuis ton PC
ssh -L 18789:127.0.0.1:18789 user@ton-vps
# Ouvre http://localhost:18789/ dans ton navigateur
```
