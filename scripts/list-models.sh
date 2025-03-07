#!/bin/bash

# Skript zum Anzeigen der installierten Ollama-Modelle
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

echo "=== Installierte Ollama-Modelle ==="
echo "Namespace: $NAMESPACE"

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Fehler: Konnte keinen laufenden Ollama Pod finden.${NC}"
    echo "Bitte stellen Sie sicher, dass Ollama läuft."
    exit 1
fi

echo "Pod: $POD_NAME"
echo

# Prüfe, ob der Pod bereit ist
POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$POD_STATUS" != "Running" ]; then
    echo -e "${RED}Fehler: Der Ollama Pod ist nicht im Status 'Running', sondern im Status '$POD_STATUS'.${NC}"
    exit 1
fi

# Versuche, die installierten Modelle direkt vom Pod zu erhalten
echo -e "Methode 1: Abfrage via Pod CLI"
echo -e "${YELLOW}Bei detaillierten Informationen werden Modellnamen, Größe und Tags angezeigt:${NC}"
if MODELS_OUTPUT=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama list 2>/dev/null); then
    echo -e "${GREEN}✓ Erfolg: Modelle erfolgreich abgefragt${NC}"
    echo
    echo "$MODELS_OUTPUT"
    
    # Zähle die Modelle
    MODEL_COUNT=$(echo "$MODELS_OUTPUT" | grep -v "NAME" | wc -l)
    echo
    echo -e "${GREEN}Insgesamt $MODEL_COUNT Modelle installiert.${NC}"
else
    echo -e "${RED}✗ Fehler: Konnte Modelle nicht vom Pod abfragen${NC}"
    echo "Versuche alternative Methode..."
    echo
fi

# Zweite Methode: Nutze die Ollama API via Port-Forwarding
echo -e "\n=== Alternative Methode: Abfrage via API ==="

# Starte temporäres Port-Forwarding
echo "Starte temporäres Port-Forwarding..."
kubectl -n "$NAMESPACE" port-forward "svc/$OLLAMA_SERVICE_NAME" 11434:11434 &>/dev/null &
PORT_FWD_PID=$!

# Cleanup-Funktion
cleanup() {
    if [ -n "$PORT_FWD_PID" ]; then
        kill $PORT_FWD_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Warte kurz, damit das Port-Forwarding aktiv wird
sleep 2

# Führe API-Anfrage durch
API_RESPONSE=$(curl -s http://localhost:11434/api/tags 2>/dev/null)
if [ -n "$API_RESPONSE" ]; then
    echo -e "${GREEN}✓ API-Abfrage erfolgreich${NC}"
    
    # Prüfe, ob jq installiert ist
    if command -v jq &> /dev/null; then
        echo
        echo "Modelle aus API-Abfrage (mit Details):"
        echo "$API_RESPONSE" | jq -r '.models[] | "Name: \(.name)\t Größe: \(.size)\t Format: \(.format)\t Parameter: \(.parameter_size)"'
        
        # Zähle die Modelle
        MODEL_COUNT=$(echo "$API_RESPONSE" | jq -r '.models | length')
        echo
        echo -e "${GREEN}Insgesamt $MODEL_COUNT Modelle installiert (laut API).${NC}"
    else
        echo
        echo "Modelle aus API-Abfrage (ohne jq):"
        echo "$API_RESPONSE" | grep -o '"name":"[^"]*"' | sed 's/"name":"//g' | sed 's/"//g'
    fi
else
    echo -e "${RED}✗ API-Abfrage fehlgeschlagen${NC}"
fi

# Zusätzliche Information zu verfügbarem Speicher
echo -e "\n=== GPU-Speicher ==="
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv,noheader 2>/dev/null; then
    echo -e "\n${GREEN}Hinweis: Achten Sie auf ausreichend freien GPU-Speicher, wenn Sie neue Modelle laden möchten.${NC}"
else
    echo -e "${YELLOW}GPU-Information nicht verfügbar.${NC}"
fi

echo -e "\n=== Befehle zum Laden neuer Modelle ==="
echo "Um ein neues Modell zu laden, verwenden Sie:"
echo "./scripts/pull-model.sh <modellname>"
echo
echo "Beispiele:"
echo "./scripts/pull-model.sh llama3:8b       # Llama 3 (8B Parameter)"
echo "./scripts/pull-model.sh gemma:2b        # Gemma (2B Parameter)"
echo "./scripts/pull-model.sh phi3:mini       # Phi-3 mini"
echo "./scripts/pull-model.sh mistral:7b      # Mistral (7B Parameter)"
