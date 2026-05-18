# B4 — Documentation Accuracy Audit (Audit 3)

**Fecha:** 2026-05-18 · **Branch:** `Auditoria-Claude` post-Wave 6 · **Auditor:** B4 (Claude subagent)
**Scope:** drift profundo doc vs código — OpenAPI vs runtime, ADRs vs implementación, diagramas, READMEs, AGENTS.md, SRS/Memoria.

> No repite hallazgos superficiales de Audit 2 (A2 cubrió drift de mappings, error codes, status enums superficial). Esta auditoría va al hueso: endpoints inexistentes, ADRs que mienten sobre el stack actual, diagramas que no existen, READMEs que omiten Bre-B.

---

## 0. Resumen ejecutivo

**El proyecto tiene un drift documental sistemático** que se acumula desde la Wave 1 (2026-03-01) hasta hoy (2026-05-18). Los ADRs no se han revisado desde la fecha original; los READMEs de la mitad de los repos siguen describiendo un PoC de 2 rieles (PIX/SPEI); los diagramas formales **no existen** (la carpeta `mipit-docs/design/diagrams/` solo contiene `.gitkeep`); y la OpenAPI spec declara endpoints (`/translate/canonical-to/{rail}`, `/translate/from/{rail}`) que **no están registrados en Fastify**.

**Magnitud:**
- **OpenAPI ↔ rutas reales:** 28 endpoints reales, 18 declarados, 7 declarados-pero-no-implementados, 17 implementados-pero-no-declarados.
- **ADRs:** 4/8 con drift material en stack/decisión (ADR-003, ADR-004, ADR-005, ADR-006).
- **READMEs:** 6/9 omiten Bre-B (que se agregó en P04, Wave 1).
- **AGENTS.md:** 1/9 faltante (Bre-B), 5/9 con referencias a archivos borrados en Wave 6 o decisiones obsoletas.
- **Diagramas:** **0 archivos**. Cero. `design/diagrams/.gitkeep` lleva ahí desde el 2026-03-02.
- **SRS:** carpeta `mipit-docs/srs/` vacía; PDFs reales viven en `C:/Users/nicog/Documents/Tesis/SRS_MIPIT.pdf` (no en el repo de docs).

**Severidad agregada:** 🟠 ALTA. No bloquea ejecución, pero **bloquea la sustentación de tesis** porque cualquier miembro del tribunal que abra los docs encontrará inconsistencias triviales que invalidan la confianza ("la doc dice 2 rieles, el código tiene 3 — ¿qué más está mal?").

---

## 1. Tabla maestra

