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
    echo "  -t, --type        Dokumenttyp (text, markdown, pdf)"
    echo "  -s, --split       Dokumente in Chunks aufteilen (Standard: true)"
    echo "  -c, --chunk-size  Chunk-Größe für Aufteilung (Standard: 500 Wörter)"
    echo
    echo "Beispiele:"
    echo "  $0 mein_dokument.txt                        # TXT-Datei hochladen"
    echo "  $0 --type markdown dokumentation.md         # Markdown-Datei hochladen"
    echo "  $0 --split false grosses_dokument.txt       # Ohne Aufteilung hochladen"
    exit 0
}

# Standardwerte
URL="$GATEWAY_URL"
DOCUMENT_TYPE="text"
SPLIT=true
CHUNK_SIZE=500

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

# Prüfe, ob RAG-Gateway erreichbar ist
if ! curl -s "$URL/api/health" &> /dev/null; then
    echo -e "${RED}Fehler: RAG-Gateway unter $URL ist nicht erreichbar.${NC}"
    echo "Bitte starten Sie die RAG-Umgebung mit ./scripts/setup-rag.sh"
    exit 1
fi

# Dateiinhalt lesen
echo -e "${YELLOW}Lese Datei '$FILE_PATH'...${NC}"
FILE_CONTENT=$(cat "$FILE_PATH")
FILENAME=$(basename "$FILE_PATH")

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
        
        # Extrahiere Chunk (wir verwenden hier awk für Wortextraktion)
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
        
        # Escapen von Anführungszeichen für JSON
        CHUNK_CONTENT=$(echo "$CHUNK_CONTENT" | sed 's/"/\\"/g')
        
        # Metadaten für den Chunk erstellen
        METADATA="{\"filename\":\"$FILENAME\",\"type\":\"$DOCUMENT_TYPE\",\"chunk\":$i,\"totalChunks\":$CHUNKS_COUNT}"
        
        echo -e "${YELLOW}Lade Chunk $i von $CHUNKS_COUNT hoch...${NC}"
        
        # An das Gateway senden
        RESPONSE=$(curl -s -X POST "$URL/api/rag/documents" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$CHUNK_CONTENT\",\"metadata\":$METADATA}")
        
        if [[ "$RESPONSE" == *"success"* ]]; then
            echo -e "${GREEN}✓${NC} Chunk $i erfolgreich hochgeladen"
        else
            echo -e "${RED}✗${NC} Fehler beim Hochladen von Chunk $i: $RESPONSE"
        fi
        
        sleep 0.2  # Kurze Pause zwischen Uploads
    done
    
    # Aufräumen
    rm -f "$TMP_FILE"
else
    # Gesamtes Dokument als einen Eintrag hochladen
    echo -e "${YELLOW}Lade komplettes Dokument als einen Eintrag hoch...${NC}"
    
    # Escapen von Anführungszeichen für JSON
    FILE_CONTENT_ESCAPED=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g')
    
    # Metadaten für das Dokument erstellen
    METADATA="{\"filename\":\"$FILENAME\",\"type\":\"$DOCUMENT_TYPE\"}"
    
    # An das Gateway senden
    RESPONSE=$(curl -s -X POST "$URL/api/rag/documents" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$FILE_CONTENT_ESCAPED\",\"metadata\":$METADATA}")
    
    if [[ "$RESPONSE" == *"success"* ]]; then
        echo -e "${GREEN}✓${NC} Dokument erfolgreich hochgeladen"
    else
        echo -e "${RED}✗${NC} Fehler beim Hochladen: $RESPONSE"
    fi
fi

echo -e "\n${GREEN}Upload abgeschlossen.${NC}"
echo -e "Sie können jetzt die RAG-Funktionalität mit der Ollama WebUI unter ${YELLOW}http://localhost:3000${NC} testen."
