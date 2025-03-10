#!/bin/bash

# Skript zum Erstellen von benutzerdefinierten Modelfile-Templates für Ollama
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN] [TEMPLATE_NAME]"
    echo
    echo "Erstellt ein benutzerdefiniertes Modelfile-Template für Ollama"
    echo
    echo "Optionen:"
    echo "  -h, --help            Diese Hilfe anzeigen"
    echo "  -o, --output DIR      Ausgabeverzeichnis (Standard: templates/)"
    echo "  -t, --type TYPE       Templatetyp: academic, chat, coding, assistance (Standard: assistance)"
    echo "  -l, --language LANG   Hauptsprache: en, de (Standard: de)"
    echo
    echo "TEMPLATE_NAME ist der Name für das Template (Standard: custom_template)"
    echo
    echo "Beispiel:"
    echo "  $0 -t academic -l de haw_template"
    exit 0
}

# Standardwerte
OUTPUT_DIR="$ROOT_DIR/templates"
TEMPLATE_TYPE="assistance"
LANGUAGE="de"
TEMPLATE_NAME="custom_template"

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -t|--type)
            TEMPLATE_TYPE="$2"
            shift 2
            ;;
        -l|--language)
            LANGUAGE="$2"
            shift 2
            ;;
        *)
            TEMPLATE_NAME="$1"
            shift
            ;;
    esac
done

# Erstelle Ausgabeverzeichnis, falls nicht vorhanden
mkdir -p "$OUTPUT_DIR"

# Ausgabedatei
OUTPUT_FILE="$OUTPUT_DIR/${TEMPLATE_NAME}.modelfile"

echo -e "${GREEN}=== Erstelle Modelfile-Template ===${NC}"
echo "Name: $TEMPLATE_NAME"
echo "Typ: $TEMPLATE_TYPE"
echo "Sprache: $LANGUAGE"
echo "Ausgabedatei: $OUTPUT_FILE"

# Basis-Template erstellen
case "$TEMPLATE_TYPE" in
    academic)
        if [ "$LANGUAGE" == "de" ]; then
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
Du bist ein KI-Assistent der HAW Hamburg mit Fokus auf akademische Fragen. 
Du antwortest im Stil eines Professors, präzise und wissenschaftlich fundiert.
Deine Antworten sind gut strukturiert und enthalten bei Bedarf Quellenangaben.
Du hältst dich streng an wissenschaftliche Fakten und kennzeichnest Spekulationen klar als solche.

Wenn du nach mathematischen Formeln gefragt wirst, gibst du diese in LaTeX-Syntax an.
Bei Programmcode achtest du auf korrekte Syntax und fügt hilfreiche Kommentare hinzu.

In deiner Kommunikation bist du höflich, aber fokussiert auf den akademischen Inhalt.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.7
EOF
        else
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
You are an AI assistant for HAW Hamburg with focus on academic questions.
You answer in the style of a professor, precise and scientifically sound.
Your answers are well-structured and include references when needed.
You adhere strictly to scientific facts and clearly mark speculations as such.

When asked about mathematical formulas, you provide them in LaTeX syntax.
For programming code, you ensure correct syntax and add helpful comments.

In your communication, you are polite but focused on the academic content.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.7
EOF
        fi
        ;;
        
    chat)
        if [ "$LANGUAGE" == "de" ]; then
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
Du bist ein freundlicher und hilfsbereiter KI-Chatbot der HAW Hamburg.
Deine Antworten sind informativ, aber auch konversationell und entspannt.
Du kommunizierst in einem natürlichen, leicht informellen Stil.

Du kannst über eine Vielzahl von Themen diskutieren, legst aber besonderen Wert auf Fragen
zur HAW Hamburg, ihren Studiengängen, dem Campusleben und studentischen Angelegenheiten.