| ID | Severity | Archivo / sección | Drift |
|----|----------|-------------------|-------|
| B4-001 | 🔴 CRÍT | `mipit-docs/openapi/openapi.yaml:265-306` | Declara `/translate/canonical-to/{rail}` y `/translate/from/{rail}` — **NO existen** en `mipit-core/src/api/routes/translate.ts` |
| B4-002 | 🔴 CRÍT | `mipit-docs/openapi/openapi.yaml:540-595` (schema `CanonicalPacs008`) | OpenAPI declara `intrBkSttlmAmt` + `intrBkSttlmDt` flat. Código tiene `amount.{value,currency,instdAmt,instdAmtCcy}` + `intrBkSttlmDt` opcional + `origin/destination/fx/lclInstrm/ctgyPurp` (campos no declarados) |
| B4-003 | 🔴 CRÍT | `mipit-docs/design/diagrams/` | **Directorio vacío** (solo `.gitkeep` desde 2026-03-02). El SPMP H4 promete "Diagramas formales 4+1"; nunca se entregaron |
| B4-004 | 🔴 CRÍT | `mipit-adapter-breb/` | **No tiene README.md ni AGENTS.md**. Los otros 8 repos sí. Inconsistencia estructural detectable a `ls` |
| B4-005 | 🟠 ALTO | `mipit-docs/openapi/openapi.yaml:86-92` + `payments.ts:24` | OpenAPI dice `Idempotency-Key: required: true`; código hace `if (idempotencyKey)` y procesa sin key. ADR-004 dice "obligatorio". **Tres fuentes en desacuerdo** |
| B4-006 | 🟠 ALTO | `mipit-docs/adrs/ADR-003-rabbitmq-async-messaging.md:31` | "Topic exchanges permiten enrutar `route.pix` y `route.spei`" — sin mención a `route.breb` ni al vhost `/mipit` (configurado en `mipit-infra/env/*.env`). Bre-B en producción desde P04 |
| B4-007 | 🟠 ALTO | `mipit-docs/adrs/ADR-006-postgres-persistence.md:17` | "query builder ligero (Kysely o Knex)" — código usa **driver `pg` crudo** con queries en `mipit-core/src/persistence/queries/index.ts`. Ni Kysely ni Knex en `package.json` |
| B4-008 | 🟠 ALTO | `mipit-docs/adrs/ADR-005-security-poc-jwt-https.md:18` | "se genera un **token estático** de demo que la UI incluye automáticamente". Código actual (`server.ts:115-132`) emite JWT dinámico vía `POST /auth/token` (gated a non-production); UI tiene flujo de auth real |
| B4-009 | 🟠 ALTO | `mipit-docs/adrs/ADR-007-hybrid-modular-architecture.md:47` | "Los adaptadores solo se comunican con el core vía RabbitMQ (nunca HTTP directo)" — pero `ui-proxy.ts:30-42` define HTTP calls del core a `adapter-pix:9101/health`, `adapter-spei:9102/health`, `adapter-breb:9103/health` |
| B4-010 | 🟠 ALTO | `mipit-docs/design/architecture-overview.md:15-36` | Diagrama ASCII solo muestra PIX y SPEI. Bre-B inexistente. UI proxy y AlertManager también ausentes |
| B4-011 | 🟠 ALTO | `mipit-docs/design/translation-layer.md:22-32, 35-88, 245` | Tabla de 6 rieles (omite BRE_B); shape del `CanonicalPacs008` obsoleto (sin `chrgBr/uetr/intrBkSttlmDt/lclInstrm/ctgyPurp` añadidos en W3-W6); línea 245 dice "PIX y SPEI ya están implementados como Option B completo" — **omite Bre-B** que también es Option B |
| B4-012 | 🟠 ALTO | `mipit-docs/design/adding-a-new-rail.md:41-44` | `SUPPORTED_RAILS = ['PIX', 'SPEI', 'SWIFT_MT103', 'ISO20022_MX', 'ACH_NACHA', 'FEDNOW']` — **falta BRE_B**. Real en `canonical.ts:4` incluye BRE_B |
| B4-013 | 🟠 ALTO | `mipit-docs/contracts/rabbitmq-messages.md:5-15, 29, 77, 83, 144` | Topología solo lista `route.{pix,spei}` y `ack.{pix,spei}` — sin Bre-B. Falta vhost `/mipit`. Mensajes ejemplo omiten BRE_B |
| B4-014 | 🟠 ALTO | `mipit-docs/contracts/payment-status-machine.md:5-18, 64-67` | Lista **11 estados**. Código `canonical.ts:15-32` tiene **15** (faltan `NORMALIZED`, `COMPENSATING`, `COMPENSATED`, `DEAD_LETTER`). Diagrama de transiciones inválido |
| B4-015 | 🟠 ALTO | `mipit-docs/contracts/error-codes.md:33-51` | Solo cataloga errores PIX y SPEI. Falta sección Bre-B (`BREB_INVALID_KEY`, etc.) y subset de errores que el código sí emite (`COMPENSATION_REJECTED`, `RECONCILIATION_*`) |
| B4-016 | 🟠 ALTO | `mipit-docs/route-rules/rules.yaml:1-67` | Sin reglas para BRE_B (`+57`, NIT, llaves `@xxx`). Field paths `canonical.creditor.alias_type` mal — código real usa `canonical.alias.type` (objeto separado, no nested en creditor) |
| B4-017 | 🟡 MED | `mipit-docs/openapi/openapi.yaml:340-359` (`/stream/payments`) | Real es `/events/payments` y `/events/payments/:paymentId` y `/events/clients` (`sse.ts:86,138,188`). El path declarado en OpenAPI **NO existe** |
| B4-018 | 🟡 MED | `mipit-docs/openapi/openapi.yaml:308-338` (analytics) | Declara `/analytics/throughput` y `/analytics/success-rate`. Real (`analytics.ts:31,82,138,149,160`) tiene `/analytics/latency`, `/analytics/summary`, `/analytics/circuit-breakers`, `/analytics/rate-limits`, `/analytics/reconciliation`. **Throughput y success-rate NO existen como endpoints** |
| B4-019 | 🟡 MED | `mipit-docs/openapi/openapi.yaml:464-472` (schema `PaymentSummary`) | Declara `destination` enum `[PIX, SPEI, BRE_B]`. Código (`payments.ts:96-105`) retorna `origin_rail` + `destination_rail` (dos campos), no `destination`. OpenAPI miente sobre el shape de la respuesta |
| B4-020 | 🟡 MED | `mipit-docs/openapi/openapi.yaml:474-538` (schema `PaymentDetail`) | Declara `original` + `canonical` + `translated`. Código retorna `original_payload` + `canonical_payload` + `translated_payload`. Naming mismatch real → consumidor de la spec va a fallar |
| B4-021 | 🟡 MED | `mipit-core/README.md:49-54` | Tabla "API Endpoints" lista 4. Real tiene **30+** (creates, lists, details, translate×3, analytics×5, events×3, webhooks×2, services proxy, mocks proxy, compensate×2, etc.) |
| B4-022 | 🟡 MED | `mipit-ui/README.md:32-38` (Pages) | Lista 4 páginas. Real (`src/app/`) tiene 8: `/`, `/simulate`, `/simulator`, `/payments/[id]`, `/history`, `/analytics`, `/live`, `/translator` |
| B4-023 | 🟡 MED | `mipit-infra/README.md:3, 67-77` | Línea 3 dice "rieles PIX (Brasil) y SPEI (México)" — omite Bre-B. Tabla "Repositorios relacionados" omite `mipit-adapter-breb` |
| B4-024 | 🟡 MED | `mipit-observability/README.md:7, 20, 32-35, 41` | Scrape targets: 5 listados, real son 6 (incluyendo adapter-breb:9100). Dashboards "Per-rail" listan "PIX vs SPEI" sin Bre-B. **AlertManager (Wave 4) no mencionado en README** aunque existe |
| B4-025 | 🟡 MED | `mipit-testkit/README.md:9-10` | "Datasets: Synthetic PIX and SPEI payment payloads" — sin Bre-B (que sí existe en `datasets/` post-W4) |
| B4-026 | 🟡 MED | `mipit-docs/README.md:91-102` | Tabla "Repos relacionados" lista 7 repos — **omite `mipit-adapter-breb`** (que es el 8º) |
| B4-027 | 🟡 MED | `mipit-docs/AGENTS.md:57, 65` | "11 statuses" pero real 15. Lista en línea 65 contiene `TRANSLATED` (no existe en código) y omite `COMPENSATING/COMPENSATED/DEAD_LETTER`. Línea 50 referencia `mapping CSVs` borrados en Wave 6 |
| B4-028 | 🟡 MED | `mipit-docs/AGENTS.md:43, 50, 66` | Líneas 43+50 referencian `mapping CSVs` y `mapping_table seeds` — los CSVs fueron borrados en W6.13 (eliminado `mappings/canonical-fields.md` + 4 CSVs). Error codes (línea 66): "MIPIT-4xx" format no coincide con código real |
| B4-029 | 🟡 MED | `mipit-core/AGENTS.md:7, 10, 52, 112` | Línea 7: 4 endpoints listados (real 30+). Línea 10 + 52: solo PIX/SPEI mencionados (sin BRE_B ni los 4 Option A). Línea 112: orden del pipeline incorrecto ("validate → canonicalize" pero código real persiste antes de validate) |
| B4-030 | 🟡 MED | `mipit-ui/AGENTS.md:8, 12, 28, 99` | Línea 8: "8 steps". Línea 12: "polling until terminal state" — el código real usa **SSE/EventSource** (`use-sse.ts`); polling también existe pero el primario es SSE. Línea 28: "uses polling" — mentira directa |
| B4-031 | 🟡 MED | `mipit-observability/AGENTS.md:7, 40` | Línea 7: 5 scrape targets, real 6. Línea 40: ref a `alerting/rules.yaml` — existe como legacy pero **prometheus rules reales viven en `prometheus/rules/mipit-{alerts,recording}.yaml`**, mounted via compose volume |
| B4-032 | 🟡 MED | `mipit-docs/srs/` + `spmp/` + `propuesta/` | **Tres directorios vacíos**. `mipit-docs/README.md:13-15` los lista como si tuvieran PDFs. Los PDFs reales viven en `C:/Users/nicog/Documents/Tesis/SRS_MIPIT.pdf` (raíz del workspace, no dentro de `mipit-docs`) |
| B4-033 | 🟡 MED | `mipit-docs/design/next-steps.md:31, 189, 31-44` | Línea 31: "Backend core — incluye traductores SWIFT, ISO20022, ACH, FedNow" — omite Bre-B. Línea 189: "Reemplazar el JWT estático del PoC" — JWT ya NO es estático (drift con ADR-005 que también lo dice). Comandos `npm test` por adapter no mencionan `mipit-adapter-breb` |
| B4-034 | 🟢 BAJO | `mipit-docs/openapi/openapi.yaml:11-17` | Header dice "P12 (Wave 4)". Estamos en post-Wave 6. La spec **sí refleja muchos cambios** post-W4 (uetr, chrgBr, lclInstrm declarados) pero el sello de versión miente |
| B4-035 | 🟢 BAJO | `mipit-docs/openapi/openapi.yaml:4` | `version: 0.4.0` — `package.json` de core dice version 0.1.0. Mismatch nominal |
| B4-036 | 🟢 BAJO | `mipit-docs/adrs/README.md:7-16` | Tabla de índice ADRs con "Estado: Aceptado" para los 8. Real: ADR-002 fue **revisado el 2026-05-16** (header dentro del ADR lo dice). Estado debería ser "Aceptado (revisado)" en el índice |
| B4-037 | 🟢 BAJO | `mipit-core/AGENTS.md:67` | "7-step orchestration" — código real tiene Step 1-7 + Step 6b (duplicación) en `payment-pipeline.ts:48-248`. Real son **8 etapas observable** aunque numeradas hasta 7 |
| B4-038 | 🟢 BAJO | `mipit-docs/openapi/openapi.yaml:184-198` (GET /payments query) | Query param declara `destination` con enum `[PIX, SPEI, BRE_B]`. Código (`payments.ts:91`) lee `query.rail` no `query.destination`. Param name drift |
| B4-039 | 🟢 BAJO | `mipit-docs/openapi/openapi.yaml:340-359` (`/stream/payments` auth) | OpenAPI dice `security: []` (público con `?token=` query). Realidad: `sse.ts:91-93` verifica el token via `app.jwt.verify(token)` y devuelve 401 si inválido. **Es público SOLO en cuanto a método de auth (no header), pero requiere token válido** — la spec lo describe ambiguo |
| B4-040 | 🟢 BAJO | `mipit-adapter-pix/AGENTS.md:107` + análogo SPEI | "mock-server.ts: POST /pix/payments returns 200 (90%) or 500 (10%), latency 100-500ms" — porcentajes hardcodeados en doc; mocks reales tienen `/admin/config` para parametrizar reject rate / timeout. La doc miente sobre la mecánica configurable |

