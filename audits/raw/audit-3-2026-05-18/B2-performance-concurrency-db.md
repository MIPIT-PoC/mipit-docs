# Auditoría 3 — B2: Performance, Concurrency y DB Health

**Fecha:** 2026-05-18
**Scope:** mipit-core, mipit-adapter-{pix,spei,breb}, mipit-infra/db, mipit-infra/rabbitmq
**Out of scope:** spec compliance (cubierto A1), seguridad (A3/A4), inconsistencias (A5), branding/UI (A6).
**Branch:** `Auditoria-Claude` (Wave 1-6 cerradas)

---

## Resumen Ejecutivo

El PoC funciona pero la maquinaria interna está dimensionada para **decenas** de TPS, no centenas. El cuello inmediato es el **AckConsumer sin prefetch** (default = infinito): RabbitMQ vuelca toda la cola al proceso Node-single-thread que hace 3 escrituras DB sincrónicas por mensaje, garantizando back-pressure invisible y latencias multi-segundo bajo carga. Hay 4 races confirmadas (UPDATE sin CAS, webhook re-entry, mapping cache thundering-herd, CircuitBreaker compartido no atomic), 5 índices faltantes que penalizan `findRecent` y `findByPaymentId`, ningún índice GIN sobre los 4 columns JSONB que se consultan por path, y una fuga lenta de SSE clients en escenarios de error pre-`reply.send`. Estimación TPS sostenible **~25-45 PIX/s** sobre el setup actual (1 core, 1 PG pool de 50, RabbitMQ quorum queue), limitado por el ACK consumer single-threaded antes que por la rail. Los 3 bottlenecks principales: (1) **`AckConsumer` sin prefetch + sin paralelismo**, (2) **`audit_events` crece sin bound + sin partición**, (3) **`payments.UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS` sin guard CAS** que corrompe estado bajo retry de ACK.

---

## Tabla maestra de hallazgos

| ID      | Sev | Área         | File:Line | Title |
|---------|-----|--------------|-----------|-------|
| B2-001  | 🔴  | RMQ          | `mipit-core/src/messaging/consumer.ts:55`, `dlq-handler.ts:43` | `AckConsumer` y `DlqHandler` no llaman `channel.prefetch()` — fan-out ilimitado |
| B2-002  | 🔴  | DB / Concur. | `mipit-core/src/persistence/queries/index.ts:23-34` | `UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS` sin guard `AND status = oldStatus` |
| B2-003  | 🔴  | DB / Index   | `mipit-infra/db/init/001_schema.sql:44-48`, `mipit-core/src/persistence/repositories/payment.repository.ts:283-299` | `findRecent` filtra por `status`+`origin_rail`/`destination_rail` + ORDER BY `created_at` sin índice composite |
| B2-004  | 🔴  | DB           | `mipit-infra/db/init/001_schema.sql:51-63` | `audit_events` no tiene cap, no se partitionea, no tiene cleanup job — crece infinitamente |
| B2-005  | 🟠  | RMQ          | `mipit-adapter-{pix,spei,breb}/src/messaging/publisher.ts:9-12` | Adapters publican ACK **sin confirms** (`createChannel`, no `createConfirmChannel`) → pérdida silenciosa |
| B2-006  | 🟠  | Concurrency  | `mipit-core/src/translation/mapping-loader.ts:22-46`, `mipit-core/src/routing/rule-loader.ts:17-27` | TTL expira → 2+ requests cargan en paralelo desde DB (thundering herd) |
| B2-007  | 🟠  | Concurrency  | `mipit-core/src/messaging/consumer.ts:160-166`, `mipit-core/src/webhooks/webhook.repository.ts:51-58` | Re-entrega ACK + `findPending` sin filtro `fired_at IS NULL` → webhook duplicado |
| B2-008  | 🟠  | Concurrency  | `mipit-core/src/compensation/compensation-service.ts:40-122` | Doble `/compensate/:id` simultáneo emite 2 pacs.004 + double-status-flip |
| B2-009  | 🟠  | DB / Index   | `mipit-infra/db/init/001_schema.sql:51-63`, `mipit-core/src/persistence/queries/index.ts:80` | `audit_events` lookup `WHERE payment_id ORDER BY created_at` sin índice composite |
| B2-010  | 🟠  | Performance  | `mipit-core/src/pipeline/payment-pipeline.ts:50-263` | Pipeline emite ~9 escrituras DB sincrónicas por payment (5 UPDATE + 4 INSERT audit) |
| B2-011  | 🟠  | DB / FK      | `mipit-infra/db/init/001_schema.sql:53`, `mipit-infra/db/migrations/009_audit_events_constraints.sql:34-37` | `audit_events.payment_id FK ON DELETE RESTRICT` bloquea reaped de payments antiguos |
| B2-012  | 🟠  | RMQ          | `mipit-infra/rabbitmq/definitions.json:15-39` vs `mipit-adapter-pix/src/messaging/rabbitmq.ts:19-25` | Conflicto de declaración: `definitions.json` declara quorum + TTL + max-length; adapter `assertQueue` con args distintos → `PRECONDITION_FAILED` posible |
| B2-013  | 🟠  | DB           | `mipit-core/src/persistence/repositories/payment.repository.ts:316-322` | `findSince(created_at >= $1) ORDER BY created_at DESC` sin LIMIT — full scan en reconciliation cada 30 min |
| B2-014  | 🟡  | Concurrency  | `mipit-core/src/api/routes/sse.ts:65-79` | `broadcastPaymentEvent` mutates `clients[]` durante iteración write-failure |
| B2-015  | 🟡  | Concurrency  | `mipit-core/src/resilience/circuit-breaker.ts:76-126` | `CircuitBreaker.execute` lee y muta `state`/`failures`/`successes` sin lock (async-callback race) |
| B2-016  | 🟡  | Performance  | `mipit-core/src/persistence/db.ts:8-13` | `pg.Pool max=50` sin variable de entorno + `connectionTimeoutMillis=10s` muy alto |
| B2-017  | 🟡  | DB / Index   | `mipit-infra/db/init/001_schema.sql:5`, `008_payments_constraints_and_iso.sql:65` | No hay índices GIN sobre `canonical_payload`, `translated_payload`, `rail_ack`, `origin_payload` |
| B2-018  | 🟡  | RMQ          | `mipit-adapter-{pix,spei,breb}/src/messaging/rabbitmq.ts` | Adapters singleton module-level channel sin reconnect — `connection.on('close', () => warn)` no reschedule |
| B2-019  | 🟡  | Performance  | `mipit-core/src/fx/fx-service.ts:114-146` | FX `fetch` con timeout 5s pero **sin** Circuit Breaker + sin invalidación cache cuando "fetch ok pero rates incompletos" |
| B2-020  | 🟡  | Concurrency  | `mipit-core/src/api/middleware/rate-limit.ts:39-46` | In-memory `windows` Map: si se escalan replicas de core, cada nodo tiene su propio bucket → rate effectively N× |
| B2-021  | 🟡  | DB / Index   | `mipit-infra/db/migrations/008_payments_constraints_and_iso.sql:106` | `idx_payments_end_to_end_id` declarado partial pero `end_to_end_id` se usa también en JOINs futuros sin `is_active`-style filter — OK pero documentar |
| B2-022  | 🟡  | DB           | `mipit-infra/db/init/001_schema.sql:13` | `payments.amount` es `NUMERIC(18,2)` — OK; pero `instructed_amount`/`settlement_amount` `NUMERIC(18,5)` (mig 008:71-73) — inconsistencia precisión |
| B2-023  | 🟡  | Performance  | `mipit-core/src/index.ts:61-72` | Sweeper de idempotency corre cada **1h**, no por demanda — claves expiradas viven hasta 1h después del TTL |
| B2-024  | 🟡  | RMQ          | `mipit-core/src/messaging/dlq-handler.ts:81-85` | `nack(msg, false, true)` requeue del propio DLQ — bucle infinito si el handler falla persistentemente |
| B2-025  | 🟢  | DB           | `mipit-infra/db/init/001_schema.sql:94` | `idempotency_keys.payment_id` no es FK (comentario lo justifica), pero no hay índice sobre la columna |
| B2-026  | 🟢  | DB           | `mipit-infra/db/init/001_schema.sql:51-63` | Audit `detail JSONB` sin index — analytics queries del UI proxy pueden escanear full table |
| B2-027  | 🟢  | Performance  | `mipit-adapter-pix/src/pix/mock-server.ts:280` | Mock simula 80-450ms aleatorio (config); razonable, pero `setTimeout` no se cancela si el cliente cierra (sigue procesando) |
| B2-028  | 🟢  | RMQ          | `mipit-core/src/messaging/publisher.ts:38-60` | Publisher confirms sin pipelining/batching: `await new Promise` por mensaje → throughput máx ~RTT al broker |

