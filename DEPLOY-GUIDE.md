# OpenClaw sur DigitalOcean — Guide de deploiement complet

> **Budget : 0$ pendant 60 jours** grace aux 200$ de credit offerts aux nouveaux comptes.
> Apres : ~6$/mois (Droplet) + ~1-3$/mois (tokens Kimi K2.5) = **~7-9$/mois**.

---

## Etape 1 : Creer le compte DigitalOcean + 200$ de credit

1. Va sur **digitalocean.com** via le lien d'inscription qui donne 200$ de credit
2. Cree ton compte (email + carte bancaire requise, mais rien ne sera debite)
3. **Verifie que le credit de 200$ est bien applique** dans Billing > Credits
4. Ces 200$ sont valables **60 jours** — largement assez pour tester

> Note : Le code promo "OPENCLAW" n'existe pas en tant que tel. Le credit de 200$/60 jours
> est l'offre standard DigitalOcean pour les nouveaux comptes. Si tu es etudiant, le
> GitHub Student Developer Pack donne aussi 200$ avec **1 an de validite** au lieu de 60 jours.

---

## Etape 2 : Creer le Droplet

### Option A : 1-Click Marketplace (le plus rapide)

1. Va sur **marketplace.digitalocean.com/apps/openclaw**
2. Clique **Create OpenClaw Droplet**
3. Configure :
   - **Region** : Frankfurt (FRA1) ou Amsterdam (AMS3) — le plus proche de toi
   - **Size** : Basic > Regular > **4GB RAM / 2 vCPU** (le minimum recommande) = **24$/mois**
     - Ou si tu veux economiser : **2GB / 1 vCPU** = **12$/mois** (suffisant pour usage perso)
   - **Authentication** : SSH Key (recommande) ou Password
4. Clique **Create Droplet**
5. Attends 1-2 minutes que le droplet soit pret

### Option B : Droplet vierge + notre script (plus de controle, moins cher)

1. Va sur **cloud.digitalocean.com** > Create > Droplets
2. Configure :
   - **Region** : Frankfurt ou Amsterdam
   - **Image** : Ubuntu 24.04 LTS
   - **Size** : Basic > Regular > **2GB RAM / 1 vCPU / 50GB SSD** = **12$/mois**
     - Ou le plan a **6$/mois** (1GB RAM / 25GB SSD) — le strict minimum
   - **Authentication** : SSH Key (recommande)
3. Clique **Create Droplet**

**C'est l'Option B que je recommande** — moins cher et tu as le controle total.

---

## Etape 3 : Deployer OpenClaw sur le droplet

### Si Option B (droplet vierge) — utilise notre script automatique :

```bash
# 1. Copie l'IP de ton droplet depuis le dashboard DigitalOcean

# 2. SSH dans le droplet
ssh root@<TON-IP-DROPLET>

# 3. Lance le bootstrap automatique (1 seule commande)
git clone https://github.com/khalilkrimech/khalilkrimech.git /tmp/oc-setup \
  && bash /tmp/oc-setup/do-bootstrap.sh

# Le script fait tout automatiquement :
#   - Met a jour le systeme
#   - Installe Docker + Docker Compose
#   - Cree un utilisateur non-root (openclaw)
#   - Configure le firewall (SSH only, port 18789 bloque)
#   - Clone le repo
#   - Lance setup.sh (onboarding interactif)
#   - Affiche les instructions de connexion
```

### Si Option A (1-Click) — OpenClaw est deja installe :

```bash
# 1. SSH dans le droplet
ssh root@<TON-IP-DROPLET>

# 2. Le setup interactif demarre automatiquement au premier login
#    Suis les instructions :
#    - Choisis ton provider LLM (Gradient, OpenAI, ou Anthropic)
#    - Entre ta cle API
#    - Configure les channels (Telegram, WhatsApp, etc.)
```

---

## Etape 4 : Se connecter au dashboard (tunnel SSH)

Le dashboard OpenClaw n'est **jamais** expose sur internet. Tu y accedes via un tunnel SSH securise.

