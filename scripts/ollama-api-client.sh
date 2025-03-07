#!/bin/bash

# Ollama API Client für Modell- und GPU-Tests
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

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN] BEFEHL"
    echo
    echo "Ollama API Client für Modell- und GPU-Tests"
    echo
    echo "Befehle:"
    echo "  list              Liste aller vorhandenen Modelle anzeigen"
    echo "  test MODEL        Einfachen Inferenz-Test für das angegebene Modell durchführen"
    echo "  benchmark MODEL   Performance-Benchmark für ein Modell durchführen"
    echo "  gpu-stats         Aktuelle GPU-Auslastung anzeigen"
    echo "  api-health        Überprüfe, ob die Ollama API erreichbar ist"
    echo "  pull MODEL        Modell herunterladen"
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -p, --port        Lokaler Port für Port-Forwarding (Standard: 11434)"
    echo "  -m, --prompt      Angepasster Prompt für Tests (in Anführungszeichen)"
    echo
    echo "Beispiele:"
    echo "  $0 list                        # Alle Modelle auflisten"
    echo "  $0 test llama3:8b              # Test mit llama3:8b Modell"
    echo "  $0 benchmark llama3:8b --prompt \"Erkläre Quantencomputing\"  # Benchmark mit angepasstem Prompt"
    exit 0
}

# Standardwerte
LOCAL_PORT=11434
CUSTOM_PROMPT="Erkläre in einem kurzen Absatz, was eine GPU ist und warum sie für KI-Anwendungen wichtig ist."

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -p|--port)
            LOCAL_PORT="$2"
            shift 2
            ;;
        -m|--prompt)
            CUSTOM_PROMPT="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Überprüfe ob ein Befehl übergeben wurde
