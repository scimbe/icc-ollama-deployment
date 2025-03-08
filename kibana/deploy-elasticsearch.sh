#!/bin/bash

# Skript zum Deployment von Elasticsearch für RAG-Funktionalität
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"  # Nur eine Ebene hoch gehen

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    exit 1
fi

# Erstelle temporäre YAML-Datei für das Deployment
TMP_FILE=$(mktemp)

# Manifest-Vorlage laden und Umgebungsvariablen ersetzen
cat "$SCRIPT_DIR/manifests/elasticsearch.yaml" | envsubst > "$TMP_FILE"

# Anwenden der Konfiguration
echo "Deploying Elasticsearch to namespace $NAMESPACE..."
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das Elasticsearch StatefulSet..."
kubectl -n "$NAMESPACE" rollout status statefulset/"$ES_DEPLOYMENT_NAME" --timeout=300s

# Installiere Vektor-Embedding-Modell
echo "Warte, bis Elasticsearch bereit ist..."
# Port-Forwarding für den Zugriff auf Elasticsearch
kubectl -n "$NAMESPACE" port-forward "svc/$ES_SERVICE_NAME" 9200:9200 &
PF_PID=$!

# Warte länger auf Elasticsearch (besonders für langsamere Systeme)
sleep 30

# Setup für ML-Modelle
echo "Initialisiere ML-Funktionalität..."
curl -X POST "http://localhost:9200/_ml/set_upgrade_mode?enabled=false" -H "Content-Type: application/json"

# Lade Embedding-Modell
if [ "$ENABLE_RAG" = "true" ]; then
    echo "Lade Embedding-Modell $EMBEDDING_MODEL..."
    curl -X POST "http://localhost:9200/_inference/text_embedding/$EMBEDDING_MODEL" \
        -H "Content-Type: application/json" \
        -d '{
            "input": "Test embedding model initialization"
        }'
fi

# Beende Port-Forwarding
kill $PF_PID

echo "Elasticsearch Deployment erfolgreich."
echo "Service erreichbar über: $ES_SERVICE_NAME:9200"
if [ "$ENABLE_RAG" = "true" ]; then
    echo "Embedding-Modell $EMBEDDING_MODEL wurde initialisiert."
fi
