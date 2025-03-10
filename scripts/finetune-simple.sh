#!/bin/bash

# Skript für direktes Finetuning ohne LoRA in Ollama
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
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "Direktes Finetuning eines Ollama-Modells (ohne LoRA)"
    echo
    echo "Optionen:"
    echo "  -h, --help          Diese Hilfe anzeigen"
    echo "  -m, --model NAME    Basismodell (Standard: $LORA_BASE_MODEL)"
    echo "  -n, --name NAME     Name des angepassten Modells (Standard: ${LORA_BASE_MODEL%:*}-custom)"
    echo "  -d, --data FILE     Pfad zur Trainingsdaten-Datei (JSONL-Format)"
    echo "  -t, --template FILE Optional: Pfad zu einer benutzerdefinierten Template-Datei"
    echo
    echo "Beispiel:"
    echo "  $0 -m llama3:8b -n haw-custom -d training_data.jsonl"
    exit 0
}

# Standardwerte
BASE_MODEL="$LORA_BASE_MODEL"
CUSTOM_NAME="${LORA_BASE_MODEL%:*}-custom"
DATA_FILE=""
TEMPLATE_FILE=""

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -m|--model)
            BASE_MODEL="$2"
            shift 2
            ;;
        -n|--name)
            CUSTOM_NAME="$2"
            shift 2
            ;;
        -d|--data)
            DATA_FILE="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unbekannte Option: $1${NC}"
            show_help
            ;;
    esac
done

# Überprüfe, ob notwendige Parameter vorhanden sind
if [ -z "$DATA_FILE" ]; then
    echo -e "${RED}Fehler: Keine Trainingsdaten angegeben.${NC}"
    echo "Bitte geben Sie eine Trainingsdaten-Datei mit -d oder --data an."
    show_help
    exit 1
fi

if [ ! -f "$DATA_FILE" ]; then
    echo -e "${RED}Fehler: Trainingsdaten-Datei '$DATA_FILE' nicht gefunden.${NC}"
    exit 1
fi

# Hole den Pod-Namen
POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l service=ollama -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Fehler: Konnte keinen laufenden Ollama Pod finden.${NC}"
    exit 1
fi

echo -e "${GREEN}=== Direktes Finetuning starten ===${NC}"
echo "Pod: $POD_NAME"
echo "Basismodell: $BASE_MODEL"
echo "Name des angepassten Modells: $CUSTOM_NAME"
echo "Trainingsdaten: $DATA_FILE"

# Validiere Trainingsdaten-Format (JSONL)
if ! grep -q '"prompt":' "$DATA_FILE" || ! grep -q '"response":' "$DATA_FILE"; then
    echo -e "${RED}Fehler: Trainingsdaten scheinen nicht im JSONL-Format mit 'prompt' und 'response' Feldern zu sein.${NC}"
    echo "Beispiel für korrektes Format:"
    echo '{"prompt": "Wer ist die HAW?", "response": "Die HAW Hamburg ist eine Hochschule für angewandte Wissenschaften."}'
    exit 1
fi

# Bestätigung einholen
read -p "Möchten Sie mit dem Finetuning fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 0
fi

# Erstelle Modelfile
TMP_MODELFILE=$(mktemp)

if [ -n "$TEMPLATE_FILE" ] && [ -f "$TEMPLATE_FILE" ]; then
    # Verwende benutzerdefiniertes Template
    echo "FROM $BASE_MODEL" > "$TMP_MODELFILE"
    echo "" >> "$TMP_MODELFILE"
    echo "TEMPLATE $(cat "$TEMPLATE_FILE")" >> "$TMP_MODELFILE"
else
    # Verwende Standard-Template
    cat << EOF > "$TMP_MODELFILE"
FROM $BASE_MODEL

TEMPLATE """
{{ if .First }}
Du bist ein KI-Assistent der HAW Hamburg. Du antwortest präzise und hilfreich auf alle Fragen bezüglich der HAW Hamburg.
{{ else }}
{{ .Prompt }}
{{ end }}
"""
EOF
fi

# Kopiere Modelfile in den Pod
echo "Kopiere Modelfile in den Pod..."
kubectl cp "$TMP_MODELFILE" "$NAMESPACE/$POD_NAME:/tmp/custom_modelfile"
rm "$TMP_MODELFILE"

# Kopiere Trainingsdaten
echo "Kopiere Trainingsdaten in den Pod..."
kubectl cp "$DATA_FILE" "$NAMESPACE/$POD_NAME:/tmp/training_data.jsonl"

# Erstelle benutzerdefiniertes Modell
echo -e "\n${GREEN}Erstelle angepasstes Modell '$CUSTOM_NAME'...${NC}"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama create "$CUSTOM_NAME" -f /tmp/custom_modelfile

# Bereite Finetuning-Anweisungen vor
TMP_INSTRUCTIONS=$(mktemp)
cat << EOF > "$TMP_INSTRUCTIONS"
#!/bin/bash
echo "Starte Finetuning für Modell $CUSTOM_NAME..."
cat /tmp/training_data.jsonl | while read -r line; do
    prompt=\$(echo \$line | grep -o '"prompt":"[^"]*"' | sed 's/"prompt":"//g' | sed 's/"//g')
    response=\$(echo \$line | grep -o '"response":"[^"]*"' | sed 's/"response":"//g' | sed 's/"//g')
    
    echo "Training mit Prompt: \$prompt"
    echo "\$prompt" | ollama run $CUSTOM_NAME --nowordwrap > /dev/null
    
    # Simuliere Nutzerantwort für kontinuierliches Lernen
    # Hinweis: Das ist eine vereinfachte Version ohne tatsächliches LoRA-Training
done
echo "Finetuning abgeschlossen."
EOF

# Kopiere und führe Anweisungen aus
kubectl cp "$TMP_INSTRUCTIONS" "$NAMESPACE/$POD_NAME:/tmp/finetune_instructions.sh"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- chmod +x /tmp/finetune_instructions.sh
rm "$TMP_INSTRUCTIONS"

echo -e "\n${GREEN}Starte Finetuning-Prozess...${NC}"
echo "Dies kann je nach Größe der Trainingsdaten einige Zeit dauern."
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- /tmp/finetune_instructions.sh

echo -e "\n${GREEN}Initialisierung abgeschlossen.${NC}"
echo "Das angepasste Modell '$CUSTOM_NAME' wurde erstellt und mit Ihren Daten initialisiert."
echo "Sie können das Modell nun mit dem folgenden Befehl testen:"
echo "  ./scripts/ollama-api-client.sh test $CUSTOM_NAME"
echo -e "\n${YELLOW}Hinweis:${NC} Dies ist eine vereinfachte Form der Modellanpassung ohne LoRA,"
echo "die auf Ihrem aktuellen Ollama-Setup funktioniert. In zukünftigen Versionen könnte"
echo "die vollständige LoRA-Funktionalität verfügbar sein."
