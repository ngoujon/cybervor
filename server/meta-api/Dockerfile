# API méta Cybervor (profils, battle pass, liste des serveurs, matchmaking)
# Construire depuis la racine du dépôt :  docker build -f server/meta-api/Dockerfile -t cybervor-meta .
FROM python:3.12-slim
WORKDIR /app
COPY server/meta-api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server/meta-api/app.py .
COPY data/battlepass.json /app/data/battlepass.json
ENV CYBERVOR_DB=/data/cybervor.db \
    CYBERVOR_SEASON_FILE=/app/data/battlepass.json
VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health')"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]
