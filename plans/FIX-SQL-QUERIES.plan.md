# FIX-SQL-QUERIES — Alinear nombres de queries SQL (Prerequisito S7)

**Prioridad:** P0 — Bloquea compilación TypeScript
**Archivo:** `src/persistence/queries/index.ts`
**Afecta:** `payment.repository.ts`, `audit.repository.ts`

---

## Paso 1 — Verificar que la branch `Nicolas_07` existe

- [ ] `git checkout master && git pull origin master`
- [ ] `git checkout -b Nicolas_07`
- [ ] Verificar: `git branch` muestra `* Nicolas_07`

---

## Paso 2 — Identificar todas las discrepancias

Comparar lo que usan los repositorios vs lo que exporta `queries/index.ts`:

### `payment.repository.ts` usa:
| Propiedad usada | Queries tiene | Match? |
|---|---|---|
| `SQL.INSERT_PAYMENT` | `SQL.INSERT_PAYMENT` | ✅ |
| `SQL.FIND_PAYMENT_BY_ID` | `SQL.FIND_PAYMENT_BY_ID` | ✅ |
| `SQL.UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS` | `SQL.UPDATE_PAYMENT_STATUS` | ❌ |
| `SQL.UPDATE_PAYMENT_CANONICAL_PAYLOAD` | `SQL.UPDATE_CANONICAL` | ❌ |
| `SQL.UPDATE_PAYMENT_ROUTE` | `SQL.UPDATE_ROUTE` | ❌ |
| `SQL.UPDATE_PAYMENT_TRANSLATED_PAYLOAD` | `SQL.UPDATE_TRANSLATED` | ❌ |
| `SQL.UPDATE_RAIL_ACK` | `SQL.UPDATE_ACK` | ❌ |

### `audit.repository.ts` usa:
| Propiedad usada | Queries tiene | Match? |
|---|---|---|
| `SQL.INSERT_AUDIT` | `SQL.INSERT_AUDIT_EVENT` | ❌ |
| `SQL.FIND_AUDITS_BY_PAYMENT` | `SQL.FIND_AUDIT_BY_PAYMENT_ID` | ❌ |

---

## Paso 3 — Corregir `queries/index.ts`

Opción elegida: **renombrar las propiedades en `queries/index.ts`** para que coincidan con los repositorios (los repos son los consumidores, es más natural que la fuente se adapte).

### Cambios concretos:

```typescript
export const SQL = {
  // Payments
  INSERT_PAYMENT: `...`,                            // sin cambio
  FIND_PAYMENT_BY_ID: `...`,                        // sin cambio

  // RENOMBRAR: UPDATE_PAYMENT_STATUS → UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS
  UPDATE_PAYMENT_STATUS_WITH_MILESTONE_TIMESTAMPS: `
    UPDATE payments SET status = $1,
      validated_at   = CASE WHEN $1 = 'VALIDATED'           THEN NOW() ELSE validated_at END,
      queued_at      = CASE WHEN $1 = 'QUEUED'              THEN NOW() ELSE queued_at END,
      sent_at        = CASE WHEN $1 = 'SENT_TO_DESTINATION' THEN NOW() ELSE sent_at END,
      completed_at   = CASE WHEN $1 = 'COMPLETED'           THEN NOW() ELSE completed_at END,
      failed_at      = CASE WHEN $1 = 'FAILED'              THEN NOW() ELSE failed_at END
    WHERE payment_id = $2
    RETURNING *`,

  // RENOMBRAR: UPDATE_CANONICAL → UPDATE_PAYMENT_CANONICAL_PAYLOAD
  UPDATE_PAYMENT_CANONICAL_PAYLOAD: `
    UPDATE payments
    SET canonical_payload = $1::jsonb, status = $2, canonicalized_at = NOW()
    WHERE payment_id = $3
    RETURNING *`,

  // RENOMBRAR: UPDATE_ROUTE → UPDATE_PAYMENT_ROUTE
  UPDATE_PAYMENT_ROUTE: `
    UPDATE payments
    SET destination_rail = $1, route_rule_applied = $2, status = $3, routed_at = NOW()
    WHERE payment_id = $4
    RETURNING *`,

  // RENOMBRAR: UPDATE_TRANSLATED → UPDATE_PAYMENT_TRANSLATED_PAYLOAD
  UPDATE_PAYMENT_TRANSLATED_PAYLOAD: `
    UPDATE payments SET translated_payload = $1::jsonb
    WHERE payment_id = $2
    RETURNING *`,

  // RENOMBRAR: UPDATE_ACK → UPDATE_RAIL_ACK
  UPDATE_RAIL_ACK: `
    UPDATE payments
    SET rail_ack = $1::jsonb, status = $2, acked_at = NOW(),
        completed_at = CASE WHEN $2 = 'COMPLETED' THEN NOW() ELSE completed_at END
    WHERE payment_id = $3
    RETURNING *`,

  // Audit — RENOMBRAR
  INSERT_AUDIT: `
    INSERT INTO audit_events (id, payment_id, event_type, actor, detail, trace_id, created_at)
    VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7)`,

  FIND_AUDITS_BY_PAYMENT: `
    SELECT * FROM audit_events WHERE payment_id = $1 ORDER BY created_at ASC`,

  // Idempotency (sin cambios)
  FIND_IDEMPOTENCY_BY_KEY: `...`,
  INSERT_IDEMPOTENCY: `...`,
  UPDATE_IDEMPOTENCY_RESPONSE: `...`,

  // Route Rules (sin cambios)
  FIND_ACTIVE_ROUTE_RULES: `...`,
  FIND_ROUTE_RULE_BY_ID: `...`,

  // Mappings (sin cambios)
  FIND_MAPPINGS_BY_RAIL: `...`,
  FIND_ALL_MAPPINGS: `...`,
} as const;
```

**Notas importantes:**
- `INSERT_AUDIT` cambia la columna `stage` → `actor` y agrega `detail` como `$5::jsonb` para coincidir con lo que `audit.repository.ts` envía.
- Todas las UPDATE queries ahora incluyen `RETURNING *` para que los repos puedan retornar el objeto actualizado.
- Se agrega `::jsonb` cast explícito en campos JSON.

---

## Paso 4 — Verificar compilación

- [ ] `npx tsc --noEmit` — debe compilar sin errores en `payment.repository.ts` y `audit.repository.ts`

---

## Paso 5 — Verificar tests existentes

- [ ] `npx jest --passWithNoTests` — los tests existentes (S5 + S6) deben seguir pasando

---

## Paso 6 — Documentar tests en `test_7.md`

- [ ] Crear/abrir `mipit-core/test_7.md`
- [ ] Agregar sección para FIX-SQL-QUERIES:

```markdown
## FIX-SQL-QUERIES — Tests recomendados

No requiere tests unitarios propios. La corrección se verifica indirectamente a través de:
- Compilación TypeScript (`npx tsc --noEmit`)
- Tests existentes de repositorios (S5) que usan estos SQL queries
```

---

## Paso 7 — Commit

```bash
git add src/persistence/queries/index.ts
git commit -m "fix(queries): alinear nombres SQL con repositorios — resuelve errores TS"
```
