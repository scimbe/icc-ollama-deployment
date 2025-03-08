#!/bin/bash

# Skript zur Einrichtung des Ollama-Connectors in Kibana
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    exit 1
fi

# Prüfe, ob die Deployments existieren
if ! kubectl -n "$NAMESPACE" get deployment "$KIBANA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Kibana Deployment '$KIBANA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst kibana/deploy-kibana.sh aus."
    exit 1
fi

if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh oder scripts/deploy-ollama.sh aus."
    exit 1
fi

# Warte auf die Kibana API
echo "Prüfe, ob Kibana bereit ist..."
for i in {1..30}; do
    # Starte temporäres Port-Forwarding, um die Kibana-API zu testen
    kubectl -n "$NAMESPACE" port-forward "svc/$KIBANA_SERVICE_NAME" 5601:5601 &
    PF_PID=$!
    sleep 3
    
    if curl -s "http://localhost:5601/api/status" | grep -q "available"; then
        echo "Kibana ist bereit."
        kill $PF_PID
        break
    else
        echo "Warte auf Kibana... ($i/30)"
        kill $PF_PID
        sleep 10
    fi
    
    if [ $i -eq 30 ]; then
        echo "Fehler: Kibana ist nach 5 Minuten immer noch nicht bereit."
        exit 1
    fi
done

echo "Bereite Schritte zur manuellen Connector-Einrichtung vor..."
echo

# Da die Connector-Erstellung über APIs Authentifizierung und komplexe JSON-Struktur erfordert,
# geben wir stattdessen detaillierte Anweisungen für die manuelle Einrichtung

echo "========================================================================="
echo "                Ollama-Connector in Kibana einrichten"
echo "========================================================================="
echo
echo "1. Starten Sie Port-Forwarding für Kibana und Ollama:"
echo "   kubectl -n $NAMESPACE port-forward svc/$KIBANA_SERVICE_NAME 5601:5601"
echo "   kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434"
echo
echo "2. Öffnen Sie Kibana im Browser: http://localhost:5601"
echo "   Melden Sie sich mit Benutzername 'elastic' und Passwort 'changeme' an"
echo
echo "3. Navigieren Sie zu:"
echo "   Stack Management > Alerts and Insights > Connectors"
echo
echo "4. Klicken Sie auf 'Create connector' und wählen Sie 'OpenAI'"
echo
echo "5. Konfigurieren Sie den Connector mit den folgenden Werten:"
echo "   - Connector name: $CONNECTOR_NAME"
echo "   - Select an OpenAI provider: other (OpenAI Compatible Service)"
echo "   - URL: http://localhost:11434/v1/chat/completions"
echo "     (Bei Verwendung aus einem Container: http://$OLLAMA_SERVICE_NAME:11434/v1/chat/completions)"
echo "   - Default model: $DEFAULT_MODEL"
echo "   - API key: $CONNECTOR_KEY (der Wert ist unwichtig, wird aber benötigt)"
echo
echo "6. Klicken Sie auf 'Save' und dann auf 'Test connector API'"
echo
echo "7. Nach erfolgreicher Einrichtung können Sie Playground verwenden:"
echo "   Elasticsearch > Playground"
echo 
echo "8. Laden Sie Beispieldaten (optional):"
echo "   ./kibana/load-example-data.sh"
echo
echo "========================================================================="
echo
echo "TIPP: Wenn der Test fehlschlägt, stellen Sie sicher, dass:"
echo "- Mindestens ein Modell in Ollama geladen ist (z.B. mit scripts/pull-model.sh llama3:8b)"
echo "- Beide Port-Forwarding-Prozesse laufen"
echo "- In Produktionsumgebungen die korrekte URL mit dem Service-Namen verwendet wird"
