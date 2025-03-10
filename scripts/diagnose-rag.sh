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

wait_for_service() {
    local url=$1
    local service_name=$2
    local max_time=$3
    local interval=$4
    
    log_info "Warte auf $service_name unter $url (Timeout: ${max_time}s, Intervall: ${interval}s)..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + max_time))
    local current_time=$start_time
    
    while [ $current_time -lt $end_time ]; do
        if curl -s "$url" &> /dev/null; then
            local elapsed=$((current_time - start_time))
            log_success "$service_name ist nach ${elapsed}s erreichbar"
            return 0
        fi
        echo -n "."
        sleep $interval
        current_time=$(date +%s)
    done
    
    log_error "$service_name ist nach ${max_time}s noch nicht erreichbar"
    return 1
}

test_http_status() {
    local url=$1
    local expected_status=${2:-200}
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$response" -eq "$expected_status" ]; then
        return 0
    else
        return 1
    fi
}

get_container_status() {
    local container_name=$1
    if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
        local status=$(docker inspect -f '{{.State.Status}}' "$container_name")
        local health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no health check{{end}}' "$container_name" 2>/dev/null || echo "no health check")
        local uptime=$(docker inspect -f '{{.State.StartedAt}}' "$container_name" | xargs -I{} date -d {} +%s)
        local now=$(date +%s)
        local runtime=$((now - uptime))
        
        echo "$status (laufzeit: ${runtime}s, health: $health)"
    else
        echo "nicht gefunden"
    fi
}

check_elasticsearch() {
    log_header "Elasticsearch-Diagnose"
    
    # Container-Status prüfen
    local status=$(get_container_status "elasticsearch")
    if [[ "$status" == *"running"* ]]; then
        log_success "Elasticsearch Container: $status"
    else
        log_error "Elasticsearch Container: $status"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs elasticsearch"
        return 1
    fi
    
    # Verbindung prüfen
    if curl -s "$ES_URL" &> /dev/null; then
        log_success "Elasticsearch ist unter $ES_URL erreichbar"
        
        # Weitere Informationen abrufen
        local es_info=$(curl -s "$ES_URL")
        if command -v jq &> /dev/null; then
            local es_version=$(echo "$es_info" | jq -r '.version.number')
            log_debug "Version: $es_version"
        else
            log_debug "Elasticsearch-Info: $es_info"
            log_info "Installieren Sie jq für eine besser formatierte Ausgabe"
        fi
        
        # Cluster-Gesundheit prüfen
        local health_info=$(curl -s "$ES_URL/_cluster/health")
        if command -v jq &> /dev/null; then
            local status=$(echo "$health_info" | jq -r '.status')
            local nodes=$(echo "$health_info" | jq -r '.number_of_nodes')
            local shards=$(echo "$health_info" | jq -r '.active_shards')
            
            log_debug "Cluster-Status: $status, Knoten: $nodes, Aktive Shards: $shards"
            
            if [[ "$status" == "green" ]]; then
                log_success "Cluster-Gesundheit: $status"
            elif [[ "$status" == "yellow" ]]; then
                log_warning "Cluster-Gesundheit: $status"
            else
                log_error "Cluster-Gesundheit: $status"
            fi
        else
            log_debug "Cluster-Gesundheit: $health_info"
        fi
        
        # Indizes prüfen
        log_info "Prüfe RAG-Index..."
        local indices_info=$(curl -s "$ES_URL/_cat/indices?format=json")
        if command -v jq &> /dev/null; then
            if echo "$indices_info" | jq -e '.[] | select(.index == "ollama-rag")' &> /dev/null; then
                local index_info=$(echo "$indices_info" | jq -r '.[] | select(.index == "ollama-rag") | "Dokumente: \(.docs.count), Größe: \(.store.size)"')
                log_success "RAG-Index gefunden: $index_info"
            else
                log_warning "RAG-Index nicht gefunden. Wurde noch kein Dokument hochgeladen?"
                log_debug "Verfügbare Indizes: $(echo "$indices_info" | jq -r '.[].index' | tr '\n' ', ')"
            fi
        else
            log_debug "Indizes-Info: $indices_info"
        fi
    else
        log_error "Elasticsearch ist nicht unter $ES_URL erreichbar"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs elasticsearch"
        return 1
    fi
    
    return 0
}

