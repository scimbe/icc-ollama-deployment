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
    if curl -s "http://localhost:$LOCAL_PORT/api/tags" | grep -q "models"; then
        echo "✅ Ollama API ist erreichbar und funktioniert."
        return 0
    else
        echo "❌ Ollama API ist nicht erreichbar oder antwortet nicht wie erwartet."
        return 1
    fi
}

# Hauptlogik basierend auf dem Befehl
case "$COMMAND" in
    list)
        start_port_forwarding
        echo "=== Verfügbare Modelle ==="
        curl -s "http://localhost:$LOCAL_PORT/api/tags" | jq -r '.models[] | "\(.name) (\(.size))"' || \
            echo "Fehler beim Abrufen der Modelle. Ist jq installiert?"
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
        echo "Prompt: $CUSTOM_PROMPT"
        echo 
        
        # Führe Inferenz-Test durch
        START_TIME=$(date +%s.%N)
        curl -s "http://localhost:$LOCAL_PORT/api/generate" \
            -d "{\"model\":\"$MODEL_NAME\",\"prompt\":\"$CUSTOM_PROMPT\",\"stream\":false}" | \
            jq -r '.response'
        END_TIME=$(date +%s.%N)
        
        # Berechne Dauer
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        echo 
        echo "Inferenz-Dauer: $DURATION Sekunden"
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
        
    *)
        echo "Unbekannter Befehl: $COMMAND"
        show_help
        ;;
esac
