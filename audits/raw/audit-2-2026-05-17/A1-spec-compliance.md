# A1 — Spec Compliance Deep (Audit 2)

**Fecha:** 2026-05-17 · **Branch:** `Auditoria-Claude` post-Wave 4 · **Scope:** ISO 20022 + PIX/SPEI/Bre-B/SWIFT updates 2024-2026.

> Nota: WebSearch/WebFetch denegadas en sesión del agente. Hallazgos `[VERIFY]` requieren validación contra docs oficiales cuando se restablezca acceso.

## 1. Confirmaciones de Wave 1-4 cerradas

| Hallazgo W1 | Estado | Evidencia |
|---|---|---|
| UETR con `Math.random()` | CERRADO | `payment-pipeline.ts:41` usa `randomUUID()` |
| PIX EndToEndId mal formado | CERRADO | `pix/types.ts:196-221` formato E+ISPB+BRT+CSPRNG 32 chars |
| `ChrgBr`/`IntrBkSttlmDt` ausentes | CERRADO | pipeline los estampa (`payment-pipeline.ts:43,107-116`) |
| Bre-B `idTransaccion` Math.random | CERRADO | `breb/types.ts:148-169` con `randomBytes` |
| SPEI `claveRastreo` con guión | CERRADO | `spei/types.ts:245-257` 1-30 alnum CSPRNG |
| FX COP con `Math.round(*100)/100` | CERRADO | `fx/currency-metadata.ts:32-72` banker's rounding |
| Rate-limit `acquire` dead code | CERRADO | invocado en `payment-pipeline.ts:170-176` |
| pacs.002 schema sin uso | PARCIAL | schema existe, consumer mapea legacy→TxSts pero **adapters no emiten pacs002 enriquecido** (N-001) |

## 2. Hallazgos NUEVOS — pacs.008.001.10

### N-001 CRÍTICO — adapters NO emiten `pacs002.txSts` aunque el schema lo soporta
- **WHERE:** `mipit-core/src/messaging/consumer.ts:76` + `mipit-adapter-{pix,spei,breb}/src/worker.ts:65-75/80/86`
- **WHAT:** Schema `pacs002.schema.ts` define `orgnlEndToEndId/orgnlUetr/txSts/stsRsnInf` opcional. Workers retornan solo `rail_ack.status: 'ACCEPTED'|'REJECTED'|'ERROR'`. Consumer cae siempre a `legacyStatusToTxSts()`.
- **EVIDENCE:** ISO 20022 pacs.002.001.10 `TxInfAndSts.TxSts [1..1]` con `ExternalPaymentTransactionStatus1Code` (ACSC/ACSP/RJCT/...). CBPR+ v9 §3.4 obliga `OrgnlUETR` para correlación cross-border.
- **FIX:** ~10 líneas por worker: construir `pacs002` con `{ msgId: ulid(), orgnlMsgId, orgnlEndToEndId, orgnlUetr, txSts: mapRailStatus(...), stsRsnInf: error ? {...} : undefined }`.

### N-002 ALTO — Rejection codes BACEN/CECOBAN/BREB crudos, sin mapping a ISO ExternalStatusReason1Code
- **WHERE:** `mipit-adapter-pix/src/pix/response-mapper.ts:32-37` + equivalentes SPEI/BREB
- **WHAT:** Códigos como `AB03/AC01/AM04/RR04/BE01/DS04` (BACEN), `R01-R09/LIM/BLQ/CAN` (CECOBAN), `BREB001-005` (inventado) se persisten crudos. ISO ExternalCodeSets 2024-05 publica `ExternalStatusReason1Code` con ~80 valores (AC01/AC04/AG01/AM04/FF01/MS03/NARR...). CBPR+ exige `Rsn.Cd` ISO y `Rsn.Prtry` para propietario.
- **FIX:** `mipit-core/src/translation/rail-rejection-mapping.ts` con 3 mapas. Output: `stsRsnInf.rsn = { cd: isoCd, prtry: railCd }`.

