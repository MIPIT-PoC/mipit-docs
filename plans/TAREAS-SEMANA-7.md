# Tareas Semana 7 — Mensajería RabbitMQ y Pipeline

**Branch:** `Nicolas_07`
**Depende de:** Semana 6 (translator, normalizer, route engine) ✅ Completada
**Objetivo:** Completar y verificar la mensajería RabbitMQ, el pipeline de 7 pasos y el consumer de ACK. Al finalizar, un pago puede fluir desde la recepción hasta la publicación en la cola del adaptador correcto, y el ACK del adaptador cierra el ciclo.

---

## Estado actual del código

Los archivos de Semana 7 ya existen como **skeleton** del scaffolding inicial. El trabajo consiste en **completar, corregir y verificar** las implementaciones, no en crearlas desde cero.

### Archivos existentes y su estado

| Archivo | Ticket | Estado actual | Qué falta |
|---|---|---|---|
| `src/messaging/rabbitmq.ts` | CORE-025 (Carlos) | Funcional básico | Faltan queues de route (`payments.route.pix`, `payments.route.spei`) |
| `src/messaging/publisher.ts` | CORE-026 (Carlos) | Funcional básico | Faltan `trace_id` y `payment_id` en AMQP headers |
| `src/audit/audit-service.ts` | CORE-027 (Carlos) | Completo | Verificar que métodos coincidan con `AuditRepository` |
| `src/pipeline/payment-pipeline.ts` | CORE-028 (Nicolas) | Flujo básico | Falta try/catch, métricas por stage, step VALIDATED |
| `src/messaging/consumer.ts` | CORE-029 (Nicolas) | Flujo básico | Falta logger, error handling/nack, métricas |
| `test/integration/pipeline.test.ts` | CORE-030 (Nicolas) | Solo `.todo()` stubs | Implementar todos los tests |
| `test/integration/messaging.test.ts` | — | Solo `.todo()` stubs | Implementar todos los tests |

### Issue transversal: SQL query names

`src/persistence/queries/index.ts` usa nombres que **no coinciden** con lo que esperan los repositorios:

| Repository usa | queries/index.ts tiene | Acción |
|---|---|---|
| `SQL.INSERT_AUDIT` | `SQL.INSERT_AUDIT_EVENT` | Alinear nombre |
| `SQL.FIND_AUDITS_BY_PAYMENT` | `SQL.FIND_AUDIT_BY_PAYMENT_ID` | Alinear nombre |
| `SQL.UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS` | `SQL.UPDATE_PAYMENT_STATUS` | Agregar query con timestamps |
| `SQL.UPDATE_PAYMENT_CANONICAL_PAYLOAD` | `SQL.UPDATE_CANONICAL` | Alinear nombre |
| `SQL.UPDATE_PAYMENT_ROUTE` | `SQL.UPDATE_ROUTE` | Alinear nombre |
| `SQL.UPDATE_PAYMENT_TRANSLATED_PAYLOAD` | `SQL.UPDATE_TRANSLATED` | Alinear nombre |
| `SQL.UPDATE_RAIL_ACK` | `SQL.UPDATE_ACK` | Alinear nombre |

**Esto debe resolverse ANTES de implementar los tests**, ya que las compilación TypeScript falla.

---

## Tickets de Nicolas (Branch `Nicolas_07`)

### CORE-028 — Completar `pipeline/payment-pipeline.ts` (P0)

**Qué existe:** Clase `PaymentPipeline` con método `execute()` que implementa los 7 pasos del flujo (inferir rail, persistir, traducir, normalizar, rutear, traducir a destino, publicar).

**Qué falta:**
1. **Error handling**: Envolver todo el flujo en try/catch. En caso de error: actualizar status a FAILED, registrar audit event de error, re-throw.
2. **Métricas**: Instrumentar con `mipit_payment_latency_ms` histogram por stage (`translation_to_canonical`, `normalization`, `routing`, `translation_from_canonical`, `total`).
3. **Step VALIDATED**: Después de persistir (RECEIVED), validar el payload explícitamente y actualizar a VALIDATED antes de traducir.
4. **Logging**: Agregar logs en cada paso del pipeline con child logger.

**Impacto:** Es el corazón del middleware. Sin este paso completo no hay flujo de pagos.

---

### CORE-029 — Completar `messaging/consumer.ts` (ACK) (P0)

**Qué existe:** Clase `AckConsumer` con `start()` que consume de `payments.ack`, parsea el mensaje, mapea status (ACCEPTED→COMPLETED, REJECTED→REJECTED, ERROR→FAILED), actualiza pago en DB, log audit, channel.ack.

**Qué falta:**
1. **Logger**: Importar y usar logger para cada ACK procesado.
2. **Error handling**: try/catch dentro del callback de consume. Si falla el procesamiento: log error, nack con `requeue: false` para evitar loop infinito.
3. **Métricas**: Registrar `mipit_payments_total` con label `status` por cada ACK procesado.
4. **Validación**: Validar estructura del mensaje ACK antes de procesarlo (Zod schema o check manual).

