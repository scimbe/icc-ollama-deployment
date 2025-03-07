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

# Ollama-WebUI image als Frontend für Ollama
resource "docker_image" "ollama_webui_image" {
  name = "ghcr.io/open-webui/open-webui:main"
  pull_triggers = [
    sha256(timestamp())
  ]
}

resource "docker_container" "ollama_webui_container" {
  image = docker_image.ollama_webui_image.name
  name  = "open-webui"
  ports {
    internal = 8080
    external = 3000
    protocol = "tcp"
  }
  
  # Verbindung zu einem lokalen Ollama-Server oder zum Kubernetes-Service via Port-Forwarding
  env = [
    # "OLLAMA_BASE_URL=http://127.0.0.1:11434/" # Für Docker Desktop auf macOS und Windows
    # "OLLAMA_BASE_URL=http://172.17.0.1:11434/" # Für standard Docker Bridge Network auf Linux
  ]
  
  # Stellt sicher, dass der Container nach einem Neustart wieder gestartet wird
  restart = "unless-stopped"
}

# Output zur Anzeige der URLs
output "webui_url" {
  value = "http://localhost:3000"
  description = "URL zum Zugriff auf die Ollama WebUI"
}

#output "api_url" {
#  value = "http://127.0.0.1:11434"
#  description = "URL zum Zugriff auf die Ollama API (muss separat bereitgestellt werden)"
#}
