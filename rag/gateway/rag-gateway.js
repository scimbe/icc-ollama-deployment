/**
 * RAG-Gateway für Ollama ICC Deployment
 * 
 * Versionskompatible Implementierung mit Debug-Unterstützung für beide
 * Ollama-API-Endpunkte (/api/generate und /api/chat)
 * v2.0.0 (2025)
 */

const express = require('express');
const cors = require('cors');
const { Client } = require('@elastic/elasticsearch');
const axios = require('axios');
const bodyParser = require('body-parser');
const dotenv = require('dotenv');

dotenv.config();
const app = express();
const port = process.env.PORT || 3100;
const ollamaBaseUrl = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
const elasticUrl = process.env.ELASTICSEARCH_URL || 'http://localhost:9200';
const elasticIndex = process.env.ELASTICSEARCH_INDEX || 'ollama-rag';
const MAX_RESULTS = parseInt(process.env.MAX_RESULTS || "3");
const NODE_ENV = process.env.NODE_ENV || 'production';
const DEBUG_MODE = process.env.DEBUG_MODE === 'true' || true;
let preferredApiEndpoint = 'chat'; // Dynamisch ermittelt beim Start

// Erweitertes Logging
const log = (message, level = 'info', details = null) => {
  if (NODE_ENV === 'production' && level === 'info' && !DEBUG_MODE) return;
  const timestamp = new Date().toISOString();
  console[level === 'error' ? 'error' : level === 'warn' ? 'warn' : 'log'](`[${timestamp}] [${level.toUpperCase()}] ${message}`);
  if (details && (DEBUG_MODE || level === 'error')) {
    let detailsOutput = typeof details === 'object' ? 
      JSON.stringify(details, null, 2) : String(details);
    console[level === 'error' ? 'error' : level === 'warn' ? 'warn' : 'log'](`[${timestamp}] [${level.toUpperCase()}] Details: ${detailsOutput}`);
  }
};

// Elasticsearch Client
const esClient = new Client({ 
  node: elasticUrl,
  maxRetries: 5,
  requestTimeout: 30000,
  sniffOnStart: false,
  sniffOnConnectionFault: false,
  ssl: { rejectUnauthorized: false }
});

// Test Ollama-API und bestimme bevorzugten Endpunkt
async function checkOllamaVersion() {
  try {
    // Teste Version
    const response = await axios.get(`${ollamaBaseUrl}/api/version`);
    log(`Ollama-Version erkannt: ${response.data.version}`, 'info');
    
    // Teste Chat-API
    try {
      await axios.post(`${ollamaBaseUrl}/api/chat`, {
        messages: [{ role: "user", content: "test" }],
        model: "phi4", stream: false
      });
      preferredApiEndpoint = 'chat';
      log('Verwende /api/chat-Endpunkt', 'info');
      return true;
    } catch (chatError) {
      if (chatError.response?.status === 404) {
        preferredApiEndpoint = 'generate';
        log('Verwende /api/generate-Endpunkt (chat nicht verfügbar)', 'warn');
        return true;
      }
      log(`Chat-API-Test fehlgeschlagen: ${chatError.message}`, 'warn');
    }

    // Teste Generate-API
    try {
      await axios.post(`${ollamaBaseUrl}/api/generate`, {
        prompt: "test", model: "phi4", stream: false
      });
      preferredApiEndpoint = 'generate';
      log('Verwende /api/generate-Endpunkt', 'info');
      return true;
    } catch (genError) {
      log(`Generate-API-Test fehlgeschlagen: ${genError.message}`, 'warn');
    }
    
    return false;
  } catch (error) {
    log(`Ollama-Verbindungsfehler: ${error.message}`, 'error');
    return false;
  }
}

