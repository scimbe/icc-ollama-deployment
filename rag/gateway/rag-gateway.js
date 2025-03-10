/**
 * RAG-Gateway für Ollama ICC Deployment
 * 
 * Dieses Gateway vermittelt zwischen dem Client (Open WebUI) und Ollama,
 * und erweitert Anfragen durch Retrieval-Augmented Generation (RAG) mit Elasticsearch.
 * Es funktioniert mit allen LLM-Modellen, die in Ollama verfügbar sind.
 * 
 * Diese Version ist für ressourcenbeschränkte Umgebungen optimiert.
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

// Konstanten für Laufzeitverhalten
const MAX_RESULTS = parseInt(process.env.MAX_RESULTS || "3");
const NODE_ENV = process.env.NODE_ENV || 'production';

// Elasticsearch Client initialisieren mit ressourcenschonenden Einstellungen
const esClient = new Client({ 
  node: elasticUrl,
  maxRetries: 3,
  requestTimeout: 30000,
  sniffOnStart: false,
  sniffOnConnectionFault: false,
  ssl: {
    rejectUnauthorized: false
  }
});

// Middleware
app.use(cors());
app.use(bodyParser.json({ limit: '1mb' }));  // Reduzierte Limit-Größe

// Optimiertes Logging
const log = (message, level = 'info') => {
  // Im Produktionsmodus nur Fehler und Warnungen loggen
  if (NODE_ENV === 'production' && level === 'info') return;
  
  const timestamp = new Date().toISOString();
  console[level === 'error' ? 'error' : level === 'warn' ? 'warn' : 'log'](`[${timestamp}] [${level}] ${message}`);
};

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
              // Vereinfachtes Embedding ohne DIMS-Parameter für Elasticsearch 7.x Kompatibilität
              embedding: { 
                type: 'dense_vector',
                dims: 384
              },
              metadata: { type: 'object' },
              timestamp: { type: 'date' }
            }
          },
          settings: {
            number_of_shards: 1,  // Minimaler Wert für weniger Ressourcenverbrauch
            number_of_replicas: 0, // Keine Repliken für lokale Entwicklung
            refresh_interval: "30s" // Weniger häufige Aktualisierungen
          }
        }
      });
      log(`Elasticsearch Index '${elasticIndex}' erstellt`);
    }
  } catch (error) {
    log(`Fehler beim Setup von Elasticsearch: ${error.message}`, 'error');
    // Keine fatalen Fehler, erlaubt dennoch den Start des Servers
  }
}

// Vereinfachtes und ressourcenschonendes Embedding
function generateSimpleEmbedding(text) {
  if (!text) return new Array(384).fill(0);
  
  // Beschränke die Textlänge für Ressourceneinsparung
  const limitedText = text.slice(0, 10000);
  
  // Eine vereinfachte Version, die für kurze Texte optimiert ist
  const words = limitedText.toLowerCase().split(/\W+/).filter(w => w.length > 0);
  const vector = new Array(384).fill(0);
  
  words.forEach((word, idx) => {
    // Verwende nur die ersten 100 Wörter für Ressourceneinsparung
    if (idx >= 100) return;
    
    let hash = 0;
    // Nur die ersten 10 Zeichen des Wortes hashen
    const wordPrefix = word.slice(0, 10);
    for (let i = 0; i < wordPrefix.length; i++) {
      hash = ((hash << 5) - hash) + wordPrefix.charCodeAt(i);
      hash = hash & hash;
    }
    
    const pos = Math.abs(hash) % vector.length;
    const frequency = Math.min(1, words.filter(w => w === word).length / words.length);
    vector[pos] = frequency;
  });
  
  // Einfache Normalisierung ohne teure Berechnungen
  const sum = vector.reduce((acc, val) => acc + Math.abs(val), 0);
  return sum > 0 ? vector.map(v => v / sum) : vector;
}

// Ressourcenschonende Variante für Dokumentenabruf
async function retrieveRelevantDocuments(query, maxResults = MAX_RESULTS) {
  if (!query || query.trim().length === 0) {
    return [];
  }
  
  try {
    // Nur Textabfrage für bessere Leistung in ressourcenbeschränkten Umgebungen
    const response = await esClient.search({
      index: elasticIndex,
      body: {
        query: {
          match: {
            content: {
              query: query,
              operator: "or",
              fuzziness: "AUTO"
            }
          }
        },
        _source: ["content", "metadata", "timestamp"],
        size: maxResults
      }
    });
    
    return response.hits.hits.map(hit => hit._source);
  } catch (error) {
    log(`Fehler beim Abrufen relevanter Dokumente: ${error.message}`, 'error');
    return [];
  }
}

// Speichersparende Speicherfunktion (ohne aufwendige Embedding-Berechnung)
async function saveToElasticsearch(content, metadata = {}) {
  if (!content || content.trim().length === 0) {
    log("Leerer Content wurde nicht gespeichert", 'warn');
    return;
  }
  
  try {
    // Begrenzt die Content-Größe für Ressourceneinsparung
    const limitedContent = content.slice(0, 50000);
    
    await esClient.index({
      index: elasticIndex,
      body: {
        content: limitedContent,
        metadata: metadata,
        timestamp: new Date()
      },
      refresh: "wait_for"  // Weniger häufige Aktualisierungen
    });
  } catch (error) {
    log(`Fehler beim Speichern in Elasticsearch: ${error.message}`, 'error');
  }
}

// Health-Check-Endpunkt für Monitoring
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', gateway: 'rag-gateway', version: '1.0.0' });
});

// Speichereffizienter Proxy für Ollama generate API
app.post('/api/generate', async (req, res) => {
  try {
    const { prompt, model, system, options } = req.body;
    
    if (!prompt || prompt.trim().length === 0) {
      return res.status(400).json({ error: 'Prompt ist erforderlich' });
    }
    
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
    
    // Speichern der Antwort in Elasticsearch im Hintergrund
    if (ollamaResponse.data.response) {
      // Ausführung im Hintergrund ohne await
      saveToElasticsearch(
        ollamaResponse.data.response,
        { 
          query: prompt, 
          model: model, 
          enhanced: !!ragContext,
          ragDocsCount: relevantDocs.length
        }
      ).catch(() => {/* Fehler ignorieren */});
    }
    
    // Antwort zurück an den Client
    res.json({
      ...ollamaResponse.data,
      rag: {
        enhanced: !!ragContext,
        docsCount: relevantDocs.length
      }
    });
  } catch (error) {
    log(`Fehler bei der Verarbeitung der Anfrage: ${error.message}`, 'error');
    res.status(500).json({ error: 'Interner Serverfehler', details: error.message });
  }
});

