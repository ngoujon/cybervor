import subprocess, imageio_ffmpeg, os
F = imageio_ffmpeg.get_ffmpeg_exe()
V = os.path.join(os.path.dirname(os.path.abspath(__file__)), "segments")
MUSIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "music", "pvp.ogg")
# (fichier, début, durée)
SEGS = [("01_menu",0,6),("02_dialogue",0,10),("03_fight",4,13),("04_fight2",4,11),("05_shop",21.5,8.5),
        ("06_boss",0,15),("07_pvp",0,13),("08_skills",0,6),("09_bp",0,6),("10_social",0,6),("11_end",0,7)]
args, flt, cat = [], "", ""
for i,(n,ss,d) in enumerate(SEGS):
    args += ["-ss", str(ss), "-t", str(d), "-i", os.path.join(V, n + ".avi")]
    fo = d - 0.35
    flt += (f"[{i}:v]scale=1920:1080:flags=lanczos,fps=30,setsar=1,format=yuv420p,fade=t=in:st=0:d=0.35,fade=t=out:st={fo}:d=0.35[v{i}];"
            f"[{i}:a]aresample=48000,volume=0.55,afade=t=in:st=0:d=0.2,afade=t=out:st={fo}:d=0.35[a{i}];")
    cat += f"[v{i}][a{i}]"
total = sum(d for _,_,d in SEGS)
n = len(SEGS)
args += ["-i", MUSIC]
flt += f"{cat}concat=n={n}:v=1:a=1[v][sfx];"
flt += f"[{n}:a]aresample=48000,volume=0.8,atrim=0:{total},afade=t=in:st=0:d=1,afade=t=out:st={total-2.5}:d=2.5[mus];"
flt += "[sfx][mus]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]"
out = os.path.join(V, "..", "cybervor_trailer.mp4")
subprocess.run([F, "-v", "error", "-y"] + args + ["-filter_complex", flt, "-map", "[v]", "-map", "[a]",
    "-c:v", "libx264", "-preset", "slow", "-crf", "21", "-profile:v", "high", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out], check=True)
subprocess.run([F, "-v", "error", "-y", "-ss", "33", "-i", out, "-frames:v", "1", "-vf", "scale=1280:-1", os.path.join(V, "poster.jpg")], check=True)
print("ok", total, os.path.getsize(out) // 1024 // 1024, "Mo")
