# Tareas semanales — Nicolas

Resumen de todos los tickets asignados a Nicolas por semana.

> **Estado actual**: Semanas 5 y 6 completadas. Semana 7 es la próxima.

---

## Semana 5 — Infraestructura + Capa de Persistencia ✅ COMPLETADA

**Branch:** `Nicolas_05`  
**Objetivo de la semana:** Implementar observabilidad (OTel, logger, métricas), conexión a PostgreSQL y los tres repositorios de soporte (idempotencia, reglas de ruteo, mappings). Sin esto Carlos no puede avanzar con payment/audit ni el resto del core.

---

### CORE-002 — Implementar `src/observability/otel.ts` (P1)

**Qué hacer**
- En el repo **mipit-core**, archivo `src/observability/otel.ts`:
  - Inicializar el **NodeSDK** de OpenTelemetry.
  - Crear un **Resource** con atributo `service.name` = `env.OTEL_SERVICE_NAME` (o similar desde `env`).
  - Configurar **OTLPTraceExporter** apuntando a `env.OTEL_EXPORTER_OTLP_ENDPOINT` (ej. `http://localhost:4318/v1/traces` en dev, en Docker será el hostname de Jaeger).
  - Registrar **auto-instrumentations** para: `@opentelemetry/instrumentation-http`, `@opentelemetry/instrumentation-fastify`, `@opentelemetry/instrumentation-pg`, `@opentelemetry/instrumentation-amqplib` (o los paquetes que use el proyecto) para que HTTP, Fastify, PostgreSQL y RabbitMQ generen spans automáticamente.
  - Exportar una función `initTelemetry()` que inicia el SDK y una referencia al `sdk` para poder llamar `sdk.shutdown()` en el graceful shutdown de `index.ts`.

**Criterio de listo**
- Al arrancar el core, en Jaeger aparece al menos un span (por ejemplo del health check o de una query a DB).
- Al cerrar el proceso con SIGTERM/SIGINT, se llama `sdk.shutdown()` para no perder traces.

**Impacto**
- Todo el flujo tendrá `trace_id`; ese ID se propagará luego por headers a RabbitMQ y adapters para trazabilidad distribuida.

---

### CORE-003 — Implementar `src/observability/logger.ts` (P1)

**Qué hacer**
- En **mipit-core**, archivo `src/observability/logger.ts`:
  - Crear una instancia de **Pino** con:
    - `level`: leer de `env.LOG_LEVEL` (ej. `info`, `debug`).
    - `timestamp`: función que retorna `{ time: new Date().toISOString() }` (o equivalente en formato ISO).
    - Campo base `service`: valor de `env.OTEL_SERVICE_NAME` (ej. `mipit-core`).
  - Exportar esa instancia como `logger` para que el resto del código use `logger.info()`, `logger.error()`, etc., en formato JSON estructurado.

**Criterio de listo**
- Los logs se ven en stdout en JSON (nivel, timestamp, service, msg, y cualquier campo extra).
- Cambiar `LOG_LEVEL=debug` aumenta la cantidad de logs.

**Impacto**
- Usado en todos los módulos (persistencia, pipeline, API, consumer) para debugging y auditoría.

---

### CORE-004 — Implementar `src/persistence/db.ts` (P0)

**Qué hacer**
- En **mipit-core**, archivo `src/persistence/db.ts`:
  - Crear un **Pool** de `pg` usando `env.DATABASE_URL` (ej. `postgres://mipit:mipit_secret@localhost:5432/mipit`).
  - Parámetros sugeridos: `max: 20`, `idleTimeoutMillis: 30000`, `connectionTimeoutMillis: 5000`.
  - Exportar una función **`connectDb()`** que:
    - Cree el pool si no existe.
    - Ejecute `pool.query('SELECT 1')` para verificar conectividad.
    - Retorne el pool (o un objeto `{ pool }`) para que los repositorios lo usen.
  - Exportar **`pool`** (o el getter correspondiente) para que los repos inyecten el cliente en sus queries.

**Criterio de listo**
- Al llamar `connectDb()` con un PostgreSQL levantado (p. ej. con Docker), no hay error y una query `SELECT 1` responde correctamente.
- Si `DATABASE_URL` apunta a un host inalcanzable, `connectDb()` falla con un error claro.

**Impacto**
- Es la base de toda la persistencia: pagos, auditoría, idempotencia, reglas de ruteo y mappings dependen de este pool. Sin CORE-004 no se pueden implementar CORE-006 a CORE-011.

---

### CORE-005 — Implementar `src/observability/metrics.ts` (P2)