---

## Detalle por hallazgo

### B2-001 🔴 — AckConsumer y DlqHandler sin prefetch

**File:** `mipit-core/src/messaging/consumer.ts:55`, `dlq-handler.ts:43`
**Observado:**
```ts
async start() {
  logger.info({ queue: QUEUES.ACK }, 'AckConsumer started');
  await this.channel.consume(QUEUES.ACK, async (msg) => { … });
}
```
No hay llamada `await this.channel.prefetch(N)`. En amqplib, **default = unlimited** (al menos hasta el siguiente ACK del consumer).

**Por qué es problema:**
1. RabbitMQ vuelca toda la cola `payments.ack` (hasta `x-message-ttl=3600000`) al proceso single-threaded.
2. Cada mensaje dispara 2 escrituras DB (`updateRailAck` + `audit insert`) más fire-webhook + SSE broadcast. Con 1k mensajes en cola y prefetch ilimitado, Node mete 1k callbacks en cola simultáneamente; el event loop se ahoga.
3. Síntoma observable: latencia ACK→COMPLETED crece linealmente con el burst; mensajes lentos arrastran a los rápidos (head-of-line blocking interno por contención del pool PG).
4. Si el proceso muere mid-burst, **todos** los mensajes en flight pero no ACKed se reentregan (no perdidos, pero amplifica el problema en el restart).

**Fix:**
```ts
async start() {
  await this.channel.prefetch(10); // arrancar conservador, subir con bench
  await this.channel.consume(QUEUES.ACK, async (msg) => { … });
}
```
Y considerar mover `webhookService.fireForPayment` a una cola dedicada (`webhooks.pending`) para no bloquear el ACK consumer en HTTP delivery (timeout 10s en `webhook.service.ts:88`).

---

### B2-002 🔴 — UPDATE de status sin guard CAS

**File:** `mipit-core/src/persistence/queries/index.ts:23-34`
**Observado:**
```sql
UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS: `
    UPDATE payments SET
      status           = $1,
      validated_at     = CASE WHEN $1 = 'VALIDATED'           THEN NOW() ELSE validated_at END,
      …
    WHERE payment_id = $2
    RETURNING *`
```
No hay cláusula `AND status = <expected_old_status>`.

**Por qué es problema (escenario concreto):**
- Pipeline marca `PMT-X = QUEUED` (paso 7 en `payment-pipeline.ts:243`).
- RabbitMQ entrega un ACK rápido al consumer; consumer marca `COMPLETED` (en `consumer.ts:123`).
- **Mientras tanto** el pipeline (otro request del mismo paymentId — improbable con ULID, **pero ocurre vía retry de RabbitMQ** cuando el ACK llega 2× por DLQ requeue del propio adapter): el segundo ACK también marca `COMPLETED`. Idempotente.
- **Pero** caso real: `consumer.ts:170` hace `nack(false, false)` cuando falla `updateRailAck`. El mensaje cae al DLQ. El DLQ handler marca `DEAD_LETTER` (`dlq-handler.ts:59`). Si después un retry manual logra el `updateRailAck`, sobreescribe `DEAD_LETTER` → `COMPLETED` **sin warning** ni audit del salto ilegal.
- Más crítico: compensation marca `COMPENSATING` → otro ACK tardío llega y marca `ACKED_BY_RAIL`, perdiendo el lock de compensación.

**Fix:**
```sql
UPDATE payments SET status = $1, … 
  WHERE payment_id = $2 
    AND status NOT IN ('COMPLETED','COMPENSATED','DEAD_LETTER','REJECTED','FAILED')
RETURNING *;
```
Si `RETURNING` devuelve 0 rows, log a `audit_events` como `ILLEGAL_TRANSITION` y NO sobrescribir.

