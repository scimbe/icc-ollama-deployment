# Ausführliche Dokumentation: ICC Ollama Deployment

Diese Dokumentation führt Sie durch den gesamten Prozess der Einrichtung und Bereitstellung von Ollama mit GPU-Unterstützung auf der Informatik Compute Cloud (ICC) der HAW Hamburg.

## Inhaltsverzeichnis

1. [ICC-Zugang einrichten](#1-icc-zugang-einrichten)
2. [Repository klonen und konfigurieren](#2-repository-klonen-und-konfigurieren)
3. [Ollama mit GPU-Unterstützung deployen](#3-ollama-mit-gpu-unterstützung-deployen)
4. [Open WebUI für Ollama einrichten](#4-open-webui-für-ollama-einrichten)
5. [Auf den Dienst zugreifen](#5-auf-den-dienst-zugreifen)
6. [Modelle herunterladen und verwenden](#6-modelle-herunterladen-und-verwenden)
7. [Fehlerbehebung](#7-fehlerbehebung)
8. [Ressourcen bereinigen](#8-ressourcen-bereinigen)

## 1. ICC-Zugang einrichten

### Login und Kubeconfig erhalten

1. Besuchen Sie das Anmeldeportal der ICC und authentifizieren Sie sich mit Ihrer infw-Kennung.
2. Laden Sie die generierte Kubeconfig-Datei herunter.
3. Platzieren Sie die Kubeconfig-Datei in Ihrem `~/.kube/` Verzeichnis oder setzen Sie die Umgebungsvariable `KUBECONFIG`.

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

## 5. Auf den Dienst zugreifen

### Innerhalb des HAW-Netzes

Um auf Ihren Dienst zuzugreifen, können Sie Port-Forwarding nutzen:

```bash
# Für Ollama API
kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434

# Für WebUI (wenn in Kubernetes deployed)
kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 8080:8080
```

### Ingress für öffentlichen Zugriff einrichten

Wenn Sie Ihren Dienst öffentlich zugänglich machen möchten, folgen Sie der Anleitung in `scripts/create-ingress.sh`. Denken Sie daran, dass Sie ein Impressum und eine Datenschutzerklärung benötigen oder einen passwortgeschützten Zugang einrichten müssen.

## 6. Modelle herunterladen und verwenden

Nachdem Ollama läuft, können Sie Modelle herunterladen:

```bash
# Stellen Sie sicher, dass Port-Forwarding aktiv ist
kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434

# In einem anderen Terminal
curl -X POST http://localhost:11434/api/pull -d '{"name":"llama3:8b"}'  # Für llama3 8B Modell
```

Oder über die WebUI, falls Sie diese installiert haben.

## 7. Fehlerbehebung

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

### GPU-Status überprüfen

```bash
kubectl -n $NAMESPACE exec -it <pod-name> -- nvidia-smi
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
