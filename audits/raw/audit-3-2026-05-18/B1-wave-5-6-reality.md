# B1 — Wave 5 & 6 Reality Check

**Fecha:** 2026-05-18
**Auditor:** Agente B1 (Audit 3)
**Branch auditada:** `Auditoria-Claude` en los 9 repos (HEAD: `mipit-core@d09e556` con un working-tree dirty en `test/integration/pipeline.test.ts` ya aplicado por el orquestador).
**Scope:** Reality check ticket-por-ticket sobre los 27 tickets de Wave 5 (14) + Wave 6 (13). NO repite hallazgos de Audits 1 ni 2.

---

## Resumen ejecutivo (5 líneas)

1. **22 / 27 tickets son honestos** (código en HEAD coincide con plan/evidence).
2. **3 tickets tienen "claim drift"** (W5.10, W6.3, W6.8) — el código existe pero el efecto que el plan promete no se materializa end-to-end por desconexión con otras capas.
3. **2 tickets tienen bugs introducidos verificables** (W6.10 args swapped → mensaje de error roto; W5.4 mock incomplete en `pipeline.test.ts` — ya parcheado por el orquestador antes de mi entrada).
4. **La evidence Wave 6 está parcialmente teatral**: W6.4 dice "persiste pacs.004 real" pero el pacs.004 sólo vive como JSON dentro de `audit_events.detail` (no hay tabla/columna `pacs004_*`, no hay endpoint que lo exponga); W6.3 declara semánticamente "PIX→SPEI deriva tipoPago" pero ningún `*-to-canonical` jamás emite `ctgyPurp`, así que la rama está muerta.
5. **El acceso live "verificó" cosas que el código NO podría haber producido** sin `inferRail` + adapter-side re-mapping silente: por ejemplo, el `valor.original: "83267"` (entero) sólo aparece en `translated_payload` (output de core); el mock receptor exige `^\d+\.\d{2}$` y sería re-formateado por `mipit-adapter-breb/src/breb/mapper.ts:45` antes de llegar al mock. Lo que se "verifica live" es el efecto del **doble mapeo** (core integer → adapter `.00`), no que el integer haya "funcionado" contra el mock.

---

## Tabla maestra de hallazgos