---

### B2-003 🔴 — `findRecent` sin índice composite

**File:** `mipit-core/src/persistence/repositories/payment.repository.ts:283-299`
**Observado:**
```ts
async findRecent(limit, status?, rail?) {
  // status= → WHERE status = $1 ORDER BY created_at DESC LIMIT
  // rail=  → WHERE (origin_rail = $1 OR destination_rail = $1) ORDER BY created_at DESC LIMIT
}
```
Índices existentes:
- `idx_payments_status` (single column)
- `idx_payments_created_at` (single column)
- `idx_payments_status_created` (mig 008:107 — **NULL ASC**, no `created_at DESC`)
- `idx_payments_origin_rail`, `idx_payments_destination_rail` (singles)

**Por qué es problema:**
Postgres con `WHERE status='COMPLETED' ORDER BY created_at DESC LIMIT 50`: el planner usará uno u otro index pero no ambos; con tabla > 100k rows ese query es full index scan + sort, ~200-500ms p95. La UI ya consulta esto en `/payments?limit=50` cada refresh.

Peor — el filtro por rail `(origin_rail=$1 OR destination_rail=$1)` no puede usar índices simples por la disyunción: el planner cae a **Seq Scan** con table size > buffer cache.

**Fix:**
```sql
CREATE INDEX idx_payments_status_created_desc ON payments(status, created_at DESC);
CREATE INDEX idx_payments_origin_created_desc ON payments(origin_rail, created_at DESC);
CREATE INDEX idx_payments_dest_created_desc   ON payments(destination_rail, created_at DESC) WHERE destination_rail IS NOT NULL;
```
Y refactor el query: usar `UNION ALL` o consultar por rail concreto (origin XOR destination) en lugar de OR.

---

### B2-004 🔴 — `audit_events` sin bound, sin partición, sin cleanup

**File:** `mipit-infra/db/init/001_schema.sql:51-63`
**Observado:** Tabla `audit_events` definida con FK a `payments` y 3 índices. El pipeline emite **~7 eventos por payment** (`PAYMENT_RECEIVED`, `PAYMENT_VALIDATED`, `CANONICAL_UPDATED`, `NORMALIZATION_COMPLETE`, `ROUTE_DECISION`, `STATUS_CHANGE`, `ACK_RECEIVED`). El consumer agrega 1+. Compensation agrega 2+. **Webhook fires y reconciliation también escriben.**

**Por qué es problema:**
- A 100 TPS sostenidos = 700 inserts/seg en `audit_events`. 1 día = 60M rows. 1 mes = 1.8B rows.
- `FIND_AUDITS_BY_PAYMENT` (queries/index.ts:80) hace `WHERE payment_id ORDER BY created_at ASC` — escala según fragmentación del índice; eventualmente p99 > 1s.
- No hay job de archivado, no hay partición temporal (`PARTITION BY RANGE (created_at)`), no hay TTL.
- Es una **tabla bomba**: el PoC corre 7 días sin issue, después degrada irrecuperable sin downtime.

**Fix mínimo PoC:**
```sql
-- Particionar por mes (requiere recrear la tabla)
CREATE TABLE audit_events_partitioned (LIKE audit_events INCLUDING ALL) 
  PARTITION BY RANGE (created_at);
CREATE TABLE audit_events_2026_05 PARTITION OF audit_events_partitioned 
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
-- + cron mensual para crear partición siguiente y drop la de >12 meses
```
**Fix práctico PoC:** scheduled job (similar al sweeper de idempotency) que borra eventos > 90 días, o mover eventos non-CRITICAL (PAYMENT_RECEIVED, NORMALIZATION_COMPLETE) a downsampling después de N días.

---

### B2-005 🟠 — Adapters publican ACK sin publisher confirms

**File:** `mipit-adapter-pix/src/messaging/publisher.ts:6-18`, idem SPEI/BREB.
**Observado:**
```ts
// mipit-adapter-pix/src/messaging/rabbitmq.ts:15
channel = await connection.createChannel();   // NOT createConfirmChannel
```
```ts
// publisher.ts:9
channel.publish(env.EXCHANGE_NAME, env.ACK_ROUTING_KEY, payload, { persistent: true, … });
```

**Por qué es problema:**
`persistent: true` es teatro sin confirms. Si el broker tira la conexión entre el `publish()` (que sólo encola en el TCP buffer del adapter) y el flush al disco del broker, **el ACK se pierde silenciosamente**. El pago queda en `QUEUED` infinito porque el adapter `channel.ack(msg)` el route message creyendo entregado el ack.

Core ya está parchado (`publisher.ts:38-60` usa confirms si el channel es ConfirmChannel — `reconnect.ts:72`). Los adapters NO.

**Fix:** En cada adapter `messaging/rabbitmq.ts`:
```ts
channel = await connection.createConfirmChannel();
```
Y en `publisher.ts` envolver `channel.publish` en `new Promise((res, rej) => channel.publish(..., (err) => err ? rej : res))`.

---

### B2-006 🟠 — Mapping/Rule loader cache: thundering herd al expirar TTL

**File:** `mipit-core/src/translation/mapping-loader.ts:22-46`, `mipit-core/src/routing/rule-loader.ts:17-27`
**Observado:**
```ts
async loadMappings(rail, direction) {
  const cached = this.cache.get(key);
  if (cached && Date.now() - cached.loadedAt < TTL_MS) return cached.mappings;
  const entries = await this.repo.findByRail(rail, direction); // [A] DB query
  …
  this.cache.set(key, { mappings, loadedAt: Date.now() });    // [B]
}
```

**Por qué es problema:**
A los 5 minutos exactos, el TTL expira. Si 50 requests concurrentes están en flight, todas ven `cached.loadedAt` expirado, **todas** disparan `repo.findByRail` simultáneamente, todas escriben al mismo `cache.set`. 50× la carga al PG por 1ms.

A 200 TPS sostenidos, este pico se da cada 5 min y se traduce en ~50 queries simultáneas sobre `mapping_table` (44 rows pero index scan + parse JSON). El pool de 50 conexiones se vacía momentáneamente, todos los requests ese instante ven `ConnectionTimeout`.

