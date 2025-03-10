#!/bin/bash

# Skript zum Stoppen der RAG-Umgebung
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Stoppe RAG-Umgebung ===${NC}"

# Prüfe Docker-Compose-Verfügbarkeit
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Docker Compose nicht gefunden, verwende Docker Compose Plugin...${NC}"
    if ! docker compose version &> /dev/null; then
        echo -e "${RED}Fehler: Weder Docker Compose noch das Docker Compose Plugin sind installiert.${NC}"
        exit 1
    fi
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

cd "$ROOT_DIR/rag"

# Prüfe, ob docker-compose.yml existiert
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Fehler: docker-compose.yml wurde nicht gefunden in $ROOT_DIR/rag${NC}"
    exit 1
fi

# Stoppe die Container
echo "Stoppe alle RAG-Container..."
$DOCKER_COMPOSE down

echo -e "\n${GREEN}✓${NC} RAG-Umgebung wurde gestoppt."
