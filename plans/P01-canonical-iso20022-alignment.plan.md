# P01 — Canonical Model & ISO 20022 Alignment

**Wave**: 1 (foundation)
**Repos afectados**: `mipit-core`, `mipit-docs`, `mipit-infra`
**Branch**: `Auditoria-Claude`
**Estimación**: 3-4 días
**Riesgo**: Alto (toca el corazón del proyecto y dispara breaking changes en P02/P03/P04)

---

## 1. Objetivo

Cerrar la brecha entre lo que el proyecto llama "pacs.008 canónico" y lo que realmente es ISO 20022 pacs.008.001.10. Tres caminos posibles; este plan elige el **camino híbrido pragmático**:

1. **Renombrar** explícitamente el modelo a "MiPIT Internal Canonical (pacs.008-derived)" en TODA la documentación, ADRs, OpenAPI, dashboards, UI.
2. **Agregar los 3 campos mandatorios v10 más críticos**: `UETR` (UUIDv4), `ChrgBr` (DEBT/CRED/SHAR/SLEV), `IntrBkSttlmDt`. Persistirlos en DB y propagarlos end-to-end.
3. **Reconciliar el pacs.002 ACK** a un shape que sea trivial de mapear al real (`OrgnlMsgId, OrgnlEndToEndId, OrgnlUETR, TxSts` con códigos ISO `ACSC/ACSP/RJCT/PART/PDNG`).
4. **Eliminar el dual-canonical drift**: regenerar mappings/CSVs/canonical-fields.md para que coincidan con el código.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| A2 | **C** | `UETR` ausente (mandatorio pacs.008.001.10 — UUIDv4) |
| A3 | **C** | `ChrgBr` ausente (mandatorio v10 enum) |
| A4 | **C** | `IntrBkSttlmDt` ausente (mandatorio v10) |
| A5 | H | `TxId` marcado opcional cuando es mandatorio |
| A6 | H | `GrpHdr.InitgPty` ausente (CBPR+ mandatorio) |
| A7 | H | `GrpHdr.CtrlSum, TtlIntrBkSttlmAmt, SttlmInf.ClrSys` ausentes |
| A11 | H | `BICFI` opcional cuando debe ser mandatorio bajo `DbtrAgt/CdtrAgt` |
| A12 | M | Output etiquetado `pacs.008.001.08` cuando spec actual es `.001.10` |
| A14 | **C** | Dos canónicos discrepan en el repo (snake_case CSVs vs camelCase code) |
| A15 | **C** | pacs.002 ACK incompatible con códigos ISO reales |
| A1 | H | Snake_case + camelCase híbrido en el canónico |
| C57 | H | `status: z.string()` sin enum constraint |
| H2 | **C** | ADR-002 vs implementación (dos canónicos) |
| H8 | H | PaymentStatus 11 entries en spec, 14 en código |

---

## 3. Out of scope

- **NO** se agrega XML serialization a `canonical-to-iso20022-mx.ts` (sigue siendo JS object). Eso es opcional Bloque 2.
- **NO** se agregan `IntrmyAgt1/2/3` (correspondent banking). Documentado como limitación.
- **NO** se agrega `RgltryRptg, Tax, RltdRmtInf, SplmtryData, UltmtDbtr, UltmtCdtr`. Documentado como limitación.
- **NO** se cambia a XML literal. ADR-002 mantiene "JSON aligned to pacs.008".
- **NO** se toca FX (P05).
- **NO** se tocan adapters (P02/P03/P04).

---

## 4. Dependencias

- **Bloquea**: P02 (PIX), P03 (SPEI), P04 (Bre-B), P05 (FX), P10 (Testkit).
- **Depende de**: P09 (DB Schema) para agregar columnas `uetr UUID, charge_bearer CHAR(4), interbank_settlement_date DATE`. Coordinar — el SQL migrate de P09 sube primero.

---

## 5. Tareas detalladas

### 5.1 `mipit-core/src/domain/models/canonical.ts`
Schema Zod actual (~138 líneas) en `src/domain/models/canonical.ts`. Cambios:

