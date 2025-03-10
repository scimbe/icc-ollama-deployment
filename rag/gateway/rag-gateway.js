/**
 * RAG-Gateway für Ollama ICC Deployment
 * 
 * Dieses Gateway vermittelt zwischen dem Client (Open WebUI) und Ollama,
 * und erweitert Anfragen durch Retrieval-Augmented Generation (RAG) mit Elasticsearch.
 * Es funktioniert mit allen LLM-Modellen, die in Ollama verfügbar sind.
 */

const express = require('express');
const cors = require('cors');
const { Client } = require('@elastic/elasticsearch');
const axios = require('axios');
const bodyParser = require('body-parser');
const dotenv = require('dotenv');

// Lade Umgebungsvariablen
dotenv.config();

const app = express();
const port = process.env.PORT || 3100;

// Ollama API URL
const ollamaBaseUrl = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';

// Elasticsearch Konfiguration
const elasticUrl = process.env.ELASTICSEARCH_URL || 'http://localhost:9200';
const elasticIndex = process.env.ELASTICSEARCH_INDEX || 'ollama-rag';

// Elasticsearch Client initialisieren
const esClient = new Client({ node: elasticUrl });

// Middleware
app.use(cors());
app.use(bodyParser.json({ limit: '10mb' }));

// Starten Sie die Indizes, falls sie nicht existieren
async function setupElasticsearch() {
  try {
    const indexExists = await esClient.indices.exists({ index: elasticIndex });
    
    if (!indexExists) {
      await esClient.indices.create({
        index: elasticIndex,
        body: {
          mappings: {
            properties: {
              content: { type: 'text' },
              embedding: { 
                type: 'dense_vector', 
                dims: 384,
                index: true,
                similarity: 'cosine'
              },
              metadata: { type: 'object' },
              timestamp: { type: 'date' }
            }
          }
        }
      });
      console.log(`Elasticsearch Index '${elasticIndex}' erstellt`);
    }
  } catch (error) {
    console.error('Fehler beim Setup von Elasticsearch:', error);
  }
}

// Funktion zum Generieren von Embeddings mit einem einfachen Algorithmus
// Dies ist ein einfacher Ersatz für lizenzpflichtige Embedding-Modelle
function generateSimpleEmbedding(text) {
  // Eine einfache Methode, um Text in einen Vektor zu verwandeln
  // Basiert auf Wortfrequenzen und Position
  
  const words = text.toLowerCase().split(/\W+/).filter(w => w.length > 0);
  const uniqueWords = [...new Set(words)];
  
  // Erstelle einen Vektor mit 384 Dimensionen (standard für viele Embeddings)
  const vector = new Array(384).fill(0);
  
  // Fülle den Vektor basierend auf Wörtern
  uniqueWords.forEach((word, idx) => {
    // Hash-Funktion für jedes Wort
    let hash = 0;
    for (let i = 0; i < word.length; i++) {
      hash = ((hash << 5) - hash) + word.charCodeAt(i);
      hash = hash & hash;
    }
    
    // Verwende den Hash, um eine Position im Vektor zu bestimmen
    const pos = Math.abs(hash) % vector.length;
    
    // Setze den Wert basierend auf Frequenz und Position
    const frequency = words.filter(w => w === word).length / words.length;
    vector[pos] = frequency;
    
    // Setze auch Nachbarpositionen für mehr Ähnlichkeit
    vector[(pos + 1) % vector.length] = frequency * 0.5;
    vector[(pos + 2) % vector.length] = frequency * 0.25;
  });
  
  // Normalisiere den Vektor
  const magnitude = Math.sqrt(vector.reduce((sum, val) => sum + val * val, 0));
  return vector.map(v => magnitude ? v / magnitude : 0);
}

