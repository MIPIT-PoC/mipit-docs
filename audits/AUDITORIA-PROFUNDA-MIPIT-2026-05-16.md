# Auditoría Profunda MiPIT — 2026-05-16

> **Forensic audit completo** de los 9 repos del PoC de tesis MiPIT.
> 5 agentes paralelos auditaron código, specs oficiales (BCB, Banxico, BanRep, ISO 20022, SWIFT, FedNow, NACHA) y los PDFs originales (Propuesta, SRS, SPMP, Diseño).
> Reemplaza y extiende [AUDITORIA-MIPIT-2026-05-16.md](AUDITORIA-MIPIT-2026-05-16.md) (primera pasada).

## Cómo leer este documento

Este archivo es el **índice maestro y resumen ejecutivo**. Los reportes íntegros (~50-75 KB cada uno) están en:

- 📄 **[AUDIT-RAW-translation.md](AUDIT-RAW-translation.md)** — Translation layer (8 rieles bidireccional + canónico vs pacs.008.001.10)
- 📄 **[AUDIT-RAW-adapters.md](AUDIT-RAW-adapters.md)** — PIX/SPEI/Bre-B adapters línea por línea vs BCB OpenAPI v2.9.0 / STP WADL / BanRep Feb-2026
- 📄 **[AUDIT-RAW-ui-docs.md](AUDIT-RAW-ui-docs.md)** — UI page-by-page, testkit test-by-test, ADRs, OpenAPI drift, PDFs (Propuesta/SRS/SPMP/Diseño)
- 📋 **Inline en este doc** — Core internals (resilience, compensation, reconciliation, FX, webhooks, audit, idempotency, state machine, SQL, middleware, OTel) + Infra+DB+observability completos

---

## TL;DR — Veredicto profundo

| Pregunta | Respuesta |
|---|---|
| ¿Es honesto el código? | Sí; el código es ordenado, hay buena disciplina de logging/Zod/healthchecks. |
| ¿Es fiel a las specs oficiales? | **No para producción.** Los 3 mocks usan endpoints/auth inventados, no aguantarían un swap-base-URL real. |
| ¿Sostiene la tesis "demostrar interoperabilidad técnica"? | **Sí, parcialmente y con caveats que deben documentarse explícitamente** como limitaciones. |
| ¿Cuánto trabajo falta para defender con integridad? | Bloque 1 (1 semana): 6 fixes de criticidad. Bloque 2 (2 semanas): hardening. Bloque 3: declarar limitaciones en la tesis. |

**Agregado total nuevo (más allá de la primera pasada)**: **18 Críticos, 27 Altos, 38 Medios, 17 Bajos** ya documentados + en este pase profundo nuevos: **~25 Críticos, ~50 Altos, ~80 Medios, ~40 Bajos** distribuidos en los 5 informes.

---

# Parte I — Translation Layer (referencia: [AUDIT-RAW-translation.md](AUDIT-RAW-translation.md))

**Veredicto**: La arquitectura hub-and-spoke (un canónico + N×2 traductores) es buena tesis. La fidelidad del canónico a `pacs.008.001.10` es débil. **Ningún rail tiene round-trip lossless**.

## Hallazgos críticos (resumen — detalle completo en raw)

1. **Canónico es snake_case + camelCase híbrido** (`payment_id`, `created_at`, `trace_id` junto a `grpHdr`, `pmtId`). `src/domain/models/canonical.ts:14-138`. pacs.008 real es PascalCase XML.
2. **`ChrgBr` (mandatorio en pacs.008.001.10) está ausente del canónico**. Cada outbound emite hard-code o omite (`canonical-to-swift-mt103.ts:56` hard-codea `'SHA'`, FedNow lo omite).
3. **`UETR` (mandatorio en pacs.008.001.10) generado con `Math.random()`** (`canonical-to-fednow.ts:177-183`). SWIFT/CBPR+/FedNow lo requieren UUIDv4 CSPRNG.
4. **PIX `EndToEndId` mal formado**: spec BCB es `E + ISPB(8) + YYYYMMDDHHMM(BRT, 12) + suffix(11) = 32 chars`. Implementación: `E2E-${ulid()}` (29 chars, sin ISPB, sin timestamp BRT).
5. **Bre-B `idTransaccion` con `Math.random().toString(36)`** (`breb-to-canonical.ts:121`). No deterministico, padding degrada entropía.
6. **SPEI `claveRastreo` con guion (`-`) ilegal en CECOBAN** — `canonical-to-spei.ts:20` reutiliza `endToEndId` con prefijo `E2E-`.
7. **CLABE no se revalida en emit**: `canonical-to-spei.ts:21` blindly emits cualquier valor; un pago llegado vía SWIFT y ruteado a SPEI puede salir con CLABE inválida.
8. **ISO 20022 MX emitter omite `ChrgBr, PmtTpInf.SvcLvl, TtlIntrBkSttlmAmt, InstrForCdtrAgt/NxtAgt, RgltryRptg`** (`canonical-to-iso20022-mx.ts:28-76`).
9. **MT103 parser regex frágil**: `swift-mt103-to-canonical.ts:100` over-matches, y el amount-parser interpreta comas mal (`:32A:240515USD1,234,56` → `1234.56` en vez de `1234,56`).
10. **NACHA serializer produce archivos malformados**: padding mal (`'0'.repeat(9).substring(0,10)` = 9 chars no 10), File Control sin total-credit column.
11. **Round-trip integrity rota en TODOS los rieles** (resumen lossy en [AUDIT-RAW-translation.md §6](AUDIT-RAW-translation.md)).
12. **`mapping-loader.ts` cache sin eviction**, sin in-flight dedup; regex de validación viene de DB sin sanitizar (regex-injection risk).
13. **PIX y SPEI duplican byte-a-byte ~80 líneas** de helpers (`applyTransformation`, `getNestedValue`, etc.).
14. **Timezone**: `toISOString()` en todos lados → UTC. Bre-B txn a 23:30 Bogotá → ID con fecha del día siguiente. Mismo en PIX (BRT esperado) y SPEI (CT esperado).

## Canonical vs pacs.008.001.10 — 40 elementos requeridos/comunes, ~12 implementados, ~10 parciales, ~18 ausentes

Tabla completa en [AUDIT-RAW-translation.md §2](AUDIT-RAW-translation.md). Faltantes mandatorios destacables:

| Campo | Cardinalidad | Estado |
|---|---|---|
| `CdtTrfTxInf.PmtId.UETR` | [1..1] mandatorio v10 | ❌ Ausente |
| `CdtTrfTxInf.PmtId.TxId` | [1..1] mandatorio | ⚠️ Marcado opcional |
| `CdtTrfTxInf.ChrgBr` | [1..1] mandatorio | ❌ Ausente |
| `CdtTrfTxInf.IntrBkSttlmDt` | [1..1] mandatorio | ❌ Ausente |
| `GrpHdr.CtrlSum` | [0..1] | ❌ Ausente |
| `GrpHdr.SttlmInf.ClrSys.Cd` | [0..1] requerido para FedNow CBPR+ | ❌ Hardcoded en emitter |
| `GrpHdr.InitgPty` | [0..1] | ❌ Ausente |
| `IntrmyAgt1/2/3` | [0..1] correspondent banking | ❌ Ausente |

## pacs.002 ACK vs pacs.002.001.10 — fuertemente simplificado

`src/canonical/pacs002.schema.ts:3-15` define 7 campos. Real requiere:
- `OrgnlMsgId`, `OrgnlMsgNmId='pacs.008.001.10'`, `OrgnlCreDtTm`, `OrgnlEndToEndId`, `OrgnlUETR`, `OrgnlTxId` — todos ausentes.
- `GrpSts/TxSts` con códigos ISO `ACSC/ACSP/RJCT/PART/PDNG` — usamos `ACCEPTED/REJECTED/ERROR` (incompatible).
- `StsRsnInf.Rsn.Cd` con ExternalStatusReason1Code (`AC01`, `AC04`, `AM04`, `FF01`, `MS03`) — aceptamos cualquier string.