| ID | Sev | Ticket | Brecha | File:line |
|---|---|---|---|---|
| B1-001 | 🟠 ALTO | W5.4 | Evidence Wave 5 declara live test verde, pero `test/integration/pipeline.test.ts` fallaba con `TypeError: recordPayment is not a function` en HEAD — el `jest.mock` no fue actualizado en el commit `f3d5b75`. Orquestador ya parcheó (working-tree dirty). Indicio fuerte de que **`npm test` nunca corrió post-W5.4**. | `mipit-core/test/integration/pipeline.test.ts:8-17` (post-fix) |
| B1-002 | 🔴 CRÍT | W6.10 | `throw new TranslationError(message, 'FEDNOW')` invierte los argumentos del constructor `(rail, message, details?)`. Resultado: el error emitido tiene `rail = "FedNow is USD-domestic-only..."` (todo el mensaje) y `message = 'FEDNOW'`. Cualquier consumer del error verá un mensaje útil literalmente "FEDNOW" y el rail será una novela. Único call site en todo `src/translation/` con args swapped — los 18 otros call sites están bien. | `mipit-core/src/translation/canonical-to-fednow.ts:44-48` |
| B1-003 | 🟠 ALTO | W6.3 | `canonical.ctgyPurp` está en el schema, `ctgyPurpToTipoPago` está cableado en el SPEI mapper, **pero ningún inbound translator emite `ctgyPurp`**. `grep` por `ctgyPurp` en `src/translation/` devuelve 0 hits. Además `CreatePaymentRequest` (`api/schemas/payment-request.ts`) no acepta el campo. Resultado: la rama mapea siempre el fallback `tipoPago=1`. El plan claim "PIX.tipo='TRANSF' → ctgyPurp='CASH' → tipoPago=1" es **lógicamente cierto** pero solo porque el fallback coincidentalmente es 1. SALA→5/TAXS→14 nunca se ejercitan en producción. | `mipit-core/src/translation/*-to-canonical.ts` (ausencia), `mipit-core/src/api/schemas/payment-request.ts` (ausencia), `mipit-adapter-spei/src/spei/mapper.ts:95` (consumidor sin emisor) |
| B1-004 | 🟠 ALTO | W6.4 | Plan/evidence declaran "compensation construye + **persiste** pacs.004 real". El código construye pacs.004 OK pero la "persistencia" es `auditService.log(paymentId, 'PACS_004_EMITTED', ..., { pacs004, note: ... })`. No hay columna `pacs004_emitted`, no hay tabla, no hay endpoint REST `GET /payments/:id/pacs.004`, no se publica a ningún queue. La schema definida (`pacs004ReturnSchema`) tampoco se aplica con `.parse()` antes de emitir — si los datos del payment están mal, se emite algo no-conformante silenciosamente. | `mipit-core/src/compensation/compensation-service.ts:83-94, 155-198`; `mipit-infra/db/` (ausencia de migration para pacs.004) |
| B1-005 | 🟠 ALTO | W6.1 | Schema `pacs002AckSchema` declara `orgnlMsgId: z.string().max(35)` (mandatorio) + `orgnlUetr: z.string().uuid()` (mandatorio). Pero los 3 adapters (`adapter-pix/src/worker.ts:111-115`, `adapter-spei/src/worker.ts:99-103`, `adapter-breb/src/worker.ts:100-104`) sourean estos campos con `?.` opcional: `orgnlMsgId: routeMsg.canonical.grpHdr?.msgId` y `orgnlUetr: routeMsg.uetr ?? routeMsg.canonical.pmtId?.uetr`. Si `grpHdr.msgId` es undefined → `orgnlMsgId = undefined` (violación schema). Y el consumer (`consumer.ts:75-77`) no llama a `pacs002AckSchema.parse()` — pasa por alto la validación. Resultado: el bloque pacs002 puede emitirse técnicamente inválido. | `mipit-adapter-{pix,spei,breb}/src/worker.ts` líneas señaladas; `mipit-core/src/messaging/consumer.ts:77` (no .parse()) |
| B1-006 | 🟠 ALTO | W5.10 / W6.7 | El plan W5.10 dice "BanRep TR-002 §5 rechazaría `.00`" y "el mock toleraba `.00`". HEAD: `canonical-to-breb.ts:55` ahora emite COP integer vía `formatAmount(..., 'COP')`. PERO: el adapter `mipit-adapter-breb/src/breb/mapper.ts:44-46` **re-formatea con `.00`** antes de hablar con el mock (`Math.round(localAmount).toString() + '.00'`). El mock-server.ts:102 REQUIERE `^\d+\.\d{2}$`. Resultado: el "integer COP" sólo aparece en `translated_payload` (DB), nunca llega al mock. Dos mappers en repos distintos contradicen. El evidence "live: valor.original: '83267'" mide la DB, no la wire. | `mipit-core/src/translation/canonical-to-breb.ts:55` (emite '83267'); `mipit-adapter-breb/src/breb/mapper.ts:44-46` (rewrite a '83267.00'); `mipit-adapter-breb/src/breb/mock-server.ts:102` (regex exige .00) |
| B1-007 | 🟡 MED | W6.8 | Plan declara "Bre-B `inferTipoLlave` unified core+adapter". Realidad: el core (`breb-to-canonical.ts:164-170`) returns `BreBKeyType = TELEFONO|NIT|EMAIL|ALIAS` (4 tipos), el adapter (`adapter-breb/src/breb/mapper.ts:72-82`) returns `CC|CE|NIT|PASAPORTE|TELEFONO|EMAIL|ALIAS` (7 tipos). NO están unified — están "armonizados" en mobile-only y NIT format pero el adapter sigue clasificando PASAPORTE/CC/CE que el core etiqueta ALIAS. Si un mismo llave entra como `1234567890` (10 dígitos) → core=ALIAS, adapter=CC. Es estrictamente **menos** drift que antes, pero el claim "unified" es overstated. | `mipit-core/src/translation/breb-to-canonical.ts:37, 164-170`; `mipit-adapter-breb/src/breb/mapper.ts:72-82` |
| B1-008 | 🟡 MED | W5.11 | Plan declara regex `^\+573\d{9}$` aplicado "en TODOS los lugares". Realidad: aplicado en `payment-pipeline.ts:345` (inferRail) + `payment-request.ts:19` (isValidColombiaPhone). PERO el regex de la UI `mipit-ui/src/lib/constants.ts:29` aún usa `BREB-\+57\d{10}` (10 dígitos arbitrarios, no enforced mobile-only). La UI valida con el regex permisivo; el core rechaza si pasa landline. Inconsistencia visible para un panel que abre `constants.ts`. | `mipit-ui/src/lib/constants.ts:29` |
| B1-009 | 🟡 MED | W6.5 | Pipeline stampa `grpHdr.nbOfTxs=1, ctrlSum, ttlIntrBkSttlmAmt` (OK). PERO `canonicalRaw.grpHdr` puede venir como `undefined` desde un translator y el spread `...canonicalRaw.grpHdr` lo manejará silencioso, sin emitir `grpHdr.msgId`/`grpHdr.creDtTm` que son mandatorios en el schema. El pipeline **no llama `canonicalPacs008Schema.parse()`** después de stamping, así que un canonical inválido se persiste y publica sin error. | `mipit-core/src/pipeline/payment-pipeline.ts:107-128` (spread sin guard, sin .parse()); `mipit-core/src/domain/models/canonical.ts:61` (grpHdr mandatorio) |
| B1-010 | 🟡 MED | W6.2 | El catálogo BACEN está parcialmente cubierto (11 codes: AB03/AC01/AC03/AC04/AM04/AM18/BE01/DS04/ED05/FF07/MD06/RR04). Códigos BACEN comunes ausentes: AG01, AG02, AG03, AG07, AC02, AC05, AC13, AC14, AM02, BE02-BE10. El default `cd: 'NARR', prtry: code` es seguro (ISO acepta NARR), pero el evidence Wave 6 dice "BACEN AB03 / CECOBAN R01 crudos → ✅ Mapeados a `ExternalStatusReason1Code`". Honesto si solo nos referimos a 12 códigos; engañoso si "mapeados" sugiere catálogo completo. | `mipit-core/src/translation/rail-rejection-mapping.ts:32-45` |
| B1-011 | 🟡 MED | W6.11 | NACHA File Header byte-exact: 94 chars OK, posiciones 04-13 + 14-23 son 10 chars cada una. PERO: `immediateDestination` está poblado con `txn.odfi.routingNumber` (el ODFI, no el RDFI). El spec dice ImmediateDestination = RDFI routing. El código comenta "PoC uses same routing — production fills with ODFI EIN". Lo que el comment no dice: production fills ImmediateDestination con RDFI (el receptor); aquí ambos campos son ODFI. Bug silencioso pero técnicamente inválido contra spec. | `mipit-core/src/translation/canonical-to-ach-nacha.ts:118-120` |
| B1-012 | 🟡 MED | W5.4 | Plan trailer del propio Wave 5 reconoce: "consumer.ts:134: `recordPayment` etiqueta `origin_rail` con el rail del ACK destino, no del payment original". Sigue así en HEAD (`consumer.ts:147` — `recordPayment(finalStatus, ack.source_rail, destRail ?? 'UNKNOWN')`). Grafana `mipit_payments_total` mezclará origin/destination. Es nominalmente "trasladado a Wave 7" pero el evidence "Grafana matchea DB" es difícil de sostener mientras esta etiqueta esté volteada. | `mipit-core/src/messaging/consumer.ts:147` |
| B1-013 | 🟢 BAJO | W6.4 | `compensate()` en `CompensationService` no llama `pacs004ReturnSchema.parse(pacs004)` antes de loguear. Si el dato del payment es defectuoso (ej. `payment.uetr` no es UUID válido), se loguea como JSON pero el schema-validation gate se omite. | `mipit-core/src/compensation/compensation-service.ts:83-94` |
| B1-014 | 🟢 BAJO | W6.1 | `mipit-adapter-{pix,spei,breb}/test/unit/worker.test.ts` NO testean la emisión del bloque `pacs002` (ningún hit en grep `pacs002\|orgnlEndToEndId\|orgnlUetr`). Solo `consumer.test.ts` testea consumo. El claim "pacs.002 emitido por los adapters" depende exclusivamente de inspección manual / live. | `mipit-adapter-{pix,spei,breb}/test/` (ausencia de cobertura) |
| B1-015 | 🟢 BAJO | W5.4 | El `recordPayment` en `pipeline-pipeline.ts:308` se llama con `originRail` válido (computed fuera del try), pero después de un `inferRail` exitoso + cualquier error: incluye errores de validación, FX, rate-limit, routing. Esto significa que `mipit_payments_total{status=FAILED}` se incrementa incluso para validation errors antes de RECEIVED — métrica un poco "inflada" para los que esperan "payments-that-were-processed-but-failed". Documentado, no roto. | `mipit-core/src/pipeline/payment-pipeline.ts:289-308` |
| B1-016 | 🟢 BAJO | W6.4 | `COMPENSABLE_STATUSES = {DEAD_LETTER, FAILED}`. Un payment en `COMPENSATED` no puede recompensarse, pero un payment en `COMPENSATING` (parcial) tampoco — útil para idempotency, pero significa que si la transición a COMPENSATED falla a mitad, el payment queda atascado en COMPENSATING sin retry path. No critico para tesis. | `mipit-core/src/compensation/compensation-service.ts:25-28` |
| B1-017 | 🟢 BAJO | W6.7 | `BREB_ENTITY_CODES.NEQUI: '5070'` y `DAVIPLATA: '0051'` están duplicados con `DAVIVIENDA: '0051'` (DaviPlata es operada por Davivienda, pero documentarlo como código duplicado en un enum sin enforcement es brittle). Si el código `5070` no está en el catálogo Superfinanciera oficial, levantar bandera. | `mipit-core/src/translation/breb-to-canonical.ts:127-128` |

