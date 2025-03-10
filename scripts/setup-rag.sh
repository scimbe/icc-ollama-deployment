#!/bin/bash

# Skript zum Setup der RAG-Umgebung
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== RAG-Setup für Ollama ICC Deployment ===${NC}"

# Prüfe, ob Docker installiert ist
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Fehler: Docker ist nicht installiert.${NC}"
    echo "Bitte installieren Sie Docker und versuchen Sie es erneut."
    exit 1
fi

# Prüfe, ob Docker-Compose installiert ist
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Docker Compose nicht gefunden, verwende Docker Compose Plugin...${NC}"
    if ! docker compose version &> /dev/null; then
        echo -e "${RED}Fehler: Weder Docker Compose noch das Docker Compose Plugin sind installiert.${NC}"
        echo "Bitte installieren Sie Docker Compose und versuchen Sie es erneut."
        exit 1
    fi
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Prüfe, ob Port-Forwarding für Ollama aktiv ist
echo -e "\n${YELLOW}Prüfe Ollama-Verfügbarkeit...${NC}"
if curl -s http://localhost:11434/api/tags &> /dev/null; then
    echo -e "${GREEN}✓${NC} Ollama ist verfügbar unter http://localhost:11434"
else
    echo -e "${RED}✗${NC} Ollama scheint nicht unter http://localhost:11434 verfügbar zu sein."
    echo "Bitte stellen Sie sicher, dass Ollama läuft und port-forwarding aktiv ist:"
    echo "kubectl -n \$NAMESPACE port-forward svc/\$OLLAMA_SERVICE_NAME 11434:11434"
    echo -e "\nMöchten Sie trotzdem fortfahren? Die RAG-Umgebung wird ohne Ollama-Verbindung nicht funktionieren."
    read -p "Fortfahren (j/N)? " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        echo "Abbruch."
        exit 1
    fi
fi

# Überprüfe Docker-Ressourcen (wenn möglich)
echo -e "\n${YELLOW}Prüfe Docker-Ressourcen...${NC}"
if command -v docker &>/dev/null && docker info 2>&1 | grep -q "Memory Limit"; then
    DOCKER_MEM=$(docker info 2>/dev/null | grep "Memory Limit:" | awk '{print $3}')
    if [[ "$DOCKER_MEM" != "0B" ]]; then
        echo "Docker Speicherlimit: $DOCKER_MEM"
        # Check if memory limit is less than 3GB and Docker Desktop is being used
        if docker info 2>/dev/null | grep -q "Desktop" && [[ $(echo "$DOCKER_MEM" | sed 's/GiB//') -lt 3 ]]; then
            echo -e "${YELLOW}Warnung: Docker hat weniger als 3GB RAM zugewiesen.${NC}"
            echo "Für optimale Leistung von Elasticsearch wird empfohlen, mindestens 3GB in Docker Desktop-Einstellungen zuzuweisen."
            echo -e "Möchten Sie trotzdem fortfahren?"
            read -p "Fortfahren (j/N)? " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Jj]$ ]]; then
                echo "Bitte erhöhen Sie den für Docker verfügbaren Speicher in den Docker Desktop-Einstellungen."
                exit 1
            fi
        fi
    else
        echo "Docker hat kein Speicherlimit (unbegrenzt oder nicht ermittelbar)."
    fi
else
    echo "Docker-Ressourcen können nicht überprüft werden."
fi

# Setup der RAG-Umgebung mit Docker-Compose
echo -e "\n${YELLOW}Starte RAG-Infrastruktur...${NC}"
cd "$ROOT_DIR/rag"

# Prüfe, ob docker-compose.yml existiert
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}Fehler: docker-compose.yml wurde nicht gefunden in $ROOT_DIR/rag${NC}"
    exit 1
fi

# Starte die Container
echo "Starte Elasticsearch, Kibana und RAG-Gateway..."
$DOCKER_COMPOSE up -d