```bash
# Depuis TON PC LOCAL (pas le droplet), ouvre un tunnel :
ssh -L 18789:127.0.0.1:18789 openclaw@<TON-IP-DROPLET>

# Ou si tu utilises le 1-Click (pas de user openclaw) :
ssh -L 18789:127.0.0.1:18789 root@<TON-IP-DROPLET>

# Puis ouvre dans ton navigateur :
#   http://localhost:18789/

# Le gateway token est dans le fichier .env sur le droplet :
grep OPENCLAW_GATEWAY_TOKEN ~/khalilkrimech/.env
# Copie-colle ce token dans Settings du dashboard
```

---

## Etape 5 : Configurer le modele AI (Kimi K2.5 = le plus rentable)

```bash
# Sur le droplet, configure Kimi K2.5 comme modele par defaut
# (8x moins cher que Claude, performances comparables)
cd ~/khalilkrimech

docker compose --profile cli run --rm openclaw-cli config set \
  providers.default.model "moonshot/kimi-k2.5"
```

### Comparaison des couts en tokens :

| Modele | Prix output/1M tokens | Performance relative |
|--------|----------------------|---------------------|
| Kimi K2.5 | 3$ | ~95% de Claude Opus |
| DeepSeek V3 | 2$ | ~85% de Claude Opus |
| GPT-4.1-mini | 5$ | ~80% de Claude Opus |
| Claude Opus 4.5 | 25$ | 100% (reference) |

---

## Etape 6 : Ajouter Telegram (optionnel)

```bash
# 1. Sur Telegram, parle a @BotFather
#    /newbot → donne un nom → copie le token

# 2. Sur le droplet :
cd ~/khalilkrimech
docker compose --profile cli run --rm openclaw-cli channels add \
  --channel telegram --token "TON_TOKEN_BOTFATHER"

# 3. Verifie que ca marche :
docker compose logs -f openclaw-gateway | grep -i telegram
```

---

## Etape 7 : Valider le deploiement

```bash
# Sur le droplet :
cd ~/khalilkrimech

# Lance le diagnostic complet
./doctor.sh

# Verifie que les ports sont bien proteges
docker ps
# Doit afficher : 127.0.0.1:18789->18789  (PAS 0.0.0.0)

# Verifie le firewall
sudo ufw status
# Doit afficher : OpenSSH ALLOW, rien d'autre
```

---

## Pairing du device (si erreur 1008)

Quand tu ouvres le dashboard pour la premiere fois, il faut approuver ton appareil :

```bash
# Sur le droplet :
cd ~/khalilkrimech

# Liste les appareils en attente
docker compose --profile cli run --rm openclaw-cli devices list

# Approuve ton appareil par son ID
docker compose --profile cli run --rm openclaw-cli devices approve <REQUEST-ID>

# Rafraichis le navigateur — ca devrait marcher
```

---

## Commandes utiles au quotidien

```bash
# Voir les logs en temps reel
docker compose logs -f openclaw-gateway

# Redemarrer le gateway
docker compose restart openclaw-gateway

# Arreter tout
docker compose down

# Diagnostic + auto-reparation
./doctor.sh --fix

# Mettre a jour OpenClaw
git pull origin main
docker compose build openclaw-gateway
docker compose up -d openclaw-gateway
```

---

## Budget previsionnel

| Poste | Mois 1-2 (credit) | Apres |
|-------|-------------------|-------|
| Droplet 2GB | 0$ (sur credit) | 12$/mois |
| Droplet 1GB | 0$ (sur credit) | 6$/mois |
| Tokens Kimi K2.5 (usage leger) | ~1-3$ | ~1-3$ |
| **Total (plan eco)** | **~1-3$** | **~7-9$/mois** |
| **Total (plan confort)** | **~1-3$** | **~13-15$/mois** |

Les 200$ de credit couvrent :
- ~16 mois de droplet 2GB, ou
- ~33 mois de droplet 1GB
- ...mais le credit expire apres 60 jours, donc tu as 2 mois gratuits max.

---

## Securite — checklist

- [ ] Port 18789 bind a 127.0.0.1 uniquement (pas 0.0.0.0)
- [ ] UFW actif : seul SSH est ouvert
- [ ] Acces dashboard via tunnel SSH uniquement
- [ ] Gateway token = 64 caracteres hex aleatoires
- [ ] Fichier .env non commit dans git
- [ ] SSH par cle (pas par mot de passe)
- [ ] Permissions 600 sur ~/.openclaw/openclaw.json