**Impacto:** Cierra el ciclo del pago — sin esto los pagos quedan en QUEUED permanentemente.

---

### CORE-030 — Integration test: pipeline → DB (P2)

**Qué existe:** Archivo `test/integration/pipeline.test.ts` con 7 tests `.todo()`. Archivo `test/integration/messaging.test.ts` con 8 tests `.todo()`.

**Qué falta:**
1. **Implementar todos los tests** con mocks de RabbitMQ (publisher mock), mocks de DB (payment repo, audit repo), y las dependencias reales de translator, normalizer y route engine.
2. **Tests pipeline**: Ejecutar `process()` con payload PIX válido, verificar cada status intermedio, verificar audit events, verificar error handling.
3. **Tests messaging**: Verificar publisher routing key, consumer status mapping, consumer error handling.

**Impacto:** Primer test de integración real — valida que todo el core funciona coordinado.

---

## Tickets de Carlos (Branch `Carlos_07`)

> **Nota:** Si Carlos no puede trabajar esta semana, Nicolas debe cubrir estos tickets también (como en Semana 6).

### CORE-025 — Completar `messaging/rabbitmq.ts` (P0)

**Qué existe:** `connectRabbitMQ()` que conecta, crea channel, assert exchange `mipit.payments` (topic), assert queue `payments.ack`, bind ACK queue.

**Qué falta:**
1. Assert queues de route: `payments.route.pix` y `payments.route.spei` (las que consumen los adapters).
2. Bind route queues: `payments.route.pix` → `route.pix`, `payments.route.spei` → `route.spei`.
3. Manejo de reconexión o al menos logging de eventos de conexión (`connection.on('error')`, `connection.on('close')`).
4. Export de `closeRabbitMQ()` para graceful shutdown.

---

### CORE-026 — Completar `messaging/publisher.ts` (P0)

**Qué existe:** `Publisher` con `publishToAdapter()` que selecciona routing key y publica con `persistent: true`.

**Qué falta:**
1. Headers AMQP con `trace_id` y `payment_id` (además de tenerlos en el body).
2. Métricas: contar mensajes publicados con `mipit_payments_total` label `stage=queued`.

---

### CORE-027 — Verificar `audit/audit-service.ts` (P1)

**Qué existe:** `AuditService` completo con métodos `log`, `logStatusChange`, `logRoutingDecision`, `logError`, `logAckReceived`.

**Qué falta:**
1. Verificar que funcione correctamente con las queries SQL corregidas (issue transversal).
2. Verificar que los event types coincidan con los usados en payment-pipeline.ts.

---

## Issue transversal: Corregir SQL queries (PREREQUISITO)

Antes de cualquier ticket, se deben alinear los nombres de queries en `src/persistence/queries/index.ts` con los que usan `payment.repository.ts` y `audit.repository.ts`. Esto resuelve los errores de compilación TypeScript que existen desde Semana 5.

---

## Orden de ejecución recomendado

| Paso | Ticket | Descripción | Dependencia |
|---|---|---|---|
| 0 | — | Crear branch `Nicolas_07` desde `master` | — |
| 1 | — | **Fix SQL query names** (issue transversal) | — |
| 2 | CORE-025 | Completar `rabbitmq.ts` (route queues + shutdown) | — |
| 3 | CORE-026 | Completar `publisher.ts` (headers + métricas) | CORE-025 |
| 4 | CORE-027 | Verificar `audit-service.ts` | Fix SQL |
| 5 | CORE-028 | Completar `payment-pipeline.ts` (error handling + métricas) | CORE-026, CORE-027 |
| 6 | CORE-029 | Completar `consumer.ts` (logger + error handling) | CORE-025, CORE-027 |
| 7 | CORE-030 | Implementar integration tests | CORE-028, CORE-029 |
| 8 | — | Documentar unit tests en `test_7.md` | Todo lo anterior |

---

## Criterio de merge Semana 7

- [ ] `connectRabbitMQ()` establece conexión y crea topología completa (exchange + 3 queues + bindings)
- [ ] `publisher.publish('PIX', canonical)` publica mensaje en `payments.route.pix` con headers
- [ ] `pipeline.execute(pixRequest)` ejecuta 7 pasos y el pago queda en status QUEUED
- [ ] Error en pipeline → status FAILED + audit event
- [ ] ACK consumer procesa mensaje ACCEPTED → pago COMPLETED
- [ ] ACK consumer procesa mensaje REJECTED → pago REJECTED
- [ ] ACK consumer error handling: nack sin requeue
- [ ] Audit events registrados para cada paso del pipeline
- [ ] Integration tests pasan (pipeline + messaging)
- [ ] Unit tests documentados en `test_7.md` y ejecutados
- [ ] `npx tsc --noEmit` compila sin errores

---

*Documento generado a partir de `PLAN-DE-DESARROLLO.md`, Semana 7.*
