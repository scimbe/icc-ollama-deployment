#!/bin/bash

# Hauptskript für das Deployment von Ollama und WebUI auf der ICC
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lade Konfiguration
if [ -f "$SCRIPT_DIR/configs/config.sh" ]; then
    source "$SCRIPT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden. Bitte kopieren Sie configs/config.example.sh nach configs/config.sh und passen Sie die Werte an."
    exit 1
fi

# Prüfe, ob kubectl verfügbar ist
if ! command -v kubectl &> /dev/null; then
    echo "Fehler: kubectl ist nicht installiert oder nicht im PATH."
    echo "Bitte installieren Sie kubectl gemäß der Anleitung: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Prüfe, ob Namespace existiert
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Fehler: Namespace $NAMESPACE existiert nicht."
    echo "Bitte überprüfen Sie Ihre Konfiguration und stellen Sie sicher, dass Sie bei der ICC eingeloggt sind."
    exit 1
fi

echo "=== ICC Ollama Deployment Starter ==="
echo "Namespace: $NAMESPACE"
echo "GPU-Unterstützung: $([ "$USE_GPU" == "true" ] && echo "Aktiviert ($GPU_TYPE)" || echo "Deaktiviert")"

# Führe Deployment-Skripte aus
echo -e "\n1. Deploying Ollama..."
"$SCRIPT_DIR/scripts/deploy-ollama.sh"

echo -e "\n2. Deploying WebUI..."
"$SCRIPT_DIR/scripts/deploy-webui-k8s.sh"

echo -e "\n=== Deployment abgeschlossen! ==="
echo "Überprüfen Sie den Status mit: kubectl -n $NAMESPACE get pods"

# Zeige Anweisungen für den Zugriff
echo -e "\n=== Zugriff auf die Dienste ==="
echo "WICHTIG: Sie müssen zuerst ein Modell laden, bevor die WebUI funktioniert!"
echo "Laden Sie ein Modell mit:"
echo "  ./scripts/pull-model.sh llama3:8b"
echo 
echo "Um auf Ollama zuzugreifen, führen Sie aus:"
echo "  kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434"
echo -e "\nUm auf die WebUI zuzugreifen, führen Sie in einem anderen Terminal aus:"
echo "  export KUBECTL_PORT_FORWARD_WEBSOCKETS=\"true\""
echo "  kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 8080:8080"
echo -e "\nÖffnen Sie dann http://localhost:8080 in Ihrem Browser"

if [ "$CREATE_INGRESS" == "true" ]; then
    echo -e "\nIngress wird erstellt für: $DOMAIN_NAME"
    "$SCRIPT_DIR/scripts/create-ingress.sh"
    echo "Nach erfolgreichem Ingress-Setup können Sie Ihren Dienst unter https://$DOMAIN_NAME erreichen"
fi

echo -e "\nWeitere Informationen finden Sie in der DOCUMENTATION.md"
