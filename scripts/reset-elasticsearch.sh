#!/bin/bash

# Skript zum komplett neuen Setup von Elasticsearch
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

echo "=== Elasticsearch Reset Tool ==="
echo "Dieses Tool löscht das bestehende Elasticsearch und startet es neu."
echo "Namespace: $NAMESPACE"
echo 

read -p "Möchten Sie fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Vorgang abgebrochen."
    exit 0
fi

# Lösche bestehende Ressourcen
echo "Lösche Elasticsearch StatefulSet..."
kubectl -n "$NAMESPACE" delete statefulset "$ES_DEPLOYMENT_NAME" --grace-period=0 --force || true

echo "Lösche Elasticsearch Service..."
kubectl -n "$NAMESPACE" delete service "$ES_SERVICE_NAME" || true

echo "Warte bis Ressourcen gelöscht sind..."
sleep 10

# Starte Deployment neu
echo "Starte Elasticsearch Deployment neu..."
"$ROOT_DIR/kibana/deploy-elasticsearch.sh"

echo "Elasticsearch Reset abgeschlossen."
echo 
echo "Prüfen Sie den Status mit:"
echo "kubectl -n $NAMESPACE get pods"
echo
echo "Wenn Elasticsearch läuft, können Sie die RAG-Einrichtung fortsetzen:"
echo "./scripts/rag-setup.sh"