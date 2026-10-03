"""Remise sur grille des sprites pixel art générés par ComfyUI (style 16 bits).
Le modèle dessine du pixel art « approximatif » (pixels de tailles inégales, bords adoucis). On recadre le
sujet, on fixe une grille (ex. 64×64), et chaque case prend la couleur MAJORITAIRE de sa zone (pas la moyenne,
qui rendrait flou) dans une palette limitée. L'image finale est agrandie en blocs nets ×SCALE.
"""
import numpy as np
from PIL import Image

SCALE = 3


def snap(im: Image.Image, grid: int, colors: int = 32, scale: int = SCALE) -> Image.Image:
    im = im.convert("RGBA")
    a = np.asarray(im.getchannel("A"))
    im.putalpha(Image.fromarray(np.where(a < 128, 0, 255).astype(np.uint8)))
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size
    side = max(w, h)
    cell = side / grid
    # sujet centré dans un carré, une case de marge pour le contour
    gw = max(1, round(w / cell))
    gh = max(1, round(h / cell))
    rgb = im.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(rgb.getpalette()[: colors * 3], dtype=np.uint8).reshape(-1, 3)
    idx = np.asarray(rgb)
    alpha = np.asarray(im.getchannel("A")) > 0
    out = np.zeros((grid, grid, 4), dtype=np.uint8)
    ox = (grid - gw) // 2
    oy = (grid - gh) // 2
    for gy in range(gh):
        y0, y1 = int(gy * h / gh), max(int(gy * h / gh) + 1, int((gy + 1) * h / gh))
        for gx in range(gw):
            x0, x1 = int(gx * w / gw), max(int(gx * w / gw) + 1, int((gx + 1) * w / gw))
            al = alpha[y0:y1, x0:x1]
            if al.mean() < 0.5:
                continue
            vals = idx[y0:y1, x0:x1][al]
            c = np.bincount(vals.ravel(), minlength=len(pal)).argmax()
            if 0 <= oy + gy < grid and 0 <= ox + gx < grid:
                out[oy + gy, ox + gx, :3] = pal[c]
                out[oy + gy, ox + gx, 3] = 255
    res = Image.fromarray(out, "RGBA")
    return res.resize((grid * scale, grid * scale), Image.NEAREST)