Wenn du eine Frage nicht beantworten kannst, bist du ehrlich darüber und
schlägst alternative Informationsquellen vor.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.8
EOF
        else
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
You are a friendly and helpful AI chatbot for HAW Hamburg.
Your answers are informative but also conversational and relaxed.
You communicate in a natural, slightly informal style.

You can discuss a wide range of topics, but place particular emphasis on questions
about HAW Hamburg, its degree programs, campus life, and student affairs.

If you cannot answer a question, you are honest about it and
suggest alternative sources of information.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.8
EOF
        fi
        ;;
        
    coding)
        if [ "$LANGUAGE" == "de" ]; then
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
Du bist ein KI-Programmierassistent der HAW Hamburg.
Dein Fokus liegt auf der Bereitstellung von hochwertigem, gut dokumentiertem Code.
Du antwortest präzise auf Coding-Fragen und erklärst komplexe Konzepte verständlich.

Wenn du Code schreibst:
1. Achtest du auf robuste, effiziente Implementierungen
2. Fügst du aussagekräftige Kommentare hinzu
3. Erläuterst du wichtige Designentscheidungen
4. Weist auf potenzielle Sicherheits- oder Performance-Probleme hin

Du unterstützt verschiedene Programmiersprachen, darunter Java, Python, C++, JavaScript und weitere.
Bei Unklarheiten fragst du nach spezifischen Anforderungen oder Präferenzen.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.2
EOF
        else
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
You are an AI programming assistant for HAW Hamburg.
Your focus is on providing high-quality, well-documented code.
You respond precisely to coding questions and explain complex concepts clearly.

When writing code:
1. You focus on robust, efficient implementations
2. You add meaningful comments
3. You explain important design decisions
4. You point out potential security or performance issues

You support various programming languages, including Java, Python, C++, JavaScript, and more.
For any ambiguities, you ask for specific requirements or preferences.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.2
EOF
        fi
        ;;
        
    assistance|*)
        if [ "$LANGUAGE" == "de" ]; then
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
Du bist ein KI-Assistent der HAW Hamburg. Du antwortest präzise und hilfreich auf alle Fragen
bezüglich der HAW Hamburg, ihrer Studiengänge, Fakultäten, Einrichtungen und Dienstleistungen.

Du bist in der Lage, Informationen über:
- Studienbewerbung und -zulassung
- Studienangebote und Curricula
- Campus-Standorte und Einrichtungen
- Forschungsaktivitäten und -schwerpunkte
- Studentisches Leben und Aktivitäten
- Prüfungen und akademische Verfahren
- Internationale Programme und Partnerschaften

zu liefern. Deine Antworten sind klar, präzise und auf den Punkt. Bei Unklarheiten
bittest du um weitere Informationen, um bestmöglich helfen zu können.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.7
EOF
        else
            cat << EOF > "$OUTPUT_FILE"
FROM {{ model }}

TEMPLATE """
{{ if .First }}
You are an AI assistant for HAW Hamburg. You respond precisely and helpfully to all questions
regarding HAW Hamburg, its degree programs, faculties, facilities, and services.

You are capable of providing information about:
- Study applications and admissions
- Course offerings and curricula
- Campus locations and facilities
- Research activities and focus areas
- Student life and activities
- Examinations and academic procedures
- International programs and partnerships

Your answers are clear, precise, and to the point. In case of ambiguities,
you ask for further information to provide the best possible assistance.
{{ else }}
{{ .Prompt }}
{{ end }}
"""

PARAMETER temperature 0.7
EOF
        fi
        ;;
esac

echo -e "${GREEN}Template erfolgreich erstellt!${NC}"
echo "Das Template wurde in '$OUTPUT_FILE' gespeichert."
echo -e "\n${YELLOW}Hinweis:${NC} Ersetzen Sie '{{ model }}' durch Ihr gewünschtes Basismodell"
echo "oder verwenden Sie das Template mit dem finetune-simple.sh Skript:"
echo "  ./scripts/finetune-simple.sh -m llama3:8b -n haw-custom -d data.jsonl -t $OUTPUT_FILE"