**Qué hacer**
- En **mipit-core**, archivo `src/observability/metrics.ts`:
  - Usar **prom-client** (o el cliente Prometheus que use el proyecto).
  - Definir y registrar estas 5 métricas:
    1. **`mipit_payments_total`** (Counter): labels `status`, `origin_rail`, `destination_rail`.
    2. **`mipit_payment_latency_ms`** (Histogram): label `stage`; buckets sugeridos para latencia (ej. 5, 10, 25, 50, 100, 250, 500, 1000, 2500 ms).
    3. **`mipit_translation_errors_total`** (Counter): labels `rail`, `error_type`.
    4. **`mipit_routing_decisions_total`** (Counter): labels `rule`, `destination_rail`.
    5. **`mipit_idempotency_hits_total`** (Counter): sin labels.
  - Exportar el **registry** (o las métricas) para que la ruta `/metrics` del core exponga el formato Prometheus.

**Criterio de listo**
- Al hacer `GET /metrics` (cuando el servidor esté levantado), se ven las 5 métricas con nombres y tipos correctos; pueden estar en 0 hasta que el pipeline las use.

**Impacto**
- Alimenta los dashboards de Grafana y permite medir latencias por etapa y tasas de error en traducción y ruteo.

---

### CORE-009 — Implementar `idempotency.repository.ts` (P0)

**Qué hacer**
- En **mipit-core**, archivo `src/persistence/repositories/idempotency.repository.ts`:
  - Implementar **`findByKey(hashedKey: string)`**: `SELECT * FROM idempotency_keys WHERE hashed_key = $1` (y opcionalmente filtro por ventana de 24h si está en el esquema). Retornar la fila si existe (incluyendo `response_status_code`, `response_body` si ya hay respuesta cacheada).
  - Implementar **`insert(hashedKey: string, method: string, path: string)`**: `INSERT INTO idempotency_keys (id, hashed_key, method, path, ...)` con ULID para `id`. El hash del Idempotency-Key (SHA-256) se calcula en el middleware, no en el repo.
  - Implementar **`updateResponse(hashedKey: string, statusCode: number, responseBody: string)`**: `UPDATE idempotency_keys SET response_status_code = $2, response_body = $3, updated_at = NOW() WHERE hashed_key = $1`.
  - Usar las constantes de SQL definidas en `src/persistence/queries/index.ts` (FIND_IDEMPOTENCY_KEY, INSERT_IDEMPOTENCY, UPDATE_IDEMPOTENCY_RESPONSE) si ya existen; si no, definirlas ahí y usarlas aquí.

**Criterio de listo**
- Después de insertar una key, `findByKey` la encuentra.
- Después de `updateResponse`, `findByKey` devuelve status y body; el middleware podrá devolver esa respuesta en requests duplicados sin volver a ejecutar el pipeline.

**Impacto**
- Es la base del middleware de idempotencia (CORE-033): evita procesar dos veces el mismo pago cuando el cliente reenvía el mismo `Idempotency-Key`.

---

### CORE-010 — Implementar `route-rule.repository.ts` (P1)

**Qué hacer**
- En **mipit-core**, archivo `src/persistence/repositories/route-rule.repository.ts`:
  - **`findActive()`**: `SELECT * FROM route_rules WHERE is_active = true ORDER BY priority ASC`. Mapear filas al tipo `RouteRule` (id, name, priority, condition_type, condition_value, destination_rail, etc., según el esquema de `route_rules`).
  - **`findById(id: string)`**: `SELECT * FROM route_rules WHERE id = $1`. Retornar una sola regla o null.
  - Usar queries de `persistence/queries/index.ts` (FIND_ACTIVE_RULES, FIND_RULE_BY_ID o equivalente) con parámetros `$1`, `$2` para evitar SQL injection.

**Criterio de listo**
- Con los seeds cargados (5 reglas), `findActive()` retorna 5 registros ordenados por `priority` ascendente (menor número = mayor prioridad).
- `findById` con un id existente retorna esa regla.

**Impacto**
- El route engine (CORE-023) usará estas reglas para decidir si un pago va a PIX o SPEI según alias/país/tipo de credencial.

---

### CORE-011 — Implementar `mapping.repository.ts` (P1)

**Qué hacer**
- En **mipit-core**, archivo `src/persistence/repositories/mapping.repository.ts`:
  - **`findByRail(rail: string, direction: string)`**: `SELECT * FROM mapping_table WHERE rail = $1 AND direction = $2`. `direction` es `TO_CANONICAL` o `FROM_CANONICAL`. Retornar array de entradas tipadas (ej. `MappingEntry`: source_field, target_field, transformation, validation_rule, etc., según la tabla `mapping_table`).
  - **`findAll()`**: `SELECT * FROM mapping_table` (útil para tests o para cachear todo). Retornar array de `MappingEntry`.
  - Usar queries de `persistence/queries/index.ts` (FIND_MAPPINGS_BY_RAIL, FIND_ALL_MAPPINGS o equivalente).

