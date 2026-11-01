#!/bin/bash
# Regenerates the documentation wiki from wiki-src/.
# The generator ships with the code-wiki-generator skill (outside this repo);
# override its location with WIKI_GENERATOR=/path/to/generate_wiki.py.
set -euo pipefail
cd "$(dirname "$0")/.."
GEN="${WIKI_GENERATOR:-$HOME/.agents/skills/code-wiki-generator/scripts/generate_wiki.py}"
if [[ ! -f "$GEN" ]]; then
    echo "Wiki generator not found at: $GEN" >&2
    echo "Install the code-wiki-generator skill, or set:" >&2
    echo "  WIKI_GENERATOR=/path/to/generate_wiki.py" >&2
    exit 1
fi
python3 "$GEN" --source . --out wiki \
    --title "MacSpaces Reference" \
    --subtitle "Native macOS disk manager with AI-model audits" \
    --version 1.1 wiki-src
