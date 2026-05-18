# Wave 8 — Architecture para Producción

**Fecha planeada:** post-sustentación si MIPIT continúa como base para una versión productiva
**Branch sugerida:** `Auditoria-Claude` o branch nueva `production-ready`
**Origen:** Bloque C del documento maestro [AUDITORIA-2-2026-05-17.md](../audits/AUDITORIA-2-2026-05-17.md) — refactors arquitecturales mayores (R1–R8 de A3) + completar lo que la propuesta marcó pero no se entregó (RF19, RNF re-medidos)
**Estado:** ⏳ Planeada (no iniciada)
**Estimado:** ~7–10 días concentrados (no bloquea sustentación)

---

## Objetivo

Llevar MIPIT de PoC defendible a **MVP productivo defendible ante revisores ISO 20022 / SWIFT CBPR+**. Cierra los hallazgos críticos de A3 (code quality), implementa los RF/RNF declarados en SRS pero no entregados, y deja el sistema en estado de "ready for sandbox conexión real" (lo cual requiere licencia financiera y queda fuera del scope académico — pero la arquitectura debe estar lista).

## Tickets propuestos (28)

### Refactors arquitecturales mayores (8)

| ID | Cambio | Repos | Audit | Días |
|---|---|---|---|---|
| **W8.1 ARCH-001** | Crear paquete `@mipit/adapter-runtime` compartido. Los 3 workers PIX/SPEI/BRE_B son 95-97% idénticos (~360 LOC duplicada); extraer `runAdapterWorker(handler, metrics, rail)` genérico + tipos `PaymentRouteMessage`/`PaymentAckMessage` + `publishAck`. Cada adapter queda en ~30 LOC importando el runtime. Reducción estimada: 300 LOC. | core + 3 adapters | F08, F28, C10 | 1–2 días |
| **W8.2 ARCH-002** | Crear `@mipit/contracts` versionado con Zod schemas + ts types + JSON Schema + OpenAPI export desde una sola fuente. Validar publishers y consumers en runtime contra el mismo schema. | core + 3 adapters + ui | A5-A3/A4/A7, F25, R2 | 1 día |
| **W8.3 ARCH-003** | Idempotency middleware (separar de route handler). NOTIFY/LISTEN para resolver el race del 2nd lookup donde el perdedor recibe respuesta sintética `{status:'QUEUED'}` hardcoded. | core | F05, R3 | 0.5 día |
| **W8.4 ARCH-004** | Outbox pattern para webhooks: tabla `webhook_outbox(id, payment_id, url, payload, signature, status, attempts, next_retry_at)` + worker dedicado con retry exponencial. Garantía at-least-once. Hoy `webhook.service.ts:34-43` hace fire-and-forget. | core + infra (migration) | F33, R4 (B4 fix definitivo) | 1 día |
| **W8.5 ARCH-005** | Circuit breaker integrado en publisher + 3 adapter HTTP clients. Hoy CB solo se usa en `ui-proxy.ts:17` (admin endpoints). En producción, cada fetch que sale del proceso debería pasar por CB. | core + 3 adapters | F22, R5 (B2 master) | 1 día |
| **W8.6 ARCH-006** | Property-based tests con `fast-check`. Invariantes: roundtrip translation (`fromCanonical(toCanonical(x)) ≈ x`), FX symmetry (`convert(A,B)*convert(B,A) ≈ 1`), pipeline siempre alcanza un estado terminal. Cubre miles de casos automáticos. | core + testkit | F21, F39, R6 | 2 días |
| **W8.7 ARCH-007** | DI container — eliminar singletons module-level (`db.ts:4 let pool`, `health.ts:21 let healthDeps`, `sse.ts:26 const clients`, `circuit-breaker.ts:203 circuitBreakerRegistry`). Constructor injection. Habilita tests paralelos sin race en estado global. | core | F29, R7 | 1 día |
| **W8.8 ARCH-008** | pnpm workspace + alignment de versiones OpenTelemetry/amqplib/prom-client entre core y adapters (hoy hay drift de 6+ meses; OTel core `^0.218.0` vs adapters `^0.57.0`). Resuelve también el error TS pre-existente en `otel.ts:5` (`resourceFromAttributes` no exportado en versión adapter). | core + 3 adapters | F11, A5-I (OTel drift), R8 | 0.5 día |

### Performance + observability fixes (10)

