#!/bin/bash

# Skript zum Deployment von Kibana für RAG-Funktionalität
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
cat "$SCRIPT_DIR/manifests/kibana.yaml" | envsubst > "$TMP_FILE"

# Anwenden der Konfiguration
echo "Deploying Kibana to namespace $NAMESPACE..."
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das Kibana Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$KIBANA_DEPLOYMENT_NAME" --timeout=300s

echo "Kibana Deployment erfolgreich."
echo "Service erreichbar über: $KIBANA_SERVICE_NAME:5601"
echo
echo "WICHTIGER HINWEIS:"
echo "1. Starten Sie Port-Forwarding mit: kubectl -n $NAMESPACE port-forward svc/$KIBANA_SERVICE_NAME 5601:5601"
echo "2. Öffnen Sie Kibana im Browser: http://localhost:5601"
echo "3. Melden Sie sich mit den folgenden Zugangsdaten an:"
echo "   Benutzername: elastic"
echo "   Passwort: changeme"
echo
echo "Um den Ollama-Connector einzurichten, führen Sie folgendes aus:"
echo "  ./kibana/setup-connector.sh"
