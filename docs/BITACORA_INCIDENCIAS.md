# Bitácora de incidencias

Formato: problema → evidencia → diagnóstico → corrección → nueva ejecución → resultado.

## Fase 1: contenerización (21/11/2026)

### INC-01 · `/actuator/prometheus` respondía 404 en las pruebas

| Campo | Detalle |
|---|---|
| **Problema** | `ObservabilidadTest.prometheusExponeMetricasConLaEtiquetaDeLaAplicacion` falló en los dos microservicios. |
| **Evidencia** | `Status expected:<200> but was:<404>`; `No static resource actuator/prometheus` (log de `mvn verify`). |
| **Diagnóstico** | En `@SpringBootTest`, Spring Boot desactiva por defecto la exportación de métricas, así que el registro de Prometheus no se crea. En la aplicación real sí está activo. |
| **Corrección** | Se agregó `@AutoConfigureObservability` a la prueba para reproducir el comportamiento de producción. |
| **Nueva ejecución** | `mvn clean verify` en Microservicio2: 40 pruebas, 0 fallos. |
| **Resultado** | Resuelto en el cliente. En el backend apareció INC-02. |

### INC-02 · Métricas del backend sin la etiqueta `application`

| Campo | Detalle |
|---|---|
| **Problema** | En Microservicio1 la misma prueba siguió fallando. |
| **Evidencia** | `Expected: a string containing "application=\"Ejercicio5MyAPIGestor\""`: la salida no tenía la etiqueta. |
| **Diagnóstico** | `src/test/resources/application.properties` reemplaza al archivo principal durante las pruebas y no define `spring.application.name`, así que la etiqueta quedaba vacía. |
| **Corrección** | Se agregó `spring.application.name=Ejercicio5MyAPIGestor` al archivo de propiedades de prueba. |
| **Nueva ejecución** | `mvn clean verify`: 121 pruebas, 0 fallos; JaCoCo 100 % de líneas, ramas y métodos. |
| **Resultado** | Resuelto (commit `d49c4f4` en Microservicio1). |

### INC-03 · El puerto 3306 aparecía abierto en el host

| Campo | Detalle |
|---|---|
| **Problema** | En la verificación de exposición, el puerto 3306 del host respondía, aunque el compose no publica MariaDB. |
| **Evidencia** | `docker port gestor-mariadb-1` sale vacío; `netstat` muestra el PID 6820 escuchando en 3306, y `tasklist` lo identifica como `mysqld.exe`. |
| **Diagnóstico** | Es el servicio MySQL Server instalado en Windows, ajeno al proyecto. El contenedor no expone puertos. |
| **Corrección** | No requiere cambios. En el servidor cloud el firewall (Terraform) solo abrirá SSH y el puerto del cliente. |
| **Resultado** | Falso positivo documentado. |

### Verificación final de la fase 1

| Prueba | Resultado |
|---|---|
| `docker compose up -d` | `mariadb`, `api` y `cliente` en estado **healthy** |
| `GET /login` | 200 |
| Login `demo1@example.com` / `Demo2026!` (cliente → API → BCrypt → MariaDB) | Devuelve el usuario y **no** incluye el hash de la contraseña |
| Login con contraseña incorrecta | `nombre: "000"` (rechazado) |
| `POST /consultarProyectos` | Lista los datos de `Microservicio-BD` con acentos correctos (utf8mb4) |
| `/actuator/health` y `/actuator/prometheus` | `UP`; 276 líneas de histograma de latencias |
| API (8081) y MariaDB desde el host | No accesibles: solo están en la red interna |
| Memoria | cliente 176 MiB, api 235 MiB, mariadb 87 MiB (dentro de sus límites de 512/512/384 MiB) |

## Fase 2: Terraform en Azure (21/11/2026)

### INC-04 · Región no permitida por la política de Azure for Students

| Campo | Detalle |
|---|---|
| **Problema** | La región por defecto del código (`eastus`) no se puede usar en la suscripción. |
| **Evidencia** | `az policy assignment list`: la asignación "Allowed resource deployment regions" solo permite `westus`, `norwayeast`, `chilecentral`, `canadacentral` y `northcentralus`. |
| **Diagnóstico** | La suscripción de estudiante restringe las regiones mediante Azure Policy. |
| **Corrección** | `ubicacion = "northcentralus"`, una de las permitidas más cercanas a México. Se documentó la lista en `variables.tf`. |
| **Resultado** | Detectado antes del `apply`, sin despliegues fallidos. |

