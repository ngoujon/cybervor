"""Sorts actifs v0.3 : achetés en boutique, visés au curseur, et bien plus puissants (data/spells.json).
À lancer une seule fois sur les valeurs de la 0.2.0 (le script refuse de s'appliquer deux fois).
    python tools/rebalance_actives.py
"""
import json
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "data" / "spells.json"
d = json.loads(P.read_text(encoding="utf-8"))
if d.get("actives_v3"):
    raise SystemExit("Déjà rééquilibré.")

# multiplicateurs de dégâts par type d'actif (les ennemis ont 3-4x plus de PV que nos sorts n'en retiraient)
DMG = {"nova": 4.0, "bolt": 3.0, "chain": 3.5, "zone": 3.5, "barrage": 3.5}
CD = {"nova": 1.15, "bolt": 1.1, "chain": 1.1, "zone": 1.1, "barrage": 1.15}

# descriptions : le sort part vers le curseur
DESC = {
    "pat_puree": "Lance un obus de purée qui explose à l'endroit visé : {dmg} dégâts dans un rayon de {radius}.",
    "pat_frites": "Tire {count} frites perforantes de {dmg} dégâts vers le curseur.",
    "pat_germe": "Fait pousser un champ de germes à l'endroit visé : {dps} dégâts/s et ralentit pendant {dur} s.",
    "pat_chips": "Une averse de {count} chips géantes explosives sur la zone visée ({dmg} dégâts chacune).",
    "vol_arc": "Un éclair frappe l'ennemi visé puis rebondit sur {jumps} autres ({dmg} dégâts).",
    "vol_surtension": "Une décharge foudroyante à l'endroit visé : {dmg} dégâts (rayon {radius}).",
    "vol_aimant": "Un champ magnétique à l'endroit visé aspire les ennemis : {dps} dégâts/s pendant {dur} s.",
    "vol_orage": "Invoque {count} foudres sur la zone visée ({dmg} dégâts chacune).",
    "bru_seisme": "Un séisme à l'endroit visé : {dmg} dégâts et repousse fortement (rayon {radius}).",
    "bru_poing": "Lance {count} poing(s)-fusée(s) explosif(s) de {dmg} dégâts vers le curseur.",
    "bru_tourbi": "Tournoie sur vous-même : {dps} dégâts/s autour de vous pendant {dur} s.",
    "bru_pilon": "{count} coups de marteau géant s'abattent sur la zone visée ({dmg} dégâts chacun).",
    "gli_virus": "Infecte la zone visée : {dps} dégâts/s pendant {dur} s.",
    "gli_ddos": "Surcharge la zone visée, qui aspire les ennemis ({dps} dégâts/s, {dur} s).",
    "gli_copier": "Duplique {count} projectiles de code vers le curseur ({dmg} dégâts, perforants).",
    "gli_bombe": "{count} bombes logiques explosent sur la zone visée ({dmg} dégâts chacune).",
    "mec_mines": "Lance {count} mines sur la zone visée ({dmg} dégâts chacune).",
    "mec_boulon": "Lance {count} boulons explosifs vers le curseur ({dmg} dégâts, zone {aoe}).",
    "mec_champ": "Projette un champ de force à l'endroit visé qui repousse tout ({dmg} dégâts, rayon {radius}).",
    "cap_bordee": "Tire une bordée de {count} boulets de canon vers le curseur ({dmg} dégâts).",
    "cap_abordage": "À l'abordage ! Une charge frappe l'endroit visé ({dmg} dégâts, rayon {radius}).",
    "cap_kraken": "Un kraken surgit à l'endroit visé : aspire les ennemis et inflige {dps} dégâts/s pendant {dur} s.",
    "cap_boulets": "{count} boulets de canon pleuvent sur la zone visée ({dmg} dégâts chacun).",
}


def scale(block: dict, key: str, k: float) -> None:
    if key in block and isinstance(block[key], (int, float)):
        block[key] = round(block[key] * k, 2) if isinstance(block[key], float) else int(round(block[key] * k))


for sid, s in d["spells"].items():
    if s["type"] != "active":
        continue
    b, u, kind = s.setdefault("base", {}), s.setdefault("up", {}), s["kind"]
    if kind in DMG:
        for key in ("dmg", "dps"):
            scale(b, key, DMG[kind])
            scale(u, key, DMG[kind])
        if "cd" in b:
            b["cd"] = round(b["cd"] * CD[kind], 1)
        if kind == "nova":
            b["radius"] = b.get("radius", 150) + 20
    elif kind == "buff":   # utilitaires : effets nettement plus marqués et plus longs
        for st in b.get("stats", {}):
            b["stats"][st] = int(round(b["stats"][st] * 1.6))
        for st in u.get("stats", {}):
            u["stats"][st] = int(round(u["stats"][st] * 1.6))
        b["dur"] = b.get("dur", 5) + 2
    elif kind == "heal":
        b["pct"] = int(round(b.get("pct", 20) * 1.5))
        b["shield"] = b.get("shield", 0) + 1
    elif kind == "summon":
        b["drones"] = b.get("drones", 2) + 1
        b["dur"] = b.get("dur", 8) + 3
    if sid in DESC:
        s["desc"] = DESC[sid]

d["actives_v3"] = True
P.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
print("Sorts actifs rééquilibrés.")