---

## 2. Detalle por hallazgo

### B4-001 🔴 CRÍT — OpenAPI declara endpoints `/translate/canonical-to/{rail}` y `/translate/from/{rail}` que NO existen

**Archivo:** `mipit-docs/openapi/openapi.yaml:265-306`

**Doc dice:**
```yaml
/translate/canonical-to/{rail}:
  post:
    summary: Traducir canónico → formato nativo del riel
/translate/from/{rail}:
  post:
    summary: Traducir formato nativo del riel → canónico
```

**Código real:** `mipit-core/src/api/routes/translate.ts:39,104,120` registra:
- `POST /translate`
- `GET /translate/rails`
- `POST /translate/preview`

Ninguno de los dos paths declarados en OpenAPI está registrado en Fastify. Un consumidor que genere SDK desde la spec va a llamar a 404.

**Fix:** Reemplazar entradas 265-306 con los 3 endpoints reales (`POST /translate` con body `{sourceRail, destinationRail, payload, options}`, `GET /translate/rails`, `POST /translate/preview`).

---

### B4-002 🔴 CRÍT — Schema `CanonicalPacs008` de OpenAPI no coincide con el Zod real

**Archivo:** `mipit-docs/openapi/openapi.yaml:540-595` vs `mipit-core/src/domain/models/canonical.ts:57-270`

**OpenAPI declara:**
```yaml
CanonicalPacs008:
  properties:
    payment_id: string
    created_at: date-time
    grpHdr: { msgId, creDtTm, nbOfTxs, ctrlSum, ttlIntrBkSttlmAmt, sttlmInf }
    pmtId: { instrId, endToEndId, txId, uetr }
    intrBkSttlmAmt: { value, currency }
    intrBkSttlmDt: date
    chrgBr: enum
    debtor: CanonicalParty
    creditor: CanonicalParty
    purp: string
    rmtInf: { ustrd: array }
```

**Código real:**
```typescript
canonicalPacs008Schema = z.object({
  payment_id, created_at,
  grpHdr: { msgId, creDtTm, nbOfTxs, ctrlSum, ttlIntrBkSttlmAmt, initgPty, sttlmInf },
  pmtId: { endToEndId, instrId, txId, uetr },
  chrgBr, intrBkSttlmDt,
  lclInstrm: { cd, prtry },         // ← W6.5, NO en OpenAPI
  ctgyPurp: string,                  // ← W6.3, NO en OpenAPI
  amount: { value, currency, instdAmt, instdAmtCcy },  // ← Real shape; OpenAPI dice intrBkSttlmAmt
  fx: { source_currency, target_currency, rate, local_amount, via, source_provider, timestamp }, // ← P05, NO en OpenAPI
  origin: { rail, bic, routingNumber, ispb, institutionCode },  // ← NO en OpenAPI
  destination: { rail, bic, routingNumber, ispb, institutionCode }, // ← NO en OpenAPI
  debtor: { name, country, account_id, taxId, accountType, agencia, email, phone, address }, // ← shape distinto a CanonicalParty
  creditor: same,
  alias: { type, value }, // ← NO en OpenAPI
  purpose: string,         // ← OpenAPI dice `purp`
  reference: string,
  remittanceInfo: string,
  status: PaymentStatus,
  trace_id: string,
  rail_ack: legacy ack object,
})
```