| ID | Cambio | Repos | Audit | Tiempo |
|---|---|---|---|---|
| **W8.9 PERF-001** | `reconciliation-service.findSince` con LIMIT + cursor pagination. Actualmente carga toda la tabla `payments` en memoria sin LIMIT. Memory bomb en producción. | core | F03 master | 1 día |
| **W8.10 PERF-002** | DLQ retry counter en headers (`x-mipit-dlq-attempts`). Descartar tras max=3 a tabla `payments_dead`. Hoy `dlq-handler.ts:84` hace `nack(false, true)` (requeue=true) sin counter → poison message en bucle infinito. | core + infra (migration) | F04 master | 0.5 día |
| **W8.11 PERF-003** | Prometheus recording rules separar por stage (`by (stage, le)`). Actualmente `payment_latency:p95` agrega todos los stages en un solo p95 — engañoso. | observability | F10 | 30 min |
| **W8.12 PERF-004** | Trace context propagation: `publisher.ts` agrega `traceparent` + `tracestate` W3C headers en los mensajes RabbitMQ; consumer los lee y propaga al span OTel. Hoy `trace_id` viaja en JSON del mensaje pero no como header W3C, así que cross-service spans en Jaeger no se correlan automáticamente. | core + 3 adapters | F17 | 0.5 día |
| **W8.13 PERF-005** | Logger refactor: pasos intermedios (translation, normalization, routing, FX) a `log.debug`. Mantener `log.info` solo en boundaries (start + complete + error). Reduce de ~12 logs/payment a ~3. | core | F23 | 20 min |
| **W8.14 PERF-006** | DB índice composite `(status, created_at DESC)` para `findRecent`. Hoy usa índices separados y PG hace bitmap heap scan ineficiente. | infra (migration) | F36 | 10 min |
| **W8.15 PERF-007** | `findPercentile` con interpolación lineal entre buckets adyacentes en lugar de devolver `bucket.le` del primero que excede target. | core | F20 | 30 min |
| **W8.16 PERF-008** | Health adapters verifica `channel.checkExchange(env.EXCHANGE_NAME)` antes de devolver ok. Hoy es superficial (sólo `200 ok` independientemente del estado de RabbitMQ). | 3 adapters | F18 | 15 min |
| **W8.17 PERF-009** | Cachear `runReconciliation` 60s; servir cache salvo `?refresh=true`. Hoy `GET /analytics/reconciliation` dispara DB scan en cada request. | core | F24 | 30 min |
| **W8.18 PERF-010** | Timer leaks: `.unref()` en `rate-limit.ts:39`, `index.ts:146`, `sse.ts:89,135`. Quitar `--forceExit` de jest. Hoy los timers no-unref'd causan "worker process force exited" warnings y se ocultan con `--forceExit`. | core | F06, F40 | 30 min |

### Type safety + cleanups (3)

| ID | Cambio | Repos | Audit | Tiempo |
|---|---|---|---|---|
| **W8.19 TYPE-001** | Module augmentation Fastify `traceId` en `src/types/fastify.d.ts` con `declare module 'fastify' { interface FastifyRequest { traceId: string } }`. Elimina 4 type-assertions ugly (`(req as unknown as Record<...>).traceId as string`). | core | F26 | 10 min |
| **W8.20 BUG-001** | Borrar double-registered consumers en `mipit-core/src/index.ts:137-143` (confiar sólo en los bootstraps registrados; tras reconnect los bootstraps se reproducen → consumers duplicados → cada ACK procesado 2 veces). | core | F02, C9 master | 20 min |
| **W8.21 BUG-002** | Promover los 15 campos ISO 20022 (uetr, end_to_end_id, charge_bearer, instructed_*, settlement_*, exchange_rate, etc.) a `PaymentIntent` type. Elimina 20+ `(payment as any).fieldname` en `repository.create` y otros sites. | core | F25, A5-G3 | 20 min |

### Security (3)

| ID | Cambio | Repos | Audit | Tiempo |
|---|---|---|---|---|
| **W8.22 SEC-001** | SSRF mitigation: validar webhook URL no resuelve a IP privada (10/8, 172.16/12, 192.168/16, 169.254/16, ::1) antes del fetch. Hoy `webhook.service.ts:84` hace `fetch(url)` con URL arbitraria del cliente — un atacante podría registrar `http://169.254.169.254/latest/meta-data/` (AWS metadata) y MIPIT lo fetch desde la VPC. | core | F09 | 1 hora |
| **W8.23 SEC-002** | `/auth/token` 404 en producción (`NODE_ENV=production`). Token issuer out-of-band via `tools/issue-token.sh`. Hoy con `NODE_ENV=development` emite tokens sin credenciales. | core + tools | Q15 | 30 min |
| **W8.24 SEC-003** | JWT secret fuera del repo. Hoy `mipit-infra/env/core.env:5` lo tiene committed (`JWT_SECRET=mipit-poc-jwt-secret-change-in-production`). Mover a `.env.local` gitignored o KMS para prod. | infra | Q11 | 30 min |

### Test coverage (2)

