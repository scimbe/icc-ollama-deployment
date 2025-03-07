# ICC Ollama Deployment

Automatisierte Bereitstellung von Ollama mit GPU-Unterstützung auf der HAW Hamburg Informatik Compute Cloud (ICC).

## Übersicht

Dieses Repository enthält Scripts und Konfigurationsdateien, um Ollama mit GPU-Unterstützung auf der ICC der HAW Hamburg zu deployen. Zusätzlich wird ein Ollama WebUI als Benutzeroberfläche bereitgestellt.

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [Schnellstart](#schnellstart)
- [Detaillierte Anleitung](#detaillierte-anleitung)
- [Komponenten](#komponenten)
- [Troubleshooting](#troubleshooting)
- [Wartung](#wartung)
- [Lizenz](#lizenz)

## Voraussetzungen

- HAW Hamburg infw-Account mit Zugang zur ICC
- kubectl installiert
- Terraform installiert (für WebUI-Deployment)
- Eine aktive VPN-Verbindung zum HAW-Netz (wenn außerhalb des HAW-Netzes)
- (Optional) Make installiert für vereinfachte Befehle

## Schnellstart

```bash
# Repository klonen
git clone <repository-url>
cd icc-ollama-deployment

# Konfiguration anpassen
cp configs/config.example.sh configs/config.sh
vim configs/config.sh  # Passen Sie Ihre Namespace-Informationen an

# Deployment ausführen
./deploy.sh
```

Oder mit Make:

```bash
make deploy
```

## Detaillierte Anleitung

Eine ausführliche Schritt-für-Schritt-Anleitung finden Sie in der [DOCUMENTATION.md](DOCUMENTATION.md) Datei.
