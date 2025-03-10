#!/bin/bash

# Diagnose-Skript für das RAG-Setup
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Konstanten
MAX_WAIT_TIME=120 # Sekunden
INTERVAL=5 # Sekunden zwischen Prüfungen
OLLAMA_URL="http://localhost:11434"
ES_URL="http://localhost:9200"
KIBANA_URL="http://localhost:5601"
GATEWAY_URL="http://localhost:3100"
WEBUI_URL="http://localhost:3000"
# Modellname des verfügbaren Modells (später dynamisch gesetzt)
MODEL_NAME="phi4"

# Funktionen
log_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

log_debug() {
    echo -e "  $1"
}

# Container-Status abrufen (macOS-kompatibel)
get_container_status() {
    local container_name=$1
    if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
        local status=$(docker inspect -f '{{.State.Status}}' "$container_name")
        local health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no health check{{end}}' "$container_name" 2>/dev/null || echo "no health check")
        echo "$status (health: $health)"
    else
        echo "nicht gefunden"
    fi
}

# Ollama prüfen und verfügbares Modell erkennen
check_ollama() {
    log_header "Ollama-Diagnose"
    
    if curl -s "$OLLAMA_URL/api/tags" &> /dev/null; then
        log_success "Ollama ist unter $OLLAMA_URL erreichbar"
        
        local models_info=$(curl -s "$OLLAMA_URL/api/tags")
        
        if command -v jq &> /dev/null; then
            local models_count=$(echo "$models_info" | jq -r '.models | length')
            
            if [[ $models_count -gt 0 ]]; then
                MODEL_NAME=$(echo "$models_info" | jq -r '.models[0].name')
                log_success "$models_count Modelle verfügbar:"
                echo "$models_info" | jq -r '.models[].name' | while read -r model; do
                    log_debug "- $model"
                done
            else
                log_warning "Keine Modelle in Ollama gefunden"
            fi
        else
            log_debug "Modelle: $models_info"
            if [[ "$models_info" == *"\"name\""* ]]; then
                MODEL_NAME=$(echo "$models_info" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"$//')
            fi
        fi
        
        log_info "Teste Ollama-Generierung direkt..."
        local gen_response=$(curl -s -X POST "$OLLAMA_URL/api/generate" \
            -H "Content-Type: application/json" \
            -d "{\"prompt\":\"Sage Hallo in einem Wort.\",\"model\":\"$MODEL_NAME\",\"stream\":false}")
        
        if [[ "$gen_response" == *"response"* ]]; then
            if command -v jq &> /dev/null; then
                local response_text=$(echo "$gen_response" | jq -r '.response' | head -c 50)
                log_success "Generierung erfolgreich: \"$response_text...\""
            else
                log_success "Generierung erfolgreich"
            fi
        else
            log_error "Direkte Ollama-Generierung fehlgeschlagen"
            log_debug "Antwort: $gen_response"
        fi
    else
        log_error "Ollama ist nicht unter $OLLAMA_URL erreichbar"
        return 1
    fi
    
    return 0
}

# Elasticsearch prüfen
check_elasticsearch() {
    log_header "Elasticsearch-Diagnose"
    
    local status=$(get_container_status "elasticsearch")
    if [[ "$status" == *"running"* ]]; then
        log_success "Elasticsearch Container: $status"
    else
        log_error "Elasticsearch Container: $status"
        return 1
    fi
    
    if curl -s "$ES_URL" &> /dev/null; then
        log_success "Elasticsearch ist unter $ES_URL erreichbar"
    else
        log_error "Elasticsearch ist nicht unter $ES_URL erreichbar"
        return 1
    fi
    
    return 0
}

# RAG-Gateway prüfen
check_rag_gateway() {
    log_header "RAG-Gateway-Diagnose"
    
    local status=$(get_container_status "rag-gateway")
    if [[ "$status" == *"running"* ]]; then
        log_success "RAG-Gateway Container: $status"
    else
        log_error "RAG-Gateway Container: $status"
        return 1
    fi
    
    if curl -s "$GATEWAY_URL/api/health" &> /dev/null; then
        log_success "RAG-Gateway ist unter $GATEWAY_URL erreichbar"
        
        local health_info=$(curl -s "$GATEWAY_URL/api/health")
        if command -v jq &> /dev/null; then
            local elasticsearch_status=$(echo "$health_info" | jq -r '.elasticsearch // "nicht verbunden"')
            
            if [[ "$elasticsearch_status" == "connected" ]]; then
                log_success "Elasticsearch-Verbindung: $elasticsearch_status"
            else
                log_warning "Elasticsearch-Verbindung: $elasticsearch_status"
            fi
        fi
        
        log_info "Teste Verbindung zu Ollama über das Gateway..."
        local test_response=$(curl -s -X POST "$GATEWAY_URL/api/generate" \
            -H "Content-Type: application/json" \
            -d "{\"prompt\":\"Teste in einem Wort, ob du funktionierst.\",\"model\":\"$MODEL_NAME\"}")
        
        if [[ "$test_response" == *"response"* ]]; then
            log_success "Gateway kann mit Ollama kommunizieren"
        else
            log_error "Kommunikation mit Ollama über das Gateway fehlgeschlagen"
        fi
    else
        log_error "RAG-Gateway ist nicht unter $GATEWAY_URL erreichbar"
        return 1
    fi
    
    return 0
}

# WebUI prüfen
check_webui() {
    log_header "Open WebUI-Diagnose"
    
    local status=$(get_container_status "open-webui")
    if [[ "$status" == *"running"* ]]; then
        log_success "Open WebUI Container: $status"
    else
        log_error "Open WebUI Container: $status"
        return 1
    fi
    
    if curl -s "$WEBUI_URL" &> /dev/null; then
        log_success "Open WebUI ist unter $WEBUI_URL erreichbar"
    else
        log_error "Open WebUI ist nicht unter $WEBUI_URL erreichbar"
        return 1
    fi
    
    return 0
}

# JQ-Verfügbarkeit prüfen
if command -v jq &> /dev/null; then
    JQ_AVAILABLE=true
else
    JQ_AVAILABLE=false
fi

# Hauptprogramm
log_header "RAG-Setup-Diagnose gestartet"

# Parameter verarbeiten
VERBOSE=false
LOGS=false
ENV=false
LOGS_CONTAINER=""
ENV_CONTAINER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -l|--logs)
            LOGS=true
            LOGS_CONTAINER="$2"
            shift 2
            ;;
        -e|--environment)
            ENV=true
            ENV_CONTAINER="$2"
            shift 2
            ;;
        -h|--help)
            echo "Verwendung: $0 [OPTIONEN]"
            echo ""
            echo "Optionen:"
            echo "  -v, --verbose         Ausführliche Diagnose mit zusätzlichen Tests"
            echo "  -l, --logs CONTAINER  Zeigt die Logs für den angegebenen Container"
            echo "  -e, --env CONTAINER   Zeigt die Umgebungsvariablen für den angegebenen Container"
            echo "  -h, --help            Zeigt diese Hilfe an"
            exit 0
            ;;
        *)
            echo "Unbekannte Option: $1"
            echo "Verwenden Sie --help für Hilfe"
            exit 1
            ;;
    esac