## Done well — cosas a conservar

Detalle en [AUDIT-RAW-translation.md §7](AUDIT-RAW-translation.md):
1. Topología hub-and-spoke clean.
2. `Zod safeParse` al final de cada `*ToCanonical`.
3. Logger child con `payment_id, rail, direction` en todos los traductores.
4. Latency timer + recordTranslationError.
5. Dual ingestion (native + generic) en PIX y Bre-B.
6. Headers + comentarios per-file con referencia a operator/format/version.
7. Interfaces TS por rail (compile-time safety).
8. CLABE mod-10 validator correcto en `payment-request.ts:4-9`.
9. Separación `canonical-to-X` (estructurado) vs `serializeX()` (FIN/XML/NACHA).
10. `wrapInDocument` composable para envelopes ISO 20022.

---

# Parte II — Core internals (NO cubierto en primera pasada)

**Auditoría inline (no en archivo raw aparte)**. Detalle abajo. Severidad legend: **C**=Critical, **H**=High, **M**=Medium, **L**=Low.

## State Machine real (descubierto por trace de código)

```
RECEIVED → VALIDATED → CANONICALIZED → (in-mem NORMALIZED) → ROUTED → QUEUED
                                                                        ↓
                                          ┌──────────────────┐
                                          │ ACK on ack queue │
                                          └──────────────────┘
                                                  ↓
                ACCEPTED → COMPLETED   REJECTED → REJECTED   ERROR → FAILED

cualquier excepción → FAILED (pipeline:182)
DLQ requeue (manual helper) → DEAD_LETTER → COMPENSATING → COMPENSATED

Defined pero unused: SENT_TO_DESTINATION, ACKED_BY_RAIL, DUPLICATE, NORMALIZED
```

**Hallazgo crítico**: la transición ROUTED→QUEUED **no es atómica**: `publisher.publishToAdapter()` (sin confirms) corre antes que `updateStatus(QUEUED)`. Crash entre las dos líneas = mensaje en queue + DB diciendo ROUTED. Reconciliation lo flag pero sin auto-remediation. (`payment-pipeline.ts:127-141`)

## Resilience (`src/resilience/`)

| Archivo | Hallazgo | Sev |
|---|---|---|
| `rate-limiter.ts` | Token bucket in-memory por riel. **`acquire()` nunca se llama en ningún sitio**; solo `getStatus`. **El rate limiter es scaffolding observable, no limita nada.** | **C** |
| `rate-limiter.ts:104-115` | Clock-skew bug — `Date.now()` hacia atrás → bucket stall | M |
| `reconnect.ts:79-129` | Reabre connection pero `AckConsumer/DlqHandler/Publisher` quedan ligados al canal viejo | **C** |
| `reconnect.ts:96` | Nuevo `'close'` handler registrado en cada reconnect → leak de event listeners; EventEmitter MaxListeners (10) advierte en reconnect #11 | H |
| `reconnect.ts:131-135` | Jitter aditivo (no full jitter AWS) | M |
| `circuit-breaker.ts` | Implementación CLOSED/OPEN/HALF_OPEN correcta pero **`execute()` nunca se llama**; circuit breaker decorativo | **C** |

## Compensation (`src/compensation/`)

`compensation-service.ts:73-87` documenta en comentario que `pacs.004` *se enviaría* en producción. **Hoy no emite mensajes, no llama adapter, solo cambia status QUEUED→COMPENSATING→COMPENSATED.** **C** — claim de "saga compensation" en marketing es overstatement.

pacs.004 PaymentReturn real requiere `RtrId, RtrRsnInf, OrgnlGrpHdr, RtrdIntrBkSttlmAmt` — nada existe.

No hay policy automatic — los únicos triggers son endpoints HTTP `/compensate/:paymentId` y `/compensate/batch`. Reconciliation cada 30min **no llama** compensate.

## Reconciliation (`src/reconciliation/`)

- `setInterval(...30*60_000)` sin guard de overlap.
- Anomaly detection corre pero produce **cero persistencia, cero métricas, cero webhook** — solo log line. No hay `reconciliation_reports` table.
- No genera camt.054 (BankToCustomerDebitCreditNotification) ni camt.053. Real reconciliation compara contra extractos bancarios; el nuestro compara status interno con status interno.
- `_auditService` inyectado pero unused (`reconciliation-service.ts:73`) — recon no audita.

## FX (`src/fx/`)

- Fuente: openexchangerates.org, free tier (USD base), **una sola fuente, sin failover**. Fallback hard-coded.
- `Math.round(converted * 100) / 100` (line 76) — fuerza 2 decimales. **JPY/HUF/CLP/COP tienen 0 decimales**; KWD/BHD tienen 3. Para COP (Bre-B) hace `420000.456 → 420000.46` que es notación inválida. **M**
- `getRate('XYZ', 'USD')` falla a 1 (line 62-63) → divisas desconocidas se convierten 1:1 silenciosamente. **M**
- No hay multi-leg conversion — todo via USD con una división. Para BRL→COP son dos FX exposures collapsed.
- `canonical.fx.local_amount` se calcula pero **los adapters PIX/SPEI/Bre-B lo ignoran** (solo FedNow lo usa). Crítico para el claim cross-currency.

## Webhooks (`src/webhooks/`)

- HMAC-SHA256 hex sobre body crudo + timing-safe verify — bien.
- **Stripe convention pide `t=<timestamp>.body` para anti-replay**; nuestro solo firma el body. Un webhook interceptado se puede replayear indefinidamente. **H**
- `Promise.allSettled` fire-and-forget (line 40-42). **Un intento solo, sin retry exponencial, sin DLQ.** **H**
- `findPending` no filtra por `fired_at IS NULL` (line 51-57) → si un pago pasa QUEUED→FAILED→REJECTED dispara webhooks 2 veces (imposible por FSM, pero el query es laxo).
- SSRF risk — `http://169.254.169.254/...` (AWS metadata) registrable. Sin denylist de IPs privadas/link-local. **L**
- No idempotency-key al receiver — si MiPIT implementara retry, receivers no podrían dedupe.

## Audit (`src/audit/`)

- Insert append-only ULID + JSONB detail — bien.
- **`AUDIT_EVENT_TYPES` enum existe pero pipeline/compensation usan string literals** (`'PAYMENT_RECEIVED'`, `'COMPENSATION_STARTED'`) que **no están en el enum**. Enum decorativo.
- `audit.repository.ts:52-54` throw si `detail` está vacío → fuerza callers a inventar dummy details.
- Sin immutability a nivel DB (faltaría `REVOKE UPDATE/DELETE`).
- Sin retention policy; tabla crece sin fin.

## Idempotency

**2 implementaciones que compiten**:
1. Middleware `src/api/middleware/idempotency.ts` — **exportado pero NUNCA registrado en `server.ts`** → dead code.
2. Route handler `src/api/routes/payments.ts:26-77` — re-implementa la lógica. Hashea el body parseado por Zod; el middleware hashearía el raw → diferentes hashes si ambos corrieran. **C**

**TTL bug confirmado**: `INSERT_IDEMPOTENCY` (`queries/index.ts:66-70`) inserta 6 columns sin `expires_at`; `FIND_IDEMPOTENCY_BY_KEY` filtra por `expires_at > NOW()`. Si la columna no tiene DEFAULT → todos los lookups fallan-open (cache miss en cada replay).

RFC compliance: no valida longitud (1-256), no devuelve `Retry-After` en in-flight, 409 sin RFC 7807 shape (`type/title/status/detail`).

## Middleware