# Warte auf Elasticsearch (mit mehr Geduld)
echo -e "\n${YELLOW}Warte auf Elasticsearch...${NC}"
for i in {1..90}; do
    if curl -s http://localhost:9200 &> /dev/null; then
        echo -e "\n${GREEN}✓${NC} Elasticsearch ist bereit"
        # Zeige Elasticsearch-Status an
        ES_STATUS=$(curl -s http://localhost:9200/_cluster/health | sed 's/[{},"]//g' | sed 's/:/: /g')
        echo -e "Elasticsearch Status:\n$ES_STATUS"
        break
    fi
    echo -n "."
    sleep 3
    if [ $i -eq 90 ]; then
        echo -e "\n${RED}Timeout beim Warten auf Elasticsearch.${NC}"
        echo "Überprüfen Sie den Status mit: docker logs elasticsearch"
        echo -e "\nMöchten Sie trotzdem mit Kibana und dem RAG-Gateway fortfahren?"
        read -p "Fortfahren (j/N)? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Jj]$ ]]; then
            echo "Stoppe Container..."
            $DOCKER_COMPOSE down
            exit 1
        fi
    fi
done

# Warte auf Kibana
echo -e "\n${YELLOW}Warte auf Kibana...${NC}"
for i in {1..60}; do
    if curl -s http://localhost:5601 &> /dev/null; then
        echo -e "\n${GREEN}✓${NC} Kibana ist bereit"
        break
    fi
    echo -n "."
    sleep 3
    if [ $i -eq 60 ]; then
        echo -e "\n${RED}Timeout beim Warten auf Kibana.${NC}"
        echo "Überprüfen Sie den Status mit: docker logs kibana"
        echo -e "\nMöchten Sie trotzdem mit dem RAG-Gateway fortfahren?"
        read -p "Fortfahren (j/N)? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Jj]$ ]]; then
            echo "Stoppe Container..."
            $DOCKER_COMPOSE down
            exit 1
        fi
    fi
done

# Warte auf das RAG-Gateway
echo -e "\n${YELLOW}Warte auf das RAG-Gateway...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:3100/api/health &> /dev/null; then
        echo -e "\n${GREEN}✓${NC} RAG-Gateway ist bereit"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e "\n${RED}Timeout beim Warten auf das RAG-Gateway.${NC}"
        echo "Überprüfen Sie den Status mit: docker logs rag-gateway"
    fi
done

# Setup abgeschlossen
echo -e "\n${GREEN}RAG-Setup abgeschlossen!${NC}"
echo -e "\nZugriff auf die Dienste:"
echo -e "- Elasticsearch: ${YELLOW}http://localhost:9200${NC}"
echo -e "- Kibana:        ${YELLOW}http://localhost:5601${NC}"
echo -e "- RAG-Gateway:   ${YELLOW}http://localhost:3100${NC}"
echo -e "- Ollama WebUI:  ${YELLOW}http://localhost:3000${NC}"

echo -e "\n${GREEN}Tipps:${NC}"
echo -e "1. Laden Sie Testdokumente hoch: ${YELLOW}./scripts/upload-rag-documents.sh${NC}"
echo -e "2. Stellen Sie sicher, dass Ollama weiterhin über Port-Forwarding verfügbar bleibt:"
echo -e "   ${YELLOW}kubectl -n \$NAMESPACE port-forward svc/\$OLLAMA_SERVICE_NAME 11434:11434${NC}"
echo -e "3. Testen Sie die RAG-Funktionalität über die WebUI unter ${YELLOW}http://localhost:3000${NC}"
echo -e "4. Benutzen Sie ${YELLOW}./scripts/stop-rag.sh${NC} um alle Container zu stoppen"

# Schnellstart-Beispiel anzeigen
echo -e "\n${YELLOW}Schnellstart-Beispiel:${NC}"
echo -e "Um ein Beispieldokument hochzuladen und sofort zu testen, führen Sie aus:"
echo -e "${YELLOW}./scripts/upload-rag-documents.sh rag/data/sample-document.md${NC}"
echo -e "Öffnen Sie dann ${YELLOW}http://localhost:3000${NC} und fragen Sie: 'Was ist RAG und wie funktioniert es?'"
