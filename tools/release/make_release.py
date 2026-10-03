"""Prépare une nouvelle version de Cybervor (sans rien déployer).

    python tools/release/make_release.py 0.2.0 --note "Sauvegarde cloud" --note "Mise à jour automatique"

Étapes :
  1. écrit la version dans project.godot (application/config/version) ;
  2. exporte le jeu Windows -> tools/release/dist/Cybervor/Cybervor.exe (+ icône, LISEZMOI) ;
  3. crée tools/release/dist/Cybervor.zip et tools/release/dist/version.json (taille, sha256, notes) ;
  4. exporte le serveur Linux -> server/game/build/cybervor_server.x86_64 + server/game/build/VERSION.

Le déploiement (tools/release/deploy.py) publie ensuite, dans cet ordre : serveur de jeu (à chaud), API,
zip, puis version.json en dernier : les joueurs ne voient la nouvelle version qu'une fois tout en place.
Options : --out <dossier> pour une autre sortie (tests), --no-server pour ne pas exporter le serveur Linux.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GODOT = os.environ.get("GODOT") or str(Path.home() / "Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe")


def set_version(version: str) -> None:
    p = ROOT / "project.godot"
    s = p.read_text(encoding="utf-8")
    s2 = re.sub(r'^config/version=".*"$', f'config/version="{version}"', s, flags=re.M)
    if s2 == s and f'config/version="{version}"' not in s:
        sys.exit("config/version introuvable dans project.godot")
    p.write_text(s2, encoding="utf-8")


def export(preset: str, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".tmp")
    r = subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--export-release", preset, str(out)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    errors = [line for line in (r.stdout + r.stderr).splitlines() if "ERROR" in line and "resources still in use" not in line]
    if r.returncode != 0 or not out.exists() or errors:
        print("\n".join(errors[-10:]))
        sys.exit(f"Échec de l'export « {preset} »")
    if tmp.exists():
        tmp.unlink()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--note", action="append", default=[])
    ap.add_argument("--out", default=str(HERE / "dist"))
    ap.add_argument("--no-server", action="store_true")
    a = ap.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", a.version):
        sys.exit("Version attendue au format X.Y.Z")
    out = Path(a.out)
    game_dir = out / "Cybervor"
    if game_dir.exists():
        shutil.rmtree(game_dir)
    game_dir.mkdir(parents=True)

    print(f"[1/4] version {a.version}")
    set_version(a.version)
    print("[2/4] export Windows")
    export("Windows", game_dir / "Cybervor.exe")
    shutil.copy(HERE / "Cybervor.ico", game_dir / "Cybervor.ico")
    shutil.copy(HERE / "LISEZMOI.txt", game_dir / "LISEZMOI.txt")
    print("[3/4] archive et manifeste")
    zip_path = out / "Cybervor.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for f in ("Cybervor.exe", "Cybervor.ico", "LISEZMOI.txt"):
            z.write(game_dir / f, f"Cybervor/{f}")
    notes = a.note
    if not notes:   # par défaut : les notes de version affichées sur l'accueil du jeu (data/patchnotes.json)
        pn = json.loads((ROOT / "data/patchnotes.json").read_text(encoding="utf-8"))
        notes = next((v["notes"] for v in pn["versions"] if v["version"] == a.version), [])
        if not notes:
            print(f"Attention : aucune note pour {a.version} dans data/patchnotes.json")
    manifest = {"version": a.version, "file": "Cybervor.zip", "size": zip_path.stat().st_size,
                "sha256": sha256(zip_path), "notes": [n.split(" : ")[0] if len(n) > 90 else n for n in notes]}
    (out / "version.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    if not a.no_server:
        print("[4/4] export du serveur Linux")
        build = ROOT / "server/game/build"
        export("Serveur Linux", build / "cybervor_server.x86_64")
        (build / "VERSION").write_text(a.version + "\n", encoding="utf-8")
    print(f"Version {a.version} prête : {zip_path} ({manifest['size'] / 1048576:.1f} Mo)")


if __name__ == "__main__":
    main()