- [ ] Agregar `pmtId.uetr: z.string().uuid()` (mandatorio, UUIDv4)
- [ ] Cambiar `pmtId.txId` a mandatorio (quitar `.optional()`)
- [ ] Agregar `chrgBr: z.enum(['DEBT','CRED','SHAR','SLEV']).default('SLEV')` a nivel `CdtTrfTxInf`
- [ ] Agregar `intrBkSttlmDt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/)` (ISODate)
- [ ] Agregar `grpHdr.initgPty: z.object({ name, id?, ctryOfRes? }).optional()` (CBPR+)
- [ ] Agregar `grpHdr.ctrlSum: z.number().optional()`
- [ ] Agregar `grpHdr.ttlIntrBkSttlmAmt: { value, currency }.optional()`
- [ ] Agregar `grpHdr.sttlmInf.clrSys.cd: z.string().optional()` (códigos como `'USABA'`, `'CHATS'`, etc.)
- [ ] Cambiar `status: z.string()` a `z.enum([...14 valores...])` — incluir todos los que aparecen en código: `RECEIVED, VALIDATED, CANONICALIZED, NORMALIZED, ROUTED, QUEUED, SENT_TO_DESTINATION, ACKED_BY_RAIL, COMPLETED, FAILED, REJECTED, DUPLICATE, COMPENSATING, COMPENSATED, DEAD_LETTER`
- [ ] Marcar `DbtrAgt.BICFI` y `CdtrAgt.BICFI` como `.required` cuando `origin.rail`/`destination.rail` requiera BIC (SWIFT, ISO20022_MX)

### 5.2 `mipit-core/src/canonical/pacs002.schema.ts`
Schema actual de 7 campos. Reemplazar:

```ts
{
  // GrpHdr
  msgId: z.string().max(35),
  creDtTm: z.string().datetime(),

  // OrgnlGrpInfAndSts
  orgnlMsgId: z.string().max(35),
  orgnlMsgNmId: z.literal('pacs.008.001.10'),
  orgnlCreDtTm: z.string().datetime().optional(),

  // TxInfAndSts
  orgnlInstrId: z.string().optional(),
  orgnlEndToEndId: z.string(),
  orgnlTxId: z.string().optional(),
  orgnlUetr: z.string().uuid(),
  txSts: z.enum(['ACSC','ACSP','RJCT','PART','PDNG']),
  stsRsnInf: z.object({
    rsn: z.object({ cd: z.string().optional(), prtry: z.string().optional() }),
    addtlInf: z.array(z.string()).optional()
  }).optional(),

  // MiPIT extensions (preservar)
  payment_id: z.string(),
  rail_tx_id: z.string().optional(),
  raw_response: z.unknown().optional(),
  processed_at: z.string().datetime()
}
```

- [ ] Mapper de status legacy → ISO: `ACCEPTED → ACSC`, `REJECTED → RJCT`, `ERROR → RJCT + StsRsnInf.AddtlInf='Transport error'`, `PENDING → PDNG`
- [ ] Cada vez que un adapter publique un ACK, debe llenar `orgnlEndToEndId, orgnlUetr` desde el canónico recibido

### 5.3 `mipit-core/src/pipeline/payment-pipeline.ts`
- [ ] Generar UETR en el `executePipeline()` step 1 si no viene en el request: `crypto.randomUUID()`
- [ ] Persistir UETR en `payments.uetr` columna
- [ ] Pasar UETR al canónico (`pmtId.uetr`)
- [ ] Generar `intrBkSttlmDt = new Date().toISOString().slice(0,10)` (UTC date al canonicalize)
- [ ] `chrgBr` se setea desde request o default `'SLEV'` (service level — instant rails)
- [ ] Validar canónico contra schema actualizado antes de routing

### 5.4 `mipit-core/src/api/schemas/payment-request.ts`
- [ ] Aceptar `chargeBearer?: 'DEBT'|'CRED'|'SHAR'|'SLEV'` opcional en el request
- [ ] Si no viene, default `'SLEV'`

### 5.5 `mipit-core/src/api/routes/payments.ts`
- [ ] Response GET `/payments/:id` debe incluir `uetr`, `charge_bearer`, `interbank_settlement_date`
- [ ] Response GET debe incluir todos los 14 statuses posibles

### 5.6 `mipit-core/src/translation/*`
Cada traductor que produce ACK (consumer-side) debe usar el nuevo shape pacs.002. Para outbound translators, NO requieren cambios en este plan (eso es P02/P03/P04).

