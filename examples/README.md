# Beispielkonfigurationen

In diesem Verzeichnis finden Sie Beispielkonfigurationen für die manuelle Bereitstellung von Ollama mit GPU-Unterstützung und der WebUI auf der ICC.

## Ollama mit GPU

Die Datei `ollama-with-gpu.yaml` zeigt, wie Sie Ollama mit GPU-Unterstützung konfigurieren können.

```bash
# Anpassen und anwenden
kubectl apply -f ollama-with-gpu.yaml
```

## Ollama WebUI

Die Datei `ollama-webui.yaml` zeigt, wie Sie die WebUI für Ollama konfigurieren können.

```bash
# Anpassen und anwenden
kubectl apply -f ollama-webui.yaml
```

## Ingress für öffentlichen Zugriff

Die Datei `ingress-example.yaml` zeigt, wie Sie einen Ingress für den öffentlichen Zugriff konfigurieren können.

```bash
# Anpassen und anwenden
kubectl apply -f ingress-example.yaml
```

## Hinweise

- Stellen Sie sicher, dass Sie die Namespace-Angaben und Domain-Namen in den Beispieldateien an Ihre Umgebung anpassen.
- Diese Beispiele sind als Referenz gedacht. Für die automatisierte Bereitstellung verwenden Sie bitte die Skripte im Hauptverzeichnis.