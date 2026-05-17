# CORE-029 — Completar `messaging/consumer.ts` (ACK Consumer)

**Prioridad:** P0
**Asignado a:** Nicolas
**Archivo:** `src/messaging/consumer.ts`
**Depende de:** CORE-025 (rabbitmq), CORE-027 (audit-service)

---

## Paso 1 — Verificar branch `Nicolas_07`

- [ ] `git branch` muestra `* Nicolas_07`
- [ ] Si no existe: `git checkout -b Nicolas_07` desde `master`

---

## Paso 2 — Analizar estado actual

El archivo existe con flujo básico: consume de `payments.ack`, parsea mensaje, mapea status, actualiza pago, log audit, channel.ack. Falta:

1. **Logger**: No importa ni usa logger — solo hace operaciones silenciosas
2. **Error handling**: No hay try/catch — si falla `updateAck` o `auditService.log`, el mensaje nunca se ack/nack
3. **Métricas**: No registra métricas de ACKs procesados
4. **Validación del mensaje**: No valida que el mensaje tenga la estructura esperada

---

## Paso 3 — Implementar mejoras

### 3.1 — Importar logger y métricas

```typescript
import { logger } from '../observability/logger.js';
import { recordPayment } from '../observability/metrics.js';
```

### 3.2 — Agregar try/catch con nack

```typescript
async start() {
  logger.info('AckConsumer started, listening on queue: payments.ack');

  await this.channel.consume(QUEUES.ACK, async (msg) => {
    if (!msg) return;

    let ack: PaymentAckMessage;
    try {
      ack = JSON.parse(msg.content.toString());
    } catch (parseErr) {
      logger.error({ err: parseErr }, 'Failed to parse ACK message');
      this.channel.nack(msg, false, false); // no requeue mensajes corruptos
      return;
    }

    const log = logger.child({ payment_id: ack.payment_id, source_rail: ack.source_rail });

    try {
      // ... mapeo de status (existente) ...

      await this.paymentRepo.updateAck(ack.payment_id, ack.rail_ack, finalStatus);
      log.info({ final_status: finalStatus, latency_ms: ack.latency_ms }, 'Payment status updated from ACK');

      // ... audit log (existente) ...

      // Métricas
      recordPayment(finalStatus);

      this.channel.ack(msg);
      log.info('ACK message processed successfully');
    } catch (err) {
      log.error({ err }, 'Failed to process ACK message');
      this.channel.nack(msg, false, false);
    }
  });
}
```

### 3.3 — Validación básica del mensaje

Antes de procesar, verificar campos requeridos:

```typescript
if (!ack.payment_id || !ack.rail_ack?.status) {
  log.warn({ raw: msg.content.toString() }, 'Invalid ACK message structure');
  this.channel.nack(msg, false, false);
  return;
}
```

---

## Paso 4 — Verificar compilación

- [ ] `npx tsc --noEmit` — sin errores
- [ ] Verificar que `recordPayment` existe en `metrics.ts` (o crear helper)

---

## Paso 5 — Documentar tests en `test_7.md`

- [ ] Abrir `mipit-core/test_7.md`
- [ ] Agregar sección:

```markdown
## CORE-029 — Unit tests AckConsumer

### Archivo: `test/unit/messaging/consumer.test.ts`

**Mocks necesarios:**
- `Channel` (consume callback, ack, nack)
- `PaymentRepository` (updateAck)
- `AuditService` (log)
- `Logger` (child → info, error, warn)

**Tests recomendados (mínimo 7):**

1. `start() registra consumer en queue payments.ack`
2. `procesa ACK con status ACCEPTED → paymentRepo.updateAck con COMPLETED`
3. `procesa ACK con status REJECTED → paymentRepo.updateAck con REJECTED`
4. `procesa ACK con status ERROR → paymentRepo.updateAck con FAILED`
5. `registra audit event con datos correctos (adapter_id, latency_ms, etc.)`
6. `llama channel.ack(msg) después de procesar exitosamente`
7. `mensaje con JSON inválido → nack sin requeue`
8. `error en paymentRepo.updateAck → nack sin requeue`
9. `mensaje sin payment_id → nack sin requeue (validación)`
10. `msg null → return sin procesar (RabbitMQ consumer cancel)`
```

---

## Paso 6 — Commit

```bash
git add src/messaging/consumer.ts
git commit -m "feat(consumer): agregar logger, error handling con nack y validación de mensajes ACK"
```