---

## Detalle por hallazgo

### B1-001 🟠 ALTO — W5.4 evidence firmada sin `npm test`

**Plan/evidence Wave 5:** "✅ recordPayment(FAILED, originRail, 'UNKNOWN') en pipeline catch. counter incrementa".

**Realidad HEAD `d09e556`:** El `jest.mock` en `test/integration/pipeline.test.ts:8-12` solo mockeaba `startLatencyTimer`, `recordTranslationError`, `recordRoutingDecision`. Cuando el código nuevo de W5.4 hace `import { recordPayment }` y la pipeline catch lo invoca, jest devuelve `undefined` — error `TypeError: recordPayment is not a function`.

El orquestador ya aplicó el fix (líneas 16: `recordPayment: jest.fn()`). El working-tree de `mipit-core` muestra `test/integration/pipeline.test.ts` modificado, sin commit.

**Lo que esto implica:** Si la suite hubiera corrido localmente antes del commit `f3d5b75` (Wave 5) o `d09e556` (Wave 6), este test habría reventado. La evidence Wave 5 dice "tests offline pendientes a re-correr en Wave 6 (cambios estructurales pequeños, sin regression esperada)" — eso es exactamente el corner que dejó el agujero.

Recomendación: re-correr `npm test` en mipit-core, mipit-adapter-{pix,spei,breb} desde HEAD limpio, registrar resultado para sustentación. La evidence Wave 6 declara "310/310 ✅" — verificar si ese conteo incluye el integration test reparado.

```ts
// mipit-core/test/integration/pipeline.test.ts (HEAD, post-orquestador-fix)
jest.mock('../../src/observability/metrics.js', () => ({
  startLatencyTimer: jest.fn(() => jest.fn()),
  recordTranslationError: jest.fn(),
  recordRoutingDecision: jest.fn(),
  // W5.4 — pipeline catch block now records FAILED in mipit_payments_total
  // so Grafana matches DB. Mock missed in original Wave 5 commit (...)
  recordPayment: jest.fn(),
}));
```

