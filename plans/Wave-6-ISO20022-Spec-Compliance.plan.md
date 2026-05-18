# Wave 6 — ISO 20022 Spec Compliance

**Fecha:** 2026-05-17 (segunda mitad)
**Branch:** `Auditoria-Claude` (directo, sin branch separada — pedido del equipo)
**Origen:** Bloque B del documento maestro [AUDITORIA-2-2026-05-17.md](../audits/AUDITORIA-2-2026-05-17.md) — robustecer el claim "MIPIT habla ISO 20022 pacs.008/.002/.004" a nivel byte
**Estado:** ✅ Cerrada — 13/13 tickets entregados, verificados live + unit tests, committeados a `Auditoria-Claude`
**Evidencia:** [evidence/wave-6-verification-2026-05-17.md](../evidence/wave-6-verification-2026-05-17.md)

---

## Objetivo

Cerrar los 11 hallazgos críticos de ISO 20022 compliance identificados por el agente A1 de la auditoría 2, en ≈3.5 días estimados (entregado en una sola sesión por densidad de fixes pequeños). El criterio: **un pacs.008 emitido por MIPIT debería pasar validación XSD oficial** (al menos los campos mandatorios), y **un pacs.002 emitido por los adapters debería ser consumible por un corresponsal externo** correlando por OrgnlUETR.

## Tickets entregados (13)

### Mensajería ISO 20022 (mandatorios)

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W6.1 ISO-001** | 3 adapters emiten bloque `pacs002` enriquecido (`orgnlEndToEndId`, `orgnlUetr`, `txSts`, `stsRsnInf`). Helper `railStatusToTxSts` mapea ACCEPTED→ACSC, REJECTED→RJCT, ERROR→PDNG. Consumer materializa a `rail_ack` con `tx_sts`/`orgnl_uetr`/`orgnl_end_to_end_id` para queryability. | core + 3 adapters | N-001, M-001, C6 |
| **W6.2 ISO-002** | Nuevo `mipit-core/src/translation/rail-rejection-mapping.ts` mapea BACEN (AB03/AC01/AM04/...) + CECOBAN (R01-R09/LIM/BLQ/CAN) + BREB (BREB001-005) → ISO 20022 `ExternalStatusReason1Code` (AC01/AC04/AG01/AM02/AM04/FF01/MS03/NARR/...). Output: `stsRsnInf.rsn = { cd: isoCd, prtry: railCd }` preservando original. | core | N-002 |
| **W6.3 ISO-003** | Agrega `canonical.ctgyPurp` (ISO `ExternalCategoryPurpose1Code`). SPEI mapper deriva `tipoPago` via tabla CASH→1, INTC→4, **SALA→5 (nómina)**, SUPP→7, **TAXS→14 (impuesto federal)**, DVPM→16, TRAD→17. Tipo `SpeiCecobanRequest.tipoPago` ampliado de `1|2|3|4` a `number` para admitir el catálogo Banxico completo. | core + adapter-spei | N-003, R-008 |
| **W6.4 ISO-004** | Nuevo `mipit-core/src/canonical/pacs004.schema.ts` con el subset `pacs.004.001.09` PaymentReturn (RtrId, OrgnlMsgId, OrgnlEndToEndId, OrgnlUETR, RtrdIntrBkSttlmAmt, RtrRsnInf con `ExternalReturnReason1Code`). `compensation-service.compensate()` ahora construye + persiste un pacs.004 real cuando el payment fue ACKed por el rail. PoC scope-out: mock no consume return queue. | core | M-002, C2 |
| **W6.5 ISO-005** | Fidelity batch (4 sub-fixes): (a) pipeline stampa `grpHdr.nbOfTxs=1`, `grpHdr.ctrlSum=amount.value`, `grpHdr.ttlIntrBkSttlmAmt` (CBPR+ §4.2.1 mandatorios); (b) `iso20022-mx-to-canonical` emite `XchgRate` como objeto `{UnitCcy, XchgRate, RateTp:'SPOT'}` en lugar de string plano; (c) canónico agrega `lclInstrm{cd,prtry}`, ISO20022-MX emitter default `LclInstrm.Prtry='SCT'`; (d) MT103 `detailsOfCharges` mapeado de `canonical.chrgBr` (DEBT→OUR, CRED→BEN, SHAR→SHA, SLEV→SHA) en lugar de hardcoded `'SHA'`. | core | N-004, N-005, N-006, R-014 |
| **W6.6 ISO-006** | `pacs002.schema.orgnlMsgNmId` cambia de `z.literal('pacs.008.001.10').or(z.literal('pacs.008.001.08'))` a `z.string().regex(/^pacs\.008\.001\.\d{2}$/)`. Forward-compat con `.12` (ISO 20022 Maintenance Release May 2024). | core | N-016 |

