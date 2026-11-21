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
