# LLM-Modelle und RAG: Grundlagen und Anwendungen

## Einführung zu Large Language Models

Large Language Models (LLMs) sind komplexe KI-Systeme, die auf großen Textkorpora trainiert wurden, um natürliche Sprache zu verstehen und zu generieren. Diese Modelle basieren auf Transformer-Architekturen und nutzen Self-Attention-Mechanismen, um Zusammenhänge zwischen Wörtern und Phrasen zu erfassen.

Moderne LLMs wie Llama, Mistral und andere Open-Source-Modelle, die mit Ollama genutzt werden können, zeigen beeindruckende Fähigkeiten in verschiedenen Aufgaben:

- Textgenerierung und Fortsetzung
- Frage-Antwort-Systeme
- Zusammenfassungen
- Übersetzungen
- Code-Generierung
- Kreatives Schreiben

Trotz ihrer Stärken haben LLMs einige grundlegende Einschränkungen:
- Ihr Wissen ist auf den Trainingszeitraum begrenzt
- Sie neigen zu Halluzinationen (Generierung falscher Informationen)
- Sie haben keinen Zugriff auf externe Datenquellen
- Sie können keine Quellenangaben machen

## Retrieval-Augmented Generation (RAG)

Retrieval-Augmented Generation (RAG) ist ein Ansatz, der LLMs mit externen Wissensdatenbanken verbindet. Der Prozess funktioniert in mehreren Schritten:

1. **Indizierung**: Dokumente werden in Chunks aufgeteilt und in einer Vektordatenbank gespeichert
2. **Retrieval**: Bei einer Anfrage werden relevante Dokumente abgerufen
3. **Augmentation**: Die gefundenen Dokumente werden in den Prompt eingebettet
4. **Generation**: Das LLM generiert eine Antwort basierend auf dem erweiterten Prompt

Die Vorteile von RAG sind vielfältig:
- Zugriff auf aktuellere Informationen
- Reduzierte Halluzinationen
- Möglichkeit zur Quellenangabe
- Domänenspezifisches Wissen ohne Finetuning

## Vektordatenbanken und Embeddings

Vektordatenbanken sind ein zentraler Bestandteil von RAG-Systemen. Sie speichern Textdokumente als numerische Vektoren, die semantische Ähnlichkeit repräsentieren.

**Embeddings** sind numerische Repräsentationen von Text, die so konstruiert sind, dass ähnliche Texte nahe beieinander im Vektorraum liegen. Sie werden typischerweise durch Embedding-Modelle wie:
- OpenAI Embeddings (kostenpflichtig)
- HuggingFace Sentence Transformers
- Einfache statistische Methoden (weniger effektiv, aber kostenfrei)

**Ähnlichkeitssuche** in Vektordatenbanken verwendet Metriken wie:
- Kosinus-Ähnlichkeit
- Euklidische Distanz
- Dot-Produkt

Elasticsearch kann als Vektordatenbank genutzt werden, indem man den dense_vector-Feldtyp verwendet, der in der Basic-Lizenz verfügbar ist.

## Prompt-Engineering für RAG

Ein effektives RAG-System erfordert sorgfältiges Prompt-Engineering:

```
Systemanweisung: Du bist ein hilfreicher Assistent. Verwende nur die folgenden Informationen, um die Frage zu beantworten. Wenn die Information nicht in den bereitgestellten Dokumenten enthalten ist, sage, dass du es nicht weißt.

Kontext:
[Hier werden die abgerufenen Dokumente eingefügt]

Benutzerfrage:
[Hier steht die ursprüngliche Frage]
```

Dabei ist zu beachten:
- Der Kontext sollte klar vom Rest des Prompts getrennt sein
- Die Anweisungen müssen präzise sein, um Halluzinationen zu vermeiden
- Die Quellenangaben sollten im System berücksichtigt werden

## Chunking-Strategien

Die Aufteilung von Dokumenten in Chunks ist entscheidend für die Effektivität von RAG:

- **Größe**: Zu kleine Chunks verlieren Kontext, zu große Chunks überschreiten Tokengrenze
- **Überlappung**: Überlappende Chunks können Kontextverlust reduzieren
- **Semantische Grenzen**: Aufteilung an semantisch sinnvollen Grenzen (Absätze, Abschnitte)

Typische Chunk-Größen:
- 100-200 Wörter für kurze Fakten
- 500-1000 Wörter für komplexere Informationen

## Evaluierung von RAG-Systemen

Die Qualität eines RAG-Systems kann anhand mehrerer Kriterien bewertet werden:

1. **Abrufgenauigkeit**: Werden die richtigen Dokumente gefunden?
2. **Antwortqualität**: Ist die generierte Antwort korrekt und vollständig?
3. **Halluzinationen**: Werden falsche Informationen generiert?
4. **Quellenangaben**: Werden Quellen korrekt referenziert?

Methoden zur Evaluierung:
- Menschliche Bewertung
- Automatisierte Metriken (ROUGE, BLEU)
- Frage-Antwort-Paare mit bekannten Antworten

## Implementierung ohne Enterprise-Lizenzen

Eine RAG-Implementierung ohne kostenpflichtige Komponenten kann folgende Ansätze verwenden:

1. **Kostenfreie Embeddings**:
   - Einfache statistische Methoden (TF-IDF, BM25)
   - Lokale Open-Source-Modelle (erfordern mehr Rechenleistung)

2. **Freie Vektordatenbanken**:
   - Elasticsearch mit Basic-Lizenz
   - FAISS (Facebook AI Similarity Search)
   - Milvus (Open-Source)

3. **Open-Source LLMs**:
   - Llama 3, Mistral, Phi-3 über Ollama
   - Lokale Modelldeployments

Solche Implementierungen bieten zwar nicht die gleiche Leistung wie kommerzielle Systeme, sind aber kostengünstig und bieten volle Kontrolle über die Daten.
