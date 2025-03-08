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
export GPU_FORMAT="standard"  # Verwenden Sie "extended" für erweiterte Syntax, wenn Standard nicht funktioniert

# Ressourcenlimits
export MEMORY_LIMIT="4Gi"  # Speicherlimit für Ollama

# Zugriffskonfiguration
export CREATE_INGRESS=false  # Auf true setzen, wenn ein Ingress erstellt werden soll
export DOMAIN_NAME="your-domain.informatik.haw-hamburg.de"  # Nur relevant, wenn CREATE_INGRESS=true

# ===== Kibana-RAG Konfiguration =====

# Elasticsearch-Konfiguration
export ES_DEPLOYMENT_NAME="my-elasticsearch"
export ES_SERVICE_NAME="my-elasticsearch"
export ES_VERSION="8.12.2"
export ES_MEMORY_LIMIT="2Gi"
export ES_STORAGE_SIZE="10Gi"
export ES_REPLICAS=1

# Kibana-Konfiguration
export KIBANA_DEPLOYMENT_NAME="my-kibana"
export KIBANA_SERVICE_NAME="my-kibana"
export KIBANA_VERSION="8.12.2"
export KIBANA_MEMORY_LIMIT="1Gi"

# RAG-Konfiguration
export EMBEDDING_MODEL=".multilingual-e5-small-elasticsearch" # Standard-Embedding-Modell
export ENABLE_RAG=true                        # RAG-Funktionalität aktivieren
export CONNECTOR_NAME="Ollama (ICC)"          # Name des Ollama-Connectors in Kibana
export OLLAMA_API_URL="http://$OLLAMA_SERVICE_NAME:11434/v1/chat/completions" # API-URL für Ollama
export DEFAULT_MODEL="llama3:8b"              # Standard-Modell für RAG
export CONNECTOR_KEY="ollama-api-key"         # Dummy-API-Schlüssel für den Connector
