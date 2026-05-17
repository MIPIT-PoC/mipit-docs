# A3 — Code Quality + Architecture Deep (Audit 2)

**Fecha:** 2026-05-17 · **Branch:** `Auditoria-Claude` post-Wave 4 · **Scope:** code smells, architecture, security, perf, deps.

**LOC sigla:** core ~8.8k, ui ~4.2k, testkit ~2.8k, cada adapter ~1.5-1.7k.

## Top 5 hallazgos críticos

1. **SSE expone payments PII sin auth.** `/events/payments`, `/events/payments/:id`, `/events/clients` se registran fuera del scope autenticado (`server.ts:109`). El handler `sse.ts` no valida tokens pese al comentario in-line. Cualquier consumidor con acceso de red lee debtor/creditor alias, names, amounts, trace_ids en tiempo real. **CRÍTICA / esfuerzo bajo.**
2. **Doble registro de consumers RabbitMQ.** En `mipit-core/src/index.ts:126-138`, `AckConsumer` y `DlqHandler` se inicializan vía `reconnector.registerConsumerBootstrap` Y manualmente en canal inicial. Tras reconnect, bootstraps se reproducen → consumers duplicados → cada ACK procesado dos veces. **ALTA / esfuerzo bajo.**
3. **`reconciliation-service.findSince` carga toda la tabla en memoria.** `payment.repository.ts:316-322` hace `SELECT * FROM payments WHERE created_at >= $1 ORDER BY created_at DESC` sin LIMIT. Job recurrente cada 30 min (`index.ts:146`) → memory bomb. **ALTA / esfuerzo medio.**
4. **DLQ handler con poison-message en bucle.** `dlq-handler.ts:84` hace `nack(msg, false, true)` (requeue=true) en cualquier error. Sin retry counter. Mensaje rebota infinito. **ALTA / esfuerzo bajo.**
5. **Race condition en idempotency 2nd lookup.** `payments.ts:56-62`: cuando `tryInsert` retorna false (otro request ganó), 2do `findByKey` puede devolver `winner.response_body = null` y retorna `{ payment_id, status: 'QUEUED' }` **hardcoded**. Cliente perdedor recibe respuesta sintética. **MEDIA / esfuerzo medio.**

### Hallazgo sorpresa
`handleFailedMessage` y `shouldDeadLetter` en `dlq-handler.ts:94-146` son **código zombie** — nunca importados. Implementación "next-gen" del DLQ huérfana, el `DlqHandler.consume` usa path antiguo. ~50 LOC engañosos.

## Hallazgos por categoría

### 2.1 Code smells / Type safety

- **20 `as any` en hot path del core.** `payment.repository.ts:47-61`, `pipeline/payment-pipeline.ts:75,183`, `messaging/consumer.ts:133`, `index.ts:86`. Revelan que `PaymentIntent` no incluye campos ISO 20022 (UETR, charge_bearer, settlement/instructed amounts/currencies). Quick fix: extender `PaymentIntent` o crear `PaymentIntentIso20022`.
- **Type assertion repetida 4x para `traceId`**: `(request as unknown as Record<string, unknown>).traceId as string` en `payments.ts:23`, `translate.ts:40,121`, `error-handler.ts:7`. Falta module augmentation `declare module 'fastify' { interface FastifyRequest { traceId: string } }`.
- **3 `@typescript-eslint/no-explicit-any`** en workers adapters (`canonicalToXPayload(routeMsg.canonical as any)`).
- **TODO components UI con placeholder text visible.** `payment-card.tsx`, `payment-form.tsx`, `pix-form.tsx`, `spei-form.tsx`, `payment-status-badge.tsx` con literal `TODO:` en JSX. Stubs NO importados en ningún `page.tsx` — código zombie.
- **`TERMINAL_STATUSES` duplicado** en `webhook.service.ts:22` y literal en `consumer.ts:149`.

### 2.2 Acoplamiento / duplicación

- **Workers de adapters 95-97% idénticos.** `mipit-adapter-{pix,spei,breb}/src/worker.ts` (~120 LOC c/u) divergen solo en imports y un string de log. Mismas interfaces `PaymentRouteMessage` y `PaymentAckMessage` duplicadas 3 veces. Publishers también idénticos. Recortable ~300 LOC.
- **`BreBPermanentError` solo existe en BREB** (`mipit-adapter-breb/src/breb/retry.ts:24`). PIX/SPEI no distinguen errores permanentes vs transient — todos retrian hasta `maxRetries`. Inconsistencia.
- **Singletons module-level frenan testing**: `db.ts:4` (`let pool`), `sse.ts:26` (`const clients`), `health.ts:21` (`let healthDeps`), `circuit-breaker.ts:203` (`circuitBreakerRegistry`).
- **Helpers audit nunca usados**: `AuditService.logStatusChange`, `AuditService.logAckReceived` y equivalentes en `AuditRepository` son dead code (~50 LOC).
- **`recordIdempotencyHit` + counter `idempotencyHits`** (`observability/metrics.ts:36,58`) nunca importados — métrica zombie.