### 5.7 `mipit-core/src/messaging/consumer.ts` (AckConsumer)
- [ ] Mapear el ACK del adapter al nuevo shape pacs.002 (con códigos ISO)
- [ ] Mantener compatibilidad: si el adapter envía `status: 'ACCEPTED'`, convertir a `txSts: 'ACSC'`
- [ ] Persistir `rail_ack` en DB con el shape ISO (cambiar JSONB content)
- [ ] **Mantener `rail_tx_id` extension** (no es ISO pero útil)

### 5.8 `mipit-core/src/canonical/wrapInDocument` y `canonical-to-iso20022-mx.ts`
- [ ] Actualizar namespace literal de `'urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08'` a `'urn:iso:std:iso:20022:tech:xsd:pacs.008.001.10'`
- [ ] Asegurar emit de UETR, ChrgBr, IntrBkSttlmDt

### 5.9 Renaming "pacs.008" → "pacs.008-derived"

**Archivos a actualizar** (literal find-and-replace coordinado):
- `mipit-core/src/domain/models/canonical.ts` — header comment
- `mipit-core/openapi/openapi.yaml` — descriptions
- `mipit-core/README.md`
- `mipit-docs/adrs/ADR-002-canonical-pacs008-json.md` — agregar sección "Limitations" explícita con lista de campos no soportados
- `mipit-docs/openapi/openapi.yaml` — description top-level: "Modelo canónico derivado de pacs.008.001.10 (subset pragmático). NO interoperable con sistemas ISO reales sin extensión."
- `mipit-docs/design/translation-layer.md` — header
- `mipit-docs/mappings/canonical-fields.md` — regenerar completamente (ver 5.11)
- `mipit-observability/grafana/dashboards/mipit-overview.json` — title/description
- `mipit-ui/src/app/translator/page.tsx:303` — label "Modelo Canónico (pacs.008)" → "Modelo Canónico (pacs.008-derived)"
- `mipit-ui/src/components/payments/message-inspector.tsx` — header del bloque canónico

### 5.10 ADR-002 — actualizar a "Limitations" explícitas

`mipit-docs/adrs/ADR-002-canonical-pacs008-json.md`. Agregar al final:

```markdown
## Limitations (auditoría 2026-05-16)

El modelo canónico es un **subset pragmático** de pacs.008.001.10. NO implementa
los siguientes elementos ISO mandatorios u opcionales relevantes; el proyecto
los emite como literales o los omite. Para cumplir compliance ISO real:

### Implementado
- `GrpHdr.{MsgId, CreDtTm, NbOfTxs, SttlmInf.SttlmMtd}`
- `CdtTrfTxInf.PmtId.{InstrId, EndToEndId, TxId, UETR}`
- `CdtTrfTxInf.{IntrBkSttlmAmt, IntrBkSttlmDt, ChrgBr}`
- `Dbtr/Cdtr.{Nm, PstlAdr.{Ctry, AdrLine}, Id (taxId), CtctDtls.{EmailAdr, PhneNb}}`
- `DbtrAcct/CdtrAcct.Id` (single string, no IBAN/Othr discriminator)
- `DbtrAgt/CdtrAgt.BICFI` (opcional)
- `Purp` (free string, no ExternalPurposeCode enum)
- `RmtInf.Ustrd`

### NO implementado (limitaciones documentadas)
- `GrpHdr.{BtchBookg, CtrlSum, TtlIntrBkSttlmAmt, InitgPty, InstgAgt, InstdAgt}`
- `GrpHdr.SttlmInf.{SttlmAcct, ClrSys.Cd (hard-coded por rail), InstgRmbrsmntAgt, InstdRmbrsmntAgt}`
- `CdtTrfTxInf.PmtTpInf.{InstrPrty, ClrChanl, SvcLvl.Cd, LclInstrm.Prtry (hard-coded), CtgyPurp}`
- `CdtTrfTxInf.{SttlmPrty, SttlmTmIndctn, SttlmTmReq, AccptncDtTm, PoolgAdjstmntDt}`
- `CdtTrfTxInf.{ChrgsInf, PrvsInstgAgt1-3, IntrmyAgt1-3, UltmtDbtr, UltmtCdtr}`
- `CdtTrfTxInf.{InstrForCdtrAgt, InstrForNxtAgt, RgltryRptg, Tax, RltdRmtInf, SplmtryData}`
- `Dbtr/Cdtr.{Id.PrvtId/OrgId structured, CtryOfRes}`
- `Dbtr/Cdtr.PstlAdr.{Dept, SubDept, StrtNm, BldgNb, BldgNm, Flr, PstBx, Room, PstCd, TwnNm, TwnLctnNm, DstrctNm, CtrySubDvsn}`
- `RmtInf.Strd`
- XML serialization (canonical emits JSON; `canonical-to-iso20022-mx.ts` returns
  a JS object wrapped in `{Document: {...}}`, not an XML string)
- XSD validation against ISO schemas
```