**Criterio de listo**
- `findByRail('PIX', 'TO_CANONICAL')` retorna las filas correspondientes (13 en el seed). `findByRail('PIX', 'FROM_CANONICAL')` retorna las suyas (9). Igual para SPEI.
- Los tipos coinciden con el esquema de la tabla (source_field, target_field, transformation, etc.).

**Impacto**
- El mapping loader (CORE-012) y los mappers de traducción (CORE-013 a CORE-016) usan estos datos para convertir entre formato PIX/SPEI y el canónico pacs.008.

---

## Resumen Semana 5 — Nicolas

| ID       | Título                         | Prioridad | Repo      |
|----------|--------------------------------|-----------|-----------|
| CORE-002 | otel.ts (OpenTelemetry)        | P1        | mipit-core |
| CORE-003 | logger.ts (Pino)               | P1        | mipit-core |
| CORE-004 | db.ts (PostgreSQL Pool)        | P0        | mipit-core |
| CORE-005 | metrics.ts (Prometheus)        | P2        | mipit-core |
| CORE-009 | idempotency.repository.ts      | P0        | mipit-core |
| CORE-010 | route-rule.repository.ts       | P1        | mipit-core |
| CORE-011 | mapping.repository.ts          | P1        | mipit-core |

**Orden sugerido:** CORE-004 (DB) primero para poder probar los repos; en paralelo o después CORE-002, CORE-003, CORE-005; luego CORE-009, CORE-010, CORE-011 (dependen de pool y de que existan las queries en `persistence/queries/index.ts`; si Carlos no las tiene listas, definirlas junto con él).

---

## Semanas 6 a 17 — Listado por semana

### Semana 6 — Branch `Nicolas_06` ✅ COMPLETADA
- **CORE-012 a CORE-024** — Nicolas cubrió los 13 tickets (ambas ramas)
- 57 unit tests pasando  
- Cache TTL, FX detection, logging/metrics integrados  

### Semana 7 — Branch `Nicolas_07`
- **CORE-028** — payment-pipeline.ts (7 pasos)  
- **CORE-029** — consumer.ts (ACK)  
- **CORE-030** — Integration test pipeline → DB  

### Semana 8 — Branch `Nicolas_08`
- **CORE-034** — Middleware JWT auth  
- **CORE-035** — Middleware tracing (X-Trace-ID)  
- **CORE-036** — server.ts + index.ts bootstrap  
- **CORE-037** — Integration test HTTP → pipeline → DB  

### Semana 9 — Branch `Nicolas_09`
- **SPEI-001** — adapter-spei worker.ts  
- **SPEI-002** — mapper.ts + response-mapper.ts SPEI  
- **SPEI-003** — client.ts con retry  
- **SPEI-004** — Mock server SPEI + bootstrap  

### Semana 10 — Branch `Nicolas_10`
- **UI-005** — Simulation page completa  
- **UI-006** — Payment Detail page (timeline + message inspector)  
- **UI-007** — History page  
- **UI-008** — payment-card + status-badge  

### Semana 11 — Branch `Nicolas_11`
- **TEST-004** — E2E PIX → SPEI  
- **TEST-005** — E2E SPEI → PIX  
- **TEST-006** — Bug fixes E2E  
- **TEST-007** — Verificar observabilidad (Jaeger, Prometheus, Grafana)  

### Semana 12 — Branch `Nicolas_12`
- **STAB-002** — Evidence generation scripts  
- **STAB-003** — Actualizar READMEs  
- **STAB-004** — Demo runbook verificado end-to-end  

### Semana 13 — Branch `Nicolas_13`
- **DEPLOY-003** — VM3 (UI + Nginx + Observabilidad)  
- **DEPLOY-004** — Smoke test en entorno VM  
- **CI-001** — GitHub Actions (lint + build + test)  

### Semana 14 — Branch `Nicolas_14`
- **SEC-003** — JWT con expiración + script generate-jwt  
- **SEC-004** — Security headers y CORS estricto  

### Semana 15 — Branch `Nicolas_15`
- **PERF-003** — Profiling y optimización de latencia end-to-end (cache ya hecho en S6)
- **PERF-004** — Benchmark 100 txns concurrentes

### Semana 16 — Branch `Nicolas_16`
- **DOC-003** — Copiar PDFs tesis a mipit-docs  
- **DOC-004** — Capítulo de resultados: evidencia técnica  

### Semana 17 — Branch `Nicolas_17`
- **DEMO-003** — Fix issues dry run #1  
- **DEMO-004** — Slides de presentación  
- **EXTRA-003** — Dark mode UI  
- **EXTRA-004** — Health dashboard mejorado  
- **FINAL-003** — README principal (enlace a 8 repos)  
- **FINAL-004** — Backup y entrega  

---

*Documento generado a partir de `PLAN-DE-DESARROLLO.md`.*
