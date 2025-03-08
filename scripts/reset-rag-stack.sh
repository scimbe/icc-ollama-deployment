#!/bin/bash

# Skript zum kompletten Reset des RAG-Stacks (Elasticsearch und Kibana)
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

echo "=== RAG-Stack Reset Tool ==="
echo "Dieses Tool löscht den bestehenden RAG-Stack (Elasticsearch und Kibana) und startet ihn neu."
echo "Namespace: $NAMESPACE"
echo 

read -p "Möchten Sie fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Vorgang abgebrochen."
    exit 0
fi

# Schritt 1: Kibana löschen
echo -e "\n[1/4] Lösche Kibana..."
kubectl -n "$NAMESPACE" delete deployment "$KIBANA_DEPLOYMENT_NAME" --grace-period=0 --force 2>/dev/null || true
kubectl -n "$NAMESPACE" delete service "$KIBANA_SERVICE_NAME" 2>/dev/null || true

# Schritt 2: Elasticsearch löschen
echo -e "\n[2/4] Lösche Elasticsearch..."
kubectl -n "$NAMESPACE" delete statefulset "$ES_DEPLOYMENT_NAME" --grace-period=0 --force 2>/dev/null || true
kubectl -n "$NAMESPACE" delete service "$ES_SERVICE_NAME" 2>/dev/null || true

echo "Warte bis alle Ressourcen gelöscht sind..."
sleep 10

# Schritt 3: Elasticsearch neu starten
echo -e "\n[3/4] Starte Elasticsearch neu..."
"$ROOT_DIR/kibana/deploy-elasticsearch.sh"

# Schritt 4: Kibana neu starten
echo -e "\n[4/4] Starte Kibana neu..."
"$ROOT_DIR/kibana/deploy-kibana.sh"

echo -e "\n=== RAG-Stack Reset abgeschlossen ==="
echo 
echo "Prüfen Sie den Status mit:"
echo "kubectl -n $NAMESPACE get pods"
echo
echo "Um die Dienste zu testen, starten Sie Port-Forwarding:"
echo "kubectl -n $NAMESPACE port-forward svc/$ES_SERVICE_NAME 9200:9200 &"
echo "kubectl -n $NAMESPACE port-forward svc/$KIBANA_SERVICE_NAME 5601:5601 &"
echo
echo "Zugriff im Browser: http://localhost:5601"
echo
echo "Um den Ollama-Connector einzurichten, führen Sie folgendes aus:"
echo "  ./kibana/setup-connector.sh"