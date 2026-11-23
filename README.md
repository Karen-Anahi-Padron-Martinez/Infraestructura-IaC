# Infraestructura-IaC: Gestor de Proyectos

Infraestructura como código y despliegue del Gestor de Proyectos.

| Repositorio | Contenido |
|---|---|
| [Microservicio1](https://github.com/Karen-Anahi-Padron-Martinez/Microservicio1) | API REST (backend) |
| [Microservicio2](https://github.com/Karen-Anahi-Padron-Martinez/Microservicio2) | Cliente web (frontend) |
| [Microservicio-BD](https://github.com/Karen-Anahi-Padron-Martinez/Microservicio-BD) | Esquema y datos de MariaDB |

## Estructura

| Carpeta | Contenido | Estado |
|---|---|---|
| `despliegue/` | `docker-compose.yml`: cliente, API y MariaDB | Listo |
| `ci/` | Scripts de Jenkins: Semgrep (SAST), despliegue con Ansible y prueba de humo | Listo |
| `terraform/` | Aprovisionamiento en Azure: red, VM, firewall, IP pública | Listo |
| `ansible/` | Configuración del servidor, despliegue y monitoreo (roles comun, docker, app, monitoreo) | Listo |
| `monitoreo/` | Prometheus, Grafana, Loki + Alloy, node-exporter, cAdvisor y 7 alertas | Listo |
| `rendimiento/` | Pruebas de carga con k6 | Pendiente |

## Imágenes de contenedor

Las construye Jib desde cada microservicio, sin Dockerfile, y se publican en GitHub Container Registry:

- `ghcr.io/karen-anahi-padron-martinez/microservicio1-api`
- `ghcr.io/karen-anahi-padron-martinez/microservicio2-cliente`

## Ejecutar la aplicación en local

Requisitos: Docker y los repositorios clonados como carpetas hermanas de este (la ruta de `Microservicio-BD` es configurable con `BD_SQL_DIR`).

```bash
# 1. Construir las imágenes en el Docker local (desde cada microservicio)
cd ../Ejercicio5MyAPIGestor && mvn -B -DskipTests package jib:dockerBuild
cd ../Ejercicio5Cliente     && mvn -B -DskipTests package jib:dockerBuild

# 2. Configurar secretos y levantar
cd ../Infraestructura-IaC/despliegue
cp .env.example .env        # define DB_ROOT_PASSWORD y DB_PASSWORD
docker compose up -d
docker compose ps           # los 3 servicios deben quedar "healthy"
```

La aplicación queda en http://localhost:8082. Cuentas demo: `demo1@example.com` / `Demo2026!`.

## Seguridad

- No hay contraseñas, tokens ni llaves en el repositorio. `.env`, `*.tfvars` y las llaves están en `.gitignore`.
- MariaDB y la API no publican puertos; solo el cliente es accesible desde fuera.
- Los contenedores de las aplicaciones corren con un usuario sin privilegios (UID 1000) y con límites de memoria.
