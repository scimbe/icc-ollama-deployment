const axios = require('axios');
const { Client } = require('@elastic/elasticsearch');

// Konfiguration über Umgebungsvariablen
const ELASTICSEARCH_HOST = process.env.ELASTICSEARCH_HOST || 'http://localhost:9200';
const OLLAMA_API_URL = process.env.OLLAMA_API_URL || 'http://localhost:11434/v1/chat/completions';
const MODEL_NAME = process.env.MODEL_NAME || 'phi4';
const INDEX_NAME = process.env.INDEX_NAME || 'ollama-responses';

// Elasticsearch-Client konfigurieren
const elasticClient = new Client({ node: ELASTICSEARCH_HOST });

// Funktion zum Abrufen einer Antwort von Ollama
async function queryOllama(prompt) {
    console.log(`Sende Anfrage an Ollama mit Prompt: "${prompt}"`);
    try {
        const response = await axios.post(OLLAMA_API_URL, {
            model: MODEL_NAME,
            messages: [{ role: 'user', content: prompt }],
        });
        console.log('Antwort von Ollama erhalten');
        return response.data;
    } catch (error) {
        console.error('Fehler bei der Anfrage an Ollama:', error.message);
        if (error.response) {
            console.error('Antwortdaten:', error.response.data);
            console.error('Antwortstatus:', error.response.status);
        }
        return null;
    }
}

// Funktion zum Speichern der Antwort in Elasticsearch
async function saveToElasticsearch(prompt, response) {
    try {
        // Prüfe, ob der Index existiert, andernfalls erstelle ihn
        const indexExists = await elasticClient.indices.exists({ index: INDEX_NAME });
        
        if (!indexExists) {
            console.log(`Index ${INDEX_NAME} existiert nicht. Erstelle ihn...`);
            await elasticClient.indices.create({
                index: INDEX_NAME,
                body: {
                    mappings: {
                        properties: {
                            prompt: { type: 'text' },
                            response: { type: 'object' },
                            modelName: { type: 'keyword' },
                            timestamp: { type: 'date' },
                            contentText: { type: 'text' }
                        }
                    }
                }
            });
            console.log(`Index ${INDEX_NAME} erstellt.`);
        }
        
        // Extrahiere den Antworttext aus der Ollama-Antwort
        let contentText = '';
        if (response && response.choices && response.choices.length > 0) {
            contentText = response.choices[0].message.content;
        }
        
        // Speichere in Elasticsearch
        await elasticClient.index({
            index: INDEX_NAME,
            body: {
                prompt,
                response,
                modelName: MODEL_NAME,
                timestamp: new Date(),
                contentText
            },
        });
        console.log('Antwort erfolgreich in Elasticsearch gespeichert.');
    } catch (error) {
        console.error('Fehler beim Speichern in Elasticsearch:', error);
    }
}

// Funktion zur Suche in Elasticsearch mit einem Schlüsselwort
async function searchInElasticsearch(keyword) {
    try {
        const result = await elasticClient.search({
            index: INDEX_NAME,
            body: {
                query: {
                    multi_match: {
                        query: keyword,
                        fields: ['prompt', 'contentText']
                    }
                },
                sort: [
                    { timestamp: { order: 'desc' } }
                ],
                size: 5
            }
        });
        
        console.log(`${result.hits.total.value} Ergebnisse für "${keyword}" gefunden`);
        return result.hits.hits;
    } catch (error) {
        console.error('Fehler bei der Suche in Elasticsearch:', error);
        return [];
    }
}

// RAG-Funktion (Retrieval-Augmented Generation)
async function performRAG(prompt, searchTerm) {
    try {
        // 1. Abrufen relevanter Dokumente aus Elasticsearch
        const searchResults = await searchInElasticsearch(searchTerm || prompt);
        
        // 2. Erstellen eines Kontexts aus den gefundenen Dokumenten
        let context = '';
        if (searchResults.length > 0) {
            context = 'Kontext aus früheren Antworten:\n\n';
            searchResults.forEach((result, index) => {
                context += `[${index + 1}] Frage: ${result._source.prompt}\n`;
                context += `Antwort: ${result._source.contentText}\n\n`;
            });
        }
        
        // 3. Anfrage an Ollama mit dem erweiterten Kontext
        const enhancedPrompt = context ? 
            `${context}\nBasierend auf diesem Kontext, bitte beantworte: ${prompt}` : 
            prompt;
            
        const response = await queryOllama(enhancedPrompt);
        
        // 4. Speichern der Antwort
        if (response) {
            await saveToElasticsearch(prompt, response);
        }
        
        return response;
    } catch (error) {
        console.error('Fehler bei RAG-Verarbeitung:', error);
        return null;
    }
}