// Elasticsearch Setup
async function setupElasticsearch() {
  try {
    // Ping Test
    try {
      await esClient.ping();
      log('Elasticsearch ist erreichbar', 'info');
    } catch (pingError) {
      log(`Elasticsearch nicht erreichbar: ${pingError.message}`, 'warn');
      return false;
    }
    
    // Index prüfen/erstellen
    let indexExists = false;
    try {
      indexExists = await esClient.indices.exists({ index: elasticIndex });
      // Kompatibilität mit neueren Elasticsearch-Clients sicherstellen
      if (typeof indexExists === 'object') {
        indexExists = indexExists.body === true || indexExists.statusCode === 200;
      }
    } catch (error) {
      log(`Fehler beim Prüfen, ob Index existiert: ${error.message}`, 'warn');
      // Wir versuchen trotzdem, den Index zu erstellen
    }
    
    if (!indexExists) {
      try {
        await esClient.indices.create({
          index: elasticIndex,
          body: {
            mappings: {
              properties: {
                content: { type: 'text' },
                embedding: { type: 'dense_vector', dims: 384 },
                metadata: { type: 'object' },
                timestamp: { type: 'date' }
              }
            },
            settings: {
              number_of_shards: 1,
              number_of_replicas: 0,
              refresh_interval: "30s"
            }
          }
        });
        log(`Index '${elasticIndex}' erstellt`, 'info');
      } catch (error) {
        // Ignoriere "resource_already_exists_exception", da dies bedeutet, dass der Index bereits existiert
        if (error.message.includes('resource_already_exists_exception')) {
          log(`Index '${elasticIndex}' existiert bereits`, 'info');
        } else {
          throw error;
        }
      }
    } else {
      log(`Index '${elasticIndex}' existiert bereits`, 'info');
    }
    return true;
  } catch (error) {
    log(`Elasticsearch-Setup fehlgeschlagen: ${error.message}`, 'error', error);
    return false;
  }
}

// Dokumentensuche
async function retrieveRelevantDocuments(query, maxResults = MAX_RESULTS) {
  if (!query || query.trim().length === 0) return [];
  
  try {
    const isConnected = await esClient.ping().catch(() => false);
    if (!isConnected) {
      log('Elasticsearch nicht verfügbar, überspringe Dokumentenabruf', 'warn');
      return [];
    }
    
    const response = await esClient.search({
      index: elasticIndex,
      body: {
        query: { match: { content: { query, operator: "or", fuzziness: "AUTO" } } },
        _source: ["content", "metadata", "timestamp"],
        size: maxResults
      }
    });
    
    const docs = response.hits?.hits?.map(hit => hit._source) || [];
    log(`${docs.length} relevante Dokumente gefunden`, 'debug');
    return docs;
  } catch (error) {
    log(`Dokumentenabruf fehlgeschlagen: ${error.message}`, 'error');
    return [];
  }
}

// Erstellt einen RAG-Kontext mit starker Aufforderung, die Dokumente als Single Point of Truth zu behandeln
function createSinglePointOfTruthContext(documents) {
  if (!documents || documents.length === 0) return '';

  // Extraktion der Dokumente
  const documentContents = documents.map(doc => doc.content).join('\n\n---\n\n');
  
  // Erstelle einen Kontext, der dem Modell deutlich macht, dass die Dokumente die höchste Priorität haben
  return `WICHTIG: Die folgenden Informationen sind als SINGLE POINT OF TRUTH zu betrachten.
Du MUSST diese Informationen als primäre und zuverlässigste Quelle verwenden und ihnen HÖCHSTE PRIORITÄT geben.
Informationen aus dem Modelltraining sollen NUR ergänzend eingesetzt werden, falls es Lücken gibt.
Falls Widersprüche zwischen den folgenden Dokumenten und deinem trainierten Wissen bestehen, 
MÜSSEN IMMER die Dokumente als korrekt angesehen werden.

AUTORITATIVE DOKUMENTE:
-----------------------
${documentContents}
-----------------------

ANWEISUNG: Beantworte die folgende Frage ausschließlich auf Basis der obigen autoritativen Dokumente.
Falls diese Dokumente nicht ausreichen, um die Frage zu beantworten, gib dies explizit an.
`;
}

