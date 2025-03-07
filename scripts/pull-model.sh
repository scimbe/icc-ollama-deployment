#!/bin/bash

# Skript zum Herunterladen eines Ollama-Modells
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

# Überprüfe ob ein Modellname übergeben wurde
if [ $# -lt 1 ]; then
    echo "Fehler: Kein Modellname angegeben."
    echo "Verwendung: $0 <modellname>"
    echo "Beispiel: $0 llama3:8b"
    exit 1
fi

MODEL_NAME=$1

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

echo "Starte den Download von Modell '$MODEL_NAME' im Pod '$POD_NAME'..."
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama pull "$MODEL_NAME"

echo "Modell '$MODEL_NAME' wurde heruntergeladen."
echo "Sie können es jetzt über die WebUI oder die Ollama API verwenden."
