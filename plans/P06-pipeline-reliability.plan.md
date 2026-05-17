# P06 — Pipeline Reliability & Transactional Outbox

**Wave**: 3 (cross-cutting, post rail-specific)
**Repos afectados**: `mipit-core`, `mipit-infra`
**Branch**: `Auditoria-Claude`
**Estimación**: 4-5 días
**Riesgo**: Alto (toca el pipeline crítico; tests deben cubrir thoroughly)

---

## 1. Objetivo

Eliminar los "dead-code" patterns y los puntos de pérdida de datos. Hoy:

- Pipeline publica al broker **antes** de marcar QUEUED → crash entre los dos = mensaje en queue, DB en ROUTED.
- Publisher sin confirms → broker blip = mensaje silenciosamente perdido.
- Reconnect handler no re-attach consumers → tras blip, ACKs se acumulan y nunca procesan.
- Idempotency con TWO implementations (middleware dead, route handler activo) y TTL bug.
- Rate limiter y circuit breaker **definidos pero nunca llamados** (decorativos).
- Compensation es un stub que no emite pacs.004.

Este plan endereza todos esos puntos.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| C1 | **C** | Pipeline sin transacción DB; publish antes de UPDATE |
| C2 | **C** | Publisher sin `createConfirmChannel` |
| C3 | **C** | Reconnect no re-attach `AckConsumer/DlqHandler/Publisher` |
| C4 | H | Estado `NORMALIZED` definido pero nunca persistido |
| C5 | H | Routing rules sin tie-breaker estable |
| C6 | **C** | Pipeline ~7 writes secuenciales sin BEGIN/COMMIT |
| C7 | H | `consumer.ts:88` hard-codea destination_rail (`PIX' ? 'SPEI' : 'PIX'`) |
| C9 | **C** | 2 implementaciones idempotency que compiten |
| C10 | **C** | Idempotency TTL bug (`expires_at` no escribe) |
| C13 | H | Race en concurrent same-key sin Retry-After |
| C14 | **C** | `rate-limiter.acquire()` nunca llamado |
| C15 | **C** | `circuit-breaker.execute()` nunca llamado |
| C16 | H | Reconnect leak listeners `'close'` |
| C19 | **C** | Compensation es stub (no emite pacs.004) |
| C20 | H | pacs.004 sin `RtrId, RtrRsnInf, OrgnlGrpHdr` |
| C21 | H | Reconciliation read-only sin webhook/persistencia |
| C22 | M | Reconciliation setInterval sin overlap guard |
| E24 | H | `payments.ack` queue sin DLX |

---

## 3. Out of scope

- **NO** se hace event-sourcing total (mantiene state machine + audit table como está).
- **NO** se cambia a un message bus distinto.
- **NO** se introduce un coordinator/orchestrator service externo (mantiene monolito modular del core).

---

## 4. Dependencias

- **Bloquea**: P10 (tests resilience).
- **Depende de**: P01 (canónico con UETR/ChrgBr), P09 (DB schema).

---

## 5. Tareas detalladas

### 5.1 Transactional outbox pattern

Crear tabla `outbox` en `mipit-infra/db/migrations/007_outbox.sql`:

```sql
CREATE TABLE outbox (
  id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  payment_id  TEXT NOT NULL REFERENCES payments(payment_id),
  exchange    TEXT NOT NULL,
  routing_key TEXT NOT NULL,
  payload     JSONB NOT NULL,
  headers     JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at TIMESTAMPTZ,
  attempts    INT NOT NULL DEFAULT 0,
  last_error  TEXT
);

CREATE INDEX idx_outbox_pending ON outbox(created_at) WHERE published_at IS NULL;
```

`mipit-core/src/messaging/outbox-publisher.ts`:

