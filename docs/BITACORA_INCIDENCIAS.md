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
| Fuentes de datos de Grafana | Prometheus OK, Loki OK (Tempo OK desde el 24/11, ver INC-16) |
| Reglas de alerta cargadas | 7 (ServicioCaido, ContenedorReiniciado, TasaErrores5xxAlta, LatenciaP95Alta, CPUAlta, MemoriaAlta, DiscoCasiLleno) |
| Logs en Loki | `count_over_time({proyecto="gestor"}[1h])` = 14 líneas recibidas |
| Grafana desde la IP del administrador | 200; desde otras IP, bloqueado por el NSG |
| **Simulacro de caída** (`docker compose stop api`) | 18:00:07 se detiene → 18:00:27 `up(api)=0`, ServicioCaido *pending* → **18:01:28 firing** → 18:01:38 API recuperada → 18:02:18 alerta resuelta. Durante la caída la app pública respondía 500. |

## Fase 6: evaluación del rendimiento (22–24/11/2026)

### INC-14 · `Transfer-Encoding: chunked` duplicado en el login (defecto real)

| Campo | Detalle |
|---|---|
| **Problema** | En el primer humo de k6 falló el 100 % de `POST /verificarLogin` (20 % del total de peticiones, *checks* 66,67 %). |
| **Evidencia** | k6: `status=0 error=too many transfer encodings: ["chunked" "chunked"]`. `curl -i`: el encabezado `transfer-encoding: chunked` aparece dos veces, junto con los `Vary` de CORS de la API. Reporte: `rendimiento/reportes/humo-20261122-1809-FALLIDO-INC14.*`. |
| **Diagnóstico** | `/verificarLogin`, `/verificarTarea` y `/cambiosTareas` del cliente devolvían el `ResponseEntity` de la API con todos sus encabezados, y Tomcat agregaba su propio `Transfer-Encoding`. Es HTTP inválido: los navegadores y curl lo toleran, pero los clientes estrictos lo rechazan. |
| **Corrección** | `soloCuerpo()` reenvía solo el código y el cuerpo (Microservicio2 commit `3488515`). Se agregó la prueba `noSeReenvianLosEncabezadosDeLaApi` y la verificación 2b en `ci/humo.sh`; antes del despliegue esta última se ejecutó y **detectó** el defecto en producción. |
| **Nueva ejecución** | Pipeline App #7: 41 pruebas, SAST OK, Quality Gate OK, `cliente:7` desplegado; la verificación 2b de la prueba de humo pasó. k6 humo: 0 % de errores, 100 % de *checks*. |
| **Resultado** | Resuelto y protegido por regresiones en las pruebas unitarias y en el pipeline. |

### INC-15 · Errores `EOF` en el escenario de estrés (generador de carga, no aplicación)

| Campo | Detalle |
|---|---|
| **Problema** | Estrés (hasta 40 VU): 40 de 8 050 peticiones (0,50 %) con `EOF`; p99 de 3,28 s y máximo de 59,98 s. |
| **Evidencia** | Los errores se concentran entre 17:02 y 17:03 UTC (escalón 30→40 VU). En el servidor, durante la misma ventana: **0** respuestas 5xx, p99 de 194–207 ms, máximo de 0,52 s, sin reinicios ni OOM y sin errores en los logs de la API ni del cliente. CPU total máxima 53 %. |
| **Diagnóstico** | Los cortes de conexión ocurren en el camino del generador de carga: red NAT de Docker Desktop en una laptop con 2,7 GB para Docker y conexión doméstica con 40 conexiones simultáneas. No hay correspondencia en el servidor. |
| **Corrección** | No requiere cambios en la aplicación. Se documentó como limitación del entorno de prueba, con la recomendación de ejecutar k6 desde una VM en la misma región de Azure para estrés de mayor escala. |
| **Resultado** | El escenario cumplió todos los umbrales (errores 0,50 % < 1 %; p95 de 206 ms). Análisis completo en `rendimiento/RESULTADOS.md`. |