// Dokument speichern
async function saveToElasticsearch(content, metadata = {}) {
  if (!content || content.trim().length === 0) {
    log('Kein Inhalt zum Speichern angegeben', 'warn');
    return false;
  }
  
  try {
    // Ping-Test explizit durchführen
    const isConnected = await esClient.ping().catch((error) => {
      log(`Elasticsearch ping fehlgeschlagen: ${error.message}`, 'error');
      return false;
    });
    
    if (!isConnected) {
      log('Elasticsearch nicht erreichbar, kann Dokument nicht speichern', 'error');
      return false;
    }
    
    // Trim und Limit für Inhalt
    const limitedContent = content.trim().slice(0, 50000);
    
    // Dokument indexieren mit expliziter Fehlerbehandlung
    const response = await esClient.index({
      index: elasticIndex,
      body: {
        content: limitedContent,
        metadata,
        timestamp: new Date()
      },
      refresh: "wait_for"
    });
    
    // Erfolgreiche Indexierung loggen
    const docId = response._id || response.body?._id;
    log(`Dokument erfolgreich gespeichert mit ID: ${docId}`, 'debug');
    return true;
  } catch (error) {
    log(`Dokument konnte nicht gespeichert werden: ${error.message}`, 'error', error);
    return false;
  }
}

// Intelligente Ollama-Anfrage (unterstützt beide API-Endpunkte)
async function makeOllamaRequest(prompt, model, system, options, stream = false, temperature = 0.7) {
  const requestOptions = { responseType: stream ? 'stream' : 'json' };
  
  if (preferredApiEndpoint === 'chat') {
    const messages = [];
    if (system) messages.push({ role: "system", content: system });
    messages.push({ role: "user", content: prompt });
    
    try {
      return await axios.post(`${ollamaBaseUrl}/api/chat`, {
        messages, model: model || 'phi4', stream, options, temperature
      }, requestOptions);
    } catch (error) {
      if (error.response?.status === 404) {
        preferredApiEndpoint = 'generate';
        return makeOllamaRequest(prompt, model, system, options, stream, temperature);
      }
      throw error;
    }
  } else {
    try {
      return await axios.post(`${ollamaBaseUrl}/api/generate`, {
        prompt, model: model || 'phi4', stream, options, system, temperature
      }, requestOptions);
    } catch (error) {
      if (error.response?.status === 404) {
        preferredApiEndpoint = 'chat';
        return makeOllamaRequest(prompt, model, system, options, stream, temperature);
      }
      throw error;
    }
  }
}

// Format-Normalisierung zwischen API-Versionen
function extractResponseData(ollamaResponse, endpoint) {
  if (!ollamaResponse?.data) return { response: "" };
  
  if (endpoint === 'chat') {
    return {
      response: ollamaResponse.data.message?.content || "",
      prompt_eval_count: ollamaResponse.data.prompt_eval_count,
      eval_count: ollamaResponse.data.eval_count,
      done_reason: ollamaResponse.data.done_reason
    };
  } else {
    return ollamaResponse.data;
  }
}

// Middleware
app.use(cors());
app.use(bodyParser.json({ limit: '2mb' }));
if (DEBUG_MODE) {
  app.use((req, res, next) => {
    log(`Anfrage: ${req.method} ${req.url}`, 'debug');
    next();
  });
}

// Health-Check
app.get('/api/health', async (req, res) => {
  const elasticsearchStatus = await esClient.ping().catch(() => false);
  let ollamaStatus = false, ollamaVersionString = "unbekannt";
  
  try {
    const ollamaCheck = await axios.get(`${ollamaBaseUrl}/api/version`);
    ollamaStatus = true;
    ollamaVersionString = ollamaCheck.data.version || "unbekannt";
  } catch (error) {
    log(`Ollama nicht erreichbar: ${error.message}`, 'warn');
  }
  
  res.json({ 
    status: ollamaStatus && elasticsearchStatus ? 'ok' : 'degraded', 
    gateway: 'rag-gateway', 
    version: '2.0.0',
    timestamp: new Date().toISOString(),
    elasticsearch: elasticsearchStatus ? 'connected' : 'disconnected',
    ollama: ollamaStatus ? 'connected' : 'disconnected',
    ollamaVersion: ollamaVersionString,
    preferredApiEndpoint
  });
});

