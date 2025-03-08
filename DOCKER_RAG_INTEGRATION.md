# Ollama-Elasticsearch-Integration mit Docker und Terraform

Diese Dokumentation beschreibt, wie die Integration zwischen Ollama und Elasticsearch mittels Docker und Terraform implementiert wurde.

## Übersicht

Die Integration besteht aus einem Docker-Container, der ein Node.js-Skript ausführt, welches:

1. Anfragen an Ollama sendet
2. Die Antworten in Elasticsearch speichert
3. Bei Bedarf RAG (Retrieval-Augmented Generation) durchführt

Das gesamte Setup wird über Terraform verwaltet, sodass es einfach bereitgestellt und aktualisiert werden kann.

## Komponenten

### 1. Terraform-Modul

- **Pfad**: `terraform/modules/ollama_elastic_integration/`
- **Hauptdateien**:
  - `main.tf`: Definiert Docker-Container und Netzwerk
  - `variables.tf`: Definiert konfigurierbare Parameter
  - `outputs.tf`: Definiert Ausgaben des Moduls

### 2. Node.js-Anwendung

- **Pfad**: `terraform/modules/ollama_elastic_integration/files/`
- **Hauptdateien**:
  - `ollama-elastic-integration.js`: Implementiert die Integration
  - `package.json`: Definiert Abhängigkeiten und Metadaten

## Konfigurationsoptionen

Das Terraform-Modul bietet folgende Konfigurationsoptionen:

| Parameter | Beschreibung | Standard |
|-----------|--------------|----------|
| `elasticsearch_host` | Hostname oder IP-Adresse des Elasticsearch-Servers | `elasticsearch` |
| `ollama_host` | Hostname oder IP-Adresse des Ollama-Servers | `ollama` |
| `model_name` | Name des zu verwendenden LLM-Modells | `llama3` |
| `index_name` | Name des Elasticsearch-Index | `ollama-responses` |
| `data_path` | Pfad für persistente Daten | `/tmp/ollama-elastic-integration-data` |
| `network_name` | Name des Docker-Netzwerks | `ollama-network` |
| `create_network` | Ob ein neues Netzwerk erstellt werden soll | `true` |

## Bereitstellung

### Voraussetzungen

- Docker installiert und ausgeführt
- Terraform installiert (Version >= 1.0.0)
- Laufende Ollama- und Elasticsearch-Instanzen (lokal oder remote)

### Schritte zur Bereitstellung

1. **Einrichten der Terraform-Infrastruktur**

   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Überprüfen der Bereitstellung**

   ```bash
   docker ps | grep ollama-elastic-integration
   ```

3. **Zugriff auf die Logs**

   ```bash
   docker logs -f ollama-elastic-integration
   ```

### Konfiguration anpassen

Um die Konfiguration anzupassen, bearbeiten Sie die Datei `terraform/ollama_elastic_integration.tf` und passen Sie die Parameter an Ihre Umgebung an.

## Funktionsweise

1. Nach dem Start wird der Container:
   - Node.js-Abhängigkeiten installieren
   - Eine Verbindung zu Elasticsearch herstellen
   - Eine Beispielanfrage an Ollama senden
   - Die Antwort in Elasticsearch speichern
   - Periodisch (alle 5 Minuten) neue Anfragen senden

2. Die Integration unterstützt RAG:
   - Sucht nach relevanten früheren Antworten
   - Fügt diese als Kontext zur neuen Anfrage hinzu
   - Verbessert dadurch die Qualität der Antworten

## Zugriff auf gespeicherte Daten

Die gespeicherten Antworten können über Kibana angezeigt werden:

1. Öffnen Sie Kibana
2. Gehen Sie zu "Stack Management" > "Index Patterns"
3. Erstellen Sie ein Index Pattern für `ollama-responses*`
4. Verwenden Sie die Discover-Funktion, um die Daten anzuzeigen

## Problembehebung

### Der Container startet nicht

Überprüfen Sie:
- Ob Docker läuft
- Ob die Netzwerkkonfiguration korrekt ist
- Ob die Pfade in den Terraform-Dateien korrekt sind

### Keine Verbindung zu Elasticsearch oder Ollama

Überprüfen Sie:
- Ob Elasticsearch und Ollama laufen
- Ob die Host-Parameter korrekt konfiguriert sind
- Ob die Netzwerkkonfiguration den Zugriff erlaubt

### Fehler im Skript

Überprüfen Sie die Container-Logs:
```bash
docker logs ollama-elastic-integration
```

## Wartung und Aktualisierung

Um das System zu aktualisieren:

1. Ändern Sie die Dateien nach Bedarf
2. Führen Sie `terraform apply` aus, um die Änderungen anzuwenden

Um das System zu entfernen:

```bash
terraform destroy
```