| ID | Cambio | Repos | Audit | Tiempo |
|---|---|---|---|---|
| **W8.25 TEST-COV** | Unit tests para Wave 2-4 components sin cobertura: `resilience/reconnect.ts`, `resilience/circuit-breaker.ts`, `webhooks/webhook.service.ts`, `reconciliation/reconciliation-service.ts`, `compensation/compensation-service.ts`, `fx/fx-service.ts`, `messaging/dlq-handler.ts`. Target: 70% coverage. | core | F21 | 2 días |
| **W8.26 TEST-BREB** | `mipit-adapter-breb` tests al nivel pix/spei (44 → ~80): agregar `worker.test.ts`, `retry.test.ts`, `publisher.test.ts`, `health-server.test.ts`. | adapter-breb | F39 | 1 día |

### Cumplimiento RF/RNF declarado en SRS (2)

| ID | Cambio | Repos | Audit | Tiempo |
|---|---|---|---|---|
| **W8.27 RF19** | Implementar export CSV/JSON en `GET /payments?format=csv` y `GET /audit-events?format=json`. Es el único RF declarado en SRS sin scope-out documentado (cumplido 19/20). | core | T-001 | 3 horas |
| **W8.28 BENCH-001** | Re-medir RNF de la propuesta: throughput (declarado 100 TPS), latencia p95-p99, disponibilidad. Documentar en `evidence/benchmark-2026-05-18.md` con K6 o autocannon. RNF actuales sólo validados en histórico 2026-05-15. | core + testkit + evidence | T-003 | 0.5 día |

### Regulatory (1, opcional)

| ID | Cambio | Repos | Audit | Tiempo |
|---|---|---|---|---|
| **W8.29 REGUL-001** | Middleware `regulatory-threshold.ts`: detecta `amount >= USD-equivalent-of-10000` → stamp en audit + `regulatory_flagged: true`. No bloquea ni reporta a regulador (eso requiere integración formal), pero documenta intención. Sólo aplica si la tesis quiere defender awareness regulatorio. | core | N-007 | 0.5 día |

## Criterios de éxito

- ✅ `npm test` corre sin `--forceExit`
- ✅ Cobertura unit >70% en Wave 2-4 components
- ✅ pacs.008 generado pasa XSD validator oficial
- ✅ Cross-service trace en Jaeger atraviesa core → publisher → adapter sin gaps
- ✅ Circuit breaker se observa abriéndose en `/analytics/circuit-breakers` cuando se detiene un adapter
- ✅ DLQ retry counter visible en headers; mensajes poison no rebotan más
- ✅ Reconciliation procesa 100k pagos sin memory issue (cursor pagination)
- ✅ Benchmark K6 demuestra ≥100 TPS sostenidos (RF de la propuesta)

## Dependencias

- **Wave 7** (SoT) es ideal antes pero no bloqueante — los `@mipit/shared-types` de Wave 7 se pueden fusionar con `@mipit/contracts` de Wave 8 W8.2
- **Wave 6** ya cerró los hallazgos ISO 20022 críticos; Wave 8 solo agrega fidelity adicional (W8.12 trace headers)

## Roadmap sugerido (10 días)

| Día | Bloque |
|---|---|
| 1–2 | W8.1 (adapter-runtime) + W8.2 (contracts) |
| 3 | W8.3 (idempotency middleware) + W8.4 (webhook outbox) |
| 4 | W8.5 (CB integrado) + W8.7 (DI container) |
| 5 | W8.8 (OTel alignment) + W8.9 (reconciliation cursor) + W8.10 (DLQ counter) |
| 6 | W8.11–W8.18 (perf + obs batch) + W8.19–W8.21 (types/bugs) |
| 7 | W8.22–W8.24 (security) |
| 8–9 | W8.6 (property-based tests) + W8.25 (Wave 2-4 unit coverage) |
| 10 | W8.26 (BREB tests) + W8.27 (RF19) + W8.28 (benchmark) |

## Cuando NO hacer Wave 8

- Si el proyecto termina en la sustentación: Wave 8 no es necesaria
- Si se va a refactorizar a otro stack (Java/Go/Rust): Wave 8 invierte tiempo en una base que se va a tirar
- Si el equipo se disuelve: documentar Wave 8 como roadmap para un sucesor en lugar de implementar

## Qué demostraría Wave 8 que no demuestra Wave 6

| Claim | Wave 6 | Wave 8 |
|---|---|---|
| "MIPIT escala a 100 TPS" | Sin medición | ✅ Benchmark K6 + p95/p99 documentados |
| "Compensación end-to-end" | pacs.004 construido + persistido | ✅ + Webhook outbox at-least-once + worker dedicado |
| "Resiliencia ante adapter caído" | CB existe pero sólo en ui-proxy | ✅ CB en publisher + cada adapter HTTP client; demoable en vivo |
| "Tests automatizados de invariantes" | Unit + integration | ✅ + property-based con fast-check |
| "Trace cross-service en Jaeger" | trace_id propagado en JSON | ✅ W3C traceparent en RabbitMQ headers → correlation automática |
| "Sin SSRF en webhooks" | URL arbitraria aceptada | ✅ Allowlist + private-IP rejection |
