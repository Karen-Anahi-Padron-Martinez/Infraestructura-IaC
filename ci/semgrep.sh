#!/usr/bin/env bash
# SAST con Semgrep para los pipelines de Jenkins.
# Uso: ci/semgrep.sh <directorio> <config> [<config> ...]
#   Genera semgrep.json y semgrep.sarif en el directorio actual.
#   Falla (exit 1) si hay hallazgos de severidad ERROR; WARNING e INFO se reportan sin bloquear.
set -euo pipefail

VERSION_SEMGREP="1.186.0"
VENV="${JENKINS_HOME:-$HOME}/venvs/semgrep-${VERSION_SEMGREP}"

directorio="$1"; shift
configs=()
for c in "$@"; do configs+=(--config "$c"); done

# Entorno virtual reutilizable entre builds (se crea solo la primera vez)
if [ ! -x "$VENV/bin/semgrep" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "semgrep==${VERSION_SEMGREP}"
fi

"$VENV/bin/semgrep" --version
"$VENV/bin/semgrep" scan "$directorio" "${configs[@]}" \
  --metrics=off \
  --exclude target --exclude node_modules --exclude coverage --exclude dist \
  --exclude '*.min.js' --exclude 'bootstrap*' \
  --json --output semgrep.json \
  --sarif-output semgrep.sarif \
  --quiet || true

# Resumen por severidad y gate: solo ERROR bloquea el pipeline
python3 - <<'PY'
import json, sys
r = json.load(open("semgrep.json"))
res = r.get("results", [])
conteo = {}
for x in res:
    sev = x["extra"]["severity"]
    conteo[sev] = conteo.get(sev, 0) + 1
    print(f'[{sev}] {x["check_id"].split(".")[-1]} -> {x["path"]}:{x["start"]["line"]}')
print(f"Semgrep: {len(res)} hallazgos {conteo}; errores de análisis: {len(r.get('errors', []))}")
if conteo.get("ERROR", 0) > 0:
    print("Gate SAST: FALLA (hay hallazgos ERROR sin clasificar)")
    sys.exit(1)
print("Gate SAST: OK (sin hallazgos ERROR)")
PY
