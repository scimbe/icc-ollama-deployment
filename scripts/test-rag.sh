#!/bin/bash

# Skript zum Testen der RAG-Funktionalität mit Elasticsearch, Kibana und Ollama
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    exit 1
fi

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Überprüfe, ob Elasticsearch, Kibana und Ollama laufen
echo "Überprüfe Komponenten..."

if ! kubectl -n "$NAMESPACE" get statefulset "$ES_DEPLOYMENT_NAME" &> /dev/null; then
    echo -e "${RED}Fehler: Elasticsearch StatefulSet '$ES_DEPLOYMENT_NAME' nicht gefunden.${NC}"
    echo "Bitte führen Sie zuerst ./scripts/rag-setup.sh aus."
    exit 1
else
    echo -e "${GREEN}✓${NC} Elasticsearch ist installiert."
fi

if ! kubectl -n "$NAMESPACE" get deployment "$KIBANA_DEPLOYMENT_NAME" &> /dev/null; then
    echo -e "${RED}Fehler: Kibana Deployment '$KIBANA_DEPLOYMENT_NAME' nicht gefunden.${NC}"
    echo "Bitte führen Sie zuerst ./scripts/rag-setup.sh aus."
    exit 1
else
    echo -e "${GREEN}✓${NC} Kibana ist installiert."
fi

if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo -e "${RED}Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden.${NC}"
    echo "Bitte führen Sie zuerst ./deploy.sh aus."
    exit 1
else
    echo -e "${GREEN}✓${NC} Ollama ist installiert."
fi

# Überprüfe, ob ein Modell in Ollama geladen ist
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
MODELS_OUTPUT=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama list 2>/dev/null)
MODEL_COUNT=$(echo "$MODELS_OUTPUT" | grep -v NAME | wc -l)

if [ "$MODEL_COUNT" -eq 0 ]; then
    echo -e "${RED}Fehler: Keine Modelle in Ollama geladen.${NC}"
    echo "Bitte laden Sie zuerst ein Modell mit ./scripts/pull-model.sh <modellname>"
    exit 1
else
    MODELS=$(echo "$MODELS_OUTPUT" | grep -v NAME | awk '{print $1}')
    echo -e "${GREEN}✓${NC} Ollama hat $MODEL_COUNT Modell(e) geladen:"
    echo "$MODELS" | sed 's/^/  - /'
fi

# Starte Port-Forwarding für Elasticsearch, Kibana und Ollama
echo -e "\nStarte Port-Forwarding für alle Services..."

# Beende alle Port-Forwarding-Prozesse bei Skriptende
cleanup() {
    echo -e "\nBeende Port-Forwarding..."
    kill $ES_PF_PID $KIBANA_PF_PID $OLLAMA_PF_PID 2>/dev/null || true
    exit 0
}
trap cleanup EXIT

# Elasticsearch Port-Forwarding
kubectl -n "$NAMESPACE" port-forward "svc/$ES_SERVICE_NAME" 9200:9200 &
ES_PF_PID=$!
echo -e "${GREEN}✓${NC} Elasticsearch Port-Forwarding gestartet auf Port 9200"

# Kibana Port-Forwarding
kubectl -n "$NAMESPACE" port-forward "svc/$KIBANA_SERVICE_NAME" 5601:5601 &
KIBANA_PF_PID=$!
echo -e "${GREEN}✓${NC} Kibana Port-Forwarding gestartet auf Port 5601"

# Ollama Port-Forwarding
kubectl -n "$NAMESPACE" port-forward "svc/$OLLAMA_SERVICE_NAME" 11434:11434 &
OLLAMA_PF_PID=$!
echo -e "${GREEN}✓${NC} Ollama Port-Forwarding gestartet auf Port 11434"

# Warte kurz, damit die Port-Forwarding-Verbindungen hergestellt werden können
sleep 3

# Teste den Elasticsearch-Zugriff
echo -e "\nTeste Elasticsearch-Verbindung..."
if ES_RESPONSE=$(curl -s -u "elastic:changeme" "http://localhost:9200/_cat/indices?v" 2>/dev/null); then
    echo -e "${GREEN}✓${NC} Elasticsearch ist erreichbar."
    # Teste, ob der rag-demo-Index existiert
    if echo "$ES_RESPONSE" | grep -q "rag-demo"; then
        echo -e "${GREEN}✓${NC} RAG-Demo-Index gefunden."
    else
        echo -e "${YELLOW}⚠${NC} RAG-Demo-Index nicht gefunden. Sie können Beispieldaten mit ./kibana/load-example-data.sh laden."
    fi
else
    echo -e "${RED}✗${NC} Elasticsearch ist nicht erreichbar."
fi