if [ $# -lt 1 ]; then
    echo "Fehler: Kein Befehl angegeben."
    show_help
fi

COMMAND=$1
shift

# Starte Port-Forwarding (falls nicht bereits aktiv)
start_port_forwarding() {
    if ! nc -z localhost "$LOCAL_PORT" 2>/dev/null; then
        echo "Starte Port-Forwarding auf Port $LOCAL_PORT..."
        kubectl -n "$NAMESPACE" port-forward svc/"$OLLAMA_SERVICE_NAME" "$LOCAL_PORT":11434 &
        PORT_FWD_PID=$!
        # Warte kurz, damit das Port-Forwarding starten kann
        sleep 2
        # Prüfe, ob Port-Forwarding erfolgreich war
        if ! nc -z localhost "$LOCAL_PORT" 2>/dev/null; then
            echo "Fehler: Port-Forwarding konnte nicht gestartet werden."
            kill $PORT_FWD_PID 2>/dev/null || true
            exit 1
        fi
        echo "Port-Forwarding aktiv."
        # Registriere Cleanup-Funktion
        trap 'kill $PORT_FWD_PID 2>/dev/null || true' EXIT
    else
        echo "Port-Forwarding ist bereits aktiv."
    fi
}

# API-Gesundheitscheck
check_api_health() {
    API_RESPONSE=$(curl -s "http://localhost:$LOCAL_PORT/api/tags" 2>/dev/null)
    if [ -n "$API_RESPONSE" ] && [[ "$API_RESPONSE" == *"models"* ]]; then
        echo "✅ Ollama API ist erreichbar und funktioniert."
        return 0
    else
        echo "❌ Ollama API ist nicht erreichbar oder antwortet nicht wie erwartet."
        return 1
    fi
}

# Parse Modelle ohne jq
parse_models_without_jq() {
    local json="$1"
    
    # Extrahiere den models-Array (sehr einfach, nicht robust)
    local models_section=$(echo "$json" | grep -o '"models":\[.*\]' | sed 's/"models"://')
    
    # Extrahiere die Namen mit einfacher Regex-Suche
    echo "$models_section" | grep -o '"name":"[^"]*"' | sed 's/"name":"//g' | sed 's/"//g'
}

# Hole verfügbare Modelle
get_models() {
    local response=$(curl -s "http://localhost:$LOCAL_PORT/api/tags" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo "Fehler: Keine Antwort von der API."
        return 1
    fi
    
    # Versuche mit jq zu parsen, falls verfügbar
    if command -v jq &> /dev/null; then
        echo "$response" | jq -r '.models[] | "\(.name) (\(.size // "unbekannt"))"' 2>/dev/null
    else
        # Fallback ohne jq
        echo "Modelle (ohne Größenangabe, da jq nicht installiert ist):"
        parse_models_without_jq "$response"
    fi
}

# Testfunktion für die Inferenz
run_inference_test() {
    local model="$1"
    local prompt="$2"
    
    echo "Starte Inferenz mit Modell '$model'..."
    echo "Prompt: $prompt"
    echo
    
    # Führe Inferenz-Test durch
    START_TIME=$(date +%s.%N)
    local response=$(curl -s "http://localhost:$LOCAL_PORT/api/generate" \
        -d "{\"model\":\"$model\",\"prompt\":\"$prompt\",\"stream\":false}" 2>/dev/null)
    END_TIME=$(date +%s.%N)
    
    # Berechne Dauer
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    
    # Zeige Antwort an
    if [ -z "$response" ]; then
        echo "Keine Antwort von der API erhalten."
        return 1
    fi
    
    # Extrahiere die Antwort
    if command -v jq &> /dev/null; then
        echo "$response" | jq -r '.response' 2>/dev/null
    else
        # Extrahiere die Antwort ohne jq (einfach, nicht robust)
        echo "$response" | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g'
    fi
    
    echo
    echo "Inferenz-Dauer: $DURATION Sekunden"
}

# Hauptlogik basierend auf dem Befehl
case "$COMMAND" in
    list)
        start_port_forwarding
        echo "=== Verfügbare Modelle ==="
        get_models
        ;;
        
    test)
        if [ $# -lt 1 ]; then
            echo "Fehler: Kein Modellname angegeben."
            echo "Verwendung: $0 test <modellname>"
            exit 1
        fi
        MODEL_NAME=$1
        
        start_port_forwarding
        echo "=== Inferenz-Test mit Modell '$MODEL_NAME' ==="
        run_inference_test "$MODEL_NAME" "$CUSTOM_PROMPT"
        ;;
        
    benchmark)
        if [ $# -lt 1 ]; then
            echo "Fehler: Kein Modellname angegeben."
            echo "Verwendung: $0 benchmark <modellname>"
            exit 1
        fi
        MODEL_NAME=$1
        
        start_port_forwarding
        echo "=== Performance-Benchmark für Modell '$MODEL_NAME' ==="
        echo "Führe 3 Inferenz-Tests durch und messe die Zeit..."
        
        # Führe mehrere Tests durch
        declare -a TIMES
        for i in {1..3}; do
            echo -e "\n--- Test $i ---"
            START_TIME=$(date +%s.%N)
            curl -s "http://localhost:$LOCAL_PORT/api/generate" \
                -d "{\"model\":\"$MODEL_NAME\",\"prompt\":\"$CUSTOM_PROMPT\",\"stream\":false}" > /dev/null
            END_TIME=$(date +%s.%N)
            DURATION=$(echo "$END_TIME - $START_TIME" | bc)
            echo "Dauer: $DURATION Sekunden"
            TIMES[$i]=$DURATION
            sleep 1
        done
        
        # Berechne Durchschnitt
        SUM=$(echo "${TIMES[1]} + ${TIMES[2]} + ${TIMES[3]}" | bc)
        AVG=$(echo "scale=2; $SUM / 3" | bc)
        echo -e "\n=== Ergebnis ==="
        echo "Durchschnittliche Inferenz-Dauer: $AVG Sekunden"
        ;;
        
    gpu-stats)
        echo "=== GPU-Statistiken ==="
        POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
        if [ -z "$POD_NAME" ]; then
            echo "Fehler: Konnte keinen laufenden Ollama Pod finden."
            exit 1
        fi
        
        # Führe nvidia-smi aus
        echo "GPU-Statistiken von Pod '$POD_NAME':"
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv
        ;;
        
    api-health)
        start_port_forwarding
        check_api_health
        ;;
        
    pull)
        if [ $# -lt 1 ]; then
            echo "Fehler: Kein Modellname angegeben."
            echo "Verwendung: $0 pull <modellname>"
            exit 1
        fi
        MODEL_NAME=$1
        
        POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
        if [ -z "$POD_NAME" ]; then
            echo "Fehler: Konnte keinen laufenden Ollama Pod finden."
            exit 1
        fi
        
        echo "Starte den Download von Modell '$MODEL_NAME' im Pod '$POD_NAME'..."
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama pull "$MODEL_NAME"
        
        echo -e "\nModell '$MODEL_NAME' wurde heruntergeladen."
        echo "Sie können es jetzt über die WebUI oder die Ollama API verwenden."
        ;;
        
    *)
        echo "Unbekannter Befehl: $COMMAND"
        show_help
        ;;
esac
