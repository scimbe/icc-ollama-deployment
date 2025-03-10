#!/bin/bash

# Skript zum direkten Testen der Elasticsearch-Installation
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Elasticsearch-Minimal-Setup ===${NC}"

# Prüfe, ob Docker installiert ist
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Fehler: Docker ist nicht installiert.${NC}"
    exit 1
fi

# Prüfe, ob bereits ein Elasticsearch-Container läuft
if docker ps | grep -q elasticsearch; then
    echo -e "${YELLOW}Ein Elasticsearch-Container läuft bereits. Möchten Sie ihn stoppen und neu starten?${NC}"
    read -p "Container stoppen und neu starten (j/N)? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        echo "Stoppe laufenden Container..."
        docker stop elasticsearch
        docker rm elasticsearch
    else
        echo "Bestehenden Container beibehalten."
        exit 0
    fi
fi

# Starte einen minimalen Elasticsearch-Container
echo -e "\n${YELLOW}Starte minimalen Elasticsearch-Container...${NC}"
docker run -d --name elasticsearch \
  -p 9200:9200 -p 9300:9300 \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=false" \
  -e "xpack.ml.enabled=false" \
  -e "xpack.watcher.enabled=false" \
  -e "xpack.monitoring.enabled=false" \
  -e "ES_JAVA_OPTS=-Xms128m -Xmx128m" \
  -m 512m --memory-swap 512m \
  docker.elastic.co/elasticsearch/elasticsearch:7.17.13

echo -e "\n${YELLOW}Warte auf Elasticsearch-Start...${NC}"
for i in {1..60}; do
    if curl -s http://localhost:9200 &> /dev/null; then
        echo -e "\n${GREEN}✓${NC} Elasticsearch ist bereit"
        curl -s http://localhost:9200 | grep -o '"version".*"number":"[^"]*"'
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 60 ]; then
        echo -e "\n${RED}Timeout beim Warten auf Elasticsearch.${NC}"
        echo "Überprüfen Sie den Status mit: docker logs elasticsearch"
        exit 1
    fi
done

# Erstelle einfachen Index für Tests
echo -e "\n${YELLOW}Erstelle Test-Index...${NC}"
curl -X PUT "localhost:9200/test-index" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "properties": {
      "content": { "type": "text" }
    }
  }
}
'

echo -e "\n${YELLOW}Füge Test-Dokument hinzu...${NC}"
curl -X POST "localhost:9200/test-index/_doc" -H 'Content-Type: application/json' -d'
{
  "content": "Dies ist ein Test-Dokument für Elasticsearch."
}
'

echo -e "\n${GREEN}Setup abgeschlossen!${NC}"
echo "Elasticsearch läuft auf http://localhost:9200"
echo -e "Sie können jetzt entweder:"
echo -e "1. RAG-Gateway starten: ${YELLOW}cd rag/gateway && npm start${NC}"
echo -e "2. Minimal-WebUI starten: ${YELLOW}docker run -d -p 3000:8080 -e OLLAMA_API_BASE_URL=http://host.docker.internal:3100/api --name open-webui ghcr.io/open-webui/open-webui:main${NC}"
echo -e "3. Elasticsearch wieder stoppen: ${YELLOW}docker stop elasticsearch${NC}"