# Teste den Kibana-Zugriff
echo -e "\nTeste Kibana-Verbindung..."
if KIBANA_RESPONSE=$(curl -s "http://localhost:5601/api/status" 2>/dev/null); then
    if echo "$KIBANA_RESPONSE" | grep -q "available"; then
        echo -e "${GREEN}✓${NC} Kibana ist erreichbar und betriebsbereit."
    else
        echo -e "${YELLOW}⚠${NC} Kibana ist erreichbar, aber möglicherweise nicht vollständig gestartet."
    fi
else
    echo -e "${RED}✗${NC} Kibana ist nicht erreichbar."
fi

# Teste den Ollama-Zugriff
echo -e "\nTeste Ollama API-Verbindung..."
if OLLAMA_RESPONSE=$(curl -s "http://localhost:11434/api/tags" 2>/dev/null); then
    if echo "$OLLAMA_RESPONSE" | grep -q "models"; then
        echo -e "${GREEN}✓${NC} Ollama API ist erreichbar."
    else
        echo -e "${YELLOW}⚠${NC} Ollama API ist erreichbar, liefert aber unerwartete Antwort."
    fi
else
    echo -e "${RED}✗${NC} Ollama API ist nicht erreichbar."
fi

# Teste die OpenAI-kompatible API von Ollama (für den Connector)
echo -e "\nTeste OpenAI-kompatible Schnittstelle von Ollama..."
# Hole das erste Modell aus der Liste
FIRST_MODEL=$(echo "$MODELS" | head -n 1)

TEST_PROMPT='{
  "model": "'"$FIRST_MODEL"'",
  "messages": [
    {"role": "system", "content": "Du bist ein hilfreicher Assistent."},
    {"role": "user", "content": "Sage Hallo in einem kurzen Satz."}
  ],
  "stream": false
}'

if OPENAI_RESPONSE=$(curl -s -X POST "http://localhost:11434/v1/chat/completions" \
     -H "Content-Type: application/json" \
     -d "$TEST_PROMPT" 2>/dev/null); then
    if echo "$OPENAI_RESPONSE" | grep -q "content"; then
        echo -e "${GREEN}✓${NC} OpenAI-kompatible API funktioniert."
        # Extrahiere und zeige die Antwort
        RESPONSE=$(echo "$OPENAI_RESPONSE" | grep -o '"content":"[^"]*"' | sed 's/"content":"//g' | sed 's/"//g')
        echo -e "   Antwort: ${YELLOW}$RESPONSE${NC}"
    else
        echo -e "${YELLOW}⚠${NC} OpenAI-kompatible API antwortet, aber die Antwort hat ein unerwartetes Format."
    fi
else
    echo -e "${RED}✗${NC} OpenAI-kompatible API ist nicht erreichbar."
fi

# Tests abgeschlossen
echo -e "\n==================================================================="
echo "                     RAG-Komponenten-Test Ergebnisse                  "
echo "==================================================================="

if [ -n "$ES_RESPONSE" ] && [ -n "$KIBANA_RESPONSE" ] && [ -n "$OLLAMA_RESPONSE" ] && [ -n "$OPENAI_RESPONSE" ]; then
    echo -e "\n${GREEN}Alle Komponenten sind bereit für RAG-Anwendungen!${NC}"
    
    # URL für Kibana anzeigen
    echo -e "\nSie können Kibana unter der folgenden URL öffnen:"
    echo -e "${YELLOW}http://localhost:5601${NC}"
    echo -e "Anmeldeinformationen: elastic / changeme"
    
    # RAG-Anweisungen
    echo -e "\nUm den RAG-Workflow zu testen:"
    echo "1. Öffnen Sie Kibana im Browser"
    echo "2. Navigieren Sie zu: Elasticsearch > Playground"
    echo "3. Wählen Sie 'rag-demo' als Datenquelle (falls vorhanden)"
    echo "4. Wählen Sie den Ollama-Connector"
    echo "5. Stellen Sie eine Frage zum Text, z.B. 'Was passierte mit dem weißen Kaninchen?'"
    
    # Überwachungswerkzeuge
    echo -e "\nNützliche Befehle zur Überwachung:"
    echo "- Elasticsearch-Indizes anzeigen: curl -u elastic:changeme http://localhost:9200/_cat/indices"
    echo "- Ollama-Modelle anzeigen: curl http://localhost:11434/api/tags"
    
    echo -e "\nDie Port-Forwarding-Prozesse werden bei Beenden dieses Skripts automatisch beendet."
    echo "Drücken Sie CTRL+C, um alle Port-Forwarding-Prozesse zu beenden."
    
    # Warte auf Benutzerabbruch
    wait
else
    echo -e "\n${YELLOW}Einige Komponenten scheinen Probleme zu haben.${NC}"
    echo "Bitte überprüfen Sie die obigen Meldungen und beheben Sie etwaige Probleme."
    exit 1
fi
