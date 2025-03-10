#!/bin/bash

# Skript zum Konvertieren von JSONL-Trainingsdaten in ein für Ollama optimiertes Format
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "Konvertiert JSONL-Trainingsdaten in ein für Ollama optimiertes Format"
    echo
    echo "Optionen:"
    echo "  -h, --help          Diese Hilfe anzeigen"
    echo "  -i, --input FILE    Eingabedatei im JSONL-Format (Erforderlich)"
    echo "  -o, --output FILE   Ausgabedatei (Standard: input.converted.txt)"
    echo "  -f, --format FORMAT Ausgabeformat: txt, md oder ollama (Standard: txt)"
    echo
    echo "Beispiel:"
    echo "  $0 -i examples/haw_training_data.jsonl -o data/training_converted.txt"
    exit 0
}

# Standardwerte
INPUT_FILE=""
OUTPUT_FILE=""
FORMAT="txt"

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unbekannte Option: $1${NC}"
            show_help
            ;;
    esac
done

# Überprüfe, ob notwendige Parameter vorhanden sind
if [ -z "$INPUT_FILE" ]; then
    echo -e "${RED}Fehler: Keine Eingabedatei angegeben.${NC}"
    echo "Bitte geben Sie eine Eingabedatei mit -i oder --input an."
    show_help
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Fehler: Eingabedatei '$INPUT_FILE' nicht gefunden.${NC}"
    exit 1
fi

# Wenn keine Ausgabedatei angegeben, erstelle Standardnamen
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${INPUT_FILE%.*}.converted.${FORMAT}"
fi

echo -e "${GREEN}=== Konvertiere Trainingsdaten ===${NC}"
echo "Eingabedatei: $INPUT_FILE"
echo "Ausgabedatei: $OUTPUT_FILE"
echo "Format: $FORMAT"

# Validiere Eingabedatei-Format (JSONL)
if ! grep -q '"prompt":' "$INPUT_FILE" || ! grep -q '"response":' "$INPUT_FILE"; then
    echo -e "${RED}Fehler: Eingabedatei scheint nicht im JSONL-Format mit 'prompt' und 'response' Feldern zu sein.${NC}"
    echo "Beispiel für korrektes Format:"
    echo '{"prompt": "Wer ist die HAW?", "response": "Die HAW Hamburg ist eine Hochschule für angewandte Wissenschaften."}'
    exit 1
fi

# Konvertiere basierend auf dem ausgewählten Format
case "$FORMAT" in
    txt)
        # Einfaches Textformat mit klaren Trennlinien
        > "$OUTPUT_FILE"  # Leere Datei erstellen/überschreiben
        
        while IFS= read -r line; do
            prompt=$(echo "$line" | grep -o '"prompt":"[^"]*"' | sed 's/"prompt":"//g' | sed 's/"//g')
            response=$(echo "$line" | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g')
            
            echo "FRAGE:" >> "$OUTPUT_FILE"
            echo "$prompt" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "ANTWORT:" >> "$OUTPUT_FILE"
            echo "$response" >> "$OUTPUT_FILE"
            echo "----------------------------------------" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        done < "$INPUT_FILE"
        ;;
        
    md)
        # Markdown-Format für bessere Lesbarkeit
        > "$OUTPUT_FILE"  # Leere Datei erstellen/überschreiben
        
        while IFS= read -r line; do
            prompt=$(echo "$line" | grep -o '"prompt":"[^"]*"' | sed 's/"prompt":"//g' | sed 's/"//g')
            response=$(echo "$line" | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g')
            
            echo "## Frage" >> "$OUTPUT_FILE"
            echo "$prompt" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "## Antwort" >> "$OUTPUT_FILE"
            echo "$response" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "---" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        done < "$INPUT_FILE"
        ;;
        
    ollama)
        # Spezielles Format für Ollama-Training
        > "$OUTPUT_FILE"  # Leere Datei erstellen/überschreiben
        
        while IFS= read -r line; do
            prompt=$(echo "$line" | grep -o '"prompt":"[^"]*"' | sed 's/"prompt":"//g' | sed 's/"//g')
            response=$(echo "$line" | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g')
            
            # Format im Ollama-spezifischen Format: Human: ... Assistant: ...
            echo "Human: $prompt" >> "$OUTPUT_FILE"
            echo "Assistant: $response" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        done < "$INPUT_FILE"
        ;;
        
    *)
        echo -e "${RED}Fehler: Unbekanntes Format '$FORMAT'.${NC}"
        echo "Unterstützte Formate: txt, md, ollama"
        exit 1
        ;;
esac

echo -e "${GREEN}Konvertierung abgeschlossen!${NC}"
echo "Anzahl der konvertierten Datensätze: $(grep -c 'prompt' "$INPUT_FILE")"
echo "Die konvertierten Daten wurden in '$OUTPUT_FILE' gespeichert."