### N-003 ALTO — `CtgyPurp` (Category Purpose) no se modela; PIX `tipo` y SPEI `tipoPago` se pierden
- **WHERE:** `canonical.ts:213` (`purpose: z.string().max(35).default('P2P')`); `mipit-adapter-spei/src/spei/mapper.ts:99` (`tipoPago: 1` hardcodeado)
- **WHAT:** Sin `ctgyPurp` para `CdtTrfTxInf.PmtTpInf.CtgyPurp.Cd`. PIX `tipo` (TRANSF/COBR/DBOL/DEVOL) y SPEI `tipoPago` (1..30: tercero, nómina, impuesto, tarjeta débito...) viven en wire-format pero no en canónico. Mapper SPEI hardcodea 1 → todo flujo es "tercero-a-tercero" aunque sea nómina.
- **EVIDENCE:** ISO ExternalCategoryPurpose1Code (CASH/CORT/DVPM/INTC/SALA/SUPP/TAXS/TRAD); CBPR+ v9 §4.7; PIX Manual de Padrões §2.4.1; Banxico SPEI Manual §4 catálogo 30 valores.
- **FIX:** `canonical.ts` agregar `ctgyPurp: z.string().max(4).optional()`. PIX-to-canonical mapea `TRANSF→CASH`, `COBR→TRAD`, `DEVOL→OTHR`. Canonical-to-SPEI lee `ctgyPurp` y elige `tipoPago`.

### N-004 ALTO — `LclInstrm.Prtry` hardcodeado y faltante en 5/6 emisores
- **WHERE:** `canonical-to-fednow.ts:151` emite `LclInstrm: { Prtry: 'INST' }` ✓; faltan en `canonical-to-{pix,spei,breb,iso20022-mx,swift-mt103,ach-nacha}.ts`
- **EVIDENCE:** CBPR+ Usage Guidelines v9 §4.10; ISO ExternalLocalInstrument1Code (INST/RTGS/SDVA); BACEN Res. 1/2020 = `PIX`; CECOBAN §2.3 = `SPEI`.
- **FIX:** Agregar `lclInstrm: z.object({ cd, prtry }).optional()` al canónico. Cada emitter setea el suyo. Default `INST` para rieles instantáneos LATAM.

### N-005 ALTO — `nbOfTxs/ctrlSum/ttlIntrBkSttlmAmt` declarados pero NO poblados
- **WHERE:** `payment-pipeline.ts:104-116` no toca `grpHdr`. `spei-to-canonical.ts:108` omite `nbOfTxs`. `ctrlSum` y `ttlIntrBkSttlmAmt` jamás se setean.
- **EVIDENCE:** ISO pacs.008.001.10 `GrpHdr.NbOfTxs [1..1]` mandatorio; CBPR+ v9 §4.2.1 obliga `CtrlSum = Σ IntrBkSttlmAmt.value`.
- **FIX:** Pipeline después de UETR/ChrgBr: `canonical.grpHdr.nbOfTxs = 1; canonical.grpHdr.ctrlSum = canonical.amount.value;`.

### N-006 ALTO — `XchgRate` como string plano, no objeto ISO con `UnitCcy/RateTp/CtrctId`
- **WHERE:** `canonical-to-iso20022-mx.ts:75`: `XchgRate: canonical.fx?.rate ? String(canonical.fx.rate) : undefined`
- **EVIDENCE:** ISO 2024 maintenance: `XchgRate` es objeto `ExchangeRate1` con `UnitCcy/XchgRate(Decimal)/RateTp(SPOT|SALE|AGRD)/CtrctId`. CBPR+ obliga `RateTp` para auditoría fiscal de FX. Banxico Circular 100/2019 art. 5 §III, BACEN Circular 3.691 requieren declarar tipo de tasa para transferencias >USD 10k.
- **FIX:** Promover `canonical.fx` a `XchgRateInformation`-shaped.

### N-007 MEDIO — `RgltryRptg` ausente; sin tracking threshold USD 10k
- **EVIDENCE:** BACEN Carta-Circular 3.598/2022 (SISBACEN); Banxico Circular 100/2019 art. 5 (`tipoConcepto` regulatorio); SARLAFT Colombia.
- **FIX:** Middleware `regulatory-threshold.ts` que detecta `amount >= USD-equivalent-of-10000`, stamp en audit + `regulatory_flagged: true`.