check_kibana() {
    log_header "Kibana-Diagnose"
    
    # Container-Status prüfen
    local status=$(get_container_status "kibana")
    if [[ "$status" == *"running"* ]]; then
        log_success "Kibana Container: $status"
    else
        log_error "Kibana Container: $status"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs kibana"
        return 1
    fi
    
    # Verbindung prüfen
    if curl -s "$KIBANA_URL" &> /dev/null; then
        log_success "Kibana ist unter $KIBANA_URL erreichbar"
        
        # Prüfen, ob Kibana bereits initialisiert ist
        if curl -s "$KIBANA_URL/api/status" &> /dev/null; then
            local status_info=$(curl -s "$KIBANA_URL/api/status")
            if command -v jq &> /dev/null; then
                local kibana_status=$(echo "$status_info" | jq -r '.status.overall.level')
                if [[ "$kibana_status" == "available" ]]; then
                    log_success "Kibana-Status: $kibana_status"
                else
                    log_warning "Kibana-Status: $kibana_status"
                fi
            else
                log_debug "Kibana-Status: $status_info"
            fi
        else
            log_warning "Kibana-API noch nicht verfügbar. Kibana wird möglicherweise noch initialisiert."
            log_info "Überprüfen Sie die Container-Logs mit: docker logs kibana"
        fi
    else
        log_error "Kibana ist nicht unter $KIBANA_URL erreichbar"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs kibana"
        return 1
    fi
    
    return 0
}

check_rag_gateway() {
    log_header "RAG-Gateway-Diagnose"
    
    # Container-Status prüfen
    local status=$(get_container_status "rag-gateway")
    if [[ "$status" == *"running"* ]]; then
        log_success "RAG-Gateway Container: $status"
    else
        log_error "RAG-Gateway Container: $status"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs rag-gateway"
        return 1
    fi
    
    # Verbindung prüfen
    if curl -s "$GATEWAY_URL/api/health" &> /dev/null; then
        log_success "RAG-Gateway ist unter $GATEWAY_URL erreichbar"
        
        # Health-Check abrufen
        local health_info=$(curl -s "$GATEWAY_URL/api/health")
        if command -v jq &> /dev/null; then
            local gateway_status=$(echo "$health_info" | jq -r '.status')
            local elasticsearch_status=$(echo "$health_info" | jq -r '.elasticsearch // "nicht verbunden"')
            
            log_debug "Gateway-Status: $gateway_status"
            
            if [[ "$elasticsearch_status" == "connected" ]]; then
                log_success "Elasticsearch-Verbindung: $elasticsearch_status"
            elif [[ "$elasticsearch_status" == "null" ]]; then
                log_warning "Elasticsearch-Verbindung: nicht initialisiert"
                log_info "Warten Sie einige Minuten oder starten Sie den rag-gateway Container neu"
            else
                log_error "Elasticsearch-Verbindung: $elasticsearch_status"
                log_info "Überprüfen Sie die Container-Logs mit: docker logs rag-gateway"
            fi
        else
            log_debug "Health-Info: $health_info"
        fi
        
        # Ollama-Verbindung testen
        log_info "Teste Verbindung zu Ollama über das Gateway..."
        local test_response=$(curl -s -X POST "$GATEWAY_URL/api/generate" \
            -H "Content-Type: application/json" \
            -d '{"prompt":"Teste in einem Wort, ob du funktionierst.","model":"llama3:8b"}')
        
        if [[ "$test_response" == *"response"* ]]; then
            log_success "Gateway kann mit Ollama kommunizieren"
            
            if command -v jq &> /dev/null; then
                local response_text=$(echo "$test_response" | jq -r '.response' | head -c 50)
                log_debug "Antwort (Ausschnitt): \"$response_text...\""
                
                # RAG-Informationen
                local rag_enhanced=$(echo "$test_response" | jq -r '.rag.enhanced')
                local rag_docs=$(echo "$test_response" | jq -r '.rag.docsCount')
                
                if [[ "$rag_enhanced" == "true" ]]; then
                    log_success "RAG aktiv: $rag_docs Dokumente gefunden"
                else
                    log_info "RAG nicht aktiv für diese Abfrage (erwartetes Verhalten für diesen Test)"
                fi
            else
                log_debug "Antwort: $test_response"
            fi
        else
            log_error "Kommunikation mit Ollama über das Gateway fehlgeschlagen"
            log_debug "Antwort: $test_response"
            log_info "Überprüfen Sie, ob Ollama läuft und Port 11434 verfügbar ist"
            log_info "Container-Logs prüfen mit: docker logs rag-gateway"
        fi
    else
        log_error "RAG-Gateway ist nicht unter $GATEWAY_URL erreichbar"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs rag-gateway"
        return 1
    fi
    
    return 0
}