// Funktion zum Abrufen relevanter Dokumente aus Elasticsearch
async function retrieveRelevantDocuments(query, maxResults = 3) {
  try {
    const queryEmbedding = generateSimpleEmbedding(query);
    
    // Kombinierte Suche mit KNN-Vektorsuche und Text-Matching
    const response = await esClient.search({
      index: elasticIndex,
      body: {
        query: {
          bool: {
            should: [
              // Vektorsuche mit self-generated embedding
              {
                script_score: {
                  query: { match_all: {} },
                  script: {
                    source: "cosineSimilarity(params.query_vector, 'embedding') + 1.0",
                    params: { query_vector: queryEmbedding }
                  }
                }
              },
              // Text-Match als Fallback und zur Verbesserung
              {
                match: {
                  content: {
                    query: query,
                    boost: 0.5
                  }
                }
              }
            ]
          }
        },
        size: maxResults
      }
    });
    
    return response.hits.hits.map(hit => hit._source);
  } catch (error) {
    console.error('Fehler beim Abrufen relevanter Dokumente:', error);
    
    // Fallback auf einfache Textsuche, falls Vektorsuche fehlschlägt
    try {
      const fallbackResponse = await esClient.search({
        index: elasticIndex,
        body: {
          query: {
            match: {
              content: query
            }
          },
          size: maxResults
        }
      });
      
      return fallbackResponse.hits.hits.map(hit => hit._source);
    } catch (fallbackError) {
      console.error('Auch Fallback-Suche fehlgeschlagen:', fallbackError);
      return [];
    }
  }
}

// Hilfsfunktion zum Speichern von Dokumenten in Elasticsearch
async function saveToElasticsearch(content, metadata = {}) {
  try {
    // Generiere Embedding für den Inhalt
    const embedding = generateSimpleEmbedding(content);
    
    await esClient.index({
      index: elasticIndex,
      body: {
        content: content,
        embedding: embedding,
        metadata: metadata,
        timestamp: new Date()
      },
      refresh: true
    });
  } catch (error) {
    console.error('Fehler beim Speichern in Elasticsearch:', error);
  }
}

// Proxy für Ollama API
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', gateway: 'rag-gateway', version: '1.0.0' });
});

// Hauptendpunkt für RAG-erweiterte Anfragen
app.post('/api/generate', async (req, res) => {
  try {
    const { prompt, model, system, options } = req.body;
    
    // RAG: Relevante Dokumente abrufen
    const relevantDocs = await retrieveRelevantDocuments(prompt);
    
    // Kontext aus relevanten Dokumenten erstellen
    let ragContext = '';
    if (relevantDocs.length > 0) {
      ragContext = 'Hier sind einige relevante Informationen:\n\n' + 
        relevantDocs.map(doc => doc.content).join('\n\n') + 
        '\n\nBerücksichtige diese Informationen bei deiner Antwort:';
    }
    
    // Erweiterten Prompt erstellen
    const enhancedPrompt = ragContext ? `${ragContext}\n\n${prompt}` : prompt;
    
    // Request an Ollama senden
    const ollamaResponse = await axios.post(`${ollamaBaseUrl}/api/generate`, {
      model: model || 'llama3:8b',
      prompt: enhancedPrompt,
      system: system,
      options: options,
      stream: false
    });
    
    // Speichern der Antwort in Elasticsearch für kontinuierliches Lernen
    await saveToElasticsearch(
      ollamaResponse.data.response,
      { 
        query: prompt, 
        model: model, 
        enhanced: !!ragContext,
        ragDocsCount: relevantDocs.length
      }
    );
    
    // Antwort zurück an den Client
    res.json({
      ...ollamaResponse.data,
      rag: {
        enhanced: !!ragContext,
        docsCount: relevantDocs.length
      }
    });
  } catch (error) {
    console.error('Fehler bei der Verarbeitung der Anfrage:', error);
    res.status(500).json({ error: 'Interner Serverfehler', details: error.message });
  }
});