| Middleware | Hallazgo | Sev |
|---|---|---|
| `auth.ts` | `@fastify/jwt` sin `verify: { algorithms: ['HS256'], aud, iss, maxAge }` | H |
| `auth.ts` + `server.ts:85-91` | Endpoint `/auth/token` sin auth → cualquiera con red consigue token admin con 24h | H |
| `tracing.ts` | **Doble bookkeeping**: ULID `mipit.trace_id` + OTel auto-generated traceId. Logger emite OTel ID; audit DB usa ULID. **Cross-table correlation imposible.** | H |
| `tracing.ts` (orden) | Tracing registrado DESPUÉS de sanitize en `server.ts` → rechazo de sanitize sin trace_id | M |
| `idempotency.ts` | Dead code | C |
| `rate-limit.ts` | In-memory sliding window per IP. `req.ip` sin `trustProxy: true` → detrás de proxy todos parecen una IP. | H |
| `rate-limit.ts:39-45` | `setInterval` cleanup nunca `unref()` → bloquea graceful shutdown | M |
| `sanitize.ts` | Regex anti-SQL `(\bunion\|select\|insert\|...\bfrom\|into\|table\|where\b)` con i-flag → falsea con "Please **update** the **form**". Todo el SQL ya es parametrizado. **Eliminar**. | H |
| `error-handler.ts` | Retorna `{code, message, details, trace_id}` — no RFC 7807 | M |

Orden actual: `rate-limit → sanitize → tracing → errorHandler → routes`. Correcto sería `tracing → rate-limit → sanitize → errorHandler → routes`.

## Domain models

- `canonical.ts` — Zod thorough (~138 líneas) **pero `status` es `z.string()` (line 120)** → acepta cualquier string. **H**
- `payment.ts` — interface TS plain, no Zod. `PaymentStatus | string` (line 5) defeats type-safety.
- `audit-event.ts` enum unused.
- `route-rule.ts / mapping-entry.ts` simple DB-mirror.
- **Sin value objects** — primitivos por todos lados (`Money`, `Currency`, `Alias` deberían existir).

## Persistence — SQL Queries Audit (25 queries identificadas)

| # | Query | File:Line | Params | Tx? | Index? |
|---|---|---|---|---|---|
| 1 | INSERT_PAYMENT | queries/index.ts:3-10 | $1-$15 | No | PK |
| 2 | FIND_PAYMENT_BY_ID | :12 | $1 | No | PK |
| 3 | UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS | :14-26 | $1, $2 | No | PK |
| 4 | UPDATE_PAYMENT_CANONICAL_PAYLOAD | :28-32 | $1-$3 | No | PK |
| 5 | UPDATE_PAYMENT_ROUTE | :34-38 | $1-$4 | No | PK |
| 6 | UPDATE_PAYMENT_TRANSLATED_PAYLOAD | :40-44 | $1, $2 | No | PK |
| 7 | UPDATE_RAIL_ACK | :46-52 | $1-$3 | No | PK |
| 8 | INSERT_AUDIT | :55-57 | $1-$7 | No | depends |
| 9 | FIND_AUDITS_BY_PAYMENT | :59-60 | $1 | No | idx needed |
| 10 | FIND_IDEMPOTENCY_BY_KEY | :63-64 | $1 | No | UNIQUE idx |
| 11 | INSERT_IDEMPOTENCY | :66-70 | $1-$6 | No | UNIQUE idx |
| 12 | UPDATE_IDEMPOTENCY_RESPONSE | :72-73 | $1-$3 | No | UNIQUE idx |
| 13 | FIND_ACTIVE_ROUTE_RULES | :76-77 | — | No | needs (priority, is_active) idx |
| 14-25 | (etc — see raw inline) | | | | |

**Hallazgo C**: **No hay transacciones multi-statement**. `pipeline.execute` hace ~7 writes secuenciales sin `BEGIN/COMMIT` — cualquier falla deja estado parcial.

## Observability (`src/observability/`)

- **`otel.ts`**: Si `OTEL_EXPORTER_OTLP_ENDPOINT` está unset, `traceExporter` = undefined → SDK silently no-op, sin warning. **L** Auto-instrumentations excluye fs/dns/net/express/koa/grpc. AMQP incluido pero **publisher envía JSON serializado sin inyectar trace headers manualmente** → trace break confirmado.
- **`logger.ts`**: Pino con mixin que emite OTel trace_id. Pero audit DB usa ULID. Logs y audit no correlacionan. Sin redact config → PII fugaría si request fuera logueado.
- **`metrics.ts`**: 5 instruments. **`recordIdempotencyHit` nunca se llama** — métrica existe pero nunca incrementa. **`recordPayment(finalStatus, ack.source_rail, ack.source_rail === 'PIX' ? 'SPEI' : 'PIX')`** (`consumer.ts:88`) — bug: BRE_B acks etiquetados como `destination_rail: 'PIX'` siempre.

## Config

- `env.ts` Zod strong, fails fast.
- **`constants.ts` `RAIL_OPERATING_HOURS`**:
  - PIX `7am-23:59 weekdays + Saturday` — **WRONG**, PIX es 24/7/365 (BACEN since 2020).
  - SPEI weekdays — correcto.
  - Bre-B `6am-22:00 weekdays` — **WRONG**, BanRep es 24/7.
- `RAIL_RATE_LIMITS` arbitrarios — sin fuente.
- `HTTP_RATE_LIMIT_MAX/WINDOW_MS` se lee directo de `process.env` en `server.ts:64-65` **bypasseando el schema Zod**.

## API routes

- `payments.ts` — POST/GET cubiertos arriba.
- `health.ts` — **devuelve `{status:'ok'}` hardcoded sin probar DB/MQ**. Kubernetes readiness siempre verde aun con Postgres caído. **H**
- `sse.ts` — clients en array global, no auth requerida, sin cap. PII leak vía `GET /events/payments`. **H**
- `ui-proxy.ts` — proxy a mocks vía rutas auth. **Crítico para producción**: cualquiera con token admin (que es trivial obtener) puede flippear los mocks a reject mode. **C**

## Dependency audit (`npm audit`)

**13 vulnerabilidades: 4 críticas, 7 high, 2 moderate**.
- `@fastify/jwt <= 9.1.0` via `fast-jwt` — CRITICAL
- `protobufjs` (transitive OTel gRPC) — arbitrary code exec
- `@opentelemetry/exporter-prometheus` GHSA-q7rr-3cgh-j5r3 — HIGH (proceso crash via HTTP malformado)
- `picomatch` — ReDoS + glob bypass

Unused deps: `@opentelemetry/exporter-metrics-otlp-http` (en package.json sin import), `jsonwebtoken` (sin uso — `@fastify/jwt` ya lleva `fast-jwt`).

## What was done well (core)

1. **Schemas Zod thorough** en `canonical.ts` con length constraints ISO 20022 (max 35, 140, 4×70 lines). `tsconfig` con `strict, noUnusedLocals/Parameters, noImplicitReturns`.
2. **`tryInsert` `ON CONFLICT DO NOTHING RETURNING`** es race-correct.
3. **Audit trail con ULID + JSONB detail** sólido.
4. **HMAC verify con `timingSafeEqual`** correcto.
5. **`RabbitMQReconnector` encapsulation** bien (con bugs de re-attach).
6. **Pino + ISO timestamps + OTel mixin** fundación fuerte.
7. **Circuit breaker quality es alta** — pena que no se use.
8. **SQL 100% parametrizado** — injection surface cerrada.
9. **OTel SDK aísla auto-instrumentations no esenciales**.
10. **Health/metrics excluded del rate limit** correcto.
11. **Validation suite `run-core-validation.ts` 26 checks** — rare-quality post-deploy verification.

---

# Parte III — Adapters (referencia: [AUDIT-RAW-adapters.md](AUDIT-RAW-adapters.md))

**Veredicto**: Los 3 adapters son near-identical (template compartido). Mock fidelity scores: **PIX 2.5/5, SPEI 1.5/5, Bre-B 1.0/5**.

## Críticos nuevos (en raw el detalle file-by-file)