## Extra: trazas distribuidas con OpenTelemetry (24/11/2026)

Agente Java de OpenTelemetry 2.34.0, descargado por Ansible con su SHA-256 verificado y activado con `JAVA_TOOL_OPTIONS`. No requiere cambios de código. Las trazas se envían por OTLP/HTTP a Grafana Tempo 2.10.10, que no publica puertos. Grafana enlaza log → traza (campo `trace_id` en Loki) y traza → logs.

### INC-16 · Grafana no cargaba el nuevo datasource de Tempo

| Campo | Detalle |
|---|---|
| **Problema** | El rol `monitoreo` falló en "Grafana se conecta con Prometheus, Loki y Tempo": HTTP 500 durante 12 reintentos, también en la segunda ejecución. |
| **Evidencia** | `/api/datasources/uid/tempo/health` → `Unable to load datasource metadata`. En el log de Grafana: `error="data source not found"`. Tempo sí estaba listo (`/ready` = `ready` y todos sus módulos en `Running`). |
| **Diagnóstico** | Grafana lee el *provisioning* de datasources **solo al arrancar**. El rol copiaba el archivo nuevo, pero el contenedor de Grafana no cambiaba y por eso no se reiniciaba. Hasta ahora no había pasado porque los datasources nunca habían cambiado. |
| **Corrección** | Se agregó el handler `Reiniciar Grafana`, notificado cuando cambia la configuración de monitoreo (junto con `Recargar Prometheus`). Grafana se reinició una vez a mano porque los archivos ya estaban copiados. |
| **Nueva ejecución** | Health: Prometheus OK, Loki OK, Tempo OK. `--tags monitoreo`: ok=8, **changed=0**, failed=0 (idempotente). |
| **Resultado** | Resuelto. Un cambio futuro en datasources o tableros se aplica sin intervención manual. |

### Verificación de las trazas (`ci/verificar-trazas.sh`)

| Prueba | Resultado |
|---|---|
| Agente cargado | `gestor-api` y `gestor-cliente`: `opentelemetry-javaagent - version: 2.34.0` |
| Despliegue de la app (`--tags app`) | ok=18, failed=0; api, cliente y mariadb *healthy*; humo de login OK |
| Servicios en Tempo | `gestor-api`, `gestor-cliente` |
| Traza de `POST /verificarLogin` (92–96 ms; 819 ms la primera, con el arranque en frío) | cliente `POST /verificarLogin` → cliente HTTP `POST` → API `POST /getUsuarioLogin` → `UsuarioRepository.findByCorreo` → Hibernate `SELECT usuario` → JDBC `SELECT dbgestor.usuario` |
| Correlación log → traza | Logs de la API con `trace_id=9977e359… span_id=d0936482…`, el mismo ID de la traza |
| Memoria tras activar el agente | API 350/512 MiB (antes, máx. 274 en estrés), cliente 250/512 MiB, Tempo 41/384 MiB; VM con 2,0 GB disponibles |

## Extra: Jenkins y SonarQube en Azure (24–25/11/2026)

Jenkins y SonarQube pasaron de la laptop a una segunda VM, `vm-gestor-ci` (Standard_B2as_v2: 2 vCPU y 8 GB), creada con Terraform (`terraform/ci.tf`) y configurada con el rol de Ansible `ci`. Comparte la VNet con la aplicación, así que Jenkins despliega por la red privada (10.20.1.4). Jenkins (8080) y SonarQube (9000) solo se abren a `cidrs_admin`.

**Antes de crear la VM:** se verificó el cupo (2 de 6 vCPU regionales en uso), el precio oficial (0.0752 USD/h en Linux) y el `terraform plan`: 5 por crear, 1 por cambiar (NSG) y ninguna destrucción en Azure.

### INC-17 · Python instalado a mano dentro del contenedor de Jenkins local