### 2.3 Concurrency / race conditions

- **Circuit breaker HALF_OPEN sin mutex.** `circuit-breaker.ts:76-94`: check + transición no atómicos. En Node single-thread funciona en práctica pero frágil.
- **Pipeline catch deja status intermedio.** `payment-pipeline.ts:281-291`: si `updateStatus(FAILED)` falla, payment queda en cualquier estado intermedio.
- **SSE broadcast iterando mutado.** `sse.ts:48-62`.
- **Reconciliation `running` flag**: si `GET /analytics/reconciliation` se llama concurrente, varios requests caen en "already running" silenciosamente.

### 2.4 Error handling

- **Fastify validation errors → 500 silencioso.** `error-handler.ts:6-34` solo distingue `ZodError` y `AppError`. Native Fastify errors (`FST_ERR_VALIDATION`) caen al genérico.
- **Consumer `nack(msg, false, false)` sin distinción.** `consumer.ts:159`: cualquier error → DLQ sin retry. Inverso al DLQ handler que requeua todo.
- **`FxService.getRates()` swallow errors.** `fx-service.ts:142-146`: si API falla, devuelve cache o FALLBACK pero **no actualiza cache** → cada request reintenta. Sin límite de retries.
- **DLQ malformed mensaje silente.** `dlq-handler.ts:50-52`: `JSON.parse` falla → `ack(msg)` + log sin dump del content.
- **Webhook sin retry, sin DLQ.** `webhook.service.ts:34-43`: fire-and-forget.

### 2.5 Performance / Observability

- **Timer leaks confirmados:**
  - `rate-limit.ts:39`: `setInterval(..., 5*60_000)` sin `.unref()`
  - `index.ts:146`: `reconInterval` sin `.unref()`
  - `sse.ts:89,135`: keepAlive intervals sin `.unref()`
  - Mocks: setTimeouts hasta 30s sin clear en `req.on('close')`
- **Logger sobrecargado.** Pipeline emite ~12 logs/payment. Para 1k TPS = 12k logs/s.
- **`findRecent` sin índice composite.** `payment.repository.ts:283-299` filtra por status + ORDER BY created_at DESC. Necesita índice `(status, created_at DESC)`.
- **Histogram buckets adapters mal escalados.** `mipit-adapter-pix/src/observability/metrics.ts:18`: `[50, 100, 250, 500, 1000, 2500, 5000, 10000]`. Mock latencia 80-450ms → buckets >5000 vacíos.
- **Recording rule `payment_latency:p95` mezcla stages.** `mipit-recording.yaml:11`: agrega TODOS los stages del histograma en un p95. Engañoso. Agregar `by (stage, le)`.
- **`HighLatency` alert con 10s para "instant payments".** `mipit-alerts.yaml:20`: `> 10000ms` p95 = 100x SLO real (~100ms). Alert que nunca dispara.
- **Tracing roto en RabbitMQ envelope.** `trace_id` en JSON message pero NO en `properties.headers.tracestate/traceparent`. OpenTelemetry no correlaciona spans cross-service automáticamente.
- **`findPercentile` mal implementado.** `analytics.ts:177-190`: devuelve `bucket.le` del primer bucket que excede target, sin interpolación lineal.

### 2.6 Dependencies bloat

- **mipit-ui — 7 deps no usadas:**
  - `@radix-ui/react-{dialog,label,select,slot,toast}` UNUSED
  - `class-variance-authority` UNUSED
  - `tailwind-merge` solo en `utils.ts` (`twMerge`). Mantener.
  - ~3 MB de node_modules, ~250 KB de chunks browser eliminables
- **OpenTelemetry drift core ↔ adapters:** Core `^0.218.0/^0.76.0`; adapters `^0.57.0/^0.55.0`. Diff de 160+ versiones / 6+ meses.
- **`mipit-observability/alerting/rules.yaml` redundante.** P07 fix migró a `prometheus/rules/mipit-alerts.yaml`; viejo nunca borrado.

### 2.7 Security

- SSE expone PII (cubierto F01)
- `/auth/token` sin rate-limit explícito en non-prod
- **Webhook URL sin allowlist (SSRF risk):** `webhook.service.ts:84` hace `fetch(url)` con URL del cliente. Atacante registra `http://169.254.169.254/latest/meta-data/` (AWS metadata). Mitigación: validar IP no privada (10/8, 172.16/12, 192.168/16, 169.254/16).
- **`Math.random()` en `breb-to-canonical.ts:121`** para "unique suffix". Verificar si es trace_id user-visible.
- **SSE `X-Accel-Buffering: no` + `Access-Control-Allow-Origin: *`** choca con CORS allowlist del resto del API.
- **CSRF: no token.** Endpoints POST autenticados confían en JWT en Authorization header. Si la UI usa cookies por algún path, vulnerable.

### 2.8 Test coverage