**Fix:** Patrón single-flight:
```ts
private inflight = new Map<string, Promise<Map<string, MappingTransform>>>();
async loadMappings(rail, direction) {
  const key = `${rail}:${direction}`;
  const cached = this.cache.get(key);
  if (cached && Date.now() - cached.loadedAt < TTL_MS) return cached.mappings;
  let p = this.inflight.get(key);
  if (!p) {
    p = this.repo.findByRail(rail, direction).then((entries) => {
      const m = buildMap(entries);
      this.cache.set(key, { mappings: m, loadedAt: Date.now() });
      this.inflight.delete(key);
      return m;
    });
    this.inflight.set(key, p);
  }
  return p;
}
```

---

### B2-007 🟠 — Webhook re-entry: duplicados garantizados en retry de ACK

**File:** `mipit-core/src/messaging/consumer.ts:160-166`, `mipit-core/src/webhooks/webhook.repository.ts:51-58`
**Observado:**
```ts
// consumer.ts:160
if (this.webhookService && ['COMPLETED', 'FAILED', 'REJECTED'].includes(finalStatus)) {
  this.webhookService.fireForPayment(updatedPayment).catch((err) => { … });
}
```
```ts
// webhook.repository.ts:51 - findPending DESPRECIA su nombre
async findPending(paymentId, event) {
  return this.db.query(`SELECT * FROM webhook_subscriptions WHERE payment_id = $1 AND $2 = ANY(events)`, …);
  // ↑ NO filtra por fired_at IS NULL
}
```

**Por qué es problema:**
1. ACK llega → `updateRailAck` exitoso → broadcast → `fireForPayment` (lanza HTTP no-await).
2. `await this.auditService.log` también es awaited después. Si **ese** log falla, `nack(false, false)` → DLQ.
3. Pero el webhook ya se disparó hacia el cliente.
4. DLQ handler reentrega? No. Pero si el adapter reenvía el ACK por la razón que sea (e.g. el `nack` del core hizo perder el ack del adapter, adapter reintentó), **otro ACK llega** → otro `fireForPayment` → otra entrega HTTP.
5. `findPending` no filtra por `fired_at IS NULL` ni por idempotency-key específico de la entrega → **siempre re-fire** todas las subscriptions.

**Fix:**
- Filtrar `WHERE fired_at IS NULL` en `findPending` (el índice partial `idx_webhook_fired_at WHERE fired_at IS NULL` de mig 004:22 lo soporta).
- Mover el fire a una cola dedicada con su propia idempotencia (delivery_id por subscription+payment+event).
- Tener una guarda explícita en `consumer.ts:160`: chequear si `previous_status` ya era terminal — en ese caso skip.

---

### B2-008 🟠 — Doble compensación concurrente

**File:** `mipit-core/src/compensation/compensation-service.ts:40-122`
**Observado:**
```ts
async compensate(paymentId) {
  const payment = await this.paymentRepo.findById(paymentId);          // [A] read
  if (!COMPENSABLE_STATUSES.has(payment.status)) return …;
  await this.paymentRepo.updateStatus(paymentId, COMPENSATING);        // [B] write
  …
  await this.paymentRepo.updateStatus(paymentId, COMPENSATED);         // [C] write
}
```

**Por qué es problema (escenario concreto):**
Operador clickea "Compensar" 2 veces. Dos requests entran al endpoint `/compensate/:paymentId` (`server.ts:154`):
- T0: Req1 read → status=DEAD_LETTER → compensable=true → write COMPENSATING.
- T0+5ms: Req2 read → status=DEAD_LETTER (Req1 aún no escribió) → compensable=true → write COMPENSATING.
- Ambos emiten `pacs.004` (audit log) con `RTR-` distintos.
- Ambos escriben COMPENSATED. Cliente recibe 2 reversiones — escenario plata duplicada.

**Fix:**
```sql
UPDATE payments SET status = 'COMPENSATING' 
  WHERE payment_id = $1 
    AND status IN ('DEAD_LETTER', 'FAILED')
RETURNING *;
-- Si rowCount = 0 → otro proceso ya lo tomó, abort
```
Es CAS — variante del fix B2-002.

---

### B2-009 🟠 — `audit_events` lookup sin índice composite

**File:** `mipit-infra/db/init/001_schema.sql:61`, queries `FIND_AUDITS_BY_PAYMENT` en `mipit-core/src/persistence/queries/index.ts:80`
**Observado:**
```sql
CREATE INDEX idx_audit_payment_id  ON audit_events(payment_id);
CREATE INDEX idx_audit_created_at  ON audit_events(created_at);
```
Y query: `SELECT * FROM audit_events WHERE payment_id = $1 ORDER BY created_at ASC`.

**Por qué es problema:** El planner usa `idx_audit_payment_id` para localizar las filas pero después hace **sort en memoria** por `created_at`. Para payments con 20+ eventos en una tabla de 100M filas, el sort + heap fetches es lento. La UI hace este query cada vez que se abre el detail de un payment.

**Fix:**
```sql
CREATE INDEX idx_audit_payment_created ON audit_events(payment_id, created_at);
-- Y drop el index single-column idx_audit_payment_id (redundante)
```

---

### B2-010 🟠 — Pipeline emite ~9 escrituras DB sincrónicas por payment

**File:** `mipit-core/src/pipeline/payment-pipeline.ts:50-263`
**Observado:** Auditando un pago happy-path se ejecutan en serie:
1. `paymentRepo.create` (INSERT payment)
2. `auditService.log` PAYMENT_RECEIVED (INSERT audit)
3. `paymentRepo.updateStatus(VALIDATED)` (UPDATE payment)
4. `auditService.log` PAYMENT_VALIDATED (INSERT)
5. `paymentRepo.updateEndToEndId` (UPDATE)
6. `paymentRepo.updateCanonical` (UPDATE)
7. `auditService.log` CANONICAL_UPDATED (INSERT)
8. `auditService.log` NORMALIZATION_COMPLETE (INSERT)
9. `paymentRepo.updateFxAndSettlement` (UPDATE)
10. `paymentRepo.updateCanonical` (UPDATE, segunda vez para post-FX)
11. `paymentRepo.updateRoute` (UPDATE)
12. `auditService.logRoutingDecision` (INSERT)
13. `paymentRepo.updateTranslated` (UPDATE)
14. Publish RMQ
15. `paymentRepo.updateStatus(QUEUED)` (UPDATE)
16. `auditService.log` STATUS_CHANGE (INSERT)