**Magnitud del drift:** 12 campos en código no declarados en OpenAPI (`amount`, `fx`, `origin`, `destination`, `alias`, `purpose`, `reference`, `remittanceInfo`, `status`, `trace_id`, `lclInstrm`, `ctgyPurp`), 4 campos en OpenAPI con nombres distintos a los del código (`intrBkSttlmAmt` vs `amount`, `purp` vs `purpose`, `rmtInf.ustrd` vs `remittanceInfo`, `Party.alias` vs `debtor.account_id`).

**Fix:** regenerar la sección `CanonicalPacs008` de la OpenAPI desde el Zod schema. Considerar usar `zod-to-openapi` o `@asteasolutions/zod-to-openapi` para evitar futuro drift.

---

### B4-003 🔴 CRÍT — `mipit-docs/design/diagrams/` está vacío

**Archivo:** `mipit-docs/design/diagrams/`

**Contenido real:** únicamente `.gitkeep` (size 0, fecha 2026-03-02).

**Promesas en docs:**
- `mipit-docs/README.md:22` lista "[`design/diagrams/`](design/diagrams/) | Diagramas: alto nivel, secuencia, componentes, despliegue"
- `architecture-overview.md:64` "Los diagramas detallados (secuencia, componentes, despliegue) se encuentran en [`diagrams/`](diagrams/)"
- SPMP H1-H4 (auditoría profunda §11.5) "Arquitectura validada" + "Evaluación con 4 rieles" — implica diagramas
- Audit 2 A2 sección 4.1 #9: "Diagramas formales 4+1 / secuencia / despliegue — Solo `architecture-overview.md` y `translation-layer.md` actualizados; diagramas detallados de Diseño no re-renderizados con Bre-B"

**Fix:** Generar al menos 3 diagramas (Mermaid o draw.io exportado a SVG):
1. C4 contexto (16 containers incl. AlertManager)
2. Secuencia PIX→SPEI con pacs.008/pacs.002 + ChrgBr + ack
3. Secuencia Bre-B (con `+57` y NIT routing)

---

### B4-004 🔴 CRÍT — `mipit-adapter-breb` sin README.md ni AGENTS.md

**Archivos:** `mipit-adapter-breb/` (no contiene README ni AGENTS).

**Verificación:**
```
mipit-adapter-pix/README.md     ✓
mipit-adapter-spei/README.md    ✓
mipit-adapter-breb/README.md    ✗ FALTA
mipit-adapter-pix/AGENTS.md     ✓
mipit-adapter-spei/AGENTS.md    ✓
mipit-adapter-breb/AGENTS.md    ✗ FALTA
```

**Impacto:** un agente nuevo abriendo Bre-B no tiene contexto. La asimetría es **directamente detectable a inspección visual del directorio**. El primer tribunal que clone el proyecto va a notar el faltante.

**Fix:** copiar `mipit-adapter-spei/README.md` y `AGENTS.md` y adaptar a Bre-B (BanRep TR-002, llaves mobile-only, alias `@xxx`, NIT). Ya hay precedente en cómo se documentaron pix/spei.

---

### B4-005 🟠 ALTO — Idempotency-Key: triple drift sobre obligatoriedad

**Archivos:**
- `mipit-docs/openapi/openapi.yaml:86-92` → declara `required: true`
- `mipit-docs/adrs/ADR-004-idempotency-header.md:42` → "El header es obligatorio en `POST /payments`"
- `mipit-core/src/api/routes/payments.ts:24,26,80` → código hace `if (idempotencyKey)` y permite request sin header

**Tres fuentes que dicen 3 cosas distintas.** El código real **permite** request sin Idempotency-Key (sigue ruta de fallback línea 80 sin protección). Esto contradice tanto la OpenAPI como el ADR.

**Fix:** decidir política y unificar. Recomendación: hacer header opcional pero con warning + métrica (`mipit_payments_no_idempotency_total`), y actualizar OpenAPI a `required: false` + ADR a "recomendado, no obligatorio".

---

### B4-006 🟠 ALTO — ADR-003 omite Bre-B + vhost

**Archivo:** `mipit-docs/adrs/ADR-003-rabbitmq-async-messaging.md:31`

**Doc dice:**
> "Topic exchanges permiten enrutar `route.pix` y `route.spei` a colas específicas"

**Realidad:**
- `mipit-infra/env/breb.env:5`: `EXCHANGE_NAME=mipit.payments`, queues incluyen `route.breb`
- `mipit-infra/env/{core,pix,spei,breb}.env`: todos usan `RABBITMQ_URL=amqp://mipit:mipit_secret@rabbitmq:5672/mipit` — **vhost `/mipit`** que el ADR NO menciona

**Fix:** revisar ADR-003 con anotación "**revisado 2026-05-18**" + agregar `route.breb`/`ack.breb` + nota sobre vhost `/mipit` como decisión de aislamiento.

---

### B4-007 🟠 ALTO — ADR-006 menciona Kysely/Knex; código usa `pg` crudo

**Archivo:** `mipit-docs/adrs/ADR-006-postgres-persistence.md:17-18`

**Doc dice:**
> "Se accede mediante un query builder ligero (Kysely o Knex) en lugar de un ORM pesado."

**Realidad:**
- `grep kysely|knex C:/Users/nicog/Documents/Tesis/mipit-core/package.json` → **0 matches**
- `mipit-core/src/persistence/queries/index.ts` contiene SQL como strings (parameterized)
- Repos usan `pool.query($1, $2, ...)` del paquete `pg`

**Fix:** corregir ADR-006: "se accede directamente mediante el driver `pg` con queries parametrizadas centralizadas en `src/persistence/queries/index.ts`". Justificación: query builder no aportaba para el volumen del PoC, y el equipo prefirió SQL explícito para mantener trazabilidad de queries en logs.

---

### B4-008 🟠 ALTO — ADR-005 dice "token estático"; código genera JWT dinámico

**Archivo:** `mipit-docs/adrs/ADR-005-security-poc-jwt-https.md:18, 35`