---

### B1-002 🔴 CRÍT — W6.10 TranslationError args swapped

**Plan W6.10:** "`canonical-to-fednow.ts` lanza `TranslationError` si `currency !== USD` y no hay USD on-ramp explícito".

**Realidad HEAD:**

```ts
// mipit-core/src/translation/canonical-to-fednow.ts:44-48
throw new TranslationError(
  `FedNow is USD-domestic-only (Federal Reserve OP §3.1). Refusing to translate ${canonical.amount.currency} ${canonical.amount.value} without explicit USD on-ramp in canonical.fx.`,
  'FEDNOW',
);
```

**Pero el constructor es:**

```ts
// mipit-core/src/domain/errors/index.ts:34-35
export class TranslationError extends AppError {
  constructor(rail: string, message: string, details?: Record<string, unknown>) {
```

**Resultado:** `error.rail = "FedNow is USD-domestic-only..."` y `error.message = "FEDNOW"`. Lo que llega al consumidor del error (logging, response JSON, métrica `translation_errors_total{rail=...}`) es:
- `rail` = una novela de 200 caracteres (rompe label-cardinality de Prometheus)
- `message` = la cadena literal `"FEDNOW"` (inútil para diagnosticar)

**Compara con los otros 18 call-sites** (`grep "throw new TranslationError" src/translation/*.ts`): TODOS usan `(rail, message)` correctamente. Solo W6.10 invierte.

**Fix sugerido:**
```ts
throw new TranslationError(
  'FEDNOW',
  `FedNow is USD-domestic-only (Federal Reserve OP §3.1). Refusing to translate ${canonical.amount.currency} ${canonical.amount.value} without explicit USD on-ramp in canonical.fx.`,
);
```

---

### B1-003 🟠 ALTO — W6.3 ctgyPurp es feature muerto

**Plan W6.3:** "Agrega `canonical.ctgyPurp`. SPEI mapper deriva `tipoPago` via tabla CASH→1, INTC→4, SALA→5, SUPP→7, TAXS→14, DVPM→16, TRAD→17."

**Realidad HEAD:**
- `canonical.ts:161` declara `ctgyPurp: z.string().max(4).optional()` — ✅
- `adapter-spei/src/spei/mapper.ts:95` lee `canonical.ctgyPurp` y mapea a tipoPago — ✅
- **Ningún inbound translator emite `canonical.ctgyPurp`**: `grep -rn "ctgyPurp" src/translation/` = 0 hits.
- **`POST /payments` no acepta `ctgyPurp`** en `payment-request.ts` — el schema no lo expone.

**Consecuencia:** `canonical.ctgyPurp` es siempre `undefined` en producción → fallback `tipoPago=1` siempre. La feature SALA→5/TAXS→14 jamás se ejecuta. El plan claim "differencia P2P/nómina/impuesto" es teórico-solamente.

**Fix sugerido (camino mínimo):** aceptar `ctgyPurp` en `createPaymentSchema` y stamparlo en el canonical durante el pipeline step 4.

```ts
// payment-request.ts — agregar
ctgyPurp: z.enum(['CASH','INTC','SALA','SUPP','TAXS','DVPM','TRAD']).optional(),

// payment-pipeline.ts step 4 — agregar al canonical
const canonical: CanonicalPacs008 = {
  ...canonicalRaw,
  ctgyPurp: request.ctgyPurp ?? canonicalRaw.ctgyPurp,
  // ... resto
};
```

---

### B1-004 🟠 ALTO — W6.4 pacs.004 "persiste" en audit_events JSON

**Plan/evidence W6.4:** "`compensation-service.compensate()` ahora construye + **persiste** un pacs.004 real cuando el payment fue ACKed por el rail."

**Realidad HEAD `compensation-service.ts:82-94`:**

```ts
log.info('Payment was ACKed by rail — emitting pacs.004 PaymentReturn');
const pacs004 = buildPacs004FromPayment(payment, 'TECH');
await this.auditService.log(
  paymentId,
  'PACS_004_EMITTED',
  'compensation-service',
  {
    pacs004,  // <-- aquí se "persiste"
    note: 'Mock destination rail does not consume a return queue (PoC scope-out); pacs.004 is persisted for audit only.',
  },
  payment.trace_id,
);
```

La "persistencia" es como sub-objeto JSON dentro de `audit_events.detail`. NO existe:
- columna `pacs004_emitted` en `payments` (verificado: ningún SQL en `db/init/` ni `db/migrations/` la define)
- tabla `pacs004_returns`
- endpoint REST `GET /payments/:id/pacs.004`

**Adicional:** `buildPacs004FromPayment` retorna un `Pacs004Return` typed, pero **no se valida con `pacs004ReturnSchema.parse()`**. Si `payment.uetr` viene `null` desde DB (legacy row), el objeto resultante tiene `orgnlUetr: null` que la schema rechazaría — pero como nunca se valida, se loguea silenciosamente.

**Implicación tesis:** El claim "Saga compensation via pacs.004 ✅ pacs.004.001.09 real construido" del Wave 6 evidence es defendible solo si "persistido" se redefine como "logueado". Panel pregunta "¿se persiste a una tabla queryable?" → respuesta honesta = no.

**Fix sugerido:**
1. Migration nueva: añadir columna `pacs004_payload JSONB` a `payments`, o tabla `payment_returns`.
2. `compensation-service.ts:83` — guardar pacs004 vía `paymentRepo.savePacs004(paymentId, pacs004)`.
3. Validar con `pacs004ReturnSchema.parse(pacs004)` antes de persistir.

