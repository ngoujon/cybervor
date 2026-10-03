# Superviseur des parties Cybervor (lance une instance du serveur de jeu Godot headless par partie).
# Le binaire du serveur de jeu n'est PAS dans l'image : il est monté depuis server/game/build (volume ./build:/srv/cybervor/bin)
# pour pouvoir le mettre à jour à chaud sans couper les parties en cours (voir server/deploy/update_game.sh).
FROM ubuntu:24.04
RUN apt-get update  && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 python3  && rm -rf /var/lib/apt/lists/*  && useradd --create-home --shell /usr/sbin/nologin cybervor
WORKDIR /srv/cybervor
COPY rooms.py ./
USER cybervor
ENV CYBERVOR_PORT_MIN=7810     CYBERVOR_PORT_MAX=7829     CYBERVOR_SERVER_CMD="./bin/cybervor_server.x86_64 --headless"     CYBERVOR_VERSION_FILE=./bin/VERSION
EXPOSE 9000 7810-7829/udp
CMD ["python3", "-u", "rooms.py"]