```ts
export class OutboxPublisher {
  constructor(
    private db: Pool,
    private channel: ConfirmChannel,
    private logger: Logger,
    private pollIntervalMs = 250
  ) {}

  start() {
    this.timer = setInterval(() => this.flush().catch(err => this.logger.error({ err })), this.pollIntervalMs);
  }

  stop() { clearInterval(this.timer); }

  async flush() {
    if (this.flushing) return;
    this.flushing = true;
    try {
      const { rows } = await this.db.query(
        `SELECT * FROM outbox WHERE published_at IS NULL ORDER BY created_at ASC LIMIT 100 FOR UPDATE SKIP LOCKED`
      );
      for (const row of rows) {
        try {
          await this.publishWithConfirm(row);
          await this.db.query(`UPDATE outbox SET published_at = NOW() WHERE id = $1`, [row.id]);
        } catch (err) {
          await this.db.query(
            `UPDATE outbox SET attempts = attempts + 1, last_error = $2 WHERE id = $1`,
            [row.id, String(err)]
          );
          this.logger.warn({ err, outbox_id: row.id }, 'Outbox publish failed');
        }
      }
    } finally {
      this.flushing = false;
    }
  }

  private async publishWithConfirm(row: OutboxRow): Promise<void> {
    return new Promise((resolve, reject) => {
      this.channel.publish(
        row.exchange,
        row.routing_key,
        Buffer.from(JSON.stringify(row.payload)),
        { persistent: true, headers: row.headers ?? {} },
        (err) => err ? reject(err) : resolve()
      );
    });
  }
}
```

- [ ] Crear tabla migración
- [ ] Crear OutboxPublisher
- [ ] `Publisher` cambia a escribir en `outbox` en lugar de publicar directo
- [ ] `index.ts` arranca OutboxPublisher

### 5.2 Pipeline transactional

`mipit-core/src/pipeline/payment-pipeline.ts`. Refactor para usar **una connection + transaction**:

```ts
async execute(req: CreatePaymentRequest, ctx: PipelineContext): Promise<Payment> {
  const client = await this.db.connect();
  try {
    await client.query('BEGIN');

    const payment = await this.steps.create(client, req, ctx);
    await this.steps.validate(client, payment, ctx);
    const canonical = await this.steps.canonicalize(client, payment, ctx);
    const normalized = await this.steps.normalize(client, canonical, ctx);
    const routed = await this.steps.route(client, normalized, ctx);
    const translated = await this.steps.translate(client, routed, ctx);

    // Outbox-publish instead of direct broker write:
    await this.outboxRepo.enqueue(client, {
      payment_id: payment.payment_id,
      exchange: EXCHANGES.PAYMENTS,
      routing_key: ROUTING_KEYS[`route.${routed.destination_rail.toLowerCase()}`],
      payload: { payment_id: payment.payment_id, canonical: translated },
      headers: { trace_id: ctx.traceId, 'mipit-uetr': payment.uetr }
    });

    await this.steps.markQueued(client, payment, ctx);
    await client.query('COMMIT');
    return payment;
  } catch (err) {
    await client.query('ROLLBACK');
    await this.steps.markFailed(payment, err); // outside transaction
    throw err;
  } finally {
    client.release();
  }
}
```

- [ ] Refactorizar `payment-pipeline.ts` para usar single connection + transaction
- [ ] Cada step recibe el `client` (no usa `db.query` con random connection)
- [ ] Outbox enqueue dentro de la misma transacción → atomicity garantizada
- [ ] Si hay rollback, los acks pueden actualizar el `payment` desde el `consumer` (que tiene su propio commit)

### 5.3 Confirm channel en publishers

`mipit-core/src/messaging/publisher.ts`:

```ts
import { ConfirmChannel } from 'amqplib';

export class Publisher {
  constructor(private channel: ConfirmChannel) {} // NOT plain Channel

  async publish(exchange: string, routingKey: string, payload: any, headers: any = {}): Promise<void> {
    return new Promise((resolve, reject) => {
      this.channel.publish(
        exchange, routingKey,
        Buffer.from(JSON.stringify(payload)),
        { persistent: true, contentType: 'application/json', headers },
        (err) => err ? reject(err) : resolve()
      );
    });
  }
}
```

