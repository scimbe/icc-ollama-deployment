#!/bin/bash

# Skript zum Testen eines Ollama-Modells
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

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN] MODEL"
    echo
    echo "Testet ein Ollama-Modell mit verschiedenen Prompts"
    echo
    echo "Optionen:"
    echo "  -h, --help          Diese Hilfe anzeigen"
    echo "  -p, --prompt TEXT   Benutzerdefinierter Prompt (Standard: HAW-bezogene Frage)"
    echo "  -b, --batch FILE    Batch-Datei mit Prompts zum Testen, einer pro Zeile"
    echo "  -t, --temperature N Temperatur für die Generierung (0.0-1.0, Standard: 0.7)"
    echo "  -m, --max-tokens N  Maximale Anzahl zu generierender Tokens (Standard: 500)"
    echo
    echo "Beispiel:"
    echo "  $0 llama3:8b"
    echo "  $0 --prompt \"Was ist Reinforcement Learning?\" llama3:8b"
    echo "  $0 --batch prompts.txt haw-custom"
    exit 0
}

# Standardwerte
MODEL=""
PROMPT="Was ist die HAW Hamburg und welche Studienprogramme werden angeboten?"
BATCH_FILE=""
TEMPERATURE=0.7
MAX_TOKENS=500

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -p|--prompt)
            PROMPT="$2"
            shift 2
            ;;
        -b|--batch)
            BATCH_FILE="$2"
            shift 2
            ;;
        -t|--temperature)
            TEMPERATURE="$2"
            shift 2
            ;;
        -m|--max-tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        *)
            MODEL="$1"
            shift
            ;;
    esac
done

# Überprüfe, ob ein Modell angegeben wurde
if [ -z "$MODEL" ]; then
    echo -e "${RED}Fehler: Kein Modell angegeben.${NC}"
    show_help
    exit 1
fi

# Hole den Pod-Namen
POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l service=ollama -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Fehler: Konnte keinen laufenden Ollama Pod finden.${NC}"
    exit 1
fi

# Starte temporäres Port-Forwarding falls nötig
PORT_FORWARD_NEEDED=false
if ! nc -z localhost 11434 2>/dev/null; then
    echo -e "${YELLOW}Starte temporäres Port-Forwarding...${NC}"
    kubectl -n "$NAMESPACE" port-forward "svc/$OLLAMA_SERVICE_NAME" 11434:11434 &>/dev/null &
    PORT_FORWARD_PID=$!
    PORT_FORWARD_NEEDED=true
    # Warte kurz, damit Port-Forwarding aktiv wird
    sleep 2
    
    # Registriere cleanup
    cleanup() {
        if [ "$PORT_FORWARD_NEEDED" = true ] && [ -n "$PORT_FORWARD_PID" ]; then
            echo -e "${YELLOW}Beende Port-Forwarding...${NC}"
            kill $PORT_FORWARD_PID 2>/dev/null || true
        fi
    }
    trap cleanup EXIT
fi

# Überprüfe, ob das Modell existiert
MODEL_CHECK=$(curl -s localhost:11434/api/tags | grep -o "\"name\":\"$MODEL\"" || echo "")
if [ -z "$MODEL_CHECK" ]; then
    echo -e "${YELLOW}Warnung: Modell '$MODEL' scheint nicht verfügbar zu sein.${NC}"
    echo "Verfügbare Modelle:"
    curl -s localhost:11434/api/tags | grep -o '"name":"[^"]*"' | sed 's/"name":"//g' | sed 's/"//g' | sort
    
    # Frage, ob das Modell gepullt werden soll
    read -p "Möchten Sie das Modell '$MODEL' jetzt herunterladen? (j/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        echo -e "${GREEN}Lade Modell '$MODEL'...${NC}"
        curl -s -X POST localhost:11434/api/pull -d "{\"name\":\"$MODEL\"}" > /dev/null &
        PULL_PID=$!
        
        # Zeige Fortschritt
        echo -n "Lade Modell: "
        while kill -0 $PULL_PID 2>/dev/null; do
            echo -n "."
            sleep 2
        done
        echo " Fertig!"
        
        # Überprüfe erneut, ob das Modell jetzt verfügbar ist
        MODEL_CHECK=$(curl -s localhost:11434/api/tags | grep -o "\"name\":\"$MODEL\"" || echo "")
        if [ -z "$MODEL_CHECK" ]; then
            echo -e "${RED}Fehler: Modell konnte nicht geladen werden.${NC}"
            exit 1
        fi
    else
        echo "Abbruch."
        exit 1
    fi
