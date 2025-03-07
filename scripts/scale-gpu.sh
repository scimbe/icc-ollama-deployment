#!/bin/bash

# Skript zum Skalieren der GPU-Ressourcen für Ollama-Deployment
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

# Hilfe-Funktion
show_help() {
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "Skript zum Skalieren der GPU-Ressourcen für Ollama-Deployment."
    echo
    echo "Optionen:"
    echo "  -c, --count NUM    Anzahl der GPUs (1-4, abhängig von Verfügbarkeit)"
    echo "  -h, --help         Diese Hilfe anzeigen"
    echo
    echo "Beispiel:"
    echo "  $0 --count 2       Ollama auf 2 GPUs skalieren"
    exit 0
}

# Parameter parsen
GPU_COUNT_NEW=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--count)
            GPU_COUNT_NEW="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_help
            ;;
    esac
done

# Überprüfe Eingabeparameter
if [[ -z "$GPU_COUNT_NEW" ]]; then
    echo "Fehler: GPU-Anzahl muss angegeben werden."
    show_help
fi

# Validiere GPU-Anzahl
if ! [[ "$GPU_COUNT_NEW" =~ ^[1-4]$ ]]; then
    echo "Fehler: GPU-Anzahl muss zwischen 1 und 4 liegen."
    exit 1
fi

# Überprüfe ob das Ollama Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Aktuelle GPU-Anzahl abrufen
CURRENT_GPU_COUNT=$(kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.nvidia\.com/gpu}')

echo "=== GPU-Skalierung für Ollama ==="
echo "Namespace: $NAMESPACE"
echo "Deployment: $OLLAMA_DEPLOYMENT_NAME"
echo "Aktuelle GPU-Anzahl: $CURRENT_GPU_COUNT"
echo "Neue GPU-Anzahl: $GPU_COUNT_NEW"

# Bestätigung einholen
if [[ "$GPU_COUNT_NEW" == "$CURRENT_GPU_COUNT" ]]; then
    echo "Die angeforderte GPU-Anzahl entspricht der aktuellen Konfiguration."
    echo "Keine Änderung erforderlich."
    exit 0
fi

echo
read -p "Möchten Sie die Skalierung durchführen? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Temporäre JSON-Patchdatei erstellen
TMP_PATCH=$(mktemp)

cat << EOF > "$TMP_PATCH"
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu",
    "value": $GPU_COUNT_NEW
  }
]
EOF

# Patch anwenden
echo "Wende Patch an..."
kubectl -n "$NAMESPACE" patch deployment "$OLLAMA_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH"

# Aufräumen
rm "$TMP_PATCH"

# Warte auf das Rollout
echo "Warte auf Rollout der Änderungen..."
kubectl -n "$NAMESPACE" rollout status deployment/"$OLLAMA_DEPLOYMENT_NAME" --timeout=180s

# Aktualisierte Konfiguration anzeigen
echo "GPU-Skalierung abgeschlossen."
echo "Neue Konfiguration:"
kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'
echo

# Hinweis zur Prüfung der GPU-Funktionalität
echo "Bitte prüfen Sie die GPU-Funktionalität mit:"
echo "  ./scripts/test-gpu.sh"

# Hinweis zur Konfigurationsdatei
echo
echo "Hinweis: Diese Änderung ist temporär und wird bei einem erneuten Deployment"
echo "mit den Werten aus der config.sh überschrieben. Um die Änderung permanent zu machen,"
echo "aktualisieren Sie den GPU_COUNT-Wert in Ihrer configs/config.sh."
