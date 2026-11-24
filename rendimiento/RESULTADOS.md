# Evaluación del rendimiento: Gestor de Proyectos

**Fecha:** 24/11/2026 (humo inicial: 22/11/2026)
**Herramienta:** k6 2.4.0, ejecutado en Docker desde la laptop del equipo hacia Azure (northcentralus)
**Sistema bajo prueba:** `http://gestor-717e46.northcentralus.cloudapp.azure.com`. VM Standard_B2als_v2 (2 vCPU, 4 GB) con cliente `:7`, API `:3` y MariaDB 11.4, más el stack de monitoreo.

## 1. Escenario de prueba

Cada usuario virtual (VU) repite el flujo de un usuario real:

1. `GET /login`: página de inicio de sesión (tipo **página**).
2. `POST /verificarLogin`: login demo; verifica BCrypt contra MariaDB a través de la API (tipo **login**).
3. Pausa de 1 s.
4. `POST /consultarProyectos`, `POST /obtenerTareas` y `POST /consultarUsuarios` (tipo **consulta**; cliente → API → MariaDB).
5. Pausa aleatoria de 1 a 3 s (tiempo de lectura).

| Escenario | Carga | Duración |
|---|---|---|
| **humo** | 1 VU constante | 30 s |
| **carga** | 0 → 10 VU en 1 min, 10 VU sostenidos 3 min, bajada en 30 s | ~4,5 min |
| **estrés** | Escalones de 10 → 20 → 30 → 40 VU (1–1,5 min cada uno) y bajada | ~6 min |

**Criterios de aceptación** (*thresholds* de k6):

| Criterio | Umbral |
|---|---|
| Tasa de errores HTTP | < 1 % |
| Verificaciones (*checks*) | > 99 % |
| p95 de páginas y consultas | < 800 ms |
| p95 de login | < 1 500 ms (BCrypt es costoso a propósito) |

**Límites y seguridad:**
- Solo contra el entorno propio del proyecto.
- Máximo 40 VU y 6,5 minutos.
- Cuentas ficticias.
- Sin credenciales en el script; la contraseña demo está documentada como dato de prueba.

## 2. Resultados

Cifras tomadas de los reportes `reportes/*.json` y `*.html` (k6, del lado del usuario).

| Escenario | Peticiones | Throughput | Errores | p50 | p90 | **p95** | p99 | Máx. | Umbrales |
|---|---|---|---|---|---|---|---|---|---|
| humo (22/11, antes de la corrección) | 40 | 1,23 req/s | **20,00 %** | 104 ms | 203 ms | 216 ms | 300 ms | 331 ms | ✗ (INC-14) |
| humo (24/11) | 40 | 1,26 req/s | 0,00 % | 102 ms | 166 ms | 205 ms | 207 ms | 207 ms | ✓ |
| **carga** (10 VU) | 3 235 | **11,89 req/s** | **0,00 %** | 77 ms | 155 ms | **169 ms** | 243 ms | 1,29 s | ✓ |
| **estrés** (hasta 40 VU) | 8 050 | **22,16 req/s** | **0,50 %** (40) | 72 ms | 163 ms | **206 ms** | 3,28 s | 59,98 s | ✓ |

**p95 por tipo de petición:**

| Escenario | Página | Login | Consulta |
|---|---|---|---|
| carga | 124 ms | 206 ms | 110 ms |
| estrés | 116 ms | 298 ms | 119 ms |

**Métricas del servidor durante la prueba** (Prometheus en la VM):

| Escenario | p95 servidor (API / cliente) | p99 servidor | Máx. servidor | Respuestas 5xx | CPU máx. del servidor | CPU máx. por contenedor | Memoria máx. (límite) |
|---|---|---|---|---|---|---|---|
| carga | 88 ms / 88 ms | 111 ms | 0,43 s | **0** | 22,7 % | — | — |
| estrés | 112 ms / 109 ms | 194–207 ms | 0,52 s | **0** | 53,4 % | API 94,6 % de 1 núcleo; cliente 11,5 %; MariaDB 1,7 % | API 274/512 MB; cliente 218/512 MB; MariaDB 139/384 MB |

Durante las pruebas no hubo reinicios de contenedores, ni procesos terminados por falta de memoria (OOM), ni alertas de latencia o de errores 5xx.