### INC-05 · `SkuNotAvailable`: sin capacidad para Standard_B2s

| Campo | Detalle |
|---|---|
| **Problema** | `terraform apply` creó 8 de 10 recursos y falló al crear la VM. |
| **Evidencia** | `409 Conflict ... SkuNotAvailable: ... Standard_B2s is currently not available in location 'northcentralus'`. |
| **Diagnóstico** | Restricción de capacidad de Azure para ese tamaño en la región. `az vm list-skus -l northcentralus --size Standard_B2` mostró disponibles, sin restricciones, `B2als_v2`, `B2as_v2` y `B2ats_v2`. |
| **Corrección** | `tamano_vm = "Standard_B2als_v2"`: 2 vCPU AMD y 4 GB, equivalente a B2s y algo más barato. |
| **Nueva ejecución** | `terraform plan`: 2 recursos por crear, 0 por cambiar, 0 por destruir (la red ya existente se conserva). `terraform apply`: "Apply complete! Resources: 2 added". |
| **Resultado** | VM creada en 57 s. SSH con llave verificado: Ubuntu 24.04.5 LTS, 2 CPU, 3,8 GiB de RAM, 29 GB de disco. El acceso con contraseña se rechaza (`Permission denied (publickey)`). |

## Fase 3: Ansible y despliegue (21–22/11/2026)

### INC-06 · Ansible no conectaba: ruta de la llave en formato Windows

| Campo | Detalle |
|---|---|
| **Problema** | `ansible gestor -m ping` respondía `UNREACHABLE`. |
| **Evidencia** | `no such identity: C:Userskaren.sshid_ed25519_gestor_azure ... Permission denied (publickey)`. |
| **Diagnóstico** | El inventario generado por Terraform incluía `ansible_ssh_private_key_file` con la ruta de Windows. Ansible corre en un contenedor Linux, donde esa ruta no existe, y la variable del inventario tenía prioridad sobre `ansible.cfg`. |
| **Corrección** | Se quitó la ruta de la plantilla `inventario.ini.tftpl`; la llave se define en `ansible.cfg` (`private_key_file = /root/.ssh/id_gestor`). `terraform apply` solo regeneró el archivo local (1 añadido, 1 destruido, sin cambios en Azure). |
| **Resultado** | `vm-gestor | SUCCESS => "ping": "pong"`. |

### INC-07 · PowerShell interrumpía la ejecución de Ansible

| Campo | Detalle |
|---|---|
| **Problema** | 1) `--tags comun,docker` solo ejecutaba la recolección de datos. 2) La salida se cortaba con `NativeCommandError` en la primera advertencia. |
| **Evidencia** | `PLAY RECAP ... ok=1`; en el segundo caso, `[WARNING]: Module remote_tmp ... NativeCommandError`. |
| **Diagnóstico** | 1) PowerShell convierte `a,b` en un arreglo y separa el argumento. 2) Con `$ErrorActionPreference = "Stop"`, cualquier texto en stderr se trata como error fatal. |
| **Corrección** | Las etiquetas se pasan entre comillas (`'--tags=comun,docker'`) y `ejecutar.ps1` usa `Continue` al ejecutar el contenedor. |
| **Nueva ejecución** | Roles `comun` y `docker`: ok=14, changed=0, failed=0 (la corrida anterior sí había terminado dentro del contenedor). |
| **Resultado** | Resuelto. |

### INC-08 · El rol `app` no era idempotente

| Campo | Detalle |
|---|---|
| **Problema** | Una segunda ejecución sin cambios reportaba `changed=1`. |
| **Evidencia** | En la VM, `docker compose up -d --pull always` muestra `Pulled` para cada imagen, pero los contenedores quedan `Running` (sin recrearse). |
| **Diagnóstico** | `changed_when` consideraba `Pulled` como cambio, aunque solo se consultaba el registro. |
| **Corrección** | `changed_when` solo busca `Started`, `Recreated` o `Created`. |
| **Nueva ejecución** | `ansible-playbook site.yml`: ok=24, **changed=0**, failed=0. |
| **Resultado** | Playbook completo idempotente. |