| Campo | Detalle |
|---|---|
| **Problema** | Al preparar la migración, la imagen oficial `jenkins/jenkins` no trae `python3-venv`, que necesitan `ci/semgrep.sh` y `ci/desplegar.sh`. |
| **Evidencia** | `docker diff jenkins` en local: `A /usr/lib/python3.13/...`. Python se había instalado dentro del contenedor y no estaba en ninguna definición versionada. |
| **Diagnóstico** | Configuración no reproducible: si el contenedor se recreaba, el SAST y el despliegue dejaban de funcionar. |
| **Corrección** | `roles/ci/templates/Dockerfile.jenkins.j2`: `FROM jenkins/jenkins:2.580.1-lts-jdk21` más `python3 python3-venv openssh-client`. Ansible construye la imagen. |
| **Nueva ejecución** | La verificación del rol `ci` (`python3 -c "import venv"`) da OK. Los pipelines con SAST y despliegue pasaron en la nube. |
| **Resultado** | Las herramientas de los pipelines quedaron versionadas como código. |

### INC-18 · IP pública dinámica del administrador

| Campo | Detalle |
|---|---|
| **Problema** | El SSH a la VM de CI dejó de responder (`Connection timed out`) a mitad de la migración. |
| **Evidencia** | `curl https://api.ipify.org`: la IP pasó de 187.140.67.84 a 187.140.41.208 en menos de una hora, en la misma red doméstica. |
| **Diagnóstico** | El proveedor asigna IP dinámicas; el NSG solo admite las de `cidrs_admin`. |
| **Corrección** | IP nueva en `cidrs_admin` y `terraform apply` (0 por crear, 1 por cambiar, 0 por destruir). Se mantiene `/32` en lugar de abrir el rango del proveedor (`/16`), por seguridad. |
| **Resultado** | Acceso restablecido en segundos. Procedimiento documentado en la guía de comandos. |

### INC-19 · El plan de Terraform guardado no estaba en `.gitignore`

| Campo | Detalle |
|---|---|
| **Problema** | `git status` mostró `terraform/tfplan` como archivo nuevo sin seguimiento. |
| **Diagnóstico** | La regla era `*.tfplan`, pero el archivo se llama `tfplan`, sin extensión. Un plan puede contener valores de variables (ID de suscripción, IP). `git log --all -- terraform/tfplan` confirmó que nunca se subió. |
| **Corrección** | Regla `tfplan` agregada a `.gitignore`; `git check-ignore` lo confirma. |
| **Resultado** | Prevenido antes de cualquier commit. |

### INC-20 · El SonarQube nuevo no tenía el Quality Gate estricto ni las revisiones de hotspots

| Campo | Detalle |
|---|---|
| **Problema** | Después de migrar, SonarQube mostraba **"Hotspots Reviewed 0.0 % (E)"** en la API y el frontend (en local era 100 %, A), y aun así el Quality Gate pasaba. |
| **Evidencia** | Captura de *Projects* en el Sonar de la nube. `api/qualitygates/list`: solo existía *Sonar way*. `api/hotspots/search?status=TO_REVIEW`: 7 de la regla `java:S3752` en la API y 1 de `javascript:S2245` en el frontend. |
| **Diagnóstico** | El gate **"Sonar way + codigo global"** de la Unidad II (cobertura global ≥ 80 %, bugs = 0, vulnerabilidades = 0, hotspots revisados = 100 %) y las revisiones de hotspots vivían solo en la base H2 del Sonar local, que no se migró. El Sonar nuevo aplicaba *Sonar way*, que en el primer análisis no evalúa nada: **los umbrales habían bajado sin que nadie lo decidiera.** |
| **Corrección** | 1) El rol `ci` crea el gate (copia de *Sonar way* más las 4 condiciones globales, definidas en `group_vars/ci/vars.yml`), lo deja como predeterminado y verifica sus condiciones. 2) `ansible/revisar-hotspots.yml` vuelve a marcar Safe, **con la justificación escrita de la Unidad II**, solo las reglas ya revisadas (`S3752`, `S2245`); si aparece un hotspot de otra regla, el playbook falla para exigir revisión humana. |
| **Nueva ejecución** | Rol `ci`: gate creado y predeterminado; segunda corrida changed=0. `revisar-hotspots.yml`: 8 hotspots marcados Safe y "Sin hotspots pendientes fuera de los ya justificados". Los 4 pipelines se reejecutaron con el gate estricto (resultado abajo). |
| **Resultado** | Restaurados los umbrales de la Unidad II, ahora como código: un Sonar nuevo nace con el mismo gate. |