- [ ] Cambiar `Channel` a `ConfirmChannel`
- [ ] En `index.ts`: `await connection.createConfirmChannel()` en vez de `createChannel()`
- [ ] Adapters publisher mismo cambio
- [ ] Tests verifican confirm callback received

### 5.4 Reconnect re-attach consumers

`mipit-core/src/resilience/reconnect.ts`:

```ts
export class RabbitMQReconnector {
  private consumerBootstraps: Array<(ch: ConfirmChannel) => Promise<void>> = [];

  registerConsumerBootstrap(fn: (ch: ConfirmChannel) => Promise<void>) {
    this.consumerBootstraps.push(fn);
  }

  private async connect(): Promise<void> {
    // ... existing logic ...
    this.channel = await this.connection.createConfirmChannel();

    // Re-establish topology
    await this.onReconnect?.(this.connection, this.channel);

    // Re-register all consumers
    for (const bootstrap of this.consumerBootstraps) {
      await bootstrap(this.channel);
    }
  }

  // Fix listener leak — remove old before adding new
  private setupConnectionHandlers() {
    this.connection.removeAllListeners('close');
    this.connection.removeAllListeners('error');
    this.connection.on('close', () => this.scheduleReconnect());
    this.connection.on('error', (err) => this.logger.error({ err }));
  }
}
```

`mipit-core/src/index.ts`:

```ts
reconnector.registerConsumerBootstrap(async (ch) => {
  await ackConsumer.bind(ch);
});
reconnector.registerConsumerBootstrap(async (ch) => {
  await dlqHandler.bind(ch);
});
reconnector.registerConsumerBootstrap(async (ch) => {
  outboxPublisher.bindChannel(ch);
});
```

- [ ] Refactor reconnect.ts con `consumerBootstraps`
- [ ] AckConsumer y DlqHandler reciben `bind(channel)` en vez de constructor
- [ ] Listener leak: `removeAllListeners` antes de attach

### 5.5 Idempotency consolidation

**Borrar** `mipit-core/src/api/middleware/idempotency.ts` (el middleware que nunca se registra).

**Mantener** la lógica en `mipit-core/src/api/routes/payments.ts:26-77` pero corregir:

```ts
// 1. Insert idempotency claim WITH expires_at
const TTL_HOURS = 24;
const result = await idempotencyRepo.tryInsert(idempotencyKey, paymentId, requestHash, TTL_HOURS);

if (!result.inserted) {
  const existing = result.existing!;

  // 2. Validate hash matches (RFC 8941)
  if (existing.request_hash !== requestHash) {
    return reply.code(409).send({
      type: 'https://mipit.dev/errors/idempotency-conflict',
      title: 'Idempotency-Key reused with different request body',
      status: 409,
      detail: 'The provided Idempotency-Key was used previously with a different request body.'
    });
  }

  // 3. If response is cached, replay
  if (existing.response_status !== null) {
    return reply.code(existing.response_status).send(existing.response_body);
  }

  // 4. In-flight — return 409 Retry-After
  return reply.code(409).header('Retry-After', '2').send({
    type: 'https://mipit.dev/errors/idempotency-in-flight',
    title: 'Concurrent request with same Idempotency-Key',
    status: 409,
    detail: 'A request with this Idempotency-Key is being processed. Retry after 2 seconds.'
  });
}
```

`idempotency.repository.ts`:

```ts
async tryInsert(key: string, paymentId: string, requestHash: string, ttlHours: number): Promise<{ inserted: boolean; existing?: IdempotencyRecord }> {
  const expiresAt = new Date(Date.now() + ttlHours * 3600 * 1000);
  const { rows } = await this.db.query(`
    INSERT INTO idempotency_keys (idempotency_key, payment_id, request_hash, expires_at)
    VALUES ($1, $2, $3, $4)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING idempotency_key
  `, [key, paymentId, requestHash, expiresAt]);

  if (rows.length > 0) return { inserted: true };

  // Conflict: load existing
  const { rows: existing } = await this.db.query(
    `SELECT * FROM idempotency_keys WHERE idempotency_key = $1`, [key]
  );
  return { inserted: false, existing: existing[0] };
}
```

