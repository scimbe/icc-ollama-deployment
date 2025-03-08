# Integration von Ollama mit Elasticsearch (lokal mit Docker)

module "ollama_elastic_integration" {
  source = "./modules/ollama_elastic_integration"

  # Verbindungsdetails
  elasticsearch_host = "localhost"  # Anpassbar je nach Netzwerkkonfiguration
  ollama_host        = "localhost"  # Anpassbar je nach Netzwerkkonfiguration
  
  # Modell- und Indexname
  model_name = "llama3"            # Modell, das in Ollama geladen ist
  index_name = "ollama-responses"  # Name des Elasticsearch-Index
  
  # Pfad für persistente Daten
  data_path = "/tmp/ollama-elastic-integration-data"
  
  # Netzwerkkonfiguration
  network_name   = "ollama-network"
  create_network = true
}

# Ausgaben
output "integration_container_id" {
  description = "ID des Docker-Containers für die Integration"
  value       = module.ollama_elastic_integration.container_id
}

output "integration_container_name" {
  description = "Name des Docker-Containers für die Integration"
  value       = module.ollama_elastic_integration.container_name
}

output "integration_network_name" {
  description = "Name des Docker-Netzwerks für die Integration"
  value       = module.ollama_elastic_integration.network_name
}