- **(C) BREB sin `retry.ts`** — inlinea backoff propio (`client.ts:112-114`). `brebRetryCount` metric declarada pero **nunca incrementada**.
- **(C) BREB test broken** — `test/unit/breb-translation.test.ts:6` importa `brebToCanonical` que no se exporta. Test no corre.
- **(C) BREB cero contract test** — PIX/SPEI tienen `test/contract/<rail>-mock.test.ts`, BREB no tiene `test/contract/`.
- **(C) PIX EndToEndId timestamp UTC en `types.ts:184-185`** (`toISOString` slice) — Brasília es UTC-3. Pago a 23:30 BRT → fecha del día siguiente.
- **(C) PIX endpoint `/spi/v2/pagamentos` no existe en BCB**. Real BCB expone `/cob/{txid}`, `/cobv/`, `/pix/{e2eid}`. SPI real es XML/RSFN, no REST.
- **(C) SPEI endpoint `/spei/v3/transferencias` no existe**. STP real es SOAP en `:7024/speiws`.
- **(C) SPEI institución 3 dígitos vs 5 reales** (`types.ts:157-168`).
- **(C) STP no usa OAuth2** — usa firma RSA PKCS#1 v1.5 SHA-256 sobre canonical pipe-joined. **Nuestro mock implementa OAuth2** — paradigma completamente equivocado.
- **(C) SPEI mock comment claim "BanRep spec v1.0 (2023)" — no existe esa spec**. BanRep publicó documento técnico hasta feb-2026.
- **(C) BREB llave types incompletos**: faltan **CC, CE, Pasaporte**. `ALIAS` regex `[A-Za-z0-9]{4,20}` excluye `@` que BanRep mandata para alfanuméricas.
- **(C) SPEI mock async-settlement bug fully-wired**: con `settlementDelayMs > 0`, mock responde 202 con `EN_PROCESO` → adapter mapea a `status: 'ERROR'` → emite FAILED ack → mensaje abandonado. Mientras tanto el mock eventualmente settle a `LIQUIDADA` pero adapter ya se rindió. **End-to-end broken con el feature de async settlement activado**.

## Patrones cross-rail

| Pattern | PIX | SPEI | BREB |
|---|---|---|---|
| Prefix strip | `^PIX-` | `^SPEI-` | `'/'`-split + `^BREB-` |
| ID suffix length | 11 | 8 | 10 |
| ID timestamp | UTC slice | UTC slice | UTC slice |
| Retry backoff | 500×2^n | 500×2^n | 200×n (linear) |
| 4xx behavior | Retried | Retried | **Returned w/o retry** ✓ |
| Client secret | hard-coded | hard-coded | hard-coded |
| OAuth scope | `'spi.pagamentos'` (invented) | `'spei.transferencias'` (invented) | `'breb.pagos'` (invented) |
| `RAIL` constant | `'PIX'` | `'SPEI'` | **`'BRE_B'` (underscore!)** |
| `dataHora` field | `new Date().toISOString()` | same | **`canonical.created_at`** ✓ |
| Latency labeling | `'success'` always | same | **correct `success/rejected/error`** ✓ |

**BREB tiene 3 patrones MEJORES que PIX/SPEI** — replicar en los otros dos.

## Done well (adapters)

Detalle en [AUDIT-RAW-adapters.md §6](AUDIT-RAW-adapters.md):
1. **CLABE validator** `clabe-validator.ts` mod-10 weights [3,7,1] correcto contra Banxico spec. La pieza más fiel a spec real de todo el proyecto. Score 5/5.
2. **OAuth token cache con 60s margin** (`<rail>/client.ts:6-36`) — textbook.
3. **Mock idempotency keyed by canonical ID** — coincide con comportamiento real.
4. **Rejection code coverage**: PIX 9 códigos BACEN, SPEI 7 CECOBAN, BREB 6 propios. Mejor que mock binario.
5. **Admin control API** — `/admin/config`, reject-next, timeout-next, reset, stats — dashboard-friendly.
6. **BREB preserva `canonical.created_at`** — PIX/SPEI deberían copiar.
7. **BREB clasifica 4xx correctamente** — no quema retry attempts.
8. **Zod env validation per-adapter** con exit-1 — config hygiene fuerte.
9. **DLX scaffolding** — `x-dead-letter-exchange: 'mipit.dlx'` correcto en los 3.
10. **OAuth mock con 32-byte tokens entropy** strong.

---

# Parte IV — Infra + DB + Observability (auditoría inline)

## Servicios docker-compose — 11 servicios, port matrix

| Service | Image | Pinned | Healthcheck | Scrape OK? | Grafana? |
|---|---|---|---|---|---|
| postgres | `postgres:16-alpine` | minor | ✓ pg_isready | **❌ `postgres-exporter` declarado pero NO existe en compose** | No |
| rabbitmq | `rabbitmq:3.13-management-alpine` | minor | ✓ check_port | ✓ `:15692` plugin enabled | indirect |
| core | `ghcr.io/mipit-poc/mipit-core:latest` | **`:latest`** | ❌ none | ✓ `:8080/metrics` | ✓ 4 panels |
| adapter-pix | `:latest` | none | ❌ scrape `:9100` real `:9101` | dashboards no populan |
| adapter-spei | `:latest` | none | ❌ scrape `:9100` real `:9102` | dashboards no populan |
| adapter-breb | `:latest` | none | ✓ scrape `:9103` real `:9103` | parcial |
| ui | `:latest` | none | depende sin `condition` | No | No |
| nginx | `nginx:1.25-alpine` | minor | none | No | No |
| prometheus | `:v2.51.0` | patch | none | self | No |
| grafana | `:11.0.0` | patch | none | No | No |
| jaeger | `:1.56` | minor | none | No | datasource only |

**Crítico**:
- Todos los custom images con `:latest` → no reproducible.
- Scrape ports PIX/SPEI wrong → adapter metrics inaccessibles.
- `postgres-exporter` declarado en `prometheus.yml:45` pero **sin servicio en compose** → permanentemente down.

## DB Schema — `payments` table (33 columns)

Tabla completa en raw (inline arriba). Hallazgos:

- **H** Sin CHECK constraints en `status`, `origin_rail`, `destination_rail`, `currency`, `country` — todo TEXT libre.
- **H** **No hay columnas ISO 20022**: sin `end_to_end_id`, sin `uetr UUID UNIQUE`, sin `instructed_amount`, sin `settlement_amount`, sin `charge_bearer`. Canónico solo vive como `canonical_payload JSONB` sin enforcement.
- **H** `payments.amount > 0` no validado.
- **M** `currency TEXT DEFAULT 'USD'` para PoC LATAM es código que apesta.
- **M** `reference TEXT DEFAULT 'MIPIT-POC'` — defaults sentinel, no NULL.
- **M** `updated_at` sin trigger → nunca se actualiza.
- **L** Lifecycle denormalizado en 9 columnas timestamp vs event-sourced child table (que ya existe en `audit_events`).

## Migraciones — duplicación + drift

- `db/init/004_webhooks.sql` y `db/migrations/004_webhooks.sql` son **byte-identical duplicates**.
- `db/migrations/005_resilience.sql` está **solo en `migrations/`**, no en `init/`. Como no hay migration runner y `init/` es lo único montado, **`compensated_at, dead_letter_at` columns NO existen en VM nueva**. App que lee esas columnas verá `column does not exist`.
- `scripts/seed.sh:9-10` solo re-aplica route_rules y mapping_table.

## RabbitMQ topology

| Queue | Durable | DLX | Quorum? | TTL? |
|---|---|---|---|---|
| payments.route.pix | ✓ | → dlq.pix | ❌ classic | ❌ |
| payments.route.spei | ✓ | → dlq.spei | ❌ | ❌ |
| payments.route.breb | ✓ | → dlq.breb | ❌ | ❌ |
| **payments.ack** | ✓ | **❌ NO DLX** | ❌ | ❌ |
| dlq.* | ✓ | terminal | ❌ | ❌ |

**H**: payments.ack sin DLX — si consumer crashea entre `basic.deliver` y `ack`, mensajes se redeliveran indefinidamente sin DLQ.

## Seeds