**11 escrituras DB awaited sincrónicamente** por pago, no 9. Cada una es un round-trip al Postgres. Asumiendo p50=2ms = 22ms/pago piso solo por DB sincrónica + el publish RMQ con confirms (otro await).

**Por qué es problema:** Esto fija el techo de TPS de un Node single-thread a ~45-50 TPS (= 1/0.022). Para 100 TPS necesitás 2+ replicas del core; y entonces tenés problemas de B2-020 (rate limiter in-memory).

**Fix opciones:**
- Combinar varias `auditService.log` en un único `INSERT INTO audit_events VALUES ..., ..., ...` por pago (1 round-trip en lugar de 4-6).
- Consolidar los 5 UPDATE en un único stored procedure que avanza payment de RECEIVED a QUEUED en una sola transacción.
- Mover audit writes a una queue async (fire-and-forget al `auditService`, worker batchea cada 100ms).

---

### B2-011 🟠 — `audit_events.payment_id FK ON DELETE RESTRICT`

**File:** `mipit-infra/db/migrations/009_audit_events_constraints.sql:34-37`
**Observado:**
```sql
ALTER TABLE audit_events
  ADD CONSTRAINT audit_events_payment_id_fkey
  FOREIGN KEY (payment_id) REFERENCES payments(payment_id)
  ON DELETE RESTRICT;
```

**Por qué es problema:**
1. Implica que `DELETE FROM payments WHERE created_at < NOW() - INTERVAL '90 days'` (típico data-retention) **falla** porque `audit_events` tiene FK. Hay que borrar `audit_events` primero, en order.
2. Combinado con B2-004 (audit no bounded) y sin tooling de cleanup, retentar payments es operacionalmente caro.
3. **CASCADE bloqueante**: si alguien intenta `DROP TABLE payments` para una migración destructiva → falla.

**Fix:** No hay un fix obvio sin trade-off. Opciones:
- Cambiar a `ON DELETE NO ACTION` (igual bloquea pero permite `DEFERRABLE INITIALLY DEFERRED`).
- Cambiar a `ON DELETE SET NULL` y aceptar audit huérfanos.
- **Recomendado:** mantener `RESTRICT` pero documentar el proceso de cleanup (borrar audit_events → borrar webhook_subscriptions CASCADE-libres → borrar payments).

---

### B2-012 🟠 — Conflicto declaración queue: definitions.json vs adapter `assertQueue`

**File:** `mipit-infra/rabbitmq/definitions.json:15-39` declara:
```json
{
  "name": "payments.route.pix",
  "x-queue-type": "quorum",
  "x-dead-letter-exchange": "mipit.dlx",
  "x-dead-letter-routing-key": "dlq.pix",
  "x-message-ttl": 3600000,
  "x-max-length": 100000
}
```
Pero `mipit-adapter-pix/src/messaging/rabbitmq.ts:19-25`:
```ts
await channel.assertQueue(env.QUEUE_NAME, {
  durable: true,
  arguments: {
    'x-dead-letter-exchange': 'mipit.dlx',
    'x-dead-letter-routing-key': 'dlq.pix',
    // ← FALTA x-queue-type, x-message-ttl, x-max-length
  },
});
```

**Por qué es problema:** AMQP `queue.declare` con `passive=false` falla con `PRECONDITION_FAILED` si los argumentos no coinciden con la queue existente. Hoy funciona porque `definitions.json` carga primero y los args son **superset** del adapter — RabbitMQ ignora silenciosamente el `assertQueue` del cliente al ser equivalent-or-stricter. **Pero** si:
- Alguien edita `definitions.json` cambiando algún arg → adapter falla al startup.
- Se ejecuta el adapter contra un RabbitMQ vanilla (sin definitions.json cargado) → crea la queue como classic, sin TTL ni quorum, y el comportamiento bajo carga es completamente distinto al de staging.

**Fix:** Sincronizar args en `assertQueue` o eliminar el `assertQueue` de los adapters y confiar 100% en `definitions.json` con un `passive: true` solo para validar conectividad.

---

### B2-013 🟠 — `findSince` sin LIMIT

**File:** `mipit-core/src/persistence/repositories/payment.repository.ts:316-322`
**Observado:**
```ts
async findSince(since: string): Promise<PaymentIntent[]> {
  const result = await this.db.query(
    'SELECT * FROM payments WHERE created_at >= $1 ORDER BY created_at DESC', [since],
  );
}
```
Y `index.ts:148` lo invoca cada 30 min en reconciliation con `windowHours=1`. Pero el endpoint `/analytics/reconciliation` lo invoca con cualquier `hours` (default 24).

**Por qué es problema:** Sin LIMIT, en 24h con 100 TPS = 8.6M rows. `SELECT *` arrastra todos los JSONB de canonical/translated/origin payloads (varios KB cada uno) → MB→GB transferidos del PG al core, parseados a JS objects, iterados in-memory para construir el report. Memoria del core sube > 1 GB por una sola reconciliation request.

**Fix:** Forzar `LIMIT 50000`, paginar, o reescribir reconciliation como agregaciones SQL directas sin traer las rows completas:
```sql
SELECT status, COUNT(*), AVG(EXTRACT(EPOCH FROM (completed_at - created_at)))
FROM payments WHERE created_at >= $1 GROUP BY status;
```

---

### B2-014 🟡 — SSE broadcast itera y muta el array

**File:** `mipit-core/src/api/routes/sse.ts:65-79`
**Observado:**
```ts
for (let i = clients.length - 1; i >= 0; i--) {
  const client = clients[i];
  if (client.paymentFilter && client.paymentFilter !== event.payment_id) continue;
  try { client.reply.raw.write(`event: payment_update\ndata: ${data}\n\n`); }
  catch { clients.splice(i, 1); }
}
```
La iteración descendente con `splice` es correcta, **pero** otra request en curso (`req.raw.on('close')` en línea 123) también puede hacer `clients.splice(idx, 1)` con `idx = findIndex(c => c.id === clientId)`. Si el `findIndex` corre durante el for loop, encuentra el cliente en posición vieja, hace splice de otra cosa.

