FROM python:3.11-slim

WORKDIR /app

# Installiere Abhängigkeiten
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Kopiere Anwendungscode
COPY app.py .

# Port freigeben
EXPOSE 8000

# Starte die Anwendung
CMD ["python", "app.py"]
