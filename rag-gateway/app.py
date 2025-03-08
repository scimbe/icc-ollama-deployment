import logging
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import httpx
import uvicorn
from elasticsearch import Elasticsearch
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import os
import json
from datetime import datetime

# Konfiguration über Umgebungsvariablen
ELASTICSEARCH_HOST = os.getenv("ELASTICSEARCH_HOST", "http://localhost:9200")
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3")
INDEX_NAME = os.getenv("INDEX_NAME", "ollama-responses")

# Logging konfigurieren
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# App initialisieren
app = FastAPI(title="Open RAG Gateway", 
              description="Ein einfaches API-Gateway für RAG mit Ollama und Elasticsearch")

# CORS konfigurieren
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Elasticsearch-Client
es_client = Elasticsearch(ELASTICSEARCH_HOST)

# Modelle für die API
class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    model: str
    messages: List[ChatMessage]
    use_rag: Optional[bool] = False
    search_term: Optional[str] = None
    temperature: Optional[float] = 0.7

class SearchRequest(BaseModel):
    query: str
    max_results: Optional[int] = 5

# Elasticsearch-Indexverwaltung
async def ensure_index_exists():
    """Stellt sicher, dass der Elasticsearch-Index existiert"""
    if not es_client.indices.exists(index=INDEX_NAME):
        logger.info(f"Erstelle Index {INDEX_NAME}")
        es_client.indices.create(
            index=INDEX_NAME,
            body={
                "mappings": {
                    "properties": {
                        "prompt": {"type": "text"},
                        "response": {"type": "object"},
                        "model": {"type": "keyword"},
                        "timestamp": {"type": "date"},
                        "content_text": {"type": "text"}
                    }
                }
            }
        )
        logger.info(f"Index {INDEX_NAME} erstellt")

# Ollama-API-Funktionen
async def query_ollama(messages, model=OLLAMA_MODEL, temperature=0.7):
    """Sendet eine Anfrage an die Ollama-API"""
    async with httpx.AsyncClient() as client:
        try:
            logger.info(f"Sende Anfrage an Ollama für Modell {model}")
            response = await client.post(
                f"{OLLAMA_API_URL}/chat",
                json={
                    "model": model,
                    "messages": [{"role": m.role, "content": m.content} for m in messages],
                    "options": {"temperature": temperature}
                },
                timeout=60.0
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as e:
            logger.error(f"Fehler bei der Anfrage an Ollama: {e}")
            raise HTTPException(status_code=500, detail=f"Ollama API Fehler: {str(e)}")

async def search_in_elasticsearch(query, max_results=5):
    """Sucht nach relevanten Dokumenten in Elasticsearch"""
    try:
        result = es_client.search(
            index=INDEX_NAME,
            body={
                "query": {
                    "multi_match": {
                        "query": query,
                        "fields": ["prompt", "content_text"]
                    }
                },
                "sort": [{"timestamp": {"order": "desc"}}],
                "size": max_results
            }
        )
        
        hits = result["hits"]["hits"]
        logger.info(f"{len(hits)} Ergebnisse für \"{query}\" gefunden")
        return hits
    except Exception as e:
        logger.error(f"Fehler bei der Suche in Elasticsearch: {e}")
        return []

async def save_to_elasticsearch(prompt, response_json, model):
    """Speichert die Antwort in Elasticsearch"""
    try:
        # Extrahiere den Antworttext
        content_text = ""
        if response_json and "message" in response_json:
            content_text = response_json["message"]["content"]
        
        # Speichere in Elasticsearch
        es_client.index(
            index=INDEX_NAME,
            body={
                "prompt": prompt,
                "response": response_json,
                "model": model,
                "timestamp": datetime.now(),
                "content_text": content_text
            }
        )
        logger.info(f"Antwort für Prompt '{prompt[:30]}...' in Elasticsearch gespeichert")
        return True
    except Exception as e:
        logger.error(f"Fehler beim Speichern in Elasticsearch: {e}")
        return False

# API-Endpunkte
@app.get("/")
async def root():
    return {"message": "Open RAG Gateway API ist aktiv. Weitere Infos unter /docs"}

@app.post("/v1/chat/completions")
async def chat_completions(request: ChatRequest):
    """
    Sendet eine Chat-Anfrage an Ollama und speichert die Antwort in Elasticsearch.
    
    Wenn use_rag=True, wird zuvor in Elasticsearch nach relevantem Kontext gesucht.
    """
    await ensure_index_exists()
    
    # Extrahiere den letzten Prompt
    last_message = request.messages[-1]
    last_prompt = last_message.content
    
    # RAG-Modus
    if request.use_rag:
        search_term = request.search_term or last_prompt
        search_results = await search_in_elasticsearch(search_term)
        
        if search_results:
            # Erstelle Kontext aus den gefundenen Dokumenten
            context = "Kontext aus früheren Antworten:\n\n"
            for idx, result in enumerate(search_results):
                source = result["_source"]
                context += f"[{idx+1}] Frage: {source.get('prompt', 'Keine Frage')}\n"
                context += f"Antwort: {source.get('content_text', 'Keine Antwort')}\n\n"
            
            # Füge Kontext-Nachricht hinzu
            context_message = ChatMessage(role="user", content=context)
            prompt_message = ChatMessage(
                role="user", 
                content=f"Basierend auf dem obigen Kontext, bitte beantworte: {last_prompt}"
            )
            
            # Ersetze die letzte Nachricht durch Kontext + Prompt
            request.messages = request.messages[:-1] + [context_message, prompt_message]
    
    # Anfrage an Ollama senden
    response = await query_ollama(
        request.messages, 
        model=request.model, 
        temperature=request.temperature
    )
    
    # Antwort in Elasticsearch speichern
    await save_to_elasticsearch(last_prompt, response, request.model)
    
    return response

@app.post("/search")
async def search(request: SearchRequest):
    """Sucht nach relevanten Dokumenten in Elasticsearch"""
    await ensure_index_exists()
    results = await search_in_elasticsearch(request.query, request.max_results)
    
    return {
        "results": [
            {
                "prompt": item["_source"].get("prompt", ""),
                "response": item["_source"].get("content_text", ""),
                "model": item["_source"].get("model", ""),
                "timestamp": item["_source"].get("timestamp", "")
            }
            for item in results
        ]
    }

@app.get("/health")
async def health_check():
    """Überprüft den Gesundheitszustand des Services"""
    es_health = {"status": "unknown"}
    
    try:
        es_health = es_client.cluster.health()
    except Exception as e:
        return {"status": "unhealthy", "elasticsearch": str(e)}
    
    # Ollama Healthcheck
    ollama_health = "unknown"
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(f"{OLLAMA_API_URL}/tags")
            if response.status_code == 200:
                ollama_health = "healthy"
            else:
                ollama_health = f"unhealthy: HTTP {response.status_code}"
        except Exception as e:
            ollama_health = f"unhealthy: {str(e)}"
    
    return {
        "status": "healthy" if es_health.get("status") in ["green", "yellow"] and ollama_health == "healthy" else "unhealthy",
        "elasticsearch": es_health,
        "ollama": ollama_health
    }

# Hauptfunktion für den Standalone-Betrieb
if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    
    logger.info(f"Starte Open RAG Gateway auf {host}:{port}")
    logger.info(f"Elasticsearch: {ELASTICSEARCH_HOST}")
    logger.info(f"Ollama API: {OLLAMA_API_URL}")
    logger.info(f"Standardmodell: {OLLAMA_MODEL}")
    
    uvicorn.run(app, host=host, port=port)
