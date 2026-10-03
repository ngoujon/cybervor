import subprocess, os, sys
G = os.environ.get("GODOT", "godot")   # chemin de l'exécutable Godot 4.7 (console)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "segments")
os.makedirs(OUT, exist_ok=True)
SEGS = [
    ("01_menu", "main_menu", 6, "CYBERVOR", "Le survivor néon complètement déjanté", []),
    ("02_dialogue", "dialogue", 10, "Une campagne pleine d'humour", "5 zones, 20 missions, Mamie RAM et le Noyau moustachu", ["--top"]),
    ("03_fight", "fight", 17, "Des hordes de bugs", "Vos armes tirent toutes seules : à vous l'esquive !", ["--delay", "4"]),
    ("04_fight2", "fight2", 15, "6 héros, 12 armes", "Fusionnez, combinez, devenez une machine de guerre", ["--delay", "4"]),
    ("05_shop", "shop", 30, "Boutique entre les vagues", "24 objets et des améliorations à chaque niveau", ["--delay", "22"]),
    ("06_boss", "boss", 15, "5 boss gigantesques", "Des motifs d'attaque redoutables… et de la répartie", []),
    ("07_pvp", "pvp", 13, "Arène PvP du 1v1 au 4v4", "Contre vos amis ou des IA de 4 niveaux", []),
    ("08_skills", "skills", 6, "5 arbres de compétences", "Assaut, Blindage, Technologie, Piratage, Récolte", []),
    ("09_bp", "battlepass", 6, "Battle pass « Surtension »", "40 paliers : chapeaux, couleurs et titres", []),
    ("10_social", "social", 6, "Coop en ligne jusqu'à 4", "Amis, messagerie, serveurs dédiés", []),
    ("11_end", "main_menu", 7, "Téléchargez Cybervor", "Gratuit — vps-3962b7dc.vps.ovh.net/cybervore", []),
]
only = sys.argv[1:]
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
for name, seg, secs, cap, sub, extra in SEGS:
    if only and name not in only:
        continue
    cmd = [G, "--path", ".", "--write-movie", os.path.join(OUT, name + ".avi"), "--fixed-fps", "30", "--resolution", "1920x1080",
           "--", "--trailer", seg, "--seconds", str(secs), "--caption", cap, "--sub", sub, "--no_music"] + extra
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    errs = [l for l in (r.stdout + r.stderr).splitlines() if "SCRIPT ERROR" in l]
    print(name, "ok" if os.path.exists(os.path.join(OUT, name + ".avi")) else "ABSENT", errs[:2], flush=True)
