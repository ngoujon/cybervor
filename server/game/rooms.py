"""Superviseur des parties Cybervor : un joueur crée une partie, le superviseur lance une instance
du serveur de jeu Godot (headless) sur un port UDP libre ; les autres joueurs la rejoignent.
Chaque instance s'arrête toute seule quand elle reste vide (voir --room côté jeu).

API interne (réseau Docker uniquement, appelée par l'API méta) :
    POST /rooms   {"mode": "coop"|"pvp", "name": "Partie de Zorg", "owner": "<player_id>", "max": 4}
                  -> {"id", "host", "port", "mode", "name"}
    GET  /rooms   -> {"rooms": [...]}
    GET  /health

Variables d'environnement :
    CYBERVOR_PORT_MIN / CYBERVOR_PORT_MAX   plage de ports UDP (défaut 7810-7829)
    CYBERVOR_MAX_ROOMS                      nombre maximal de parties simultanées (défaut 12)
    CYBERVOR_SERVER_CMD                     commande du serveur de jeu (défaut ./cybervor_server.x86_64 --headless)
    CYBERVOR_PUBLIC_HOST, CYBERVOR_META_URL, CYBERVOR_SERVER_SECRET : transmises aux instances
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_MIN = int(os.environ.get("CYBERVOR_PORT_MIN", "7810"))
PORT_MAX = int(os.environ.get("CYBERVOR_PORT_MAX", "7829"))
MAX_ROOMS = int(os.environ.get("CYBERVOR_MAX_ROOMS", "12"))
SERVER_CMD = [t.strip('"') for t in shlex.split(os.environ.get("CYBERVOR_SERVER_CMD", "./bin/cybervor_server.x86_64 --headless"),
                                                 posix=os.name != "nt")]
# Version du serveur de jeu actuellement installé (fichier VERSION écrit par tools/release/make_release.py).
# Mise à jour à chaud : on remplace le binaire et VERSION ; les parties en cours gardent l'ancienne version
# jusqu'à leur fin, les nouvelles parties démarrent avec la nouvelle.
VERSION_FILE = os.environ.get("CYBERVOR_VERSION_FILE", "./bin/VERSION")


def server_version() -> str:
    try:
        with open(VERSION_FILE, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""
PUBLIC_HOST = os.environ.get("CYBERVOR_PUBLIC_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("CYBERVOR_ROOMS_PORT", "9000"))

rooms: dict[int, dict] = {}   # port -> {proc, id, mode, name, owner, created}
lock = threading.Lock()


def reap() -> None:
    """Retire les instances terminées (partie vide, plantage…)."""
    with lock:
        for port in [p for p, r in rooms.items() if r["proc"].poll() is not None]:
            r = rooms.pop(port)
            print(f"[rooms] partie {r['id']} terminée (code {r['proc'].returncode})", flush=True)


class Outdated(Exception):
    pass


def create(mode: str, name: str, owner: str, max_players: int, version: str = "") -> dict:
    reap()
    sv = server_version()
    if version and sv and version != sv:
        raise Outdated(f"Une mise à jour du jeu (version {sv}) est disponible : redémarrez Cybervor pour l'installer, puis créez votre partie.")
    with lock:
        # un joueur = une partie ouverte à la fois : on lui rend la sienne si elle existe encore
        for port, r in rooms.items():
            if owner and r["owner"] == owner and r.get("version") == sv:
                return public(port, r)
        if len(rooms) >= MAX_ROOMS:
            raise RuntimeError("Le serveur est plein, réessayez dans quelques minutes.")
        port = next((p for p in range(PORT_MIN, PORT_MAX + 1) if p not in rooms), None)
        if port is None:
            raise RuntimeError("Aucun port libre sur le serveur.")
        rid = f"room-{port}-{int(time.time()) % 100000}"
        env = dict(os.environ, CYBERVOR_SERVER_ID=rid, CYBERVOR_SERVER_NAME=name[:40],
                   CYBERVOR_ROOM_OWNER=owner, CYBERVOR_PUBLIC_HOST=PUBLIC_HOST)
        cmd = SERVER_CMD + ["--", "--server", "--room", "--port", str(port), "--mode", mode, "--max", str(max_players)]
        proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        rooms[port] = {"proc": proc, "id": rid, "mode": mode, "name": name, "owner": owner, "created": time.time(), "version": sv}
        print(f"[rooms] nouvelle partie {rid} ({mode}) « {name} » sur le port {port}", flush=True)
        return public(port, rooms[port])


def public(port: int, r: dict) -> dict:
    return {"id": r["id"], "host": PUBLIC_HOST, "port": port, "mode": r["mode"], "name": r["name"], "owner": r["owner"],
            "version": r.get("version", "")}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        reap()
        if self.path == "/health":
            return self._send(200, {"ok": True, "rooms": len(rooms), "version": server_version()})
        if self.path == "/rooms":
            with lock:
                return self._send(200, {"rooms": [public(p, r) for p, r in rooms.items()]})
        self._send(404, {"detail": "introuvable"})

    def do_POST(self):  # noqa: N802
        if self.path != "/rooms":
            return self._send(404, {"detail": "introuvable"})
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)) or 2) or b"{}")
            mode = body.get("mode", "coop")
            if mode not in ("coop", "pvp"):
                return self._send(422, {"detail": "mode inconnu"})
            room = create(mode, str(body.get("name", "Partie")), str(body.get("owner", "")), max(1, min(int(body.get("max", 4)), 4)),
                          str(body.get("version", "")))
            self._send(200, room)
        except Outdated as e:
            self._send(409, {"detail": str(e)})
        except RuntimeError as e:
            self._send(503, {"detail": str(e)})
        except Exception as e:  # noqa: BLE001
            self._send(500, {"detail": f"erreur : {e}"})

    def log_message(self, *_):
        pass


def _reaper_loop() -> None:
    while True:
        time.sleep(5)
        reap()


if __name__ == "__main__":
    threading.Thread(target=_reaper_loop, daemon=True).start()
    print(f"[rooms] superviseur prêt sur :{LISTEN_PORT}, ports {PORT_MIN}-{PORT_MAX}, {MAX_ROOMS} parties max", flush=True)
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
