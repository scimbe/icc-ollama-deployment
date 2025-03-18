#!/bin/bash

# Skript zum Deployment von Ollama mit GPU-Unterstützung
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

# GPU-Konfiguration vorbereiten
if [ "$USE_GPU" == "true" ]; then
    GPU_TOLERATIONS="
      tolerations:
        - key: \"$GPU_TYPE\"
          operator: \"Exists\"
          effect: \"NoSchedule\""
    
    # Korrekte Syntax für GPU-Ressourcen in der ICC
    GPU_RESOURCES="
              nvidia.com/gpu: $GPU_COUNT"
    
    GPU_ENV="
            - name: PATH
              value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            - name: LD_LIBRARY_PATH
              value: /usr/local/nvidia/lib:/usr/local/nvidia/lib64
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: compute,utility"
else
    GPU_TOLERATIONS=""
    GPU_RESOURCES=""
    GPU_ENV=""
fi

# Erstelle YAML für Ollama Deployment
cat << EOF > "$TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $OLLAMA_DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    service: ollama
spec:
  selector:
    matchLabels:
      service: ollama
  template:
    metadata:
      labels:
        service: ollama
    spec:$GPU_TOLERATIONS
      containers:
        - image: ollama/ollama:latest
          name: ollama
          env:$GPU_ENV
          ports:
            - containerPort: 11434
              protocol: TCP
          resources:
            limits:
              cpu: 2
              memory: "$MEMORY_LIMIT"$GPU_RESOURCES
---
apiVersion: v1
kind: Service
metadata:
  name: $OLLAMA_SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    service: ollama
spec:
  ports:
    - name: http
      port: 11434
      protocol: TCP
      targetPort: 11434
  selector:
    service: ollama
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying Ollama to namespace $NAMESPACE..."
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das Ollama Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$OLLAMA_DEPLOYMENT_NAME" --timeout=300s

echo "Ollama Deployment erfolgreich."
echo "Service erreichbar über: $OLLAMA_SERVICE_NAME:11434"