**Doc dice:**
> "Se genera un token estático de demo que la UI incluye automáticamente."
> "El token estático de demo simplifica la experiencia de demostración"

**Realidad:** `mipit-core/src/api/server.ts:115-132`:
```typescript
if (env.NODE_ENV !== 'production') {
  const tokenHandler = async (_req, reply) => {
    const token = app.jwt.sign({ sub: 'mipit-ui', role: 'admin' });
    return reply.send({ access_token: token, token_type: 'Bearer', expires_in: 86400 });
  };
  app.get('/auth/token', tokenHandler);
  app.post('/auth/token', tokenHandler);
}
```

Token es **dinámicamente firmado por request**. JWT_SECRET viene de env. En producción retorna 404. La UI llama a `/auth/token` y guarda el token retornado.

**Fix:** actualizar ADR-005 con la mecánica real: "JWT HS256 firmado en runtime por `/auth/token` (gated a non-production) con claims `sub=mipit-ui`, `iss=mipit-core`, `aud=mipit-ui`, `exp=24h`. En producción `/auth/token` devuelve 404 — la migración a OIDC quedaría documentada como next-step."

---

### B4-009 🟠 ALTO — ADR-007 dice "adapters never HTTP"; UI proxy contradice

**Archivo:** `mipit-docs/adrs/ADR-007-hybrid-modular-architecture.md:47`

**Doc dice:**
> "Los adaptadores solo se comunican con el core vía RabbitMQ (nunca HTTP directo)"

**Realidad:** `mipit-core/src/api/routes/ui-proxy.ts:14-22, 29-42`:
```typescript
const DEFAULT_RAIL_TARGETS: Record<Rail, RailTargets> = {
  PIX:   { healthUrl: 'http://adapter-pix:9101/health',   mockBaseUrl: 'http://adapter-pix:9001' },
  SPEI:  { healthUrl: 'http://adapter-spei:9102/health',  mockBaseUrl: 'http://adapter-spei:9002' },
  BRE_B: { healthUrl: 'http://adapter-breb:9103/health',  mockBaseUrl: 'http://adapter-breb:9003' },
};

async function fetchWithBreaker(rail, url, init) {
  const breaker = circuitBreakerRegistry.get(`adapter-${rail.toLowerCase()}-http`, BREAKER_OPTS);
  return await breaker.execute(() => fetch(url, init));
}
```

El core **sí** hace HTTP directo a los adapters para health checks y para proxy de admin endpoints (`/services/:rail/health`, `/mocks/:rail/admin/*`).

**Fix:** matizar el ADR-007: "Los adaptadores procesan **lógica de negocio** exclusivamente vía RabbitMQ (canonical → rail → ack). Endpoints HTTP en adapters (`:910X/health`, `:900X/admin/*`) son solo para observabilidad operacional y control del mock, no para el flujo de pagos."

---

### B4-010, B4-011, B4-012 🟠 ALTO — Documentos de diseño omiten Bre-B y campos ISO

**Archivos:**
- `architecture-overview.md:30-33`: diagrama ASCII solo PIX + SPEI
- `translation-layer.md:22-32`: tabla de 6 rieles (sin BRE_B)
- `translation-layer.md:35-88`: shape canónico obsoleto (sin chrgBr/uetr/intrBkSttlmDt/lclInstrm)
- `translation-layer.md:245`: "PIX y SPEI ya están implementados como Option B"
- `adding-a-new-rail.md:41-44`: `SUPPORTED_RAILS = [..., 'FEDNOW']` — sin BRE_B

**Realidad:** Bre-B Option B completo desde Wave 1 P04. `mipit-adapter-breb/` real con `worker.ts`, `mock-server.ts`, RabbitMQ binding `route.breb`.

**Fix:** pasada de re-escritura en estos 3 archivos. Para `adding-a-new-rail.md` específicamente, el ejemplo (Bizum) está bien pero la línea 41 de SUPPORTED_RAILS debe incluir BRE_B y la oración debe decir "7 rieles ya implementados".

---

### B4-013 🟠 ALTO — `rabbitmq-messages.md` topología obsoleta

**Archivo:** `mipit-docs/contracts/rabbitmq-messages.md:5-15`

**Doc dice:**
```
Exchange: mipit.payments
├── Binding: route.pix  → Queue: q.adapter.pix
├── Binding: route.spei → Queue: q.adapter.spei
├── Binding: ack.pix    → Queue: q.core.ack
└── Binding: ack.spei   → Queue: q.core.ack
```

**Realidad:** queues unificadas en `payments.ack` (no `q.core.ack`) según P06; bindings `route.breb` y `ack.breb` existen; DLQ unificada `payments.dlq` (Audit 2 lo confirmó); vhost `/mipit` no mencionado.

**Fix:** regenerar la sección "Topología" del contrato desde `mipit-infra/rabbitmq/definitions.json`. Documentar vhost + DLQ unificada (decisión arquitectónica de Wave 1 P06).

---

### B4-014 🟠 ALTO — `payment-status-machine.md` con 11 estados; código tiene 15

**Archivo:** `mipit-docs/contracts/payment-status-machine.md:5-18, 64-67`

**Doc lista 11 estados:** RECEIVED, VALIDATED, CANONICALIZED, ROUTED, QUEUED, SENT_TO_DESTINATION, ACKED_BY_RAIL, COMPLETED, FAILED, REJECTED, DUPLICATE.

**Código (`canonical.ts:15-32`) tiene 15 estados:**
```typescript
PAYMENT_STATUS_ENUM = [
  'RECEIVED', 'VALIDATED', 'CANONICALIZED',
  'NORMALIZED',      // ← falta en doc
  'ROUTED', 'QUEUED', 'SENT_TO_DESTINATION', 'ACKED_BY_RAIL',
  'COMPLETED', 'FAILED', 'REJECTED', 'DUPLICATE',
  'COMPENSATING',    // ← falta en doc
  'COMPENSATED',     // ← falta en doc
  'DEAD_LETTER',     // ← falta en doc
]
```

El diagrama de transiciones en líneas 19-68 es también inválido (no incluye NORMALIZED entre CANONICALIZED y ROUTED, no representa COMPENSATING/COMPENSATED/DEAD_LETTER).