// Generate API
app.post('/api/generate', async (req, res) => {
  try {
    const { prompt, model, system, options, stream, temperature } = req.body;
    
    if (!prompt?.trim()) {
      return res.status(400).json({ error: 'Prompt ist erforderlich' });
    }
    
    // RAG-Erweiterung mit Single Point of Truth
    const relevantDocs = await retrieveRelevantDocuments(prompt);
    let enhancedPrompt = prompt;
    let ragContext = '';
    
    if (relevantDocs.length > 0) {
      // Erstelle den Single Point of Truth Kontext
      ragContext = createSinglePointOfTruthContext(relevantDocs);
      enhancedPrompt = `${ragContext}\n\nFRAGE: ${prompt}`;
    }
    
    // Angepasstes System-Prompt für Single Point of Truth
    let enhancedSystem = system;
    if (relevantDocs.length > 0 && system) {
      enhancedSystem = `${system}\n\nWICHTIG: Betrachte die bereitgestellten Dokumente als Single Point of Truth. Bevorzuge diese Informationen vor allem anderen.`;
    }
    
    // Anfrage an Ollama
    const ollamaResponse = await makeOllamaRequest(
      enhancedPrompt,
      model || 'phi4',
      enhancedSystem,
      options,
      stream || false,
      temperature || 0.7
    );
    
    if (stream) {
      ollamaResponse.data.pipe(res);
      return;
    }
    
    const responseData = extractResponseData(ollamaResponse, preferredApiEndpoint);
    
    // Antwort speichern
    if (responseData.response) {
      saveToElasticsearch(
        responseData.response,
        { 
          query: prompt, 
          model, 
          enhanced: !!ragContext,
          ragDocsCount: relevantDocs.length
        }
      ).catch(() => {});
    }
    
    // Antwort zurückgeben
    res.json({
      ...responseData,
      rag: {
        enhanced: !!ragContext,
        docsCount: relevantDocs.length
      }
    });
  } catch (error) {
    log(`Fehler bei /api/generate: ${error.message}`, 'error');
    res.status(500).json({ error: 'Interner Serverfehler', details: error.message });
  }
});