- [ ] Borrar middleware dead-code
- [ ] Fix `tryInsert` para escribir `expires_at`
- [ ] Implementar Retry-After on conflict
- [ ] Implementar RFC 7807 Problem Details shape
- [ ] Background sweeper: `DELETE FROM idempotency_keys WHERE expires_at < NOW()` cada 1h

### 5.6 Wire circuit breaker around adapter HTTP calls

`mipit-core/src/resilience/circuit-breaker.ts` está bien implementado. Cablearlo:

```ts
// mipit-core/src/index.ts
const railBreakers = {
  pix: new CircuitBreaker('pix-adapter', { failureThreshold: 5, ... }),
  spei: new CircuitBreaker('spei-adapter', { failureThreshold: 5, ... }),
  breb: new CircuitBreaker('breb-adapter', { failureThreshold: 5, ... }),
};

// In ui-proxy.ts (admin to mocks) and any place that calls adapter HTTP:
const result = await railBreakers[rail].execute(() => fetch(adapterUrl));
```

- [ ] Identificar puntos donde core llama HTTP a adapter (admin endpoints, health check)
- [ ] Envolver en breaker
- [ ] Métricas `/analytics/circuit-breakers` ya existen

### 5.7 Wire rate limiter to actual rate-limited operations

Rate-limiter actual está per-rail, in-memory. Decisión: **dejarlo como observability-only** (lo que es hoy) con un comment explícito, **O** cablearlo a las llamadas adapter HTTP.

Recomendación: **Cablearlo defensivamente**. En el pipeline antes de publish:

```ts
const tokens = await rateLimiter.acquire(destination_rail, 1);
if (!tokens.acquired) {
  throw new RateLimitedError(`Rail ${destination_rail} rate limit exceeded, retry in ${tokens.retryAfterMs}ms`);
}
```

- [ ] Cablear en pipeline step `route`
- [ ] El error se convierte en HTTP 429 con `Retry-After`

### 5.8 Compensation real (pacs.004 reverso)

`mipit-core/src/compensation/compensation-service.ts`. Refactor:

```ts
async compensate(paymentId: string, reason: string): Promise<void> {
  const payment = await this.paymentRepo.findById(paymentId);
  if (!payment) throw new Error(`Payment not found: ${paymentId}`);
  if (!['QUEUED','COMPLETED','DEAD_LETTER','FAILED'].includes(payment.status)) {
    throw new Error(`Cannot compensate from status ${payment.status}`);
  }

  // Build pacs.004 PaymentReturn
  const pacs004 = {
    grpHdr: {
      msgId: `RTN-${ulid()}`,
      creDtTm: new Date().toISOString(),
    },
    orgnlGrpInfAndSts: {
      orgnlMsgId: payment.canonical_payload.grpHdr.msgId,
      orgnlMsgNmId: 'pacs.008.001.10',
      orgnlCreDtTm: payment.canonical_payload.grpHdr.creDtTm,
    },
    txInf: {
      rtrId: `R${payment.uetr.replace(/-/g, '').slice(0, 24)}`,
      orgnlInstrId: payment.canonical_payload.pmtId.instrId,
      orgnlEndToEndId: payment.canonical_payload.pmtId.endToEndId,
      orgnlUetr: payment.uetr,
      orgnlTxId: payment.canonical_payload.pmtId.txId,
      rtrdIntrBkSttlmAmt: { Ccy: payment.canonical_payload.amount.currency, value: payment.canonical_payload.amount.value },
      chrgBr: payment.canonical_payload.chrgBr,
      rtrChain: { /* ... */ },
      rtrRsnInf: { rsn: { cd: this.mapReasonCode(reason) } }
    }
  };

  await this.paymentRepo.updateStatus(paymentId, 'COMPENSATING');
  await this.auditRepo.insert({ payment_id: paymentId, event_type: 'COMPENSATION_STARTED', detail: { reason, pacs004 }});

  // Publish to compensation queue (adapters consume and reverse)
  await this.outboxRepo.enqueue({
    payment_id: paymentId,
    exchange: EXCHANGES.PAYMENTS,
    routing_key: `compensate.${payment.destination_rail.toLowerCase()}`,
    payload: pacs004,
    headers: { 'mipit-uetr': payment.uetr }
  });

  await this.paymentRepo.updateStatus(paymentId, 'COMPENSATED');
  await this.auditRepo.insert({ payment_id: paymentId, event_type: 'COMPENSATION_COMPLETED', detail: {}});
}

private mapReasonCode(reason: string): string {
  // ISO ExternalReturnReason1Code: AC04 (closed account), AM04 (insufficient funds), NARR (narrative), ...
  const map: Record<string, string> = {
    'duplicate': 'AM05',
    'fraud': 'FOCR',
    'insufficient_funds': 'AM04',
    'closed_account': 'AC04',
    'invalid_account': 'AC03',
  };
  return map[reason] ?? 'NARR';
}
```

