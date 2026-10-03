"""API méta de Cybervor : comptes invités, profils, battle pass, parties, serveurs, matchmaking.

Lancement local :  uvicorn app:app --host 0.0.0.0 --port 8080
Variables d'environnement :
    CYBERVOR_DB            chemin de la base SQLite (défaut ./cybervor.db)
    CYBERVOR_TOKEN_SECRET  secret HMAC pour les jetons joueurs (OBLIGATOIRE en production)
    CYBERVOR_SERVER_SECRET secret partagé avec les serveurs de jeu dédiés (heartbeat)
    CYBERVOR_SEASON_FILE   chemin vers battlepass.json (défaut ../../data/battlepass.json)
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import random
import re
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

DB_PATH = os.environ.get("CYBERVOR_DB", "cybervor.db")
TOKEN_SECRET = os.environ.get("CYBERVOR_TOKEN_SECRET", "dev-secret-a-changer")
SERVER_SECRET = os.environ.get("CYBERVOR_SERVER_SECRET", "dev-server-secret")
SEASON_FILE = Path(os.environ.get("CYBERVOR_SEASON_FILE") or Path(__file__).resolve().parent.parent.parent / "data" / "battlepass.json")
ADMIN_SECRET = os.environ.get("CYBERVOR_ADMIN_SECRET", "")
ROOMS_URL = os.environ.get("CYBERVOR_ROOMS_URL", "")  # superviseur des parties (server/game/rooms.py)
SERVER_TTL = 45  # secondes sans heartbeat avant de retirer un serveur de la liste
PROTOCOL = "cybervor-1"

app = FastAPI(title="Cybervor — API méta", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


# ------------------------------------------------------------------ base de données
SCHEMA = """
CREATE TABLE IF NOT EXISTS players (
    player_id TEXT PRIMARY KEY, name TEXT NOT NULL, created REAL NOT NULL, last_seen REAL NOT NULL, banned INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS profiles (
    player_id TEXT PRIMARY KEY, data TEXT NOT NULL, server_bp_xp INTEGER DEFAULT 0, updated REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT NOT NULL, mode TEXT, mission TEXT, victory INTEGER,
    waves INTEGER, kills INTEGER, bp_xp INTEGER, data TEXT, created REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS servers (
    id TEXT PRIMARY KEY, name TEXT, host TEXT, port INTEGER, mode TEXT, players INTEGER, max INTEGER,
    in_game INTEGER, protocol TEXT, last_seen REAL
);
CREATE INDEX IF NOT EXISTS runs_player ON runs(player_id);
CREATE TABLE IF NOT EXISTS friends (
    a TEXT NOT NULL, b TEXT NOT NULL, status TEXT NOT NULL, created REAL NOT NULL, PRIMARY KEY (a, b)
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL, recipient TEXT NOT NULL, text TEXT NOT NULL,
    created REAL NOT NULL, read INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS messages_pair ON messages(sender, recipient);
CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT, kind TEXT NOT NULL, text TEXT NOT NULL,
    context TEXT, created REAL NOT NULL, status TEXT DEFAULT 'nouveau'
);
CREATE TABLE IF NOT EXISTS feedback_comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT, feedback_id INTEGER NOT NULL, player_id TEXT NOT NULL,
    text TEXT NOT NULL, created REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS feedback_comments_fb ON feedback_comments(feedback_id);
CREATE TABLE IF NOT EXISTS feedback_votes (
    feedback_id INTEGER NOT NULL, player_id TEXT NOT NULL, PRIMARY KEY (feedback_id, player_id)
);
"""

# Colonnes ajoutées après la première mise en production : (table, colonne, définition)
MIGRATIONS = [
    ("players", "name_key", "TEXT"),
    ("feedback", "title", "TEXT"),
    ("servers", "owner", "TEXT DEFAULT ''"),
    ("servers", "room", "INTEGER DEFAULT 0"),
    ("servers", "version", "TEXT DEFAULT ''"),
    ("profiles", "last_push_id", "TEXT DEFAULT ''"),
    ("profiles", "last_push", "TEXT DEFAULT ''"),
]


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


@app.on_event("startup")
def _init_db() -> None:
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    with db() as c:
        c.executescript(SCHEMA)
        for table, col, decl in MIGRATIONS:
            cols = [r["name"] for r in c.execute(f"PRAGMA table_info({table})")]
            if col not in cols:
                c.execute(f"ALTER TABLE {table} ADD COLUMN {col} {decl}")
        for r in c.execute("SELECT player_id, name FROM players WHERE name_key IS NULL").fetchall():
            c.execute("UPDATE players SET name_key=? WHERE player_id=?", (name_key(r["name"]), r["player_id"]))
        c.execute("CREATE INDEX IF NOT EXISTS players_name_key ON players(name_key)")


def season() -> dict:
    try:
        return json.loads(SEASON_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"season": 1, "xp_per_tier": 1000, "tiers": [], "xp_sources": {}}


# ------------------------------------------------------------------ authentification
def make_token(player_id: str) -> str:
    sig = hmac.new(TOKEN_SECRET.encode(), player_id.encode(), hashlib.sha256).hexdigest()
    return f"{player_id}.{sig}"


def current_player(authorization: Optional[str] = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Jeton manquant")
    token = authorization[7:]
    player_id, _, _sig = token.partition(".")
    if not player_id or not hmac.compare_digest(make_token(player_id), token):
        raise HTTPException(401, "Jeton invalide")
    with db() as c:
        row = c.execute("SELECT banned FROM players WHERE player_id=?", (player_id,)).fetchone()
        if row is None:
            raise HTTPException(401, "Joueur inconnu")
        if row["banned"]:
            raise HTTPException(403, "Compte suspendu")
        c.execute("UPDATE players SET last_seen=? WHERE player_id=?", (time.time(), player_id))
    return player_id


class GuestLogin(BaseModel):
    player_id: str = Field(min_length=8, max_length=64)
    name: str = Field(min_length=1, max_length=24)


# ------------------------------------------------------------------ pseudos (uniques, insensibles à la casse)
NAME_RE = re.compile(r"^[\w][\w \-.]{1,18}[\w]$")


def name_key(name: str) -> str:
    return " ".join(name.split()).casefold()


def clean_name(name: str) -> str:
    return " ".join(name.split())


def name_taken(c, name: str, player_id: str) -> bool:
    return c.execute("SELECT 1 FROM players WHERE name_key=? AND player_id<>?", (name_key(name), player_id)).fetchone() is not None


def free_name(c, name: str, player_id: str) -> str:
    """Renvoie le pseudo demandé, ou une variante libre (« Turbo » → « Turbo42 »)."""
    name = clean_name(name)[:20] or "Joueur"
    if not name_taken(c, name, player_id):
        return name
    base = name[:16]
    for _ in range(200):
        cand = f"{base}{random.randint(2, 9999)}"
        if not name_taken(c, cand, player_id):
            return cand
    return f"{base}{player_id[:4]}"


class RestoreIn(BaseModel):
    code: str = Field(min_length=8, max_length=80)


@app.post("/api/v1/auth/restore")
def auth_restore(body: RestoreIn):
    """Récupère la sauvegarde cloud sur un autre PC (code de sauvegarde = identifiant du joueur)."""
    pid = body.code.strip().lower().replace("-", "").replace(" ", "")
    with db() as c:
        row = c.execute("SELECT name, banned FROM players WHERE player_id=?", (pid,)).fetchone()
        has = c.execute("SELECT 1 FROM profiles WHERE player_id=? AND data<>'{}'", (pid,)).fetchone()
    if not row or not has:
        raise HTTPException(404, "Aucune sauvegarde ne correspond à ce code.")
    if row["banned"]:
        raise HTTPException(403, "Compte suspendu")
    return {"player_id": pid, "name": row["name"]}


@app.post("/api/v1/auth/guest")
def auth_guest(body: GuestLogin):
    now = time.time()
    with db() as c:
        name = free_name(c, body.name, body.player_id)
        c.execute(
            "INSERT INTO players(player_id, name, name_key, created, last_seen) VALUES(?,?,?,?,?) "
            "ON CONFLICT(player_id) DO UPDATE SET name=excluded.name, name_key=excluded.name_key, last_seen=excluded.last_seen",
            (body.player_id, name, name_key(name), now, now),
        )
    return {"token": make_token(body.player_id), "player_id": body.player_id, "name": name}


class NameIn(BaseModel):
    name: str


@app.post("/api/v1/me/name")
def change_name(body: NameIn, player_id: str = Depends(current_player)):
    name = clean_name(body.name)
    if not NAME_RE.match(name):
        raise HTTPException(422, "Pseudo invalide : 3 à 20 caractères (lettres, chiffres, espace, - _ .)")
    with db() as c:
        if name_taken(c, name, player_id):
            raise HTTPException(409, "Ce pseudo est déjà pris")
        c.execute("UPDATE players SET name=?, name_key=? WHERE player_id=?", (name, name_key(name), player_id))
    return {"name": name}


@app.get("/api/v1/players/name_available")
def name_available(name: str, player_id: str = Depends(current_player)):
    name = clean_name(name)
    with db() as c:
        return {"name": name, "valid": bool(NAME_RE.match(name)), "available": not name_taken(c, name, player_id)}


# ------------------------------------------------------------------ profils
class ProfileIn(BaseModel):
    profile: dict[str, Any]


def _sanitize(profile: dict, server_bp_xp: int) -> dict:
    """Garde-fous anti-triche simples. La progression du battle pass ne peut pas dépasser
    ce que le serveur a comptabilisé via /runs (+ une marge pour les défis et achats de paliers)."""
    s = season()
    max_xp = int(s.get("xp_per_tier", 1000)) * len(s.get("tiers", [])) or 10**9
    bp = profile.get("battlepass", {})
    if isinstance(bp, dict):
        xp = int(bp.get("xp", 0))
        bp["xp"] = max(0, min(xp, max_xp))
    for k in ("puces", "neons"):
        if k in profile:
            profile[k] = max(0, int(profile[k]))
    return profile


# --- fusion des sauvegardes (cloud <-> local, hors ligne, plusieurs PC)
# Le client envoie son profil local et la « base » : la dernière version reçue du serveur.
#  - listes de déblocages (missions, cosmétiques, paliers récupérés) : union ;
#  - records et niveaux : maximum ;
#  - monnaies, XP du battle pass et statistiques cumulées : serveur + (local - base), pour garder
#    à la fois les gains hors ligne et ceux faits ailleurs (sans base connue : maximum) ;
#  - choix (héros, compétences, équipement, défis du jour) : le plus récent gagne (updated_at).
COUNTERS = ("puces", "neons")


def _num(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return default


def _union(a, b) -> list:
    out = list(a) if isinstance(a, list) else []
    for x in (b if isinstance(b, list) else []):
        if x not in out:
            out.append(x)
    return out


def _delta(srv: dict, loc: dict, base, key: str) -> int:
    """Compteur : valeur serveur + ce que le client a gagné ou dépensé depuis la base."""
    sv, lv = _num(srv.get(key)), _num(loc.get(key))
    if isinstance(base, dict):
        return max(0, sv + lv - _num(base.get(key)))
    return max(sv, lv)


def merge_profiles(srv: dict, loc: dict, base: Optional[dict]) -> dict:
    if not srv:
        return dict(loc)
    if not loc:
        return dict(srv)
    has_base = bool(base)
    base = base or {}
    newer, older = (loc, srv) if _num(loc.get("updated_at")) >= _num(srv.get("updated_at")) else (srv, loc)
    out = {**older, **newer}
    # niveau de compte : le plus avancé
    if (_num(srv.get("level"), 1), _num(srv.get("xp"))) >= (_num(loc.get("level"), 1), _num(loc.get("xp"))):
        out["level"], out["xp"] = srv.get("level", 1), srv.get("xp", 0)
    else:
        out["level"], out["xp"] = loc.get("level", 1), loc.get("xp", 0)
    out["skill_points_earned"] = max(_num(srv.get("skill_points_earned"), 1), _num(loc.get("skill_points_earned"), 1))
    for k in COUNTERS:
        if k in srv or k in loc:
            out[k] = _delta(srv, loc, base if has_base else None, k)
    # campagne : missions réussies unies, records au maximum
    sc, lc = srv.get("campaign") or {}, loc.get("campaign") or {}
    camp = {**(older.get("campaign") or {}), **(newer.get("campaign") or {})}
    for k in set(sc) | set(lc):
        a, b = sc.get(k), lc.get(k)
        if isinstance(a, list) or isinstance(b, list):
            camp[k] = _union(a, b)
        elif isinstance(a, (int, float)) or isinstance(b, (int, float)):
            camp[k] = max(_num(a), _num(b))
        elif isinstance(a, dict) and isinstance(b, dict):   # ex. étoiles par mission : le meilleur score
            camp[k] = {kk: max(_num(a.get(kk)), _num(b.get(kk))) for kk in set(a) | set(b)}
    out["campaign"] = camp
    # cosmétiques : déblocages unis, équipement le plus récent
    scos, lcos = srv.get("cosmetics") or {}, loc.get("cosmetics") or {}
    cos = {**(older.get("cosmetics") or {}), **(newer.get("cosmetics") or {})}
    for k in ("hats", "colors", "titles"):
        cos[k] = _union(scos.get(k), lcos.get(k))
    out["cosmetics"] = cos
    # battle pass : même saison -> fusion ; sinon la saison la plus récente
    sb, lb, bb = srv.get("battlepass") or {}, loc.get("battlepass") or {}, base.get("battlepass") or {}
    if _num(sb.get("season")) != _num(lb.get("season")):
        out["battlepass"] = sb if _num(sb.get("season")) > _num(lb.get("season")) else lb
    else:
        bp = {**sb, **lb}
        same_season = bb and _num(bb.get("season"), -1) == _num(sb.get("season"))
        bp["xp"] = _delta(sb, lb, bb if same_season else None, "xp")
        bp["premium"] = bool(sb.get("premium")) or bool(lb.get("premium"))
        for k in ("claimed_free", "claimed_premium"):
            bp[k] = _union(sb.get(k), lb.get(k))
        out["battlepass"] = bp
    # statistiques cumulées
    sl, ll = srv.get("lifetime") or {}, loc.get("lifetime") or {}
    bl = (base.get("lifetime") or {}) if has_base else None
    out["lifetime"] = {k: _delta(sl, ll, bl, k) for k in set(sl) | set(ll)}
    out["updated_at"] = max(_num(srv.get("updated_at")), _num(loc.get("updated_at")))
    if srv.get("player_id"):
        out["player_id"] = srv["player_id"]
    return out


@app.get("/api/v1/profile")
def get_profile(player_id: str = Depends(current_player)):
    with db() as c:
        row = c.execute("SELECT data FROM profiles WHERE player_id=?", (player_id,)).fetchone()
    return {"profile": json.loads(row["data"]) if row else {}}


class SyncIn(BaseModel):
    profile: dict[str, Any]
    base: Optional[dict[str, Any]] = None
    push_id: str = Field("", max_length=64)


@app.post("/api/v1/profile/sync")
def sync_profile(body: SyncIn, player_id: str = Depends(current_player)):
    """Fusionne la sauvegarde locale avec celle du cloud et renvoie le résultat.
    Idempotent : un envoi répété (même push_id, réponse perdue) n'ajoute pas deux fois les gains."""
    with db() as c:
        row = c.execute("SELECT data, server_bp_xp, last_push_id, last_push FROM profiles WHERE player_id=?", (player_id,)).fetchone()
        srv = json.loads(row["data"]) if row and row["data"] else {}
        base = body.base
        if row and body.push_id and row["last_push_id"] == body.push_id and row["last_push"]:
            base = json.loads(row["last_push"])   # déjà intégré : seule la différence depuis cet envoi compte
        merged = _sanitize(merge_profiles(srv, body.profile, base), row["server_bp_xp"] if row else 0)
        c.execute(
            "INSERT INTO profiles(player_id, data, server_bp_xp, updated, last_push_id, last_push) VALUES(?,?,0,?,?,?) "
            "ON CONFLICT(player_id) DO UPDATE SET data=excluded.data, updated=excluded.updated, "
            "last_push_id=excluded.last_push_id, last_push=excluded.last_push",
            (player_id, json.dumps(merged), time.time(), body.push_id, json.dumps(body.profile)),
        )
    return {"profile": merged}


@app.put("/api/v1/profile")
def put_profile(body: ProfileIn, player_id: str = Depends(current_player)):
    with db() as c:
        row = c.execute("SELECT server_bp_xp FROM profiles WHERE player_id=?", (player_id,)).fetchone()
        server_xp = row["server_bp_xp"] if row else 0
        old = c.execute("SELECT data FROM profiles WHERE player_id=?", (player_id,)).fetchone()
        data = _sanitize(merge_profiles(json.loads(old["data"]) if old and old["data"] else {}, body.profile, None), server_xp)
        c.execute(
            "INSERT INTO profiles(player_id, data, server_bp_xp, updated) VALUES(?,?,?,?) "
            "ON CONFLICT(player_id) DO UPDATE SET data=excluded.data, updated=excluded.updated",
            (player_id, json.dumps(data), server_xp, time.time()),
        )
    return {"ok": True}


# ------------------------------------------------------------------ parties
class RunIn(BaseModel):
    mode: str = "campaign"
    mission: str = ""
    victory: bool = False
    waves: int = 0
    kills: int = 0
    bosses: int = 0
    pvp_rounds: int = 0
    pvp_win: bool = False
    coop: bool = False

    model_config = {"extra": "allow"}


def compute_bp_xp(r: RunIn) -> int:
    src = season().get("xp_sources", {})
    xp = r.waves * src.get("wave", 40) + r.kills * src.get("kill", 1) + r.bosses * src.get("boss", 300)
    if r.victory:
        xp += src.get("victory", 400)
    xp += r.pvp_rounds * src.get("pvp_round_win", 120)
    if r.pvp_win:
        xp += src.get("pvp_match_win", 400)
    if r.coop:
        xp = int(xp * (1 + src.get("coop_bonus_pct", 20) / 100))
    return xp


@app.post("/api/v1/runs")
def post_run(body: RunIn, player_id: str = Depends(current_player)):
    if body.waves > 500 or body.kills > 100000:
        raise HTTPException(400, "Résultat de partie invraisemblable")
    xp = compute_bp_xp(body)
    now = time.time()
    with db() as c:
        c.execute(
            "INSERT INTO runs(player_id, mode, mission, victory, waves, kills, bp_xp, data, created) VALUES(?,?,?,?,?,?,?,?,?)",
            (player_id, body.mode, body.mission, int(body.victory), body.waves, body.kills, xp, body.model_dump_json(), now),
        )
        c.execute(
            "INSERT INTO profiles(player_id, data, server_bp_xp, updated) VALUES(?, '{}', ?, ?) "
            "ON CONFLICT(player_id) DO UPDATE SET server_bp_xp = server_bp_xp + ?",
            (player_id, xp, now, xp),
        )
    return {"bp_xp": xp}


@app.get("/api/v1/leaderboard")
def leaderboard(mode: str = "endless", limit: int = 20):
    limit = max(1, min(limit, 100))
    with db() as c:
        rows = c.execute(
            "SELECT p.name, MAX(r.waves) AS best, SUM(r.kills) AS kills FROM runs r JOIN players p USING(player_id) "
            "WHERE r.mode=? GROUP BY r.player_id ORDER BY best DESC, kills DESC LIMIT ?",
            (mode, limit),
        ).fetchall()
    return {"mode": mode, "entries": [dict(r) for r in rows]}


@app.get("/api/v1/season")
def get_season():
    return season()


# ------------------------------------------------------------------ serveurs de jeu
class Heartbeat(BaseModel):
    id: str
    name: str = "Cybervor"
    host: str = ""
    port: int = 7777
    mode: str = "coop"
    players: int = 0
    max: int = 4
    in_game: bool = False
    protocol: str = PROTOCOL
    owner: str = ""
    room: bool = False
    version: str = ""


@app.post("/api/v1/servers/heartbeat")
def heartbeat(body: Heartbeat, x_server_secret: Optional[str] = Header(None)):
    if not x_server_secret or not hmac.compare_digest(x_server_secret, SERVER_SECRET):
        raise HTTPException(403, "Secret serveur invalide")
    with db() as c:
        c.execute(
            "INSERT INTO servers(id, name, host, port, mode, players, max, in_game, protocol, last_seen, owner, room, version) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT(id) DO UPDATE SET name=excluded.name, host=excluded.host, port=excluded.port, mode=excluded.mode, "
            "players=excluded.players, max=excluded.max, in_game=excluded.in_game, protocol=excluded.protocol, last_seen=excluded.last_seen, "
            "owner=excluded.owner, room=excluded.room, version=excluded.version",
            (body.id, body.name, body.host, body.port, body.mode, body.players, body.max, int(body.in_game), body.protocol, time.time(),
             body.owner, int(body.room), body.version),
        )
        # une partie fermée libère son port : on oublie les anciennes entrées sur le même port
        c.execute("DELETE FROM servers WHERE port=? AND host=? AND id<>?", (body.port, body.host, body.id))
    return {"ok": True}


def _live_servers() -> list[dict]:
    with db() as c:
        rows = c.execute("SELECT * FROM servers WHERE last_seen > ? ORDER BY mode, name", (time.time() - SERVER_TTL,)).fetchall()
    out = []
    for r in rows:
        d = dict(r) | {"in_game": bool(r["in_game"]), "room": bool(r["room"])}
        if d["owner"]:
            with db() as c:
                o = c.execute("SELECT name FROM players WHERE player_id=?", (d["owner"],)).fetchone()
            d["owner_name"] = o["name"] if o else ""
        d.pop("owner")
        out.append(d)
    return out


def _running_rooms() -> Optional[set]:
    """Ports des parties réellement en cours selon le superviseur (None s'il ne répond pas)."""
    if not ROOMS_URL:
        return None
    import urllib.request
    try:
        with urllib.request.urlopen(ROOMS_URL.rstrip("/") + "/rooms", timeout=2) as r:
            return {int(x["port"]) for x in json.loads(r.read()).get("rooms", [])}
    except (OSError, ValueError, KeyError):
        return None


@app.get("/api/v1/servers")
def list_servers():
    running = _running_rooms()
    return {"servers": [s for s in _live_servers() if s["protocol"] == PROTOCOL
                        and (not s["room"] or running is None or s["port"] in running)]}


class RoomIn(BaseModel):
    mode: str = Field("coop", pattern="^(coop|pvp)$")
    name: str = Field("", max_length=40)
    max: int = Field(4, ge=1, le=4)
    version: str = Field("", max_length=20)


@app.post("/api/v1/rooms")
def create_room(body: RoomIn, player_id: str = Depends(current_player)):
    """Crée une partie sur le serveur unique : le superviseur lance une instance dédiée sur un port libre."""
    if not ROOMS_URL:
        raise HTTPException(503, "La création de parties n'est pas disponible sur ce serveur.")
    import urllib.error
    import urllib.request
    with db() as c:
        row = c.execute("SELECT name FROM players WHERE player_id=?", (player_id,)).fetchone()
    name = body.name.strip() or f"Partie de {row['name'] if row else 'Inconnu'}"
    req = urllib.request.Request(ROOMS_URL.rstrip("/") + "/rooms", method="POST", headers={"Content-Type": "application/json"},
                                 data=json.dumps({"mode": body.mode, "name": name, "owner": player_id, "max": body.max, "version": body.version}).encode())
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            room = json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            detail = json.loads(e.read()).get("detail", "")
        except Exception:  # noqa: BLE001
            detail = ""
        raise HTTPException(503, detail or "Impossible de créer la partie.")
    except OSError:
        raise HTTPException(503, "Le gestionnaire de parties ne répond pas.")
    return room


class MatchRequest(BaseModel):
    mode: str = "coop"
    player_id: str = ""
    version: str = ""


@app.post("/api/v1/matchmaking")
def matchmaking(body: MatchRequest):
    candidates = [s for s in _live_servers() if s["mode"] == body.mode and not s["in_game"] and s["players"] < s["max"] and s["protocol"] == PROTOCOL
                  and (not body.version or not s.get("version") or s["version"] == body.version)]
    if not candidates:
        raise HTTPException(404, "Aucun serveur disponible pour ce mode")
    # On remplit d'abord les salons déjà entamés.
    best = max(candidates, key=lambda s: s["players"])
    return {"host": best["host"], "port": best["port"], "name": best["name"]}


# ------------------------------------------------------------------ social : amis
ONLINE_WINDOW = 120  # secondes


def friend_code(player_id: str) -> str:
    """Code ami court et stable, dérivé de l'identifiant (ex. « K7Q2-9XMB »)."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    h = int(hashlib.sha256(("ami:" + player_id).encode()).hexdigest(), 16)
    chars = "".join(alphabet[(h >> (5 * i)) & 31] for i in range(8))
    return chars[:4] + "-" + chars[4:]


def _find_by_code(c, code: str) -> Optional[str]:
    code = code.strip().upper()
    for row in c.execute("SELECT player_id FROM players"):
        if friend_code(row["player_id"]) == code:
            return row["player_id"]
    return None


@app.get("/api/v1/me")
def me(player_id: str = Depends(current_player)):
    with db() as c:
        row = c.execute("SELECT name FROM players WHERE player_id=?", (player_id,)).fetchone()
    return {"player_id": player_id, "name": row["name"], "friend_code": friend_code(player_id)}


@app.get("/api/v1/friends")
def list_friends(player_id: str = Depends(current_player)):
    now = time.time()
    out = []
    with db() as c:
        rows = c.execute(
            "SELECT f.a, f.b, f.status, p.player_id AS other, p.name, p.last_seen FROM friends f "
            "JOIN players p ON p.player_id = CASE WHEN f.a=? THEN f.b ELSE f.a END WHERE f.a=? OR f.b=?",
            (player_id, player_id, player_id),
        ).fetchall()
        for r in rows:
            if r["status"] == "accepted":
                status = "accepted"
            else:
                status = "outgoing" if r["a"] == player_id else "incoming"
            unread_n = c.execute("SELECT COUNT(*) FROM messages WHERE sender=? AND recipient=? AND read=0", (r["other"], player_id)).fetchone()[0]
            out.append({"player_id": r["other"], "name": r["name"], "friend_code": friend_code(r["other"]), "status": status,
                        "online": now - r["last_seen"] < ONLINE_WINDOW, "unread": unread_n})
    out.sort(key=lambda f: (f["status"] != "incoming", not f["online"], f["name"].lower()))
    return {"friends": out, "my_code": friend_code(player_id)}


class FriendRequest(BaseModel):
    code: str = ""
    player_id: str = ""
    name: str = ""


@app.post("/api/v1/friends/request")
def friend_request(body: FriendRequest, player_id: str = Depends(current_player)):
    with db() as c:
        other = body.player_id or (_find_by_code(c, body.code) if body.code else None)
        if not other and body.name.strip():
            rows = c.execute("SELECT player_id FROM players WHERE name_key=?", (name_key(body.name),)).fetchall()
            if len(rows) > 1:
                raise HTTPException(409, "Plusieurs joueurs portent ce pseudo : utilisez son code ami")
            other = rows[0]["player_id"] if rows else None
            if not other:
                raise HTTPException(404, "Aucun joueur avec ce pseudo")
        if not other or not c.execute("SELECT 1 FROM players WHERE player_id=?", (other,)).fetchone():
            raise HTTPException(404, "Aucun joueur avec ce code ami")
        if other == player_id:
            raise HTTPException(400, "Vous ne pouvez pas vous ajouter vous-même (même si vous êtes génial)")
        existing = c.execute("SELECT a, status FROM friends WHERE (a=? AND b=?) OR (a=? AND b=?)", (player_id, other, other, player_id)).fetchone()
        if existing:
            if existing["status"] == "pending" and existing["a"] == other:
                c.execute("UPDATE friends SET status='accepted' WHERE a=? AND b=?", (other, player_id))
                return {"status": "accepted"}
            return {"status": existing["status"]}
        c.execute("INSERT INTO friends(a, b, status, created) VALUES(?,?, 'pending', ?)", (player_id, other, time.time()))
    return {"status": "pending"}


class FriendTarget(BaseModel):
    player_id: str


@app.post("/api/v1/friends/accept")
def friend_accept(body: FriendTarget, player_id: str = Depends(current_player)):
    with db() as c:
        cur = c.execute("UPDATE friends SET status='accepted' WHERE a=? AND b=? AND status='pending'", (body.player_id, player_id))
        if cur.rowcount == 0:
            raise HTTPException(404, "Demande introuvable")
    return {"status": "accepted"}


@app.post("/api/v1/friends/remove")
def friend_remove(body: FriendTarget, player_id: str = Depends(current_player)):
    with db() as c:
        c.execute("DELETE FROM friends WHERE (a=? AND b=?) OR (a=? AND b=?)", (player_id, body.player_id, body.player_id, player_id))
    return {"ok": True}


def _are_friends(c, x: str, y: str) -> bool:
    return c.execute("SELECT 1 FROM friends WHERE status='accepted' AND ((a=? AND b=?) OR (a=? AND b=?))", (x, y, y, x)).fetchone() is not None


# ------------------------------------------------------------------ social : messagerie
class MessageIn(BaseModel):
    to: str
    text: str = Field(min_length=1, max_length=500)


@app.post("/api/v1/messages")
def send_message(body: MessageIn, player_id: str = Depends(current_player)):
    now = time.time()
    with db() as c:
        if not _are_friends(c, player_id, body.to):
            raise HTTPException(403, "Vous devez être amis pour discuter")
        recent = c.execute("SELECT COUNT(*) FROM messages WHERE sender=? AND created > ?", (player_id, now - 60)).fetchone()[0]
        if recent >= 30:
            raise HTTPException(429, "Doucement ! Trop de messages en une minute")
        cur = c.execute("INSERT INTO messages(sender, recipient, text, created) VALUES(?,?,?,?)", (player_id, body.to, body.text.strip(), now))
    return {"id": cur.lastrowid}


@app.get("/api/v1/messages")
def get_messages(with_player: str, since: int = 0, player_id: str = Depends(current_player)):
    with db() as c:
        if not _are_friends(c, player_id, with_player):
            raise HTTPException(403, "Vous devez être amis pour discuter")
        rows = c.execute(
            "SELECT id, sender, recipient, text, created FROM messages WHERE id > ? AND "
            "((sender=? AND recipient=?) OR (sender=? AND recipient=?)) ORDER BY id DESC LIMIT 100",
            (since, player_id, with_player, with_player, player_id),
        ).fetchall()
        c.execute("UPDATE messages SET read=1 WHERE sender=? AND recipient=?", (with_player, player_id))
    return {"messages": [dict(r) | {"mine": r["sender"] == player_id} for r in reversed(rows)]}


@app.get("/api/v1/messages/unread")
def unread(player_id: str = Depends(current_player)):
    with db() as c:
        rows = c.execute(
            "SELECT m.sender, p.name, COUNT(*) AS n, MAX(m.id) AS last FROM messages m JOIN players p ON p.player_id=m.sender "
            "WHERE m.recipient=? AND m.read=0 GROUP BY m.sender", (player_id,)).fetchall()
        pending = c.execute("SELECT COUNT(*) FROM friends WHERE b=? AND status='pending'", (player_id,)).fetchone()[0]
    return {"unread": [dict(r) for r in rows], "friend_requests": pending}


# ------------------------------------------------------------------ retours : bugs & suggestions
class FeedbackIn(BaseModel):
    kind: str = Field(pattern="^(bug|suggestion)$")
    title: str = Field("", max_length=90)
    text: str = Field(min_length=3, max_length=4000)
    context: dict[str, Any] = {}


@app.post("/api/v1/feedback")
def post_feedback(body: FeedbackIn, authorization: Optional[str] = Header(None)):
    player_id = None
    if authorization:
        try:
            player_id = current_player(authorization)
        except HTTPException:
            player_id = None
    with db() as c:
        recent = c.execute("SELECT COUNT(*) FROM feedback WHERE player_id IS ? AND created > ?", (player_id, time.time() - 3600)).fetchone()[0]
        if player_id and recent >= 20:
            raise HTTPException(429, "Merci ! Mais ça fait beaucoup de retours pour une heure")
        title = body.title.strip() or _auto_title(body.text)
        cur = c.execute("INSERT INTO feedback(player_id, kind, title, text, context, created) VALUES(?,?,?,?,?,?)",
                        (player_id, body.kind, title, body.text, json.dumps(body.context)[:20000], time.time()))
        if player_id:
            c.execute("INSERT OR IGNORE INTO feedback_votes(feedback_id, player_id) VALUES(?,?)", (cur.lastrowid, player_id))
    return {"id": cur.lastrowid}


def _auto_title(text: str) -> str:
    first = " ".join(text.strip().split())
    return first if len(first) <= 70 else first[:67].rstrip() + "…"


def _optional_player(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    try:
        return current_player(authorization)
    except HTTPException:
        return None


FEEDBACK_STATUSES = ("nouveau", "confirmé", "en cours", "corrigé", "refusé", "doublon")
FEEDBACK_PUBLIC = (
    "SELECT f.id, f.kind, COALESCE(f.title, '') AS title, f.text, f.created, f.status, COALESCE(p.name, 'Anonyme') AS author, "
    "(SELECT COUNT(*) FROM feedback_votes v WHERE v.feedback_id=f.id) AS votes, "
    "(SELECT COUNT(*) FROM feedback_comments m WHERE m.feedback_id=f.id) AS comments, "
    "EXISTS(SELECT 1 FROM feedback_votes v WHERE v.feedback_id=f.id AND v.player_id=?) AS voted "
    "FROM feedback f LEFT JOIN players p USING(player_id)"
)


@app.get("/api/v1/feedback")
def list_public_feedback(q: str = "", kind: str = "", sort: str = "votes", limit: int = 50, offset: int = 0,
                         authorization: Optional[str] = Header(None)):
    """Liste publique des bugs et suggestions (sans les informations techniques), avec recherche."""
    me = _optional_player(authorization)
    where, args = [], [me or ""]
    if kind in ("bug", "suggestion"):
        where.append("f.kind=?")
        args.append(kind)
    for word in q.split()[:6]:
        where.append("(f.title LIKE ? OR f.text LIKE ?)")
        args += [f"%{word}%", f"%{word}%"]
    sql = FEEDBACK_PUBLIC + (" WHERE " + " AND ".join(where) if where else "")
    sql += " ORDER BY votes DESC, f.id DESC" if sort == "votes" else " ORDER BY f.id DESC"
    sql += " LIMIT ? OFFSET ?"
    args += [max(1, min(limit, 100)), max(0, offset)]
    with db() as c:
        rows = c.execute(sql, args).fetchall()
    return {"feedback": [dict(r) | {"voted": bool(r["voted"]), "text": r["text"][:300]} for r in rows]}


@app.get("/api/v1/feedback/{fid}")
def get_feedback(fid: int, authorization: Optional[str] = Header(None)):
    me = _optional_player(authorization)
    with db() as c:
        row = c.execute(FEEDBACK_PUBLIC + " WHERE f.id=?", (me or "", fid)).fetchone()
        if row is None:
            raise HTTPException(404, "Retour introuvable")
        comments = c.execute(
            "SELECT m.id, m.text, m.created, COALESCE(p.name, '?') AS author, m.player_id=? AS mine "
            "FROM feedback_comments m LEFT JOIN players p USING(player_id) WHERE m.feedback_id=? ORDER BY m.id",
            (me or "", fid)).fetchall()
    return dict(row) | {"voted": bool(row["voted"]), "comments_list": [dict(m) | {"mine": bool(m["mine"])} for m in comments]}


class CommentIn(BaseModel):
    text: str = Field(min_length=2, max_length=1000)


@app.post("/api/v1/feedback/{fid}/comments")
def comment_feedback(fid: int, body: CommentIn, player_id: str = Depends(current_player)):
    now = time.time()
    with db() as c:
        if not c.execute("SELECT 1 FROM feedback WHERE id=?", (fid,)).fetchone():
            raise HTTPException(404, "Retour introuvable")
        recent = c.execute("SELECT COUNT(*) FROM feedback_comments WHERE player_id=? AND created > ?", (player_id, now - 600)).fetchone()[0]
        if recent >= 20:
            raise HTTPException(429, "Doucement ! Trop de commentaires en peu de temps")
        cur = c.execute("INSERT INTO feedback_comments(feedback_id, player_id, text, created) VALUES(?,?,?,?)",
                        (fid, player_id, body.text.strip(), now))
    return {"id": cur.lastrowid}


@app.post("/api/v1/feedback/{fid}/vote")
def vote_feedback(fid: int, player_id: str = Depends(current_player)):
    """« Moi aussi » / « +1 » : bascule le vote du joueur."""
    with db() as c:
        if not c.execute("SELECT 1 FROM feedback WHERE id=?", (fid,)).fetchone():
            raise HTTPException(404, "Retour introuvable")
        if c.execute("SELECT 1 FROM feedback_votes WHERE feedback_id=? AND player_id=?", (fid, player_id)).fetchone():
            c.execute("DELETE FROM feedback_votes WHERE feedback_id=? AND player_id=?", (fid, player_id))
            voted = False
        else:
            c.execute("INSERT INTO feedback_votes(feedback_id, player_id) VALUES(?,?)", (fid, player_id))
            voted = True
        votes = c.execute("SELECT COUNT(*) FROM feedback_votes WHERE feedback_id=?", (fid,)).fetchone()[0]
    return {"voted": voted, "votes": votes}


class StatusIn(BaseModel):
    status: str


@app.post("/api/v1/admin/feedback/{fid}/status")
def set_feedback_status(fid: int, body: StatusIn, x_admin_secret: Optional[str] = Header(None)):
    if not ADMIN_SECRET or not x_admin_secret or not hmac.compare_digest(x_admin_secret, ADMIN_SECRET):
        raise HTTPException(403, "Accès administrateur requis")
    if body.status not in FEEDBACK_STATUSES:
        raise HTTPException(422, "Statut inconnu : " + ", ".join(FEEDBACK_STATUSES))
    with db() as c:
        c.execute("UPDATE feedback SET status=? WHERE id=?", (body.status, fid))
    return {"status": body.status}


@app.get("/api/v1/admin/feedback")
def list_feedback(kind: str = "", limit: int = 100, x_admin_secret: Optional[str] = Header(None)):
    if not ADMIN_SECRET or not x_admin_secret or not hmac.compare_digest(x_admin_secret, ADMIN_SECRET):
        raise HTTPException(403, "Accès administrateur requis")
    with db() as c:
        q = "SELECT f.*, p.name FROM feedback f LEFT JOIN players p USING(player_id)"
        args: list = []
        if kind:
            q += " WHERE f.kind=?"
            args.append(kind)
        rows = c.execute(q + " ORDER BY f.id DESC LIMIT ?", (*args, max(1, min(limit, 500)))).fetchall()
    return {"feedback": [dict(r) | {"context": json.loads(r["context"] or "{}")} for r in rows]}


@app.get("/health")
def health():
    return {"ok": True, "servers": len(_live_servers())}
