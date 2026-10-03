"""Reconstruit les 40 paliers du battle pass : uniquement des cosmétiques (+ des néons pour le pass premium).
Usage : python tools/battlepass_cosmetic.py   (modifie data/battlepass.json)"""
import collections
import json
import os

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "battlepass.json")
d = json.load(open(P, encoding="utf-8"))

NEW_HATS = [("bob", "Bob fluo"), ("fez", "Fez à pompon LED"), ("sorcier", "Chapeau de sorcier du code"),
            ("casque_audio", "Casque gamer RGB"), ("helice", "Casquette à hélice"), ("ninja", "Bandeau de ninja"),
            ("pizza", "Part de pizza (chapeau)"), ("astronaute", "Casque d'astronaute")]
NEW_COLORS = [("menthe", "Menthe glaciale", "#7dffd4"), ("bubblegum", "Chewing-gum", "#ff6fb5"), ("cuivre", "Cuivre rétro", "#d98a4f"),
              ("lavande", "Lavande", "#b8a1ff"), ("citron", "Citron pressé", "#f4ff5f"), ("ocean", "Océan profond", "#2fa8ff"),
              ("corail", "Corail", "#ff7f6b"), ("onyx", "Onyx", "#5a5470"), ("turquoise", "Turquoise", "#3fe0d0"),
              ("prune", "Prune", "#a64dff"), ("caramel", "Caramel", "#e6a35c"), ("neon_vert", "Néon toxique", "#9dff00")]
NEW_TITLES = [("t_ctrlz", "Maître du Ctrl+Z"), ("t_404", "Introuvable (404)"), ("t_lag", "Roi du lag"), ("t_cafe", "Alimenté au café"),
              ("t_canard", "Ami des canards en plastique"), ("t_wifi", "Chasseur de Wi-Fi gratuit"),
              ("t_bug", "Ce n'est pas un bug, c'est une fonctionnalité"), ("t_reboot", "Redémarreur professionnel"),
              ("t_pixel", "Pixel parfait"), ("t_mamie", "Chouchou de Mamie RAM"), ("t_moustache", "Rival de la moustache du Noyau"),
              ("t_tomate", "Jardinier de tomates Bluetooth"), ("t_glace", "Climatiseur humain"), ("t_holo", "Star des hologrammes"),
              ("t_decharge", "Roi de la décharge"), ("t_survivant", "Survivant de la mise à jour"), ("t_turbo", "Mode turbo activé"),
              ("t_patch", "Patch note ambulant"), ("t_chapeau", "Collectionneur de chapeaux"), ("t_legende", "Légende du Réseau")]

for i, n in NEW_HATS:
    d["hats"][i] = {"name": n, "sprite": f"res://assets/sprites/hats/{i}.png"}
for i, n, c in NEW_COLORS:
    d["colors"][i] = {"name": n, "color": c}
for i, n in NEW_TITLES:
    d["titles"][i] = n

hats, colors, titles = list(d["hats"]), list(d["colors"]), list(d["titles"])
free_hats = ["bob", "helice", "pizza", "ninja", "fez"]
prem_hats = [h for h in hats if h not in free_hats]          # 11
free_colors, prem_colors = colors[8:18], colors[:8] + colors[18:]   # 10 / 10
free_titles, prem_titles = titles[8:24] + titles[27:], titles[:8] + titles[24:27]   # 17 / 11 (« Légende du Réseau » en gratuit)
NEON_TIERS = [1, 5, 10, 15, 20, 25, 30, 35]


def track(h, c, t, neons):
    """32 cosmétiques répartis régulièrement + 8 récompenses de néons."""
    lists = {"hat": h, "color": c, "title": t}
    total = sum(len(v) for v in lists.values())
    assert total == 40 - len(NEON_TIERS), total
    counts = dict.fromkeys(lists, 0)
    cos = []
    for k in range(total):
        best = max(lists, key=lambda x: (len(lists[x]) * (k + 1) / total - counts[x]) if counts[x] < len(lists[x]) else -99)
        cos.append({"type": best, "id": lists[best][counts[best]]})
        counts[best] += 1
    out, ni = [], 0
    for tier in range(1, 41):
        if tier in NEON_TIERS:
            out.append({"type": "neons", "amount": neons[ni]})
            ni += 1
        else:
            out.append(cos.pop(0))
    return out


def put_last(tr, id_):
    i = next(k for k, r in enumerate(tr) if r.get("id") == id_)
    tr[i], tr[39] = tr[39], tr[i]


free = track(free_hats, free_colors, free_titles, [20, 20, 30, 30, 40, 40, 50, 60])
prem = track(prem_hats, prem_colors, prem_titles, [40, 40, 60, 60, 80, 80, 100, 120])
put_last(prem, "couronne")
put_last(free, "t_legende")
for i, t in enumerate(d["tiers"]):
    t["free"], t["premium"] = free[i], prem[i]
json.dump(d, open(P, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

for name in ("free", "premium"):
    print(name, dict(collections.Counter(t[name]["type"] for t in d["tiers"])))
ids = [t[n]["id"] for t in d["tiers"] for n in ("free", "premium") if "id" in t[n]]
print("cosmétiques :", len(ids), "doublons :", len(ids) - len(set(ids)))