check_webui() {
    log_header "Open WebUI-Diagnose"
    
    # Container-Status prüfen
    local status=$(get_container_status "open-webui")
    if [[ "$status" == *"running"* ]]; then
        log_success "Open WebUI Container: $status"
    else
        log_error "Open WebUI Container: $status"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs open-webui"
        return 1
    fi
    
    # Verbindung prüfen
    if curl -s "$WEBUI_URL" &> /dev/null; then
        log_success "Open WebUI ist unter $WEBUI_URL erreichbar"
        
        # Weitere Tests könnten hier hinzugefügt werden, aber die WebUI-API ist eingeschränkt
        log_info "WebUI scheint korrekt zu funktionieren. Öffnen Sie die URL in einem Browser für weitere Tests."
    else
        log_error "Open WebUI ist nicht unter $WEBUI_URL erreichbar"
        log_info "Überprüfen Sie die Container-Logs mit: docker logs open-webui"
        return 1
    fi
    
    return 0
}

check_ollama() {
    log_header "Ollama-Diagnose"
    
    # Verbindung prüfen
    if curl -s "$OLLAMA_URL/api/tags" &> /dev/null; then
        log_success "Ollama ist unter $OLLAMA_URL erreichbar"
        
        # Modelle abrufen
        local models_info=$(curl -s "$OLLAMA_URL/api/tags")
        if command -v jq &> /dev/null; then
            local models_count=$(echo "$models_info" | jq -r '.models | length')
            
            if [[ $models_count -gt 0 ]]; then
                log_success "$models_count Modelle verfügbar:"
                echo "$models_info" | jq -r '.models[].name' | while read -r model; do
                    log_debug "- $model"
                done
            else
                log_warning "Keine Modelle in Ollama gefunden"
                log_info "Laden Sie ein Modell mit: kubectl -n \$NAMESPACE exec \$POD_NAME -- ollama pull llama3:8b"
                log_info "oder: ./scripts/pull-model.sh llama3:8b"
            fi
        else
            log_debug "Modelle: $models_info"
        fi
        
        # Einfachen Generierungstest durchführen
        log_info "Teste Ollama-Generierung direkt..."
        local gen_response=$(curl -s -X POST "$OLLAMA_URL/api/generate" \
            -H "Content-Type: application/json" \
            -d '{"prompt":"Sage Hallo in einem Wort.","model":"llama3:8b","stream":false}')
        
        if [[ "$gen_response" == *"response"* ]]; then
            if command -v jq &> /dev/null; then
                local response_text=$(echo "$gen_response" | jq -r '.response' | head -c 50)
                log_success "Generierung erfolgreich: \"$response_text...\""
            else
                log_success "Generierung erfolgreich"
                log_debug "Antwort: $gen_response"
            fi
        else
            log_error "Direkte Ollama-Generierung fehlgeschlagen"
            log_debug "Antwort: $gen_response"
            log_info "Prüfen Sie die Port-Weiterleitung und stellen Sie sicher, dass ein Modell geladen ist"
        fi
    else
        log_error "Ollama ist nicht unter $OLLAMA_URL erreichbar"
        log_info "Stellen Sie sicher, dass Ollama läuft und Port-Forwarding aktiv ist mit:"
        log_info "kubectl -n \$NAMESPACE port-forward svc/\$OLLAMA_SERVICE_NAME 11434:11434"
        return 1
    fi
    
    return 0
}