- **`route_rules` 8 reglas — buen diseño**, prioridad alias>country>phone>fallback. Una crítica: `fallback_unavailable` overloads `destination_rail` column como flag de status.
- **`mapping_table` 44 rows (PIX 22, SPEI 22)** — **0 rows Bre-B**. Adapter BREB traduce hard-coded (anula table-driven design).
- PIX mappings: nombres en portugués matchean BACEN vocabulary; validaciones `iso_4217`, `18_digits`, `len_0_35`, `len_0_140` correctas contra spec.
- SPEI mappings: nombres en español matchean Banxico CDA; `claveRastreo, institucionContraparte, cuentaBeneficiario, conceptoPago, referenciaNumerica` todos presentes.

## Nginx

- ✓ TLS 1.3-only, HTTP→HTTPS redirect.
- ❌ **Sin security headers**: HSTS, CSP, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, X-Frame-Options.
- ❌ Sin rate limit (`limit_req`).
- ❌ Sin `client_max_body_size`.
- ❌ **Sin SSE/streaming buffering control** → `proxy_buffering on` default mata SSE en 60s.
- ❌ Sin `proxy_read_timeout` para real-time.

## Env files — secrets committed

**Todos los `.env.example` tienen los mismos valores que los `.env`** (gitignored localmente pero la convención los expone):
- `JWT_SECRET=mipit-poc-jwt-secret-change-in-production` (`env/core.env:5`)
- `mipit_secret` reutilizado en Postgres, RabbitMQ, DATABASE_URL, RABBITMQ_URL, los 3 adapters
- `GF_SECURITY_ADMIN_PASSWORD=mipit2026` directo en `docker-compose.yml:182` (no en env)

## Prometheus scrape — confirmado broken

| Job | Target | Real port | Estado |
|---|---|---|---|
| mipit-core | `core:8080` | 8080 | ✓ |
| adapter-pix | `adapter-pix:9100` | **9101** | ❌ Down |
| adapter-spei | `adapter-spei:9100` | **9102** | ❌ Down |
| adapter-breb | `adapter-breb:9103` | 9103 | ✓ |
| rabbitmq | `rabbitmq:15692` | 15692 plugin | ✓ |
| postgres-exporter | `postgres-exporter:9187` | **service doesn't exist** | ❌ permanent down |

## Grafana dashboards — 3 dashboards, 8 paneles rotos de 19 totales

**`mipit-overview.json`**: ✓ 6/6 paneles funcionan (usan métricas reales del core).

**`mipit-latency.json`**: 3/5 paneles rotos. Panels 3,4 querían `mipit_adapter_latency_ms_bucket{rail="X"}` — métrica real es `mipit_adapter_pix_payment_latency_ms_bucket` con label `status` (no `rail`).

**`mipit-rails.json`**: **8/8 paneles rotos**. Todos usan `mipit_adapter_requests_total`, `mipit_adapter_errors_total`, `mipit_adapter_retries_total` con label `rail` — esos nombres no existen en código.

**Fix**: unificar metrics adapters a una sola shape:
```ts
new Counter({ name: 'mipit_adapter_requests_total', labelNames: ['rail', 'status'] })
new Histogram({ name: 'mipit_adapter_latency_ms', labelNames: ['rail'] })
new Counter({ name: 'mipit_adapter_retries_total', labelNames: ['rail'] })
new Counter({ name: 'mipit_adapter_errors_total', labelNames: ['rail', 'error'] })
```

## Alerts

3 alerts en `alerting/rules.yaml`: HighErrorRate, HighLatency, RabbitMQQueueBacklog.

- ✓ Las 3 referencian métricas reales.
- ❌ **`rule_files:` no está en `prometheus.yml`** → alerts no cargan.
- ❌ AlertManager no desplegado.
- ❌ Sin severity tiers, sin runbook_url, sin owner labels.
- ❌ Threshold-based no SLO-based (no burn-rate).

## OTel Collector

**Config file existe (`otel-collector/otel-collector.yaml`) pero NO hay servicio en compose**. Apps apuntan directo a `jaeger:4318` bypaseando collector.

Consecuencias:
- Sin sampling (cada span va a Jaeger; saturate Jaeger a 1k TPS load).
- Sin metrics derived-from-spans (RED metrics ausentes).
- "OTel-based observability" claim half-true.

## Cross-cutting verification de claims

| Claim | Status |
|---|---|
| 3 rails work | **2.5/3** (Bre-B sin mapping_table, sin tests E2E, sin docs) |
| ISO 20022 canonical | **JSONB blob sin estructura**; no columnas dedicadas |
| Real-time | Core latency observable; rail-side no scrapeado |
| Observable end-to-end | **Sin log layer**; adapter metrics inaccesibles; OTel collector no desplegado |
| Resilient | DLX en route queues ✓; **payments.ack sin DLX**; quorum ❌; healthchecks parciales; compensation columns no aplicadas |
| Secure | TLS 1.3 ✓; sin security headers; secrets en env.example; admin paths sin auth |

## Done well (infra/obs)

1. PIX y SPEI mapping seeds excelentes — 44 rows traceables a BACEN/Banxico spec.
2. Route rules priority order sensible.
3. DLX wiring correcto en 3 rieles.
4. Compose dependency con healthchecks condition en data layer.
5. Core metric definitions clean (5 instruments, bounded cardinality, stage buckets).
6. TLSv1.3-only.
7. `up.sh` idempotente con health-check.sh follow-up.
8. `idempotency_keys` table design correct para claim-first pattern.
9. Grafana overview dashboard production-grade (6 paneles funcionando).
10. Observability README documenta el contrato intended.
11. `webhook_subscriptions` con `ON DELETE CASCADE` y partial index `WHERE fired_at IS NULL`.
12. `gen_random_uuid()::TEXT` + `pgcrypto` extension — primitivas correctas.
13. Override pattern para dev (`docker-compose.override.yml`).
14. BREB env más completo que PIX/SPEI (BREB_TIMEOUT_MS, BREB_MAX_RETRIES, INSTANCE_ID).

---

# Parte V — UI + Testkit + Docs + PDFs (referencia: [AUDIT-RAW-ui-docs.md](AUDIT-RAW-ui-docs.md))

## UI

**Estado general**: Bien construida (Next 15, React 19, TS strict). Problemas concretos:

- **C** `<Toaster />` nunca montado → todas las toasts perdidas
- **H** Origin/dest rail en form NO se transmiten al backend (`simulate/page.tsx:127-144`). Picker decorativo.
- **H** SSE no recibe JWT (`EventSource` sin Authorization header)
- **H** `globals.css` define solo `--color-card`; el resto (`foreground/background/border/primary`) referenciados pero **nunca declarados**.
- **H** `payments/[id]/page.tsx` no muestra `trace_id` (ADR-008 lo promete, SRS lo menciona). PaymentDetail type sin trace_id.
- **H** `__tests__/lib/constants.test.ts:11` asserts `Object.keys(STATUS_CONFIG).length === 11` — constants.ts tiene 14. **Test debe estar rojo**.
- **H** `__tests__/hooks/use-payment.test.ts:11-20` mocks payment con `origin`/`destination` cuando real type usa `origin_rail`/`destination_rail` — test contra type obsoleto.
- **M** Stats-cards/payment-table client-side sobre `listPayments({limit:200})` — escala mal.
- **M** Sin error boundary, sin polling visibility-aware.
- Dead code: 4 component stubs no usados (`payment-form.tsx`, `pix-form.tsx`, `spei-form.tsx`, `payment-card.tsx`, parcialmente `rail-selector.tsx`).

## Testkit

**Hallazgo crítico**: La suite `tools/run-validation-suite.ts` cuenta **3 escenarios "históricos" con `durationMs: 0`** como pasados (`historical-load`, `historical-routing`, `historical-verifications`). El comentario del código lo dice: `"Resultado histórico documentado, no re-ejecutado en esta corrida."` El headline "11/11 green" es defensible solo con asterisco.

**Tests con assertions reales vs placebos**:

| File | Real | Placebos | Verdict |
|---|---|---|---|
| `tests/contract/canonical-schema.test.ts` | 2 | 2× `expect(true).toBe(true)` | placebo-heavy |
| `tests/contract/openapi-validation.test.ts` | 0 | **6×** | **100% placebo** |
| `tests/contract/rabbitmq-messages.test.ts` | 0 | **5×** | **100% placebo** |
| `tests/e2e/pix-to-spei.test.ts` | full E2E | none | **drift: espera 202, real es 201** |
| `tests/e2e/spei-to-pix.test.ts` | full E2E | none | **drift: espera 202** |
| `tests/integration/core-api.test.ts` | real POST+GET | none | **drift: espera 202** |
| `tests/integration/routing.test.ts` | dense, multi-rail | none | **REAL** (mejor archivo del repo, ya adaptado a 201) |
| `tests/integration/translation.test.ts` | partial | 3× | shape obsoleta `detail.canonical.debtor.rail` |

**Coverage matrix de pares de rieles**:

| From\To | PIX | SPEI | Bre-B |
|---|---|---|---|
| PIX | n/a | ✓ | ✓ (`routing.test.ts:94-136`) |
| SPEI | ✓ | n/a | ✓ (`routing.test.ts:138-152`) |
| Bre-B | ✓ (`routing.test.ts:154-167`) | ❌ | n/a |

Resilience scenarios: **5/13 cubiertos**. Gaps: broker outage, DB primary down, DLQ requeue specific, out-of-order ACK, compensation E2E.

**Datasets**: CLABE `012345678901234567` en `datasets/pix/pix-valid-01.json:9` tiene check digit **inválido** (calculado: 8, observado: 7). `fix_testkit.py:17-30` lo corrige pero **no se ha aplicado al working copy de Windows** — solo se ejecutó en la VM.

**No hay `datasets/breb/`**, no hay `generators/generate-breb.ts`. Bre-B sin fixtures.

## ADRs vs implementación — drift uno por uno

| ADR | Drift | Sev |
|---|---|---|
| ADR-001 (TS/Node/Fastify) | Diseno PDF §3.1.2 menciona Spring Boot — drift PDF vs ADR | M |
| ADR-002 (pacs.008 JSON) | **Dos canonical specs en el repo**: nested camelCase (translation-layer.md, código) vs flat snake_case (mappings/CSVs, canonical-fields.md, algunos tests). | **H** |
| ADR-003 (RabbitMQ DLQ) | ADR sin Bre-B; queue names `q.adapter.pix` vs real `payments.route.pix`. **2 esquemas naming en el repo**. | M |
| ADR-004 (Idempotency-Key) | Sin drift evidente | OK |
| ADR-005 (JWT/HTTPS) | OpenAPI **no declara `/auth/token`** como endpoint pese a que UI lo requiere. smoke-test.sh sin Authorization. | H |
| ADR-006 (Postgres jsonb) | Sin drift evidente | OK |
| ADR-007 (Hybrid modular) | OK | OK |
| ADR-008 (OTel+Prom+Grafana) | Promete W3C TraceContext propagation y trace_id en messages; UI nunca muestra trace_id, sin link a Jaeger. | H |

## OpenAPI spec drift — 12 endpoints reales sin documentar

`mipit-docs/openapi/openapi.yaml` describe mundo de 2 rieles. Reality:

| Spec dice | Realidad |
|---|---|
| `POST /payments` retorna 202 | Retorna **201/200** |
| `destination` enum `[PIX, SPEI]` | 7 valores |
| PaymentStatus 11 entries | **14** (faltan COMPENSATING, COMPENSATED, DEAD_LETTER) |
| Idempotency-Key **required** | optional |
| **NO declarados pero usados por UI**: `/translate`, `/translate/preview`, `/translate/rails`, `/analytics/{summary,latency,circuit-breakers,rate-limits,reconciliation}`, `/services/{rail}/health`, `/events/payments[/{id}]` SSE, `/compensate/{paymentId}`, `/compensate/batch`, `/mocks/{rail}/admin/*`, `/mocks/{rail}/health`, `/auth/token` | |
| `Party.alias` "Clave PIX, CLABE…" | impl usa prefijos `PIX-`, `SPEI-`, `BREB-` (no documentado) |

**Blocker**: OpenAPI es starter doc; realidad es plataforma multi-rail con 20+ rutas adicionales.

## Mapping CSVs vs translators

Los 4 CSVs (`pix-to-canonical.csv`, `canonical-to-pix.csv`, `spei-to-canonical.csv`, `canonical-to-spei.csv`) describen **flat snake_case** (`canonical.msg_id`, `canonical.amount`). Realidad: **nested camelCase** (`grpHdr.msgId`, `amount.value`).

**Cero CSVs para BRE_B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW** — 5 rieles sin documentación de mapping.

## Route rules YAML vs DB seed

`mipit-docs/route-rules/rules.yaml` define routing por `alias_type` enum (`CLABE/CPF/PHONE/EMAIL/EVP/PHONE_MX`). Implementación real **rutea por prefijo** (`PIX-`, `SPEI-`, `BREB-`). YAML es diseño aspiracional, no realidad. Sin reglas Bre-B.

## Design docs

- `architecture-overview.md` diagrama solo PIX/SPEI — Bre-B missing
- `translation-layer.md` lista 6 rieles, omite Bre-B
- `contracts/payment-status-machine.md` 11 states, código 14
- `contracts/error-codes.md` con `PIX_INSUFFICIENT_FUNDS` genéricos — mocks usan códigos reales BACEN/CECOBAN/BREB
- `contracts/rabbitmq-messages.md` queue names viejos

## Demo runbook

- `local-demo.md` paso 7 idempotency dice "El estado debe mostrar `DUPLICATE`" — la realidad es replay cacheado, el pago no cambia a DUPLICATE
- `vm-demo.md` usa IPs placeholder `192.168.1.10/.11/.12` — reales son `10.43.101.28/.29`
- `checklist-pre-demo.md` queue names obsoletos

## CONTEXTO-MIPIT.md drift

**Línea 13**: "Semanas 5, 6 y 7 completadas. Próxima: Semana 8."  ← **stale, evidencia prueba semana 13-14 entregada**.

Otros drifts:
- Línea 27 y 113: dice "mipit-ui: React, TypeScript, Vite" — realidad es **Next.js 15**
- Línea 56: branches `Nicolas_05..07, carlos_05` — nomenclatura outdated
- Línea 108: "RabbitMQ 3.12+" — real es 3.13

## PDFs originales — promesa vs entrega

### Propuesta — `Plantilla Propuesta Proyecto Middleware.pdf`
- **Promesa**: 4 rieles **PIX, SPEI, FedNow, Bre-B** evaluables
- **Entrega**: 3 rieles full Option-B (PIX, SPEI, BRE_B) + 4 translators Option-A (SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW)
- **Drift**: FedNow se prometió como evaluable; entregado como translator-only. **Bre-B sustituyó a FedNow** en el slot de "rail con mock". Net positivo en breadth pero subtle re-framing.

### SRS — `SRS_MIPIT.pdf`
20 requirements funcionales RF01-RF20. Implementados:

| RF | Implementado? | Evidencia |
|---|---|---|
| RF01-RF05 | ✓ | tests/integration |
| RF06 MappingTable | parcial | DB OK, YAML/CSV drift |
| RF07 RouteRule | ✓ con drift de shape | prefix-based vs alias_type docs |
| RF08-RF14 | ✓ | |
| RF15 Grafana dashboards | ✓ (con bugs scrape) | |
| RF16-RF18 | ✓ | FlowTimeline, MessageInspector, RailAckPanel |
| **RF19 export CSV/JSON** | **❌ NO IMPLEMENTADO** | sin feature de export en UI |
| RF20 restart entre sesiones | ✓ | docker-compose + admin/reset |

NFR: 99.9% delivery (claim validado), 15s max response (p99 = 250ms), TLS 1.3 ✓, API Key vs JWT (semantic drift), mTLS futuro.

