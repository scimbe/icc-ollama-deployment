# RAG-Integration für Ollama ICC Deployment

Dieses Dokument beschreibt die RAG-Integration (Retrieval-Augmented Generation) für das Ollama ICC Deployment, die ohne Enterprise-Lizenzen auskommt und mit allen LLM-Modellen funktioniert.

## Übersicht

Die RAG-Integration erweitert Ollama um Retrieval-Augmented Generation (RAG) mittels eines lokalen Elasticsearch-Setups. Das System besteht aus:

1. **RAG-Gateway**: Ein NodeJS-Server, der Anfragen zwischen der Open WebUI und Ollama vermittelt und dabei relevante Informationen aus Elasticsearch abruft.

2. **Elasticsearch**: Lokaler Elasticsearch-Server zur Speicherung und Indizierung von Dokumenten.

3. **Kibana**: Web-Interface für Elasticsearch zur Visualisierung und Verwaltung der Daten.

4. **Open WebUI**: Die bestehende Web-Benutzeroberfläche, die nun mit dem RAG-Gateway statt direkt mit Ollama kommuniziert.

Diese Lösung kommt bewusst ohne lizenzpflichtige Enterprise-Features aus, indem sie:
- Statt kostenpflichtiger Embedding-Modelle ein einfaches, eigenentwickeltes Embedding-Verfahren nutzt
- Die Community-Version von Elasticsearch verwendet
- Alle Komponenten als Open-Source-Software implementiert

## Architektur

Die Architektur kombiniert lokale Docker-Container für die RAG-Komponenten mit dem bestehenden Ollama-Deployment in der ICC:

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

## Komponenten im Detail

### 1. RAG-Gateway

Das RAG-Gateway ist ein NodeJS-basierter Server, der:

- Zwischen Open WebUI und Ollama vermittelt
- Elasticsearch abfragt, um relevante Dokumente für Anfragen zu finden
- Diese Dokumente in den Prompt einfügt, bevor er an Ollama gesendet wird
- Die Antworten von Ollama zurück an die WebUI sendet
- Neue Anfragen und Antworten in Elasticsearch speichert, um die Wissensbasis zu erweitern

Der Gateway nutzt ein einfaches, eigenentwickeltes Embedding-Verfahren, um Texte in Vektoren zu transformieren, ohne kostenpflichtige Embedding-APIs zu benötigen.

### 2. Elasticsearch & Kibana

Elasticsearch dient als Vektordatenbank und Textspeicher. Es ist konfiguriert, ohne kostenpflichtige Features auszukommen:

- Nutzt die kostenlose Basic-Lizenz von Elasticsearch
- Verzichtet auf Enterprise-Features wie Machine Learning
- Verwendet das kostenlose dense_vector-Feld für Vektorspeicherung
- Führt Ähnlichkeitssuche mit einfacher Kosinus-Ähnlichkeit durch

Kibana dient zur Administration und Visualisierung der gespeicherten Daten.

### 3. Integration mit Ollama in der ICC

Die Verbindung zu Ollama in der ICC erfolgt über Port-Forwarding:

- Das RAG-Gateway verbindet sich mit dem lokal verfügbaren Port-Forward von Ollama
- Alle LLM-Modelle, die in Ollama verfügbar sind, können ohne Änderungen genutzt werden
- Die bestehende GPU-Beschleunigung in der ICC wird weiterhin genutzt

## Setup und Verwendung

### Voraussetzungen

- Laufendes Ollama-Deployment in der ICC mit aktivem Port-Forwarding
- Docker und Docker Compose auf dem lokalen System
- Node.js (für Entwicklung, nicht für Ausführung erforderlich)

### Installation und Start

1. **RAG-Umgebung starten**:
   ```bash
   ./scripts/setup-rag.sh
   ```
   Dieses Skript startet Elasticsearch, Kibana, das RAG-Gateway und die Open WebUI.

2. **Dokumente für RAG hochladen**:
   ```bash
   ./scripts/upload-rag-documents.sh --direct pfad/zur/datei.txt
   ```
   Dieses Skript lädt Dokumente in Elasticsearch hoch, die dann für RAG verwendet werden.

3. **WebUI verwenden**:
   Öffnen Sie die WebUI unter http://localhost:3000 und interagieren Sie mit Ollama wie gewohnt.
   RAG wird automatisch im Hintergrund angewendet, wenn relevante Dokumente gefunden werden.

4. **RAG-Umgebung stoppen**:
   ```bash
   ./scripts/stop-rag.sh
   ```

## Entwicklung und Anpassung

### Eigene Dokumente hinzufügen

Nutzen Sie das Skript `upload-rag-documents.sh`, um eigene Dokumente hochzuladen:

```bash
./scripts/upload-rag-documents.sh --direct --type markdown meine_doku.md
```

Unterstützte Dokumenttypen:
- `text`: Einfache Textdateien
- `markdown`: Markdown-Dokumente
- `pdf`: PDF-Dateien (Textextraktion erfolgt automatisch)

### Einstellungen anpassen

Die Konfiguration kann über Umgebungsvariablen im `.env`-File angepasst werden:

- `OLLAMA_BASE_URL`: URL zu Ollama (Standard: http://localhost:11434)
- `ELASTICSEARCH_URL`: URL zu Elasticsearch (Standard: http://elasticsearch:9200)
- `ELASTICSEARCH_INDEX`: Index-Name für RAG-Dokumente (Standard: ollama-rag)

## Limitierungen

- Die selbstimplementierte Embedding-Methode ist nicht so leistungsfähig wie spezialisierte ML-Modelle
- Die Vektor-Ähnlichkeitssuche ist optimiert für kurze bis mittellange Texte
- Sehr lange Dokumente müssen in Chunks aufgeteilt werden, um innerhalb des Kontextfensters von Ollama zu passen
- Es gibt kein automatisches Embedding-Update bei Modelländerungen

## Vergleich mit Enterprise-Lösungen

| Feature               | Diese Lösung                        | Enterprise-Lösung             |
|-----------------------|-------------------------------------|-------------------------------|
| Embedding-Modelle     | Einfache Wortstatistik-Methode      | ML-basiert (OpenAI, HuggingFace) |
| Vektorsuche           | Einfache Kosinus-Ähnlichkeit        | Hybrid mit KNN, ANN, HNSW     |
| Lizenzkosten          | Keine (vollständig Open Source)     | Kostenpflichtige Lizenzen     |
| Rechenressourcen      | Minimal (läuft auf lokalem System)  | Höhere Anforderungen          |
| Integration           | Docker Compose                      | Kubernetes mit Helm           |
| Skalierbarkeit        | Beschränkt auf lokale Ressourcen    | Horizontal skalierbar         |

## Fehlersuche

- **WebUI zeigt keine Verbindung**: Stellen Sie sicher, dass Port-Forwarding für Ollama aktiv ist.
- **RAG-Gateway startet nicht**: Prüfen Sie die Logs mit `docker logs rag-gateway`.
- **Keine RAG-Ergebnisse**: Laden Sie Dokumente mit `upload-rag-documents.sh` hoch und prüfen Sie Elasticsearch.