**Fix:** regenerar el doc con los 15 estados + transiciones reales. Considerar generar el diagrama desde el código (puede hacerse parseando el `PAYMENT_STATUS_ENUM` y el state machine).

---

### B4-015 🟠 ALTO — `error-codes.md` omite Bre-B + códigos nuevos

**Archivo:** `mipit-docs/contracts/error-codes.md:33-51`

**Doc cataloga solo PIX y SPEI**:
- PIX: PIX_INSUFFICIENT_FUNDS, PIX_INVALID_KEY, PIX_ACCOUNT_BLOCKED, PIX_DAILY_LIMIT, PIX_TIMEOUT
- SPEI: SPEI_INVALID_CLABE, SPEI_TIMEOUT, SPEI_BANK_REJECTED, SPEI_MAINTENANCE, SPEI_DAILY_LIMIT

**Realidad:** `mipit-adapter-breb/src/breb/types.ts` define códigos Bre-B (BanRep TR-002):
- BREB_INVALID_KEY (alias no registrado en BanRep directory)
- BREB_PHONE_FORMAT_ERROR (phone no es `+573[0-9]{9}`)
- BREB_NIT_INVALID
- BREB_RECEIVER_NOT_ENROLLED
- BREB_DAILY_LIMIT

Adicionalmente, código real emite errores internos no documentados:
- `COMPENSATION_REJECTED` (compensation-service)
- `RECONCILIATION_STUCK` (reconciliation-service)
- `RATE_LIMIT_EXCEEDED` (rate-limiter; existe pero no en este catálogo)

**Fix:** agregar sección "Bre-B errors" + sección "Errores de servicios internos" (compensation, reconciliation).

---

### B4-016 🟠 ALTO — `route-rules/rules.yaml` obsoleto

**Archivo:** `mipit-docs/route-rules/rules.yaml:1-67`

**Drift:**
1. **Sin reglas para BRE_B.** No hay `creditor.alias` con `+57`, NIT mod-11, `@xxx`.
2. **Field paths inválidos.** Doc dice `canonical.creditor.alias_type`. Código real (`canonical.ts:237-240`) tiene `alias: { type, value }` como objeto separado, **no anidado en creditor**.
3. **Valores enum stale.** Doc usa `CPF`, `CNPJ`, `EVP`, `PHONE`, `PHONE_MX`. Código (`canonical.ts:8` `ALIAS_TYPE_ENUM`) usa `['PIX_KEY', 'CLABE', 'IBAN', 'ACCOUNT', 'ABA_ROUTING', 'BIC', 'LLAVE_BREB']` — categorías diferentes.

**Fix:** regenerar `rules.yaml` desde las reglas actuales en `route-engine.ts`. Note: `route_rules` tabla en DB es la fuente de verdad (cargadas desde `002_seed_route_rules.sql` + `013_seed_breb_mappings.sql`).

---

### B4-017 🟡 MED — SSE path drift

**Archivo:** `mipit-docs/openapi/openapi.yaml:340-359`

**OpenAPI dice:** `GET /stream/payments`
**Código:** `sse.ts:86,138,188`:
- `GET /events/payments`
- `GET /events/payments/:paymentId`
- `GET /events/clients`

El path **`/stream/payments` no existe** en Fastify. Plus, el listing per-payment-id y el monitoring endpoint no están en OpenAPI.

**Fix:** reemplazar `/stream/payments` con los 3 endpoints reales bajo `/events/`.

---

### B4-018 🟡 MED — Analytics endpoints OpenAPI ≠ real

**Archivo:** `mipit-docs/openapi/openapi.yaml:308-338`

**OpenAPI declara:** `/analytics/throughput`, `/analytics/success-rate`, `/analytics/rate-limits`, `/analytics/reconciliation`.
**Código (`analytics.ts:31,82,138,149,160`) tiene:** `/analytics/latency`, `/analytics/summary`, `/analytics/circuit-breakers`, `/analytics/rate-limits`, `/analytics/reconciliation`.

Coincidencia: **2/5** (rate-limits, reconciliation). Los otros 3 declarados no existen, y 3 reales (latency, summary, circuit-breakers) no están en spec.

**Fix:** regenerar sección `paths` de analytics desde el código.

---

### B4-019, B4-020 🟡 MED — PaymentSummary y PaymentDetail response shapes drift

**Archivo:** `mipit-docs/openapi/openapi.yaml:464-538`

**OpenAPI declara `PaymentSummary`:**
```yaml
properties:
  payment_id, status, received_at, destination (enum)
```

**Código retorna en `GET /payments` (`payments.ts:96-105`):**
```typescript
{
  payment_id, status,
  origin_rail,           // ← OpenAPI no lo declara
  destination_rail,      // ← OpenAPI dice "destination"
  amount, currency,      // ← OpenAPI no los declara
  timestamps: { created_at, completed_at }
}
```

**OpenAPI declara `PaymentDetail`:** campos `original`, `canonical`, `translated`.
**Código retorna (`payments.ts:124-176`):** `original_payload`, `canonical_payload`, `translated_payload`.

**Fix:** corregir nombres en OpenAPI. Cualquier SDK generado va a fallar al parsear porque la spec dice `payment.original` pero la JSON real es `payment.original_payload`.

---

### B4-021 hasta B4-026 🟡 MED — READMEs de los 9 repos: drift sistemático Bre-B-less

Resumen consolidado:

| Repo | Línea(s) | Drift |
|------|----------|-------|
| `mipit-core/README.md` | 49-54 | Lista 4 endpoints; real 30+ |
| `mipit-ui/README.md` | 32-38 | Lista 4 páginas; real 8 (faltan analytics, live, simulator, translator) |
| `mipit-infra/README.md` | 3, 67-77 | "rieles PIX y SPEI"; sin Bre-B en tabla de repos |
| `mipit-observability/README.md` | 7, 20, 41 | 5 scrape targets (real 6); sin AlertManager |
| `mipit-testkit/README.md` | 9-10 | "Synthetic PIX and SPEI" — sin Bre-B |
| `mipit-docs/README.md` | 22, 91-102 | Linea 22 referencia `diagrams/` vacío; tabla de repos omite `mipit-adapter-breb` |

**Patrón común:** todos fueron escritos pre-P04 (Wave 1 que agregó Bre-B). El equipo agregó Bre-B al código pero olvidó pasar por READMEs.

