#!/bin/bash

# Skript zum komplett neuen Setup von Kibana
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

echo "=== Kibana Reset Tool ==="
echo "Dieses Tool löscht das bestehende Kibana-Deployment und startet es neu."
echo "Namespace: $NAMESPACE"
echo 

read -p "Möchten Sie fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Vorgang abgebrochen."
    exit 0
fi

# Lösche bestehende Ressourcen
echo "Lösche Kibana Deployment..."
kubectl -n "$NAMESPACE" delete deployment "$KIBANA_DEPLOYMENT_NAME" --grace-period=0 --force 2>/dev/null || true

echo "Lösche Kibana Service..."
kubectl -n "$NAMESPACE" delete service "$KIBANA_SERVICE_NAME" 2>/dev/null || true

echo "Warte bis Ressourcen gelöscht sind..."
sleep 10

# Starte Deployment neu
echo "Starte Kibana Deployment neu..."
"$ROOT_DIR/kibana/deploy-kibana.sh"

echo "Kibana Reset abgeschlossen."
echo 
echo "Prüfen Sie den Status mit:"
echo "kubectl -n $NAMESPACE get pods"
echo
echo "Wenn Kibana läuft, testen Sie den Zugriff mit:"
echo "kubectl -n $NAMESPACE port-forward svc/$KIBANA_SERVICE_NAME 5601:5601"
echo "Zugriff im Browser: http://localhost:5601"