// OpenAI-kompatibler Chat-API Endpunkt
app.post('/api/chat/completions', async (req, res) => {
  try {
    const { messages, model, stream, temperature } = req.body;
    const lastUserMessage = messages.filter(m => m.role === 'user').pop();
    
    if (!lastUserMessage) {
      return res.status(400).json({ error: 'Keine Benutzernachricht gefunden' });
    }
    
    // RAG-Erweiterung mit Single Point of Truth
    const relevantDocs = await retrieveRelevantDocuments(lastUserMessage.content);
    let enhancedMessages = [...messages];
    
    if (relevantDocs.length > 0) {
      // Erstelle den Single Point of Truth Kontext
      const ragContext = createSinglePointOfTruthContext(relevantDocs);
      
      // Füge die Anweisung als System-Nachricht hinzu oder erweitere eine bestehende
      const systemMessageIndex = enhancedMessages.findIndex(m => m.role === 'system');
      
      if (systemMessageIndex >= 0) {
        // Erweitere die bestehende System-Nachricht
        enhancedMessages[systemMessageIndex] = {
          ...enhancedMessages[systemMessageIndex],
          content: `${enhancedMessages[systemMessageIndex].content}\n\n${ragContext}`
        };
      } else {
        // Füge eine neue System-Nachricht am Anfang hinzu
        enhancedMessages.unshift({ 
          role: 'system', 
          content: ragContext 
        });
      }
    }
    
    // Anfrage an Ollama
    const ollamaResponse = await axios.post(`${ollamaBaseUrl}/api/chat`, {
      messages: enhancedMessages,
      model: model || 'phi4',
      stream,
      temperature
    }, {
      responseType: stream ? 'stream' : 'json'
    });
    
    if (stream) {
      ollamaResponse.data.pipe(res);
      return;
    }
    
    // Antwort speichern
    const assistantResponse = ollamaResponse.data.message?.content;
    if (assistantResponse) {
      saveToElasticsearch(
        assistantResponse,
        {
          query: lastUserMessage.content,
          model,
          enhanced: relevantDocs.length > 0,
          ragDocsCount: relevantDocs.length
        }
      ).catch(() => {});
    }
    
    // OpenAI-kompatible Antwort
    res.json({
      id: `chatcmpl-${Date.now()}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: model || "ollama_model",
      choices: [{
        index: 0,
        message: {
          role: "assistant",
          content: assistantResponse || "",
        },
        finish_reason: ollamaResponse.data.done_reason || "stop"
      }],
      usage: {
        prompt_tokens: ollamaResponse.data.prompt_eval_count || 0,
        completion_tokens: ollamaResponse.data.eval_count || 0,
        total_tokens: (ollamaResponse.data.prompt_eval_count || 0) + (ollamaResponse.data.eval_count || 0)
      },
      rag_info: {
        enhanced: relevantDocs.length > 0,
        docsCount: relevantDocs.length
      }
    });
  } catch (error) {
    log(`Fehler bei /api/chat/completions: ${error.message}`, 'error');
    res.status(500).json({ error: 'Interner Serverfehler', details: error.message });
  }
});

// Nativer Ollama Chat-API Endpunkt
app.post('/api/chat', async (req, res) => {
  try {
    const { messages, model, stream, temperature } = req.body;
    const lastUserMessage = messages.filter(m => m.role === 'user').pop();
    
    if (!lastUserMessage) {
      return res.status(400).json({ error: 'Keine Benutzernachricht gefunden' });
    }
    
    // RAG-Erweiterung mit Single Point of Truth
    const relevantDocs = await retrieveRelevantDocuments(lastUserMessage.content);
    let enhancedMessages = [...messages];
    
    if (relevantDocs.length > 0) {
      // Erstelle den Single Point of Truth Kontext
      const ragContext = createSinglePointOfTruthContext(relevantDocs);
      
      // Füge die Anweisung als System-Nachricht hinzu oder erweitere eine bestehende
      const systemMessageIndex = enhancedMessages.findIndex(m => m.role === 'system');
      
      if (systemMessageIndex >= 0) {
        // Erweitere die bestehende System-Nachricht
        enhancedMessages[systemMessageIndex] = {
          ...enhancedMessages[systemMessageIndex],
          content: `${enhancedMessages[systemMessageIndex].content}\n\n${ragContext}`
        };
      } else {
        // Füge eine neue System-Nachricht am Anfang hinzu
        enhancedMessages.unshift({ 
          role: 'system', 
          content: ragContext 
        });
      }
    }
    
    // Anfrage an Ollama
    const ollamaResponse = await axios.post(`${ollamaBaseUrl}/api/chat`, {
      messages: enhancedMessages,
      model: model || 'phi4',
      stream,
      temperature
    }, {
      responseType: stream ? 'stream' : 'json'
    });
    
    if (stream) {
      ollamaResponse.data.pipe(res);
      return;
    }
    
    // Antwort speichern
    const assistantResponse = ollamaResponse.data.message?.content;
    if (assistantResponse) {
      saveToElasticsearch(
        assistantResponse,
        {
          query: lastUserMessage.content,
          model,
          enhanced: relevantDocs.length > 0,
          ragDocsCount: relevantDocs.length
        }
      ).catch(() => {});
    }
    
    // Antwort im nativen Format zurückgeben
    res.json({
      ...ollamaResponse.data,
      rag_info: {
        enhanced: relevantDocs.length > 0,
        docsCount: relevantDocs.length
      }
    });
  } catch (error) {
    log(`Fehler bei /api/chat: ${error.message}`, 'error');
    res.status(500).json({ error: 'Interner Serverfehler', details: error.message });
  }
});

// RAG-Dokumente API
app.post('/api/rag/documents', async (req, res) => {
  try {
    log('Dokument-Upload-Request erhalten', 'debug', req.body);
    
    const { content, metadata } = req.body;
    if (!content) {
      log('Content fehlt in der Anfrage', 'error');
      return res.status(400).json({ error: 'Content ist erforderlich' });
    }
    
    // Prüfen, ob Elasticsearch erreichbar ist
    const isConnected = await esClient.ping().catch((error) => {
      log(`Elasticsearch ping fehlgeschlagen: ${error.message}`, 'error');
      return false;
    });
    
    if (!isConnected) {
      log('Elasticsearch nicht erreichbar für Dokument-Upload', 'error');
      return res.status(503).json({ error: 'Elasticsearch ist nicht erreichbar' });
    }
    
    // Mit verbesserter Fehlerbehandlung speichern
    const saved = await saveToElasticsearch(content, metadata);
    
    if (saved) {
      log('Dokument erfolgreich gespeichert', 'info');
      return res.json({ success: true, message: 'Dokument gespeichert' });
    } else {
      log('Dokument konnte nicht gespeichert werden', 'error');
      return res.status(500).json({ error: 'Fehler beim Speichern des Dokuments' });
    }
  } catch (error) {
    log(`Unbehandelter Fehler beim Speichern: ${error.message}`, 'error', error);
    res.status(500).json({ error: 'Fehler beim Speichern', details: error.message });
  }
});

app.get('/api/rag/documents', async (req, res) => {
  try {
    const { query, limit } = req.query;
    const maxResults = parseInt(limit) || 10;
    
    const docs = await retrieveRelevantDocuments(query || '', maxResults);
    res.json(docs);
  } catch (error) {
    log(`Fehler beim Abrufen: ${error.message}`, 'error');
    res.status(500).json({ error: 'Fehler beim Abrufen', details: error.message });
  }
});

// Allgemeiner API-Proxy
const apiRouter = express.Router();
app.use('/api', apiRouter);

apiRouter.all('/:path(*)', async (req, res) => {
  if (['chat/completions', 'chat', 'generate', 'health', 'rag/documents'].includes(req.params.path)) {
    return; // Bereits definierte Routen überspringen
  }
  
  try {
    const ollamaPath = `/api/${req.params.path}`;
    const ollamaUrl = `${ollamaBaseUrl}${ollamaPath}`;
    log(`Proxy: ${req.method} ${ollamaUrl}`, 'debug');
    
    const response = await axios({
      method: req.method,
      url: ollamaUrl,
      data: req.method !== 'GET' ? req.body : undefined,
      headers: { 'Content-Type': 'application/json' },
    });
    
    res.status(response.status).json(response.data);
  } catch (error) {
    log(`Proxy-Fehler: ${error.message}`, 'error');
    res.status(error.response?.status || 500).json(
      error.response?.data || { error: error.message }
    );
  }
});

// Server starten
app.listen(port, async () => {
  log(`RAG-Gateway läuft auf Port ${port}`, 'info');
  log(`Ollama-URL: ${ollamaBaseUrl}, Elasticsearch: ${elasticUrl}`, 'info');
  
  // Teste Ollama-Verbindung
  try {
    const versionResponse = await axios.get(`${ollamaBaseUrl}/api/version`);
    log(`Ollama ist erreichbar, Version: ${versionResponse.data.version}`, 'info');
    await checkOllamaVersion();
  } catch (error) {
    log(`Ollama ist nicht erreichbar: ${error.message}`, 'error');
  }
  
  // Elasticsearch aufsetzen
  setTimeout(async () => {
    try {
      await setupElasticsearch();
    } catch (e) {
      log(`Elasticsearch-Setup fehlgeschlagen: ${e.message}`, 'warn');
    }
  }, 5000);
});