## 3. Análisis

1. **Latencia.** Con 10 usuarios concurrentes el p95 de extremo a extremo es de **169 ms**, unas 4,7 veces por debajo del objetivo de 800 ms. Con 40 usuarios sube apenas a **206 ms**: la latencia que percibe el usuario **casi no se degrada** al cuadruplicar la carga.

2. **Latencia de red frente a la del servidor.** El servidor responde en p95 ≈ 88–112 ms. La diferencia con lo que mide k6 (≈ 70–100 ms extra) es el recorrido México ↔ región *northcentralus* de Azure. Por eso, para usuarios en México la ubicación de la región pesa más que el código.

3. **Throughput.** Pasó de 11,9 req/s (10 VU) a **22,2 req/s** (40 VU). No crece de forma lineal con los usuarios porque cada iteración incluye de 2 a 4 s de pausa, como un usuario real. La capacidad no se agotó: la CPU total del servidor quedó en **53 %**.

4. **Cuello de botella.** Es el **login**: su p95 es el más alto (298 ms en estrés) y la **API llegó a 94,6 % de un núcleo**, mientras el cliente y MariaDB apenas se usaron. La causa es BCrypt (costo 10), que es **costoso a propósito** para dificultar ataques de fuerza bruta. Es una decisión de seguridad, no un defecto.

5. **Errores en estrés (0,50 %).** Los 40 errores son `EOF` (conexión cerrada) y aparecen solo entre 17:02 y 17:03 UTC, en el escalón de 30 a 40 VU. Junto con el p99 de 3,28 s y el máximo de 60 s, **no tienen correspondencia en el servidor**:
   - Prometheus no registró ninguna respuesta 5xx y el máximo del servidor fue de 0,52 s.
   - Los logs de la API y el cliente no tienen errores en esa ventana.
   - No hubo reinicios ni OOM.

   **Conclusión:** se originaron en el camino de red del **generador de carga**: la red NAT de Docker Desktop en una laptop con 2,7 GB para Docker, más la conexión doméstica con 40 conexiones simultáneas. No son fallos de la aplicación (ver INC-15).

6. **Calidad encontrada por la prueba.** El primer humo descubrió un **defecto real** (INC-14): `Transfer-Encoding: chunked` duplicado en `/verificarLogin`. Los navegadores lo toleraban, pero hacía fallar el 100 % de los logins en clientes HTTP estrictos. Se corrigió, se agregó una prueba unitaria y una verificación en la prueba de humo del pipeline, y se desplegó con CI/CD (App #7).

## 4. Conclusiones

- Con la carga esperada para el proyecto (decenas de usuarios), el sistema **cumple todos los criterios**: 0 % de errores con 10 usuarios, p95 < 210 ms con hasta 40 usuarios y uso de CPU ≤ 53 %.
- El componente que limitará primero la capacidad es la **API durante el login**, por BCrypt. Si hiciera falta escalar:
  - aumentar las vCPU de la VM o ejecutar más réplicas de la API;
  - mantener el costo de BCrypt; no reducirlo, porque bajaría la seguridad.
- Para pruebas de estrés más altas, el generador de carga debe correr **en otra VM de la misma región de Azure**. Así se elimina el ruido de la red doméstica y de Docker Desktop, y los percentiles altos (p99/máx.) reflejan solo al servidor.
- La correlación entre k6 (lado del usuario) y Prometheus/Grafana (lado del servidor) permitió **distinguir con evidencia** los problemas de la aplicación de los del entorno de prueba.

## 5. Archivos

| Archivo | Contenido |
|---|---|
| `prueba-carga.js` | Script de k6 (escenarios, flujo y umbrales) |
| `ejecutar.sh` | Ejecuta un escenario con Docker y guarda los reportes |
| `reportes/<escenario>-<fecha>.html` | Reporte visual de k6 (gráficas de VU, latencia y throughput en el tiempo) |
| `reportes/<escenario>-<fecha>.json` | Resumen de métricas de k6 |
| `reportes/consola-*.txt` | Salida de consola, incluidos los errores `EOF` del estrés |
| `reportes/humo-20261122-1809-FALLIDO-INC14.*` | Humo que reveló el defecto INC-14 |