### INC-09 · Cambio de red: SSH bloqueado por el firewall

| Campo | Detalle |
|---|---|
| **Problema** | Al trabajar desde otra red, la IP pública cambió (154.212.7.54 → 177.242.194.123). |
| **Diagnóstico** | El NSG solo permite SSH y Grafana desde `cidrs_admin`. |
| **Corrección** | Se agregó la IP nueva a `cidrs_admin` en `terraform.tfvars`. `terraform plan`: 0 por crear, 1 por cambiar (solo el NSG), 0 por destruir. |
| **Resultado** | `Apply complete! Resources: 0 added, 1 changed` (4 s); SSH restablecido sin tocar la VM. |

### Verificación del despliegue en Azure

| Prueba (desde internet) | Resultado |
|---|---|
| `GET http://gestor-717e46.northcentralus.cloudapp.azure.com/` | 200 en 0,76 s |
| Login `demo1@example.com` (cliente → API → MariaDB) | Devuelve el usuario y no expone la contraseña |
| `POST /consultarProyectos` | Datos de Microservicio-BD con acentos correctos |
| `/actuator/health` | `UP` (liveness, readiness) |
| Puertos 8081 (API), 3306 (MariaDB) y 9090 (Prometheus) | Cerrados |
| `/opt/gestor/.env` en la VM | Permisos `600`, dueño `root` (azureuser recibe `Permission denied`) |
| Servicios | `api=healthy, cliente=healthy, mariadb=healthy` |

## Fase 4: CI/CD con SAST y despliegue continuo (22/11/2026)

### INC-10 · Semgrep: Actuator expuesto públicamente (CWE-200) — vulnerabilidad real

| Campo | Detalle |
|---|---|
| **Problema** | Semgrep (`spring-actuator-dangerous-endpoints-enabled`, OWASP A01) señaló que Actuator expone `health,info,prometheus`. |
| **Evidencia** | `curl http://gestor-717e46.northcentralus.cloudapp.azure.com/actuator/prometheus` → **200** desde internet: métricas internas visibles para cualquiera. |
| **Diagnóstico** | Actuator compartía el puerto público del cliente (80 → 8082). |
| **Corrección** | `MANAGEMENT_SERVER_PORT=8090` en los contenedores (puerto de administración no publicado). Health checks de Compose y Ansible usan 8090. Se agregaron regresiones: Ansible exige 404 en `/actuator/prometheus` y `ci/humo.sh` lo verifica desde internet. |
| **Nueva ejecución** | Desde internet: `/actuator/prometheus`, `/actuator/health` y `/actuator` → **404**; `/login` → 200. Dentro de la red interna, `/actuator/prometheus` en 8090 devuelve 292 líneas de métricas. |
| **Resultado** | Mitigado. El aviso estático de Semgrep sigue (la regla mira la configuración) y queda clasificado como *mitigado*; es WARNING, no bloquea el gate. |

### INC-11 · Semgrep: hashes BCrypt en los datos de prueba — falso positivo