### 5.11 Reconciliar mapping CSVs

**Drift cubierto en H13/H14**. 5 archivos a regenerar:

- `mipit-docs/mappings/canonical-fields.md` — **borrar y regenerar** desde el Zod schema. Estructura: per-field table con columns `Field path`, `Type`, `Required`, `ISO 20022 equivalent`, `Notes`. Usar nested camelCase, NO flat snake_case.
- `mipit-docs/mappings/pix-to-canonical.csv` — regenerar contra `mipit-core/src/translation/pix-to-canonical.ts` real
- `mipit-docs/mappings/canonical-to-pix.csv` — idem
- `mipit-docs/mappings/spei-to-canonical.csv` — regenerar contra código actual
- `mipit-docs/mappings/canonical-to-spei.csv` — idem
- **Crear** `mipit-docs/mappings/breb-to-canonical.csv` y `canonical-to-breb.csv` (P04 los completa)
- **Crear** `mipit-docs/mappings/swift-mt103-{to,from}-canonical.csv`, `iso20022-mx-{to,from}-canonical.csv`, `ach-nacha-{to,from}-canonical.csv`, `fednow-{to,from}-canonical.csv`

### 5.12 OpenAPI spec — alinear con realidad

`mipit-docs/openapi/openapi.yaml`. Cambios mínimos para coherencia con P01 (no es rewrite total — eso es P12):

- [ ] `description` top-level: agregar disclaimer pacs.008-derived
- [ ] `POST /payments` response: `201 Created`, no 202
- [ ] `Rail` enum: `[PIX, SPEI, BRE_B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW]`
- [ ] `PaymentStatus` enum: 14 valores (agregar `CANONICALIZED, NORMALIZED, SENT_TO_DESTINATION, ACKED_BY_RAIL, COMPENSATING, COMPENSATED, DEAD_LETTER` a los existentes)
- [ ] `PaymentDetail` schema: agregar `uetr (uuid), charge_bearer (enum), interbank_settlement_date (date), trace_id (string)`

### 5.13 Migration SQL (depends on P09)

P09 agrega:
```sql
ALTER TABLE payments
  ADD COLUMN uetr UUID UNIQUE,
  ADD COLUMN charge_bearer CHAR(4) CHECK (charge_bearer IN ('DEBT','CRED','SHAR','SLEV')) DEFAULT 'SLEV',
  ADD COLUMN interbank_settlement_date DATE;

CREATE INDEX idx_payments_uetr ON payments(uetr) WHERE uetr IS NOT NULL;
```

---

## 6. Acceptance criteria

- [ ] `canonical.ts` schema incluye los 5 campos críticos nuevos y validan con Zod
- [ ] `pacs002.schema.ts` tiene los 9 campos ISO + 4 extensiones MiPIT
- [ ] Test unitario: dado un `CreatePaymentRequest` válido, el `executePipeline` produce un canónico con `uetr` UUID válido, `chrgBr` enum, `intrBkSttlmDt` ISODate
- [ ] Test unitario: dado un ACK del adapter con `status: 'ACCEPTED'`, el consumer lo persiste como `txSts: 'ACSC'`
- [ ] DB tiene columnas `uetr, charge_bearer, interbank_settlement_date` (verificar `\d payments` en psql)
- [ ] `GET /payments/:id` retorna los 3 campos nuevos
- [ ] OpenAPI describe `Rail` con 7 valores y `PaymentStatus` con 14
- [ ] `canonical-fields.md` está regenerado y coincide byte-a-byte con el output del schema Zod
- [ ] Los 4 CSVs PIX/SPEI están regenerados contra el código real
- [ ] ADR-002 tiene la sección "Limitations" agregada
- [ ] UETR generado en pipeline es el mismo a través de toda la cadena (pipeline → publish → adapter → ack → ack consumer)
- [ ] `validate:core` y `validate:suite` siguen siendo 11/11 verde
- [ ] `mipit-ui/src/__tests__/lib/constants.test.ts` ya no espera 11 statuses (pasa a 14)

