# CORE-030 — Integration test: pipeline → DB

**Prioridad:** P2
**Asignado a:** Nicolas
**Archivos:** `test/integration/pipeline.test.ts`, `test/integration/messaging.test.ts`
**Depende de:** CORE-028 (pipeline), CORE-029 (consumer)

---

## Paso 1 — Verificar branch `Nicolas_07`

- [ ] `git branch` muestra `* Nicolas_07`

---

## Paso 2 — Analizar estado actual

Ambos archivos de test existen con solo stubs `.todo()`:
- `test/integration/pipeline.test.ts` — 7 tests todo
- `test/integration/messaging.test.ts` — 8 tests todo

---

## Paso 3 — Implementar `test/integration/pipeline.test.ts`

### Estrategia de mocking

- **Publisher**: Mock completo (no queremos RabbitMQ real en tests)
- **PaymentRepository**: Mock que simula DB en memoria (Map)
- **AuditService**: Mock que registra llamadas
- **Translator**: Instancia REAL (usa las funciones de traducción de S6)
- **Normalizer**: Instancia REAL (usa las reglas de normalización de S6)
- **RouteEngine**: Mock con reglas predefinidas (no queremos DB real)
- **Logger**: Mock de Pino (child → log functions)

### Tests a implementar

```typescript
describe('PaymentPipeline (integration)', () => {
  // Setup: crear mocks, instanciar pipeline

  it('should execute the full 7-step pipeline for a PIX→SPEI payment', async () => {
    // Given: payload con alias PIX-xxx, creditor SPEI-xxx
    // When: pipeline.execute(request, { traceId: 'test-trace' })
    // Then: retorna { payment_id, status: 'RECEIVED', destination_rail: 'SPEI' }
  });

  it('should execute the full 7-step pipeline for a SPEI→PIX payment', async () => {
    // Given: payload con alias SPEI-xxx, creditor PIX-xxx
    // When: pipeline.execute(request, {})
    // Then: retorna { destination_rail: 'PIX' }
  });

  it('should persist payment with RECEIVED status on step 2', async () => {
    // Verificar: paymentRepo.create fue llamado con status RECEIVED
  });

  it('should update canonical payload after translation (step 4)', async () => {
    // Verificar: paymentRepo.updateCanonical fue llamado con CanonicalPacs008
  });

  it('should update route and destination after routing (step 6)', async () => {
    // Verificar: paymentRepo.updateRoute fue llamado con destination y ruleName
  });

  it('should publish message to RabbitMQ and set QUEUED status (step 7)', async () => {
    // Verificar: publisher.publishToAdapter llamado
    // Verificar: paymentRepo.updateStatus llamado con QUEUED
  });

  it('should throw on unknown rail alias prefix', async () => {
    // Given: alias 'UNKNOWN-xxx'
    // Then: throws Error 'Cannot infer rail'
  });

  it('should set status FAILED and log error when translator throws', async () => {
    // Given: translator.toCanonical throws TranslationError
    // Then: paymentRepo.updateStatus(FAILED)
    // Then: auditService.logError called
  });

  it('should register audit events for each pipeline step', async () => {
    // Verificar: auditService.log llamado mínimo 4 veces
    // Verificar: auditService.logRoutingDecision llamado 1 vez
  });
});
```

---

## Paso 4 — Implementar `test/integration/messaging.test.ts`

### Tests Publisher

```typescript
describe('Publisher', () => {
  it('should publish a message to the PIX routing key', async () => {
    // Given: mock channel
    // When: publisher.publishToAdapter('PIX', message)
    // Then: channel.publish llamado con routing key 'route.pix'
  });

  it('should publish a message to the SPEI routing key', async () => {
    // Similar con 'route.spei'
  });

  it('should set persistent and content-type headers', async () => {
    // Verificar: options incluye persistent: true, contentType: 'application/json'
  });
});
```

### Tests AckConsumer

```typescript
describe('AckConsumer', () => {
  // Helper: simular channel.consume invocando el callback con un msg fake

  it('should update payment to COMPLETED on ACCEPTED ack', async () => {
    // Given: ACK con rail_ack.status === 'ACCEPTED'
    // Then: paymentRepo.updateAck con status COMPLETED
  });

  it('should update payment to REJECTED on REJECTED ack', async () => {
    // Given: ACK con rail_ack.status === 'REJECTED'
    // Then: paymentRepo.updateAck con status REJECTED
  });

  it('should update payment to FAILED on ERROR ack', async () => {
    // Given: ACK con rail_ack.status === 'ERROR'
    // Then: paymentRepo.updateAck con status FAILED
  });

  it('should log audit event with adapter and latency metadata', async () => {
    // Verificar: auditService.log llamado con adapter_id, latency_ms
  });

  it('should acknowledge the message after processing', async () => {
    // Verificar: channel.ack(msg) llamado
  });
});
```

---

## Paso 5 — Ejecutar tests

- [ ] `npx jest test/integration/ --verbose`
- [ ] Todos los tests pasan (sin `.todo()` restantes)

---

## Paso 6 — Documentar tests en `test_7.md`

- [ ] Abrir `mipit-core/test_7.md`
- [ ] Agregar sección:

```markdown
## CORE-030 — Integration tests pipeline + messaging

### Archivos:
- `test/integration/pipeline.test.ts`
- `test/integration/messaging.test.ts`

**Tipo:** Integration (mocks parciales, componentes reales de S6)

**Cobertura:**
- Pipeline completo PIX→SPEI y SPEI→PIX
- Persistencia en cada step
- Audit trail completo
- Error handling (status FAILED)
- Publisher routing key correcta
- Consumer status mapping (ACCEPTED/REJECTED/ERROR)
- Consumer channel.ack después de procesar

**Total tests:** ~14 (9 pipeline + 5 messaging)
```

---

## Paso 7 — Commit

```bash
git add test/integration/pipeline.test.ts test/integration/messaging.test.ts
git commit -m "test(integration): implementar tests de pipeline y messaging — 14 tests"
```
