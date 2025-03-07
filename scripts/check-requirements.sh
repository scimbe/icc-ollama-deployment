#!/bin/bash

# Skript zur Überprüfung der Voraussetzungen für das ICC Ollama Deployment
set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "=== Überprüfung der Voraussetzungen für ICC Ollama Deployment ==="

# Funktion zur Überprüfung eines Befehls
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 ist installiert"
        return 0
    else
        echo -e "${RED}✗${NC} $1 ist nicht installiert"
        return 1
    fi
}

# Funktion zur Überprüfung der Kubernetes-Verbindung
check_kubernetes() {
    # Namespace aus Kubeconfig ermitteln oder vom Benutzer abfragen
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
    if [ -z "$CURRENT_CONTEXT" ]; then
        echo -e "${RED}✗${NC} Kein Kubernetes-Kontext gefunden. Sind Sie bei der ICC eingeloggt?"
        return 1
    fi
    
    NAMESPACE=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "")
    if [ -z "$NAMESPACE" ]; then
        echo -e "${YELLOW}Kein Standard-Namespace gefunden. Bitte geben Sie Ihren Namespace ein (z.B. wXYZ123-default):${NC}"
        read -r NAMESPACE
        if [ -z "$NAMESPACE" ]; then
            echo -e "${RED}✗${NC} Kein Namespace angegeben"
            return 1
        fi
    fi
    
    echo -e "Verwende Namespace: ${YELLOW}$NAMESPACE${NC}"
    
    # Prüfung mit Namespace
    if kubectl -n "$NAMESPACE" cluster-info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Kubernetes-Verbindung zur ICC hergestellt"
        echo -e "   Kontext: $(kubectl config current-context)"
        echo -e "   Namespace: $NAMESPACE"
        return 0
    else
        echo -e "${RED}✗${NC} Keine Verbindung zu Kubernetes möglich"
        return 1
    fi
}

# Überprüfe kubectl
kubectl_ok=0
check_command "kubectl" && kubectl_ok=1

# Überprüfe Terraform
terraform_ok=0
check_command "terraform" && terraform_ok=1

# Überprüfe Docker
docker_ok=0
check_command "docker" && docker_ok=1

# Überprüfe Make
make_ok=0
check_command "make" && make_ok=1

# Kubernetes-Verbindung überprüfen, wenn kubectl installiert ist
k8s_ok=0
if [ $kubectl_ok -eq 1 ]; then
    check_kubernetes && k8s_ok=1
fi

# Zusammenfassung
echo -e "\n=== Zusammenfassung ==="
if [ $kubectl_ok -eq 1 ] && [ $k8s_ok -eq 1 ]; then
    echo -e "${GREEN}Kubernetes-Setup: OK${NC}"
else
    echo -e "${RED}Kubernetes-Setup: FEHLT${NC}"
    echo -e "${YELLOW}Bitte installieren Sie kubectl und stellen Sie sicher, dass Sie Zugriff auf die ICC haben.${NC}"
    echo -e "${YELLOW}Verwenden Sie das Skript ./scripts/icc-login.sh, um sich anzumelden.${NC}"
    echo -e "${YELLOW}Siehe auch: https://kubernetes.io/docs/tasks/tools/${NC}"
fi

if [ $terraform_ok -eq 1 ]; then
    echo -e "${GREEN}Terraform: OK${NC}"
else
    echo -e "${YELLOW}Terraform: FEHLT (nur für lokale WebUI erforderlich)${NC}"
    echo -e "${YELLOW}Siehe: https://developer.hashicorp.com/terraform/install${NC}"
fi

if [ $docker_ok -eq 1 ]; then
    echo -e "${GREEN}Docker: OK${NC}"
else
    echo -e "${YELLOW}Docker: FEHLT (nur für lokale Entwicklung erforderlich)${NC}"
    echo -e "${YELLOW}Siehe: https://docs.docker.com/get-docker/${NC}"
fi

if [ $make_ok -eq 1 ]; then
    echo -e "${GREEN}Make: OK${NC}"
else
    echo -e "${YELLOW}Make: FEHLT (optional)${NC}"
fi

# Prüfe, ob die Konfigurationsdatei existiert
ROOT_DIR="$(dirname "$(dirname "$0")")"
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    echo -e "${GREEN}Konfigurationsdatei: OK${NC}"
else
    echo -e "${RED}Konfigurationsdatei: FEHLT${NC}"
    echo -e "${YELLOW}Bitte erstellen Sie die Konfigurationsdatei mit:${NC}"
    echo -e "${YELLOW}cp configs/config.example.sh configs/config.sh${NC}"
fi

# Ausgabe des Status
if [ $kubectl_ok -eq 1 ] && [ $k8s_ok -eq 1 ]; then
    echo -e "\n${GREEN}Das System ist bereit für das ICC Ollama Deployment.${NC}"
    
    # Speichere Namespace für spätere Verwendung
    if [ -n "$NAMESPACE" ] && [ ! -f "$ROOT_DIR/configs/config.sh" ]; then
        echo -e "\n${YELLOW}Tipp: Erstellen Sie die Konfigurationsdatei mit Ihrem Namespace:${NC}"
        echo -e "cp configs/config.example.sh configs/config.sh"
        echo -e "sed -i 's/wXYZ123-default/$NAMESPACE/g' configs/config.sh"
    fi
else
    echo -e "\n${RED}Einige Voraussetzungen sind nicht erfüllt. Bitte beheben Sie die Probleme vor dem Deployment.${NC}"
    exit 1
fi