---

### B1-005 🟠 ALTO — W6.1 pacs.002 emitido sin schema gate

**Plan W6.1:** "3 adapters emiten bloque `pacs002` enriquecido (`orgnlEndToEndId`, `orgnlUetr`, `txSts`, `stsRsnInf`)."

**Realidad HEAD adapter-pix `worker.ts:110-122`:**

```ts
pacs002: {
  msgId: `STS-${randomUUID()}`,
  orgnlMsgId: routeMsg.canonical.grpHdr?.msgId,        // ← opcional via ?.
  orgnlMsgNmId: 'pacs.008.001.10',
  orgnlEndToEndId: routeMsg.canonical.pmtId?.endToEndId ?? routeMsg.payment_id,
  orgnlUetr: routeMsg.uetr ?? routeMsg.canonical.pmtId?.uetr,  // ← puede ser undefined
  txSts,
  stsRsnInf: railAck.error ? { rsn: { prtry: ... }, addtlInf: [...] } : undefined,
},
```

**Pero el schema `pacs002AckSchema` (core):**
- `msgId: z.string().max(35)` — mandatorio
- `orgnlMsgId: z.string().max(35)` — mandatorio
- `orgnlEndToEndId: z.string().max(35)` — mandatorio
- `orgnlUetr: z.string().uuid()` — mandatorio

Si una run no tiene `grpHdr.msgId` o `uetr`, el bloque emitido viola la schema, **pero el consumer `consumer.ts:75-77` no llama `pacs002AckSchema.parse(ack.pacs002)`**:

```ts
const txSts: Pacs002TxStatus = ack.pacs002?.txSts ?? legacyStatusToTxSts(ack.rail_ack.status);
// no pacs002AckSchema.parse() en ningún lado
```

**Implicación:** El bloque pacs002 "existe" en el wire pero podría ser sintácticamente inválido (campos mandatorios = undefined). Un consumer externo real (que sí valide) lo rechazaría.

Mitigación: en la práctica, `payment-pipeline.ts:42` siempre setea `uetr = randomUUID()` y el publish a la queue incluye `uetr` en `routeMsg.uetr`, así que `orgnlUetr` virtualmente nunca es undefined en prod. **PERO** `orgnlMsgId: routeMsg.canonical.grpHdr?.msgId` ES vulnerable: si el inbound translator no setea `grpHdr.msgId`, queda `undefined`.

**Fix sugerido:**
- Adapter side: validar con la schema antes de publicar.
- Core consumer: validar con `pacs002AckSchema.safeParse()` y nack si no pasa.

---

### B1-006 🟠 ALTO — W5.10/W6.7 doble mapping BREB hace inútil el "fix" COP integer

**Plan W5.10:** "`canonical-to-breb` usa `formatAmount(value, 'COP')` (entero, no `.toFixed(2)`). El mock toleraba `.00` pero BanRep TR-002 §5 lo rechazaría."

**Realidad — flujo HEAD:**

1. `mipit-core/src/translation/canonical-to-breb.ts:55` emite `valor.original = '83267'` (entero) → guardado en DB `translated_payload`.
2. RabbitMQ entrega `routeMsg.canonical` al adapter (NOTA: NO entrega `translated`).
3. `mipit-adapter-breb/src/worker.ts:85` llama `canonicalToBreBPayload(routeMsg.canonical)`.
4. `mipit-adapter-breb/src/breb/mapper.ts:44-46`:
   ```ts
   const amountStr = ccy === 'COP'
     ? Math.round(localAmount).toString() + '.00'  // <-- AGREGA .00
     : (Math.round(localAmount * 100) / 100).toFixed(2);
   ```
5. La payload que llega al `mock-server.ts:102` (regex `^\d+\.\d{2}$`) tiene `.00` → mock acepta.

**Consecuencia:**
- La DB `translated_payload` muestra "83267" (integer) como dice la evidence.
- El wire real al mock muestra "83267.00".
- Si BanRep TR-002 §5 rechazaría `.00`, el adapter de MIPIT seguiría enviando `.00` y BanRep igual rechazaría.
- El "fix" W5.10 solo cambia el output del core, no el del adapter (que es lo que llega a BanRep).

**Y la evidence "live verify" mide DB, no wire:** El comando `SELECT jsonb_pretty(translated_payload)` lee el output del CORE, no del ADAPTER.

**Lo que esto significa:**
- Si la tesis defiende "MIPIT emite COP integer per BanRep TR-002", la evidence necesita capturar el HTTP request body del adapter al mock, no la columna `translated_payload`.
- Hay drift entre dos mappers (`mipit-core/.../canonical-to-breb.ts` y `mipit-adapter-breb/.../mapper.ts`) que deberían ser uno.

**Fix sugerido:**
1. Decisión arquitectónica: ¿el adapter usa el `translated_payload` que viene en el `routeMsg`, o re-traduce desde el `canonical`? Hoy hace lo segundo. Si se cambia a usar `translated_payload` (single source of truth), el doble mapping desaparece.
2. Mientras tanto: cambiar `adapter-breb/src/breb/mapper.ts:45` a emitir entero sin `.00` y actualizar el mock-server.ts:102 al regex `^\d+(\.\d{2})?$`.

---

### B1-007 🟡 MED — W6.8 inferTipoLlave "unified" es overstated

