# CORE-028 — Completar `pipeline/payment-pipeline.ts`

**Prioridad:** P0
**Asignado a:** Nicolas
**Archivo:** `src/pipeline/payment-pipeline.ts`
**Depende de:** FIX-SQL-QUERIES, CORE-025, CORE-026, CORE-027

---

## Paso 1 — Verificar branch `Nicolas_07`

- [ ] `git branch` muestra `* Nicolas_07`
- [ ] Si no existe: `git checkout -b Nicolas_07` desde `master`

---

## Paso 2 — Analizar estado actual

El archivo existe con un flujo básico de 7 pasos. Falta:

1. **try/catch con manejo de errores**: Si cualquier paso falla → status FAILED + audit event + re-throw
2. **Métricas por stage**: `mipit_payment_latency_ms` histogram con labels por stage
3. **Step VALIDATED**: Después de persistir con RECEIVED, validar el payload y actualizar a VALIDATED
4. **Logging por paso**: Child logger con `payment_id` y `trace_id`

---

## Paso 3 — Implementar mejoras

### 3.1 — Agregar step VALIDATED

Después de `paymentRepo.create()` y antes de `translator.toCanonical()`:
- Validar `request` con el schema Zod (`createPaymentSchema.parse()`)
- `paymentRepo.updateStatus(paymentId, PAYMENT_STATUS.VALIDATED)`
- Audit: `log(paymentId, 'PAYMENT_VALIDATED', 'system-validator', { ... }, traceId)`

### 3.2 — Envolver en try/catch

```typescript
async execute(request, context) {
  const paymentId = `PMT-${ulid()}`;
  // ... setup ...

  try {
    // Step 1-7 ...
    return result;
  } catch (err) {
    await this.paymentRepo.updateStatus(paymentId, PAYMENT_STATUS.FAILED);
    await this.auditService.logError(
      paymentId, 'PIPELINE_ERROR', err instanceof Error ? err : new Error(String(err)),
      'system-pipeline', traceId,
    );
    this.logger.error({ payment_id: paymentId, err }, 'Pipeline failed');
    throw err;
  }
}
```

### 3.3 — Métricas por stage

Importar `startLatencyTimer` de `observability/metrics.ts`. Medir cada stage:

```typescript
const stopTotal = startLatencyTimer('pipeline_total');
// ... step 3 ...
const stopTranslation = startLatencyTimer('pipeline_to_canonical');
const canonical = await this.translator.toCanonical(...);
stopTranslation();
// ... etc para cada step ...
stopTotal();
```

### 3.4 — Logging con child logger

```typescript
const log = this.logger.child({ payment_id: paymentId, trace_id: traceId });
log.info({ origin_rail: originRail }, 'Step 1: Rail inferred');
// ... en cada paso ...
```

---

## Paso 4 — Verificar compilación

- [ ] `npx tsc --noEmit` — sin errores
- [ ] Revisar que los imports de métricas están correctos

---

## Paso 5 — Documentar tests en `test_7.md`

- [ ] Abrir/crear `mipit-core/test_7.md`
- [ ] Agregar sección:

```markdown
## CORE-028 — Unit tests PaymentPipeline

### Archivo: `test/unit/pipeline/payment-pipeline.test.ts`

**Mocks necesarios:**
- `Translator` (toCanonical, fromCanonical)
- `Normalizer` (normalize)
- `RouteEngine` (resolve)
- `Publisher` (publishToAdapter)
- `PaymentRepository` (create, updateCanonical, updateRoute, updateTranslated, updateStatus)
- `AuditService` (log, logRoutingDecision, logError)
- `Logger` (child → info, error, debug)

**Tests recomendados (mínimo 8):**

1. `execute() con PIX request válido → retorna payment_id y status RECEIVED`
2. `execute() infiere rail PIX para alias 'PIX-xxx'`
3. `execute() infiere rail SPEI para alias 'SPEI-xxx'`
4. `execute() lanza error para alias desconocido`
5. `execute() llama translator.toCanonical con rail y payload correctos`
6. `execute() llama normalizer.normalize con canonical`
7. `execute() llama routeEngine.resolve y publisher.publishToAdapter con destino correcto`
8. `execute() llama paymentRepo.updateStatus(QUEUED) al final`
9. `execute() registra audit events en cada paso (mínimo 4 calls a auditService)`
10. `execute() cuando translator falla → status FAILED + audit error + re-throw`
11. `execute() cuando routeEngine falla → status FAILED + audit error + re-throw`
```

---

## Paso 6 — Commit

```bash
git add src/pipeline/payment-pipeline.ts
git commit -m "feat(pipeline): completar payment-pipeline con error handling, métricas y step VALIDATED"
```
