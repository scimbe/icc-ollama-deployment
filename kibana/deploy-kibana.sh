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

# Prüfe, ob Elasticsearch läuft
echo "Prüfe, ob Elasticsearch bereit ist..."
ES_READY=false
for i in {1..5}; do
    if kubectl -n "$NAMESPACE" get pod -l app=elasticsearch -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        ES_READY=true
        break
    fi
    echo "Warte auf Elasticsearch (Versuch $i/5)..."
    sleep 10
done

if [ "$ES_READY" = "false" ]; then
    echo "Warnung: Elasticsearch scheint nicht zu laufen. Stellen Sie sicher, dass es korrekt deployed ist."
    echo "Sie können es mit folgendem Befehl überprüfen:"
    echo "kubectl -n $NAMESPACE get pod -l app=elasticsearch"
    
    read -p "Möchten Sie trotzdem mit dem Kibana-Deployment fortfahren? (j/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        echo "Deployment abgebrochen."
        exit 1
    fi
fi

# Prüfe, ob ein bestehendes Kibana-Deployment existiert
if kubectl -n "$NAMESPACE" get deployment "$KIBANA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Bestehendes Kibana-Deployment gefunden."
    echo "Lösche es für einen sauberen Neustart..."
    kubectl -n "$NAMESPACE" delete deployment "$KIBANA_DEPLOYMENT_NAME"
    
    # Kurz warten bis das Deployment gelöscht ist
    echo "Warte auf Löschen des Deployments..."
    sleep 5
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
echo "Warte auf das Kibana Deployment (kann einige Minuten dauern)..."
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