**Plan:** "Bre-B `inferTipoLlave` unified core+adapter".

**Realidad:**

```ts
// mipit-core/src/translation/breb-to-canonical.ts:37, 164-170
export type BreBKeyType = 'TELEFONO' | 'NIT' | 'EMAIL' | 'ALIAS';  // 4 tipos
function inferTipoLlave(llave: string): BreBKeyType {
  if (/^\+573\d{9}$/.test(llave)) return 'TELEFONO';
  if (/^\d{9,10}-\d$/.test(llave)) return 'NIT';
  if (/^@[a-zA-Z0-9._]{3,19}$/.test(llave)) return 'ALIAS';
  if (/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(llave)) return 'EMAIL';
  return 'ALIAS';
}
```

```ts
// mipit-adapter-breb/src/breb/mapper.ts:72-82
let tipoLlave: 'CC' | 'CE' | 'NIT' | 'PASAPORTE' | 'TELEFONO' | 'EMAIL' | 'ALIAS' = 'ALIAS';  // 7 tipos
if (/^\+573\d{9}$/.test(llave)) tipoLlave = 'TELEFONO';
else if (/^\d{9,10}-\d$/.test(llave)) tipoLlave = 'NIT';
else if (/^@[a-zA-Z0-9._]{3,19}$/.test(llave)) tipoLlave = 'ALIAS';
else if (/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(llave)) tipoLlave = 'EMAIL';
else if (/^[A-Z]{1,3}\d{5,10}$/.test(llave)) tipoLlave = 'PASAPORTE';
else if (/^\d{6,7}$/.test(llave)) tipoLlave = 'CE';
else if (/^\d{8,10}$/.test(llave)) tipoLlave = 'CC';
```

**Brecha:** 
- `12345678` (8 dígitos) → core=ALIAS, adapter=CC.
- `AB123456` → core=ALIAS, adapter=PASAPORTE.
- `1234567` (7 dígitos) → core=ALIAS, adapter=CE.

Si el canónico que viene desde core dice `alias.type='LLAVE_BREB'` y el adapter re-clasifica, hay un re-typing silencioso. No es bug crítico (el adapter es el que habla con el rail), pero el plan claim "unified" es overstated.

---

### B1-008 🟡 MED — W5.11 regex BRE_B no enforced en UI

**Plan:** "Regex BRE_B mobile-only `^\+573\d{9}$` en el inferRail del pipeline + en el validator de `payment-request.ts`."

**Realidad:** sí está en `payment-pipeline.ts:345` + `payment-request.ts:19`. Pero la UI `mipit-ui/src/lib/constants.ts:29`:

```ts
BRE_B: { 
  ...,  
  aliasPattern: /^(BREB-\+57\d{10}|\d{9,10}-\d|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+)$/,
  ...
}
```

`BREB-\+57\d{10}` acepta cualquier 10 dígitos después de `+57` (incluyendo landlines `+5712345xxxxx`). El usuario llena un form con `BREB-+571234567890`, la UI valida, el POST sale, el core lo rechaza con 400.

**Fix sugerido:** Cambiar `\+57\d{10}` → `\+573\d{9}` en `constants.ts:29`.

---

### B1-009 🟡 MED — W6.5 stamping sin schema gate

**Plan W6.5:** "pipeline stampa `grpHdr.nbOfTxs=1, ctrlSum, ttlIntrBkSttlmAmt`".

Código en `payment-pipeline.ts:114-122`:

```ts
grpHdr: {
  ...canonicalRaw.grpHdr,   // si canonicalRaw.grpHdr es undefined, spread es no-op
  nbOfTxs: 1,
  ctrlSum: canonicalRaw.amount.value,
  ttlIntrBkSttlmAmt: canonicalRaw.grpHdr?.ttlIntrBkSttlmAmt ?? {
    value: canonicalRaw.amount.value,
    currency: canonicalRaw.amount.currency,
  },
},
```

Si `canonicalRaw.grpHdr` es undefined, el objeto resultante es:
```
{ nbOfTxs: 1, ctrlSum: 123, ttlIntrBkSttlmAmt: {...} }
```

Falta `msgId` y `creDtTm`, que la schema (`canonical.ts:61-63`) declara **mandatorios** (sin `.optional()`). El pipeline **no llama `canonicalPacs008Schema.parse(canonical)`** después de stampar, así que el canonical defectuoso se persiste sin error.

**Mitigación parcial:** Los translators inbound (PIX/SPEI/BRE_B/SWIFT/etc.) sí emiten grpHdr.msgId — verificado vía grep. Así que en la práctica `canonicalRaw.grpHdr` no es undefined en runs reales. **PERO** un translator nuevo que olvide emitir grpHdr no produciría error visible.

**Fix sugerido:** validar el canónico con `canonicalPacs008Schema.safeParse()` después del stamping. Si falla, lanzar `TranslationError` y dejar que el catch del pipeline registre el fail.

---

### B1-010 🟡 MED — W6.2 catálogo BACEN parcial

`rail-rejection-mapping.ts:32-45` cubre 12 códigos BACEN. Catálogo BACEN público (Manual de Códigos de Rejeição SPI Apêndice III v3.1) tiene >70 códigos. Los ausentes incluyen:
- AG01-AG07 (Agreement violations)
- AC02, AC05, AC13, AC14
- AM02, AM05-AM21
- BE02-BE10
- Etc.