done

# Spezifische Container-Logs anzeigen, wenn angefordert
if [[ "$LOGS" == "true" && -n "$LOGS_CONTAINER" ]]; then
    log_header "Logs für Container: $LOGS_CONTAINER"
    if docker ps --format '{{.Names}}' | grep -q "^$LOGS_CONTAINER$"; then
        docker logs "$LOGS_CONTAINER" --tail 50
    else
        log_error "Container $LOGS_CONTAINER nicht gefunden"
    fi
    exit 0
fi

# Umgebungsvariablen eines Containers anzeigen, wenn angefordert
if [[ "$ENV" == "true" && -n "$ENV_CONTAINER" ]]; then
    log_header "Umgebungsvariablen für Container: $ENV_CONTAINER"
    if docker ps --format '{{.Names}}' | grep -q "^$ENV_CONTAINER$"; then
        docker exec "$ENV_CONTAINER" env | sort
    else
        log_error "Container $ENV_CONTAINER nicht gefunden"
    fi
    exit 0
fi

# Zuerst Ollama prüfen, um das verfügbare Modell zu erkennen
check_ollama

# Standardtests durchführen
check_elasticsearch
check_rag_gateway
check_webui

# Zusammenfassung
log_header "Kurzübersicht"

# Alle Container auflisten
echo "Container-Status:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'elasticsearch|kibana|rag-gateway|open-webui' || echo "Keine RAG-Container gefunden"

# Health-Check-Übersicht
echo -e "\nErreichbarkeit der Dienste:"
curl -s "$ES_URL" > /dev/null && log_success "Elasticsearch: erreichbar" || log_error "Elasticsearch: nicht erreichbar"
curl -s "$GATEWAY_URL/api/health" > /dev/null && log_success "RAG-Gateway: erreichbar" || log_error "RAG-Gateway: nicht erreichbar"
curl -s "$WEBUI_URL" > /dev/null && log_success "Open WebUI: erreichbar" || log_error "Open WebUI: nicht erreichbar"
curl -s "$OLLAMA_URL/api/tags" > /dev/null && log_success "Ollama: erreichbar" || log_error "Ollama: nicht erreichbar"

# Gateway-Elasticsearch-Verbindung
echo -e "\nGateway-Elasticsearch-Verbindung:"
GW_HEALTH=$(curl -s "$GATEWAY_URL/api/health")
if [ "$JQ_AVAILABLE" = true ]; then
    ES_CONN=$(echo "$GW_HEALTH" | jq -r '.elasticsearch // "nicht verbunden"')
    if [[ "$ES_CONN" == "connected" ]]; then
        log_success "Gateway mit Elasticsearch verbunden"
    elif [[ "$ES_CONN" == "null" ]]; then
        log_warning "Gateway-Elasticsearch-Verbindung nicht initialisiert"
        log_info "Warten Sie einige Minuten oder starten Sie den rag-gateway Container neu: docker restart rag-gateway"
    else
        log_error "Gateway nicht mit Elasticsearch verbunden: $ES_CONN"
    fi
else
    if [[ "$GW_HEALTH" == *"elasticsearch"*"connected"* ]]; then
        log_success "Gateway mit Elasticsearch verbunden"
    else
        log_warning "Gateway-Elasticsearch-Verbindungsstatus unbekannt"
        log_info "Gateway Health-Info: $GW_HEALTH"
    fi
fi

echo
log_info "Bei Problemen mit dem Gateway:"
log_debug "1. Überprüfen Sie die Logs: docker logs rag-gateway"
log_debug "2. Starten Sie es neu: docker restart rag-gateway"
log_debug "3. Führen Sie eine ausführliche Diagnose durch: $0 -v"