### N-008 MEDIO — `IntrmyAgt1/2/3` ausentes; flujos corresponsales >2 hops no representables
- **EVIDENCE:** CBPR+ v9 §3.1.1 obliga `IntrmyAgt1` para correspondent banking ≥2 hops.
- **FIX:** Scope-out aceptable si LIMITATIONS lo nota; o agregar slot `intrmyAgt: z.array(...).max(3).optional()`.

### N-009 MEDIO — `UltmtDbtr/UltmtCdtr` ausentes; PSPs fintech mal modelados
- **EVIDENCE:** BanRep Bre-B TR-002 §4.2 (SEDPE Nequi/Daviplata en custodia); `UltmtDbtr` es la referencia ISO.
- **FIX:** Scope-out documentable o agregar `ultmtDbtr/ultmtCdtr: { name, taxId, country }.optional()`.

### N-010 BAJO — `ChrgsInf` ausente; `ChrgBr` se setea sin monto detallado
- **EVIDENCE:** CBPR+ v9 §4.6.
- **FIX:** Scope-out aceptable (PoC LATAM instantáneo casi siempre SLEV).

### N-011 BAJO — `mappings/canonical-fields.md` stale (W4 no lo actualizó)
- **WHERE:** describe `msg_id/creation_date_time/number_of_txs/settlement_method/instructing_agent/debtor.alias` — no existen.
- **FIX:** Regenerar desde Zod o eliminar (ADR-002 está al día).

### N-012 MEDIO — BREB drift: core usa 8-dig legacy, adapter usa 4-dig oficial
- **WHERE:** `mipit-core/src/translation/breb-to-canonical.ts:99-109` (`00000007`); `mipit-adapter-breb/src/breb/types.ts:105-122` (`0007`)
- **EVIDENCE:** Catálogo Superfinanciera (4 dígitos vigente).
- **FIX:** Unificar en `SUPERFIN_ENTITY_CODES` 4 dígitos.

### N-013 MEDIO — Bre-B `ALIAS` regex mismatch entre core y adapter
- **WHERE:** `breb-to-canonical.ts:129` infiere sin `@`; `mapper.ts:75` exige `@`. Un alias `123456789` puede ser clasificado como CC en core pero rechazado por adapter.
- **EVIDENCE:** BanRep TR-002: alias siempre `@xxx`.
- **FIX:** Unificar regla: `^@[A-Za-z0-9._]{3,19}$`. Si llega sin `@`, marcar `ALIAS` solo si no matchea otro tipo.

### N-014 MEDIO — `canonical-to-pix.ts` stub reusa `endToEndId` raw
- **WHERE:** `mipit-core/src/translation/canonical-to-pix.ts:20` (`endToEndId: canonical.pmtId.endToEndId`)
- **WHAT:** Si canónico viene de SPEI, e2eId es `E2E-${ulid()}` (no formato SPI). Mock rechaza con regex `/^E\d{8}\d{12}[A-Za-z0-9]{11}$/`. El adapter pix `mapper.ts:63` regenera correctamente; el stub queda divergente.
- **FIX:** Llamar `generatePixEndToEndId(canonical.origin.ispb)` o reusar `canonicalToPixPayload` del adapter (vía paquete compartido).

### N-015 BAJO — `status` enum mezcla 15 estados internos pipeline con ISO
- **WHERE:** `canonical.ts:15-32,219` incluye `RECEIVED/VALIDATED/CANONICALIZED/NORMALIZED/ROUTED/QUEUED` (FSM interna) con `COMPLETED/REJECTED/...` (ISO).
- **FIX:** Separar `canonical.status` (FSM interna) de `canonical.txSts` (ISO).

### N-016 MEDIO — `pacs002.schema.ts:55` solo acepta pacs.008.001.10/.08
- **WHAT:** `z.literal('pacs.008.001.10').or(z.literal('pacs.008.001.08'))`. ISO Maintenance Release May 2024 publica `.12`. Forward-compat broken.
- **FIX:** `z.string().regex(/^pacs\.008\.001\.\d{2}$/)`.

## 3. Mensajería complementaria

### M-001 ALTO — pacs.002 nunca emitido al exterior
- **WHERE:** `consumer.ts:43-163` persiste ACK en DB + webhooks/SSE pero no produce mensaje pacs.002 estructurado exportable.
- **IMPACT:** Limita claim "MIPIT habla pacs.002" — solo habla JSON propietario interno.
- **FIX:** Endpoint `GET /payments/:id/pacs.002` o publish a exchange `payments.acks.pacs002`.

