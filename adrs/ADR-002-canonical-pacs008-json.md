# ADR-002: Modelo canónico basado en pacs.008-derived (JSON)

**Estado**: Aceptado (revisado 2026-05-16 por Auditoría Claude)
**Fecha**: 2026-03-01 · **Revisión**: 2026-05-16
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

Se necesita una "lengua franca" para representar instrucciones de crédito
entre rieles heterogéneos (PIX, SPEI, Bre-B, y los 4 traductores Option-A).

## Decisión

Usar **un modelo derivado de pacs.008.001.10** ("pacs.008-derived") como base
del modelo canónico, representado en **JSON interno** (no XML ISO literal),
pero alineado semánticamente a la estructura de pacs.008.

Para respuestas/confirmaciones del riel destino, se define un modelo
**derivado de pacs.002.001.10** que carry los campos ISO `OrgnlEndToEndId`,
`OrgnlUETR`, `TxSts` con códigos `ACSC/ACSP/RJCT/PART/PDNG`.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| XML ISO 20022 literal | Estándar real, interoperable | Verboso, parsing complejo, overhead para PoC |
| JSON schema propio sin ISO | Simple, libre | Sin fundamento estándar, difícil de justificar |
| **JSON alineado a pacs.008-derived** | Balance entre estándar y pragmatismo | No interoperable con sistemas ISO reales sin extensión |
| Protocol Buffers | Eficiente, tipado | Overhead de tooling, menos legible |

## Razones

- pacs.008 encaja naturalmente con "transferencia de crédito entre rieles"
- JSON es más ergonómico que XML para el PoC y la UI
- La alineación semántica permite documentar el mapeo ISO 20022
- pacs.002-derived permite representar ACSC/RJCT/PDNG del riel con códigos ISO

## Consecuencias

- No se valida contra XSD ISO 20022 real (solo subset)
- El modelo canónico es propio del middleware (no interoperable con sistemas ISO reales)
- Se documenta como limitación aceptada del PoC (sección "Limitations" abajo)

---

## Limitations (revisión 2026-05-16)

El modelo canónico es un **subset pragmático** de pacs.008.001.10. Esta lista
es la fuente de verdad para defender qué se implementó y qué no.

### Implementado

**GrpHdr**:
- `MsgId` (max 35)
- `CreDtTm` (ISODateTime)
- `NbOfTxs` (numeric, default 1)
- `SttlmInf.SttlmMtd` (enum INDA/INGA/COVE/CLRG)
- `SttlmInf.ClrSys.{Cd, Prtry}` (opcional — usado por FedNow para `USABA`)
- `InitgPty.{name, id, ctryOfRes}` (opcional, CBPR+)
- `CtrlSum` (opcional)
- `TtlIntrBkSttlmAmt.{value, currency}` (opcional)

**CdtTrfTxInf**:
- `PmtId.InstrId, EndToEndId, TxId, UETR` — los 4 IDs ISO (UETR es UUIDv4)
- `IntrBkSttlmAmt.{value, currency}` con currency ISO 4217
- `IntrBkSttlmDt` (ISODate, MANDATORIO)
- `ChrgBr` (DEBT/CRED/SHAR/SLEV, MANDATORIO, default SLEV)
- `InstdAmt` (opcional, original currency pre-FX)
- `XchgRate` (opcional)
- `DbtrAgt/CdtrAgt.FinInstnId.{BICFI, ClrSysMmbId.MmbId}`
- `Dbtr/Cdtr.{Nm, PstlAdr.{Ctry, AdrLine[]}, Id (taxId flat), CtctDtls.{EmailAdr, PhneNb}}`
- `DbtrAcct/CdtrAcct.Id` (single string — no IBAN/Othr structural discrimination)
- `Purp.Cd` (free string, no ExternalPurposeCode enum enforcement)
- `RmtInf.Ustrd` (free-form, max 140 chars)

### NO implementado (limitaciones documentadas)

**GrpHdr**:
- `BtchBookg` (BatchBooking)
- `InstgAgt, InstdAgt` (separate — overloaded via origin/destination.bic)
- `SttlmInf.SttlmAcct, SttlmAcctOwnr, SttlmAcctSvcr, InstgRmbrsmntAgt, InstdRmbrsmntAgt`

**CdtTrfTxInf**:
- `PmtTpInf.{InstrPrty, ClrChanl, SvcLvl.Cd, LclInstrm.Prtry, CtgyPurp}` (hard-coded per rail)
- `SttlmPrty, SttlmTmIndctn, SttlmTmReq, AccptncDtTm, PoolgAdjstmntDt`
- `ChrgsInf, PrvsInstgAgt1-3, IntrmyAgt1-3` (correspondent banking)
- `UltmtDbtr, UltmtCdtr`
- `InstrForCdtrAgt, InstrForNxtAgt`
- `RgltryRptg` (regulatory reporting — relevant for FX > USD 10k)
- `Tax`
- `RltdRmtInf, SplmtryData`

**Dbtr/Cdtr**:
- `Id.PrvtId/OrgId` structured (DtAndPlcOfBirth, AnyBIC, LEI, structured Othr)
- `CtryOfRes`
- `PstlAdr` structured fields: `Dept, SubDept, StrtNm, BldgNb, BldgNm, Flr, PstBx, Room, PstCd, TwnNm, TwnLctnNm, DstrctNm, CtrySubDvsn` (solo emitimos AdrLine)

**RmtInf**:
- `Strd` (structured remittance info)

**Otros**:
- XML serialization — `canonical-to-iso20022-mx.ts` retorna JS object envuelto en `{Document: {...}}`, no XML string
- XSD validation contra schemas ISO oficiales
- pacs.004 PaymentReturn structured (stub en P06, persistencia pero sin XSD)
- pacs.009 FinancialInstitutionCreditTransfer (inter-bank), camt.054, camt.053

### Justificación académica

Este PoC demuestra **interoperabilidad técnica** entre 3 rieles instantáneos
usando un canónico ISO 20022-derivado. La fidelidad byte-exacta al pacs.008.001.10
real está fuera de scope porque:

1. Requeriría XML XSD validation (verbose para PoC).
2. Requeriría CBPR+ certificación.
3. No es necesario para demostrar el claim arquitectónico (un canónico es viable).

Para conexión con sistemas ISO reales en el futuro, los gaps listados arriba
serían los puntos de inicio de un plan de extensión.
