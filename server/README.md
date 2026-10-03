# Infrastructure en ligne de Cybervor

Tout est préparé pour l'hébergement. Il ne reste qu'à choisir la machine et à remplir les secrets
(les instructions infra détaillées viendront ensuite).

## Architecture

```
            ┌───────────────── Internet ──────────────────┐
 Joueurs ──►│  UDP 7777..7779  ──► serveurs de jeu Godot   │  (ENet, autoritaire, headless)
 (Cybervor) │  HTTPS / 8080    ──► API méta (FastAPI)      │  profils, battle pass, liste
            └──────────────────────────────────────────────┘  des serveurs, matchmaking
                     serveurs de jeu ──heartbeat 15 s──► API méta
```

- **Serveur de jeu** (`game/`) : export « Serveur Linux » du projet Godot (fonctionnalité `dedicated_server`),
  lancé en headless. Un conteneur = un salon (coop ou PvP, 4 joueurs max). Le premier joueur connecté
  devient chef du salon et choisit mission / mode. À la fin d'une partie, le salon revient en attente.
- **API méta** (`meta-api/`) : FastAPI + SQLite.
  - `POST /api/v1/auth/guest` : compte invité (identifiant généré par le client) → jeton HMAC
  - `GET|PUT /api/v1/profile` : sauvegarde du profil (garde-fous : monnaies ≥ 0, XP du pass plafonnée)
  - `POST /api/v1/runs` : résultat de partie, XP de battle pass recalculée côté serveur (registre anti-triche)
  - `GET /api/v1/season` : définition de la saison du battle pass
  - `GET /api/v1/leaderboard?mode=endless` : classement
  - `POST /api/v1/servers/heartbeat` (en-tête `X-Server-Secret`) / `GET /api/v1/servers`
  - `POST /api/v1/matchmaking` : renvoie un serveur libre pour le mode demandé
  - Social : `GET /api/v1/me` (code ami), `GET /api/v1/friends`, `POST /api/v1/friends/request|accept|remove`,
    `GET|POST /api/v1/messages`, `GET /api/v1/messages/unread` (messagerie réservée aux amis, anti-spam 30/min)
  - `POST /api/v1/feedback` : bugs et suggestions (compte facultatif)
  - `GET /api/v1/admin/feedback?kind=bug` (en-tête `X-Admin-Secret`) : lire les retours des joueurs
  - `GET /health`

## Déploiement (Docker)

```bash
# 1. Exporter le serveur Linux (depuis Windows) :
powershell -ExecutionPolicy Bypass -File server/build_server.ps1
# 2. Sur la machine serveur, à la racine du dépôt :
cd server && cp .env.example .env && nano .env   # PUBLIC_HOST + secrets
docker compose up -d --build
```

Ports à ouvrir : **UDP 7777-7779** (jeu) et **TCP 8080** (API, ou 80/443 avec le proxy Caddy commenté).
Ajouter des salons = dupliquer un service `game-*` dans `docker-compose.yml` avec un nouveau port.

### Variables d'environnement du serveur de jeu

| Variable | Rôle |
|---|---|
| `CYBERVOR_PORT`, `CYBERVOR_MODE` (`coop`/`endless`/`pvp`), `CYBERVOR_MAX` | port UDP, mode par défaut, joueurs max |
| `CYBERVOR_META_URL` | URL de l'API méta (heartbeat) |
| `CYBERVOR_SERVER_SECRET` | secret partagé avec l'API |
| `CYBERVOR_PUBLIC_HOST` | IP / domaine annoncé aux joueurs |
| `CYBERVOR_SERVER_ID`, `CYBERVOR_SERVER_NAME` | identifiant et nom affiché |

Sans Docker : `./cybervor_server.x86_64 --headless -- --server --port 7777 --mode coop --max 4`
(sous Windows : `Cybervor.exe --headless -- --server ...`).

## Côté client

Renseigner l'URL de l'API dans `config/online.cfg` (`[meta] url=`, et `[jeu] hote=` pour le serveur
proposé par défaut) avant l'export, ou en jeu dans **Paramètres > Réseau**. Le jeu reste jouable hors ligne.
Le menu Jouer affiche alors les serveurs en ligne et les boutons « Partie rapide ».

## Tests

```bash
cd server/meta-api && python -m pytest -q        # 7 tests
```

## À faire lors de la mise en production