### Diseno — `Diseno_MIPIT.pdf`
- Endpoints `/transactions` vs impl `/payments` — documentado en plan
- Schema: `sourceAccount/destinationAccount/destinationRail/metadata` vs `debtor/creditor/purpose/reference`
- Status enum `RECEIVED, PROCESSING, SUCCESS, FAILED` (4) vs **14** statuses reales
- §3.1.2 Spring Boot drift vs ADR-001

### SPMP — `SPMP.pdf`
- 16 weeks vs CONTEXTO-MIPIT 17 (off-by-one, likely week 0 inclusion)
- **H3 over-delivered**: prometía 2-rail E2E, entregó 3-rail
- **H4 strict reading not met**: prometía 4-rail evaluable, entregó 3-Option-B
- H5 academic article: out of scope audit

## `fix_testkit.py` en root

Script Python one-shot con paths Linux (`/home/estudiante/tesis/...`). Hace 5 fixes (CLABE check digits, auth wrapper inject, 202→201, broken helper import, ui.env IPs). **Probablemente ejecutado en VM, no en working copy Windows** → tests locales contienen bugs ya corregidos en VM.

Recomendación: mover a `scripts/migrations/` o portar a Windows + commit.

## Done well (UI/testkit/docs)

1. `tests/integration/routing.test.ts` — mejor file del testkit, 329 líneas multi-rail concurrent.
2. `e2e-verifications.mjs` + `E2E-VERIFICATION-RESULTS.md` — 76 honest assertions documentadas per-código.
3. `tools/run-validation-suite.ts` — Windows-compatible, env-loading, scenario abstraction, JSON+MD report.
4. UI Simulator page — control panel production-quality.
5. UI Analytics page — defensive parsing.
6. `lib/api.ts` token cache con 60s pre-expiry margin.
7. `use-sse.ts` con auto-reconnect.
8. ADR template adherence excelente (Status/Date/Context/Decision/Alternatives/Reasons/Consequences).
9. `design/translation-layer.md` — doc más preciso del repo.
10. `design/adding-a-new-rail.md` — extensibility doc con Bizum example.

---

# Parte VI — Inconsistencias específicas que mencionaste (re-verificadas en profundidad)

| Tu hipótesis | Verdict profundo | Donde |
|---|---|---|
| "Bre-B usa llaves pero formato no correcto" | ✅ **Confirmado con detalle**: faltan CC, CE, Pasaporte (tipos llave); alfanumérica regex rechaza `@` prefix; código entidad 8-dig vs 4-dig Superfinanciera real; `BREB-` prefix es invención MiPIT que leakea entre 3 capas; UTC en `idTransaccion` vs COT esperado. | Adapter [§4](AUDIT-RAW-adapters.md), translation [§4.3](AUDIT-RAW-translation.md) |
| "PIX usa timestamp envío pero no lo usamos" | ✅ **Confirmado**: `horario` descartado en `pix-to-canonical.ts:117-148`; normalizer pisa con `new Date().toISOString()`. Además: EndToEndId tiene un timestamp embebido que se genera con UTC vs BRT esperado (fecha errada cerca de medianoche). | Translation §4.1, Adapters §2.6 |
| "SPEI formato no concuerda con spec" | ✅ **Confirmado**: institución 3-dig vs 5-dig Banxico real; **falta `firma` RSA** (STP no usa OAuth); `claveRastreo` acepta `-_` cuando CECOBAN solo permite alfanumérico; mapping table `referenciaNumerica` validation `len_0_140` vs Banxico 7 dígitos; **endpoint `/spei/v3/transferencias` inventado** (STP real es SOAP `:7024/speiws`); RFC sin checksum; CURP sin checksum. | Adapters §3, Translation §4.2 |
| "ISO 20022 no concuerda con ISO 20022 real" | ✅ **Confirmado estructuralmente**: faltan campos mandatorios `UETR, ChrgBr, IntrBkSttlmDt, InitgPty, SttlmInf.ClrSys`; **3 artefactos internos discrepan entre sí** (canonical-fields.md flat snake_case vs translation-layer.md nested camelCase vs canonical-to-iso20022-mx.ts emitter); pacs.002 ACK incompatible con `OrgnlMsgId/OrgnlEndToEndId/OrgnlUETR/TxSts` ISO codes; salida etiquetada `pacs.008.001.08` cuando spec actual es `.001.10`; canonical-to-iso20022-mx.ts NO emite XML (devuelve JS object). | Translation §1-3, UI/Docs §4 (ADR-002), §6 (mapping CSVs) |

---

# Parte VII — ¿Cumple la tesis? (claim por claim — profundo)

| Claim | Veredicto | Caveats |
|---|---|---|
| **"Demostrar interoperabilidad técnica entre 3 pasarelas instantáneas"** | ⚠️ **Parcial defendible** | PIX↔SPEI con caveats reales; Bre-B desplegado pero **sin tests E2E, sin mapping_table, llaves incompletas, formato wire inventado** |
| **"Modelo canónico basado en ISO 20022 pacs.008"** | ❌ **Misleading sin re-naming** | Es "pacs.008-derived" — faltan UETR, ChrgBr, IntrBkSttlmDt mandatorios v10; 3 documentos internos discrepan; output etiquetado v08 cuando spec actual es v10 |
| **"Pagos en tiempo real"** | ⚠️ **Untested SLO** | E2E acepta hasta 30s; mocks son sub-segundo así que demo se ve rápida; SLO `<10s` no enforced |
| **"Cross-border / cross-currency"** | ❌ **Structurally broken** | FX se calcula pero ignorado por adapters PIX/SPEI/Bre-B (solo FedNow lo usa); BRL→MXN llega como 100 BRL no MXN |
| **"Observable end-to-end"** | ⚠️ **Half-true** | Core observable; **adapter scrapes rotos en Prom**, OTel collector no desplegado, AlertManager ausente, sin log layer, UI no muestra trace_id, traza se corta entre publisher y adapter (sin W3C TraceContext en AMQP headers) |
| **"Mensajería async con resiliencia"** | ⚠️ **Parcial** | RabbitMQ DLX OK; **publisher sin confirms**; **reconnect no re-attach consumers**; rate limiter `acquire()` nunca llamado; circuit breaker `execute()` nunca llamado; compensation logged-only sin pacs.004 real |
| **"Mock-fidelity para swap-base-URL"** | ❌ **No** | PIX endpoint inventado `/spi/v2/pagamentos`; SPEI usa OAuth2 cuando STP usa RSA-signed SOAP; Bre-B inventa todo; los 3 con códigos institución incorrectos |

---

# Parte VIII — Plan de remediación priorizado

## Bloque 1 — Pre-sustentación (1 semana)

Estos cierran las brechas que un panel técnico cazaría de inmediato:

1. **Renombrar canónico** a "MiPIT Internal Canonical (pacs.008-derived)" en OpenAPI, dashboards, UI, README. ADR-002 ya admite la limitación — propagar coherentemente.
2. **Agregar `UETR` (UUIDv4 con `crypto.randomUUID()`) y `ChrgBr` al canónico**, persistirlos en `payments`, reusarlos en toda la cadena (un único UETR per pago).
3. **Fix PIX EndToEndId**: implementar `generatePixE2EId(ispb, brtTimestamp)` con formato exacto BCB (`E + ISPB(8) + YYYYMMDDHHMM(BRT) + 11 alnum`). Marcar `MIPIT_FAKE_ISPB` como "simulado" en código y tesis.
4. **Fix FX**: los 3 outbound translators (`canonical-to-pix`, `canonical-to-spei`, `canonical-to-breb`) deben leer `canonical.fx.local_amount/target_currency` si existe.
5. **Fix SPEI institutionCode**: catálogo 5-dígitos Banxico (40072, 40012, 90646...). Generar `claveRastreo` que cumpla `^[A-Za-z0-9]{1,30}$` (sin guion).
6. **Documentar Bre-B** como "implementación de referencia, formato wire inventado porque BanRep no publicó spec". Agregar al menos 1 test E2E y filas en `mapping_table`. Agregar tipos llave **CC, CE, Pasaporte**. Fix regex alfanumérica para aceptar `@` prefix.
7. **Fix observability scrapes**: cambiar `prometheus.yml` a `:9101/:9102/:9103`. Quitar `postgres-exporter` o agregarlo a compose. Cargar `rule_files`.
8. **Mostrar `traceId` en UI** de detalle pago con link a Jaeger.
9. **Montar `<Toaster />`** en `layout.tsx`. Sin esto el demo se ve roto.
10. **Re-aplicar `fix_testkit.py`** en working copy (CLABE check digits, 202→201, auth wrapper).
11. **Actualizar `CONTEXTO-MIPIT.md`**: dice semana 8 pendiente cuando estás en semana 13-14.