**Por qué es problema:** Es Node single-thread, el for loop no se interrumpe a mitad de iteración por callbacks I/O — el splice del 'close' handler corre en otro tick. **Pero** si `client.reply.raw.write` lanza síncronamente (rare, pero documented en Node streams), entramos al catch que hace splice, y el `findIndex` posterior del 'close' handler (otro tick) busca un cliente ya eliminado y splicea otro.

**Fix:** Usar un `Map<clientId, SseClient>` en lugar de Array. O snapshot la lista al inicio del broadcast.

---

### B2-015 🟡 — CircuitBreaker mutate-sin-lock

**File:** `mipit-core/src/resilience/circuit-breaker.ts:76-126`
**Observado:**
```ts
async execute<T>(fn) {
  if (this.state === 'OPEN') { … }                  // [read]
  try { const r = await fn(); this.onSuccess(); }  // [await + write]
  catch (e) { this.onFailure(); throw e; }          // [write]
}
```
- Req1 entra, state=CLOSED → llama fn() → await.
- Req2 entra, ve state=CLOSED → llama fn() → await.
- Req1 falla → onFailure → state=OPEN, openedAt=now.
- Req2 falla → onFailure → entra al `if (state === 'HALF_OPEN')` (línea 113) → ¡PERO el state está en OPEN!

Spoiler: el chequeo de Req2 ve `state==='OPEN'` y va al else branch (línea 119) `if (state === 'CLOSED' && shouldOpen())` — no entra. Ningún side effect raro. **PERO:**

El verdadero problema está en `shouldTransitionToHalfOpen` + transición. Dos requests llegan simultáneamente cuando cooldownMs vence:
- Req1: `state==='OPEN'` → `shouldTransitionToHalfOpen() === true` → `transitionTo('HALF_OPEN')` (línea 79) → await fn().
- Req2: misma carrera → mismo path → HALF_OPEN → fn().

Resultado: dos probes simultáneos. El propósito de HALF_OPEN era exactamente uno. Si la primera prueba falla y la segunda éxito, la segunda sobreescribe a CLOSED reseteando contadores; el "fail safe" del breaker está derrotado.

**Fix:**
```ts
async execute<T>(fn) {
  if (this.state === 'OPEN') {
    if (this.shouldTransitionToHalfOpen()) {
      // CAS atómico:
      if (this.state !== 'OPEN') throw new CircuitOpenError(...);  // alguien más cambió
      this.state = 'HALF_OPEN';
    } else throw new CircuitOpenError(...);
  }
  // Para HALF_OPEN: contador atomic de probes "ya en vuelo"
  if (this.state === 'HALF_OPEN' && this.probesInFlight >= 1) throw new CircuitOpenError(...);
  this.probesInFlight++;
  try { ... } finally { this.probesInFlight--; }
}
```

---

### B2-016 🟡 — `pg.Pool max=50` hardcoded + connectTimeout 10s

**File:** `mipit-core/src/persistence/db.ts:8-13`
**Observado:**
```ts
pool = new Pool({
  connectionString,
  max: 50,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
});
```

**Por qué es problema:**
- `max=50` está hardcoded; postgres está configurado con `max_connections=200` (`docker-compose.yml:20`) — 4 cores comerían el pool entero si se escala.
- `connectionTimeoutMillis: 10_000`: bajo back-pressure, un request espera **10 segundos** para fallar — Fastify timeout default es 0 (sin), así que el cliente HTTP recibe 30s sin response. p99 explota.
- Mejor: 3000ms; queremos fail-fast bajo presión y dejar que el HTTP rate limiter o el cliente reintente.

**Fix:**
```ts
pool = new Pool({
  connectionString,
  max: parseInt(process.env.PG_POOL_MAX ?? '20', 10),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 3_000,
  statement_timeout: 5_000,         // cancelar queries > 5s
  query_timeout: 5_000,
});
```

---

### B2-017 🟡 — No hay índices GIN sobre JSONB

**File:** `mipit-infra/db/init/001_schema.sql:26-29`
**Observado:** Tabla `payments` tiene 4 columnas JSONB (`origin_payload`, `canonical_payload`, `translated_payload`, `rail_ack`) y `audit_events.detail` JSONB. Ningún índice GIN.

**Por qué es problema:** Hoy no hay queries que filtran por path JSONB en producción, **pero** el endpoint `GET /payments/:id` (payments.ts:148) retorna los 4 payloads completos — si alguien implementa `/payments?uetr=...` filtrando por `canonical_payload->>'uetr'` será full scan. Y la UI de UI-proxy (ver `analytics.ts`) puede agregar filtros por `rail_ack->>'rail_tx_id'`.

**Fix (preventivo, opcional):**
```sql
CREATE INDEX idx_payments_canonical_gin ON payments USING GIN (canonical_payload jsonb_path_ops);
CREATE INDEX idx_payments_rail_ack_gin  ON payments USING GIN (rail_ack jsonb_path_ops);
```
Cost: ~30% más slow al INSERT y ~3-5% más espacio. Beneficio: filter por any path con O(log n).

---

### B2-018 🟡 — Adapters sin auto-reconnect

**File:** `mipit-adapter-{pix,spei,breb}/src/messaging/rabbitmq.ts:31-37`
**Observado:**
```ts
connection.on('error', (err) => { logger.error({err}, 'RabbitMQ connection error'); });
connection.on('close', () => { logger.warn('RabbitMQ connection closed'); });
```
Solo loggea. No re-conecta. No re-bind queue.

**Por qué es problema:** Si RabbitMQ se reinicia (mantenimiento, healthcheck failure, OOM), los 3 adapters quedan zombies hasta que docker compose restart los detecte. Core sí maneja reconnect (`reconnect.ts`). Aún parchado en core (Wave 6), los adapters no.

**Fix:** Portar `RabbitMQReconnector` a un módulo compartido y usarlo en los 3 adapters. (Esto se mencionó en AUDIT-RAW-adapters.md también).

---

### B2-019 🟡 — FX sin Circuit Breaker