test_rag_functionality() {
    log_header "RAG-Funktionalitätstest"
    
    # Sample-Dokument
    SAMPLE_DOC="$ROOT_DIR/rag/data/sample-document.md"
    
    if [ ! -f "$SAMPLE_DOC" ]; then
        log_error "Sample-Dokument nicht gefunden: $SAMPLE_DOC"
        return 1
    fi
    
    # Testbedingungen prüfen
    log_info "Prüfe Voraussetzungen für RAG-Test..."
    if ! curl -s "$GATEWAY_URL/api/health" &> /dev/null; then
        log_error "RAG-Gateway nicht erreichbar. Test kann nicht durchgeführt werden."
        return 1
    fi
    
    if ! curl -s "$OLLAMA_URL/api/tags" &> /dev/null; then
        log_error "Ollama nicht erreichbar. Test kann nicht durchgeführt werden."
        return 1
    fi
    
    # Gateway-Health-Check
    local health_info=$(curl -s "$GATEWAY_URL/api/health")
    local elasticsearch_status=""
    
    if command -v jq &> /dev/null; then
        elasticsearch_status=$(echo "$health_info" | jq -r '.elasticsearch // "nicht verbunden"')
    else
        if [[ "$health_info" == *"connected"* ]]; then
            elasticsearch_status="connected"
        else
            elasticsearch_status="nicht verbunden"
        fi
    fi
    
    if [[ "$elasticsearch_status" != "connected" ]]; then
        log_warning "Elasticsearch ist nicht mit dem Gateway verbunden. RAG-Funktionalität wird eingeschränkt sein."
        log_info "Versuche trotzdem fortzufahren..."
    fi
    
    # 1. Dokument hochladen
    log_info "Lade Sample-Dokument hoch..."
    CONTENT=$(cat "$SAMPLE_DOC" | tr -d '\n' | tr -d '"' | head -c 1000)
    
    UPLOAD_RESPONSE=$(curl -s -X POST "$GATEWAY_URL/api/rag/documents" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$CONTENT\",\"metadata\":{\"filename\":\"sample-document.md\",\"type\":\"test\"}}")
    
    local upload_success=false
    
    if command -v jq &> /dev/null; then
        if echo "$UPLOAD_RESPONSE" | jq -e '.success == true' &> /dev/null; then
            log_success "Dokument erfolgreich hochgeladen"
            upload_success=true
        else
            log_error "Dokument-Upload fehlgeschlagen: $(echo "$UPLOAD_RESPONSE" | jq -r '.error // "Unbekannter Fehler"')"
        fi
    else
        if [[ "$UPLOAD_RESPONSE" == *"success"* && "$UPLOAD_RESPONSE" == *"true"* ]]; then
            log_success "Dokument erfolgreich hochgeladen"
            upload_success=true
        else
            log_error "Dokument-Upload fehlgeschlagen: $UPLOAD_RESPONSE"
        fi
    fi
    
    # 2. RAG-Abfrage testen
    log_info "Teste RAG-Abfrage..."
    sleep 2  # Kurze Pause, damit Elasticsearch das Dokument indizieren kann
    
    TEST_QUERY="Was ist RAG und wie funktioniert es?"
    
    RAG_RESPONSE=$(curl -s -X POST "$GATEWAY_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"prompt\":\"$TEST_QUERY\",\"model\":\"llama3:8b\"}")
    
    if [[ "$RAG_RESPONSE" == *"response"* ]]; then
        log_success "RAG-Abfrage erfolgreich"
        
        if command -v jq &> /dev/null; then
            local response_text=$(echo "$RAG_RESPONSE" | jq -r '.response' | head -c 100)
            local rag_enhanced=$(echo "$RAG_RESPONSE" | jq -r '.rag.enhanced')
            local rag_docs=$(echo "$RAG_RESPONSE" | jq -r '.rag.docsCount')
            
            log_debug "Antwort (Ausschnitt): \"$response_text...\""
            
            if [[ "$rag_enhanced" == "true" ]]; then
                log_success "RAG aktiv: $rag_docs Dokumente gefunden"
                
                if [[ $rag_docs -gt 0 ]]; then
                    log_success "RAG-Funktionalität ist vollständig"
                else
                    log_warning "RAG aktiv, aber keine relevanten Dokumente gefunden"
                    log_info "Dies könnte an der Suchabfrage liegen oder das Dokument wurde nicht korrekt indiziert"
                fi
            else
                log_warning "RAG nicht aktiv für diese Abfrage"
                log_info "Dies könnte auf ein Problem mit Elasticsearch hindeuten"
                log_info "Überprüfen Sie die Container-Logs des Gateways und Elasticsearch"
            fi
        else
            log_debug "Antwort: $RAG_RESPONSE"
        fi
    else
        log_error "RAG-Abfrage fehlgeschlagen"
        log_debug "Antwort: $RAG_RESPONSE"
    fi
    
    return 0
}

