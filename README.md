# Ollama Installation und Dokumentation

Dieses Repository enthält Scripts und Konfigurationsdateien, um Ollama mit GPU-Unterstützung auf der ICC der HAW Hamburg zu deployen. Zusätzlich wird ein Ollama WebUI als Benutzeroberfläche bereitgestellt sowie Funktionen zur Anpassung der Modelle an spezifische Anwendungsfälle.

## Inhaltsverzeichnis

- [Voraussetzungen](#voraussetzungen)
- [ICC-Zugang einrichten](#icc-zugang-einrichten)
- [Schnellstart](#schnellstart)
- [Detaillierte Anleitung](#detaillierte-anleitung)
- [GPU-Ressourcen skalieren](#gpu-ressourcen-skalieren)
- [GPU-Testen und Überwachen](#gpu-testen-und-überwachen)
- [Architektur](#architektur)
- [Troubleshooting](#troubleshooting)
- [Wartung](#wartung)
- [Lizenz](#lizenz)


## Voraussetzungen

- HAW Hamburg infw-Account mit Zugang zur ICC
- kubectl installiert
- (Optional) Terraform installiert (Nur für das lokale WebUI-Deployment)
- Eine aktive VPN-Verbindung zum HAW-Netz (wenn außerhalb des HAW-Netzes)
- (Optional) Make installiert für vereinfachte Befehle
- (Optional) IntelliJ IDEA für die erweiterte IDE-Integration

## ICC-Zugang einrichten

Bevor Sie beginnen können, müssen Sie sich bei der ICC anmelden und Ihre Kubeconfig-Datei einrichten. Dazu stellen wir ein Hilfsskript bereit:

```bash
# Öffnet den Browser mit der ICC-Login-Seite und führt Sie durch die Einrichtung
./scripts/icc-login.sh
```

Dieses Skript führt Sie durch den gesamten Prozess:
1. Öffnet die ICC-Login-Seite in Ihrem Standard-Browser
2. Führt Sie durch den Anmeldeprozess mit Ihrer infw-Kennung
3. Hilft beim Speichern und Einrichten der heruntergeladenen Kubeconfig-Datei
4. Testet die Verbindung und zeigt Ihre Namespace-Informationen an

Alternativ können Sie die [manuelle Einrichtung](DOCUMENTATION.md#1-icc-zugang-einrichten) durchführen.

## Schnellstart

```bash
# Repository klonen
git clone <repository-url>
cd icc-ollama-deployment

# ICC-Zugang einrichten (falls noch nicht geschehen)
./scripts/icc-login.sh

# Konfiguration anpassen
cp configs/config.example.sh configs/config.sh
vim configs/config.sh  # Passen Sie Ihre Namespace-Informationen an

# Ausführungsberechtigungen für Skripte setzen
./scripts/set-permissions.sh

# Deployment ausführen
./deploy.sh
```

Oder mit Make:

```bash
make deploy
```

## Detaillierte Anleitung

Eine ausführliche Schritt-für-Schritt-Anleitung finden Sie in der [DOCUMENTATION.md](DOCUMENTATION.md) Datei.

## GPU-Ressourcen skalieren

Um die Performance zu optimieren oder größere Modelle zu unterstützen, können Sie die Anzahl der GPUs dynamisch anpassen:

```bash
# Skalieren auf 2 GPUs für verbesserte Performance
./scripts/scale-gpu.sh --count 2

# Reduzieren auf 1 GPU, wenn nicht alle Ressourcen benötigt werden
./scripts/scale-gpu.sh --count 1
```

Weitere Details zur GPU-Skalierung finden Sie in der [ausführlichen Dokumentation](DOCUMENTATION.md#7-gpu-ressourcen-skalieren).

## GPU-Testen und Überwachen

Das Projekt enthält verschiedene Skripte zum Testen, Überwachen und Benchmarken der GPU-Funktionalität:

### GPU-Funktionalität testen

Überprüfen Sie, ob die GPU korrekt eingerichtet ist und von Ollama genutzt wird:

```bash
./scripts/test-gpu.sh
# oder
make gpu-test
```

### GPU-Auslastung überwachen

Überwachen Sie die GPU-Auslastung in Echtzeit:

```bash
./scripts/monitor-gpu.sh
# oder
make gpu-monitor
```

Mit Optionen für kontinuierliche Überwachung oder CSV-Export:

```bash
# 10 Messungen im 5-Sekunden-Intervall
./scripts/monitor-gpu.sh -i 5 
```

### GPU-Benchmarks durchführen

Führen Sie Leistungstests für ein spezifisches Modell durch:

```bash
./scripts/benchmark-gpu.sh llama3:8b
# oder
make gpu-bench MODEL=llama3:8b
```

### GPU-Kompatibilität prüfen

Überprüfen Sie die vollständige GPU-Konfiguration und -Kompatibilität:

```bash
./scripts/check-gpu-compatibility.sh
# oder
make gpu-compat
```

## Architektur

Einen Überblick über die Systemarchitektur und die Komponenten des Projekts finden Sie in der [ARCHITECTURE.md](ARCHITECTURE.md) Datei.

## Troubleshooting

Bei Problemen mit der GPU-Funktionalität oder Modellanpassung können folgende Schritte helfen:

1. Überprüfen Sie die GPU-Kompatibilität: `make gpu-compat`
2. Testen Sie die GPU-Funktionalität: `make gpu-test`
3. Überprüfen Sie die Deployment-Konfiguration: `kubectl -n $NAMESPACE get deployment $OLLAMA_DEPLOYMENT_NAME -o yaml`
4. Prüfen Sie die Logs des Ollama-Pods: `make logs`
5. Öffnen Sie eine Shell im Pod: `make shell`

Weitere Informationen zur Fehlerbehebung finden Sie in der [DOCUMENTATION.md](DOCUMENTATION.md#9-fehlerbehebung).

## Wartung

Die Funktionen für GPU-Tests, Monitoring und Modellanpassung ermöglichen ein kontinuierliches Management Ihrer Ollama-Instanz, um sicherzustellen, dass sie optimal mit den verfügbaren Ressourcen arbeitet und an Ihre spezifischen Anforderungen angepasst ist.

