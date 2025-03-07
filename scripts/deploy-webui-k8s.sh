#!/bin/bash

# Skript zum Deployment der Ollama WebUI in Kubernetes
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

# Erstelle temporäre YAML-Datei für das Deployment
TMP_FILE=$(mktemp)

# Erstelle YAML für WebUI Deployment
cat << EOF > "$TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $WEBUI_DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    service: ollama-webui
spec:
  selector:
    matchLabels:
      service: ollama-webui
  template:
    metadata:
      labels:
        service: ollama-webui
    spec:
      dnsPolicy: ClusterFirst
      containers:
        - image: ghcr.io/open-webui/open-webui:main
          name: webui
          env:
            - name: OLLAMA_BASE_URL
              value: http://$OLLAMA_SERVICE_NAME:11434/api
          ports:
            - containerPort: 8080
              protocol: TCP
          resources:
            limits:
              memory: "2Gi"
              cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: $WEBUI_SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    service: ollama-webui
spec:
  ports:
    - name: http
      port: 8080
      protocol: TCP
      targetPort: 8080
  selector:
    service: ollama-webui
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying WebUI to namespace $NAMESPACE..."
kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das WebUI Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$WEBUI_DEPLOYMENT_NAME" --timeout=300s

echo "WebUI Deployment erfolgreich."
echo "Service erreichbar über: $WEBUI_SERVICE_NAME:8080"
echo
echo "WICHTIGER HINWEIS: Die WebUI funktioniert erst, nachdem mindestens ein Modell geladen wurde."
echo "Laden Sie ein Modell mit dem folgenden Befehl:"
echo "  ./scripts/pull-model.sh llama3:8b"
echo "oder wählen Sie ein anderes verfügbares Modell."
echo
echo "Detaillierte Anweisungen finden Sie in der DOCUMENTATION.md unter Abschnitt 6."
