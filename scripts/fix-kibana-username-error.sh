#!/bin/bash

# Quick fix script for Kibana error
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

echo "=== Kibana Username Error Fix ==="
echo "Lösche bestehendes Kibana-Deployment..."
kubectl -n "$NAMESPACE" delete deployment "$KIBANA_DEPLOYMENT_NAME" --grace-period=0 --force 2>/dev/null || true

echo "Warte auf Löschen des Deployments..."
sleep 5

echo "Deploye Kibana mit korrigierter Konfiguration..."
"$ROOT_DIR/kibana/deploy-kibana.sh"

echo "Fix abgeschlossen. Überprüfen Sie den Status mit:"
echo "kubectl -n $NAMESPACE get pods"