// Hauptfunktion zur Verarbeitung eines Prompts
async function processPrompt(prompt, useRAG = false, searchTerm = null) {
    if (useRAG) {
        return await performRAG(prompt, searchTerm);
    } else {
        const response = await queryOllama(prompt);
        if (response) {
            await saveToElasticsearch(prompt, response);
        }
        return response;
    }
}

// Beispielaufruf der Hauptfunktion
async function runExample() {
    try {
        // Prüfe Verbindung zu Elasticsearch
        console.log(`Prüfe Verbindung zu Elasticsearch (${ELASTICSEARCH_HOST})...`);
        
        // Warte auf Elasticsearch-Verfügbarkeit
        let elasticsearchReady = false;
        let retries = 0;
        const maxRetries = 30;
        
        while (!elasticsearchReady && retries < maxRetries) {
            try {
                const health = await elasticClient.cluster.health();
                console.log('Elasticsearch-Status:', health.status);
                elasticsearchReady = true;
            } catch (error) {
                console.log(`Warte auf Elasticsearch... (${retries + 1}/${maxRetries})`);
                await new Promise(resolve => setTimeout(resolve, 5000));
                retries++;
            }
        }
        
        if (!elasticsearchReady) {
            console.error('Elasticsearch ist nicht erreichbar nach mehreren Versuchen.');
            return;
        }
        
        // Verarbeite einen einfachen Prompt
        const userPrompt = 'Was ist künstliche Intelligenz?';
        console.log(`Verarbeite Prompt: "${userPrompt}"`);
        
        const response = await processPrompt(userPrompt);
        
        if (response && response.choices && response.choices.length > 0) {
            console.log('Antwort von Ollama:', response.choices[0].message.content);
        }
        
        // Optional: RAG-Beispiel ausführen
        if (process.argv.includes('--rag')) {
            console.log('\n--- RAG-Beispiel ---');
            const ragPrompt = 'Welche Anwendungen hat KI in der Medizin?';
            console.log(`Verarbeite RAG-Prompt: "${ragPrompt}"`);
            
            const ragResponse = await processPrompt(ragPrompt, true);
            
            if (ragResponse && ragResponse.choices && ragResponse.choices.length > 0) {
                console.log('RAG-Antwort von Ollama:', ragResponse.choices[0].message.content);
            }
        }
        
        console.log('Skript wurde erfolgreich ausgeführt.');
        
        // Starte periodische Abfragen alle 5 Minuten
        setInterval(async () => {
            try {
                const topics = [
                    "Künstliche Intelligenz und Ethik",
                    "Maschinelles Lernen in der Praxis",
                    "Neuronale Netze erklären",
                    "Geschichte der KI-Forschung",
                    "KI in der Medizin"
                ];
                const randomPrompt = topics[Math.floor(Math.random() * topics.length)];
                console.log(`\n[${new Date().toISOString()}] Periodische Abfrage: "${randomPrompt}"`);
                
                const periodicResponse = await processPrompt(randomPrompt, Math.random() > 0.5);
                
                if (periodicResponse && periodicResponse.choices && periodicResponse.choices.length > 0) {
                    console.log('Antwort:', periodicResponse.choices[0].message.content.substring(0, 100) + '...');
                }
            } catch (error) {
                console.error('Fehler bei periodischer Abfrage:', error);
            }
        }, 5 * 60 * 1000); // 5 Minuten
        
    } catch (error) {
        console.error('Fehler bei der Ausführung:', error);
    }
}

// Führe das Skript aus, wenn es direkt aufgerufen wird
if (require.main === module) {
    console.log('Ollama-Elasticsearch-Integration gestartet.');
    console.log('Konfiguration:');
    console.log('- ELASTICSEARCH_HOST:', ELASTICSEARCH_HOST);
    console.log('- OLLAMA_API_URL:', OLLAMA_API_URL);
    console.log('- MODEL_NAME:', MODEL_NAME);
    console.log('- INDEX_NAME:', INDEX_NAME);
    
    runExample().catch(error => {
        console.error('Fehler beim Ausführen des Beispiels:', error);
    });
}

// Exportiere Funktionen für die Verwendung als Modul
module.exports = {
    queryOllama,
    saveToElasticsearch,
    searchInElasticsearch,
    performRAG,
    processPrompt
};