fi

# Test mit einem einzelnen Prompt oder einer Batch-Datei
if [ -n "$BATCH_FILE" ]; then
    # Batch-Modus mit Datei
    if [ ! -f "$BATCH_FILE" ]; then
        echo -e "${RED}Fehler: Batch-Datei '$BATCH_FILE' nicht gefunden.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Batch-Test des Modells '$MODEL' ===${NC}"
    echo "Temperatur: $TEMPERATURE"
    echo "Max Tokens: $MAX_TOKENS"
    echo "Batch-Datei: $BATCH_FILE"
    echo "Anzahl der Prompts: $(wc -l < "$BATCH_FILE")"
    echo
    
    # Durchlaufe alle Prompts in der Datei
    PROMPT_NUM=1
    while IFS= read -r TEST_PROMPT || [ -n "$TEST_PROMPT" ]; do
        # Überspringe leere Zeilen und Kommentare
        if [ -z "$TEST_PROMPT" ] || [[ "$TEST_PROMPT" == \#* ]]; then
            continue
        fi
        
        echo -e "${YELLOW}Prompt $PROMPT_NUM:${NC} $TEST_PROMPT"
        echo
        
        # Führe die Inferenz durch
        START_TIME=$(date +%s.%N)
        RESPONSE=$(curl -s -X POST localhost:11434/api/generate -d "{
            \"model\": \"$MODEL\",
            \"prompt\": \"$TEST_PROMPT\",
            \"temperature\": $TEMPERATURE,
            \"max_tokens\": $MAX_TOKENS,
            \"stream\": false
        }" | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g')
        END_TIME=$(date +%s.%N)
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        
        # Zeige die Antwort an
        echo "$RESPONSE"
        echo
        echo -e "${GREEN}Inferenz-Dauer:${NC} $DURATION Sekunden"
        echo -e "${GREEN}Ungefähre Tokenzahl:${NC} $(echo "$RESPONSE" | wc -w)"
        echo "----------------------------------------"
        echo
        
        PROMPT_NUM=$((PROMPT_NUM + 1))
    done < "$BATCH_FILE"
    
    echo -e "${GREEN}Batch-Test abgeschlossen.${NC}"
else
    # Einzelner Prompt-Test
    echo -e "${GREEN}=== Test des Modells '$MODEL' ===${NC}"
    echo "Prompt: $PROMPT"
    echo "Temperatur: $TEMPERATURE"
    echo "Max Tokens: $MAX_TOKENS"
    echo
    
    # Führe die Inferenz durch
    START_TIME=$(date +%s.%N)
    RESPONSE=$(curl -s -X POST localhost:11434/api/generate -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"$PROMPT\",
        \"temperature\": $TEMPERATURE,
        \"max_tokens\": $MAX_TOKENS,
        \"stream\": false
    }" | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g')
    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    
    # Zeige die Antwort an
    echo "$RESPONSE"
    echo
    echo -e "${GREEN}Inferenz-Dauer:${NC} $DURATION Sekunden"
    echo -e "${GREEN}Ungefähre Tokenzahl:${NC} $(echo "$RESPONSE" | wc -w)"
    
    # Schätze die Qualität der Antwort
    if grep -q -i "HAW Hamburg" <<< "$RESPONSE" && grep -q -i "Studieng" <<< "$RESPONSE"; then
        echo -e "${GREEN}Antwortqualität:${NC} Die Antwort enthält relevante Informationen zum Prompt."
    else
        echo -e "${YELLOW}Antwortqualität:${NC} Die Antwort könnte von der Frage abweichen."
    fi
fi
