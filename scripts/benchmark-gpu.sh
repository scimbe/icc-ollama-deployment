#!/bin/bash

# GPU-Benchmark-Skript für Ollama
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
    echo "Verwendung: $0 [OPTIONEN] [MODELL]"
    echo
    echo "GPU-Benchmark für Ollama-Modelle"
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -m, --model       Zu testendes Modell (Standard: Erstes verfügbares Modell)"
    echo "  -p, --prompt      Angepasster Prompt für Tests (in Anführungszeichen)"
    echo "  -i, --iterations  Anzahl der Testdurchläufe (Standard: 3)"
    echo "  -t, --tokens      Anzahl der zu generierenden Tokens (Standard: 100)"
    echo
    echo "Beispiele:"
    echo "  $0                              # Führt Benchmark mit Standardparametern durch"
    echo "  $0 -m llama3:8b -i 5           # Testet llama3:8b mit 5 Iterationen"
    echo "  $0 -p \"Schreibe ein Gedicht\"  # Verwendet einen benutzerdefinierten Prompt"
    exit 0
}

# Standardwerte
MODEL=""
ITERATIONS=3
PROMPT="Erkläre in einem detaillierten Absatz, wie GPUs die Berechnung von Matrixmultiplikationen beschleunigen, die in neuronalen Netzwerken verwendet werden."
MAX_TOKENS=100

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -m|--model)
            MODEL="$2"
            shift 2
            ;;
        -p|--prompt)
            PROMPT="$2"
            shift 2
            ;;
        -i|--iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        -t|--tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        *)
            if [ -z "$MODEL" ]; then
                MODEL="$1"
            fi
            shift
            ;;
    esac
done

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "Fehler: Konnte keinen laufenden Ollama Pod finden."
    exit 1
fi

# Starte die Benchmark
echo "=== Ollama GPU-Benchmark ==="
echo "Pod: $POD_NAME"
echo "Anzahl Iterationen: $ITERATIONS"
echo "Max Tokens: $MAX_TOKENS"

# Prüfe GPU-Verfügbarkeit
echo -e "\n=== GPU-Verfügbarkeit prüfen ==="
if ! kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi &> /dev/null; then
    echo "❌ FEHLER: Keine GPU verfügbar oder nvidia-smi nicht installiert."
    exit 1
fi

# Hole verfügbare Modelle
echo -e "\n=== Verfügbare Modelle prüfen ==="
AVAILABLE_MODELS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama list -j 2>/dev/null | grep "name" | awk -F'"' '{print $4}')

if [ -z "$AVAILABLE_MODELS" ]; then
    echo "Keine Modelle gefunden. Bitte laden Sie zuerst ein Modell mit:"
    echo "./scripts/pull-model.sh llama3:8b"
    exit 1
fi

echo "Verfügbare Modelle:"
echo "$AVAILABLE_MODELS"

# Wenn kein Modell angegeben wurde, verwende das erste verfügbare Modell
if [ -z "$MODEL" ]; then
    MODEL=$(echo "$AVAILABLE_MODELS" | head -n 1)
    echo "Kein Modell angegeben, verwende: $MODEL"
fi

# Überprüfe, ob das gewählte Modell verfügbar ist
if ! echo "$AVAILABLE_MODELS" | grep -q "^$MODEL$"; then
    echo "⚠️ WARNUNG: Das Modell '$MODEL' scheint nicht verfügbar zu sein."
    read -p "Möchten Sie es herunterladen? (j/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        echo "Lade Modell '$MODEL' herunter..."
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama pull "$MODEL"
    else
        echo "Abbruch: Gewähltes Modell nicht verfügbar."
        exit 1
    fi
fi

# Zeige GPU-Status vor dem Benchmark
echo -e "\n=== GPU-Status vor dem Benchmark ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv

# Erstelle temporäre Datei für den Prompt
PROMPT_FILE=$(mktemp)
echo "$PROMPT" > "$PROMPT_FILE"

# Kopiere Prompt in den Pod
kubectl cp "$PROMPT_FILE" "$NAMESPACE/$POD_NAME:/tmp/prompt.txt"

