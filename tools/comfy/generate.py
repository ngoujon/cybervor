"""Générateur d'assets Cybervor via l'API HTTP de ComfyUI.

Usage :
    python tools/comfy/generate.py                  # tout ce qui manque
    python tools/comfy/generate.py --kind images    # images | music | sfx
    python tools/comfy/generate.py --only char_volta boss_noyau --force
    python tools/comfy/generate.py --seed-offset 1 --only enemy_brute --force   # nouvelle variante

Les workflows (format API) sont dans tools/comfy/workflows/. Les champs "{{nom}}"
y sont remplacés par les valeurs du manifeste (manifest.json).
"""
import argparse
import hashlib
import io
import json
import os
import sys
import time
import urllib.parse

import numpy as np
import requests
import soundfile as sf
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
COMFY = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def fill(node, values):
    """Remplace récursivement les chaînes "{{clé}}" (valeur typée si la chaîne entière est un jeton)."""
    if isinstance(node, dict):
        return {k: fill(v, values) for k, v in node.items()}
    if isinstance(node, list):
        return [fill(v, values) for v in node]
    if isinstance(node, str) and "{{" in node:
        if node.startswith("{{") and node.endswith("}}") and node.count("{{") == 1:
            return values[node[2:-2]]
        out = node
        for k, v in values.items():
            out = out.replace("{{" + k + "}}", str(v))
        return out
    return node


def seed_for(asset_id, offset):
    return int(hashlib.md5(asset_id.encode()).hexdigest()[:8], 16) + offset * 7919


def run(workflow, timeout=900):
    r = requests.post(f"{COMFY}/prompt", json={"prompt": workflow}, timeout=30)
    if r.status_code != 200:
        raise RuntimeError(f"Erreur ComfyUI {r.status_code}: {r.text[:500]}")
    pid = r.json()["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        h = requests.get(f"{COMFY}/history/{pid}", timeout=30).json()
        if pid in h:
            entry = h[pid]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(f"Échec d'exécution: {json.dumps(status)[:800]}")
            files = []
            for out in entry.get("outputs", {}).values():
                for key in ("images", "audio"):
                    files.extend(out.get(key, []))
            if files:
                return files
        time.sleep(1.0)
    raise TimeoutError(pid)


def download(f):
    q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""), "type": f.get("type", "output")})
    r = requests.get(f"{COMFY}/view?{q}", timeout=120)
    r.raise_for_status()
    return r.content


# ---------------------------------------------------------------- post-traitement
def process_sprite(data, size, dest):
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    alpha = np.array(im.split()[-1])
    alpha[alpha < 12] = 0
    im.putalpha(Image.fromarray(alpha))
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - w) // 2, (side - h) // 2))
    canvas = canvas.resize((size, size), Image.LANCZOS)
    canvas.save(dest)


def process_wide_sprite(data, width, dest):
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    ratio = width / im.size[0]
    im = im.resize((width, max(1, int(im.size[1] * ratio))), Image.LANCZOS)
    im.save(dest)


def process_image(data, size, dest):
    im = Image.open(io.BytesIO(data)).convert("RGB")
    ratio = size / im.size[0]
    im = im.resize((size, int(im.size[1] * ratio)), Image.LANCZOS)
    im.save(dest)


def make_seamless(path):
    """Rend une texture raccordable : centre d'origine, bords issus d'une copie décalée d'une demi-tuile."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    h, w, _ = im.shape
    rolled = np.roll(np.roll(im, h // 2, axis=0), w // 2, axis=1)
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    mask = np.clip((1 - np.maximum(x, y)) / 0.45, 0, 1)[:, :, None]
    Image.fromarray((im * mask + rolled * (1 - mask)).clip(0, 255).astype(np.uint8)).save(path)


def read_audio(data):
    audio, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=True)
    return audio, sr


def process_sfx(data, dest, max_len=None):
    audio, sr = read_audio(data)
    mono = np.abs(audio).max(axis=1)
    thr = max(mono.max() * 0.03, 1e-4)
    idx = np.where(mono > thr)[0]
    if len(idx):
        start = max(0, idx[0] - int(0.005 * sr))
        end = min(len(audio), idx[-1] + int(0.05 * sr))
        audio = audio[start:end]
    if max_len:
        audio = audio[: int(max_len * sr)].copy()
    fade = min(len(audio) // 4, int(0.04 * sr))
    if fade > 0:
        audio[-fade:] *= np.linspace(1, 0, fade)[:, None]
    peak = np.abs(audio).max()
    if peak > 0:
        audio = audio / peak * 0.89
    sf.write(dest, audio, sr, subtype="PCM_16")


def process_music(data, dest, loop=True):
    audio, sr = read_audio(data)
    peak = np.abs(audio).max()
    if peak > 0:
        audio = audio / peak * 0.89
    if loop and len(audio) > sr * 8:
        # fondu enchaîné fin -> début pour une boucle sans clic
        xf = int(1.5 * sr)
        head = audio[:xf].copy()
        tail = audio[-xf:]
        ramp = np.linspace(0, 1, xf)[:, None]
        audio = audio[:-xf].copy()
        audio[:xf] = head * ramp + tail * (1 - ramp)
    else:
        fade = int(0.3 * sr)
        audio[-fade:] *= np.linspace(1, 0, fade)[:, None]
    # Écriture par blocs : libsndfile plante sur les longues écritures Vorbis d'un seul tenant.
    with sf.SoundFile(dest, "w", sr, audio.shape[1], format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(audio), 8192):
            f.write(audio[i:i + 8192])


# ---------------------------------------------------------------- main
def pixel_grid(a) -> int:
    """Taille de la grille 16 bits d'un sprite (en pixels d'art) ; l'image finale fait grille × 3 (× 4 portraits)."""
    folder = a["out"].split("/")[2]
    if folder == "enemies":
        enemies = load_json(os.path.join(ROOT, "data", "enemies.json"))
        disp = max([float(v.get("size", 64)) for v in enemies.values()
                    if isinstance(v, dict) and v.get("sprite", "").endswith(a["out"].split("/")[-1])] or [64])
        return int(min(64, max(32, round(disp * 0.62))))
    return {"characters": 64, "bosses": 96, "npc": 96, "pickups": 24}.get(folder, 32)


