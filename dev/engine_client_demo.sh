#!/usr/bin/env bash
# CANDID engine client demo (curl) - the raw HTTP contract behind the UI-agnostic
# core, driven with zero R. Discovers the source catalog, then posts a candidate
# gene list + a chosen subset of sources to /review. A richer, catalog-driven
# version (parses the catalog, groups by domain) is dev/engine_client_demo.py.
#
# Requires a running engine (needs the `plumber` package):
#   Rscript dev/serve.R 8000          # in another terminal
#   dev/engine_client_demo.sh [base_url]
#
# Research use only. Not for clinical or diagnostic use.
set -euo pipefail
BASE="${1:-http://127.0.0.1:8000}"

echo "== GET ${BASE}/catalog  (source discovery) =="
curl -s "${BASE}/catalog"
echo

echo
echo "== POST ${BASE}/review  (candidate set + selected sources) =="
curl -s -X POST "${BASE}/review" \
  -H "Content-Type: application/json" \
  -d '{
    "sources": [
      {"genes": ["NF1","SUZ12","CDKN2A","TP53","EED","TTN"], "label": "my candidates", "type": "pasted"}
    ],
    "options": {"sources": ["ot_assoc","gnomad_loeuf","cbioportal","civic","clingen"], "caveats": true}
  }'
echo
echo
echo "Research use only. Not for clinical or diagnostic use."