# Führe Benchmarks durch
echo -e "\n=== Benchmark läuft ==="
echo "Modell: $MODEL"
echo "Prompt: $PROMPT"
echo

# Array für Ergebnisse
declare -a TIMES
declare -a TOKEN_RATES

# Führe mehrere Benchmark-Durchläufe durch
for i in $(seq 1 $ITERATIONS); do
    echo "Durchlauf $i von $ITERATIONS..."
    
    # GPU-Status vor dem Durchlauf
    GPU_USAGE_BEFORE=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    MEM_USAGE_BEFORE=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    
    # Starte Zeitmessung
    START_TIME=$(date +%s.%N)
    
    # Führe Inferenz durch
    RESULT=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c "cat /tmp/prompt.txt | ollama run $MODEL --verbose 2>&1" | tee /dev/stderr | grep -i "eval\|load\|tokens")
    
    # Ende Zeitmessung
    END_TIME=$(date +%s.%N)
    
    # GPU-Status nach dem Durchlauf
    GPU_USAGE_AFTER=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    MEM_USAGE_AFTER=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    
    # Berechne Dauer
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    TIMES[$i]=$DURATION
    
    # Extrahiere Token-Informationen
    TOKENS_INFO=$(echo "$RESULT" | grep -i "tokens")
    TOTAL_TOKENS=$(echo "$TOKENS_INFO" | grep -oE '[0-9]+' | head -n 1 || echo "0")
    
    # Berechne Tokens pro Sekunde
    if [ "$TOTAL_TOKENS" -gt 0 ]; then
        TOKEN_RATE=$(echo "scale=2; $TOTAL_TOKENS / $DURATION" | bc)
        TOKEN_RATES[$i]=$TOKEN_RATE
    else
        TOKEN_RATES[$i]="N/A"
    fi
    
    # Zeige Ergebnis dieses Durchlaufs
    echo "  Dauer: ${TIMES[$i]} Sekunden"
    echo "  Tokens: $TOTAL_TOKENS"
    echo "  Rate: ${TOKEN_RATES[$i]} Tokens/Sekunde"
    echo "  GPU-Auslastung: $GPU_USAGE_BEFORE% -> $GPU_USAGE_AFTER%"
    echo "  GPU-Speicher: $MEM_USAGE_BEFORE MB -> $MEM_USAGE_AFTER MB"
    echo
    
    # Pause zwischen den Durchläufen
    if [ "$i" -lt "$ITERATIONS" ]; then
        sleep 2
    fi
done

# Berechne Durchschnittswerte
SUM=0
for t in "${TIMES[@]}"; do
    SUM=$(echo "$SUM + $t" | bc)
done
AVG_TIME=$(echo "scale=2; $SUM / $ITERATIONS" | bc)

SUM_RATES=0
COUNT_RATES=0
for r in "${TOKEN_RATES[@]}"; do
    if [ "$r" != "N/A" ]; then
        SUM_RATES=$(echo "$SUM_RATES + $r" | bc)
        COUNT_RATES=$((COUNT_RATES + 1))
    fi
done

if [ "$COUNT_RATES" -gt 0 ]; then
    AVG_RATE=$(echo "scale=2; $SUM_RATES / $COUNT_RATES" | bc)
else
    AVG_RATE="N/A"
fi

# Zeige Benchmark-Zusammenfassung
echo -e "\n=== Benchmark-Ergebnisse ==="
echo "Modell: $MODEL"
for i in $(seq 1 $ITERATIONS); do
    echo "Durchlauf $i: ${TIMES[$i]} Sekunden (${TOKEN_RATES[$i]} Tokens/Sek.)"
done
echo
echo "Durchschnittliche Inferenz-Dauer: $AVG_TIME Sekunden"
echo "Durchschnittliche Token-Rate: $AVG_RATE Tokens/Sekunde"

# Zeige GPU-Status nach dem Benchmark
echo -e "\n=== GPU-Status nach dem Benchmark ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv

# Aufräumen
rm -f "$PROMPT_FILE" 2>/dev/null || true
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- rm -f /tmp/prompt.txt 2>/dev/null || true

echo -e "\nBenchmark abgeschlossen."