**File:** `mipit-core/src/fx/fx-service.ts:114-146`
**Observado:**
```ts
const res = await fetch(url, { signal: AbortSignal.timeout(5000), … });
…
} catch (err) {
  logger.warn({err}, 'Failed to fetch FX rates — using fallback rates');
  return this.cache?.rates ?? FALLBACK_RATES;  // NOT updating this.cache
}
```

**Por qué es problema:**
1. Sin CB, si Open Exchange Rates está down, cada request al pipeline (cada `normalize` en `currency-rules.ts:54`) intenta el `fetch` con timeout 5s. A 50 TPS = 50 fetches/seg en cola, cada uno fail-bound al timeout. Latencia p99 del pipeline pasa de 50ms a 5s+.
2. El comentario "Don't update cache on error so we retry sooner" amplifica el problema. Debería ser todo lo contrario: si falla, cache la falla por 60s para fail-fast siguientes intentos.

**Fix:**
```ts
import { circuitBreakerRegistry } from '../resilience/circuit-breaker.js';
const fxBreaker = circuitBreakerRegistry.get('fx-service', { failureThreshold: 3, cooldownMs: 60_000 });
async getRates() {
  …
  try {
    return await fxBreaker.execute(() => this.fetchRates());
  } catch {
    return this.cache?.rates ?? FALLBACK_RATES;
  }
}
```

---

### B2-020 🟡 — Rate limiter HTTP in-memory

**File:** `mipit-core/src/api/middleware/rate-limit.ts:36-46`
**Observado:**
```ts
const windows = new Map<string, WindowEntry>();
```

**Por qué es problema:** Si el core se replica (escala horizontal), cada réplica tiene su propio `Map`. Cliente con IP X disparando 200 req/min ve `2 × 200 = 400` permitidos (round-robin entre 2 réplicas). El rate limit se debilita proporcionalmente al `N` replicas.

Similar para el `RateLimiter` token-bucket por rail (`resilience/rate-limiter.ts`) que limita el **destination rail** — si hay 2 cores, PIX puede recibir 2×20 = 40 TPS, superando el rate limit que el adapter PIX espera.

**Fix:** Migrar a Redis (`@upstash/ratelimit` o `fastify-rate-limit` con `redis` store). Para PoC con 1 replica es non-issue, marcarlo como "TODO antes de escalar".

---

### B2-021 🟡 — Inconsistencia precision en amounts

**File:** `mipit-infra/db/init/001_schema.sql:13` vs `mipit-infra/db/migrations/008_payments_constraints_and_iso.sql:71-73`
**Observado:**
```sql
-- 001:
amount NUMERIC(18,2) NOT NULL,
-- 008:
ADD COLUMN IF NOT EXISTS instructed_amount NUMERIC(18,5);
ADD COLUMN IF NOT EXISTS settlement_amount NUMERIC(18,5);
```

**Por qué es problema:** `amount` está con 2 decimales (BRL/MXN/USD requieren 2). `instructed_amount` y `settlement_amount` con 5 decimales (justificado para FX rates, e.g. 0.19987 BRL/USD). Pero si el código copia `amount` a `instructed_amount` (`payment-pipeline.ts:73`), la inconsistencia no causa bug — el ISO 20022 `InstdAmt` puede admitir 5 dec. **Sí causa confusión en queries de analytics**: si se hace `SUM(amount) - SUM(settlement_amount)` para detectar drift, los redondeos no coinciden.

**Fix:** Aceptable como está, pero documentar en el schema (comment SQL en la columna).

---

### B2-022 🟡 — Idempotency sweeper corre cada 1h

**File:** `mipit-core/src/index.ts:61-72`
**Observado:**
```ts
const sweepInterval = setInterval(async () => { … }, 60 * 60 * 1000);
```

**Por qué es problema:** TTL es 24h (default). Sweeper corre cada hora. Una clave expirada a las 13:01 vive hasta las 14:00. **Función**: si un cliente envía la misma `idempotency-key` después de 24h, el `findByKey` (que ya filtra `expires_at > NOW()` en el query) retorna NULL — entonces el `tryInsert` falla con `ON CONFLICT DO NOTHING` porque la fila vieja sigue ahí.

Wait — re-leyendo `INSERT_IDEMPOTENCY`: usa `ON CONFLICT (idempotency_key) DO NOTHING RETURNING payment_id`. Si la fila vieja expirada existe, `ON CONFLICT` se dispara y `tryInsert` retorna `claimed=false`. Pero `findByKey` retorna NULL (filtra por expires_at). Entonces el handler `payments.ts:56-62` cree que otro request claimó el key recientemente y devuelve... `winner?.payment_id` que es undefined. **El endpoint retorna `200 { payment_id: undefined, status: 'QUEUED' }`**. Bug observable.

**Fix:**
- Correr sweeper cada 5 min: `60 * 5 * 1000`.
- O cambiar `INSERT_IDEMPOTENCY` a `INSERT ... ON CONFLICT DO UPDATE SET payment_id=$2, ... WHERE idempotency_keys.expires_at < NOW()`.

---

### B2-023 🟡 — DLQ handler con `nack(false, true)` loopea

**File:** `mipit-core/src/messaging/dlq-handler.ts:81-85`
**Observado:**
```ts
} catch (err) {
  log.error({err}, 'Failed to process DLQ message');
  this.channel.nack(msg, false, true);  // requeue=true en la propia DLQ
}
```

**Por qué es problema:** Si el handler falla persistente (por ejemplo, el payment_id no existe en la tabla payments porque alguien lo borró), el mensaje se requeue, el handler vuelve a fallar, loop infinito al 100% CPU.

**Fix:**
```ts
} catch (err) {
  const retries = (msg.properties.headers?.['x-dlq-retries'] as number) ?? 0;
  if (retries >= 3) {
    log.fatal({err, retries}, 'DLQ message un-processable; discarding');
    this.channel.ack(msg);  // accept and drop
    return;
  }
  this.channel.nack(msg, false, true);
  // … podemos mejorar republishing con x-dlq-retries++, pero el ack-after-N es lo mínimo
}
```

---

### B2-024 🟢 — `idempotency_keys.payment_id` sin índice

