#!/bin/bash
source configs/config.sh
# Skript zum Öffnen der ICC-Login-Seite und Hilfe beim Download der Kubeconfig
set -e

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ICC_LOGIN_URL="https://icc-login.informatik.haw-hamburg.de/"
KUBECONFIG_PATH="$HOME/.kube/config"   # In some configurations it differ

echo -e "${BLUE}=== ICC Login Helper ===${NC}"
echo -e "Dieses Skript öffnet die ICC-Login-Seite in Ihrem Standard-Browser."
echo -e "Sie können dann:"
echo -e "  1. Sich mit Ihrer ${YELLOW}infw-Kennung${NC} anmelden"
echo -e "  2. Die Kubeconfig-Datei herunterladen"
echo -e "  3. Die Datei in Ihrem Kubernetes-Konfigurationsverzeichnis platzieren"
echo

# Funktion zum Öffnen des Browsers basierend auf dem Betriebssystem
open_browser() {
    case "$(uname -s)" in
        Linux*)
            if command -v xdg-open &> /dev/null; then
                xdg-open "$ICC_LOGIN_URL"
            else
                echo -e "${YELLOW}Konnte den Browser nicht automatisch öffnen.${NC}"
                echo -e "Bitte öffnen Sie manuell die URL: $ICC_LOGIN_URL"
                return 1
            fi
            ;;
        Darwin*)  # macOS
            open "$ICC_LOGIN_URL"
            ;;
        CYGWIN*|MINGW*|MSYS*)  # Windows
            start "$ICC_LOGIN_URL" || (
                echo -e "${YELLOW}Konnte den Browser nicht automatisch öffnen.${NC}"
                echo -e "Bitte öffnen Sie manuell die URL: $ICC_LOGIN_URL"
                return 1
            )
            ;;
        *)
            echo -e "${YELLOW}Unbekanntes Betriebssystem. Konnte den Browser nicht automatisch öffnen.${NC}"
            echo -e "Bitte öffnen Sie manuell die URL: $ICC_LOGIN_URL"
            return 1
            ;;
    esac
    return 0
}

# Öffne Browser
echo -e "Öffne Browser mit der ICC-Login-Seite..."
if open_browser; then
    echo -e "${GREEN}✓${NC} Browser wurde geöffnet."
else
    echo -e "Bitte öffnen Sie die Seite manuell: $ICC_LOGIN_URL"
fi

echo
echo -e "${BLUE}=== Anleitung ===${NC}"
echo -e "1. Melden Sie sich mit Ihrer infw-Kennung an."
echo -e "2. Klicken Sie auf 'Download Config'."
echo -e "3. Warten Sie, bis die Konfigurationsdatei heruntergeladen wurde."
echo

# Warte auf Benutzereingabe, um fortzufahren
read -p "Drücken Sie Enter, wenn Sie die Konfigurationsdatei heruntergeladen haben..." -r

# Frage nach dem Pfad zur heruntergeladenen Datei
echo
echo -e "${BLUE}=== Kubeconfig einrichten ===${NC}"
echo -e "Bitte geben Sie den vollständigen Pfad zur heruntergeladenen Konfigurationsdatei an"
echo -e "(oder lassen Sie es leer, um den Standardpfad zu verwenden: ~/Downloads/config.txt):"
read -r CONFIG_PATH

# Wenn kein Pfad angegeben wurde, verwende Standardpfad
if [ -z "$CONFIG_PATH" ]; then
    CONFIG_PATH="$HOME/Downloads/config.txt"
    echo -e "Verwende Standardpfad: $CONFIG_PATH"
fi

# Überprüfe, ob die Datei existiert
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${YELLOW}Die angegebene Datei wurde nicht gefunden: $CONFIG_PATH${NC}"
    echo -e "Bitte stellen Sie sicher, dass Sie den richtigen Pfad angegeben haben."
    exit 1
fi

# Erstelle .kube-Verzeichnis, falls es nicht existiert
mkdir -p "$HOME/.kube"

# Kopiere die Konfigurationsdatei
echo -e "Kopiere Konfigurationsdatei nach $KUBECONFIG_PATH..."
cp "$CONFIG_PATH" "$KUBECONFIG_PATH"

# Setze Berechtigungen
chmod 600 "$KUBECONFIG_PATH"

echo -e "${GREEN}✓${NC} Kubeconfig wurde erfolgreich eingerichtet!"
echo -e "Sie können jetzt kubectl verwenden, um mit der ICC zu interagieren."
echo

# Teste die Verbindung
echo -e "${BLUE}=== Verbindungstest ===${NC}"
echo -e "Teste Verbindung zur ICC..."
CURRENT_NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
if kubectl cluster-info -n $CURRENT_NS  &> /dev/null; then
    echo -e "${GREEN}✓${NC} Verbindung erfolgreich hergestellt!"
    echo -e "Ihre aktueller Kontext ist: $(kubectl config current-context)"
    
    # Zeige Namespace-Informationen an
    echo -e "\n${BLUE}=== Namespace-Informationen ===${NC}"
    CURRENT_NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
    echo -e "Ihr aktueller Namespace ist: ${YELLOW}$CURRENT_NS${NC}"
    
    echo -e "\nVerfügbare Subnamespaces:"
    kubectl get subns -n $CURRENT_NS 2>/dev/null || echo -e "${YELLOW}Keine Subnamespaces gefunden oder keine Berechtigung.${NC}"
else
    echo -e "${YELLOW}Konnte keine Verbindung zur ICC herstellen.${NC}"
    echo -e "Bitte überprüfen Sie Ihre VPN-Verbindung und die Kubeconfig-Datei."
    echo -e "Auch wird ~/kube/config genutzt, das kann in anderen Konfigurationen abweichen"
fi

echo
echo -e "${GREEN}Sie können jetzt die ICC-Ollama-Deployment-Skripte verwenden!${NC}"
echo -e "Passen Sie zunächst die Konfigurationsdatei an:"
echo -e "cp configs/config.example.sh configs/config.sh"
echo -e "nano configs/config.sh  # Anpassen an Ihren Namespace"
