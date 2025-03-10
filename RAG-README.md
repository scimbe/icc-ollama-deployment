# Ollama ICC Deployment mit RAG-Unterstützung

Dieses Repository wurde um eine lokale RAG-Unterstützung (Retrieval-Augmented Generation) erweitert, die ohne kostenpflichtige Enterprise-Lizenzen auskommt. Die RAG-Komponenten werden lokal als Docker-Container betrieben, während Ollama weiterhin in der ICC läuft.

## Was ist RAG (Retrieval-Augmented Generation)?

RAG ist eine Technik, die große Sprachmodelle (LLMs) mit einer externen Wissensdatenbank verbindet. Die wichtigsten Vorteile:

1. **Aktualität**: Das LLM kann auf Informationen zugreifen, die nach seinem Trainingszeitraum entstanden sind
2. **Spezifität**: Domänenspezifisches Wissen kann ohne Finetuning eingebunden werden
3. **Nachvollziehbarkeit**: Quellen können zu Antworten referenziert werden
4. **Weniger Halluzinationen**: Das Modell kann sich auf verifizierte Informationen stützen

## Übersicht der Architektur

Das System verwendet folgende Komponenten:

- **Ollama** in der ICC: Stellt die LLM-Inferenz mit GPU-Beschleunigung bereit
- **Lokale RAG-Infrastruktur**:
  - **Elasticsearch**: Speichert und indiziert Dokumente für Retrieval
  - **Kibana**: Web-Interface für Elasticsearch zur Datenvisualisierung
  - **RAG-Gateway**: Verbindet Open WebUI, Elasticsearch und Ollama
  - **Open WebUI**: Benutzeroberfläche für die Interaktion mit dem System

## Installation und Start

### 1. Ollama in der ICC deployen

Folgen Sie den Anweisungen im [Hauptdokument](README.md), um Ollama mit GPU-Unterstützung in der ICC zu deployen:

```bash
# Repository klonen
git clone <repository-url>
cd icc-ollama-deployment

# ICC-Zugang einrichten
./scripts/icc-login.sh

# Konfiguration anpassen
cp configs/config.example.sh configs/config.sh
vim configs/config.sh

# Deployment ausführen
./scripts/deploy-ollama.sh
```

### 2. Port-Forwarding für Ollama aktivieren

```bash
kubectl -n $NAMESPACE port-forward svc/$OLLAMA_SERVICE_NAME 11434:11434
```

### 3. RAG-Infrastruktur lokal starten

```bash
# Startet Elasticsearch, Kibana, RAG-Gateway und Open WebUI
./scripts/setup-rag.sh
```

### 4. Dokumente für RAG hochladen

```bash
# Beispiel: Text-Datei hochladen
./scripts/upload-rag-documents.sh deine_datei.txt

# Markdown-Datei hochladen
./scripts/upload-rag-documents.sh --type markdown dokumentation.md
```

### 5. Auf die WebUI zugreifen

Öffnen Sie http://localhost:3000 in Ihrem Browser und interagieren Sie mit dem System:

- Stellen Sie Fragen zum hochgeladenen Material
- Das System wird automatisch relevante Informationen aus den Dokumenten abrufen

## Zugriff auf die Komponenten

- **Ollama WebUI**: http://localhost:3000
- **RAG-Gateway API**: http://localhost:3100
- **Elasticsearch**: http://localhost:9200
- **Kibana**: http://localhost:5601

## Features

- **Modellunabhängig**: Funktioniert mit allen Ollama-kompatiblen Modellen
- **Lizenzfrei**: Keine kostenpflichtigen Enterprise-Lizenzen erforderlich
- **Einfache Installation**: Automatisierte Setup-Skripte
- **Dokument-Upload**: Einfache Werkzeuge zum Hochladen und Verwalten von Dokumenten
- **Einfache Vektorsuche**: Implementierung von Ähnlichkeitssuche ohne spezialisierte Vector Embeddings

## Architekturdiagramm

```
┌─── Lokale Umgebung ───────────────────────────┐     ┌─── ICC Kubernetes Cluster ───┐
│                                                │     │                              │
│  ┌───────────┐      ┌────────────┐             │     │                              │
│  │           │      │            │             │     │                              │
│  │ Open WebUI├─────►│ RAG Gateway├────────────────┬─►│ Ollama (mit GPU-Support)    │
│  │           │      │            │             │  │  │                              │
│  └───────────┘      └─────┬──────┘             │  │  │                              │
│                           │                    │  │  │                              │
│                           ▼                    │  │  │                              │
│                     ┌───────────┐              │  │  │                              │
│                     │           │              │  │  │                              │
│                     │Elasticsearch             │  │  │                              │
│                     │           │◄─────────────┘  │  │                              │
│                     └─────┬─────┘                 │  │                              │
│                           │                       │  │                              │
│                           ▼                       │  │                              │
│                     ┌───────────┐                 │  │                              │
│                     │           │                 │  │                              │
│                     │  Kibana   │                 │  │                              │
│                     │           │                 │  │                              │
│                     └───────────┘                 │  │                              │
│                                                   │  │                              │
└───────────────────────────────────────────────────┘  └──────────────────────────────┘
```