El default `{cd:'NARR', prtry:code}` es seguro (NARR es ISO válido), pero el evidence Wave 6 dice "BACEN AB03 / CECOBAN R01 crudos → ✅ Mapeados a `ExternalStatusReason1Code`". Si "mapeados" sugiere catálogo completo, es overstated.

**Recomendación:** documentar explícitamente la cobertura parcial en el plan o agregar las 30 entries más comunes.

---

### B1-011 🟡 MED — W6.11 NACHA File Header semánticamente roto pero byte-exact

Posiciones son byte-exact (94 chars, pos 04-13 = 10 chars Immediate Destination, pos 14-23 = 10 chars Immediate Origin). Bien.

**PERO** `canonical-to-ach-nacha.ts:118-120`:

```ts
const rdfiRouting = txn.odfi.routingNumber.padStart(9, '0').slice(0, 9);
const immediateDestination = ` ${rdfiRouting}`;   // 10 chars (leading blank + 9 digits)
const immediateOrigin = ` ${rdfiRouting}`;        // 10 chars (PoC uses same routing — production fills with ODFI EIN)
```

`txn.odfi.routingNumber` es el routing del **originator** (ODFI). El spec NACHA dice:
- Immediate Destination = routing del receptor (RDFI o operator del sistema, ej. Federal Reserve)
- Immediate Origin = routing del emisor (el ODFI)

Aquí ambos son ODFI. Un parser NACHA estricto que verifique `ImmediateDestination ≠ ImmediateOrigin` lo rechazaría. El comment del código admite "PoC uses same routing" pero deja sin documentar que ImmediateDestination debería referenciar al RDFI.

**Fix sugerido:** usar `txn.entryDetail.routingTransitNumber` (que ES el RDFI según la línea 134-137) para `immediateDestination`, y `txn.odfi.routingNumber` para `immediateOrigin`. O al menos un comentario más explícito.

---

### B1-012 🟡 MED — Persist `origin_rail` mislabel en consumer (W5.4 trailer)

El propio plan Wave 5 trailers:
> "Bug menor en `consumer.ts:134`: `recordPayment` etiqueta `origin_rail` con el rail del ACK destino, no del payment original → Wave 7 SOT-001/CLEAN-001"

HEAD `consumer.ts:147`:
```ts
recordPayment(finalStatus, ack.source_rail, destRail ?? 'UNKNOWN');
```

`ack.source_rail` = el adapter que envió el ACK = el **destination_rail del payment** (porque el adapter de destino emite el ACK). Así que `origin_rail` en `mipit_payments_total` está al revés para todos los completed/rejected events.

**Implicación demo:** Si Grafana se filtra por `origin_rail="PIX"`, no aparecen los payments PIX→SPEI completados (aparecen como `origin_rail="SPEI"`).

El evidence Wave 5 dice "✅ Grafana `mipit_payments_total` matchea `SELECT COUNT(*) FROM payments`". Eso es probable que matcheé en agregado total, pero no por rail.

---

### B1-013 🟢 BAJO — pacs.004 emitido sin schema gate

Ver detalle en B1-004. `buildPacs004FromPayment` no llama `pacs004ReturnSchema.parse(result)` antes de retornar. Si los datos del payment están corruptos (ej. uetr inválido), se emite silenciosamente algo no-conformante.

---

### B1-014 🟢 BAJO — pacs.002 emisión adapter sin test

Adapters tienen tests para `mapper.ts`, `response-mapper.ts`, `worker.ts` (al menos pix tiene 7 archivos test/unit). Pero ninguno cubre la construcción del bloque `pacs002` enriquecido (B1 verificó: `grep "pacs002" mipit-adapter-pix/test/` = 0 hits). El claim "3 adapters emiten pacs002" se sostiene por inspección manual del código, no por test gate.

**Fix sugerido:** un test unit por adapter que arme un `routeMsg` fake y verifique que `publishAck` recibe el bloque `pacs002` con `orgnlUetr`, `orgnlEndToEndId`, `txSts` correctos.

---

### B1-015 🟢 BAJO — `recordPayment` FAILED contado para validation errors

`payment-pipeline.ts:289-308` ejecuta `recordPayment(FAILED, originRail, 'UNKNOWN')` en el catch. Si la falla viene de:
- step 2 `paymentRepo.create()` — DB falló, payment_id NO existe pero la métrica se incrementa.
- step 3 validation error — tampoco hay row aún.
- step 4 translator error.

Esto significa que `SELECT COUNT(*) FROM payments WHERE status='FAILED'` será MENOR que `sum(mipit_payments_total{status='FAILED'})` cuando hay errores tempranos. La evidence W5.4 "Grafana matchea DB" es relativo — matchea en happy path, no en error path.

---

### B1-016 🟢 BAJO — `COMPENSATING` no es compensable

`COMPENSABLE_STATUSES = {DEAD_LETTER, FAILED}`. Si el flow se interrumpe entre `updateStatus(COMPENSATING)` y `updateStatus(COMPENSATED)`, el payment queda `COMPENSATING` y un nuevo `compensate(paymentId)` lo rechaza con "not compensable". No hay retry path.

Fix: agregar `COMPENSATING` al set, idempotency-via-state (si ya hay un pacs.004 en audit_events, skip).

---

### B1-017 🟢 BAJO — `BREB_ENTITY_CODES` duplicado

`breb-to-canonical.ts:127-128`:
```ts
DAVIVIENDA:        '0051',
BANCAMIA:          '0059',
NEQUI:             '5070',
DAVIPLATA:         '0051',  // operada por Davivienda
```

