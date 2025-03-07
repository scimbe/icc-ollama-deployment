# Terraform-Konfiguration für Ollama WebUI

Diese Terraform-Konfiguration ermöglicht es, die Open WebUI für Ollama lokal zu deployen und mit einem Ollama-Server zu verbinden.

## Voraussetzungen

- Terraform installiert (v1.0.0 oder höher)
- Docker installiert und laufend
- Ollama muss separat ausgeführt werden (entweder lokal oder auf der ICC)

## Verwendung

### 1. Konfiguration anpassen

Passen Sie bei Bedarf die Konfiguration in `main.tf` an:

- Prüfen Sie den `docker.host`-Pfad für Ihr Betriebssystem und kommentieren Sie die richtige Zeile ein
- Passen Sie die Umgebungsvariable `OLLAMA_API_BASE_URL` an die URL Ihres Ollama-Servers an

### 2. Terraform initialisieren

```bash
terraform init
```

### 3. Konfiguration anwenden

```bash
terraform apply
```

### 4. Zugriff auf die WebUI

Nach erfolgreicher Ausführung können Sie die WebUI unter http://localhost:8080 aufrufen.

### 5. Aufräumen

Um alle erstellten Ressourcen zu entfernen:

```bash
terraform destroy
```

## Hinweise

- Diese Konfiguration ist vor allem für die lokale Entwicklung und Tests gedacht.
- Für die Produktionsumgebung auf der ICC empfehlen wir, die Kubernetes-Deployment-Option zu verwenden.
- Die WebUI benötigt Zugriff auf einen laufenden Ollama-Server. Stellen Sie sicher, dass dieser verfügbar ist, bevor Sie die WebUI starten.