### Decisiones de la migración

| Tema | Decisión |
|---|---|
| Jenkins | Se migró `jenkins_home`: jobs, historial de builds, plugins, herramientas, credenciales y su llave de cifrado. Se excluyeron `workspace`, cachés y los artefactos archivados de builds anteriores, porque se regeneran. Respaldo de 596 MB (era 3.5 GB) enviado por `scp`; la restauración la hace Ansible solo si el volumen está vacío. |
| SonarQube | El local usaba la base embebida H2, que la propia herramienta marca "solo para evaluación", y no tenía volúmenes. En la nube corre sobre **PostgreSQL 16.16**. Ansible cambia la contraseña inicial `admin/admin` por la de Vault y crea el webhook del Quality Gate hacia Jenkins. Los proyectos se recrearon al reanalizar. |
| Secretos nuevos | `group_vars/ci/vault.yml` (AES256) generado por `scripts/generar-vault-ci.sh`. El texto plano solo existe en el contenedor efímero. El token de Sonar y la credencial `mariadb-ci` los actualizó la administradora en Jenkins. |
| Memoria | Jenkins con 1 ejecutor (evita builds en paralelo, INC-12), límite de 3.5 GB; SonarQube 2.5 GB; swap de 4 GB. |
| Disparo automático | `triggers { pollSCM('H/5 * * * *') }` en los 4 Jenkinsfiles. Los checkouts auxiliares usan `poll: false` para que solo el repo propio dispare cada pipeline. |

### Verificación de CI en la nube

| Prueba | Resultado |
|---|---|
| Rol `ci` | ok=24, failed=0. Segunda corrida: **changed=0** (después de corregir el `changed_when` de `compose up --build`, que siempre imprime "Built") |
| Servicios | `jenkins`, `sonarqube`, `sonar-db` (healthy), `mariadb-container` (healthy). Memoria: 5.2 GB disponibles de 8 |
| Jenkins → VM de la app por la red privada | Puerto 22 en 10.20.1.4 alcanzable desde el contenedor de Jenkins |
| Backend-Microservicio1-API **#4** | SUCCESS en 2 min 51 s (en local, 8 min 52 s): 121 pruebas, SAST OK, Quality Gate OK, `api:4` desplegado por SSH a 10.20.1.4, humo OK |
| BD-dbgestor **#3** | SUCCESS en 43 s: 42 pruebas (incluida la de integración con el MariaDB de pruebas), 0 hallazgos SAST, Quality Gate OK |
| Frontend-Microservicio2 **#9** | SUCCESS en 1 min 19 s: 66 pruebas, SAST OK, Quality Gate OK |
| App-Microservicio2-Cliente **#8** | SUCCESS en 3 min 22 s: 41 pruebas, SAST OK, Quality Gate OK, `cliente:8` desplegado, humo OK |
| Registro de `pollSCM` | Segunda corrida (BD #4, Backend #5, Frontend #10, App #9: todos SUCCESS). Los 4 jobs quedan con `<spec>H/5 * * * *</spec>` |
| **Disparo automático con un push** | Commit `dcae127` en Microservicio-BD a las 19:52:51 UTC, sin lanzar nada a mano → **BD #5 "Started by an SCM change"** a las 19:54:09 (78 s después): 42 pruebas, Quality Gate OK, SUCCESS |
| **Pipelines con el Quality Gate estricto** (después de INC-20) | BD #6, Backend #6, Frontend #11, App #10: todos SUCCESS con "Quality gate is 'OK'" en "Sonar way + codigo global". Medidas en Sonar: API cobertura 100 %, frontend 97.8 %, **hotspots revisados 100 %** en ambos, 0 bugs, 0 vulnerabilidades |
