#!/bin/bash

# Verbessertes Skript zum Testen der GPU-Funktionalität im Ollama Pod
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

# Überprüfe ob das Ollama Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: Ollama Deployment '$OLLAMA_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Überprüfe ob GPU aktiviert ist
if [ "$USE_GPU" != "true" ]; then
    echo "Fehler: GPU-Unterstützung ist in der Konfiguration nicht aktiviert."
    echo "Bitte setzen Sie USE_GPU=true in Ihrer config.sh."
    exit 1
fi

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "Fehler: Konnte keinen laufenden Ollama Pod finden."
    exit 1
fi

echo "Teste GPU-Verfügbarkeit im Pod '$POD_NAME'..."

# Führe nvidia-smi im Pod aus
echo -e "\n=== NVIDIA-SMI Ausgabe ==="
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi; then
    echo -e "\n✅ NVIDIA GPU erfolgreich erkannt und verfügbar!"
else
    echo -e "\n❌ Fehler: nvidia-smi konnte nicht ausgeführt werden. GPU möglicherweise nicht verfügbar."
    exit 1
fi

# Prüfe Umgebungsvariablen für CUDA
echo -e "\n=== CUDA Umgebungsvariablen ==="
echo "LD_LIBRARY_PATH:"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $LD_LIBRARY_PATH'
echo "NVIDIA_DRIVER_CAPABILITIES:"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $NVIDIA_DRIVER_CAPABILITIES'

# Teste CUDA-Verfügbarkeit
echo -e "\n=== CUDA-Verfügbarkeit ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'ls -la /usr/local/cuda 2>/dev/null || echo "CUDA-Verzeichnis nicht gefunden"'

# Teste die verfügbaren Modelle
echo -e "\n=== Verfügbare Modelle ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama list || echo "Keine Modelle gefunden oder Befehl fehlgeschlagen."

# Teste die Ollama-API
echo -e "\n=== Ollama API Test ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- curl -s http://localhost:11434/api/tags | grep -q "models" && \
    echo "✅ Ollama API funktioniert korrekt." || \
    echo "❌ Ollama API antwortet nicht wie erwartet."

# Optional: Einfacher Inferenztest mit einem vorhandenen Modell
echo -e "\n=== GPU-Inferenztest (optional) ==="
read -p "Möchten Sie einen GPU-Inferenztest durchführen? (j/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    # Liste verfügbare Modelle
    MODELS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ollama list -j 2>/dev/null | grep "name" | awk -F'"' '{print $4}')
    
    if [ -z "$MODELS" ]; then
        echo "Keine Modelle für den Inferenztest verfügbar. Bitte laden Sie zuerst ein Modell mit:"
        echo "./scripts/pull-model.sh llama3:8b"
        echo "oder ein anderes kleines Modell."
    else
        echo "Verfügbare Modelle: $MODELS"
        # Wähle das erste Modell für den Test
        MODEL=$(echo "$MODELS" | head -n 1)
        echo "Führe Inferenztest mit Modell '$MODEL' durch..."
        
        # Zeitmessung für Inference beginnen
        START_TIME=$(date +%s.%N)
        
        # Führe einen einfachen Prompt aus
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c "echo 'Beantworte in einem Satz: Was ist GPU-beschleunigte Inferenz?' | ollama run $MODEL --verbose" || \
            echo "❌ Inferenztest fehlgeschlagen. Überprüfen Sie das Modell und die GPU-Konfiguration."
        
        # Zeitmessung beenden
        END_TIME=$(date +%s.%N)
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        echo "Inferenz-Dauer: $DURATION Sekunden"
    fi
fi

# Ressourcenauslastung anzeigen
echo -e "\n=== GPU-Ressourcennutzung ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

echo -e "\nGPU-Test abgeschlossen."