show_verbose_logs() {
    local container=$1
    local lines=${2:-50}
    
    log_header "Logs für Container: $container (letzte $lines Zeilen)"
    
    if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        docker logs "$container" --tail "$lines"
    else
        log_error "Container $container nicht gefunden"
    fi
}

show_container_environment() {
    local container=$1
    
    log_header "Umgebungsvariablen für Container: $container"
    
    if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        docker exec "$container" env | sort
    else
        log_error "Container $container nicht gefunden"
    fi
}

# Hauptprogramm
log_header "RAG-Setup-Diagnose gestartet"
log_info "Diagnose läuft für folgende Komponenten:"
log_debug "- Elasticsearch: $ES_URL"
log_debug "- Kibana: $KIBANA_URL"
log_debug "- RAG-Gateway: $GATEWAY_URL"
log_debug "- Open WebUI: $WEBUI_URL"
log_debug "- Ollama: $OLLAMA_URL"

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
            echo ""
            echo "Beispiele:"
            echo "  $0                    Standard-Diagnose durchführen"
            echo "  $0 -v                 Ausführliche Diagnose durchführen"
            echo "  $0 -l rag-gateway     Logs des rag-gateway Containers anzeigen"
            echo "  $0 -e elasticsearch    Umgebungsvariablen des elasticsearch Containers anzeigen"
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
    show_verbose_logs "$LOGS_CONTAINER"
    exit 0
fi

# Umgebungsvariablen eines Containers anzeigen, wenn angefordert
if [[ "$ENV" == "true" && -n "$ENV_CONTAINER" ]]; then
    show_container_environment "$ENV_CONTAINER"
    exit 0
fi

# Standardtests durchführen
check_ollama
check_elasticsearch
check_rag_gateway
check_webui

# Im ausführlichen Modus auch Kibana und RAG-Funktionalität testen
if [[ "$VERBOSE" == "true" ]]; then
    check_kibana
    test_rag_functionality
    
    # Verbindung zwischen Gateway und Elasticsearch detaillierter prüfen
    log_header "Detaillierte Gateway-Elasticsearch-Verbindung"
    
    log_info "Gateway-Container-Umgebungsvariablen:"
    docker exec rag-gateway env | grep ELASTICSEARCH || echo "Keine ELASTICSEARCH-Variablen gefunden"
    
    log_info "Gateway kann Elasticsearch erreichen?"
    docker exec rag-gateway curl -s "$ES_URL" > /dev/null && \
        log_success "Verbindung vom Gateway zu Elasticsearch erfolgreich" || \
        log_error "Gateway kann Elasticsearch nicht erreichen"
    
    # Netzwerk-Informationen anzeigen
    log_info "Docker-Netzwerkinformationen:"
    docker network inspect rag-network | grep -A 10 "Containers" | grep -A 3 -B 1 "rag-gateway\|elasticsearch"
fi

log_header "Diagnose abgeschlossen"
log_info "Verwenden Sie folgende Optionen für weitere Informationen:"
log_debug "- Ausführliche Diagnose: $0 -v"
log_debug "- Container-Logs anzeigen: $0 -l <container-name>"
log_debug "- Container-Umgebungsvariablen anzeigen: $0 -e <container-name>"
log_debug ""
log_debug "Typische Container-Namen: elasticsearch, kibana, rag-gateway, open-webui"

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
if [[ "$JQ_AVAILABLE" == "true" ]]; then
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
