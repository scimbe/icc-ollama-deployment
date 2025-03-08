# Kibana-RAG für Ollama auf ICC

Diese Erweiterung integriert Kibana mit Elasticsearch und Ollama, um Retrieval-Augmented Generation (RAG) auf der Informatik Compute Cloud (ICC) zu ermöglichen.

## Funktionsweise

Die Integration ermöglicht:
1. Bereitstellung von Elasticsearch für Vektoreinbettungen
2. Bereitstellung von Kibana als Frontend
3. Anbindung an Ollama für lokale LLM-Inferenz
4. Nutzung des Kibana Playgrounds für RAG-Anwendungen

## Voraussetzungen

- Funktionierendes Ollama-Deployment auf der ICC
- Mindestens ein geladenes Modell in Ollama (z.B. `llama3:8b`)
- Genügend Ressourcen für Elasticsearch und Kibana

## Schnellstart

```bash
# Elasticsearch bereitstellen
./kibana/deploy-elasticsearch.sh

# Kibana bereitstellen
./kibana/deploy-kibana.sh

# Anweisungen zum Einrichten des Ollama-Connectors befolgen
./kibana/setup-connector.sh

# Optional: Beispieldaten laden
./kibana/load-example-data.sh
```

## Zugriff auf Kibana

Nutzen Sie Port-Forwarding für den Zugriff auf Kibana:

```bash
kubectl -n NAMESPACE port-forward svc/my-kibana 5601:5601
```

Öffnen Sie dann http://localhost:5601 in Ihrem Browser.

## Einen RAG-Workflow erstellen

1. Elasticsearch > Playground öffnen
2. Datenquelle auswählen oder hinzufügen
3. Ollama-Connector auswählen
4. System-Prompt anpassen
5. Fragen stellen, die aus den Dokumenten beantwortet werden sollen

## Beispielabfragen für die Demo-Daten

- "Wer ist die Hauptfigur in der Geschichte?"
- "Was passierte mit dem weißen Kaninchen?"
- "Beschreibe den Kaninchenbau."

## Fehlerbehebung

Wenn Sie Probleme mit dem Connector haben:
- Stellen Sie sicher, dass Ollama läuft
- Prüfen Sie, ob mindestens ein LLM geladen ist
- Überprüfen Sie die URL des Connectors
- Testen Sie die API direkt: `curl -X POST http://localhost:11434/v1/chat/completions`
