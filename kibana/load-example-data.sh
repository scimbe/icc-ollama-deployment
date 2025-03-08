#!/bin/bash

# Skript zum Laden von Beispieldaten für RAG-Funktionalität
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"  # Nur eine Ebene hoch gehen

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    exit 1
fi

# Prüfe, ob Elasticsearch läuft
if ! kubectl -n "$NAMESPACE" get statefulset "$ES_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Elasticsearch StatefulSet '$ES_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst kibana/deploy-elasticsearch.sh aus."
    exit 1
fi

# Erstelle temporäre Datei für die Beispieldaten
TMP_TEXT_FILE=$(mktemp)
TMP_INDEX_FILE=$(mktemp)

# Schreibe Beispieltext (Alice im Wunderland)
cat << EOF > "$TMP_TEXT_FILE"
Alice's Adventures in Wonderland
by Lewis Carroll

CHAPTER I. Down the Rabbit-Hole

Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, 'and what is the use of a book,' thought Alice 'without pictures or conversations?'

So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

There was nothing so very remarkable in that; nor did Alice think it so very much out of the way to hear the Rabbit say to itself, 'Oh dear! Oh dear! I shall be late!' (when she thought it over afterwards, it occurred to her that she ought to have wondered at this, but at the time it all seemed quite natural); but when the Rabbit actually took a watch out of its waistcoat-pocket, and looked at it, and then hurried on, Alice started to her feet, for it flashed across her mind that she had never before seen a rabbit with either a waistcoat-pocket, or a watch to take out of it, and burning with curiosity, she ran across the field after it, and fortunately was just in time to see it pop down a large rabbit-hole under the hedge.

In another moment down went Alice after it, never once considering how in the world she was to get out again.

The rabbit-hole went straight on like a tunnel for some way, and then dipped suddenly down, so suddenly that Alice had not a moment to think about stopping herself before she found herself falling down a very deep well.

Either the well was very deep, or she fell very slowly, for she had plenty of time as she went down to look about her and to wonder what was going to happen next. First, she tried to look down and make out what she was coming to, but it was too dark to see anything; then she looked at the sides of the well, and noticed that they were filled with cupboards and book-shelves; here and there she saw maps and pictures hung upon pegs. She took down a jar from one of the shelves as she passed; it was labelled 'ORANGE MARMALADE', but to her great disappointment it was empty: she did not like to drop the jar for fear of killing somebody, so managed to put it into one of the cupboards as she fell past it.
EOF

# Erstelle Index-Konfiguration mit Vektorsuche
cat << EOF > "$TMP_INDEX_FILE"
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "properties": {
      "text": {
        "type": "text",
        "analyzer": "standard",
        "copy_to": "text_vector"
      },
      "text_vector": {
        "type": "semantic_text",
        "inference_id": "${EMBEDDING_MODEL}"
      }
    }
  }
}
EOF

# Starte Port-Forwarding für Elasticsearch
echo "Starte Port-Forwarding für Elasticsearch..."
kubectl -n "$NAMESPACE" port-forward "statefulset/$ES_DEPLOYMENT_NAME" 9200:9200 &
PF_PID=$!
sleep 5

# Erstelle den Index
echo "Erstelle Index 'rag-demo' mit Vektorsuche..."
curl -X PUT "http://localhost:9200/rag-demo" \
  -H "Content-Type: application/json" \
  -d @"$TMP_INDEX_FILE"

# Frage den Text und speichere ihn in Chunks
echo "Indiziere Beispieldaten..."
CHUNK_SIZE=500
TEXT=$(cat "$TMP_TEXT_FILE")
TEXT_LENGTH=${#TEXT}

# Indiziere den Text in Chunks
for (( i=0; i<TEXT_LENGTH; i+=CHUNK_SIZE )); do
  CHUNK="${TEXT:$i:$CHUNK_SIZE}"
  DOC_ID=$((i / CHUNK_SIZE + 1))
  
  # Erstelle JSON für diesen Chunk
  TMP_DOC=$(mktemp)
  echo "{\"text\": \"${CHUNK//\"/\\\"}\"}" > "$TMP_DOC"
  
  # Füge den Chunk zum Index hinzu
  curl -X POST "http://localhost:9200/rag-demo/_doc/$DOC_ID" \
    -H "Content-Type: application/json" \
    -d @"$TMP_DOC"
  
  rm "$TMP_DOC"
  echo "Chunk $DOC_ID indiziert."
done

# Erzwinge Aktualisierung des Index für sofortige Suche
curl -X POST "http://localhost:9200/rag-demo/_refresh" \
  -H "Content-Type: application/json"
  
# Aufräumen
kill $PF_PID
rm "$TMP_TEXT_FILE" "$TMP_INDEX_FILE"

echo
echo "Beispieldaten wurden erfolgreich in Elasticsearch geladen."
echo "Sie können jetzt RAG-Tests mit 'Alice im Wunderland' durchführen."
echo 
echo "Schritte zur Nutzung im Playground:"
echo "1. Öffnen Sie Kibana und navigieren Sie zu 'Elasticsearch > Playground'"
echo "2. Wählen Sie 'rag-demo' als Datenquelle"
echo "3. Passen Sie den System-Prompt an (z.B. 'Verwende die folgenden Kontextinformationen...')"
echo "4. Stellen Sie eine Frage wie 'Was passierte mit dem weißen Kaninchen?'"