## Bloque 2 — Hardening (2 semanas opcionales)

12. Outbox transaccional para publish a RabbitMQ (resuelve C3 del primer pase).
13. `confirmChannel` + `waitForConfirms` en publishers.
14. Reconnect handler que re-registre consumers (C5 del primer pase).
15. CHECK constraints en DDL para `status`, `origin_rail`, `destination_rail`, `amount > 0`, `currency IN (...)`.
16. Validación checksum **CPF/CNPJ/CURP/RFC** en mocks (algoritmos públicos, ~50 líneas c/u).
17. Pino `redact` para PII (debtor/creditor name, taxId, alias).
18. CORS hard-coded; JWT con `algorithms: ['HS256']` y `iss/aud`.
19. **Borrar middleware regex anti-SQL** — las queries ya son parametrizadas y bloquea remittance legítimos.
20. **Eliminar componente "service-health soporta 7 rails"** — la tesis es 3.
21. Tests E2E para los 6 pares de rieles (PIX↔SPEI, PIX↔Bre-B, SPEI↔Bre-B).
22. SLO de latencia en E2E (`<10s` per rail) que falla el test si regresiona.
23. AlertManager + carga de `rule_files` en `prometheus.yml`.
24. Desplegar OTel collector (o quitar el config file y documentar el bypass).
25. Inyectar W3C TraceContext (`traceparent` header) en AMQP message properties.
26. Aplicar `db/migrations/005_resilience.sql` o copiarlo a `db/init/`.
27. nginx security headers + SSE-friendly location (`proxy_buffering off; proxy_cache off`).
28. RabbitMQ quorum queues + `x-message-ttl` + DLX en `payments.ack`.
29. Eliminar `rate-limiter.acquire()` o cablearlo (currently dead).
30. Eliminar circuit-breaker `execute()` o cablearlo (currently dead).

## Bloque 3 — Honestidad académica (siempre)

Agregar a la tesis una **sección "Limitaciones del PoC" explícita** que enumere:

- Canónico es subset pragmático de pacs.008, sin UETR/ChrgBr/IntrBkSttlmDt/InitgPty/SttlmInf.ClrSys hasta implementación futura.
- Mocks **no son byte-fidelity** a APIs reales: PIX usa endpoint inventado (real BCB es `/cob/{txid}` PSP-side + RSFN XML internal); SPEI no implementa firma RSA (real STP es SOAP signed); Bre-B no tiene spec pública wire-format.
- Sin certificados ICP-Brasil / HSM / mTLS — fuera de scope académico.
- Sin verificación checksums CPF/CNPJ/RFC/CURP — se podría agregar pero no aporta al claim de interop.
- FX estática con tabla in-memory (USD pivot, sin multi-leg) — no consume API real en tiempo real.
- Compensation logged-only (no emite pacs.004 real).
- Reconciliation reporting-only (no consume camt.054 / camt.053).
- Rate limiter y circuit breaker son scaffolding observable sin enforcement.

Hacer esto explícito convierte una "inconsistencia oculta" en una "limitación documentada" — que es exactamente lo que un panel académico valora.

---

# Apéndices

## A. Métricas agregadas

**Total findings nuevos** (más allá de la primera pasada en `AUDITORIA-MIPIT-2026-05-16.md`):

| Severidad | Count nuevo aprox |
|---|---|
| Critical | ~25 |
| High | ~50 |
| Medium | ~80 |
| Low | ~40 |

## B. Lista de archivos generados por esta auditoría

- `AUDITORIA-MIPIT-2026-05-16.md` — Primera pasada (resumen ejecutivo + plan)
- **`AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md`** — Este archivo (índice + síntesis profunda)
- `AUDIT-RAW-translation.md` — Translation layer forensic
- `AUDIT-RAW-adapters.md` — Adapters forensic (PIX/SPEI/Bre-B línea por línea)
- `AUDIT-RAW-ui-docs.md` — UI/testkit/docs/PDFs forensic

## C. Sources cited

- ISO 20022 pacs.008.001.10 message definition — https://www.iso20022.org
- BCB PIX API v2.9.0 OpenAPI — https://raw.githubusercontent.com/bacen/pix-api/master/openapi.yaml
- BCB pix-api rendered — https://bacen.github.io/pix-api/index.html
- BCB Manual de Padrões para Iniciação do Pix — https://www.bcb.gov.br/content/estabilidadefinanceira/pix/Regulamento_Pix/II_ManualdePadroesparaIniciacaodoPix.pdf
- BCB API DICT — https://www.bcb.gov.br/content/estabilidadefinanceira/pix/API-DICT-MED-2.0.html
- BCB Resolução nº 1/2020 (SPI operating model 24/7)
- Banxico Circular 14/2017 — https://www.banxico.org.mx/marco-normativo/normativa-emitida-por-el-banco-de-mexico/circular-14-2017/
- Banxico Manual de Operación SPEI v5.4
- Banxico Catálogo de Participantes SPEI — https://www.banxico.org.mx/servicios/participantes-spei-banco-me.html
- STP APIs + WADL — https://stp.mx/en/apis/, https://demo.stpmex.com:7024/speiws/rest/application.wadl
- cuenca-mx/stpmex-python — https://github.com/cuenca-mx/stpmex-python
- Banco de la República Bre-B — https://www.banrep.gov.co/es/bre-b
- BanRep Bre-B technical doc feb-2026 — https://d1b4gd4m8561gs.cloudfront.net/sites/default/files/publicaciones/archivos/documento-tecnico-bre-b-febrero-2026.pdf
- Bancolombia Bre-B llaves guide — https://blog.bancolombia.com/educacion-financiera/llaves-sistema-de-pagos-inmediatos/
- Decreto 1297/2022 (Colombia pagos inmediatos interoperables)
- IotaFinance MT103 — https://www.iotafinance.com/en/SWIFT-ISO15022-Message-type-MT103.html
- Paiementor MT103 — https://www.paiementor.com/swift-mt103-format-specifications/
- BNZ MT103 Standards 2021 — https://www.bnz.co.nz/assets/bnz/business-banking/help-and-support/SWIFT-MT103.pdf
- pacs008.com — https://pacs008.com/pacs-explained/
- BankingCircle Pacs.008 — https://docs.bankingcircleconnect.com/docs/fi-to-fi-credit-transfers-pacs008
- Payments Canada RTR pacs.008 — https://www.payments.ca/sites/default/files/RTR_FItoFI_CustomerCreditTransfer_pacs.008.pdf
- Clearstream CBPR+ pacs.008 — https://www.clearstream.com/resource/blob/4151636/748b8c7bc59fe132742e3a15955d175d/pacs-008-2-data.pdf
- JPMorgan ISO 20022 mapping — https://www.jpmorgan.com/content/dam/jpmorgan/documents/payments/iso20022-mapping-guide.pdf
- SWIFT ISO 20022 Market Practice — https://www.swift.com/swift-resource/252216/download
- Federal Reserve FedNow ISO 20022 spec v2024.1
- RFC 7807 Problem Details for HTTP APIs
- IETF draft Idempotency-Key HTTP Header (draft-ietf-httpapi-idempotency-key)
- OWASP Authentication Cheat Sheet (JWT aud/iss/alg pinning)
- AWS Architecture Blog Exponential Backoff and Jitter
- RabbitMQ Quorum Queues / DLX / Alternate Exchanges
- Prometheus / Grafana / OpenTelemetry Collector official docs
- Stripe webhooks signature convention
