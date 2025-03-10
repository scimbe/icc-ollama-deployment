terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {
  # Linux
  #host = "unix:///var/run/docker.sock"
  
  # macOS
  host = "unix:///Users/martin/.colima/default/docker.sock"
  
  # Windows
  # host = "npipe:////.//pipe//docker_engine"
}

# Docker-Netzwerk für RAG-Komponenten
resource "docker_network" "rag_network" {
  name = "rag-network"
}

# Elasticsearch Container
resource "docker_image" "elasticsearch_image" {
  name = "docker.elastic.co/elasticsearch/elasticsearch:8.11.1"
  pull_triggers = [
    sha256(timestamp())
  ]
}

resource "docker_container" "elasticsearch_container" {
  image = docker_image.elasticsearch_image.name
  name  = "elasticsearch"
  
  networks_advanced {
    name = docker_network.rag_network.name
  }
  
  ports {
    internal = 9200
    external = 9200
    protocol = "tcp"
  }
  
  ports {
    internal = 9300
    external = 9300
    protocol = "tcp"
  }
  
  env = [
    "discovery.type=single-node",
    "xpack.security.enabled=false",
    "ES_JAVA_OPTS=-Xms512m -Xmx512m"
  ]
  
  restart = "unless-stopped"
  
  volumes {
    container_path = "/usr/share/elasticsearch/data"
    host_path      = "${path.cwd}/elasticsearch-data"
  }
}

# Kibana Container
resource "docker_image" "kibana_image" {
  name = "docker.elastic.co/kibana/kibana:8.11.1"
  pull_triggers = [
    sha256(timestamp())
  ]
}

resource "docker_container" "kibana_container" {
  image = docker_image.kibana_image.name
  name  = "kibana"
  
  networks_advanced {
    name = docker_network.rag_network.name
  }
  
  ports {
    internal = 5601
    external = 5601
    protocol = "tcp"
  }
  
  env = [
    "ELASTICSEARCH_HOSTS=http://elasticsearch:9200"
  ]
  
  restart = "unless-stopped"
  
  depends_on = [
    docker_container.elasticsearch_container
  ]
}

# RAG-Gateway Container
resource "docker_image" "rag_gateway_image" {
  name = "ollama-rag-gateway:latest"
  build {
    path = "${path.cwd}/../rag/gateway"
    tag  = ["ollama-rag-gateway:latest"]
  }
}

resource "docker_container" "rag_gateway_container" {
  image = docker_image.rag_gateway_image.name
  name  = "rag-gateway"
  
  networks_advanced {
    name = docker_network.rag_network.name
  }
  
  ports {
    internal = 3100
    external = 3100
    protocol = "tcp"
  }
  
  env = [
    "OLLAMA_BASE_URL=http://host.docker.internal:11434",
    "ELASTICSEARCH_URL=http://elasticsearch:9200",
    "ELASTICSEARCH_INDEX=ollama-rag",
    "PORT=3100"
  ]
  
  restart = "unless-stopped"
  
  depends_on = [
    docker_container.elasticsearch_container
  ]
  
  # Für Docker Desktop und Linux
  extra_hosts = [
    "host.docker.internal:host-gateway"
  ]
}

# Ollama WebUI Container konfiguriert für das Gateway
resource "docker_image" "ollama_webui_image" {
  name = "ghcr.io/open-webui/open-webui:main"
  pull_triggers = [
    sha256(timestamp())
  ]
}

resource "docker_container" "ollama_webui_container" {
  image = docker_image.ollama_webui_image.name
  name  = "open-webui"
  
  networks_advanced {
    name = docker_network.rag_network.name
  }
  
  ports {
    internal = 8080
    external = 3000
    protocol = "tcp"
  }
  
  env = [
    "OLLAMA_API_BASE_URL=http://rag-gateway:3100/api"
  ]
  
  restart = "unless-stopped"
  
  depends_on = [
    docker_container.rag_gateway_container
  ]
}

# Outputs
output "elasticsearch_url" {
  value = "http://localhost:9200"
  description = "URL zum Zugriff auf Elasticsearch"
}

output "kibana_url" {
  value = "http://localhost:5601"
  description = "URL zum Zugriff auf Kibana"
}

output "rag_gateway_url" {
  value = "http://localhost:3100"
  description = "URL zum Zugriff auf das RAG-Gateway"
}

output "webui_url" {
  value = "http://localhost:3000"
  description = "URL zum Zugriff auf die Ollama WebUI"
}
