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
BLUE='\033[0;34m'
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

# Prüfe, ob curl installiert ist
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Fehler: curl ist nicht installiert.${NC}"
    echo "Bitte installieren Sie curl und versuchen Sie es erneut."
    exit 1
fi

# Prüfe, ob jq installiert ist (optional, aber nützlich für die Validierung)
JQ_AVAILABLE=false
if command -v jq &> /dev/null; then
    JQ_AVAILABLE=true
else
    echo -e "${YELLOW}Hinweis: jq ist nicht installiert. Die Systemvalidierung wird vereinfacht durchgeführt.${NC}"
    echo "Für bessere Ergebnisse empfehlen wir die Installation von jq."
fi

# Prüfe, ob Port-Forwarding für Ollama aktiv ist
echo -e "\n${YELLOW}Prüfe Ollama-Verfügbarkeit...${NC}"
if curl -s http://localhost:11434/api/tags &> /dev/null; then
    echo -e "${GREEN}✓${NC} Ollama ist verfügbar unter http://localhost:11434"
    
    # Prüfe, ob mindestens ein Modell verfügbar ist
    MODELS_RESPONSE=$(curl -s http://localhost:11434/api/tags)
    if [[ "$JQ_AVAILABLE" == "true" ]]; then
        MODEL_COUNT=$(echo "$MODELS_RESPONSE" | jq -r '.models | length')
        if [[ "$MODEL_COUNT" -gt 0 ]]; then
            MODEL_NAME=$(echo "$MODELS_RESPONSE" | jq -r '.models[0].name')
            echo -e "   Verfügbares Modell: ${BLUE}$MODEL_NAME${NC} (und $((MODEL_COUNT-1)) weitere)"
        else
            echo -e "${YELLOW}⚠ Keine Modelle in Ollama gefunden.${NC}"
            echo "Bitte laden Sie ein Modell mit einem dieser Befehle:"
            echo "kubectl -n \$NAMESPACE exec \$POD_NAME -- ollama pull llama3:8b"
            echo "oder"
            echo "./scripts/pull-model.sh llama3:8b"
        fi
    else
        if [[ "$MODELS_RESPONSE" == *"models"* ]]; then
            echo -e "   Mindestens ein Modell ist verfügbar"
        else
            echo -e "${YELLOW}⚠ Möglicherweise sind keine Modelle in Ollama geladen.${NC}"
        fi
    fi
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

# Stoppe zuerst alle möglicherweise laufenden Container für einen sauberen Start
echo "Stoppe eventuell laufende Container..."
$DOCKER_COMPOSE down 2>/dev/null || true

# Starte die Container
echo "Starte Elasticsearch, Kibana, RAG-Gateway und Open WebUI..."
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
        echo -e "\nMöchten Sie trotzdem mit den anderen Komponenten fortfahren?"
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
        GATEWAY_STATUS=$(curl -s http://localhost:3100/api/health)
        echo -e "\n${GREEN}✓${NC} RAG-Gateway ist bereit"
        
        # Zeige Gateway-Status an, falls möglich
        if [[ "$JQ_AVAILABLE" == "true" ]]; then
            ES_STATUS=$(echo "$GATEWAY_STATUS" | jq -r '.elasticsearch')
            echo -e "   Elasticsearch-Verbindungsstatus: ${BLUE}$ES_STATUS${NC}"
        fi
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e "\n${RED}Timeout beim Warten auf das RAG-Gateway.${NC}"
        echo "Überprüfen Sie den Status mit: docker logs rag-gateway"
        echo -e "\nMöchten Sie trotzdem mit der Open WebUI fortfahren?"
        read -p "Fortfahren (j/N)? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Jj]$ ]]; then
            echo "Stoppe Container..."
            $DOCKER_COMPOSE down
            exit 1
        fi
    fi
done

# Warte auf Open WebUI
echo -e "\n${YELLOW}Warte auf Open WebUI...${NC}"
for i in {1..45}; do
    if curl -s http://localhost:3000 &> /dev/null; then
        echo -e "\n${GREEN}✓${NC} Open WebUI ist bereit"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 45 ]; then
        echo -e "\n${RED}Timeout beim Warten auf Open WebUI.${NC}"
        echo "Überprüfen Sie den Status mit: docker logs open-webui"
    fi
done

# Führe einen Systemtest durch, um die gesamte Funktionalität zu validieren
echo -e "\n${YELLOW}Führe Systemvalidierung durch...${NC}"

# 1. Teste die Verbindung zum RAG-Gateway
echo -e "1. Teste RAG-Gateway-Verbindung..."
if HEALTH_RESPONSE=$(curl -s http://localhost:3100/api/health); then
    echo -e "   ${GREEN}✓${NC} RAG-Gateway ist erreichbar"
    
    # Überprüfe die Elasticsearch-Verbindung
    if [[ "$JQ_AVAILABLE" == "true" ]]; then
        ES_CONN=$(echo "$HEALTH_RESPONSE" | jq -r '.elasticsearch')
        if [[ "$ES_CONN" == "connected" ]]; then
            echo -e "   ${GREEN}✓${NC} Elasticsearch ist mit dem Gateway verbunden"
        else
            echo -e "   ${YELLOW}⚠${NC} Elasticsearch ist nicht mit dem Gateway verbunden ($ES_CONN)"
            echo "   Warten Sie einige Minuten, bis die Verbindung hergestellt wird"
        fi
    else
        echo -e "   Gateway-Status: $HEALTH_RESPONSE"
    fi
else
    echo -e "   ${RED}✗${NC} RAG-Gateway ist nicht erreichbar"
fi

# 2. Teste die Verbindung zur Open WebUI
echo -e "2. Teste Open WebUI-Verbindung..."
if curl -s http://localhost:3000 &> /dev/null; then
    echo -e "   ${GREEN}✓${NC} Open WebUI ist erreichbar"
else
    echo -e "   ${RED}✗${NC} Open WebUI ist nicht erreichbar"
fi

# 3. Teste die End-to-End-Funktionalität, wenn ein Modell verfügbar ist
echo -e "3. Teste End-to-End-Funktionalität (einfache Anfrage)..."

# Lade ein Beispieldokument hoch, wenn Elasticsearch verbunden ist
if [[ "$ES_CONN" == "connected" ]]; then
    SAMPLE_DOC="$ROOT_DIR/rag/data/sample-document.md"
    if [ -f "$SAMPLE_DOC" ]; then
        echo -e "   Lade Beispieldokument für RAG-Test hoch..."
        CONTENT=$(cat "$SAMPLE_DOC" | tr -d '\n' | tr -d '"' | head -c 1000)
        UPLOAD_RESPONSE=$(curl -s -X POST "http://localhost:3100/api/rag/documents" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$CONTENT\",\"metadata\":{\"filename\":\"sample-document.md\",\"type\":\"test\"}}")
        
        if [[ "$JQ_AVAILABLE" == "true" ]]; then
            UPLOAD_SUCCESS=$(echo "$UPLOAD_RESPONSE" | jq -r '.success')
            if [[ "$UPLOAD_SUCCESS" == "true" ]]; then
                echo -e "   ${GREEN}✓${NC} Testdokument erfolgreich hochgeladen"
            else
                echo -e "   ${YELLOW}⚠${NC} Testdokument konnte nicht hochgeladen werden"
            fi
        else
            if [[ "$UPLOAD_RESPONSE" == *"success"* ]]; then
                echo -e "   ${GREEN}✓${NC} Testdokument scheint erfolgreich hochgeladen worden zu sein"
            else
                echo -e "   ${YELLOW}⚠${NC} Testdokument konnte möglicherweise nicht hochgeladen werden"
            fi
        fi
    else
        echo -e "   ${YELLOW}⚠${NC} Beispieldokument nicht gefunden: $SAMPLE_DOC"
    fi
fi

# Teste eine einfache Inferenz über das Gateway
echo -e "   Teste Ollama-Verbindung über das Gateway..."
TEST_PROMPT="Erkläre in einem Satz, was RAG ist."
TEST_RESPONSE=$(curl -s -X POST "http://localhost:3100/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"$TEST_PROMPT\"}")

if [[ "$TEST_RESPONSE" == *"response"* ]]; then
    echo -e "   ${GREEN}✓${NC} Gateway kann erfolgreich mit Ollama kommunizieren"
    
    # Extrahiere einen Teil der Antwort
    if [[ "$JQ_AVAILABLE" == "true" ]]; then
        RESPONSE_TEXT=$(echo "$TEST_RESPONSE" | jq -r '.response' | head -c 100)
        RAG_ENHANCED=$(echo "$TEST_RESPONSE" | jq -r '.rag.enhanced')
        RAG_DOCS=$(echo "$TEST_RESPONSE" | jq -r '.rag.docsCount')
        
        echo -e "   Antwort (Ausschnitt): ${BLUE}\"$RESPONSE_TEXT...\"${NC}"
        echo -e "   RAG aktiviert: $RAG_ENHANCED, Gefundene Dokumente: $RAG_DOCS"
    else
        echo -e "   Antwort erhalten (installieren Sie jq für detailliertere Informationen)"
    fi
else
    echo -e "   ${RED}✗${NC} Kommunikation mit Ollama über das Gateway fehlgeschlagen"
    echo "   Stellen Sie sicher, dass Ollama läuft und ein Modell geladen ist"
fi

# Abschluss und Zusammenfassung
echo -e "\n${GREEN}RAG-Setup abgeschlossen!${NC}"
echo -e "\nZugriff auf die Dienste:"
echo -e "- Elasticsearch: ${YELLOW}http://localhost:9200${NC}"
echo -e "- Kibana:        ${YELLOW}http://localhost:5601${NC}"
echo -e "- RAG-Gateway:   ${YELLOW}http://localhost:3100${NC}"
echo -e "- Ollama WebUI:  ${YELLOW}http://localhost:3000${NC}"

echo -e "\n${GREEN}Tipps:${NC}"
echo -e "1. Laden Sie weitere Dokumente hoch: ${YELLOW}./scripts/upload-rag-documents.sh pfad/zur/datei.md${NC}"
echo -e "2. Stellen Sie sicher, dass Ollama weiterhin über Port-Forwarding verfügbar bleibt:"
echo -e "   ${YELLOW}kubectl -n \$NAMESPACE port-forward svc/\$OLLAMA_SERVICE_NAME 11434:11434${NC}"
echo -e "3. Testen Sie die RAG-Funktionalität über die WebUI unter ${YELLOW}http://localhost:3000${NC}"
echo -e "4. Benutzen Sie ${YELLOW}./scripts/stop-rag.sh${NC} um alle Container zu stoppen"

# Schnellstart-Beispiel anzeigen
echo -e "\n${YELLOW}Schnellstart-Beispiel:${NC}"
echo -e "Um ein Beispieldokument hochzuladen und sofort zu testen, führen Sie aus:"
echo -e "${YELLOW}./scripts/upload-rag-documents.sh --direct rag/data/sample-document.md${NC}"
echo -e "Öffnen Sie dann ${YELLOW}http://localhost:3000${NC} und fragen Sie: 'Was ist RAG und wie funktioniert es?'"
