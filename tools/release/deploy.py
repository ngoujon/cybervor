"""Déploie une version préparée par make_release.py sur le VPS — À LANCER UNIQUEMENT APRÈS LE « GO ».

    python tools/release/deploy.py 0.2.0 [--site] [--recreate-rooms]

Ordre choisi pour ne jamais interrompre les parties en cours :
  1. sauvegarde (/opt/cybervor-backup-<date> + base SQLite) ;
  2. serveur de jeu à chaud (server/deploy/update_game.sh) : les parties en cours gardent l'ancien binaire,
     les nouvelles parties démarrent en <version> ;
  3. API méta (docker compose up -d --build meta : quelques secondes, les clients réessaient tout seuls) ;
     --recreate-rooms : recrée aussi le superviseur (nécessaire seulement si rooms.py/Dockerfile/compose changent ;
     refusé tant qu'une partie est en cours) ;
  4. site + Cybervor.zip (copie puis renommage atomique) ;
  5. version.json EN DERNIER : les jeux ouverts proposent alors la mise à jour, les autres l'installent au lancement.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIST = Path(__file__).resolve().parent / "dist"
# réglages propres à la machine (hôte SSH réel…) : fichier local non versionné, lignes CLE=valeur
_LOCAL = Path(__file__).with_name("deploy.local.env")
if _LOCAL.exists():
    for _line in _LOCAL.read_text(encoding="utf-8").splitlines():
        if "=" in _line and not _line.lstrip().startswith("#"):
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip())
HOST =os.environ.get("CYBERVOR_SSH_HOST", "cybervor-vps")      # alias SSH (~/.ssh/config)
PUBLIC = os.environ.get("CYBERVOR_PUBLIC_URL", "https://vps-3962b7dc.vps.ovh.net/cybervore")
WWW = os.environ.get("CYBERVOR_WWW", "/var/www/cybervore")
SRV = os.environ.get("CYBERVOR_SRV", "/opt/cybervor/server")


def sh(cmd: str) -> str:
    r = subprocess.run(["ssh", HOST, cmd], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        sys.exit(f"Échec : {cmd[:80]}")
    return r.stdout


def put(local: Path, remote: str) -> None:
    if subprocess.run(["scp", "-q", str(local), f"{HOST}:{remote}"]).returncode != 0:
        sys.exit(f"Échec de l'envoi de {local}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--site", action="store_true", help="met aussi à jour website/index.html")
    ap.add_argument("--recreate-rooms", action="store_true")
    a = ap.parse_args()
    manifest = json.loads((DIST / "version.json").read_text(encoding="utf-8"))
    built = (ROOT / "server/game/build/VERSION").read_text(encoding="utf-8").strip()
    if manifest["version"] != a.version or built != a.version:
        sys.exit(f"Versions incohérentes : manifeste {manifest['version']}, serveur {built}, demandé {a.version}")

    print("[1/5] sauvegarde")
    print(sh("TS=$(date +%Y%m%d-%H%M%S); sudo cp -a /opt/cybervor /opt/cybervor-backup-$TS && "
             "sudo docker exec cybervor-meta-1 python -c \"import sqlite3;s=sqlite3.connect('/data/cybervor.db');"
             "d=sqlite3.connect('/data/cybervor-backup-'+'$TS'+'.db');s.backup(d)\" && echo sauvegarde $TS"))

    print("[2/5] serveur de jeu (à chaud)")
    put(ROOT / "server/game/build/cybervor_server.x86_64", "/tmp/cybervor_server.x86_64")
    put(ROOT / "server/deploy/update_game.sh", "/tmp/cybervor_update_game.sh")
    print(sh(f"sudo install -m 755 /tmp/cybervor_update_game.sh {SRV}/deploy/update_game.sh 2>/dev/null || "
             f"(sudo mkdir -p {SRV}/deploy && sudo install -m 755 /tmp/cybervor_update_game.sh {SRV}/deploy/update_game.sh); "
             f"sudo sh {SRV}/deploy/update_game.sh /tmp/cybervor_server.x86_64 {a.version} && rm /tmp/cybervor_server.x86_64"))

    print("[3/5] API méta")
    for rel in ["server/meta-api/app.py", "server/meta-api/Dockerfile", "server/meta-api/requirements.txt",
                "server/docker-compose.yml", "server/game/Dockerfile", "server/game/rooms.py", "server/README.md", "data/battlepass.json"]:
        put(ROOT / rel, "/tmp/cybervor_upload")
        sh(f"sudo install -m 644 /tmp/cybervor_upload /opt/cybervor/{rel}")
    sh(f"cd {SRV} && sudo docker compose up -d --build meta")
    for _ in range(60):   # l'API redémarre : on attend qu'elle réponde
        try:
            urllib.request.urlopen(PUBLIC + "/api/v1/season", timeout=5)
            break
        except OSError:
            time.sleep(2)
    else:
        sys.exit("L'API ne répond pas après son redémarrage")
    if a.recreate_rooms:
        live = json.loads(urllib.request.urlopen(PUBLIC + "/api/v1/servers", timeout=10).read())["servers"]
        busy = [s for s in live if s.get("players", 0) > 0]
        if busy:
            sys.exit(f"{len(busy)} partie(s) en cours : superviseur NON recréé (relancer plus tard avec --recreate-rooms)")
        sh(f"cd {SRV} && sudo docker compose up -d --build rooms")

    print("[4/5] site et téléchargement")
    put(DIST / "Cybervor.zip", "/tmp/Cybervor.zip")
    sh(f"sudo install -m 644 /tmp/Cybervor.zip {WWW}/Cybervor.zip.new && sudo mv -f {WWW}/Cybervor.zip.new {WWW}/Cybervor.zip && rm /tmp/Cybervor.zip")
    if a.site:
        put(ROOT / "website/index.html", "/tmp/cybervor_index.html")
        sh(f"sudo install -m 644 /tmp/cybervor_index.html {WWW}/index.html && rm /tmp/cybervor_index.html")

    print("[5/5] annonce de la version")
    put(DIST / "version.json", "/tmp/cybervor_version.json")
    sh(f"sudo install -m 644 /tmp/cybervor_version.json {WWW}/version.json.new && sudo mv -f {WWW}/version.json.new {WWW}/version.json")
    got = json.loads(urllib.request.urlopen(PUBLIC + "/version.json", timeout=10).read())
    print(f"Version en ligne : {got['version']} — les joueurs vont être mis à jour.")


if __name__ == "__main__":
    main()
