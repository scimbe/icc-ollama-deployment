#!/bin/bash

# Skript zum Erstellen eines Ingress für öffentlichen Zugriff
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    exit 1
fi

# Überprüfe, ob CREATE_INGRESS aktiviert ist
if [ "$CREATE_INGRESS" != "true" ]; then
    echo "Ingress-Erstellung ist in der Konfiguration deaktiviert."
    echo "Setzen Sie CREATE_INGRESS=true in Ihrer config.sh, um einen Ingress zu erstellen."
    exit 0
fi

# Überprüfe, ob DOMAIN_NAME gesetzt ist
if [ -z "$DOMAIN_NAME" ]; then
    echo "Fehler: DOMAIN_NAME ist nicht gesetzt."
    echo "Bitte definieren Sie DOMAIN_NAME in Ihrer config.sh."
    exit 1
fi

# Erstelle temporäre YAML-Datei für den Ingress
TMP_FILE=$(mktemp)

# Erstelle YAML für Ingress
cat << EOF > "$TMP_FILE"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ollama-ingress
  namespace: $NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: $DOMAIN_NAME
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: $WEBUI_SERVICE_NAME
            port:
              number: 8080
  tls: 
  - hosts:
    - $DOMAIN_NAME
    secretName: ollama-tls-cert
EOF

# Anwenden der Konfiguration
echo "Erstelle Ingress für $DOMAIN_NAME..."
kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

echo "Ingress erstellt. Wichtige Hinweise:"
echo "1. Stellen Sie sicher, dass ein CNAME-Eintrag von $DOMAIN_NAME auf 'icc-k8s-api.informatik.haw-hamburg.de' verweist."
echo "2. Die Zertifikatserstellung kann einige Minuten dauern."
echo "3. Standardmäßig ist der Zugriff nur aus dem HAW-Netz möglich."
echo "4. Für weltweiten Zugriff kontaktieren Sie das ICC-Team über den MS-Teams-Kanal."
echo "5. Beachten Sie die rechtlichen Auflagen: Entweder Zugangsbeschränkung oder korrektes Impressum mit Datenschutzerklärung."
