output "container_id" {
  description = "ID des erstellten Docker-Containers"
  value       = docker_container.integration.id
}

output "container_name" {
  description = "Name des erstellten Docker-Containers"
  value       = docker_container.integration.name
}

output "network_id" {
  description = "ID des verwendeten Docker-Netzwerks"
  value       = var.create_network ? docker_network.ollama_network[0].id : null
}

output "network_name" {
  description = "Name des verwendeten Docker-Netzwerks"
  value       = var.create_network ? docker_network.ollama_network[0].name : var.network_name
}
