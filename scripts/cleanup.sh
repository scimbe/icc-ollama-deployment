#!/bin/bash

# Skript zum Bereinigen aller erstellten Ressourcen
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

echo "=== Bereinigung der ICC Ollama Deployment Ressourcen ==="
echo "Namespace: $NAMESPACE"

# Bestätigung einholen
read -p "Sind Sie sicher, dass Sie alle Ressourcen löschen möchten? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Lösche Ingress, falls vorhanden
if kubectl -n "$NAMESPACE" get ingress ollama-ingress &> /dev/null; then
    echo "Lösche Ingress..."
    kubectl -n "$NAMESPACE" delete ingress ollama-ingress
fi

# Lösche WebUI Deployment und Service
echo "Lösche WebUI..."
kubectl -n "$NAMESPACE" delete deployment "$WEBUI_DEPLOYMENT_NAME" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "$WEBUI_SERVICE_NAME" --ignore-not-found=true

# Lösche Ollama Deployment und Service
echo "Lösche Ollama..."
kubectl -n "$NAMESPACE" delete deployment "$OLLAMA_DEPLOYMENT_NAME" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "$OLLAMA_SERVICE_NAME" --ignore-not-found=true

echo "Bereinigung abgeschlossen."
