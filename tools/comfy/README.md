# Génération des assets avec ComfyUI

Tous les visuels, musiques et effets sonores de Cybervor sont produits par ComfyUI (http://127.0.0.1:8188)
à partir du manifeste `manifest.json` et de 4 workflows au format API.

## Workflows (`workflows/`)

| Fichier | Usage | Modèles |
|---|---|---|
| `sprite.json` | Sprites et icônes détourés (PNG transparent) | Z-Image Turbo (`z_image_turbo_bf16`, `qwen_3_4b`, `ae`) + BiRefNet (détourage) |
| `image.json` | Fonds d'écran et textures de sol | Z-Image Turbo |
| `music.json` | Musiques instrumentales en boucle | ACE-Step 1.5 Turbo (`ace_step_1.5_turbo_aio`) |
| `sfx.json` | Effets sonores courts | Stable Audio Open 1.0 + T5 base |

Les champs `"{{prompt}}"`, `"{{seed}}"`, etc. sont remplacés par le générateur. Les workflows peuvent aussi
être chargés dans l'interface ComfyUI (menu *Load* → format API) pour expérimenter.

## Générateur

```
python tools/comfy/generate.py                         # génère tout ce qui manque
python tools/comfy/generate.py --kind music            # images | music | sfx
python tools/comfy/generate.py --only boss_noyau --force
python tools/comfy/generate.py --only boss_noyau --force --seed-offset 3   # autre variante (graine mémorisée dans seeds.json)
```

Post-traitement automatique :
- sprites et icônes (styles `sprite` / `icon`, liste `pixel_styles`) : style 16 bits. Z-Image dessine en pixel art, puis `pixel_snap.py` recadre le sujet, le remet sur une vraie grille (64 px héros, 32 px icônes, 96 px boss et portraits, ennemis selon leur taille à l'écran) avec la couleur majoritaire de chaque case, et agrandit en blocs nets ×3 ;
- logo : style HD (`sprite_hd`), recadré et redimensionné ;
- textures de sol : rendues raccordables (fondu décalé d'une demi-tuile) ;
- SFX : suppression des silences, fondu de sortie, normalisation, WAV 16 bits ;
- musiques : normalisation et fondu enchaîné fin → début pour des boucles sans clic, OGG Vorbis.

Style visuel commun : « hand-drawn illustration style, thick black ink outlines, flat cel shading,
vibrant neon cyberpunk colors, cute cartoon video game art ». Pour ajouter un asset, ajoutez une entrée
au manifeste et relancez le générateur.