- [ ] Implementar
- [ ] Crear nuevas queue bindings: `compensate.{pix,spei,breb}` en `mipit-infra/rabbitmq/definitions.json`
- [ ] Adapters (futuro) implementan compensation handlers — para PoC, dejar comment `// TODO: adapter compensation handler stub` y solo persist el pacs.004 en `payments.compensation_payload` JSONB

### 5.9 Add DLX to `payments.ack`

`mipit-infra/rabbitmq/definitions.json`:

```json
{
  "name": "payments.ack",
  "vhost": "mipit",
  "durable": true,
  "auto_delete": false,
  "arguments": {
    "x-dead-letter-exchange": "mipit.dlx",
    "x-dead-letter-routing-key": "dlq.ack"
  }
}
```

Y agregar binding + queue `dlq.ack`.

### 5.10 Fix `consumer.ts:88` hardcoded destination_rail

`mipit-core/src/messaging/consumer.ts`:

```ts
// ANTES
recordPayment(finalStatus, ack.source_rail, ack.source_rail === 'PIX' ? 'SPEI' : 'PIX');

// DESPUÉS — read from payment row
const payment = await this.paymentRepo.findById(ack.payment_id);
recordPayment(finalStatus, payment.origin_rail, payment.destination_rail);
```

- [ ] Refactor

### 5.11 Reconciliation overlap guard + persistence

```ts
private running = false;

async runReconciliation() {
  if (this.running) {
    this.logger.warn('Reconciliation already running, skipping');
    return;
  }
  this.running = true;
  try {
    const report = await this.detectAnomalies();
    await this.reconReportRepo.persist(report); // new table
    if (report.anomalies > 0) {
      await this.webhookService.fireReconciliationReport(report);
    }
  } finally {
    this.running = false;
  }
}
```

- [ ] Crear tabla `reconciliation_reports`
- [ ] Persist + webhook fire-out

### 5.12 Routing tie-breaker

`mipit-core/src/persistence/queries/index.ts:76-77`:

```sql
-- ANTES
SELECT * FROM route_rules WHERE is_active = TRUE ORDER BY priority ASC

-- DESPUÉS
SELECT * FROM route_rules WHERE is_active = TRUE ORDER BY priority ASC, id ASC
```

- [ ] Update query
- [ ] Add UNIQUE partial index: `CREATE UNIQUE INDEX route_rules_unique_priority ON route_rules(priority) WHERE is_active = TRUE` — opcional, prevenir duplicados

---

## 6. Acceptance criteria