- **Wave 2-4 components sin unit tests:**
  - `resilience/reconnect.ts` (crítico, RabbitMQReconnector)
  - `resilience/circuit-breaker.ts`
  - `webhooks/webhook.service.ts`
  - `reconciliation/reconciliation-service.ts`
  - `compensation/compensation-service.ts`
  - `fx/fx-service.ts`
  - `messaging/dlq-handler.ts`
- **mipit-adapter-breb tiene MENOS tests que PIX/SPEI**: 3 vs 8/9. Falta `worker.test.ts`, `retry.test.ts`, `publisher.test.ts`, `health-server.test.ts`.
- **`--forceExit --detectOpenHandles`** en `package.json:16` mata proceso por timers no unref'd. Esconde el problema.

## Quick Wins (≤30 min cada uno)

1. **F01** — Añadir `verifyToken(req.query.token)` en SSE handlers (`sse.ts:69,113`).
2. **F02** — Borrar `index.ts:137-143` (manual `new AckConsumer/DlqHandler`); confiar solo en bootstraps.
3. **F06** — Timer `.unref()` en `rate-limit.ts:39`, `index.ts:146`, `sse.ts:89,135`. Remove `--forceExit` de jest.
4. **F13** — `npm uninstall @radix-ui/react-{dialog,label,select,slot,toast} class-variance-authority` en `mipit-ui`.
5. **F14** — Borrar `payment-card.tsx`, `payment-form.tsx`, `spei-form.tsx`, `pix-form.tsx`. Fixar `payment-status-badge.tsx`.
6. **F15** — Borrar `dlq-handler.ts:94-146`, helpers audit unused, `idempotencyHits` counter, etc.
7. **F16** — `git rm mipit-observability/alerting/rules.yaml`.
8. **F18** — Health adapters: chequear `channel.checkExchange(env.EXCHANGE_NAME)`.
9. **F23** — Bajar a `log.debug` los pasos intermedios en pipeline.
10. **F25** — Promover 15 campos ISO 20022 a `PaymentIntent`, elimina `as any`.
11. **F17** — En `publisher.ts:42-50`, agregar `headers: { 'mipit-trace-id': trace_id, traceparent }`.
12. **Module augmentation Fastify** — `src/types/fastify.d.ts` para eliminar 4 type-assertions ugly.
13. **F20** — `findPercentile` con interpolación lineal entre buckets adyacentes.
14. **F24** — Cachear `runReconciliation` 60s; servir cache salvo `?refresh=true`.

## Architecture mayor (pre-producción)

### R1. Extraer `@mipit/adapter-runtime`
360 LOC duplicados al 97% en 3 workers. Mismo publisher.ts, mismo package.json. Resultado: cada adapter ~30 LOC importando `runAdapterWorker`. Reducción ~300 LOC.

### R2. `@mipit/contracts` versionado
Zod schemas + ts types + JSON Schema export desde una sola fuente. Validar publishers y consumers en runtime contra el mismo schema. Permite generar OpenAPI desde una sola SoT.

### R3. Idempotency middleware (no en handler)
`payments.ts:26-77` mezcla parsing + idempotency + pipeline. Refactor: middleware con pre/post-handler hooks. Race F05 se elimina con NOTIFY/LISTEN: perdedor espera `idempotency_completed:<key>`.

### R4. Outbox pattern para webhooks
`webhook.service.ts:34-43` fire-and-forget; si proceso muere entre DB commit y webhook fire, se pierde. Proponer tabla `webhook_outbox(id, payment_id, url, payload, signature, status, attempts, next_retry_at)` + worker dedicado con retry exponencial.

### R5. Circuit breaker integrado en publisher + adapter HTTP clients
CB solo se usa en `ui-proxy.ts` y `analytics.ts`. NO protege `publisher.publishToAdapter` ni adapter clients. En producción, wrap fetch calls con `circuitBreakerRegistry.get('rail-X-http').execute(...)`.

### R6. Property-based tests con fast-check
Reemplazar suites validation/generators ad-hoc. Invariantes: roundtrip translation, pipeline always reaches terminal, FX symmetry.

### R7. DI container (eliminar singletons module-level)
`db.ts:4`, `health.ts:21`, `sse.ts:26`, `circuit-breaker.ts:203` rompen testability paralelo.

### R8. OpenTelemetry alineado vía workspaces
pnpm workspace que comparta `@opentelemetry/*`, `amqplib`, `prom-client` versions. Eliminar drift core ↔ adapters.

## Conclusión

Wave 1-4 cerró los hallazgos macro pero dejó cicatrices:
- `as any` que evidencian model debt (ISO fields nunca promovidos al type)
- Duplicación masiva en 3 adapters (no se extrajo runtime común)
- 0% cobertura unit en componentes Wave 2-4 (reconnect/CB/webhook/FX/reconciliation/compensation/DLQ)
- Dead code ~150 LOC
- Stubs UI con `TODO:` visible
- Timer leaks ocultados por `--forceExit`
- **Vulnerabilidad SSE — debe cerrarse antes de demo externa**

Para producción: Quick Wins + R1 + R2 + R4 + R5 mínimo.
