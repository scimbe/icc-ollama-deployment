#!/bin/bash

# ICC Namespace (wird automatisch erstellt, normalerweise ist es Ihre w-Kennung + "-default")
# Beispiel: Wenn Ihr Login infwaa123 ist, dann ist Ihr Namespace waa123-default
export NAMESPACE="wXYZ123-default"  # Ersetzen Sie dies mit Ihrem Namespace

# Deployment-Namen
export OLLAMA_DEPLOYMENT_NAME="my-ollama"
export OLLAMA_SERVICE_NAME="my-ollama"
export WEBUI_DEPLOYMENT_NAME="ollama-webui"
export WEBUI_SERVICE_NAME="ollama-webui"

# GPU-Konfiguration
export USE_GPU=true  # Auf false setzen, wenn keine GPU benötigt wird
export GPU_TYPE="gpu-tesla-v100"  # Oder "gpu-tesla-v100s" je nach Verfügbarkeit
export GPU_COUNT=1  # Anzahl der GPUs (normalerweise 1)

# Ressourcenlimits
export MEMORY_LIMIT="4Gi"  # Speicherlimit

# Zugriffskonfiguration
export CREATE_INGRESS=false  # Auf true setzen, wenn ein Ingress erstellt werden soll
export DOMAIN_NAME="your-domain.informatik.haw-hamburg.de"  # Nur relevant, wenn CREATE_INGRESS=true