// Chat-Completions-Proxy
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
      // Speichern der Antwort in Elasticsearch im Hintergrund
      const assistantResponse = ollamaResponse.data.choices[0]?.message?.content;
      if (assistantResponse) {
        // Asynchron und nicht-blockierend
        saveToElasticsearch(
          assistantResponse,
          {
            query: lastUserMessage.content,
            model: model,
            enhanced: relevantDocs.length > 0,
            ragDocsCount: relevantDocs.length
          }
        ).catch(() => {/* Fehler ignorieren */});
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
    log(`Fehler bei der Verarbeitung der Chat-Anfrage: ${error.message}`, 'error');
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
    log(`Fehler beim Proxy zu Ollama: ${error.message}`, 'error');
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
    log(`Fehler beim Speichern des Dokuments: ${error.message}`, 'error');
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
    log(`Fehler beim Abrufen der Dokumente: ${error.message}`, 'error');
    res.status(500).json({ error: 'Fehler beim Abrufen', details: error.message });
  }
});

// Server starten
app.listen(port, async () => {
  log(`RAG-Gateway läuft auf Port ${port}`);
  
  // Versuche Elasticsearch einzurichten, aber lasse den Server auch starten, wenn es fehlschlägt
  try {
    await setupElasticsearch();
  } catch (e) {
    log(`Elasticsearch-Setup fehlgeschlagen, Gateway startet trotzdem: ${e.message}`, 'warn');
  }
});
