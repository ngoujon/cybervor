#!/bin/sh
# Mise à jour à chaud du serveur de jeu Cybervor, SANS couper les parties en cours.
#   sudo sh update_game.sh /tmp/cybervor_server.x86_64 0.2.0
# Le binaire est remplacé par renommage atomique : les instances déjà lancées gardent l'ancien fichier
# (même inode) jusqu'à la fin de leur partie ; les nouvelles parties démarrent avec la nouvelle version.
# Le superviseur (conteneur « rooms ») n'est pas redémarré.
set -eu
NEW_BIN="$1"
VERSION="$2"
BIN_DIR="${BIN_DIR:-/opt/cybervor/server/game/build}"

install -m 755 "$NEW_BIN" "$BIN_DIR/cybervor_server.x86_64.new"
mv -f "$BIN_DIR/cybervor_server.x86_64.new" "$BIN_DIR/cybervor_server.x86_64"
printf '%s\n' "$VERSION" > "$BIN_DIR/VERSION.new"
mv -f "$BIN_DIR/VERSION.new" "$BIN_DIR/VERSION"
echo "Serveur de jeu $VERSION installé ; parties en cours conservées."
