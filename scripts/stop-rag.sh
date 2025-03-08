#!/bin/bash

# Skript zum Stoppen des Ollama-Elasticsearch-RAG-Systems

set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farben für die Ausgabe
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Ollama-Elasticsearch-RAG-System stoppen ===${NC}"

cd "$ROOT_DIR"

# Bestimme die richtige Docker Compose-Version
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

$DOCKER_COMPOSE down

echo -e "\n${GREEN}Alle Dienste wurden gestoppt.${NC}"
echo "Die Datenvolumes bleiben erhalten. Um auch diese zu löschen, führen Sie aus:"
echo "cd $ROOT_DIR && $DOCKER_COMPOSE down -v"