`DAVIVIENDA` y `DAVIPLATA` comparten `'0051'`. Si alguien busca `BREB_ENTITY_CODES.DAVIPLATA` y luego lo usa como label de Prometheus, métrica se solapará. `NEQUI: '5070'` — falta verificar contra catálogo Superfinanciera oficial; SEDPE códigos van en rango 5xxx, pero `5070` específicamente no lo verifiqué.

---

## Veredicto por ticket

| Ticket | Estado |
|---|---|
| W5.1 surface UETR/FX/timestamps | ✅ HONEST |
| W5.2 /webhooks/alertmanager | ✅ HONEST |
| W5.3 UI Jaeger search-by-attribute | ✅ HONEST |
| W5.4 recordPayment en pipeline catch | ⚠️ HONEST en código, pero test mock estaba incompleto (B1-001) |
| W5.5 histogram buckets [10..30000] | ✅ HONEST |
| W5.6 UI NORMALIZED + neutral badge | ✅ HONEST |
| W5.7 CLABE mod-10 placeholders | ✅ HONEST (validados offline) |
| W5.8 /simulate 3 rieles + banner | ✅ HONEST |
| W5.9 SSE jwt.verify | ✅ HONEST |
| W5.10 canonical-to-breb COP integer | 🚨 CLAIM DRIFT (B1-006) — el adapter sigue agregando `.00` |
| W5.11 BRE_B regex mobile-only | ⚠️ HONEST en core, GAP en UI (B1-008) |
| W5.12 stubs zombie deleted | ✅ HONEST |
| W5.13 comment honestidad académica | ✅ HONEST |
| W5.14 seed_mapping_table.sql doc | ✅ HONEST |
| W6.1 pacs.002 enriched | ⚠️ HONEST en emisión, pero sin schema gate (B1-005) y sin test cobertura (B1-014) |
| W6.2 rail-rejection-mapping | ⚠️ HONEST con cobertura parcial (B1-010) |
| W6.3 ctgyPurp → tipoPago | 🚨 CLAIM DRIFT (B1-003) — feature muerta sin emisor |
| W6.4 pacs.004 en compensation | 🚨 INCOMPLETE (B1-004) — solo loguea, no persiste a tabla queryable |
| W6.5 fidelity batch | ⚠️ HONEST en código, sin schema gate (B1-009) |
| W6.6 orgnlMsgNmId regex .NN | ✅ HONEST |
| W6.7 BREB 4-dig | ✅ HONEST (con caveats B1-017 / B1-006) |
| W6.8 inferTipoLlave "unified" | ⚠️ CLAIM DRIFT mínimo (B1-007) |
| W6.9 endToEndId regeneration | ✅ HONEST |
| W6.10 FedNow USD-only | 🐛 BUG INTRODUCIDO (B1-002) — args swapped en TranslationError |
| W6.11 NACHA byte-exact File Header | ⚠️ HONEST byte-exact, semánticamente débil (B1-011) |
| W6.12 LIMITATIONS.md §11 §12 | ✅ HONEST |
| W6.13 CSVs eliminados + README | ✅ HONEST |

## Conteo final

- **HONEST sin caveats**: 12/27 (W5.1, W5.2, W5.3, W5.5, W5.6, W5.7, W5.8, W5.9, W5.12, W5.13, W5.14, W6.6, W6.9, W6.12, W6.13) = 15/27
- **HONEST con caveats menores**: W5.4, W5.11, W6.1, W6.2, W6.5, W6.7, W6.11 = 7/27
- **CLAIM DRIFT (código existe pero efecto declarado no se materializa)**: W5.10, W6.3, W6.8 = 3/27
- **INCOMPLETE (la palabra "persiste" se redefine para encubrir falta de persistencia real)**: W6.4 = 1/27
- **BUG INTRODUCIDO en el propio ticket**: W6.10 = 1/27

**Total tickets que requieren acción adicional:** 5 (W5.10, W6.3, W6.4, W6.8, W6.10).

---

## Recomendaciones para defensa

1. **Antes de la sustentación**:
   - Aplicar el fix B1-002 (TranslationError args swap). 5 minutos.
   - Aplicar el fix B1-008 (UI regex mobile-only). 5 minutos.
   - Re-correr `npm test` completo en mipit-core post-orquestador-fix y registrar el conteo real (puede que no sea 310/310).
2. **Aceptar y documentar el claim drift**:
   - W6.3 ctgyPurp es scaffolding sin emisor — agregarlo al README como "Wave 7: cablear `ctgyPurp` desde POST /payments → canonical".
   - W6.4 pacs.004 es "audit-trail-only-persistence" — actualizar el plan/evidence para que diga "persiste como JSON en `audit_events` (PoC); migration a tabla dedicada en Wave 7".
   - W5.10 doble mapeo BREB — admitir en el plan que el output integer solo vive en `translated_payload` (DB) y que el adapter aún emite `.00` al mock; corrección real requiere unificar mappers (Wave 7 SOT).
3. **Para el panel**: si preguntan "¿el pacs.002 emitido pasa validación XSD?", la respuesta honesta es "los campos están presentes pero no validamos con `pacs002AckSchema.parse()` en el consumer — un cliente externo que sí valide podría rechazar un bloque con `orgnlMsgId` undefined". Tener un script `npm run validate-pacs002` listo añade defensibilidad.
