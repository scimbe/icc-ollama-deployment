#!/bin/bash

# Hauptskript für die Einrichtung der RAG-Funktionalität
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

# Überprüfe, ob Ollama bereits läuft
if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst ./deploy.sh aus."
    exit 1
fi

# Überprüfe, ob ein Modell geladen ist
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
MODELS_OUTPUT=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama list 2>/dev/null)
MODEL_COUNT=$(echo "$MODELS_OUTPUT" | grep -v NAME | wc -l)

if [ "$MODEL_COUNT" -eq 0 ]; then
    echo "Es sind keine Modelle in Ollama geladen."
    echo "Möchten Sie jetzt ein Modell laden? (j/n)"
    read -r LOAD_MODEL
    if [[ "$LOAD_MODEL" =~ ^[Jj]$ ]]; then
        echo "Lade Standard-Modell $DEFAULT_MODEL..."
        "$ROOT_DIR/scripts/pull-model.sh" "$DEFAULT_MODEL"
    else
        echo "WARNUNG: Ohne geladenes Modell wird der RAG-Connector nicht funktionieren."
        echo "Bitte laden Sie später ein Modell mit ./scripts/pull-model.sh <modellname>"
    fi
fi

echo "==================================================================="
echo "           Einrichtung der RAG-Funktionalität mit Kibana           "
echo "==================================================================="
echo
echo "Dieser Assistent richtet die folgenden Komponenten ein:"
echo "1. Elasticsearch für Vektor-Einbettungen und Suche"
echo "2. Kibana als Frontend für RAG-Anwendungen"
echo "3. Connector zwischen Kibana und Ollama"
echo
echo "Das Setup benötigt ca. 5-10 Minuten, abhängig von Ihrer Verbindung."
echo

# Bestätigung einholen
read -p "Möchten Sie mit der Einrichtung fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Einrichtung abgebrochen."
    exit 0
fi

# Elasticsearch deployen
echo -e "\n[1/4] Deploye Elasticsearch..."
"$ROOT_DIR/kibana/deploy-elasticsearch.sh"

# Kibana deployen
echo -e "\n[2/4] Deploye Kibana..."
"$ROOT_DIR/kibana/deploy-kibana.sh"

# Connector-Setup
echo -e "\n[3/4] Richte Ollama-Connector ein..."
"$ROOT_DIR/kibana/setup-connector.sh"

# Beispieldaten laden
echo -e "\n[4/4] Möchten Sie Beispieldaten für den RAG-Workflow laden? (j/N) "
read -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    echo "Lade Beispieldaten..."
    "$ROOT_DIR/kibana/load-example-data.sh"
else
    echo "Überspringen des Ladens von Beispieldaten."
fi

echo
echo "==================================================================="
echo "                   RAG-Einrichtung abgeschlossen                   "
echo "==================================================================="
echo
echo "Um mit RAG zu beginnen:"
echo "1. Starten Sie Port-Forwarding für Kibana und Ollama:"
echo "   kubectl -n $NAMESPACE port-forward svc/$KIBANA_SERVICE_NAME 5601:5601"
echo "   kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434"
echo
echo "2. Öffnen Sie Kibana im Browser: http://localhost:5601"
echo "   Anmeldedaten: elastic / changeme"
echo
echo "3. Navigieren Sie zu: Elasticsearch > Playground"
echo
echo "4. Folgen Sie dem RAG-Tutorial im Wiki oder in der README.md"
echo
echo "Mit dem folgendem Befehl können Sie einen schnellen Test durchführen:"
echo "  ./scripts/test-rag.sh"
echo "==================================================================="
