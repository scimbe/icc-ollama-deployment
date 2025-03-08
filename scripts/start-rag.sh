#!/bin/bash

# Skript zum Starten des Ollama-Elasticsearch-RAG-Systems

set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farben für die Ausgabe
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Ollama-Elasticsearch-RAG-System starten ===${NC}"

# Prüfe, ob Docker und Docker Compose installiert sind
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Fehler: Docker ist nicht installiert.${NC}"
    echo "Bitte installieren Sie Docker gemäß der Anleitung: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}Fehler: Docker Compose ist nicht installiert.${NC}"
    echo "Bitte installieren Sie Docker Compose gemäß der Anleitung: https://docs.docker.com/compose/install/"
    exit 1
fi

# Starte die Docker-Container
echo -e "\n${YELLOW}Docker-Container starten...${NC}"
cd "$ROOT_DIR"

# Bestimme die richtige Docker Compose-Version
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

$DOCKER_COMPOSE up -d

echo -e "\n${YELLOW}Warte auf Start der Dienste...${NC}"
echo "Dies kann einige Minuten dauern, besonders beim ersten Start."

# Warte auf Elasticsearch
echo -e "\n${YELLOW}Warte auf Elasticsearch...${NC}"
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if curl -s http://localhost:9200/_cluster/health | grep -q '"status":\("green"\|"yellow"\)'; then
        echo -e "${GREEN}Elasticsearch ist bereit.${NC}"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
done

if [ $elapsed -ge $timeout ]; then
    echo -e "\n${RED}Timeout beim Warten auf Elasticsearch.${NC}"
    echo "Bitte prüfen Sie die Logs mit: docker logs elasticsearch"
    exit 1
fi

# Warte auf Kibana
echo -e "\n${YELLOW}Warte auf Kibana...${NC}"
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if curl -s http://localhost:5601/api/status | grep -q '"overall":{"level":"available"'; then
        echo -e "${GREEN}Kibana ist bereit.${NC}"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
done

if [ $elapsed -ge $timeout ]; then
    echo -e "\n${RED}Timeout beim Warten auf Kibana.${NC}"
    echo "Bitte prüfen Sie die Logs mit: docker logs kibana"
fi

# Warte auf RAG Gateway
echo -e "\n${YELLOW}Warte auf RAG Gateway...${NC}"
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if curl -s http://localhost:8000/health | grep -q '"status":"healthy"'; then
        echo -e "${GREEN}RAG Gateway ist bereit.${NC}"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
done

if [ $elapsed -ge $timeout ]; then
    echo -e "\n${RED}Timeout beim Warten auf RAG Gateway.${NC}"
    echo "Bitte prüfen Sie die Logs mit: docker logs rag-gateway"
fi

echo -e "\n${GREEN}=== Ollama-Elasticsearch-RAG-System erfolgreich gestartet! ===${NC}"
echo
echo "Die folgenden Dienste sind verfügbar:"
echo "- Elasticsearch: http://localhost:9200"
echo "- Kibana: http://localhost:5601"
echo "- Ollama API: http://localhost:11434"
echo "- RAG Gateway: http://localhost:8000"
echo "- RAG Gateway API-Dokumentation: http://localhost:8000/docs"
echo
echo "Um den RAG-Prozess zu testen, können Sie folgende Anfrage stellen:"
echo "curl -X POST http://localhost:8000/v1/chat/completions -H \"Content-Type: application/json\" -d '{\"model\":\"llama3\",\"messages\":[{\"role\":\"user\",\"content\":\"Was ist künstliche Intelligenz?\"}],\"use_rag\":true}'"
echo
echo "Um das System zu stoppen, führen Sie aus:"
echo "cd $ROOT_DIR && $DOCKER_COMPOSE down"