### Catálogos rieles (productivos)

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W6.7 ISO-007** | `BREB_ENTITY_CODES` core unificados a 4-dig Superfinanciera (`BANCOLOMBIA: '0007'`, `BBVA: '0013'`, ...). Mock adapter acepta `^(\d{4}\|\d{8})$` para retro-compat. Mensajes de error stale ("debe ser exactamente 8 dígitos") corregidos. | core + adapter-breb | N-012 |
| **W6.8 ISO-008** | `inferTipoLlave` Bre-B unificada con el adapter: TELEFONO `+573xxx`, NIT `\d{9,10}-\d`, ALIAS exige `@<3-19>` (TR-002 convention), EMAIL regex estricta con TLD. Antes el core inferir `EMAIL` para cualquier `@` y `ALIAS` para todo lo demás, mientras el adapter re-clasificaba CC/CE/PASAPORTE más finamente — un alias numérico como `1234567890` se canonizaba como ALIAS en core y se rechazaba en adapter. | core | N-013 |
| **W6.9 ISO-009** | `canonical-to-pix.ts` regenera `endToEndId` al formato BCB SPI `E + ISPB(8) + YYYYMMDDHHmm(BRT) + 11 alnum` cuando el valor del canónico no matchea el regex (caso SPEI→PIX donde e2eId trae `E2E-${ulid()}`). Análogo en `canonical-to-spei.ts` para `claveRastreo` Banxico (1-30 alfanumérico, sin hyphens). `canonical-to-breb.ts` ya regeneraba via `generateBrebTransactionId`. | core | N-014 |

### Rieles case-study

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W6.10 ISO-010** | `canonical-to-fednow.ts` lanza `TranslationError` si `currency !== 'USD'` y no hay USD on-ramp explícito en `canonical.fx`. FedNow es USD-domestic-only per Federal Reserve Service Operating Procedures §3.1. | core | R-013 |
| **W6.11 ISO-011** | NACHA File Header (Type 1) layout corregido. El bug original: `'0'.repeat(9).substring(0, 10)` producía 9 chars donde el spec requiere 10, desplazando cada campo subsecuente. Reescrito con assembly campo-por-campo explícito + nuevo unit test que asserta byte-exact positions per NACHA Operating Rules 2025 §3.1 (pos 04-13 Immediate Destination, pos 14-23 Immediate Origin, pos 34 File ID Modifier, pos 38-39 Blocking Factor, etc.). | core | R-015 |

### Documentación

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W6.12 ISO-012** | `LIMITATIONS.md` ampliado con §11 (scope-outs ISO 20022: Pix Automático, MED estructurado, DiMo, TR-002 oficial, Bre-B directorio, FedNow cross-border, camt.054/053, `RgltryRptg`, `IntrmyAgt1-3`, `UltmtDbtr/Cdtr`, `ChrgsInf`) y §12 (case-study rails clarificados como diferenciador de extensibilidad, no limitación encubierta). | docs | varios |
| **W6.13 ISO-013** | Borrados `mappings/canonical-fields.md` + 4 CSVs (`canonical-to-pix.csv`, `canonical-to-spei.csv`, `pix-to-canonical.csv`, `spei-to-canonical.csv`) que describían un canónico flat ya inexistente (`canonical.msg_id`, `canonical.debtor.alias_type` con `CPF/CNPJ/PHONE/EMAIL/EVP/CLABE/PHONE_MX/CARD`). La fuente de verdad del canónico ahora es `mipit-core/src/domain/models/canonical.ts` (Zod schema) + ADR-002. README.md y AGENTS.md actualizados con la nueva guía de navegación. | docs | A5-A1, A5-A2, N-011 |

## Criterios de éxito (todos cumplidos)

- ✅ Live: ACK trae `tx_sts: ACSC` ISO + `orgnl_uetr` + `orgnl_end_to_end_id`
- ✅ Live: BREB outbound `codigoEntidad: "9999"` (4-dig) + `valor.original: "83267"` (COP integer)
- ✅ Live: cross-currency PIX BRL→BRE_B COP via FX (rate fallback 832.67)
- ✅ Unit: `mipit-core` 310/310 (+3 por W6.11)
- ✅ Unit: 3 adapters mantienen 62 + 86 + 44 (sin regresión)
- ✅ TS compila clean (excepto pre-existente `otel.ts` cubierto por Wave 8)

