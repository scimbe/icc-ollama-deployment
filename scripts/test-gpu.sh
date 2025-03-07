#!/bin/bash

# Skript zum Testen der GPU-Funktionalität im Ollama Pod
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

# Überprüfe ob das Ollama Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Überprüfe ob GPU aktiviert ist
if [ "$USE_GPU" != "true" ]; then
    echo "Fehler: GPU-Unterstützung ist in der Konfiguration nicht aktiviert."
    echo "Bitte setzen Sie USE_GPU=true in Ihrer config.sh."
    exit 1
fi

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "Fehler: Konnte keinen laufenden Ollama Pod finden."
    exit 1
fi

echo "Teste GPU-Verfügbarkeit im Pod '$POD_NAME'..."

# Führe nvidia-smi im Pod aus
echo -e "\n=== nvidia-smi Ausgabe ==="
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi; then
    echo -e "\n✅ GPU erfolgreich erkannt und verfügbar!"
else
    echo -e "\n❌ Fehler: nvidia-smi konnte nicht ausgeführt werden. GPU möglicherweise nicht verfügbar."
    exit 1
fi

# Teste, ob Ollama die GPU erkennt
echo -e "\n=== Ollama GPU-Test ===="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama info

echo -e "\nGPU-Test abgeschlossen."
echo "Wenn oben CUDA oder ROCm-Informationen angezeigt werden, ist die GPU erfolgreich konfiguriert."