## Vorteile der RAG-Integration

### Ohne Enterprise-Lizenzen

Diese Implementierung verzichtet bewusst auf kostenpflichtige Komponenten:

- **Kostenfreies Embedding**: Verwendet eine einfache, eigenentwickelte Embedding-Methode statt teurer API-Dienste
- **Basic-Lizenz von Elasticsearch**: Nutzt nur Features, die in der kostenlosen Version verfügbar sind
- **Open-Source-Stack**: Alle Komponenten sind Open Source

### Flexibilität

- **Modellunabhängig**: Funktioniert mit allen LLMs, die von Ollama unterstützt werden
- **Lokale Kontrolle**: Volle Kontrolle über den RAG-Prozess und die gespeicherten Dokumente
- **Anpassbar**: Einfach zu erweitern und anzupassen für spezifische Anwendungsfälle

## Komponentendetails

### RAG-Gateway

Das RAG-Gateway ist ein Node.js-Server, der:

- Anfragen von der WebUI empfängt
- Relevante Dokumente aus Elasticsearch abruft
- Diese Dokumente in den Prompt einfügt
- Den erweiterten Prompt an Ollama sendet
- Die generierte Antwort zurück an die WebUI weiterleitet

### Elasticsearch & Kibana

- **Elasticsearch**: Speichert und indiziert Dokumente für schnellen Zugriff
- **Kibana**: Bietet eine Benutzeroberfläche zur Verwaltung und Visualisierung von Elasticsearch-Daten

### Open WebUI

Die Open WebUI wird so konfiguriert, dass sie mit dem RAG-Gateway kommuniziert, anstatt direkt mit Ollama. Die Benutzeroberfläche und der Funktionsumfang bleiben unverändert.

## Verwendung im Detail

### Dokumente hochladen

Dokumente können über das Befehlszeilenskript `upload-rag-documents.sh` hochgeladen werden:

```bash
# Einzeldokument hochladen
./scripts/upload-rag-documents.sh pfad/zur/datei.txt

# Mit Optionen
./scripts/upload-rag-documents.sh --type markdown --split true --chunk-size 500 pfad/zur/datei.md
```

### Mögliche Erweiterungen

- **Bessere Embeddings**: Integration kostenloser, lokaler Embedding-Modelle
- **Dokumentenverarbeitung**: Verbesserte Extraktion aus komplexen Formaten (PDF, Word, etc.)
- **Automatische Quellenangaben**: Automatisches Hinzufügen von Quellenverweisen zu Antworten
- **Feedback-Schleife**: Benutzer-Feedback zum Verbessern der Relevanz von Retrieval

## Bekannte Einschränkungen

- Die selbstimplementierte Embedding-Methode ist nicht so leistungsfähig wie spezialisierte ML-Modelle
- Große Dokumente müssen in Chunks aufgeteilt werden, um in das Kontextfenster von Ollama zu passen
- Die Skalierbarkeit ist durch die lokalen Ressourcen begrenzt

## Hilfsskripte

- `setup-rag.sh`: Startet die gesamte RAG-Infrastruktur
- `stop-rag.sh`: Stoppt alle RAG-Komponenten
- `upload-rag-documents.sh`: Lädt Dokumente in Elasticsearch hoch

## Fehlerbehebung

### Häufige Probleme

1. **Verbindung zu Ollama fehlgeschlagen**
   - Überprüfen Sie, ob das Port-Forwarding für Ollama aktiv ist
   - Prüfen Sie, ob Ollama im ICC-Cluster läuft

2. **Elasticsearch startet nicht**
   - Stellen Sie sicher, dass Sie genügend RAM haben (mindestens 4 GB frei)
   - Prüfen Sie die Logs: `docker logs elasticsearch`

3. **Keine relevanten Dokumente gefunden**
   - Stellen Sie sicher, dass Sie Dokumente hochgeladen haben
   - Prüfen Sie die Elasticsearch-Indizes in Kibana

## Zukünftige Erweiterungen

- Integration lokaler Embedding-Modelle für verbesserte Ähnlichkeitssuche
- Verbesserte Dokumentenprozessierung für komplexere Dateiformate
- Web-Interface für Dokumentenverwaltung
- Direkte Elasticsearch-Integration in der ICC (optional)
