terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

# Lokale Variablen
locals {
  container_name = "ollama-elastic-integration"
  image_name     = "node:18-alpine"
  network_name   = var.network_name != "" ? var.network_name : "ollama-network"
}

# Docker Netzwerk erstellen, falls es nicht bereits existiert
resource "docker_network" "ollama_network" {
  count = var.create_network ? 1 : 0
  name  = local.network_name
}

# Docker Container für die Integration
resource "docker_container" "integration" {
  name  = local.container_name
  image = local.image_name
  
  # Starte den Container nur, wenn er nicht bereits läuft
  restart = "unless-stopped"
  
  # Netzwerkeinstellungen
  networks_advanced {
    name = var.create_network ? docker_network.ollama_network[0].name : local.network_name
  }
  
  # Umgebungsvariablen
  env = [
    "ELASTICSEARCH_HOST=http://${var.elasticsearch_host}:9200",
    "OLLAMA_API_URL=http://${var.ollama_host}:11434/v1/chat/completions",
    "MODEL_NAME=${var.model_name}",
    "INDEX_NAME=${var.index_name}"
  ]
  
  # Gespeicherte Dateien in den Container kopieren
  upload {
    content = file("${path.module}/files/package.json")
    file    = "/app/package.json"
  }
  
  upload {
    content = file("${path.module}/files/ollama-elastic-integration.js")
    file    = "/app/ollama-elastic-integration.js"
  }
  
  # Befehl zum Starten des Containers
  command = [
    "/bin/sh", 
    "-c", 
    "cd /app && npm install && node ollama-elastic-integration.js"
  ]
  
  # Volume für persistente Daten
  volumes {
    container_path = "/app/data"
    host_path      = var.data_path
  }
}