---

## 7. Testing plan

### Unit tests nuevos (`mipit-core/test/unit/`)
- `test/unit/canonical/uetr-generation.test.ts` — generar UETR, validar UUIDv4
- `test/unit/canonical/charge-bearer.test.ts` — defaulting + propagation
- `test/unit/canonical/pacs002-status-mapping.test.ts` — ACCEPTED→ACSC, REJECTED→RJCT, ERROR→RJCT+addtl
- `test/unit/canonical/canonical-roundtrip-with-uetr.test.ts` — UETR preserved end-to-end

### Integration test
- `test/integration/canonical-with-iso-fields.test.ts` — POST /payments retorna 201, GET retorna uetr/charge_bearer/intrBkSttlmDt

### Validation suite
- Agregar checks 27-30 a `mipit-core/test/validation/run-core-validation.ts`:
  - check 27: response GET tiene `uetr` UUID válido
  - check 28: response GET tiene `charge_bearer` ∈ ['DEBT','CRED','SHAR','SLEV']
  - check 29: response GET tiene `interbank_settlement_date` formato YYYY-MM-DD
  - check 30: ACK persistido tiene `txSts` con código ISO

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Breaking change en `pacs002.schema.ts` rompe el consumer | Agregar shim: si el ACK no tiene `txSts`, mapear desde `status` legacy. Deprecar legacy en 2 semanas |
| UETR persistence falla si la columna no existe | P09 corre primero. CI debe asegurar migrations aplicadas antes de tests |
| Tests del UI fallan por enum cambio | P11 incluye actualizar `constants.test.ts` y `constants.ts` |
| OpenAPI mal formado rompe la doc render | Validar con `openapi-cli validate` antes de commit |

---

## 9. Commits sugeridos (orden)

1. `feat(canonical): add UETR (UUIDv4) to canonical schema and persist`
2. `feat(canonical): add ChrgBr and IntrBkSttlmDt with defaults`
3. `feat(canonical): tighten status enum + InitgPty + GrpHdr extras`
4. `refactor(canonical): rename pacs.008 → pacs.008-derived in docs and code`
5. `feat(ack): rewrite pacs002 schema to align with ISO codes (ACSC/ACSP/RJCT/PART/PDNG)`
6. `feat(consumer): map legacy ACCEPTED/REJECTED to ISO TxSts codes`
7. `docs(canonical-fields): regenerate from Zod schema (nested camelCase)`
8. `docs(mappings): regenerate PIX/SPEI CSVs against current translators`
9. `docs(adr-002): add Limitations section with non-supported elements`
10. `docs(openapi): correct status codes, rail enum, status enum, add new fields`

---

## 10. Notas para el dev

- **Filosofía**: el canónico sigue siendo "pragmático ISO 20022-aligned". No estamos persiguiendo XSD validation. Estamos persiguiendo que un examinador que abra `iso20022.org/pacs.008` y mire nuestro canónico no encuentre **incoherencias gritando**.
- **UETR es la clave**. Un UETR único per pago, propagado en cada mensaje (pacs.008 outbound, pacs.002 ack, eventual pacs.004 return). Tracking key universal.
- **ChrgBr default `'SLEV'`** porque pagos instantáneos retail son service-level (el cliente final no negocia comisiones).
- **`crypto.randomUUID()` siempre**, nunca `Math.random()`. Disponible en Node ≥14.17.
- Si encontrás conflictos al renombrar "pacs.008" → "pacs.008-derived", PRIORIZAR semántica: en código mantener `pacs.008` literal (compatibility), en doc/UI/ADR/OpenAPI usar "pacs.008-derived".
