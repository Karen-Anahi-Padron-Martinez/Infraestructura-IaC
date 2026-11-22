#!/usr/bin/env bash
# Prueba de humo desde fuera de la VM (como un usuario de internet) después de cada despliegue.
# Uso: ci/humo.sh <url-base>
set -euo pipefail
url="${1%/}"

codigo() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@"; }

echo "1) Página de login"
[ "$(codigo "$url/login")" = "200" ] || { echo "FALLA: /login no responde 200"; exit 1; }

echo "2) Login con la cuenta demo (cliente -> API -> MariaDB)"
respuesta="$(curl -s --max-time 15 -X POST "$url/verificarLogin" -H 'Content-Type: application/json' \
  -d '{"correo_electronico":"demo1@example.com","contrasena":"Demo2026!"}')"
echo "$respuesta" | grep -q '"nombre":"Usuario Demo Uno"' || { echo "FALLA: login demo -> $respuesta"; exit 1; }
echo "$respuesta" | grep -q '"contrasena":null' || { echo "FALLA: la respuesta expone la contraseña"; exit 1; }

echo "3) Datos desde la base de datos"
curl -s --max-time 15 -X POST "$url/consultarProyectos" | grep -q '"id_proyecto"' || { echo "FALLA: /consultarProyectos sin datos"; exit 1; }

echo "4) Actuator no expuesto públicamente (CWE-200)"
[ "$(codigo "$url/actuator/prometheus")" = "404" ] || { echo "FALLA: /actuator/prometheus es público"; exit 1; }

echo "Prueba de humo OK: $url"