**File:** `mipit-infra/db/init/001_schema.sql:94-104`
**Observado:**
```sql
CREATE TABLE idempotency_keys (
    idempotency_key TEXT PRIMARY KEY,
    payment_id      TEXT NOT NULL,  -- no FK
    …
);
CREATE INDEX idx_idempotency_expires ON idempotency_keys(expires_at);
```
No hay índice en `payment_id`.

**Por qué es problema:** Hoy no se busca por payment_id en este tabla. Pero si alguien implementa "qué idempotency-key se usó para crear PMT-X" para debugging, será seq scan.

**Fix:** Solo si se anticipa el query. Marcar como `BAJO`.

---

### B2-025 🟢 — Audit detail JSONB sin GIN

**File:** `mipit-infra/db/init/001_schema.sql:51-63`
**Observado:** `audit_events.detail JSONB` con 3 índices, ninguno sobre `detail`. Recursos como `WHERE detail->>'destination_rail' = 'PIX'` para analytics serán full scan.

**Por qué es problema:** Análogo a B2-017 pero menos crítico porque hoy nadie filtra por detail.

**Fix:** Diferir.

---

### B2-026 🟢 — Mock setTimeout no cancelable

**File:** `mipit-adapter-pix/src/pix/mock-server.ts:233-237`, 280-323
**Observado:** El mock dispara `setTimeout` de 80-450ms (success) o 30s (forceTimeoutNext) sin guardar reference. Si el adapter cierra la HTTP request antes de que el setTimeout dispare, `res.json(...)` igual ejecuta — error `Cannot set headers after they are sent`.

**Fix:** Guardar el timer y cancelarlo en `req.on('close', () => clearTimeout(timer))`.

---

### B2-027 🟢 — Publisher confirms sin pipelining

**File:** `mipit-core/src/messaging/publisher.ts:38-60`
**Observado:** Cada `publishToAdapter` espera el confirm individual (`new Promise((resolve, reject) => publish(...))`). Throughput máximo ≈ 1 / RTT al broker. Con RTT~2ms local = 500 publish/seg. En producción con broker remoto (10ms RTT) = 100 publish/seg → cuello.

**Fix:** Batchear N publishes y hacer `await channel.waitForConfirms()` una sola vez cada N. Implementación más compleja pero permite >10k publish/seg. Para PoC no es urgente.

---

## Estimación TPS sostenible (PoC actual)

**Setup medido:** 1 mipit-core + 3 adapters (PIX/SPEI/BREB), PG 16 con `max_connections=200`, RabbitMQ 3.13 con quorum queues, todo en Docker compose local en 1 host (probable 4-8 cores).

**Cuellos de botella en orden de severidad:**

1. **ACK consumer single-threaded + sin prefetch (B2-001)**
   - Cada ACK: 1 UPDATE payments + 1 INSERT audit + opcional webhook fire + SSE broadcast.
   - Latencia p50 estimada por ACK: ~10ms (1 UPDATE 3ms + 1 INSERT 3ms + overhead 4ms).
   - Sin paralelismo (no prefetch=N + concurrent handler), techo = 1/0.010 = **100 ACK/seg**.
   - Pero al recibir burst, sin prefetch RabbitMQ inunda el handler con todos los messages a la vez, el event loop se congestiona, p99 se va a >1s.

2. **Pipeline DB heavy: 11 escrituras awaited (B2-010)**
   - Latencia p50 pipeline: ~50-60ms estimado (11 round-trips @ 3-5ms + translate + normalize + publish con confirms).
   - Techo de pipeline single-thread: ~18 TPS si las escrituras son completamente secuenciales (= 1/0.055).
   - Pero Node hace event loop concurrency → 5-10 pipeline en vuelo a la vez sin contención (cada uno awaiteando I/O distinta) → ~50-80 TPS.

3. **PG pool de 50 conexiones + 11 queries/payment (B2-016)**
   - Cada pipeline retiene 1 conexión por query (pg async). Con 50 conexiones y 11 queries/pago = ~4 pipelines simultáneas máximas si todas saturan el pool. En realidad, las queries son cortas y la conexión vuelve al pool inmediatamente → cuello no es el pool, es el throughput de Postgres.
   - PG con `shared_buffers=128MB` es mínimo. A >100 TPS el cache hit rate baja, p99 sube.

**Estimación realista TPS sostenido (sin degradación >p95=500ms):** **25-45 PIX/SPEI/BREB-mixto TPS**.

- Esto excluye burst — un burst de 200 mensajes en 1 segundo el sistema lo absorbe pero la latencia del último mensaje del burst puede ser 5-10s.
- En modo "all-PIX" porque el rate limiter por rail es 20/seg (`constants.ts:151`), techo PIX puro = 20 TPS por config. Otros rails también capean (SPEI 10, BRE_B 8).
- Sin las 5 mejoras críticas (B2-001 a B2-004, B2-005), llegar a 100 TPS requiere mucho más que tunear — hay que cambiar la arquitectura (mover audit a async queue, batching, particionado).

**Los 3 cuellos de botella principales (priorizados):**

1. 🔴 **B2-001 — ACK consumer sin prefetch + sin paralelismo + webhook inline**.
   Fix: prefetch=10 + `Promise.allSettled` por message-batch + webhook a queue separada.
   Ganancia esperada: 2-3× throughput del consumer.

2. 🔴 **B2-010 — Pipeline emite 11 escrituras DB awaited en serie**.
   Fix: Consolidar audit INSERTs (batch), stored procedure para advance status, async audit log.
   Ganancia esperada: ~50% reducción de latencia p50 pipeline → 2× TPS.

3. 🔴 **B2-004 — `audit_events` sin bound** + 🔴 **B2-002 — UPDATE sin CAS**.
   No son TPS-bottlenecks hoy, pero son **liability-bottlenecks**: en 30 días de operación el sistema se vuelve no-mantenible (audit terabytes, status corrupted bajo retries).
   Fix: scheduled cleanup audit (90 días) + CAS guard en updateStatus.

**Acción concreta sugerida pre-demo:**
- Aplicar B2-001 (1 línea).
- Aplicar B2-002 (cláusula AND status en el UPDATE).
- Aplicar B2-003 (3 CREATE INDEX).
- Estos 3 fixes son <1h de trabajo, mejoran el throughput observable y eliminan los 2 riesgos de corrupción más obvios. Resto puede ir a backlog post-PoC.