def process_pixel_sprite(data, a, dest):
    from pixel_snap import snap
    grid = pixel_grid(a)
    im = Image.open(io.BytesIO(data))
    snap(im, grid, scale=4 if a["out"].split("/")[2] == "npc" else 3).save(dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", choices=["images", "music", "sfx"], nargs="*")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--seed-offset", type=int, default=0)
    args = ap.parse_args()

    man = load_json(os.path.join(HERE, "manifest.json"))
    wfs = {n[:-5]: load_json(os.path.join(HERE, "workflows", n)) for n in os.listdir(os.path.join(HERE, "workflows")) if n.endswith(".json")}
    seeds_path = os.path.join(HERE, "seeds.json")
    seeds = load_json(seeds_path) if os.path.exists(seeds_path) else {}
    kinds = args.kind or ["images", "music", "sfx"]

    jobs = []
    for kind in kinds:
        for a in man[kind]:
            if args.only and a["id"] not in args.only:
                continue
            dest = os.path.join(ROOT, a["out"])
            if os.path.exists(dest) and not args.force:
                continue
            jobs.append((kind, a, dest))

    print(f"{len(jobs)} asset(s) à générer")
    failures = []
    for i, (kind, a, dest) in enumerate(jobs, 1):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        seed = seeds.get(a["id"], seed_for(a["id"], 0)) + args.seed_offset * 7919
        prefix = f"cybervor/{kind}/{a['id']}"
        t0 = time.time()
        try:
            if kind == "images":
                style = man["styles"][a["style"]]
                values = {
                    "prompt": f"{a['prompt']}, {style}",
                    "negative": man["negative"]["image"],
                    "width": a.get("w", 1024), "height": a.get("h", 1024),
                    "seed": seed, "prefix": prefix,
                }
                files = run(fill(wfs[a["wf"]], values))
                data = download(files[0])
                if a["style"] in man.get("pixel_styles", []):
                    process_pixel_sprite(data, a, dest)
                elif a["wf"] == "sprite" and "w" in a:
                    process_wide_sprite(data, a["size"], dest)
                elif a["wf"] == "sprite":
                    process_sprite(data, a["size"], dest)
                else:
                    process_image(data, a["size"], dest)
                    if a["style"] == "ground":
                        make_seamless(dest)
            elif kind == "music":
                values = {"prompt": a["prompt"], "lyrics": a.get("lyrics", "[Instrumental]"), "seed": seed,
                          "bpm": a["bpm"], "duration": float(a["duration"]), "key": a["key"], "prefix": prefix}
                files = run(fill(wfs["music"], values), timeout=1800)
                process_music(download(files[0]), dest, loop=a["duration"] >= 60)
            else:
                values = {"prompt": a["prompt"], "negative": man["negative"]["sfx"], "seed": seed,
                          "duration": max(1.5, float(a["duration"])), "prefix": prefix}
                files = run(fill(wfs["sfx"], values))
                process_sfx(download(files[0]), dest, max_len=float(a["duration"]) * 1.25)
            if args.seed_offset:
                seeds[a["id"]] = seed
                with open(seeds_path, "w", encoding="utf-8") as f:
                    json.dump(seeds, f, indent=1)
            print(f"[{i}/{len(jobs)}] OK {a['id']} -> {a['out']} ({time.time() - t0:.1f}s)", flush=True)
        except Exception as e:  # noqa: BLE001
            failures.append(a["id"])
            print(f"[{i}/{len(jobs)}] ÉCHEC {a['id']}: {e}", flush=True)
    if failures:
        print("Échecs :", " ".join(failures))
        sys.exit(1)


if __name__ == "__main__":
    main()
