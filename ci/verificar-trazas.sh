#!/usr/bin/env bash
# Verifica en la VM que las trazas OpenTelemetry llegan a Tempo y que los logs llevan trace_id.
# Uso (desde ansible/): .\ejecutar.ps1 ansible gestor -b -m script -a /work/ci/verificar-trazas.sh
set -euo pipefail

tempo() { docker compose -f /opt/monitoreo/docker-compose.yml exec -T grafana wget -qO- "http://tempo:3200$1"; }

echo "== 1. Agente cargado en los contenedores"
for c in gestor-api-1 gestor-cliente-1; do
  # Se lee el log completo a una variable: con pipefail, grep -m1 cortaría la tubería y daría un falso negativo
  logs=$(docker logs "$c" 2>&1)
  printf '%s: %s\n' "$c" "$(grep -o -m1 'opentelemetry-javaagent - version: [0-9.]*' <<<"$logs" || echo 'SIN AGENTE')"
done

echo "== 2. Generar tráfico (página de login y login demo)"
for _ in 1 2 3; do
  curl -s -o /dev/null -w '%{http_code} ' http://localhost/login
  curl -s -o /dev/null -w '%{http_code} ' -X POST -H 'Content-Type: application/json' \
    -d '{"correo_electronico":"demo1@example.com","contrasena":"Demo2026!"}' http://localhost/verificarLogin
done
echo; sleep 15

echo "== 3. Servicios que reportan trazas a Tempo"
tempo /api/search/tag/service.name/values; echo

echo "== 4. Trazas recientes de /verificarLogin"
tempo '/api/search?tags=http.route%3D%2FverificarLogin&limit=3'; echo

echo "== 5. Una traza completa (spans por servicio)"
id=$(tempo '/api/search?tags=http.route%3D%2FverificarLogin&limit=1' | grep -o '"traceID":"[0-9a-f]*"' | head -1 | cut -d'"' -f4)
echo "traceID=$id"
tempo "/api/traces/$id" | grep -o '"name":"[^"]*"' | sort | uniq -c

echo "== 6. Correlación log -> traza (logs de la API con trace_id)"
docker logs gestor-api-1 2>&1 | grep -E 'trace_id=[0-9a-f]{32}' | tail -2 || echo "sin logs con trace_id"

echo "== 7. Memoria"
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | grep -E 'api|cliente|tempo'
free -m | head -2
