"""Objets actifs communs à tous les héros (vendus en boutique), à viser précisément : lasers, frappe, zones.
Ajoute les sorts dans data/spells.json (liste "generic") et leurs icônes dans le manifeste ComfyUI.
    python tools/add_generic_actives.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPELLS = ROOT / "data" / "spells.json"
MANIFEST = ROOT / "tools" / "comfy" / "manifest.json"

GENERIC = {
    "gen_laser": {"name": "Canon laser", "kind": "laser", "color": "#ff4d6d",
                  "desc": "Un rayon laser vers le curseur : {dmg} dégâts à tous les ennemis sur la ligne (portée {length}).",
                  "base": {"dmg": 140, "length": 800, "width": 16, "cd": 6.0}, "up": {"dmg": 45, "length": 40, "cd": -0.3},
                  "prompt": "red laser cannon firing a straight beam"},
    "gen_rail": {"name": "Railgun d'épaule", "kind": "laser", "color": "#5ff7ff",
                 "desc": "Un tir de rail ultra-fin et dévastateur : {dmg} dégâts sur une ligne de {length}. Visez juste !",
                 "base": {"dmg": 330, "length": 1000, "width": 9, "cd": 12.0}, "up": {"dmg": 110, "cd": -0.6},
                 "prompt": "sleek cyan railgun with electric coils, piercing beam"},
    "gen_cryo": {"name": "Rayon cryo", "kind": "laser", "color": "#9be7ff",
                 "desc": "Un large rayon glacé : {dmg} dégâts et ralentit fortement les ennemis touchés (portée {length}).",
                 "base": {"dmg": 70, "length": 700, "width": 30, "slow": 0.7, "cd": 7.0}, "up": {"dmg": 25, "width": 3, "cd": -0.35},
                 "prompt": "icy blue freeze ray gun with frost crystals"},
    "gen_orbitale": {"name": "Frappe orbitale", "kind": "strike", "color": "#ffd166",
                     "desc": "Un satellite frappe l'endroit visé après {delay} s : {dmg} dégâts dans un petit rayon ({radius}).",
                     "base": {"dmg": 420, "radius": 65, "delay": 0.8, "cd": 14.0}, "up": {"dmg": 140, "radius": 5, "cd": -0.7},
                     "prompt": "golden orbital satellite strike beam hitting a target from the sky"},
    "gen_iem": {"name": "Grenade IEM", "kind": "zone", "color": "#c77dff",
                "desc": "Une grenade qui grille les circuits à l'endroit visé : {dps} dégâts/s et paralyse presque pendant {dur} s.",
                "base": {"dps": 30, "radius": 120, "dur": 2.5, "slow": 0.85, "at": "target", "cd": 11.0},
                "up": {"dps": 10, "radius": 8, "dur": 0.3, "cd": -0.5},
                "prompt": "purple EMP grenade with electric sparks"},
    "gen_trounoir": {"name": "Mini trou noir", "kind": "zone", "color": "#7b5cff",
                     "desc": "Ouvre un mini trou noir à l'endroit visé : aspire les ennemis et inflige {dps} dégâts/s pendant {dur} s.",
                     "base": {"dps": 40, "radius": 150, "dur": 3.0, "pull": 320, "at": "target", "cd": 15.0},
                     "up": {"dps": 14, "radius": 10, "dur": 0.3, "cd": -0.7},
                     "prompt": "tiny swirling black hole with purple accretion disk"},
}

d = json.loads(SPELLS.read_text(encoding="utf-8"))
for sid, s in GENERIC.items():
    d["spells"][sid] = {"name": s["name"], "type": "active", "kind": s["kind"], "color": s["color"], "desc": s["desc"],
                        "icon": f"res://assets/sprites/spells/{sid}.png", "max": 5, "base": s["base"], "up": s["up"],
                        "prompt": s["prompt"], "generic": True}
d["generic"] = list(GENERIC)
SPELLS.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")

m = json.loads(MANIFEST.read_text(encoding="utf-8"))
ids = {e["id"] for e in m["images"]}
for sid, s in GENERIC.items():
    if "spell_" + sid not in ids:
        m["images"].append({"id": "spell_" + sid, "wf": "sprite", "style": "icon", "out": f"assets/sprites/spells/{sid}.png",
                            "size": 72, "prompt": s["prompt"] + ", game item icon"})
MANIFEST.write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"{len(GENERIC)} objets actifs communs ajoutés.")
