#!/bin/bash

# Skript zum Hochladen von Dokumenten für RAG
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Konfigurationsparameter
GATEWAY_URL="http://localhost:3100"
ELASTICSEARCH_URL="http://localhost:9200"  # Direkter Elasticsearch-Zugriff als Fallback
ELASTICSEARCH_INDEX="ollama-rag"

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN] DATEI"
    echo
    echo "Dokumente für RAG in Elasticsearch hochladen"
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -u, --url         URL des RAG-Gateways (Standard: $GATEWAY_URL)"
    echo "  -e, --elastic     URL von Elasticsearch (Standard: $ELASTICSEARCH_URL)"
    echo "  -t, --type        Dokumenttyp (text, markdown, pdf)"
    echo "  -s, --split       Dokumente in Chunks aufteilen (Standard: true)"
    echo "  -c, --chunk-size  Chunk-Größe für Aufteilung (Standard: 500 Wörter)"
    echo "  -d, --direct      Direkt in Elasticsearch hochladen, Gateway umgehen"
    echo
    echo "Beispiele:"
    echo "  $0 mein_dokument.txt                        # TXT-Datei hochladen"
    echo "  $0 --type markdown dokumentation.md         # Markdown-Datei hochladen"
    echo "  $0 --split false grosses_dokument.txt       # Ohne Aufteilung hochladen"
    echo "  $0 --direct wichtige_daten.txt              # Direkt in Elasticsearch laden"
    exit 0
}

# Standardwerte
URL="$GATEWAY_URL"
ELASTIC_URL="$ELASTICSEARCH_URL"
DOCUMENT_TYPE="text"
SPLIT=true
CHUNK_SIZE=500
DIRECT_TO_ES=false

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -u|--url)
            URL="$2"
            shift 2
            ;;
        -e|--elastic)
            ELASTIC_URL="$2"
            shift 2
            ;;
        -t|--type)
            DOCUMENT_TYPE="$2"
            shift 2
            ;;
        -s|--split)
            SPLIT="$2"
            shift 2
            ;;
        -c|--chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
        -d|--direct)
            DIRECT_TO_ES=true
            shift
            ;;
        *)
            FILE_PATH="$1"
            shift
            ;;
    esac
done

# Überprüfen, ob eine Datei angegeben wurde
if [ -z "$FILE_PATH" ]; then
    echo -e "${RED}Fehler: Keine Datei angegeben.${NC}"
    show_help
fi

# Überprüfen, ob die Datei existiert
if [ ! -f "$FILE_PATH" ]; then
    echo -e "${RED}Fehler: Die Datei '$FILE_PATH' existiert nicht.${NC}"
    exit 1
fi

# Prüfe Erreichbarkeit der Services
if [ "$DIRECT_TO_ES" = true ]; then
    echo -e "${YELLOW}Verwende direkten Elasticsearch-Upload...${NC}"
    if ! curl -s "$ELASTIC_URL" &> /dev/null; then
        echo -e "${RED}Fehler: Elasticsearch unter $ELASTIC_URL ist nicht erreichbar.${NC}"
        echo "Bitte starten Sie die Elasticsearch-Umgebung."
        exit 1
    fi
else
    echo -e "${YELLOW}Prüfe RAG-Gateway-Verfügbarkeit...${NC}"
    if ! curl -s "$URL/api/health" &> /dev/null; then
        echo -e "${RED}Fehler: RAG-Gateway unter $URL ist nicht erreichbar.${NC}"
        echo "Versuche, direkt mit Elasticsearch zu kommunizieren..."
        
        if ! curl -s "$ELASTIC_URL" &> /dev/null; then
            echo -e "${RED}Fehler: Auch Elasticsearch unter $ELASTIC_URL ist nicht erreichbar.${NC}"
            echo "Bitte starten Sie die RAG-Umgebung mit ./scripts/setup-rag.sh"
            exit 1
        else
            echo -e "${YELLOW}Elasticsearch ist erreichbar, verwende direkten Upload als Fallback...${NC}"
            DIRECT_TO_ES=true
        fi
    fi
fi

# Dateiinhalt lesen
echo -e "${YELLOW}Lese Datei '$FILE_PATH'...${NC}"
FILE_CONTENT=$(cat "$FILE_PATH")
FILENAME=$(basename "$FILE_PATH")

# Funktion zum Direkten Upload in Elasticsearch
upload_to_elasticsearch() {
    local content="$1"
    local metadata="$2"
    
    # Escapen von Anführungszeichen für JSON
    local content_escaped=$(echo "$content" | sed 's/"/\\"/g')
    
    # An Elasticsearch senden
    local response=$(curl -s -X POST "$ELASTIC_URL/$ELASTICSEARCH_INDEX/_doc" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$content_escaped\",\"metadata\":$metadata,\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}")
    
    if [[ "$response" == *"\"result\":\"created\""* ]] || [[ "$response" == *"\"result\":\"updated\""* ]]; then
        echo -e "${GREEN}✓${NC} Dokument erfolgreich in Elasticsearch hochgeladen"
        return 0
    else
        echo -e "${RED}✗${NC} Fehler beim Hochladen in Elasticsearch: $response"
        return 1
    fi
}