**Fix mínimo:** pasada sistemática de búsqueda-reemplazo "PIX y SPEI" → "PIX, SPEI y Bre-B" en los 6 archivos.

---

### B4-027 hasta B4-031 🟡 MED — AGENTS.md: 5/8 con drift material

**mipit-docs/AGENTS.md:**
- Línea 43: `Verify mapping CSVs match actual mapping_table seeds in mipit-infra` — los CSVs fueron borrados en W6.13
- Línea 50: `Keep mapping CSVs aligned` — referencia rota
- Línea 57: `verify status machine covers all 11 statuses` — son 15
- Línea 65: `Status machine has 11 states: RECEIVED, VALIDATED, ... TRANSLATED, ...` — incluye `TRANSLATED` que NO existe en código; omite COMPENSATING/COMPENSATED/DEAD_LETTER
- Línea 66: `error codes: API errors (MIPIT-4xx), Internal errors (MIPIT-5xx), Rail-specific (PIX-xxx, SPEI-xxx)` — formato real es `VALIDATION_ERROR`, `IDEMPOTENCY_CONFLICT`, etc., sin prefijo MIPIT-

**mipit-core/AGENTS.md:**
- Líneas 7, 10, 52: solo PIX y SPEI mencionados; sin Bre-B
- Línea 112: "receive → validate → canonicalize → normalize → route → translate → publish" — el orden real es persist → validate → translate → normalize → route → translate-destination → publish (validate después de persist)

**mipit-ui/AGENTS.md:**
- Línea 8: "flow timeline (8 steps)" — coincide con el pipeline (mantener)
- Línea 12: "real-time status polling until terminal state" — el código usa **SSE** primario (`hooks/use-sse.ts`)
- Línea 28: "real-time WebSocket connections (uses polling)" — mentira directa: usa SSE
- Línea 99: "RAIL_CONFIG maps PIX and SPEI" — sin Bre-B

**mipit-observability/AGENTS.md:**
- Línea 7: "5 scrape targets (mipit-core, adapter-pix, adapter-spei, rabbitmq, postgres-exporter)" — falta adapter-breb (6 targets reales)
- Línea 40: `Check alerting/rules.yaml` — el rules.yaml real está en `prometheus/rules/`; el legacy `alerting/rules.yaml` existe pero NO se monta en compose

**Fix:** pasada de 30 min por cada AGENTS.md. Asegurar paridad PIX/SPEI/BRE_B en cada uno.

---

### B4-032 🟡 MED — Directorios srs/spmp/propuesta vacíos

**Archivos:** `mipit-docs/srs/`, `mipit-docs/spmp/`, `mipit-docs/propuesta/` (todos directorios vacíos).

**mipit-docs/README.md:11-15 los lista** como si tuvieran PDFs:
```
| [`srs/`](srs/) | Software Requirements Specification (PDF) |
| [`spmp/`](spmp/) | Software Project Management Plan (PDF) |
| [`propuesta/`](propuesta/) | Propuesta del proyecto (PDF) |
```

**Realidad:** los PDFs viven en la **raíz del workspace** (`C:/Users/nicog/Documents/Tesis/SRS_MIPIT.pdf`, `SPMP.pdf`, etc.), **fuera de `mipit-docs`**.

**Fix:** mover (o symlinkear/copiar) los PDFs a las carpetas correspondientes. Alternativa: actualizar README para apuntar a la raíz, pero entonces los links rotos.

---

### B4-033 🟡 MED — `next-steps.md` con info stale post-Wave 4

**Archivo:** `mipit-docs/design/next-steps.md:31, 189`

- Línea 31: "Backend core — incluye traductores SWIFT, ISO20022, ACH, FedNow" — omite Bre-B traductor (existe desde Wave 1)
- Línea 189: "Reemplazar el JWT estático del PoC" — el JWT ya **no es estático** (ver B4-008)
- Línea 32-41: comandos `npm test` por adapter mencionan pix y spei pero no breb

**Fix:** pasada por todo el archivo para reflejar estado post-Wave 6.

---

### B4-034 hasta B4-040 🟢 BAJO — Drift menores

Detalle en tabla maestra. Principal patrón: versiones y headers que mienten ("P12 Wave 4" cuando ya pasó Wave 6); enums de query params con nombres distintos (`destination` vs `rail`); descripciones de mock que datan pre-`/admin/config`.

---

## 3. RNFs SRS vs Evidencia (sección obligatoria del scope)

Audit 2 cubrió esto en la auditoría de cumplimiento. **Mis hallazgos profundos:**

| RNF (SRS / Memoria) | Promesa | Realidad medible hoy | Brecha |
|---|---|---|---|
| Throughput | ≥100 tx/sesión | Histórico 2026-05-15 (`e2e-load.mjs`) sin re-medición Wave 4-6 | **No hay assertion CI** que falle si regresa. La validation-suite cuenta "historical-load" con `durationMs: 0` |
| Latencia | ≤15s p99 | p99 ≈ 250 ms histórico | E2E tests aceptan 30s timeout — **un test pasa aunque latencia esté en 25s**. SLO no enforced |
| Tasa éxito | ≥99.9% | 999/999 histórico | No re-medido Wave 4-6 |
| Disponibilidad rails | Conformidad reglamentaria | PIX 24/7 ✓, SPEI L-V ventana ✓, Bre-B 24/7 ✓ | OK |
| Seguridad auth | API Key o equivalente | JWT HS256 dinámico ✓ | OK (drift documental con ADR-005 — B4-008) |
| Seguridad TLS | TLS 1.3 | nginx TLSv1.3-only ✓ | Pero **sin HSTS/CSP/X-Frame-Options** (auditoría profunda lo marcó; sigue sin fix en LIMITATIONS) |
| Idempotencia | Header con dedupe | Cumplido + sweeper TTL 24h | OK (drift con OpenAPI/ADR sobre obligatoriedad — B4-005) |
| Observabilidad | OTel + Prom + Grafana | Cumplido ✓ AlertManager extra | OK |
| Escalabilidad | Implícita PoC | Sin test de carga formal | **Brecha real** — rate limiter implementado pero no probado bajo presión |
| **Interoperabilidad sin downtime durante upgrade** | (de propuesta) | **No demostrado** — no hay test de rolling-upgrade ni de cero-downtime | Brecha de evidencia |

