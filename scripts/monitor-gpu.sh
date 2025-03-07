#!/bin/bash

# GPU-Monitoring-Skript für Ollama in Kubernetes
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
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "GPU-Monitoring für Ollama in Kubernetes"
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -i, --interval    Aktualisierungsintervall in Sekunden (Standard: 2)"
    echo "  -c, --count       Anzahl der Messungen (Standard: kontinuierlich)"
    echo "  -f, --format      Ausgabeformat: 'full', 'compact' oder 'csv' (Standard: full)"
    echo "  -s, --save        Daten in CSV-Datei speichern (Dateiname als Argument)"
    echo
    echo "Beispiele:"
    echo "  $0                             # Standard-Monitoring mit allen Details"
    echo "  $0 -i 5 -c 10                  # 10 Messungen im 5-Sekunden-Intervall"
    echo "  $0 -f compact                  # Kompaktere Ausgabe"
    echo "  $0 -f csv -s gpu_metrics.csv   # Speichere im CSV-Format"
    exit 0
}

# Standardwerte
INTERVAL=2
COUNT=0  # 0 = kontinuierlich
FORMAT="full"
SAVE_FILE=""

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -c|--count)
            COUNT="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -s|--save)
            SAVE_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_help
            ;;
    esac
done

# Überprüfe ob das Ollama Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "Fehler: Konnte keinen laufenden Ollama Pod finden."
    exit 1
fi

# Überprüfe, ob nvidia-smi im Pod verfügbar ist
if ! kubectl -n "$NAMESPACE" exec "$POD_NAME" -- which nvidia-smi &> /dev/null; then
    echo "Fehler: nvidia-smi ist im Pod nicht verfügbar. Ist GPU aktiviert?"
    exit 1
fi

# CSV-Header initialisieren, falls erforderlich
if [ -n "$SAVE_FILE" ]; then
    echo "Zeitstempel,GPU-Index,GPU-Name,Temperatur,GPU-Auslastung,Speicher-Auslastung,Verwendeter Speicher,Freier Speicher" > "$SAVE_FILE"
    echo "CSV-Ausgabe wird in '$SAVE_FILE' gespeichert."
fi

# Monitoring-Funktion für volle Ausgabe
monitor_full() {
    local iteration=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo "=== GPU-Monitoring ($timestamp, Iteration $iteration) ==="
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi
    
    echo -e "\n--- Prozesse ---"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
    
    # Speichere in CSV, falls erforderlich
    if [ -n "$SAVE_FILE" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
            echo "$timestamp,$line" >> "$SAVE_FILE"
        done
    fi
}

# Monitoring-Funktion für kompakte Ausgabe
monitor_compact() {
    local iteration=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] Iteration $iteration"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv
    
    # Speichere in CSV, falls erforderlich
    if [ -n "$SAVE_FILE" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
            echo "$timestamp,$line" >> "$SAVE_FILE"
        done
    fi
}

# Monitoring-Funktion für CSV-Ausgabe
monitor_csv() {
    local iteration=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
        echo "$timestamp,$line"
        
        # Speichere in CSV, falls erforderlich
        if [ -n "$SAVE_FILE" ]; then
            echo "$timestamp,$line" >> "$SAVE_FILE"
        fi
    done
}

# Hauptmonitoring-Schleife
echo "Starte GPU-Monitoring für Pod '$POD_NAME'..."
echo "Intervall: $INTERVAL Sekunden"
if [ "$COUNT" -gt 0 ]; then
    echo "Anzahl Messungen: $COUNT"
else
    echo "Modus: Kontinuierliches Monitoring (CTRL+C zum Beenden)"
fi
echo "Format: $FORMAT"
echo

# Initialisiere Zähler
iteration=1

# Starte Monitoring-Schleife
while true; do
    case "$FORMAT" in
        "full")
            monitor_full $iteration
            ;;
        "compact")
            monitor_compact $iteration
            ;;
        "csv")
            monitor_csv $iteration
            ;;
        *)
            echo "Unbekanntes Format: $FORMAT"
            exit 1
            ;;
    esac
    
    # Prüfe, ob wir die gewünschte Anzahl erreicht haben
    if [ "$COUNT" -gt 0 ] && [ "$iteration" -ge "$COUNT" ]; then
        echo "Monitoring abgeschlossen ($COUNT Messungen)."
        break
    fi
    
    # Warte das angegebene Intervall
    sleep "$INTERVAL"
    
    # Inkrementiere Zähler
    ((iteration++))
done