# Funktion zum Upload über Gateway
upload_to_gateway() {
    local content="$1"
    local metadata="$2"
    
    # Escapen von Anführungszeichen für JSON
    local content_escaped=$(echo "$content" | sed 's/"/\\"/g')
    
    # An das Gateway senden
    local response=$(curl -s -X POST "$URL/api/rag/documents" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$content_escaped\",\"metadata\":$metadata}")
    
    if [[ "$response" == *"success"* ]]; then
        echo -e "${GREEN}✓${NC} Dokument erfolgreich über Gateway hochgeladen"
        return 0
    else
        echo -e "${RED}✗${NC} Fehler beim Hochladen über Gateway: $response"
        return 1
    fi
}

# Funktion zum Upload (wählt Gateway oder direkt je nach Konfiguration)
upload_document() {
    local content="$1"
    local metadata="$2"
    
    if [ "$DIRECT_TO_ES" = true ]; then
        upload_to_elasticsearch "$content" "$metadata"
    else
        if ! upload_to_gateway "$content" "$metadata"; then
            echo -e "${YELLOW}Gateway-Upload fehlgeschlagen, versuche direkten Upload in Elasticsearch...${NC}"
            upload_to_elasticsearch "$content" "$metadata"
        fi
    fi
}

# Wenn Aufteilung aktiviert ist, teile den Inhalt in Chunks
if [ "$SPLIT" = "true" ]; then
    echo -e "${YELLOW}Teile Dokument in Chunks (Größe: $CHUNK_SIZE Wörter)...${NC}"
    
    # Zähle Wörter und berechne die Anzahl der Chunks
    TOTAL_WORDS=$(echo "$FILE_CONTENT" | wc -w | tr -d ' ')
    CHUNKS_COUNT=$(( ($TOTAL_WORDS + $CHUNK_SIZE - 1) / $CHUNK_SIZE ))
    
    echo "Gesamtanzahl Wörter: $TOTAL_WORDS"
    echo "Anzahl Chunks: $CHUNKS_COUNT"
    
    # Temporäre Datei für die Aufteilung erstellen
    TMP_FILE=$(mktemp)
    
    # Alle Wörter in eine temporäre Datei schreiben
    echo "$FILE_CONTENT" > "$TMP_FILE"
    
    # In Chunks aufteilen und hochladen
    for (( i=1; i<=$CHUNKS_COUNT; i++ )); do
        # Berechne Start- und Endposition für den Chunk
        START_WORD=$(( ($i - 1) * $CHUNK_SIZE + 1 ))
        END_WORD=$(( $i * $CHUNK_SIZE ))
        if [ $END_WORD -gt $TOTAL_WORDS ]; then
            END_WORD=$TOTAL_WORDS
        fi
        
        # Extrahiere Chunk mit awk
        CHUNK_CONTENT=$(cat "$TMP_FILE" | awk -v start="$START_WORD" -v end="$END_WORD" '
            BEGIN { RS=" |\n"; count=0; text="" }
            { 
                count++;
                if (count >= start && count <= end) {
                    text = text " " $0;
                }
            }
            END { print text }
        ')
        
        # Metadaten für den Chunk erstellen
        METADATA="{\"filename\":\"$FILENAME\",\"type\":\"$DOCUMENT_TYPE\",\"chunk\":$i,\"totalChunks\":$CHUNKS_COUNT}"
        
        echo -e "${YELLOW}Lade Chunk $i von $CHUNKS_COUNT hoch...${NC}"
        upload_document "$CHUNK_CONTENT" "$METADATA"
        
        sleep 0.2  # Kurze Pause zwischen Uploads
    done
    
    # Aufräumen
    rm -f "$TMP_FILE"
else
    # Gesamtes Dokument als einen Eintrag hochladen
    echo -e "${YELLOW}Lade komplettes Dokument als einen Eintrag hoch...${NC}"
    
    # Metadaten für das Dokument erstellen
    METADATA="{\"filename\":\"$FILENAME\",\"type\":\"$DOCUMENT_TYPE\"}"
    
    upload_document "$FILE_CONTENT" "$METADATA"
fi

echo -e "\n${GREEN}Upload abgeschlossen.${NC}"
echo -e "Sie können jetzt die RAG-Funktionalität mit der Ollama WebUI unter ${YELLOW}http://localhost:3000${NC} testen."
