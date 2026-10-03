"""Dessine les curseurs de souris néon de Cybervor (assets/ui/curseurs/*.png).
Dessin à 4x puis réduction pour un bord net et lissé.   python tools/make_cursors.py"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "assets" / "ui" / "curseurs"
S = 4            # suréchantillonnage
SIZE = 48        # taille finale (px)
CYAN = (64, 240, 230, 255)
MAGENTA = (255, 60, 190, 255)
DARK = (18, 8, 40, 255)


def canvas():
    return Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))


def glow(img, color, radius=6):
    """Halo néon sous le dessin."""
    alpha = img.split()[3].filter(ImageFilter.GaussianBlur(radius * S / 2))
    halo = Image.new("RGBA", img.size, color[:3] + (0,))
    halo.putalpha(alpha.point(lambda a: int(a * 0.8)))
    return Image.alpha_composite(halo, img)


def finish(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}.png")
    print("curseur", name)


def p(*pts):
    return [(x * S, y * S) for x, y in pts]


# --- flèche (menus) : pointe en (3, 3)
img = canvas()
d = ImageDraw.Draw(img)
arrow = p((3, 3), (3, 36), (12, 28), (18, 41), (24, 38), (18, 26), (30, 26))
d.polygon(arrow, fill=DARK)
d.line(arrow + [arrow[0]], fill=CYAN, width=3 * S, joint="curve")
d.polygon(p((7, 11), (7, 27), (12, 22), (20, 22)), fill=MAGENTA)
finish(glow(img, CYAN), "fleche")

# --- main (boutons, éléments cliquables) : bout du doigt en (15, 3)
img = canvas()
d = ImageDraw.Draw(img)
hand = p((12, 6), (15, 3), (18, 6), (18, 18), (22, 17), (26, 18), (30, 19), (34, 21), (36, 25), (35, 34),
         (31, 42), (17, 42), (11, 35), (6, 26), (8, 23), (12, 25))
d.polygon(hand, fill=DARK)
d.line(hand + [hand[0]], fill=MAGENTA, width=3 * S, joint="curve")
for x in (22, 27):
    d.line(p((x, 21), (x, 28)), fill=MAGENTA, width=2 * S)
d.ellipse(p((13, 30), (19, 36)), fill=CYAN)
finish(glow(img, MAGENTA), "main")

# --- viseur (en partie) : centre en (24, 24)
img = canvas()
d = ImageDraw.Draw(img)
c = 24
d.ellipse(p((c - 13, c - 13), (c + 13, c + 13)), outline=CYAN, width=3 * S)
for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
    d.line(p((c + dx * 7, c + dy * 7), (c + dx * 20, c + dy * 20)), fill=CYAN, width=3 * S)
d.ellipse(p((c - 3, c - 3), (c + 3, c + 3)), fill=MAGENTA)
finish(glow(img, CYAN, 5), "viseur")

# --- texte (champs de saisie) : centre en (24, 24)
img = canvas()
d = ImageDraw.Draw(img)
d.line(p((24, 8), (24, 40)), fill=CYAN, width=3 * S)
d.line(p((17, 8), (31, 8)), fill=CYAN, width=3 * S)
d.line(p((17, 40), (31, 40)), fill=CYAN, width=3 * S)
finish(glow(img, CYAN, 4), "texte")
