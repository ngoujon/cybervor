#!/usr/bin/env sh
# Exporte le serveur dédié Linux de Cybervor vers server/game/build (utilisé par le Dockerfile).
# Usage : GODOT=/chemin/godot sh server/build_server.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
mkdir -p "$ROOT/server/game/build"
"$GODOT" --headless --path "$ROOT" --export-release "Serveur Linux" "$ROOT/server/game/build/cybervor_server.x86_64"
echo "Serveur exporté dans server/game/build"
