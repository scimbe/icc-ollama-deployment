#!/bin/bash

# Skript zum Setzen der korrekten Ausführungsberechtigungen für RAG-Skripte
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== Setze Ausführungsberechtigungen für RAG-Skripte ==="

# Liste der RAG-bezogenen Skripte
RAG_SCRIPTS=(
    "$SCRIPT_DIR/setup-rag.sh"
    "$SCRIPT_DIR/stop-rag.sh"
    "$SCRIPT_DIR/upload-rag-documents.sh"
)

# Setze Ausführungsberechtigungen für RAG-Skripte
for script in "${RAG_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        echo -e "${GREEN}✓${NC} Ausführungsberechtigung für $(basename "$script") gesetzt"
    else
        echo "Warnung: Skript $script nicht gefunden"
    fi
done

# Überprüfe, ob die Verzeichnisstruktur für RAG existiert
echo -e "\nÜberprüfe RAG-Verzeichnisstruktur..."

# Liste der erforderlichen Verzeichnisse
RAG_DIRS=(
    "$ROOT_DIR/rag"
    "$ROOT_DIR/rag/gateway"
    "$ROOT_DIR/rag/data"
)

for dir in "${RAG_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "Erstelle Verzeichnis $dir"
        mkdir -p "$dir"
    else
        echo -e "${GREEN}✓${NC} Verzeichnis $dir existiert bereits"
    fi
done

echo -e "\n${GREEN}Ausführungsberechtigungen wurden erfolgreich gesetzt.${NC}"
echo "Sie können jetzt die RAG-Skripte ausführen:"
echo "  ./scripts/setup-rag.sh         # Starte die RAG-Umgebung"
echo "  ./scripts/upload-rag-documents.sh    # Dokumente hochladen"
echo "  ./scripts/stop-rag.sh          # Stoppe die RAG-Umgebung"
