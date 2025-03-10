# Ausführliche Dokumentation: ICC Ollama Deployment

Diese Dokumentation führt Sie durch den gesamten Prozess der Einrichtung und Bereitstellung von Ollama mit GPU-Unterstützung auf der Informatik Compute Cloud (ICC) der HAW Hamburg.

## Inhaltsverzeichnis

1. [ICC-Zugang einrichten](#1-icc-zugang-einrichten)
2. [Repository klonen und konfigurieren](#2-repository-klonen-und-konfigurieren)
3. [Ollama mit GPU-Unterstützung deployen](#3-ollama-mit-gpu-unterstützung-deployen)
4. [Open WebUI für Ollama einrichten](#4-open-webui-für-ollama-einrichten)
5. [Modelle herunterladen und verwenden](#5-modelle-herunterladen-und-verwenden)
6. [Auf den Dienst zugreifen](#6-auf-den-dienst-zugreifen)
7. [GPU-Ressourcen skalieren](#7-gpu-ressourcen-skalieren)
8. [GPU-Testen und Überwachen](#8-gpu-testen-und-überwachen)
9. [Fehlerbehebung](#9-fehlerbehebung)
10. [Ressourcen bereinigen](#10-ressourcen-bereinigen)

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
mv /pfad/zur/heruntergeladenen/config.txt ~/.kube/conf # bei mir funktioniert conf -> ich habe andere Anleitungen mit config gesehen

# Oder als Umgebungsvariable
export KUBECONFIG=/pfad/zur/heruntergeladenen/conf
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
GPU_COUNT=1  # Anzahl der GPUs (üblicherweise 1, kann bis zu 4 sein)
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

### Option 2: Mit Terraform (für lokale Webui, braucht docker)

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

### Ingress für öffentlichen Zugriff einrichten (TODO TEST)

Wenn Sie Ihren Dienst öffentlich zugänglich machen möchten, folgen Sie der Anleitung in `scripts/create-ingress.sh`. Denken Sie daran, dass Sie ein Impressum und eine Datenschutzerklärung benötigen oder einen passwortgeschützten Zugang einrichten müssen.

## 7. GPU-Ressourcen skalieren

Je nach Anforderung Ihrer Anwendung können Sie die Anzahl der verwendeten GPUs für das Ollama-Deployment dynamisch anpassen. Dies ist besonders nützlich für:

- Verarbeitung größerer Modelle, die mehr GPU-Speicher benötigen
- Verbesserte Inferenzgeschwindigkeit durch parallele Verarbeitung
- Freigabe von Ressourcen, wenn sie nicht benötigt werden
- Teilen von GPU-Ressourcen mit anderen Nutzern auf der ICC

### GPU-Anzahl anpassen

Verwenden Sie das Skalierungsskript, um die Anzahl der GPUs anzupassen:

```bash
# Skalieren auf 2 GPUs
./scripts/scale-gpu.sh --count 2

# Zurück auf 1 GPU reduzieren
./scripts/scale-gpu.sh --count 1
```

Das Skript führt folgende Aktionen aus:
1. Zeigt die aktuelle GPU-Konfiguration an
2. Validiert die angeforderte GPU-Anzahl (1-4, abhängig von der Verfügbarkeit)
3. Patcht das Deployment, um die neue GPU-Anzahl zu verwenden
4. Wartet auf den erfolgreichen Abschluss des Rollouts

### Wichtige Hinweise zur GPU-Skalierung

- Die maximale Anzahl von GPUs ist durch die ICC-Ressourcenbeschränkungen und die Verfügbarkeit limitiert
- Größere Modelle (z.B. llama3:70b) können mehr als eine GPU erfordern
- Die Skalierung führt zu einem Neustart des Ollama-Pods, was kurzzeitige Ausfallzeiten verursachen kann
- Änderungen durch `scale-gpu.sh` sind temporär und werden bei einem erneuten Deployment auf die Werte aus der `config.sh` zurückgesetzt
- Für permanente Änderungen sollten Sie den `GPU_COUNT`-Wert in Ihrer `configs/config.sh` aktualisieren

## 8. GPU-Testen und Überwachen

Das Projekt bietet mehrere Skripte für Tests, Überwachung und Benchmarking der GPU-Funktionalität.

### GPU-Funktionalität testen

Der grundlegendste Test, um sicherzustellen, dass Ihre GPU korrekt konfiguriert ist:

```bash
./scripts/test-gpu.sh
# oder mit Make
make gpu-test
```

Dieses Skript führt folgende Tests durch:
- Prüft die NVIDIA GPU-Verfügbarkeit mit `nvidia-smi`
- Überprüft CUDA-Umgebungsvariablen
- Listet verfügbare Modelle auf
- Testet die Ollama API
- Bietet einen optionalen Inferenztest mit einem ausgewählten Modell

### GPU-Kompatibilität prüfen

Für eine detaillierte Analyse der GPU-Konfiguration:

```bash
./scripts/check-gpu-compatibility.sh
# oder mit Make
make gpu-compat
```

Dieses Skript prüft:
- Kubernetes-Konfiguration (Ressourcenlimits und Tolerations)
- NVIDIA-Treiber und CUDA-Version
- GPU-Hardware-Informationen (Modell, Speicher, Compute-Capability)
- CUDA-Bibliotheken
- Ollama API-Funktionalität

### GPU-Leistung messen

Benchmarks für eine detaillierte Leistungsanalyse:

```bash
# Standard-Benchmark mit dem ersten verfügbaren Modell
./scripts/benchmark-gpu.sh

# Benchmark für ein bestimmtes Modell
./scripts/benchmark-gpu.sh llama3:8b
# oder mit Make
make gpu-bench MODEL=llama3:8b

# Angepasster Benchmark
./scripts/benchmark-gpu.sh -m llama3:8b -i 5 -p "Erkläre Quantencomputing" -t 200
```

Der Benchmark liefert:
- Token-Generierungsraten
- Inferenz-Dauer
- GPU-Auslastung während der Inferenz
- Speichernutzung

### GPU-Ressourcen überwachen

Überwachen Sie Ihre GPU-Nutzung in Echtzeit:

```bash
./scripts/monitor-gpu.sh
# oder mit Make
make gpu-monitor
```

Die Überwachung kann angepasst werden:
```bash
# 10 Messungen im 5-Sekunden-Intervall mit kompakter Ausgabe
./scripts/monitor-gpu.sh -i 5 
```

### Ollama API-Client für Tests

Für direkte Inferenz-Tests und API-Interaktionen:

```bash
# Liste aller Modelle anzeigen
./scripts/ollama-api-client.sh list

# Einfachen Inferenz-Test durchführen
./scripts/ollama-api-client.sh test llama3:8b

# Performance-Benchmark
./scripts/ollama-api-client.sh benchmark llama3:8b

# Anzeigen der aktuellen GPU-Statistiken
./scripts/ollama-api-client.sh gpu-stats
```

## 9. Fehlerbehebung

### "Connection refused" Fehler bei der WebUI

Wenn Sie beim Zugriff auf die WebUI Fehler wie "connection refused" erhalten, überprüfen Sie:
1. Ist mindestens ein Modell geladen? Die WebUI funktioniert erst, nachdem ein Modell geladen wurde.
2. Führen Sie `./scripts/pull-model.sh llama3:8b` aus und versuchen Sie es erneut.

### GPU-Probleme diagnostizieren

Führen Sie folgende Schritte aus, um GPU-Probleme zu diagnostizieren:

1. Überprüfen Sie die GPU-Kompatibilität:
   ```bash
   ./scripts/check-gpu-compatibility.sh
   ```

2. Testen Sie die grundlegende GPU-Funktionalität:
   ```bash
   ./scripts/test-gpu.sh
   ```

3. Überprüfen Sie die Deployment-Konfiguration:
   ```bash
   kubectl -n $NAMESPACE get deployment $OLLAMA_DEPLOYMENT_NAME -o yaml | grep -A 10 resources
   ```

4. Prüfen Sie die Pod-Logs auf Fehler:
   ```bash
   kubectl -n $NAMESPACE logs $POD_NAME
   ```

5. Überprüfen Sie die CUDA-Konfiguration im Container:
   ```bash
   kubectl -n $NAMESPACE exec -it $POD_NAME -- bash -c 'echo $LD_LIBRARY_PATH'
   kubectl -n $NAMESPACE exec -it $POD_NAME -- nvidia-smi
   ```

### Modell- und API-Probleme

Bei Problemen mit Modellen oder der API:

1. Überprüfen Sie, ob die API funktioniert:
   ```bash
   ./scripts/ollama-api-client.sh api-health
   ```

2. Prüfen Sie, ob Modelle verfügbar sind:
   ```bash
   ./scripts/ollama-api-client.sh list
   ```

3. Versuchen Sie, ein kleines Modell zu laden und zu testen:
   ```bash
   ./scripts/pull-model.sh gemma:2b
   ./scripts/ollama-api-client.sh test gemma:2b
   ```

### Weitere Diagnostik

```bash
# Überprüfen des Pod-Status
kubectl -n $NAMESPACE get pods

# Pod-Logs anzeigen
kubectl -n $NAMESPACE logs <pod-name>

# Interaktive Shell im Container
kubectl -n $NAMESPACE exec -it <pod-name> -- /bin/bash
```

## 10. Ressourcen bereinigen

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