### M-002 ALTO — `/compensate` no emite pacs.004
- **WHERE:** `compensation-service.ts:73-87` comenta "In production: pacs.004" pero solo cambia estado DB.
- **EVIDENCE:** ISO pacs.004.001.09: `RtrId [1..1]`, `OrgnlMsgId`, `OrgnlEndToEndId`, `OrgnlUETR`, `RtrdIntrBkSttlmAmt`, `RtrRsnInf.Rsn` con `ExternalReturnReason1Code`.
- **IMPACT:** Saga compensation claim no se sostiene técnicamente.
- **FIX:** Crear `pacs004.schema.ts`; construir pacs.004 desde `payment.canonical_msg` y publicar a `payments.returns`.

### M-003 MEDIO — camt.054 (BankToCustomerDebitCreditNotification) ausente
- **EVIDENCE:** ISO camt.054.001.08; CBPR+ v9 §6.
- **FIX:** Scope-out aceptable o ~1 día de esfuerzo.

### M-004 BAJO — Reconciliation read-only, no consume camt.053
- **WHERE:** `reconciliation/reconciliation-service.ts`
- **FIX:** Scope-out aceptable (cubierto LIMITATIONS §4).

## 4. Por riel (updates 2024-2026)

### R-001 ALTO [VERIFY] — Pix Automático + Pix Garantido no modelados
- **EVIDENCE:** BCB Res. 304/2023, GA jun-2024. PIX Manual §4.5 Q1-2024.
- **WHAT:** Sin `RecurrentPaymentInformation/Frequency/PaymentMandate/MandateRelatedInfo`. `PixTipoTransacao` solo TRANSF/COBR/DBOL.
- **FIX:** Scope-out documentable o agregar `mandateInfo`.

### R-002 MEDIO — MED (Mecanismo Especial de Devolução) no modelado como flujo
- **EVIDENCE:** BCB Res. 103/2021 + 215/2022.
- **WHAT:** Mock menciona "tipo enum extended with DEVOL" pero no flujo SLA 80 días, motivos FRAU/FAIL/REFD.

### R-003 BAJO — PIX límite BRL 1k PF / 20k PJ no chequeado por cnpj vs cpf
- **WHERE:** `pix/mock-server.ts:199-204` solo si `ENFORCE_HOURS=true`.
- **EVIDENCE:** BCB Res. 142/2021 art. 3.

### R-004 BAJO — Mock sin `/v2/dict/{key}` ni `/v2/pix/{e2eid}/devolucao`
- **FIX:** Scope-out documentado.

### R-005 ALTO [VERIFY] — DiMo (Dinero Móvil, Banxico oct-2024) no modelado
- **WHAT:** DiMo permite SPEI vía celular; `tipoCuentaBeneficiario=10` (Phone-linked) + `aliasCelular` resuelto contra catálogo nacional. Adapter SPEI solo trabaja con tipo=40 (CLABE).
- **EVIDENCE:** Banxico Comunicado oct-2024 + DiMo Especificación Técnica v1.0.

### R-006 MEDIO [VERIFY] — `isSpeiWindowOpen()` aún L-V 07:00-17:30 CST (legacy)
- **WHERE:** `spei/mock-server.ts:14,64-73,192-198`
- **EVIDENCE:** SPEI migró a 24/7 desde 2023 (Banxico Circular 14/2017 enmienda 17/2023).
- **FIX:** Cambiar a `return true` por default.

### R-007 BAJO — `SPEI_BANXICO_CODES.MIPIT_SIM='90999'` colisiona con rango PSPs autorizados
- **WHERE:** `spei/types.ts:191`. Rango 90xxx es reservado a IFS autorizadas (STP=90646).
- **FIX:** Cambiar a 99xxx.

### R-008 MEDIO — SPEI `tipoPago: 1` hardcoded
- Ver N-003. Mismo fix.