// Stream-Endpunkt für interaktive Antworten
app.post('/api/chat/completions', async (req, res) => {
  try {
    const { messages, model, stream, temperature } = req.body;
    
    // Extrahiere den letzten Benutzer-Prompt aus den Nachrichten
    const lastUserMessage = messages.filter(m => m.role === 'user').pop();
    
    if (!lastUserMessage) {
      return res.status(400).json({ error: 'Keine Benutzernachricht gefunden' });
    }
    
    // RAG: Relevante Dokumente für den letzten Prompt abrufen
    const relevantDocs = await retrieveRelevantDocuments(lastUserMessage.content);
    
    // Erweitere die Systemnachricht oder füge eine hinzu, wenn keine vorhanden ist
    const systemMessage = messages.find(m => m.role === 'system');
    let enhancedMessages = [...messages];
    
    if (relevantDocs.length > 0) {
      const ragContext = 'Hier sind einige relevante Informationen:\n\n' + 
        relevantDocs.map(doc => doc.content).join('\n\n') + 
        '\n\nBerücksichtige diese Informationen bei deiner Antwort.';
      
      if (systemMessage) {
        // Aktualisiere die vorhandene Systemnachricht
        const systemIndex = enhancedMessages.findIndex(m => m.role === 'system');
        enhancedMessages[systemIndex] = {
          ...systemMessage,
          content: `${systemMessage.content}\n\n${ragContext}`
        };
      } else {
        // Füge eine neue Systemnachricht hinzu
        enhancedMessages.unshift({
          role: 'system',
          content: ragContext
        });
      }
    }
    
    // Request an Ollama senden
    const ollamaResponse = await axios.post(`${ollamaBaseUrl}/api/chat/completions`, {
      messages: enhancedMessages,
      model: model || 'llama3:8b',
      stream: stream,
      temperature: temperature
    }, {
      responseType: stream ? 'stream' : 'json'
    });
    
    if (stream) {
      // Stream-Modus: Leite die Antwort direkt weiter
      ollamaResponse.data.pipe(res);
    } else {
      // Speichern der Antwort in Elasticsearch
      const assistantResponse = ollamaResponse.data.choices[0]?.message?.content;
      if (assistantResponse) {
        await saveToElasticsearch(
          assistantResponse,
          {
            query: lastUserMessage.content,
            model: model,
            enhanced: relevantDocs.length > 0,
            ragDocsCount: relevantDocs.length
          }
        );
      }
      
      // Füge RAG-Informationen zur Antwort hinzu
      const enhancedResponse = {
        ...ollamaResponse.data,
        rag_info: {
          enhanced: relevantDocs.length > 0,
          docsCount: relevantDocs.length
        }
      };
      
      res.json(enhancedResponse);
    }
  } catch (error) {
    console.error('Fehler bei der Verarbeitung der Chat-Anfrage:', error);
    res.status(500).json({ error: 'Interner Serverfehler', details: error.message });
  }
});

// Proxy für alle anderen Anfragen an Ollama
app.all('/api/*', async (req, res) => {
  try {
    const ollamaPath = req.path;
    const response = await axios({
      method: req.method,
      url: `${ollamaBaseUrl}${ollamaPath}`,
      data: req.method !== 'GET' ? req.body : undefined,
      headers: { 
        'Content-Type': 'application/json' 
      },
    });
    
    res.status(response.status).json(response.data);
  } catch (error) {
    console.error('Fehler beim Proxy zu Ollama:', error);
    res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
  }
});

// Endpunkt zum Speichern von Dokumenten in Elasticsearch
app.post('/api/rag/documents', async (req, res) => {
  try {
    const { content, metadata } = req.body;
    
    if (!content) {
      return res.status(400).json({ error: 'Content ist erforderlich' });
    }
    
    await saveToElasticsearch(content, metadata);
    res.json({ success: true, message: 'Dokument gespeichert' });
  } catch (error) {
    console.error('Fehler beim Speichern des Dokuments:', error);
    res.status(500).json({ error: 'Fehler beim Speichern', details: error.message });
  }
});

// Endpunkt zum Abrufen von Dokumenten
app.get('/api/rag/documents', async (req, res) => {
  try {
    const { query, limit } = req.query;
    const maxResults = parseInt(limit) || 10;
    
    const docs = await retrieveRelevantDocuments(query || '', maxResults);
    res.json(docs);
  } catch (error) {
    console.error('Fehler beim Abrufen der Dokumente:', error);
    res.status(500).json({ error: 'Fehler beim Abrufen', details: error.message });
  }
});

// Bulk-Import-Endpunkt
app.post('/api/rag/bulk', async (req, res) => {
  try {
    const { documents } = req.body;
    
    if (!Array.isArray(documents)) {
      return res.status(400).json({ error: 'Documents muss ein Array sein' });
    }
    
    let successCount = 0;
    
    for (const doc of documents) {
      if (doc.content) {
        await saveToElasticsearch(doc.content, doc.metadata || {});
        successCount++;
      }
    }
    
    res.json({ 
      success: true, 
      message: `${successCount} von ${documents.length} Dokumenten importiert` 
    });
  } catch (error) {
    console.error('Fehler beim Bulk-Import:', error);
    res.status(500).json({ error: 'Fehler beim Import', details: error.message });
  }
});

// Server starten
app.listen(port, async () => {
  console.log(`RAG-Gateway läuft auf Port ${port}`);
  await setupElasticsearch().catch(console.error);
});