- Mettre l'API derrière HTTPS (Caddy / Nginx) et changer les secrets.
- Rendre le battle pass entièrement autoritaire : faire remonter les résultats directement des serveurs
  de jeu (avec `X-Server-Secret`) plutôt que des clients, puis ignorer `battlepass.xp` envoyé par le client.
- Achats réels de néons : brancher un prestataire de paiement côté API (non implémenté volontairement).

## Parties créées par les joueurs (serveur unique)

Il n'y a qu'un seul serveur : un joueur clique sur « Créer une partie » (coopération ou arène PvP),
les autres la voient dans « Parties ouvertes » et la rejoignent.

```
client ──POST /api/v1/rooms──▶ API méta ──POST /rooms──▶ superviseur (game/rooms.py, conteneur « rooms »)
                                                          └─ lance cybervor_server --room sur un port libre (7810-7829/udp)
instance ──heartbeat (owner, room)──▶ API méta ──GET /api/v1/servers──▶ liste « Parties ouvertes »
```

- Une partie par joueur : s'il en a déjà une, on lui renvoie la sienne.
- Une instance s'arrête seule si personne ne la rejoint en 2 min, ou dès qu'elle reste vide 60 s ;
  l'API la retire aussitôt de la liste (elle interroge le superviseur).
- Variables : `GAME_PORT_MIN`, `GAME_PORT_MAX`, `MAX_ROOMS` (12 par défaut, ~60-90 Mo par partie).
- Test local sous Windows : lancer `rooms.py` avec
  `CYBERVOR_SERVER_CMD="<godot_console.exe> --headless --path <projet>"` et l'API avec `CYBERVOR_ROOMS_URL`.

## Publier une nouvelle version (mise à jour automatique des joueurs)

1. Ajouter les notes de la version dans `data/patchnotes.json` (affichées sur l'accueil du jeu et dans la
   proposition de mise à jour).
2. `python tools/release/make_release.py X.Y.Z` : version dans `project.godot`, export Windows + zip + `version.json`
   (taille, sha256, notes) dans `tools/release/dist/`, export du serveur Linux + `server/game/build/VERSION`.
3. Après le « go » uniquement : `python tools/release/deploy.py X.Y.Z [--site]`.
   - serveur de jeu remplacé **à chaud** (`server/deploy/update_game.sh`) : les parties en cours continuent avec
     l'ancienne version, les nouvelles démarrent avec la nouvelle ;
   - `version.json` est publié en dernier : les jeux ouverts proposent la mise à jour (jamais pendant une partie),
     les autres l'installent au lancement puis redémarrent ;
   - une partie d'une autre version est signalée dans la liste (« Mettre à jour ») et la création de partie
     avec un jeu pas à jour renvoie un message invitant à mettre à jour.

## Sauvegarde cloud

`POST /api/v1/profile/sync` fusionne le profil local et celui du cloud (missions et déblocages unis, records au
maximum, monnaies : serveur + gains locaux depuis la dernière synchro, choix les plus récents). Idempotent
(`push_id`). Hors ligne, le jeu garde ses progrès et les envoie à la reconnexion. Code de sauvegarde (Profil) +
`POST /api/v1/auth/restore` pour retrouver sa progression sur un autre PC. Les anciens clients (PUT /profile)
sont aussi fusionnés : ils ne peuvent plus écraser une progression.

## Déploiement en production

Le serveur tourne avec `docker compose` (projet `cybervor`) derrière un reverse proxy HTTPS ; les secrets sont
dans `server/.env` (jamais versionné, `chmod 600`). L'API méta écoute en local et est publiée par le proxy sous
`/cybervore/api/`, le site statique (`website/`) sous `/cybervore/`, et les salons de jeu utilisent une plage de
ports UDP dédiée (voir `.env.example`). Les mises à jour se font avec `tools/release/deploy.py`
(hôte SSH et chemins configurables par variables d'environnement).

> **Volume du binaire** : le binaire du serveur de jeu est monté en volume (`./game/build` → `/srv/cybervor/bin`) :
> après la première installation, le conteneur `rooms` n'a plus besoin d'être recréé pour mettre le jeu à jour
> (`deploy.py --recreate-rooms` uniquement si nécessaire, refusé tant qu'une partie est en cours).

Mettre à jour les serveurs à la main : réexporter le serveur Linux, copier `server/game/build/` sur le serveur,
puis `docker compose up -d --build`.
Lire les retours joueurs : `curl -H "X-Admin-Secret: <CYBERVOR_ADMIN_SECRET du .env>" <URL de l'API>/api/v1/admin/feedback`.
