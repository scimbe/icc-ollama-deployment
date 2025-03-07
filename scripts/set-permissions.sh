#!/bin/bash

# Skript zum Setzen der korrekten Ausführungsberechtigungen für alle Skripte
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== Setze Ausführungsberechtigungen für Skripte ==="

# Setze Ausführungsberechtigungen für alle .sh Dateien im scripts/ Verzeichnis
echo "Verarbeite Skripte im $SCRIPT_DIR Verzeichnis..."
find "$SCRIPT_DIR" -name "*.sh" -type f -exec chmod +x {} \;
echo -e "${GREEN}✓${NC} Ausführungsberechtigungen für Skripte gesetzt"

# Setze Ausführungsberechtigungen für Hauptskripte im Root-Verzeichnis
echo "Verarbeite Skripte im $ROOT_DIR Verzeichnis..."
if [ -f "$ROOT_DIR/deploy.sh" ]; then
    chmod +x "$ROOT_DIR/deploy.sh"
    echo -e "${GREEN}✓${NC} Ausführungsberechtigung für deploy.sh gesetzt"
fi

# Ausgabe der Skripte mit Ausführungsberechtigungen
echo -e "\nSkripte mit Ausführungsberechtigungen:"
find "$SCRIPT_DIR" -name "*.sh" -type f -executable | sort | sed 's|.*/||' | sed 's/^/  /'
if [ -f "$ROOT_DIR/deploy.sh" ] && [ -x "$ROOT_DIR/deploy.sh" ]; then
    echo "  deploy.sh"
fi

echo -e "\nBerechtigungen wurden erfolgreich gesetzt."
echo "Sie können jetzt die Skripte ausführen, z.B.:"
echo "  ./scripts/test-gpu.sh"
echo "  ./scripts/monitor-gpu.sh"
echo "  make gpu-test"
