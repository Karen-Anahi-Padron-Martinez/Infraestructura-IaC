#!/usr/bin/env bash
# Ejecuta un escenario de k6 con Docker y guarda el reporte HTML y el resumen JSON en rendimiento/reportes/.
# Uso: rendimiento/ejecutar.sh <humo|carga|estres> [url-base]
set -euo pipefail
escenario="${1:-humo}"
url="${2:-http://gestor-717e46.northcentralus.cloudapp.azure.com}"
dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir/reportes"
marca="$(date +%Y%m%d-%H%M)"

# MSYS_NO_PATHCONV evita que Git Bash en Windows reescriba las rutas del contenedor
MSYS_NO_PATHCONV=1 docker run --rm -i \
  -e ESCENARIO="$escenario" -e BASE_URL="$url" \
  -e K6_WEB_DASHBOARD=true \
  -e K6_WEB_DASHBOARD_EXPORT="/reportes/${escenario}-${marca}.html" \
  -v "$(cd "$dir/reportes" && (pwd -W 2>/dev/null || pwd)):/reportes" \
  grafana/k6:2.4.0 run --quiet \
  --summary-export "/reportes/${escenario}-${marca}.json" - < "$dir/prueba-carga.js"
