"""Type de dégâts de chaque sort actif (data/spells.json, champ "dmg_type") :
melee = Physique, ranged = Distance, tech = Techno, support = Soutien (soins, boucliers, renforts).
Les sorts profitent de la statistique correspondante (Dégâts de mêlée / à distance / techno).
    python tools/assign_damage_types.py
"""
import json
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "data" / "spells.json"
d = json.loads(P.read_text(encoding="utf-8"))

BY_KIND = {"nova": "melee", "bolt": "ranged", "barrage": "ranged", "chain": "tech", "zone": "tech",
           "laser": "tech", "strike": "tech", "buff": "support", "heal": "support", "summon": "support"}
OVERRIDE = {
    "vol_surtension": "tech", "mec_champ": "tech",          # décharges électriques / champ de force
    "bru_tourbi": "melee",                                    # tournoiement au corps à corps
    "pat_germe": "tech",
    "gen_rail": "ranged",                                     # tir de rail : arme à distance
    "mec_mines": "tech", "gli_bombe": "tech",                 # explosifs électroniques
}
n = 0
for sid, s in d["spells"].items():
    if s["type"] != "active":
        continue
    s["dmg_type"] = OVERRIDE.get(sid, BY_KIND.get(s["kind"], "tech"))
    n += 1
P.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"{n} sorts actifs typés.")