### R-009 ALTO — Bre-B 100% guessed; header de `breb-to-canonical.ts:18-24` miente "(BanRep spec)"
- **WHERE:** `mipit-adapter-breb/src/breb/types.ts:1-25` declara honestamente "EDUCATED GUESSES, not BanRep-verified". Pero `breb-to-canonical.ts:18-24` dice "(BanRep spec)" para BREB001-005 inventados.
- **FIX:** Corregir header a "(MIPIT-invented, NOT BanRep)". Validar contra TR-002 cuando recupere acceso a internet.

### R-010 ALTO [VERIFY] — Bre-B debería emitir códigos ISO derivados
- **WHERE:** `mock-server.ts:233-269` produce BREB001/004/002/005 inventados.
- **EVIDENCE:** TR-002 v1.1 (oct-2025) referencia `ExternalStatusReason1Code` ISO.
- **FIX:** Mapear `BREB001→AM04`, `BREB002→BE01`, `BREB003→AM02`, `BREB004→AC01`, `BREB005→MS03`.

### R-011 MEDIO — Bre-B directorio (alias→PSP) no existe en adapter
- **WHAT:** Asume `destination.ispb` ya resuelto. BanRep tiene directorio central tipo DICT brasileño.
- **FIX:** Scope-out documentable o stub `GET /breb/v1/directorio/{llave}` con mapa hardcoded.

### R-012 BAJO — BREB límites COP inventados
- **WHERE:** `mipit-adapter-breb/src/breb/mock-server.ts:55-56` (`LIMIT_NATURAL_COP=20M`, `LIMIT_JURIDICA_COP=200M`).
- **FIX:** Comentar "illustrative, not BanRep-mandated".

### R-013 MEDIO — FedNow translator aplica FX pero FedNow es USD-domestic-only
- **WHERE:** `canonical-to-fednow.ts:30-33`
- **EVIDENCE:** Federal Reserve Operating Procedures v3.0 §3.1.
- **FIX:** Throw `TranslationError` si `canonical.amount.currency !== 'USD'`, o documentar que asume on-ramp USD previo.

### R-014 MEDIO — `canonical-to-swift-mt103.ts:56` hardcodea `detailsOfCharges: 'SHA'`
- **WHAT:** No respeta `canonical.chrgBr`. Mapeo correcto: `DEBT→OUR`, `CRED→BEN`, `SHAR→SHA`, `SLEV→omit-o-SHA`.
- **FIX:** 4 líneas `const map = { DEBT: 'OUR', CRED: 'BEN', SHAR: 'SHA', SLEV: 'SHA' };`.

### R-015 MEDIO — NACHA padding bugs persisten
- **WHERE:** `canonical-to-ach-nacha.ts:103,108,115,131,137` con `'0'.repeat(9).substring(0,10)` = 9 chars
- **EVIDENCE:** NACHA Operating Rules 2025 §3.1 (94 chars exactos).
- **FIX:** `padStart(10, '0')` + fixture test contra ejemplo real.

## 5. Top-5 acciones (~3.5 días para sustentación defendible)

| # | Acción | Días | Impacto |
|---|---|---|---|
| 1 | N-001+N-002: adapters emiten `pacs002` enriquecido + mapping códigos ISO | 1.0 | MUY ALTO |
| 2 | M-002: `/compensate` emite pacs.004 real con schema | 1.0 | ALTO |
| 3 | N-003+R-008: `ctgyPurp` propagado canónico→SPEI | 0.5 | ALTO |
| 4 | LIMITATIONS.md update con todos los nuevos scope-out (R-001/R-002/R-005/R-010/R-011/R-013/M-003/N-007/N-008/N-009) | 0.5 | ALTO |
| 5 | Fidelity fixes: N-005 nbOfTxs/ctrlSum + N-006 XchgRate objeto + N-004 LclInstrm + R-014 MT103 chrgBr | 0.5 | MEDIO-ALTO |

## Apéndice — Verificaciones externas pendientes [VERIFY]

1. ISO 20022 pacs.008.001.12 (Maintenance May 2024)
2. PIX Manual de Padrões v3.0 (Q3-25)
3. Banxico SPEI 24/7 (Circular 14/2017 enmiendas)
4. BanRep Bre-B TR-002 v1.1 + posibles TR-003
5. CBPR+ Usage Guidelines v9 (Nov 2025)
6. FedNow Service Operating Procedures v3.0
7. NACHA Operating Rules 2025
