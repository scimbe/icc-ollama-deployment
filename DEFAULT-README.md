# ICC Ollama Deployment

Automatisierte Bereitstellung von Ollama mit GPU-Unterstützung auf der HAW Hamburg Informatik Compute Cloud (ICC). Jetzt auch mit **RAG-Unterstützung** ohne Enterprise-Lizenzen!

## Übersicht

Dieses Repository enthält Scripts und Konfigurationsdateien, um Ollama mit GPU-Unterstützung auf der ICC der HAW Hamburg zu deployen. Zusätzlich wird ein Ollama WebUI als Benutzeroberfläche bereitgestellt. 

**NEU**: RAG-Unterstützung (Retrieval-Augmented Generation) mit lokalen Elasticsearch und Kibana Containern, ohne kostenpflichtige Enterprise-Lizenzen!

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [ICC-Zugang einrichten](#icc-zugang-einrichten)
- [Schnellstart](#schnellstart)
- [Detaillierte Anleitung](#detaillierte-anleitung)
- [GPU-Ressourcen skalieren](#gpu-ressourcen-skalieren)
- [GPU-Testen und Überwachen](#gpu-testen-und-überwachen)
- [RAG-Unterstützung](#rag-unterstützung) 👈 **NEU!**
- [Architektur](#architektur)
- [Troubleshooting](#troubleshooting)
- [Wartung](#wartung)
- [Lizenz](#lizenz)

## Voraussetzungen

- HAW Hamburg infw-Account mit Zugang zur ICC
- kubectl installiert
- Docker und Docker Compose (für RAG-Funktionalität)
- (Optional) Terraform installiert (Nur für das lokale WebUI-Deployment)
- Eine aktive VPN-Verbindung zum HAW-Netz (wenn außerhalb des HAW-Netzes)
- (Optional) Make installiert für vereinfachte Befehle

## ICC-Zugang einrichten

Bevor Sie beginnen können, müssen Sie sich bei der ICC anmelden und Ihre Kubeconfig-Datei einrichten. Dazu stellen wir ein Hilfsskript bereit:

```bash
# Öffnet den Browser mit der ICC-Login-Seite und führt Sie durch die Einrichtung
./scripts/icc-login.sh
```

Dieses Skript:
1. Öffnet die ICC-Login-Seite in Ihrem Standard-Browser
2. Führt Sie durch den Anmeldeprozess mit Ihrer infw-Kennung
3. Hilft beim Speichern und Einrichten der heruntergeladenen Kubeconfig-Datei
4. Testet die Verbindung und zeigt Ihre Namespace-Informationen an

Alternativ können Sie die [manuelle Einrichtung](DOCUMENTATION.md#1-icc-zugang-einrichten) durchführen.

## Schnellstart

```bash
# Repository klonen
git clone <repository-url>
cd icc-ollama-deployment

# ICC-Zugang einrichten (falls noch nicht geschehen)
./scripts/icc-login.sh

# Konfiguration anpassen
cp configs/config.example.sh configs/config.sh
vim configs/config.sh  # Passen Sie Ihre Namespace-Informationen an

# Ausführungsberechtigungen für Skripte setzen
./scripts/set-permissions.sh

# Deployment ausführen
./deploy.sh
```

Oder mit Make:

```bash
make deploy
```

## Detaillierte Anleitung

Eine ausführliche Schritt-für-Schritt-Anleitung finden Sie in der [DOCUMENTATION.md](DOCUMENTATION.md) Datei.

## GPU-Ressourcen skalieren

Um die Performance zu optimieren oder größere Modelle zu unterstützen, können Sie die Anzahl der GPUs dynamisch anpassen:

```bash
# Skalieren auf 2 GPUs für verbesserte Performance
./scripts/scale-gpu.sh --count 2

# Reduzieren auf 1 GPU, wenn nicht alle Ressourcen benötigt werden
./scripts/scale-gpu.sh --count 1
```

Weitere Details zur GPU-Skalierung finden Sie in der [ausführlichen Dokumentation](DOCUMENTATION.md#7-gpu-ressourcen-skalieren).

## GPU-Testen und Überwachen

Das Projekt enthält verschiedene Skripte zum Testen, Überwachen und Benchmarken der GPU-Funktionalität:

### GPU-Funktionalität testen

Überprüfen Sie, ob die GPU korrekt eingerichtet ist und von Ollama genutzt wird:

```bash
./scripts/test-gpu.sh
# oder
make gpu-test
```

### GPU-Auslastung überwachen

Überwachen Sie die GPU-Auslastung in Echtzeit:

```bash
./scripts/monitor-gpu.sh
# oder
make gpu-monitor
```

Mit Optionen für kontinuierliche Überwachung oder CSV-Export:

```bash
# 10 Messungen im 5-Sekunden-Intervall
./scripts/monitor-gpu.sh -i 5 
```

### GPU-Benchmarks durchführen

Führen Sie Leistungstests für ein spezifisches Modell durch:

```bash
./scripts/benchmark-gpu.sh llama3:8b
# oder
make gpu-bench MODEL=llama3:8b
```

## RAG-Unterstützung

Neu hinzugefügt: RAG-Unterstützung (Retrieval-Augmented Generation), die ohne Enterprise-Lizenzen auskommt!

### Was ist RAG?

RAG (Retrieval-Augmented Generation) verbindet LLMs mit externen Wissensdatenbanken. Vorteile:
- Reduzierte Halluzinationen durch Zugriff auf verifizierte Informationen
- Zugriff auf aktuellere Informationen als im Trainingskorpus
- Möglichkeit zur Quellenangabe

### Schnellstart RAG

```bash
# Bitte stellen Sie sicher, dass Ollama läuft und port-forwarding aktiv ist:
# kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434

# RAG-Infrastruktur lokal starten
./scripts/setup-rag.sh

# Test-Dokument hochladen
./scripts/upload-rag-documents.sh --direct rag/data/sample-document.md

# Öffnen Sie http://localhost:3000 im Browser
```

### RAG-Komponenten

Die RAG-Lösung besteht aus folgenden Komponenten:

1. **Elasticsearch**: Speichert und indiziert Dokumente und Embeddings
2. **Kibana**: Weboberfläche für Elasticsearch zur Datenvisualisierung
3. **RAG-Gateway**: Vermittelt zwischen WebUI, Elasticsearch und Ollama
4. **Open WebUI**: Bleibt unverändert, kommuniziert aber mit dem Gateway

Alle Komponenten außer Ollama werden als lokale Docker-Container ausgeführt:

```
┌─── Lokale Umgebung ────────────────────┐     ┌─── ICC Kubernetes Cluster ───┐
│                                         │     │                              │
│ Open WebUI → RAG Gateway → Elasticsearch│ ←→  │ Ollama (mit GPU-Support)    │
│     ↑                     ↑             │     │                              │
│     └─────────────────────┘             │     │                              │
│                 ↑                       │     │                              │
│               Kibana                    │     │                              │
│                                         │     │                              │
└─────────────────────────────────────────┘     └──────────────────────────────┘
```

### Keine Enterprise-Lizenzen erforderlich

Diese RAG-Implementierung benötigt keine kostenpflichtigen Lizenzen:

- Verwendet die kostenlose Basic-Lizenz von Elasticsearch
- Implementiert ein einfaches, eigenes Embedding-Verfahren
- Funktioniert mit allen Ollama-Modellen

Weitere Details zur RAG-Integration finden Sie in der [RAG-Dokumentation](RAG-README.md).

## Architektur

Einen Überblick über die Systemarchitektur und die Komponenten des Projekts finden Sie in der [ARCHITECTURE.md](ARCHITECTURE.md) Datei.

## Troubleshooting

### Ollama und GPU

Bei Problemen mit der GPU-Funktionalität können folgende Schritte helfen:

1. Überprüfen Sie die GPU-Kompatibilität: `make gpu-compat`
2. Testen Sie die GPU-Funktionalität: `make gpu-test`
3. Überprüfen Sie die Deployment-Konfiguration: `kubectl -n $NAMESPACE get deployment $OLLAMA_DEPLOYMENT_NAME -o yaml`
4. Prüfen Sie die Logs des Ollama-Pods: `make logs`
5. Öffnen Sie eine Shell im Pod: `make shell`

Weitere Informationen zur Fehlerbehebung finden Sie in der [DOCUMENTATION.md](DOCUMENTATION.md#8-fehlerbehebung).

### RAG-Komponenten

Bei Problemen mit der RAG-Funktionalität:

1. **WebUI verbindet nicht mit RAG-Gateway**:
   - Prüfen Sie, ob das RAG-Gateway läuft: `docker ps | grep rag-gateway`
   - Prüfen Sie die Logs: `docker logs rag-gateway`

2. **Elasticsearch startet nicht**:
   - Prüfen Sie, ob genügend Arbeitsspeicher verfügbar ist
   - Prüfen Sie die Logs: `docker logs elasticsearch`

3. **Keine Dokumente gefunden**:
   - Stellen Sie sicher, dass Sie Dokumente hochgeladen haben
   - Prüfen Sie den Elasticsearch-Index in Kibana: http://localhost:5601

## Wartung

Die automatisierten Skripte erleichtern die Wartung des Systems:

- **GPU-Komponenten**: Nutzen Sie die GPU-Test- und Monitoring-Werkzeuge für kontinuierliche Überwachung
- **RAG-Komponenten**: Die Docker-Container können einfach aktualisiert und neu gestartet werden
- **Ollama-Updates**: Aktualisieren Sie das Deployment mit dem neuesten Ollama-Image

## Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).