- [ ] Pipeline en single DB transaction (BEGIN/COMMIT/ROLLBACK)
- [ ] Outbox table existe; messages se persisten antes de publish
- [ ] OutboxPublisher daemon corre y flushea cada 250ms
- [ ] Publisher usa `createConfirmChannel`; `publish` await confirms
- [ ] Reconnect handler re-registra consumers tras blip — test verificable matando RabbitMQ container
- [ ] Listener count on connection stays <= 2 after 100 reconnects
- [ ] Idempotency middleware dead-code eliminado
- [ ] `tryInsert` escribe `expires_at`
- [ ] Sweeper job borra keys expirados
- [ ] In-flight idempotent request retorna 409 + Retry-After (RFC 7807)
- [ ] Circuit breaker wraps adapter HTTP calls
- [ ] Rate limiter is consulted in pipeline (no longer pure observability)
- [ ] `compensation-service.compensate` produces pacs.004 con `RtrId, RtrRsnInf, OrgnlUETR`
- [ ] `consumer.ts:88` reads destination_rail from DB, no hardcoded
- [ ] Reconciliation has overlap guard, persists reports
- [ ] `payments.ack` queue has DLX
- [ ] Routing rules ORDER BY priority, id
- [ ] Tests E2E broker-down recovery: kill `mipit-rabbitmq` container, restart, verify no message loss
- [ ] Test: 10 concurrent POSTs same idempotency key → 1 success, 9 receive cached or 409

---

## 7. Testing plan

### Unit
- `pipeline/transactional.test.ts` — verify ROLLBACK on error
- `outbox/outbox-publisher.test.ts` — flushing, retries
- `publisher/confirm-channel.test.ts` — confirms received
- `resilience/reconnect-consumers.test.ts` — re-bind verified

### Integration
- `idempotency-rfc-7807.test.ts` — 409 con shape Problem Details
- `compensation-pacs004.test.ts` — pacs.004 shape correcto
- `reconciliation-overlap.test.ts` — segundo run skip-ea

### E2E
- `e2e-resilience-broker-kill.mjs` — kill broker mid-flow, verify outbox flush on reconnect
- `e2e-idempotency-100-concurrent.mjs` — 100 POSTs same key, 1 win

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Outbox introduce latency (250ms poll) | Trigger flush() on every commit; poll is fallback |
| Transactional pipeline rompe tests existentes | Migrar test fixtures progresivamente |
| Confirm channel ralentiza publish | Acceptable trade-off vs message loss; batch publishes if needed |
| Compensation pacs.004 sin adapter handler real | Marcar como TODO P15; mensaje queda en queue para futura impl |

---

## 9. Commits sugeridos

1. `feat(infra): outbox table + outbox-publisher daemon`
2. `refactor(pipeline): single DB transaction + outbox enqueue`
3. `fix(publisher): use confirmChannel + await publisher confirms`
4. `fix(reconnect): re-register consumers on reconnect; remove listener leak`
5. `refactor(idempotency): consolidate to route handler; fix TTL bug`
6. `feat(idempotency): RFC 7807 Problem Details + 409 Retry-After`
7. `feat(idempotency): background sweeper for expired keys`
8. `feat(resilience): wire circuit breaker around adapter HTTP`
9. `feat(resilience): wire rate limiter in pipeline route step`
10. `feat(compensation): emit pacs.004 PaymentReturn with RtrId/RtrRsnInf/OrgnlUETR`
11. `fix(consumer): read destination_rail from DB, not hardcoded inverse`
12. `feat(reconciliation): overlap guard + report persistence + webhook`
13. `fix(infra): add DLX to payments.ack queue`
14. `fix(routing): ORDER BY priority, id for deterministic tie-breaking`

---

## 10. Notas para el dev

- **Outbox pattern**: la clave es que el INSERT INTO outbox y el UPDATE payments están en la **misma DB transaction**. Si la commit falla, ninguno persiste. Si commit OK, OutboxPublisher eventualmente lee y publica al broker (con confirms).
- **Confirm channel**: ojo a la perf — `await ch.publish` se vuelve sequential. Para alto throughput, batch publish con `waitForConfirms()` en grupos. Para PoC, sequential está bien.
- **Reconnect re-attach**: este es un patrón fácil de equivocar. Hacer un test integration con un script `docker stop mipit-rabbitmq; sleep 5; docker start mipit-rabbitmq` y verificar que no hay mensajes perdidos.
- **Compensation handler en adapters**: marcado como TODO P15. Por ahora el core emite el pacs.004 en queue; adapters lo ignoran (no consumen `compensate.*` keys). Esto cierra el claim "compensation is real" porque el mensaje **existe** en queue inspectable, aunque no se ejecute.