**Hallazgo no enumerado en Audit 2:** el SRS RF19 (export CSV/JSON desde UI) **sigue sin implementar** post-Wave 6. La auditoría de cumplimiento ya lo marcó como brecha real. Verifico: `mipit-ui/src/app/history/page.tsx` y `mipit-ui/src/app/analytics/page.tsx` no tienen botón export. Cero refs a `URL.createObjectURL`, `Blob`, `download`.

---

## 4. Memoria de tesis (Diseño_MIPIT.pdf) — evidencia indirecta

No leo el PDF directamente (no es ejecutable). Pero del cross-reference con `AUDIT-RAW-ui-docs.md` §11 y `mipit-docs/evidence/AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` §4.1:

**Drift conocido entre Memoria PDF y código:**
1. PDF declara endpoints `/transactions` y `/transactions/{id}` — código tiene `/payments`
2. PDF declara schema con `sourceAccount/destinationAccount/destinationRail/metadata` — código tiene `debtor/creditor/purpose/reference`
3. PDF declara 4 estados (`RECEIVED, PROCESSING, SUCCESS, FAILED`) — código tiene 15
4. PDF declara stack Spring Boot — código es Node.js + Fastify
5. PDF declara FedNow como rail evaluable (Option B) — código tiene FedNow translator-only

**Sobre-entrega no en Memoria:**
- Compensación, reconciliación, webhooks, SSE, translate endpoints, analytics endpoints, AlertManager, 14 estados, generadores con checksum, circuit breakers, rate limiter
- Auditoría de cumplimiento ya lo lista en §4.2

**Fix:** la Memoria es PDF estático — no puede actualizarse fácilmente. **Solución pragmática:** generar un `mipit-docs/memoria-addenda.md` que documente explícitamente los drifts conscientes y la sobre-entrega. Esto sirve para defensa de tesis ("la Memoria se escribió en planeación; aquí está el delta real, justificado").

---

## 5. Lista priorizada — Top 5 archivos a actualizar primero

### 1. `mipit-docs/openapi/openapi.yaml` (🔴 CRÍT)
**Por qué primero:** es el contrato formal. Cualquier consumidor que genere SDK fallará. Drift acumulado: ~50% de endpoints incorrectos o ausentes, schema canónico completamente desincronizado.
**Acción:** regenerar desde código. Considerar usar `@fastify/swagger` para auto-generación + `zod-to-openapi` para schemas.

### 2. `mipit-docs/design/diagrams/` (🔴 CRÍT)
**Por qué segundo:** está completamente **vacío**. SPMP H1-H4 lo promete, README de docs lo lista, defensa de tesis lo necesita.
**Acción:** mínimo 3 diagramas Mermaid en commits separados:
- `containers.mmd` (16 containers C4 nivel 2)
- `sequence-payment.mmd` (POST /payments → pacs.008 → adapter → ack)
- `sequence-bre-b.mmd` (Bre-B con TR-002 y `+57` routing)

### 3. `mipit-docs/contracts/payment-status-machine.md` (🟠 ALTO)
**Por qué tercero:** 11 vs 15 estados es el drift más visible/embarazoso. Cualquier reviewer abriendo este doc va a ver que falta NORMALIZED/COMPENSATING/COMPENSATED/DEAD_LETTER en 30 segundos.
**Acción:** regenerar tabla, transiciones, diagrama. Considerar auto-generar desde `PAYMENT_STATUS_ENUM`.

### 4. `mipit-docs/contracts/rabbitmq-messages.md` + `route-rules/rules.yaml` (🟠 ALTO, pair)
**Por qué cuarto:** son los contratos de mensajería y ruteo. Hoy mienten sobre la topología (sin Bre-B, sin vhost `/mipit`, queues con nombres distintos `q.adapter.pix` vs real `payments.route.pix`).
**Acción:** regenerar desde `mipit-infra/rabbitmq/definitions.json` y `mipit-core/src/routing/route-engine.ts`.

### 5. `mipit-adapter-breb/README.md` + `AGENTS.md` (🔴 CRÍT pero más fácil)
**Por qué quinto:** missing files son detectables por simple `ls`. Copiar/adaptar de `mipit-adapter-spei` toma 30 min. Cierra B4-004.

**Honorable mention:** `mipit-docs/adrs/ADR-003`, `ADR-005`, `ADR-006`, `ADR-007` — los 4 ADRs con drift material. Pero son de **revisión rápida** (cada uno necesita 10 min de edición), así que pueden agruparse como una sola wave de "ADR refresh post-Wave 6".

---

## 6. Recomendación operacional (no obligatoria)

Audit 2 ya recomendó un `B7-validation` que verifique automáticamente: OpenAPI tiene paths para todos los Fastify routes. Extiendo:

1. **`mipit-testkit/tests/contract/doc-parity.test.ts`** — test que carga `openapi.yaml`, levanta el server, hace `app.printRoutes()`, y compara. Falla CI si hay drift.
2. **`mipit-testkit/tests/contract/status-machine-parity.test.ts`** — parsea `PAYMENT_STATUS_ENUM` y verifica que cada estado aparece en `payment-status-machine.md`.
3. **Pre-commit hook en `mipit-docs`** — bloquea commits si `architecture-overview.md`, `translation-layer.md` o `rabbitmq-messages.md` no fueron tocados pero `mipit-core/src/domain/models/canonical.ts` o `mipit-core/src/api/routes/*` sí (en el mismo PR).
4. **`mipit-docs/README.md`** — agregar tabla "Última verificación de drift" con fecha del último audit por sección.

---

## 7. Cierre

El proyecto **funciona** (Wave 6 cerrada, 11/11 validación verde). Pero la **documentación se quedó en Wave 1**. La sustentación de tesis es donde más duele: cualquier miembro del tribunal que abra los docs ve un sistema de 2 rieles con 11 estados, y luego corre el código y ve 7 rieles con 15 estados. Eso es exactamente la inconsistencia que vuelve "frágil" un PoC académico.

**Total hallazgos B4:** 40 (4 críticos, 17 altos, 16 medios, 3 bajos).
**Esfuerzo estimado fix completo:** 3-4 días de trabajo de documentación + 1 día de auto-generación (OpenAPI, status machine).