| Campo | Detalle |
|---|---|
| **Problema** | 3 hallazgos ERROR `detected-bcrypt-hash` en `Microservicio-BD/sql/02_datos_prueba.sql`. |
| **Diagnóstico** | Son los hashes de la contraseña demo documentada para cuentas ficticias `@example.com`. Un hash BCrypt no es una credencial reutilizable y los datos no pertenecen a ningún sistema real. |
| **Corrección** | `-- nosemgrep: detected-bcrypt-hash` en cada línea, con una justificación en el script (commit `7895e9f`). |
| **Resultado** | Semgrep en Microservicio-BD: 0 hallazgos activos (BD #2). |

### INC-12 · Jenkins terminado por falta de memoria (OOMKilled)

| Campo | Detalle |
|---|---|
| **Problema** | El build Frontend #7 quedó ABORTED y Jenkins dejó de responder. |
| **Evidencia** | `docker inspect jenkins`: `OOMKilled=true ExitCode=137` durante la etapa "Análisis SonarQube" (analizador JavaScript con Node). |
| **Diagnóstico** | La VM de Docker local tiene 2,7 GB; SonarQube (1,2 GB) + Jenkins + el analizador de Node superaron el límite. |
| **Corrección** | `sonar.javascript.node.maxspace=768` en el frontend y la BD; Jenkins reiniciado; pipelines ejecutados en serie. |
| **Nueva ejecución** | Frontend #8 y BD #2: SUCCESS. |
| **Resultado** | Resuelto. Recomendación: asignar más RAM a Docker (`.wslconfig`). |

### Resumen de hallazgos SAST (Semgrep 1.186.0)

| # | Regla | Severidad | Ubicación | Clasificación | Acción |
|---|---|---|---|---|---|
| 1 | `spring-actuator-dangerous-endpoints-enabled` | WARNING | Microservicio1 `application.properties` | Real → **mitigado** | Actuator en el puerto interno 8090 + regresión (INC-10) |
| 2 | `spring-actuator-dangerous-endpoints-enabled` | WARNING | Microservicio2 `application.properties` | Real → **mitigado** | Ídem |
| 3–5 | `detected-bcrypt-hash` | ERROR | Microservicio-BD `02_datos_prueba.sql` (×3) | **Falso positivo** | `nosemgrep` con justificación (INC-11) |

### Ejecuciones de la fase 4 (Jenkins)

| Pipeline | Build | Etapas nuevas | Resultado |
|---|---|---|---|
| Backend-Microservicio1-API | **#3** | SAST → … → Publicar imagen `api:3` → Desplegar en Azure → Prueba de humo | SUCCESS (121 pruebas; despliegue `api=3 cliente=latest`) |
| App-Microservicio2-Cliente | **#5** | Ídem con `cliente:5` | SUCCESS (40 pruebas; despliegue `api=3 cliente=5`) |
| Frontend-Microservicio2 | **#8** | SAST (Semgrep) | SUCCESS (66 pruebas; 1 WARNING ya clasificado) |
| BD-dbgestor | **#2** | SAST (Semgrep) | SUCCESS (lint 0 problemas; 42 pruebas; 0 hallazgos) |

## Fase 5: monitoreo y observabilidad (22/11/2026)

### INC-13 · Grafana no arrancaba: thrashing de disco por límite de memoria

| Campo | Detalle |
|---|---|
| **Problema** | El rol `monitoreo` falló: `http://localhost:3000/api/health` → `Connection reset by peer` durante 30 reintentos. |
| **Evidencia** | `top`: **67 % iowait**. `docker stats`: Grafana leyó **32,1 GB** del disco en pocos minutos con `mem_limit: 256m`; Alloy, 891 MB con 192m. |
| **Diagnóstico** | El binario y la caché de Grafana 13 no caben en 256 MB. El kernel desaloja páginas del cgroup y las vuelve a leer del disco continuamente (*thrashing*), saturando el disco StandardSSD de 30 GB. |
| **Corrección** | `mem_limit` de Grafana a 768m, y de Alloy y Loki a 384m. |
| **Nueva ejecución** | `ansible-playbook site.yml --tags monitoreo`: ok=9, failed=0. Grafana sano en unos 20 s. |
| **Resultado** | iowait **0 %**. Grafana usa 464 MiB (por eso no cabía en 256), Alloy 81 MiB y Loki 65 MiB. |

### Verificación del monitoreo

| Prueba | Resultado |
|---|---|
| Objetivos de Prometheus | `api=up, cliente=up, contenedores=up, nodo=up, prometheus=up` |
| Fuentes de datos de Grafana | Prometheus OK, Loki OK |
| Reglas de alerta cargadas | 7 (ServicioCaido, ContenedorReiniciado, TasaErrores5xxAlta, LatenciaP95Alta, CPUAlta, MemoriaAlta, DiscoCasiLleno) |
| Logs en Loki | `count_over_time({proyecto="gestor"}[1h])` = 14 líneas recibidas |
| Grafana desde la IP del administrador | 200; desde otras IP, bloqueado por el NSG |
| **Simulacro de caída** (`docker compose stop api`) | 18:00:07 se detiene → 18:00:27 `up(api)=0`, ServicioCaido *pending* → **18:01:28 firing** → 18:01:38 API recuperada → 18:02:18 alerta resuelta. Durante la caída la app pública respondía 500. |