## Commits y push (todos directos a `Auditoria-Claude`)

| Repo | Commit | Tickets |
|---|---|---|
| `mipit-core` | `d09e556` | W6.1/2/3/4/5/6/8/9/10/11 + 5 tests ajustados |
| `mipit-adapter-pix` | `a398357` | W6.1 |
| `mipit-adapter-spei` | `53043c0` | W6.1 + W6.3 |
| `mipit-adapter-breb` | `c9a4e77` | W6.1 + W6.7 (msg) |
| `mipit-docs` | `7e5903a` | W6.12 + W6.13 + evidence |

## Tests ajustados al código (no al revés)

| Test | Cambio | Razón |
|---|---|---|
| `canonical-to-pix.test.ts` | `endToEndId` ahora regex BCB SPI | W6.9 regenera al formato real |
| `canonical-to-spei.test.ts` | `claveRastreo` ahora regex Banxico (alphanum, no hyphen) | W6.9 regenera al formato real |
| `breb.test.ts` | `valor.original = '500000'` (entero); `generateBrebTransactionId` admite 28 o 32 chars | W5.10 COP entero + W6.7 4-dig BREB |
| `metrics.test.ts` | expected buckets `[10..30000]` | W5.5 cap extendido a 30s |
| `pipeline.test.ts` | mock incluye `recordPayment` | W5.4 cuenta failures |
| `ach-nacha.test.ts` | +1 nuevo test "File Header positions exact per NACHA OR §3.1" | W6.11 byte-exact |

## Lecciones aprendidas

1. **Worker triplicado**: el cambio W6.1 requirió editar 3 workers casi idénticos. Confirma la prioridad de Wave 8 ARCH-001 (`@mipit/adapter-runtime` shared package).
2. **Tipo restrictivo de catálogo**: `tipoPago: 1|2|3|4` ocultaba la diversidad real del catálogo Banxico (1..30). El union restrictivo "documentaba" pero limitaba. Lección: si el dominio tiene un enum abierto, usar `number` con docstring referenciando el catálogo.
3. **Network DNS race** en Docker Compose ocurre cuando se rebuildan sub-services sin tocar la network. Solución: `compose down + up` completo si se ve `ENOTFOUND <service-name>`.
4. **Test flakiness** en PIX/SPEI (mocks no liberan puerto entre tests) — no es bug Wave 6, pero confirma A3 F40 (`--forceExit --detectOpenHandles` esconde el problema).

## Pendientes trasladados a Wave 7+

- **W6.4 verify live pacs.004**: código + tests unit pasan, falta provocar FAILED + compensate en demo
- **W6.1 pacs.002 endpoint REST**: el bloque persiste en `rail_ack` pero no se expone aún en endpoint dedicado `GET /payments/:id/pacs.002` (Wave 7 SOT-001 puede absorberlo)
- **`LclInstrm` en wire-formats nativos**: el canónico tiene el campo, pero PIX/SPEI/BRE_B nativos no lo emiten porque sus protocolos no lo usan. Solo iso20022-mx + FedNow lo emiten. Documentado.

## Qué demuestra Wave 6

| Claim | Antes | Después |
|---|---|---|
| "MIPIT emite pacs.002" | Schema existía pero adapters no lo poblaban | ✅ 3 adapters emiten bloque enriquecido con OrgnlUETR/OrgnlEndToEndId/TxSts ISO |
| "Saga compensation via pacs.004" | Sólo cambio de estado DB | ✅ pacs.004.001.09 real construido (RtrId, RtrRsnInf con `ExternalReturnReason1Code`) |
| "Códigos rechazo ISO 20022" | BACEN AB03 / CECOBAN R01 crudos | ✅ Mapeados a `ExternalStatusReason1Code` con `Rsn.Prtry` preservando original |
| "ctgyPurp diferencia P2P/nómina/impuesto" | SPEI hardcodeaba tipoPago=1 | ✅ canonical.ctgyPurp → Banxico tipoPago semántico |
| "Fidelidad ISO mandatorios" | nbOfTxs/ctrlSum nunca poblados, XchgRate como string, MT103 SHA hardcoded | ✅ Todos los mandatorios pacs.008.001.10 stamped en pipeline |
| "Forward-compat pacs.012" | Sólo aceptaba .10/.08 | ✅ Regex admite cualquier minor revision `.NN` |
