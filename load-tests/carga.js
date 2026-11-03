// Prueba de carga con k6 - Evaluacion Final DGITI
//
// Uso (desde la raiz del repositorio):
//   k6 run -e BASE_URL=http://<dns-del-alb> -e PERFIL=estres load-tests/carga.js
//
// Perfiles (variable PERFIL):
//   humo   -> 5 usuarios, 30 s: verifica que todo responde
//   carga  -> hasta 50 usuarios, ~4 min: comportamiento normal
//   estres -> hasta 200 usuarios, ~8 min: satura la CPU y dispara el Auto Scaling
//
// Que mide: tiempo de respuesta (p50/p95/p99), usuarios virtuales concurrentes,
// porcentaje de errores y como reparte el ALB las solicitudes entre zonas.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8000').replace(/\/$/, '');
const PERFIL = __ENV.PERFIL || 'carga';
const AZ_A = __ENV.AZ_A || 'us-east-1a';
const AZ_B = __ENV.AZ_B || 'us-east-1b';
const ITERACIONES = __ENV.ITERACIONES || '20000';
// IDs de las instancias en servicio al iniciar (los pasa scripts/prueba-carga.ps1): el resumen
// muestra cuantas respuestas atendio cada una = evidencia directa del reparto del ALB.
const INSTANCIAS = (__ENV.INSTANCIAS || '').split(',').map((x) => x.trim()).filter(Boolean);

const PERFILES = {
  humo: [
    { duration: '30s', target: 5 },
  ],
  carga: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 30 },
    { duration: '2m', target: 50 },
    { duration: '30s', target: 0 },
  ],
  estres: [
    { duration: '30s', target: 20 },   // calentamiento
    { duration: '1m', target: 50 },    // carga normal
    { duration: '1m30s', target: 100 }, // carga alta
    { duration: '3m', target: 200 },   // saturacion: CPU > objetivo -> escala el ASG
    { duration: '1m30s', target: 200 }, // sostenida: se ven las instancias nuevas
    { duration: '30s', target: 0 },    // recuperacion
  ],
};

if (!PERFILES[PERFIL]) {
  throw new Error(`PERFIL desconocido: ${PERFIL}. Use humo, carga o estres.`);
}

// Respuestas exitosas por zona y por instancia (evidencia del balanceo)
const respuestasPorZona = new Counter('respuestas_por_zona');
const respuestasPorInstancia = new Counter('respuestas_por_instancia');
// Tiempo que reporta la propia instancia para el calculo de CPU
const tiempoCpuServidor = new Trend('tiempo_cpu_servidor', true);

const umbralesPorInstancia = {};
for (const id of INSTANCIAS) {
  umbralesPorInstancia[`respuestas_por_instancia{instancia:${id}}`] = ['count>0'];
}

export const options = {
  scenarios: {
    usuarios: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: PERFILES[PERFIL],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],             // menos de 5% de errores
    http_req_duration: ['p(95)<2000'],          // p95 menor a 2 s
    'http_req_duration{endpoint:info}': ['p(95)<1500'],
    'http_req_duration{endpoint:compute}': ['p(95)<3000'],
    'http_req_duration{endpoint:items}': ['p(95)<2000'],
    [`respuestas_por_zona{zona:${AZ_A}}`]: ['count>0'], // el ALB envia trafico a la AZ A
    [`respuestas_por_zona{zona:${AZ_B}}`]: ['count>0'], // y a la AZ B
    ...umbralesPorInstancia, // cada instancia inicial recibio trafico
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export function setup() {
  const res = http.get(`${BASE_URL}/health`);
  if (res.status !== 200) {
    throw new Error(`El servicio no responde en ${BASE_URL}/health (status ${res.status})`);
  }
  console.log(`Objetivo: ${BASE_URL} | perfil: ${PERFIL}`);
}

export default function () {
  const r = Math.random();
  let res;
  if (r < 0.6) {
    res = http.get(`${BASE_URL}/api/compute?n=${ITERACIONES}`, { tags: { endpoint: 'compute' } });
  } else if (r < 0.9) {
    res = http.get(`${BASE_URL}/api/info`, { tags: { endpoint: 'info' } });
  } else {
    res = http.get(`${BASE_URL}/api/items?limit=10`, { tags: { endpoint: 'items' } });
  }

  const ok = check(res, {
    'status 200': (x) => x.status === 200,
    'responde una instancia': (x) => x.status === 200 && !!x.json('instance_id'),
  });

  if (ok) {
    respuestasPorZona.add(1, { zona: res.json('availability_zone') });
    respuestasPorInstancia.add(1, { instancia: res.json('instance_id') });
    const elapsed = res.json('elapsed_ms');
    if (elapsed !== null && elapsed !== undefined) {
      tiempoCpuServidor.add(elapsed);
    }
  }

  sleep(0.5);
}
