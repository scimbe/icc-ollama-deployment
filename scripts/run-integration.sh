#!/bin/bash

# Skript zum Starten der Ollama-Elasticsearch-Integration mit Terraform

set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farben für die Ausgabe
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Ollama-Elasticsearch-Integration starten ===${NC}"

# Prüfe, ob Docker läuft
if ! docker info &>/dev/null; then
    echo "Fehler: Docker ist nicht gestartet oder der Benutzer hat keine ausreichenden Berechtigungen."
    echo "Bitte starten Sie Docker und stellen Sie sicher, dass Ihr Benutzer die entsprechenden Rechte hat."
    exit 1
fi

# Prüfe, ob Terraform installiert ist
if ! command -v terraform &>/dev/null; then
    echo "Fehler: Terraform ist nicht installiert oder nicht im PATH."
    echo "Bitte installieren Sie Terraform gemäß der Anleitung: https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi

# Initialisiere und starte Terraform
cd "$ROOT_DIR/terraform"

echo -e "\n${YELLOW}Terraform initialisieren...${NC}"
terraform init

echo -e "\n${YELLOW}Terraform ausführen...${NC}"
terraform apply -auto-approve

# Container-Status prüfen
CONTAINER_NAME=$(terraform output -raw integration_container_name)
echo -e "\n${YELLOW}Prüfe Container-Status...${NC}"
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${GREEN}Container $CONTAINER_NAME läuft.${NC}"
else
    echo "Fehler: Container $CONTAINER_NAME läuft nicht."
    echo "Bitte prüfen Sie die Docker-Logs für weitere Informationen:"
    echo "docker logs $CONTAINER_NAME"
    exit 1
fi

echo -e "\n${GREEN}=== Integration erfolgreich gestartet! ===${NC}"
echo
echo "Der Docker-Container '$CONTAINER_NAME' läuft nun und verbindet Ollama mit Elasticsearch."
echo
echo "Um die Logs anzuzeigen:"
echo "  docker logs -f $CONTAINER_NAME"
echo
echo "Um die Integration zu stoppen, führen Sie aus:"
echo "  cd $ROOT_DIR/terraform && terraform destroy -auto-approve"
echo
echo "Nachdem Daten in Elasticsearch gespeichert wurden, können Sie diese in Kibana anzeigen:"
echo "1. Öffnen Sie Kibana (z.B. über http://localhost:5601)"
echo "2. Gehen Sie zu Stack Management > Index Patterns"
echo "3. Erstellen Sie ein neues Index Pattern für 'ollama-responses*'"
echo "4. Erkunden Sie die Daten unter Discover"
