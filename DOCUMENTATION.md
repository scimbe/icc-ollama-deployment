# Ausführliche Dokumentation: ICC Ollama Deployment

Diese Dokumentation führt Sie durch den gesamten Prozess der Einrichtung und Bereitstellung von Ollama mit GPU-Unterstützung auf der Informatik Compute Cloud (ICC) der HAW Hamburg.

## Inhaltsverzeichnis

1. [ICC-Zugang einrichten](#1-icc-zugang-einrichten)
2. [Repository klonen und konfigurieren](#2-repository-klonen-und-konfigurieren)
3. [Ollama mit GPU-Unterstützung deployen](#3-ollama-mit-gpu-unterstützung-deployen)
4. [Open WebUI für Ollama einrichten](#4-open-webui-für-ollama-einrichten)
5. [Modelle herunterladen und verwenden](#5-modelle-herunterladen-und-verwenden)
6. [Auf den Dienst zugreifen](#6-auf-den-dienst-zugreifen)
7. [Fehlerbehebung](#7-fehlerbehebung)
8. [Ressourcen bereinigen](#8-ressourcen-bereinigen)

## 1. ICC-Zugang einrichten

### Automatische Einrichtung (empfohlen)

Der einfachste Weg, um die ICC-Zugang einzurichten, ist unser Hilfsskript zu verwenden:

```bash
./scripts/icc-login.sh
```

Dieses Skript führt Sie durch den gesamten Prozess:
1. Öffnet die ICC-Login-Seite in Ihrem Standard-Browser
2. Führt Sie durch den Anmeldeprozess mit Ihrer infw-Kennung
3. Hilft beim Speichern und Einrichten der heruntergeladenen Kubeconfig-Datei
4. Testet die Verbindung und zeigt Ihre Namespace-Informationen an

### Manuelle Einrichtung

Falls Sie die manuelle Einrichtung bevorzugen:

1. Besuchen Sie das Anmeldeportal der ICC unter https://icc-login.informatik.haw-hamburg.de/
2. Authentifizieren Sie sich mit Ihrer infw-Kennung
3. Laden Sie die generierte Kubeconfig-Datei herunter
4. Platzieren Sie die Kubeconfig-Datei in Ihrem `~/.kube/` Verzeichnis oder setzen Sie die Umgebungsvariable `KUBECONFIG`

```bash
# Linux/macOS
mkdir -p ~/.kube
mv /pfad/zur/heruntergeladenen/config.txt ~/.kube/config

# Oder als Umgebungsvariable
export KUBECONFIG=/pfad/zur/heruntergeladenen/config.txt
```

### Überprüfen Sie Ihren Namespace

Die ICC erstellt automatisch einen Namespace basierend auf Ihrer w-Kennung (wenn Sie sich mit infwXYZ123 anmelden, ist Ihr Namespace wXYZ123-default).

```bash
kubectl get subns
```

## 2. Repository klonen und konfigurieren

```bash
# Repository klonen
git clone <repository-url>
cd icc-ollama-deployment

# Konfigurationsdatei erstellen
cp configs/config.example.sh configs/config.sh
```

Öffnen Sie `configs/config.sh` und passen Sie die Variablen an Ihre Umgebung an:

```bash
# Beispielkonfiguration
NAMESPACE="wXYZ123-default"  # Ersetzen Sie dies mit Ihrem Namespace
OLLAMA_DEPLOYMENT_NAME="my-ollama"
OLLAMA_SERVICE_NAME="my-ollama"
WEBUI_DEPLOYMENT_NAME="ollama-webui"
WEBUI_SERVICE_NAME="ollama-webui"
USE_GPU=true  # Auf false setzen, wenn keine GPU benötigt wird
GPU_TYPE="gpu-tesla-v100"  # Oder "gpu-tesla-v100s" je nach Verfügbarkeit
```

## 3. Ollama mit GPU-Unterstützung deployen

Nachdem Sie Ihre Konfiguration angepasst haben, können Sie das Deployment starten:

```bash
./scripts/deploy-ollama.sh
```

Dieser Befehl:
1. Erstellt das Kubernetes Deployment mit GPU-Unterstützung
2. Erstellt einen Kubernetes Service für den Zugriff auf Ollama
3. Wartet, bis die Pods erfolgreich gestartet sind

## 4. Open WebUI für Ollama einrichten

Sie haben zwei Möglichkeiten, die WebUI zu deployen:

### Option 1: Mit Kubernetes (empfohlen für ICC)

```bash
./scripts/deploy-webui-k8s.sh
```

### Option 2: Mit Terraform (für lokale Entwicklung)

```bash
cd terraform
terraform init
terraform apply
```

## 5. Modelle herunterladen und verwenden

**WICHTIG: Die WebUI funktioniert erst, nachdem mindestens ein Modell geladen wurde!** Wenn Sie versuchen, auf die WebUI zuzugreifen, bevor ein Modell geladen ist, werden Sie möglicherweise Verbindungsfehler erhalten.

Nachdem Ollama läuft, laden Sie ein Modell wie folgt:

```bash
# Mit unserem Hilfsskript (empfohlen)
./scripts/pull-model.sh llama3:8b
```

Andere beliebte Modelle, die Sie laden könnten:
- `./scripts/pull-model.sh gemma:2b` (kleines Modell, gut für Tests)
- `./scripts/pull-model.sh phi3:mini` (kompaktes Modell)
- `./scripts/pull-model.sh mistral:7b-instruct-v0.2` (gutes Allzweckmodell)

Sie können ein Modell auch manuell herunterladen, wenn Sie bereits Port-Forwarding aktiviert haben:

```bash
# Stellen Sie zuerst sicher, dass Port-Forwarding aktiv ist
kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434

# In einem anderen Terminal
curl -X POST http://localhost:11434/api/pull -d '{"name":"llama3:8b"}'
```

## 6. Auf den Dienst zugreifen

### Innerhalb des HAW-Netzes

Nachdem Sie mindestens ein Modell geladen haben, können Sie auf die Dienste zugreifen:

```bash
# Für Ollama API und WebUI gleichzeitig (empfohlen)
./scripts/port-forward.sh

# Oder manuell für einzelne Dienste
kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434
kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 8080:8080
```

Anschließend können Sie die WebUI unter http://localhost:8080 in Ihrem Browser öffnen.

### Ingress für öffentlichen Zugriff einrichten

Wenn Sie Ihren Dienst öffentlich zugänglich machen möchten, folgen Sie der Anleitung in `scripts/create-ingress.sh`. Denken Sie daran, dass Sie ein Impressum und eine Datenschutzerklärung benötigen oder einen passwortgeschützten Zugang einrichten müssen.

## 7. Fehlerbehebung

### "Connection refused" Fehler bei der WebUI

Wenn Sie beim Zugriff auf die WebUI Fehler wie "connection refused" erhalten, überprüfen Sie:
1. Ist mindestens ein Modell geladen? Die WebUI funktioniert erst, nachdem ein Modell geladen wurde.
2. Führen Sie `./scripts/pull-model.sh llama3:8b` aus und versuchen Sie es erneut.

### GPU-Funktionalität testen

```bash
./scripts/test-gpu.sh
```

### Überprüfen des Pod-Status

```bash
kubectl -n $NAMESPACE get pods
```

### Pod-Logs anzeigen

```bash
kubectl -n $NAMESPACE logs <pod-name>
```

### Interaktive Shell im Container

```bash
kubectl -n $NAMESPACE exec -it <pod-name> -- /bin/bash
```

## 8. Ressourcen bereinigen

Wenn Sie die Deployment entfernen möchten:

```bash
./scripts/cleanup.sh
```

Oder einzelne Komponenten:

```bash
kubectl -n $NAMESPACE delete deployment $OLLAMA_DEPLOYMENT_NAME
kubectl -n $NAMESPACE delete service $OLLAMA_SERVICE_NAME
```

Denken Sie daran, dass nach 90 Tagen Inaktivität die ICC automatisch Ihre Ressourcen bereinigt.
