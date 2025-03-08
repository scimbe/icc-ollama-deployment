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

# Prüfe ob ein bestehendes Elasticsearch Deployment existiert
if kubectl -n "$NAMESPACE" get statefulset "$ES_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Bestehendes Elasticsearch Deployment gefunden."
    echo "Lösche es für einen sauberen Neustart..."
    kubectl -n "$NAMESPACE" delete statefulset "$ES_DEPLOYMENT_NAME" --timeout=60s
    
    # Kurz warten bis das StatefulSet gelöscht ist
    echo "Warte auf Löschen des StatefulSets..."
    sleep 5
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
echo "Gebe Elasticsearch 60 Sekunden Zeit zum Starten..."
sleep 60

# Teste ob Elasticsearch erreichbar ist
if ! curl -s "http://localhost:9200/_cluster/health" > /dev/null; then
    echo "Warnung: Elasticsearch scheint noch nicht bereit zu sein."
    echo "Warte weitere 30 Sekunden..."
    sleep 30
fi

# Setup für ML-Modelle
echo "Initialisiere ML-Funktionalität..."
if curl -s -X POST "http://localhost:9200/_ml/set_upgrade_mode?enabled=false" -H "Content-Type: application/json"; then
    echo "ML-Funktionalität initialisiert."
else
    echo "Warnung: Konnte ML-Funktionalität nicht initialisieren, versuche es später erneut."
fi

# Lade Embedding-Modell
if [ "$ENABLE_RAG" = "true" ]; then
    echo "Lade Embedding-Modell $EMBEDDING_MODEL..."
    if curl -s -X POST "http://localhost:9200/_inference/text_embedding/$EMBEDDING_MODEL" \
            -H "Content-Type: application/json" \
            -d '{
                "input": "Test embedding model initialization"
            }'; then
        echo "Embedding-Modell erfolgreich geladen."
    else
        echo "Warnung: Konnte Embedding-Modell nicht laden, versuche es später erneut."
    fi
fi

# Beende Port-Forwarding
kill $PF_PID || true

echo "Elasticsearch Deployment erfolgreich."
echo "Service erreichbar über: $ES_SERVICE_NAME:9200"
if [ "$ENABLE_RAG" = "true" ]; then
    echo "Embedding-Modell $EMBEDDING_MODEL sollte initialisiert sein."
fi