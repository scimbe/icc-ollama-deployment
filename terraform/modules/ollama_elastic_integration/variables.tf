variable "elasticsearch_host" {
  description = "Hostname oder IP-Adresse des Elasticsearch-Servers"
  type        = string
  default     = "elasticsearch"
}

variable "ollama_host" {
  description = "Hostname oder IP-Adresse des Ollama-Servers"
  type        = string
  default     = "ollama"
}

variable "model_name" {
  description = "Name des zu verwendenden LLM-Modells"
  type        = string
  default     = "llama3"
}

variable "index_name" {
  description = "Name des Elasticsearch-Index für die Speicherung von Antworten"
  type        = string
  default     = "ollama-responses"
}

variable "data_path" {
  description = "Pfad auf dem Host für persistente Daten"
  type        = string
  default     = "/tmp/ollama-elastic-integration-data"
}

variable "network_name" {
  description = "Name des Docker-Netzwerks, das verwendet werden soll"
  type        = string
  default     = ""
}

variable "create_network" {
  description = "Ob ein neues Docker-Netzwerk erstellt werden soll"
  type        = bool
  default     = true
}
