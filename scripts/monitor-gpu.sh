#!/bin/bash

# GPU-Monitoring-Skript für Ollama in Kubernetes mit TUI (Terminal User Interface)
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
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "GPU-Monitoring mit TUI (Terminal User Interface) für Ollama in Kubernetes"
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -i, --interval    Aktualisierungsintervall in Sekunden (Standard: 2)"
    echo "  -f, --format      Ausgabeformat: 'full' oder 'compact' (Standard: compact)"
    echo "  -s, --save        Daten in CSV-Datei speichern (Dateiname als Argument)"
    echo
    echo "Beispiele:"
    echo "  $0                             # Standard-Monitoring mit TUI"
    echo "  $0 -i 5                        # 5-Sekunden-Aktualisierungsintervall"
    echo "  $0 -f full                     # Ausführlichere Anzeige"
    echo "  $0 -s gpu_metrics.csv          # Speichere parallel im CSV-Format"
    exit 0
}

# Standardwerte
INTERVAL=2
FORMAT="compact"
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

# Überprüfe, ob notwendige Befehle verfügbar sind
if ! command -v tput &> /dev/null; then
    echo "Warnung: 'tput' ist nicht installiert. Einige Formatierungsfunktionen könnten eingeschränkt sein."
    # Füge grundlegende tput-Funktionen hinzu, falls nicht vorhanden
    tput() {
        case "$1" in
            cup)
                echo -e "\033[${2};${3}H"
                ;;
            smcup|rmcup)
                # Nichts tun, wenn nicht unterstützt
                ;;
            *)
                # Für andere Befehle nichts tun
                ;;
        esac
    }
fi

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

# Temporäre Datei für die Ausgabe
TMP_OUTPUT=$(mktemp)
trap 'rm -f "$TMP_OUTPUT"' EXIT

# Monitoring-Funktion für volle Ausgabe
monitor_full() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Header
    echo -e "${BOLD}=== GPU-Monitoring ($timestamp) ===${NC}"
    echo -e "${BLUE}Pod:${NC} $POD_NAME"
    echo -e "${BLUE}Namespace:${NC} $NAMESPACE"
    echo
    
    # GPU-Informationen
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi
    
    echo -e "\n${BOLD}--- GPU-Prozesse ---${NC}"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
    
    # Top CPU-Prozesse
    echo -e "\n${BOLD}--- Top CPU-Prozesse ---${NC}"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- top -b -n 1 | head -15
    
    # Speichere in CSV, falls erforderlich
    if [ -n "$SAVE_FILE" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
            echo "$timestamp,$line" >> "$SAVE_FILE"
        done
    fi
}

# Monitoring-Funktion für kompakte Ausgabe
monitor_compact() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Header
    echo -e "${BOLD}=== GPU-Monitoring ($timestamp) ===${NC}"
    echo -e "${BLUE}Pod:${NC} $POD_NAME"
    echo -e "${BLUE}Namespace:${NC} $NAMESPACE"
    echo
    
    # GPU-Informationen in kompaktem Format
    echo -e "${BOLD}GPU-Status:${NC}"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv
    
    # Zeige laufende Ollama-Prozesse
    echo -e "\n${BOLD}Ollama-Prozesse:${NC}"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -E 'ollama|python|cuda' | grep -v grep
    
    # Speicher und CPU-Auslastung des Pods
    echo -e "\n${BOLD}Allgemeine Pod-Ressourcen:${NC}"
    kubectl -n "$NAMESPACE" top pod "$POD_NAME" 2>/dev/null || echo "Ressourcennutzung nicht verfügbar (metrics-server erforderlich)"
    
    # Speichere in CSV, falls erforderlich
    if [ -n "$SAVE_FILE" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
            echo "$timestamp,$line" >> "$SAVE_FILE"
        done
    fi
}

# Hauptmonitoring-Funktion
run_monitoring() {
    case "$FORMAT" in
        "full")
            monitor_full > "$TMP_OUTPUT"
            ;;
        "compact"|*)
            monitor_compact > "$TMP_OUTPUT"
            ;;
    esac
    cat "$TMP_OUTPUT"
}

# TUI-Fallback für Systeme ohne 'watch'
run_tui_fallback() {
    echo "Starte GPU-Monitoring für Pod '$POD_NAME'..."
    echo "Intervall: $INTERVAL Sekunden"
    echo "Format: $FORMAT"
    echo "Drücken Sie CTRL+C zum Beenden"
    echo
    
    # Kontinuierliche Schleife mit verbesserter Bildschirmaktualisierung
    # Wir vermeiden "clear", da es zu Flackern führen kann
    while true; do
        # Cursor an den Anfang des Terminals bewegen
        tput cup 0 0
        
        # Ausgabe erzeugen
        run_monitoring
        
        # Warte auf das nächste Update
        sleep "$INTERVAL"
    done
}

# Hauptfunktion
main() {
    # Terminal vorbereiten
    clear
    
    echo "Starte GPU-Monitoring für Pod '$POD_NAME'..."
    echo "Intervall: $INTERVAL Sekunden"
    echo "Format: $FORMAT"
    echo "Drücken Sie CTRL+C zum Beenden"
    
    # Verzögerung, damit die Startmeldung sichtbar ist
    sleep 1
    
    # Bildschirm speichern, um später wieder dorthin zurückzukehren
    tput smcup
    
    # Auf CTRL+C reagieren, um Terminal ordnungsgemäß wiederherzustellen
    trap 'tput rmcup; echo "GPU-Monitoring beendet."; exit 0' SIGINT SIGTERM
    
    if command -v watch &> /dev/null && [[ "$OSTYPE" != "darwin"* ]]; then
        # Verwende 'watch' für bessere TUI, aber nur auf Linux (auf macOS verursacht watch oft Probleme)
        # Erstelle ein Skript, das 'run_monitoring' aufruft
        TMP_SCRIPT=$(mktemp)
        cat << EOF > "$TMP_SCRIPT"
#!/bin/bash
source "$ROOT_DIR/configs/config.sh"
$(declare -f monitor_full)
$(declare -f monitor_compact)
$(declare -f run_monitoring)
FORMAT="$FORMAT"
NAMESPACE="$NAMESPACE"
POD_NAME="$POD_NAME"
SAVE_FILE="$SAVE_FILE"
run_monitoring
EOF
        chmod +x "$TMP_SCRIPT"
        
        # Starte watch mit dem temporären Skript
        watch --color -n "$INTERVAL" "$TMP_SCRIPT"
        
        # Aufräumen
        rm -f "$TMP_SCRIPT"
    else
        # Eigene Implementierung für macOS und für Systeme ohne 'watch'
        run_tui_fallback
    fi
    
    # Terminal wiederherstellen
    tput rmcup
}

# Starte das Monitoring
main
