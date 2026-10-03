"""Tests de l'API méta : python -m pytest server/meta-api -q"""
import os
import tempfile

os.environ["CYBERVOR_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["CYBERVOR_SERVER_SECRET"] = "s3cret"
os.environ["CYBERVOR_ADMIN_SECRET"] = "adm1n"

from fastapi.testclient import TestClient  # noqa: E402

import app as meta  # noqa: E402

meta._init_db()  # création du schéma (normalement faite au démarrage du serveur)
client = TestClient(meta.app)

PID = "abcdef0123456789"


def _auth():
    r = client.post("/api/v1/auth/guest", json={"player_id": PID, "name": "Testeur"})
    assert r.status_code == 200
    return {"Authorization": "Bearer " + r.json()["token"]}


def test_profile_roundtrip():
    h = _auth()
    assert client.get("/api/v1/profile", headers=h).json() == {"profile": {}}
    prof = {"level": 3, "puces": -50, "neons": 10, "battlepass": {"xp": 99999999}}
    assert client.put("/api/v1/profile", json={"profile": prof}, headers=h).status_code == 200
    got = client.get("/api/v1/profile", headers=h).json()["profile"]
    assert got["puces"] == 0                     # valeurs négatives refusées
    assert got["battlepass"]["xp"] <= 40 * 1000  # plafonné au maximum de la saison


def test_bad_token():
    r = client.get("/api/v1/profile", headers={"Authorization": "Bearer " + PID + ".faux"})
    assert r.status_code == 401


def test_runs_and_leaderboard():
    h = _auth()
    r = client.post("/api/v1/runs", json={"mode": "endless", "waves": 12, "kills": 300, "bosses": 2}, headers=h)
    assert r.status_code == 200 and r.json()["bp_xp"] > 0
    lb = client.get("/api/v1/leaderboard?mode=endless").json()
    assert lb["entries"][0]["best"] == 12


def test_servers_and_matchmaking():
    hb = {"id": "srv-1", "name": "Coop FR", "host": "1.2.3.4", "port": 7777, "mode": "coop", "players": 1, "max": 4}
    assert client.post("/api/v1/servers/heartbeat", json=hb).status_code == 403
    assert client.post("/api/v1/servers/heartbeat", json=hb, headers={"X-Server-Secret": "s3cret"}).status_code == 200
    servers = client.get("/api/v1/servers").json()["servers"]
    assert servers[0]["name"] == "Coop FR"
    mm = client.post("/api/v1/matchmaking", json={"mode": "coop"}).json()
    assert mm["host"] == "1.2.3.4" and mm["port"] == 7777
    assert client.post("/api/v1/matchmaking", json={"mode": "pvp"}).status_code == 404


def test_season():
    s = client.get("/api/v1/season").json()
    assert s["season"] == 1 and len(s["tiers"]) == 40


def _login(pid, name):
    r = client.post("/api/v1/auth/guest", json={"player_id": pid, "name": name})
    return {"Authorization": "Bearer " + r.json()["token"]}


def test_friends_and_messages():
    ha = _login("aaaaaaaaaaaa0001", "Alice")
    hb = _login("bbbbbbbbbbbb0002", "Bob")
    code_b = client.get("/api/v1/me", headers=hb).json()["friend_code"]
    assert client.post("/api/v1/messages", json={"to": "bbbbbbbbbbbb0002", "text": "salut"}, headers=ha).status_code == 403
    assert client.post("/api/v1/friends/request", json={"code": code_b}, headers=ha).json()["status"] == "pending"
    fb = client.get("/api/v1/friends", headers=hb).json()["friends"]
    assert fb[0]["status"] == "incoming" and fb[0]["name"] == "Alice"
    assert client.get("/api/v1/messages/unread", headers=hb).json()["friend_requests"] == 1
    assert client.post("/api/v1/friends/accept", json={"player_id": "aaaaaaaaaaaa0001"}, headers=hb).status_code == 200
    assert client.post("/api/v1/messages", json={"to": "bbbbbbbbbbbb0002", "text": "On fait une partie ?"}, headers=ha).status_code == 200
    un = client.get("/api/v1/messages/unread", headers=hb).json()["unread"]
    assert un[0]["name"] == "Alice" and un[0]["n"] == 1
    msgs = client.get("/api/v1/messages?with_player=aaaaaaaaaaaa0001", headers=hb).json()["messages"]
    assert msgs[0]["text"] == "On fait une partie ?" and not msgs[0]["mine"]
    assert client.get("/api/v1/messages/unread", headers=hb).json()["unread"] == []
    assert client.post("/api/v1/friends/request", json={"code": "ZZZZ-ZZZZ"}, headers=ha).status_code == 404


def test_feedback():
    ha = _login("aaaaaaaaaaaa0001", "Alice")
    assert client.post("/api/v1/feedback", json={"kind": "bug", "text": "Le boss est trop fort", "context": {"mode": "campaign"}}, headers=ha).status_code == 200
    assert client.post("/api/v1/feedback", json={"kind": "suggestion", "text": "Plus de chapeaux !"}).status_code == 200
    assert client.post("/api/v1/feedback", json={"kind": "autre", "text": "xxx"}).status_code == 422
    assert client.get("/api/v1/admin/feedback").status_code == 403
    fb = client.get("/api/v1/admin/feedback", headers={"X-Admin-Secret": "adm1n"}).json()["feedback"]
    assert len(fb) == 2 and fb[1]["name"] == "Alice"


def test_unique_names_and_friend_by_name():
    h1 = _login("cccccccccccc0003", "Zorglub")
    r = client.post("/api/v1/auth/guest", json={"player_id": "dddddddddddd0004", "name": "zorglub"})
    assert r.json()["name"] != "zorglub" and r.json()["name"].startswith("zorglub")  # pseudo déjà pris -> variante
    h2 = {"Authorization": "Bearer " + r.json()["token"]}
    assert client.post("/api/v1/me/name", json={"name": "ZORGLUB"}, headers=h2).status_code == 409
    assert client.post("/api/v1/me/name", json={"name": "x"}, headers=h2).status_code == 422
    assert client.post("/api/v1/me/name", json={"name": "Grand Zorg"}, headers=h2).json()["name"] == "Grand Zorg"
    assert client.get("/api/v1/players/name_available?name=grand%20zorg", headers=h1).json()["available"] is False
    # ajout d'ami par pseudo (insensible à la casse), sans code
    assert client.post("/api/v1/friends/request", json={"name": "grand zorg"}, headers=h1).json()["status"] == "pending"
    assert client.post("/api/v1/friends/request", json={"name": "Personne Inconnue"}, headers=h1).status_code == 404
    fr = client.get("/api/v1/friends", headers=h2).json()["friends"]
    assert fr[0]["name"] == "Zorglub" and fr[0]["status"] == "incoming"


def test_feedback_community():
    ha = _login("eeeeeeeeeeee0005", "Alpha")
    hb = _login("ffffffffffff0006", "Bravo")
    fid = client.post("/api/v1/feedback", json={"kind": "bug", "title": "Le laser traverse les murs",
                                                "text": "Le pistolaser tire à travers les murs de la zone 2", "context": {"gpu": "secret"}},
                      headers=ha).json()["id"]
    client.post("/api/v1/feedback", json={"kind": "suggestion", "text": "Ajouter un mode chapeau géant"}, headers=hb)
    lst = client.get("/api/v1/feedback?q=laser", headers=hb).json()["feedback"]
    assert len(lst) == 1 and lst[0]["id"] == fid and lst[0]["votes"] == 1 and lst[0]["voted"] is False
    assert "context" not in lst[0]   # les infos techniques restent privées
    assert client.get("/api/v1/feedback?kind=suggestion").json()["feedback"][0]["title"] == "Ajouter un mode chapeau géant"
    v = client.post(f"/api/v1/feedback/{fid}/vote", headers=hb).json()
    assert v == {"voted": True, "votes": 2}
    assert client.post(f"/api/v1/feedback/{fid}/comments", json={"text": "Pareil chez moi, avec le railgun aussi"}, headers=hb).status_code == 200
    assert client.post(f"/api/v1/feedback/{fid}/comments", json={"text": "anonyme"}).status_code == 401
    d = client.get(f"/api/v1/feedback/{fid}", headers=hb).json()
    assert d["comments"] == 1 and d["comments_list"][0]["author"] == "Bravo" and d["comments_list"][0]["mine"] and d["voted"]
    assert client.post(f"/api/v1/feedback/{fid}/vote", headers=hb).json() == {"voted": False, "votes": 1}
    assert client.post(f"/api/v1/admin/feedback/{fid}/status", json={"status": "corrigé"}, headers={"X-Admin-Secret": "adm1n"}).status_code == 200
    assert client.get(f"/api/v1/feedback/{fid}").json()["status"] == "corrigé"
    assert client.get("/api/v1/feedback/99999").status_code == 404


def test_migration_from_v1_schema():
    import sqlite3
    path = os.path.join(tempfile.mkdtemp(), "old.db")
    con = sqlite3.connect(path)
    con.executescript("CREATE TABLE players (player_id TEXT PRIMARY KEY, name TEXT NOT NULL, created REAL NOT NULL, last_seen REAL NOT NULL, banned INTEGER DEFAULT 0);"
                      "CREATE TABLE feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT, kind TEXT NOT NULL, text TEXT NOT NULL, context TEXT, created REAL NOT NULL, status TEXT DEFAULT 'nouveau');"
                      "INSERT INTO players VALUES ('old0000000000001', 'Ancien Joueur', 0, 0, 0);")
    con.commit()
    con.close()
    old, meta.DB_PATH = meta.DB_PATH, path
    try:
        meta._init_db()
        with meta.db() as c:
            assert c.execute("SELECT name_key FROM players").fetchone()[0] == "ancien joueur"
            assert "title" in [r["name"] for r in c.execute("PRAGMA table_info(feedback)")]
    finally:
        meta.DB_PATH = old


def test_rooms_created_by_players(monkeypatch):
    """Un joueur crée sa partie via le superviseur ; une partie fermée disparaît aussitôt de la liste."""
    h = _auth()
    monkeypatch.setattr(meta, "ROOMS_URL", "")
    assert client.post("/api/v1/rooms", json={"mode": "coop"}, headers=h).status_code == 503
    assert client.post("/api/v1/rooms", json={"mode": "coop"}).status_code == 401
    assert client.post("/api/v1/rooms", json={"mode": "foot"}, headers=h).status_code == 422

    import io
    import json as _json
    import urllib.request
    running = {7820}
    calls = []

    def fake_urlopen(req, timeout=0):
        url = req if isinstance(req, str) else req.full_url
        if url.endswith("/rooms") and not isinstance(req, str) and req.data:
            calls.append(_json.loads(req.data))
            return io.BytesIO(_json.dumps({"id": "room-7820", "host": "h", "port": 7820, "mode": "coop", "name": calls[-1]["name"]}).encode())
        return io.BytesIO(_json.dumps({"rooms": [{"port": p} for p in running]}).encode())

    monkeypatch.setattr(meta, "ROOMS_URL", "http://rooms:9000")
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    r = client.post("/api/v1/rooms", json={"mode": "coop"}, headers=h)
    assert r.status_code == 200 and r.json()["port"] == 7820
    assert calls[-1]["owner"] == PID and calls[-1]["name"].startswith("Partie de ")
    hb = {"id": "room-7820", "name": "Partie de Testeur", "host": "h", "port": 7820, "owner": PID, "room": True}
    assert client.post("/api/v1/servers/heartbeat", json=hb, headers={"X-Server-Secret": "s3cret"}).status_code == 200
    listed = [s for s in client.get("/api/v1/servers").json()["servers"] if s["id"] == "room-7820"]
    assert listed and listed[0]["owner_name"] and "owner" not in listed[0]
    running.clear()   # l'instance s'est arrêtée (partie vide)
    assert not [s for s in client.get("/api/v1/servers").json()["servers"] if s["id"] == "room-7820"]


def _prof(**kw):
    p = {"level": 1, "xp": 0, "skill_points_earned": 1, "puces": 200, "neons": 0, "character": "patatron",
         "campaign": {"completed": [], "best_endless": 0},
         "cosmetics": {"hats": [], "colors": [], "titles": [], "hat": "", "color": "", "title": ""},
         "battlepass": {"season": 1, "xp": 0, "premium": False, "claimed_free": [], "claimed_premium": []},
         "lifetime": {}, "updated_at": 1000}
    for k, v in kw.items():
        p[k] = v
    return p


def test_cloud_sync_offline_and_two_pcs():
    r = client.post("/api/v1/auth/guest", json={"player_id": "5e1f0a2b3c4d5e6f", "name": "Synchro"})
    h = {"Authorization": "Bearer " + r.json()["token"]}
    sync = lambda prof, base, pid: client.post("/api/v1/profile/sync", json={"profile": prof, "base": base, "push_id": pid}, headers=h).json()["profile"]

    # 1) première synchro (aucune sauvegarde cloud) : le profil local devient la sauvegarde
    p1 = _prof(campaign={"completed": ["z1_m1"], "best_endless": 4}, puces=300)
    cloud = sync(p1, None, "a1")
    assert cloud["campaign"]["completed"] == ["z1_m1"] and cloud["puces"] == 300

    # 2) PC A joue hors ligne (gagne 2 missions, +150 puces, dépense 40), PC B joue en ligne entre-temps
    pc_a = _prof(campaign={"completed": ["z1_m1", "z1_m2", "z1_m3"], "best_endless": 4}, puces=410, updated_at=2000,
                 character="volta", lifetime={"kills": 50})
    pc_b = _prof(campaign={"completed": ["z1_m1", "z2_m1"], "best_endless": 9}, puces=350, updated_at=1500,
                 cosmetics={"hats": ["fez"], "colors": [], "titles": [], "hat": "fez", "color": "", "title": ""},
                 lifetime={"kills": 30})
    cloud = sync(pc_b, cloud, "b1")
    assert cloud["puces"] == 350
    # 3) PC A revient en ligne : rien n'est perdu d'un côté ni de l'autre
    merged = sync(pc_a, p1, "a2")
    assert set(merged["campaign"]["completed"]) == {"z1_m1", "z1_m2", "z1_m3", "z2_m1"}
    assert merged["campaign"]["best_endless"] == 9
    assert merged["puces"] == 300 + 50 + 110          # base 300 ; B : +50 ; A : +110
    assert merged["cosmetics"]["hats"] == ["fez"]
    assert merged["character"] == "volta"              # choix le plus récent (A)
    assert merged["lifetime"]["kills"] == 80           # 30 (B) + 50 (A)

    # 4) réponse perdue : A renvoie le même envoi -> les gains ne sont pas comptés deux fois
    again = sync(pc_a, p1, "a2")
    assert again["puces"] == merged["puces"] and again["lifetime"]["kills"] == 80
    # … et avec une modification faite entre-temps (+10 puces), seule la différence s'ajoute
    pc_a2 = dict(pc_a, puces=420)
    again = sync(pc_a2, p1, "a2")
    assert again["puces"] == merged["puces"] + 10

    # 5) nouveau PC : restauration avec le code de sauvegarde
    assert client.post("/api/v1/auth/restore", json={"code": "inconnu-0000-0000"}).status_code == 404
    r = client.post("/api/v1/auth/restore", json={"code": "5E1F-0A2B-3C4D-5E6F"})
    assert r.status_code == 200 and r.json()["player_id"] == "5e1f0a2b3c4d5e6f"
    fresh = sync(_prof(updated_at=0), None, "c1")   # profil neuf (updated_at 0), sans base : le cloud prime
    assert fresh["puces"] == again["puces"] and len(fresh["campaign"]["completed"]) == 4
    assert fresh["character"] == "volta"


def test_legacy_client_put_never_loses_progress():
    """Un joueur encore en 0.1.0 (PUT /profile, profil complet sans updated_at) ne doit pas écraser
    ce qu'il a fait en 0.2.0 sur un autre PC."""
    r = client.post("/api/v1/auth/guest", json={"player_id": "0ld0c11e47000001", "name": "Ancien"})
    h = {"Authorization": "Bearer " + r.json()["token"]}
    new = _prof(campaign={"completed": ["z1_m1", "z1_m2", "z1_m3"], "best_endless": 12}, puces=900, updated_at=5000,
                cosmetics={"hats": ["fez", "bob"], "colors": [], "titles": [], "hat": "bob", "color": "", "title": ""})
    client.post("/api/v1/profile/sync", json={"profile": new, "base": None, "push_id": "n1"}, headers=h)
    old = _prof(campaign={"completed": ["z1_m1"], "best_endless": 3}, puces=400)
    old.pop("updated_at")
    assert client.put("/api/v1/profile", json={"profile": old}, headers=h).status_code == 200
    got = client.get("/api/v1/profile", headers=h).json()["profile"]
    assert got["campaign"]["completed"] == ["z1_m1", "z1_m2", "z1_m3"] and got["campaign"]["best_endless"] == 12
    assert got["puces"] == 900 and got["cosmetics"]["hats"] == ["fez", "bob"] and got["cosmetics"]["hat"] == "bob"
