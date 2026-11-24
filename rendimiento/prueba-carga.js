// Prueba de rendimiento del Gestor de Proyectos con k6.
// Solo contra el entorno propio (VM de Azure del proyecto), con límites de usuarios y duración.
//
// Uso (con Docker):
//   docker run --rm -i -e ESCENARIO=carga -e BASE_URL=http://<fqdn> grafana/k6:2.4.0 run - < prueba-carga.js
// Escenarios: humo (1 usuario, 30 s) | carga (10 usuarios sostenidos) | estres (escalones hasta 40 usuarios)
import http from "k6/http";
import { check, group, sleep } from "k6";

const BASE = (__ENV.BASE_URL || "http://gestor-717e46.northcentralus.cloudapp.azure.com").replace(/\/$/, "");
const ESCENARIO = __ENV.ESCENARIO || "humo";

const ESCENARIOS = {
  humo: { executor: "constant-vus", vus: 1, duration: "30s" },
  carga: {
    executor: "ramping-vus",
    startVUs: 0,
    stages: [
      { duration: "1m", target: 10 }, // subida
      { duration: "3m", target: 10 }, // carga sostenida
      { duration: "30s", target: 0 }, // bajada
    ],
    gracefulRampDown: "30s",
  },
  estres: {
    executor: "ramping-vus",
    startVUs: 0,
    stages: [
      { duration: "1m", target: 10 },
      { duration: "1m30s", target: 20 },
      { duration: "1m30s", target: 30 },
      { duration: "1m30s", target: 40 },
      { duration: "30s", target: 0 },
    ],
    gracefulRampDown: "30s",
  },
};

if (!ESCENARIOS[ESCENARIO]) {
  throw new Error(`Escenario desconocido: ${ESCENARIO}`);
}

export const options = {
  scenarios: { [ESCENARIO]: ESCENARIOS[ESCENARIO] },
  // Criterios de aceptación (SLO del proyecto)
  thresholds: {
    http_req_failed: ["rate<0.01"],                       // < 1 % de errores
    "http_req_duration{tipo:consulta}": ["p(95)<800"],     // consultas p95 < 800 ms
    "http_req_duration{tipo:pagina}": ["p(95)<800"],       // páginas p95 < 800 ms
    "http_req_duration{tipo:login}": ["p(95)<1500"],       // login p95 < 1,5 s (BCrypt es costoso a propósito)
    checks: ["rate>0.99"],
  },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "p(99)", "max"],
  userAgent: "k6-prueba-gestor/1.0 (entorno propio)",
};

const JSON_HEADERS = { headers: { "Content-Type": "application/json" } };

export default function () {
  group("1. Abrir login", () => {
    const r = http.get(`${BASE}/login`, { tags: { tipo: "pagina", nombre: "GET /login" } });
    check(r, { "login: 200": (x) => x.status === 200 });
  });

  group("2. Iniciar sesión", () => {
    const r = http.post(
      `${BASE}/verificarLogin`,
      JSON.stringify({ correo_electronico: "demo1@example.com", contrasena: "Demo2026!" }),
      Object.assign({ tags: { tipo: "login", nombre: "POST /verificarLogin" } }, JSON_HEADERS)
    );
    check(r, {
      "verificarLogin: 200": (x) => x.status === 200,
      "verificarLogin: usuario válido": (x) => x.status === 200 && x.json("nombre") === "Usuario Demo Uno",
    });
  });

  sleep(1);

  group("3. Consultar proyecto", () => {
    const proyectos = http.post(`${BASE}/consultarProyectos`, null, { tags: { tipo: "consulta", nombre: "POST /consultarProyectos" } });
    check(proyectos, { "proyectos: 200 con datos": (x) => x.status === 200 && x.body.includes("id_proyecto") });

    const tareas = http.post(`${BASE}/obtenerTareas`, JSON.stringify({ id_proyecto: 197 }),
      Object.assign({ tags: { tipo: "consulta", nombre: "POST /obtenerTareas" } }, JSON_HEADERS));
    check(tareas, { "tareas: 200": (x) => x.status === 200 });

    const usuarios = http.post(`${BASE}/consultarUsuarios`, null, { tags: { tipo: "consulta", nombre: "POST /consultarUsuarios" } });
    check(usuarios, { "usuarios: 200": (x) => x.status === 200 });
  });

  // Tiempo de "lectura" del usuario entre acciones
  sleep(1 + Math.random() * 2);
}
