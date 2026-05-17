I have enough to write the comprehensive forensic audit. Let me deliver it.

---

# Translation Layer â€” Forensic Audit

A field-by-field, spec-driven review of `mipit-core/src/translation/` (16 files) plus the canonical models in `src/domain/models/canonical.ts` and `src/canonical/`. Every finding cites `file:line`. Spec references are listed under "Sources" at the end.

---

## 1. Executive Summary

The MIPIT translation layer correctly implements the **outline** of a "all rails â†” canonical pacs.008" hub-and-spoke topology, but the canonical model is a *very loose subset* of real `pacs.008.001.10`, several emitters generate **non-spec-compliant identifiers** that real APIs would reject, and **round-trip integrity is lossy for every rail**. As a thesis-defense PoC, the architecture is sound; as a production interop layer, it would fail conformance testing on day one. The worst findings, ordered by severity:

1. **Canonical model uses snake_case + camelCase hybrid** (`payment_id`, `created_at`, `trace_id` alongside `grpHdr`, `pmtId`, `endToEndId`) â€” `src/domain/models/canonical.ts:14-138`. Real pacs.008 is uniformly PascalCase XML. This makes every emitter a manual remapping rather than a serialization.
2. **`ChrgBr` is entirely absent from canonical** (`canonical.ts` has no charge-bearer field). Real pacs.008.001.10 marks `ChrgBr` as **mandatory** with the enum `DEBT/CRED/SHAR/SLEV`. Every outbound rail emits a hard-coded value or omits it (`canonical-to-swift-mt103.ts:56` hard-codes `'SHA'`; `canonical-to-fednow.ts` omits it altogether).
3. **`UETR` (Unique End-to-End Transaction Reference) is generated with `Math.random()`** in `canonical-to-fednow.ts:177-183`. SWIFT CBPR+ and FedNow both **mandate** a cryptographically strong UUIDv4 because the UETR is the global tracking key. `Math.random()` is not CSPRNG and can collide.
4. **PIX `EndToEndId` does not follow BCB SPI format** â€” BCB Manual de PadrÃµes requires `E` + ISPB(8) + YYYYMMDDHHMM(12) + suffix(11) = 32 chars exactly. `pix-to-canonical.ts:172` generates `E2E-${ulid()}` (29 chars, no ISPB anchor), and `canonical-to-pix.ts:20` propagates that ULID-shaped string to the outbound `endToEndId`. BCB SPI would reject this on schema validation.
5. **Bre-B `idTransaccion` uses `Math.random().toString(36)` for the unique component** (`breb-to-canonical.ts:121`). BanRep spec for SPI requires a unique deterministic identifier per ODI; `Math.random()` is non-monotonic and can collide. The padding `.padEnd(10, '0')` only triggers when toString(36) returns < 10 chars, which is rare but possible.
6. **SPEI emitter does not produce a valid `claveRastreo`** â€” STP requires `claveRastreo` â‰¤ 30 alphanumeric chars unique per institution per day. `canonical-to-spei.ts:20` reuses `canonical.pmtId.endToEndId` verbatim, which in our PIX path will be `E2E-01HXX...` (29 chars) â€” fits the length, but the `-` is illegal in `claveRastreo` per STP WADL ([A-Z0-9] only, see stp.mx/en/apis/).
7. **CLABE is not validated on emit** â€” `canonical-to-spei.ts:21` blindly emits `clabe: canonical.alias.value`. STP rejects any CLABE that fails mod-10. The validation exists for inbound at `payment-request.ts:4-9` but is **not re-applied** on emit, so a payment received via SWIFT/ACH and routed to SPEI can produce an invalid CLABE.
8. **ISO 20022 MX emitter omits multiple required pacs.008.001.10 elements**: `IntrBkSttlmDt` is emitted as a date-string but `ChrgBr`, `PmtTpInf.SvcLvl`, `TtlIntrBkSttlmAmt` (group-header total), `InstrForCdtrAgt`, `InstrForNxtAgt`, `RgltryRptg` are not emitted (`canonical-to-iso20022-mx.ts:28-76`).
9. **MT103 parser regex is non-greedy and can over-match**: `swift-mt103-to-canonical.ts:100` uses `:${tag}:([\\s\\S]*?)(?=:\\d{2}[A-Z]?:|$|-\})` â€” the alternative `-\}` is **not properly escaped** as a regex literal (`-\}` is fine but `-}` lookahead doesn't anchor on word boundary), so a `:70:` field whose remittance text contains a literal `:50:` will truncate. The regex also doesn't handle `:XX:` style continuation lines per FIN spec.
10. **MT103 amount parser is locale-broken**: `swift-mt103-to-canonical.ts:118` regex `/^(\d{6})([A-Z]{3})([\d,]+)$/` accepts commas inside the digit run, so `:32A:240515USD1,234,56` becomes `1234.56` after the single `.replace(',','.')`, but `1,234,56` should be `1234,56` (German-style thousand separator). The replace is single-occurrence â€” wrong for any amount â‰¥ 1000.
11. **NACHA serializer produces malformed files**: `canonical-to-ach-nacha.ts:96-146` â€” File Header (line 103) embeds spaces inside the routing slot, the "10 chars" padding string `'0'.repeat(9).substring(0, 10)` is **9 chars not 10**, the immediate destination/origin name fields are concatenated without correct width, and the File Control record (line 137) omits the `entry/addenda count` and `total debit` columns. The output will not parse on any real ACH operator.
12. **Round-trip integrity is broken across every rail**: I traced PIXâ†’canonicalâ†’PIX, SPEIâ†’canonicalâ†’SPEI, MT103â†’canonicalâ†’MT103, ISO20022â†’canonicalâ†’ISO20022, ACHâ†’canonicalâ†’ACH, FedNowâ†’canonicalâ†’FedNow, BreBâ†’canonicalâ†’BreB. None preserve all input fields (details in Â§4 per-rail).
13. **`mapping-loader.ts` cache is per-instance and unbounded in key cardinality** (`mapping-loader.ts:18,44`). TTL is 5 min but eviction never runs â€” keys accumulate forever if the rail/direction tuple varies.
14. **`pix-to-canonical.ts:204` declares `let transformedValue` then never re-assigns**; the `let` should be `const`. The mapping framework is structurally broken: `applyTransformation` is called once and result used immediately, so chained transformations are impossible.
15. **PIX and SPEI translators duplicate ~80 lines of helper code verbatim** (`pix-to-canonical.ts:11-84` â‰¡ `spei-to-canonical.ts:11-84`). Two copies of `applyTransformation`, `getNestedValue`, `setNestedValue`, `applyValidation`. Bre-B/MT103/ACH/FedNow/ISO 20022 do **not** use mapping-loader at all â€” only PIX and SPEI do, which is an inconsistent architectural choice.
16. **Timezone mishandling everywhere**: `breb-to-canonical.ts:119-120` slices `toISOString()` for date and time; `toISOString()` always returns UTC, but BanRep, BCB, STP, Banxico all require **local civil time** for the date/time embedded in transaction IDs. So an order placed at 23:30 BogotÃ¡ time on May 15 gets a transaction ID stamped `20260516 / 0430` (UTC).

The architecture itself â€” single canonical, per-rail bidirectional translators, Zod validation at every boundary, OpenTelemetry-style child-loggers, latency timers around every translate call â€” is **good thesis-quality design** (Â§7).

---

## 2. Canonical Schema vs `pacs.008.001.10`

Element-by-element table comparing `src/domain/models/canonical.ts` (lines 14-136) against the official ISO 20022 `pacs.008.001.10` definition. "Cardinality" follows ISO notation `[min..max]`.

### GroupHeader (GrpHdr)

| pacs.008.001.10 element | Cardinality | Type | Present in canonical? | Naming match | Issue |
|---|---|---|---|---|---|
| `MsgId` | [1..1] | Max35Text | Yes (`grpHdr.msgId`) `canonical.ts:19` | camelCase vs PascalCase | OK semantically. No regex enforcement â€” real spec is `[A-Za-z0-9/\-?:().,'+]{1,35}` |
| `CreDtTm` | [1..1] | ISODateTime | Yes (`grpHdr.creDtTm`) `canonical.ts:20` | camelCase | OK |
| `BtchBookg` | [0..1] | TrueFalseIndicator | **No** | â€” | Missing (low impact for single-tx PoC) |
| `NbOfTxs` | [1..1] | Max15NumericText | Yes as `z.number()` `canonical.ts:22` | camelCase | **WRONG TYPE** â€” spec is numeric string `^[0-9]{1,15}$`. Code uses `number` then `canonical-to-iso20022-mx.ts:33` casts back to `'1'` literal |
| `CtrlSum` | [0..1] | DecimalNumber | **No** | â€” | Missing |
| `TtlIntrBkSttlmAmt` | [0..1] | ActiveCurrencyAndAmount | **No** | â€” | Missing â€” group-level total |
| `IntrBkSttlmDt` | [0..1] | ISODate | **No at GrpHdr level** â€” only emitted at `CdtTrfTxInf` level by `canonical-to-iso20022-mx.ts:60` | â€” | OK in v10, but pacs.008.001.08 had it at GrpHdr |
| `SttlmInf` | [1..1] (mandatory) | SettlementInstruction15 | Yes `canonical.ts:24-26` but **only `SttlmMtd`** | camelCase | Missing: `SttlmAcct`, `SttlmAcctOwnr`, `SttlmAcctSvcr`, `ClrSys`, `InstgRmbrsmntAgt`, `InstdRmbrsmntAgt` |
| `SttlmInf.SttlmMtd` | [1..1] | enum INDA/INGA/COVE/CLRG | Yes `canonical.ts:25` | OK | Correct enum, default `'CLRG'` is reasonable for clearing |
| `SttlmInf.ClrSys` | [0..1] | ClearingSystemIdentification3Choice | **No** | â€” | Missing â€” required by FedNow CBPR+ (`USABA`). FedNow path hard-codes `Cd: 'USABA'` at `canonical-to-fednow.ts:73` instead |
| `PmtTpInf` | [0..1] | PaymentTypeInformation28 | **No at GrpHdr** | â€” | Missing both at GrpHdr and at CdtTrfTxInf level (see below) |
| `InstgAgt` | [0..1] | BranchAndFinancialInstitutionIdentification6 | Partial â€” emitted only in canonicalâ†’ISO20022 path via `canonical.origin.bic` `canonical-to-iso20022-mx.ts:36-38` | â€” | Canonical has no dedicated `instgAgt` â€” relies on `origin.bic` overload |
| `InstdAgt` | [0..1] | BranchAndFinancialInstitutionIdentification6 | Partial â€” same as above with `destination.bic` | â€” | Same overload |

### CreditTransferTransactionInformation (CdtTrfTxInf)

| pacs.008.001.10 element | Cardinality | Present in canonical? | Issue |
|---|---|---|---|
| `PmtId` | [1..1] | Yes `canonical.ts:29-36` | Only 3 of 4 sub-elements |
| `PmtId.InstrId` | [0..1] | Yes `pmtId.instrId` | OK |
| `PmtId.EndToEndId` | [1..1] | Yes `pmtId.endToEndId`, max 35 | OK length; no format regex |
| `PmtId.TxId` | [1..1] **mandatory** | Yes `pmtId.txId` but **marked optional** `canonical.ts:35` | **WRONG cardinality** â€” `TxId` is mandatory in pacs.008.001.10 |
| `PmtId.UETR` | [1..1] **mandatory in v10** | **No** | **MISSING REQUIRED FIELD**. UETR is mandatory in pacs.008.001.10 CBPR+. Only FedNow path generates one (with `Math.random()`, see Â§6) |
| `PmtTpInf` | [0..1] | **No** | Missing â€” `InstrPrty`, `ClrChanl`, `SvcLvl.Cd`, `LclInstrm.Prtry`, `CtgyPurp` all absent. FedNow path hard-codes `LclInstrm.Prtry: 'INST'` at `canonical-to-fednow.ts:151` |
| `IntrBkSttlmAmt` | [1..1] | Yes `amount` `canonical.ts:38-44` | Mostly OK |
| `IntrBkSttlmAmt.Ccy` | attribute | Yes `currency` length 3 | OK but no ISO-4217 enum check â€” accepts `'XXX'` |
| `IntrBkSttlmAmt.value` | DecimalNumber | Yes `value: number` | **TYPE drift**: spec requires fractionDigits â‰¤ currency-decimals (USD=2, JPY=0). Our `z.number().positive()` accepts 0.00001 |
| `IntrBkSttlmDt` | [1..1] **mandatory** | **No** at canonical | **MISSING REQUIRED**. Reconstructed in every emitter via `canonical.created_at.slice(0,10)` |
| `SttlmPrty` | [0..1] enum HIGH/NORM/URGT | **No** | Missing |
| `SttlmTmIndctn` (CdtDtTm/DbtDtTm) | [0..1] | **No** | Missing â€” important for instant rails |
| `SttlmTmReq` | [0..1] | **No** | Missing |
| `AccptncDtTm` | [0..1] | **No** | Missing |
| `PoolgAdjstmntDt` | [0..1] | **No** | Missing |
| `InstdAmt` | [0..1] | Yes `amount.instdAmt`, `amount.instdAmtCcy` `canonical.ts:42-43` | OK but flattened |
| `XchgRate` | [0..1] | Yes `fx.rate` `canonical.ts:50` | OK |
| `ChrgBr` | [1..1] **mandatory** | **No** | **MISSING REQUIRED**. `canonical-to-swift-mt103.ts:56` hard-codes `'SHA'`, FedNow/ISO20022 omit it entirely |
| `ChrgsInf` | [0..unbounded] | **No** | Missing |
| `PrvsInstgAgt1/2/3` + Accts | [0..1] each | **No** | Missing |
| `IntrmyAgt1/2/3` + Accts | [0..1] each | **No** | Missing â€” relevant for cross-currency correspondent banking |
| `UltmtDbtr` | [0..1] | **No** | Missing |
| `InitgPty` | [0..1] | **No** | Missing |
| `Dbtr` | [1..1] | Yes `debtor` `canonical.ts:79-95` | See sub-table |
| `Dbtr.Nm` | [0..1] | Yes `debtor.name`, max 140 | OK |
| `Dbtr.PstlAdr` | [0..1] | Partial â€” `debtor.country`, `debtor.address[]` | Missing: `Dept`, `SubDept`, `StrtNm`, `BldgNb`, `BldgNm`, `Flr`, `PstBx`, `Room`, `PstCd`, `TwnNm`, `TwnLctnNm`, `DstrctNm`, `CtrySubDvsn` â€” only free-form `AdrLine` + Ctry. JPMorgan ISO 20022 mapping guide flags this as non-compliant for SEPA |
| `Dbtr.Id` | [0..1] | Partial â€” `taxId` `canonical.ts:84` is unstructured | Real spec splits into `PrvtId.DtAndPlcOfBirth`, `PrvtId.Othr[].Id+SchmeNm`, `OrgId.AnyBIC`, `OrgId.LEI`, `OrgId.Othr[]` |
| `Dbtr.CtryOfRes` | [0..1] | **No** | Missing |
| `Dbtr.CtctDtls` | [0..1] | Partial via `debtor.email`, `debtor.phone` `canonical.ts:90-92` flattened | Real spec is `CtctDtls.NmPrfx`, `Nm`, `PhneNb`, `MobNb`, `FaxNb`, `EmailAdr`, `Othr` |
| `DbtrAcct` | [0..1] | Partial â€” `debtor.account_id` is a single string `canonical.ts:82` | Lossy: real schema is `Id.IBAN` xor `Id.Othr.Id + SchmeNm + Issr`. Our schema has no `Tp`, `Ccy`, `Nm`, `Prxy` |
| `DbtrAgt` | [0..1] | Via `origin.bic`, `origin.routingNumber`, `origin.ispb`, `origin.institutionCode` `canonical.ts:55-65` | Overloaded â€” see "Field overloading" in Â§6 |
| `DbtrAgtAcct` | [0..1] | **No** | Missing |
| `CdtrAgt` | [1..1] | Same overload via `destination.*` | OK semantically |
| `CdtrAgtAcct` | [0..1] | **No** | Missing |
| `Cdtr` | [1..1] | Yes `creditor` | Same shape as `Dbtr`, same gaps |
| `CdtrAcct` | [0..1] | Same as `DbtrAcct` | Same gaps |
| `UltmtCdtr` | [0..1] | **No** | Missing |
| `InstrForCdtrAgt` | [0..*] | **No** | Missing |
| `InstrForNxtAgt` | [0..*] | **No** | Missing |
| `Purp` | [0..1] `Cd` xor `Prtry` | Yes `canonical.purpose` (string) `canonical.ts:115` | Flattened to single string; doesn't distinguish `Cd` (ExternalPurpose code list â€” SALA, CHAR, GOVT, INTC, CASH, TAXS) from `Prtry`. Code at `canonical-to-iso20022-mx.ts:72` always emits as `Cd` even if value is non-code (e.g., `'TRANSF'` from native PIX `pix-to-canonical.ts:145`) â€” that would fail ExternalPurpose1Code validation |
| `RgltryRptg` | [0..*] | **No** | Missing â€” important for cross-border FX |
| `Tax` | [0..1] | **No** | Missing |
| `RltdRmtInf` | [0..*] | **No** | Missing |
| `RmtInf.Ustrd` | [0..*] (up to 140 chars Ã— 35) | Yes `remittanceInfo`, max 140 `canonical.ts:118` | OK for unstructured |
| `RmtInf.Strd` | [0..*] | **No** | Missing â€” would prevent ISO 20022 â†’ SWIFT MX migration |
| `SplmtryData` | [0..*] | **No** | Missing |

### Non-pacs.008 canonical extensions (not bad, but proprietary)

| Canonical field | Purpose | Comment |
|---|---|---|
| `payment_id` `canonical.ts:15` | MIPIT internal correlation `PMT-â€¦` | Reasonable; not part of pacs.008. Regex `^PMT-[A-Z0-9]{10,32}$` is documented |
| `created_at` `canonical.ts:16` | MIPIT timestamp | Duplicates `grpHdr.creDtTm` semantically â€” drift possible |
| `trace_id` `canonical.ts:121` | OTel correlation | Good observability decision |
| `status` `canonical.ts:120` | Lifecycle marker | Free-form string â€” no enum constraint, risk of typos |
| `rail_ack` `canonical.ts:123-135` | Embedded ack | Fine for PoC; in real pacs.008 the ack is a separate pacs.002 |
| `alias.type` / `alias.value` | Rail alias projection | Reasonable shortcut; no equivalent in pacs.008 (closest is `CdtrAcct.Prxy`) |

**Summary**: Of the **~40 mandatory or commonly-used pacs.008.001.10 elements**, the canonical model fully implements ~12, partially supports ~10 via overloaded fields, and **omits ~18 entirely**, including the v10-mandatory `UETR`, `TxId`, `ChrgBr`, and `IntrBkSttlmDt`.

---

## 3. pacs.002 ACK Model vs `pacs.002.001.10`

`src/canonical/pacs002.schema.ts:3-15` defines an ack of 7 fields. Comparison:

| pacs.002.001.10 element | Cardinality | Present in `pacs002AckSchema`? | Issue |
|---|---|---|---|
| `GrpHdr.MsgId` | [1..1] | **No** | Missing â€” replaced by `payment_id` (line 4) which conflates correlation with original-message ID |
| `GrpHdr.CreDtTm` | [1..1] | Partial â€” `processed_at` (line 14) is ack-creation time, OK |
| `GrpHdr.InstgAgt` | [0..1] | **No** | Missing |
| `GrpHdr.InstdAgt` | [0..1] | **No** | Missing |
| `OrgnlGrpInfAndSts.OrgnlMsgId` | [1..1] | **No** | Missing â€” should reference original pacs.008 MsgId |
| `OrgnlGrpInfAndSts.OrgnlMsgNmId` | [1..1] | **No** | Missing â€” should be `pacs.008.001.10` |
| `OrgnlGrpInfAndSts.OrgnlCreDtTm` | [0..1] | **No** | Missing |
| `OrgnlGrpInfAndSts.GrpSts` | [0..1] enum ACSC/ACSP/RJCT/PART/PDNG | Partial â€” `status` (line 6) uses ACCEPTED/REJECTED/ERROR | **Enum drift**: real codes are 4-letter ISO codes |
| `TxInfAndSts.OrgnlInstrId` | [0..1] | **No** | Missing |
| `TxInfAndSts.OrgnlEndToEndId` | [0..1] | **No** | Missing â€” only `rail_tx_id` (line 5) tracks rail ID, not E2E |
| `TxInfAndSts.OrgnlTxId` | [0..1] | **No** | Missing |
| `TxInfAndSts.OrgnlUETR` | [0..1] | **No** | Missing â€” UETR carry-through is the whole point of pacs.002 |
| `TxInfAndSts.TxSts` | [0..1] | Same as `status` overload | Same drift |
| `TxInfAndSts.StsRsnInf.Rsn.Cd` | [0..1] | Partial via `error.code` (line 9) | Real codes are from ExternalStatusReason1Code (e.g., `AC01`, `AC04`, `AM04`, `FF01`, `MS03`) â€” our `code: z.string()` accepts anything |
| `TxInfAndSts.StsRsnInf.AddtlInf` | [0..*] | Partial via `error.message` | Free-form |

**Verdict on pacs.002 model**: heavily simplified to a flat object useful for a PoC but unrecognizable as a pacs.002. The `status` enum `ACCEPTED/REJECTED/ERROR` cannot be mapped to ISO `ACSC/ACSP/RJCT/PART/PDNG` because `ERROR` has no equivalent (it's a transport failure, not a status). Concrete fix: split into `transport_error?: {code, message}` and `business_status: 'ACSC'|'ACSP'|'RJCT'|'PART'|'PDNG'`.

---

## 4. Per-Rail Audit

### 4.1 PIX (`pix-to-canonical.ts`, `canonical-to-pix.ts`)

#### Field-by-field mapping table

| Canonical field | PIX rail field | Direction | Transformation | Issue? |
|---|---|---|---|---|
| `payment_id` | â€” | â€” | injected | â€” |
| `created_at` | â€” | â€” | `new Date().toISOString()` `pix-to-canonical.ts:112` | UTC â€” see Â§6 timezone |
| `grpHdr.msgId` | `endToEndId` (native) | â† | `e2eId` reuse `pix-to-canonical.ts:125` | Conflates MsgId with E2E |
| `grpHdr.msgId` | (DB-path) | â† | `MSG-${ulid()}` line 172 | Reasonable for canonical-side |
| `grpHdr.creDtTm` | â€” | â† | `now` line 172 | UTC |
| `pmtId.endToEndId` | `endToEndId` | â†” | `slice(0, 35)` line 126 | **Spec violation**: BCB requires `E + ISPB(8) + YYYYMMDDHHMM(12) + suffix(11) = 32 chars`. We produce 29-char ULID |
| `amount.value` | `valor.original` | â† | `parseFloat()` line 119 | **Float precision loss**: real PIX uses 2-decimal strings; `parseFloat("0.10")` = 0.1; further multiplications lose precision |
| `amount.value` | `amount` (outbound) | â†’ | direct number `canonical-to-pix.ts:22` | â€” |
| `amount.currency` | hard-coded `'BRL'` | â† | line 127 | Doesn't read from input â€” OK since PIX is always BRL, but undocumented |
| `origin.rail` | `'PIX'` | â† | const | â€” |
| `origin.ispb` | `pagador.ispb` | â† | line 129 | OK |
| `destination.ispb` | `recebedor.ispb` | â† | line 130 | OK |
| `debtor.name` | `pagador.nome` | â†” | line 132; outbound `debtorName` `canonical-to-pix.ts:9` | â€” |
| `debtor.country` | hard-coded `'BR'` | â† | line 133 | Lossy on outbound â€” country not emitted |
| `debtor.account_id` | `pagador.contaTransacional.numero` | â†” | line 134 fallback `acc-${paymentId}` | Synthetic fallback is non-spec |
| `debtor.taxId` | `pagador.cpf` | â† | line 135 | **Validation missing**: no CPF mod-11 check (real BCB rejects invalid CPFs). Outbound: not emitted to PIX schema â†’ lossy |
| `debtor.accountType` | `pagador.contaTransacional.tipoConta` | â† | line 136 default `'CACC'` | OK |
| `creditor.name` | `recebedor.nome` | â†” | line 139 | â€” |
| `creditor.country` | `'BR'` | â† | line 140 | â€” |
| `creditor.account_id` | `PIX-${chave}` | â† | line 141 | Prefixes the chave â€” round-trip via `strip_pix_prefix` (line 19) â€” but **rebuild fails** if downstream rail strips again |
| `creditor.taxId` | `recebedor.cpf` | â† | line 142 | Same CPF issue |
| `alias.value` | `chave` | â†” | line 144 | **No validation by chave type**: CPF mod-11, CNPJ mod-11, email format, phone E.164 (+55), UUIDv4 variant/version bits â€” none checked |
| `alias.type` | const `'PIX_KEY'` | â† | line 144 | Doesn't classify sub-type (CPF vs email vs EVP) |
| `purpose` | `tipo` | â†” | line 145; default `'TRANSF'` | `'TRANSF'` is **not** a valid ExternalPurpose1Code â€” would fail downstream ISO 20022 validation |
| `reference` | `campoLivre` | â†” | line 146 | OK |

Outbound `canonical-to-pix.ts` shape (`PixOutboundPayload`):

| Outbound field | Source | Issue |
|---|---|---|
| `endToEndId` | `canonical.pmtId.endToEndId` line 20 | Non-spec format (see above) |
| `pixKey` | `canonical.alias.value` line 21 | Unvalidated |
| `amount` | `canonical.amount.value` line 22 | **Wrong type vs BCB**: real `valor.original` is a **string** with exactly 2 decimals, e.g. `"100.50"`. We emit `number` |
| `currency` | `canonical.amount.currency` line 23 | BCB PIX is always BRL â€” emitting variable currency is wrong |
| `debtorName`/`creditorName` | `canonical.debtor.name`/`creditor.name` lines 24-26 | OK |
| `debtorAccount`/`creditorAccount` | `canonical.debtor.account_id`/`creditor.account_id` lines 25-27 | Carries `PIX-` prefix â†’ outbound PIX call will fail |
| `purpose` | `canonical.purpose` line 28 | Not in real BCB schema |
| `reference` | `canonical.reference` line 29 | Real field is `infoAdicionais[].nome/valor` |
| `createdAt` | `canonical.created_at` line 30 | Real BCB uses `calendario.criacao` |

#### Spec-compliance findings (PIX)
- **Missing required**: `txid` (BCB `POST /v2/cob` required), `calendario.expiracao`, `valor.original` as string, `solicitacaoPagador`, `loc.id`. The `PixOutboundPayload` shape is a custom JSON unrelated to BCB pix-api.
- **Wrong types**: `valor.original` is **string with `.` decimal** in BCB, we emit `number`.
- **Field-name drift**: `endToEndId` âœ“ but everything else (`pixKey`, `debtorAccount`, `creditorAccount`, `currency`, `purpose`, `reference`, `createdAt`) does not appear in BCB pix-api.
- **Validation gaps**: chave type-specific validation absent for CPF mod-11, CNPJ mod-11, email, phone E.164 (+55XXXXXXXXXXX), EVP UUIDv4 (variant bits `4` and `8/9/a/b`).
- **Lossy**: `pagador.cpf`, `recebedor.cpf`, `tipoChave`, `infoAdicionais`, `tipo` all dropped on outbound.

#### Round-trip integrity verdict (PIX)
**Lossy**. Input fields that get dropped: `tipoChave` (re-inferred), `campoLivre` (renamed to `reference`), original `valor.original` precision (parseFloat round-trip), CPF/CNPJ, account-type. Field `endToEndId` may also change length (if input > 35 â†’ truncation at `pix-to-canonical.ts:126`).

---

### 4.2 SPEI (`spei-to-canonical.ts`, `canonical-to-spei.ts`)

#### Field-by-field mapping table

| Canonical | SPEI native | Dir | Transform | Issue |
|---|---|---|---|---|
| `pmtId.endToEndId` (TO_CANONICAL has no native path â€” only generic CreatePaymentRequest input) | `claveRastreo` | â†’ | `E2E-${ulid()}` line 109 | **Spec violation**: STP `claveRastreo` is `[A-Za-z0-9]{1,30}`, our value `E2E-01HXXâ€¦` contains `-` |
| `amount.value` | `monto` | â†’ | direct number `canonical-to-spei.ts:22` | OK numeric, but STP expects **decimal-string with 2 decimals**, not number |
| `amount.currency` | `moneda` | â†” | hard-coded `'MXN'` in canonical-side fallback line 113 | STP doesn't use `moneda` field; MXN is implicit. **Field-name drift**: STP API doesn't define `moneda` â€” multi-currency is via separate endpoint |
| `debtor.name` | `nombreOrdenante` | â†’ | line 24 outbound | OK length-wise but STP requires max 40 chars; we use `?` |
| `debtor.account_id` | `cuentaOrdenante` | â†’ | line 25 outbound | **No CLABE validation on emit**. May produce `SPEI-XXXXâ€¦` (with prefix) since strip only happens for alias fallback `spei-to-canonical.ts:158-163` not for `account_id` |
| `creditor.name` | `nombreBeneficiario` | â†’ | line 26 | Same length cap missing |
| `creditor.account_id` | `cuentaBeneficiario` | â†’ | line 27 | Same prefix risk |
| `alias.value` | `clabe` | â†’ | line 21 | **No CLABE mod-10 validation**. Inbound at `payment-request.ts:4-9` validates, but cross-rail (e.g. ACHâ†’SPEI) skips |
| `purpose` | `concepto` | â†’ | line 28 | STP requires `conceptoPago` not `concepto`. **Field-name drift** |
| `reference` | `referencia` | â†’ | line 29 | STP uses `referenciaNumerica` (numeric only) â€” our field is free-text |
| `created_at` | `fechaOperacion` | â†’ | `split('T')[0]` line 30 | UTC split â€” see Â§6 timezone. STP expects `YYYYMMDD` not `YYYY-MM-DD` |

#### Spec-compliance findings (SPEI)
- **Missing required**: `empresa` (STP merchant ID), `institucionContraparte` (5-digit Banxico institution code â€” completely absent from canonical), `institucionOperante`, `tipoCuentaOrdenante` (40=card, 10=cellphone, 03=tarjeta, 40=CLABE), `tipoCuentaBeneficiario`, `rfcCurpOrdenante`, `rfcCurpBeneficiario`, `firma` (digital signature).
- **Wrong types**: amount should be string `"100.00"`, date should be `YYYYMMDD`.
- **Field-name drift**: `concepto` should be `conceptoPago`, `referencia` should be `referenciaNumerica` (and numeric-only), `moneda` not in STP API. Our canonical has `origin.institutionCode` `canonical.ts:64` but the SPEI translator **never reads or emits it**.
- **Validation gaps**: no CLABE mod-10 on emit, no 18-digit length check on emit, no `institucionContraparte` lookup against Banxico catÃ¡logo.
- **Lossy**: `taxId`, `accountType`, `address`, `agencia`, `email`, `phone` all dropped.

#### Round-trip integrity (SPEI)
**Heavily lossy**. SPEIâ†’canonical only supports the generic `CreatePaymentRequest` path (`spei-to-canonical.ts:95`); there's no native STP payload parser. So round-trip means re-input the same `CreatePaymentRequest`, not "STP message â†’ canonical â†’ STP message".

---

### 4.3 Bre-B (`breb-to-canonical.ts`, `canonical-to-breb.ts`)

#### Field-by-field mapping table

| Canonical | Bre-B native | Dir | Transform | Issue |
|---|---|---|---|---|
| `pmtId.endToEndId` | `idTransaccion` | â†” | `substring(0, 35)` `breb-to-canonical.ts:181`; outbound `generateBrebTransactionId()` `canonical-to-breb.ts:45` | **Random component is weak**: `Math.random().toString(36).substring(2, 12)` line 121 |
| `grpHdr.msgId` | `idTransaccion` | â† | line 175 | Conflates MsgId with TxId |
| `created_at` | `fechaHora` | â†” | line 173, 78 outbound | OK |
| `amount.value` | `valor.original` | â†” | `parseFloat` line 166; `.toFixed(2)` line 50 outbound | OK |
| `amount.currency` | (hard-coded `'COP'`) | â† | line 183 | OK |
| `origin.ispb` | `pagador.codigoEntidad` | â†” | line 184, 25 outbound | **Field overload**: canonical has no `breb_entity_code`, reuses `ispb` (`canonical.ts:62`). Semantically wrong but functional |
| `destination.ispb` | `beneficiario.codigoEntidad` | â†” | line 185, 26 outbound | Same overload |
| `debtor.name` | `pagador.nombre` | â†” | line 187, 54 outbound | `.substring(0, 140)` cap OK |
| `debtor.account_id` | composite `${codigoEntidad}/${id}` | â†” | line 189, 29-32 outbound | **Lossy split**: outbound `slice(1).join('/')` works only if no `/` in account |
| `debtor.taxId` | `pagador.nit` âˆª `pagador.cc` | â†” | line 190, 55-60 outbound | **Heuristic split**: `taxId?.includes('-')` decides NIT vs CC â€” fragile. A CC `"123456789-1"` would be misclassified as NIT |
| `debtor.accountType` | `pagador.tipoCuenta` | â†” | line 191, 62 outbound | OK |
| `creditor.*` | `beneficiario.*` | â†” | lines 193-199 | Same as debtor |
| `alias.value` | `llave` | â†” | line 200, 43-76 outbound | OK |
| `alias.type` | const `'LLAVE_BREB'` | â† | line 200 | Sub-type (TELEFONO/NIT/EMAIL/ALIAS) is dropped from canonical; outbound infers via `inferTipoLlave` |
| `purpose` | derived | â† | `tipoLlave === 'NIT' ? 'SUPP' : 'P2P'` line 201 | Inference is reasonable but lossy |
| `reference` | `idTransaccion` | â† | line 202 | Conflates ref with txId |
| `remittanceInfo` | `concepto` | â†” | line 203, 77 outbound | OK |

#### Spec-compliance findings (Bre-B)
According to BanRep Bre-B technical doc (Feb 2026 PDF, search results) and the SPI guide, Bre-B has **5 llave types**: ID document, mobile, alphanumeric, email, commerce code. Our `inferTipoLlave` (`breb-to-canonical.ts:127-131`) detects 4 of the 5 â€” missing "commerce code" (merchant alias) classification.
- **Entity codes**: real BanRep entity codes for SPBVI participants are not 8-digit "ISPB-style" â€” they are 4-digit Superfinanciera codes (e.g., 0007 Bancolombia, 0023 Banco de BogotÃ¡). Our `BREB_ENTITY_CODES` constants use 8-digit codes (lines 100-108) **mixing real Banxico/ISPB-style codes with invented ones**. Note `BANCO_DE_BOGOTA: '00000013'` and `BBVA_COLOMBIA: '00000013'` are **duplicate values** (`breb-to-canonical.ts:102,104`) â€” copy-paste bug.
- **Missing required**: `firmaDigital`, `mensajeId` distinct from `idTransaccion`, `tipoOperacion`, `formaPago`. Real Bre-B includes a `comisiones` block.
- **Validation gaps**: NIT format `\d{9,10}-\d` does not validate the DIAN mod-11 check digit; phone `+57\d{10}` doesn't enforce that the first digit after +57 is `3` (Colombia mobile prefix) â€” landlines start with 1-8 and aren't valid Bre-B phone llaves.
- **idTransaccion format**: code says "32 chars = BR + 8 + 8 + 4 + 10". `BR(2) + 8 + 8 + 4 + 10 = 32` âœ“. But the time slice `toISOString().slice(11, 16)` gives `HH:mm` then strips `:` â†’ `HHmm` (4 chars). UTC time, not BogotÃ¡ time â€” see Â§6.
- **Lossy**: `idConfirmacion` (BanRep-side ID), `fechaLiquidacion`, `codigoError`/`descripcionError` are defined in `BreBPaymentResponse` interface but never wired into `rail_ack`.

#### Round-trip integrity (Bre-B)
**Mostly preserved** if input was a native `BreBPaymentRequest`, except:
- `idTransaccion` is regenerated by `canonical-to-breb.ts:45` (not preserved from canonical) â€” so input â†’ canonical â†’ output has a **different transaction ID**.
- `tipoLlave` is re-inferred â€” if user explicitly set `tipoLlave: 'ALIAS'` for a string that happens to match the email regex, it flips to `'EMAIL'`.

---

### 4.4 SWIFT MT103 (`swift-mt103-to-canonical.ts`, `canonical-to-swift-mt103.ts`)

#### Field-by-field mapping table

| Canonical | MT103 tag | Dir | Transform | Issue |
|---|---|---|---|---|
| `pmtId.endToEndId` | `:20:` transactionRef | â†” | `substring(0, 35)` line 214; outbound `substring(0, 16).replace(/[^A-Z0-9/-]/gi, 'X')` line 23 | :20: is **16 chars max** per SWIFT spec â€” our 35-cap on inbound is too loose; outbound is correct |
| `pmtId.instrId` | same `:20:` | â† | line 215 | Conflated |
| `amount.value` + `amount.currency` | `:32A:` | â†” | regex parse line 118; outbound formatted YYMMDD+CCY+amount-with-comma `canonical-to-swift-mt103.ts:72` | See Â§1 finding #10 (comma/thousand-sep) |
| Y2K-window date | `:32A:` YYMMDD | â† | `year >= 70 ? 19 : 20` line 125 | Reasonable until 2070 |
| `bankOperationCode` | `:23B:` | â† | line 114 default `'CRED'` | But not propagated to canonical at all â€” **lossy** |
| `origin.bic` | `:50A:` BIC or `:52A:` | â†” | line 223, 35 outbound | Combined `orderingInstitution?.bic ?? orderingCustomer.bic` â€” loses distinction |
| `debtor.account_id` | `:50K:` line1 or `:50A:` | â†” | line 199, 30 outbound | Strips `(PIX-|SPEI-|SWIFT-)` prefix â€” but **adds `'X'`** for non-alnum in :20: |
| `debtor.name` | `:50K:` line2 | â†” | line 230, 31 outbound | `substring(0, 35)` â€” :50K each line is **35 chars max** âœ“ |
| `debtor.address` | `:50K:` lines 3-5 | â†” | line 233, 32 outbound | OK |
| `debtor.country` | derived from address last line | â† | `extractCountryFromAddress` line 270 | Heuristic â€” line `New York US` returns `US`, but `Cra. 7 #12-34 BogotÃ¡ CO` works only if `CO` is last 2 chars. Brittle |
| `destination.bic` | `:57A:` | â†” | line 227, 42 outbound | OK |
| `creditor.account_id` | `:59:` line1 or `:59A:` IBAN | â†” | line 201, 47 outbound | IBAN detection via regex `/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/` â€” **doesn't validate mod-97 checksum** |
| `creditor.name` | `:59:` line2 | â†” | line 236, 49 outbound | 35-char cap âœ“ |
| `remittanceInfo` | `:70:` | â†” | line 247, 105 outbound `buildRemittanceInfo` | 35-char Ã— 4-line split via `splitRemittance` line 141 âœ“ |
| `purpose` | const `'P2P'` | â† | line 245 | **Lossy** â€” `:70:` may carry `/PURP/SUPP` codes not extracted |
| â€” | `:71A:` charges | â† | parsed line 166 into `detailsOfCharges`, but **never written to canonical** | **Lossy**. Always emitted as `'SHA'` on outbound `canonical-to-swift-mt103.ts:56` |
| â€” | `:13C:` time | not parsed | â€” | Missing |
| â€” | `:23E:` instruction code | not parsed | â€” | Missing |
| â€” | `:33B:` instructed amount | not parsed | â€” | Missing â€” needed for FX |
| â€” | `:36:` exchange rate | not parsed | â€” | Missing |
| â€” | `:52A:` ordering inst | parsed but partial | â€” | Only BIC, no name/address |
| â€” | `:53A/54A/55A/56A:` correspondents | not parsed | â€” | Missing â€” common in real MT103 |
| â€” | `:72:` senderâ†’receiver | parsed structurally `swift-mt103-to-canonical.ts:84` but **not stored in canonical** (no field) | â€” | **Lossy**. Outbound emits `/MIPIT/${payment_id}` line 57 |
| â€” | `:77B:` regulatory reporting | not parsed | â€” | Missing |

#### Serializer issues (`canonical-to-swift-mt103.ts:68-125`)
- Line 103: `const today = new Date()` and `fileDate` uses `today.getMonth() + 1` â€” **wrong file**, this is the NACHA serializer header logic copy-pasted into MT103 nowhere. Actually this is `serializeAchNacha.ts:101` â€” not in MT103. The MT103 serializer at `canonical-to-swift-mt103.ts:68-125` uses `msg.valueDate.replace(/-/g, '').slice(2)` â†’ YYMMDD âœ“.
- Line 124: Block-1 header `{1:F01MIPITSIMMXXX0000000000}` is **invalid LT** (Logical Terminal) â€” real format is BIC8 + LT-code(1, A-Z) + Branch(3). `MIPITSIM` is 8 chars OK, `M` is LT, `XXX` is branch â€” but `MIPITSIM` is not a real BIC and the trailing `XXX0000000000` mixes branch (XXX) with session/sequence (10 digits) â€” actually the SWIFT BLR is `BIC8 + LT + Branch + SessionNb(4) + SeqNb(6)` = `MIPITSIM M XXX 0000 000000` âœ“ in length but the BIC is fake. Block-2 `{2:I103MIPITSIMMXXXN}` â€” input message, `103`, receiver `MIPITSIMMXX`, priority `N` â€” receiver BIC is 11 chars but spec needs `BIC11 + priority`; ours has only 11 chars + `N` âœ“.

#### Round-trip integrity (MT103)
**Lossy**:
- `:23B:` bank operation code â†’ lost (always emits CRED outbound).
- `:71A:` â†’ always emits `SHA`.
- `:72:` â†’ always emits `/MIPIT/{payment_id}`.
- `:50K:` address lines may differ (extracted country tacked on).
- `:20:` will change because outbound replaces non-alnum with `X`.

---

### 4.5 ISO 20022 MX (`iso20022-mx-to-canonical.ts`, `canonical-to-iso20022-mx.ts`)

#### Field-by-field mapping table

| Canonical | ISO 20022 XPath | Dir | Transform | Issue |
|---|---|---|---|---|
| `grpHdr.msgId` | `GrpHdr/MsgId` | â†” | direct line 185, 30 outbound | OK |
| `grpHdr.creDtTm` | `GrpHdr/CreDtTm` | â†” | line 186, 31 outbound | OK |
| `grpHdr.nbOfTxs` (number) | `GrpHdr/NbOfTxs` (numeric string) | â†” | `parseInt(grp.NbOfTxs ?? '1', 10)` line 187; outbound `'1'` literal line 32 | **Type drift** â€” always `'1'` regardless of canonical value |
| `grpHdr.sttlmInf.sttlmMtd` | `GrpHdr/SttlmInf/SttlmMtd` | â†” | line 188, 34 outbound | Outbound uses `((canonical.grpHdr as Record<string,unknown>)?.sttlmInf as Record<string,unknown>)?.['sttlmMtd'] as 'CLRG' ?? 'CLRG'` â€” **type assertion abuse**, would not produce 'CLRG' literal correctly; the `as 'CLRG' ?? 'CLRG'` defaults always to literal 'CLRG' |
| `pmtId.endToEndId` | `CdtTrfTxInf/PmtId/EndToEndId` | â†” | `substring(0, 35)` line 191, 47 outbound | OK |
| `pmtId.instrId` | `â€¦/PmtId/InstrId` | â†” | lines 192, 46 | OK |
| `pmtId.txId` | `â€¦/PmtId/TxId` | â†” | lines 193, 48 | OK |
| `amount.value` + currency | `IntrBkSttlmAmt/{Ccy,value}` | â†” | `parseFloat` line 147; `.toFixed(2)` line 53 outbound | Outbound 2-decimal hard-coded â€” **wrong for JPY/KRW (0 decimals)** |
| `amount.instdAmt` / `instdAmtCcy` | `InstdAmt` | â†” | lines 198-199, 56-58 outbound | OK |
| `fx.rate` | `XchgRate` | â†” | `parseFloat` line 167; `String(rate)` line 62 outbound | OK |
| `fx.local_amount` | from `InstdAmt.value` | â† | line 169 | OK (one-way) |
| `origin.bic` | `DbtrAgt/FinInstnId/BICFI` | â†” | lines 204, 64-65 outbound | OK |
| `origin.routingNumber` | `DbtrAgt/FinInstnId/ClrSysMmbId/MmbId` | â†” | lines 205, 64 outbound | OK |
| `destination.bic` | `CdtrAgt/FinInstnId/BICFI` | â†” | lines 209, 68 outbound | OK |
| `destination.routingNumber` | `CdtrAgt/FinInstnId/ClrSysMmbId/MmbId` | â†” | lines 210, 68 outbound | OK |
| `debtor.name` | `Dbtr/Nm` | â†” | lines 213, 115 outbound | OK |
| `debtor.country` | `Dbtr/PstlAdr/Ctry` | â†” | lines 214, 118 outbound | OK |
| `debtor.address` | `Dbtr/PstlAdr/AdrLine[]` | â†” | lines 216, 119 outbound | OK |
| `debtor.taxId` | `Dbtr/Id/PrvtId/Othr/Id` | â†’ only | line 123 outbound emits `taxId.replace(/\D/g,'')` | **One-way**: inbound never reads `Dbtr/Id/PrvtId` (only stub `Id?` in interface line 70-72) |
| `debtor.account_id` | `DbtrAcct/Id/IBAN` âˆª `DbtrAcct/Id/Othr/Id` | â†” | lines 152-153, `buildAccount` line 128 | OK |
| `creditor.*` | `Cdtr/*`, `CdtrAcct/*` | â†” | mirrored | Same issues |
| `purpose` | `Purp/Cd` âˆª `Purp/Prtry` | â†” | line 179; line 72 outbound emits `Purp.Cd` (max 4 chars) | **Format violation**: if canonical purpose is `'P2P'` (length 3) â†’ OK as code; if `'TRANSF'` â†’ truncated to `'TRAN'` which is not in ExternalPurpose1Code |
| `remittanceInfo` | `RmtInf/Ustrd` | â†” | lines 174-176, `buildRemittance` line 160 | OK |
| `reference` | â€” | â€” | doesn't map to ISO field outbound; inbound reuses `EndToEndId` line 229 | Lossy: distinct fields collapsed |

#### Spec-compliance findings (ISO 20022 MX)
- Missing emitted elements: `ChrgBr`, `PmtTpInf` (SvcLvl, LclInstrm, CtgyPurp), `IntrmyAgt1-3`, `InstrForCdtrAgt`, `InstrForNxtAgt`, `RgltryRptg`, `Tax`, `RltdRmtInf`, `SttlmInf.ClrSys`, `TtlIntrBkSttlmAmt`, `CtrlSum`, `SttlmTmIndctn`, `UltmtDbtr`, `UltmtCdtr`, `UETR` (mandatory in v10).
- **The output is labeled as `pacs.008.001.08`** at `canonical-to-iso20022-mx.ts:86` (`@xmlns: 'urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08'`) but the task asked for `.001.10`. v10 introduced mandatory UETR; our output is **v08**, which is what FedNow uses. Document this version mismatch.
- **No actual XML serializer**: `canonicalToIso20022Mx` returns a JS object. `wrapInDocument` (line 83) wraps it in `{Document: {â€¦}}` but never serializes to XML. A real ISO 20022 MX payload is XML â€” JSON output is a thesis simplification but should be documented.
- `mapAliasTypeToScheme` line 150 maps `'PIX_KEY'` and `'CLABE'` both to `'BBAN'` â€” neither is a valid ExternalAccountIdentification4Code. The correct value would be `Prtry: 'PIX_KEY'` etc.

#### Round-trip integrity (ISO 20022 MX)
**Largely preserved** when going JSON-Object â†’ canonical â†’ JSON-Object, *except*:
- `Dbtr.Id.PrvtId/OrgId` is never read inbound â€” lost.
- `PmtTpInf` (defined in the interface but not in canonical) â€” lost.
- `BtchBookg`, `CtrlSum`, `TtlIntrBkSttlmAmt` (GrpHdr level) â€” never modeled.

---

### 4.6 ACH NACHA (`ach-nacha-to-canonical.ts`, `canonical-to-ach-nacha.ts`)

#### Field-by-field mapping table (Entry Detail Type 6)

| Canonical | NACHA field | Dir | Transform | Issue |
|---|---|---|---|---|
| `pmtId.endToEndId` | `traceNumber` (15 digits) | â†” | `substring(0, 35)` line 201; outbound `${odfiRouting.substring(0,8)}${Date.now() % 10000000â€¦padStart(7,'0')}` line 33 | **Format violation**: real Trace Number is **15 digits exactly** = ODFI(8) + seq(7). Our slice `substring(0,8)` of ODFI is fine; the seq is `Date.now() % 10M` which can collide rapidly and isn't monotonic per batch |
| `pmtId.instrId` | `companyId-batchNumber` | â†’ | line 202 | OK |
| `amount.value` | `amount` (cents int) | â†” | `/100` inbound line 186; `Math.round(value * 100)` outbound line 13 | **Floatâ†’int round** can drift: `Math.round(0.1 + 0.2 * 100)` = `Math.round(30.000000000000004)` = 30 âœ“ here, but `Math.round(99.995 * 100)` = 9999 not 9999.5 â€” pre-existing banker's rounding issue |
| `amount.currency` | hard-coded `'USD'` | â† | line 207 | OK (NACHA is USD only) |
| `origin.routingNumber` | `originatingDfiId` (8 digits) | â†” | `.substring(0,9).padEnd(9,'0')` line 210; outbound `.substring(0,8)` line 45 | **Inconsistent length**: NACHA Batch Header field is **8-digit** (ODFI routing without check digit), but our canonical stores 9-digit. Inbound pads to 9, outbound trims to 8 â€” possible drift if the 9th digit isn't the real check digit |
| `destination.routingNumber` | `routingTransitNumber` (9 digits) | â†” | line 215, 52 outbound | **Length is 9 with check digit** âœ“, but **no ABA check-digit validation** (3Â·d1 + 7Â·d2 + 1Â·d3 + â€¦ mod 10) |
| `debtor.name` | `companyName` (16 chars) | â†” | line 219, 39 outbound `.substring(0,16).padEnd(16)` | OK |
| `debtor.account_id` | `originator.accountNumber` (custom struct) | â†” | line 221, 64 outbound | NACHA Type 6 doesn't carry originator account â€” placed in a non-standard `originator` block |
| `debtor.taxId` | `companyId` (10 chars) | â†” | line 222, 40 outbound `.replace(/\D/g, '').substring(0,10) ?? '1234567890'` | **Hard-coded fallback `'1234567890'`** is a fake EIN â€” real ACH would reject |
| `creditor.name` | `individualName` (22 chars) | â†” | line 225, 56 outbound `.padEnd(22)` | OK |
| `creditor.account_id` | `accountNumber` (17 chars) | â†” | line 227, 53 outbound `.padEnd(17)` | OK; but **no validation** that account is digits-only (NACHA spec allows any printable) |
| `creditor.taxId` | `individualIdNumber` (15 chars) | â†” | line 55 outbound | One-way: never read on inbound |
| `alias.value` | `${routing}/${account}` | â†” | line 230, `parseAbaAlias` line 149 outbound | Heuristic split |
| `purpose` | `companyEntryDescription` (10 chars) | â†” | line 233, 42 outbound `.padEnd(10)` | OK |
| `reference` | `companyId-batchNumber` | â†” | line 234 | Conflated |
| `remittanceInfo` | `addenda[0].paymentRelatedInfo` (80 chars) | â†” | line 235, 80-char cap in `buildAddendaPaymentInfo` line 162 | OK |

#### Spec-compliance findings (NACHA)
- **Missing required**: `transactionCode` enum (we hard-code 22 on outbound line 51 â€” debit accounts and savings accounts ignored), `serviceClassCode` is hard-coded `'220'` line 38 (no debit support), `secCode` heuristic `destination.routingNumber ? 'CCD' : 'PPD'` line 41 â€” but for an inbound transaction `routingNumber` is always set so we'd always emit CCD even for consumer payments.
- **File-format violations** in `serializeAchNacha` line 96-146:
  - File Header line 103: position-by-position, NACHA Type 1 requires `1` + `priorityCode(2)` + `ImmDestination(10)` + `ImmOrigin(10)` + `FileCreDate(6)` + `FileCreTime(4)` + `FileIDMod(1)` + `RecSize(3)` + `BlkFactor(2)` + `FormatCode(1)` + `ImmDestName(23)` + `ImmOriginName(23)` + `RefCode(8)` = 94 chars. Our line `\`101 ${txn.odfi.routingNumber.substring(0, 9)} ${'0'.repeat(9).substring(0, 10)}â€¦\`` puts spaces around the routing number â€” that's literal-space-separated, not position-padded. The expression `'0'.repeat(9).substring(0, 10)` = `'000000000'` which is **9 chars not 10** (immediate-origin must be 10).
  - Batch Header line 108 uses `' '.repeat(20)` for `companyDiscretionaryData` â€” correct width but should be filler that matches IRS regs.
  - File Control line 137: `9000001${blockCount}${entryCount}${hash}${amount}${'0'.repeat(12)}${' '.repeat(39)}` â€” missing fields, NACHA Type 9 layout is `9` + `BatchCount(6)` + `BlkCount(6)` + `EntryAddendaCount(8)` + `EntryHash(10)` + `TotalDebit(12)` + `TotalCredit(12)` + `Reserved(39)`. We collapse Batch & Block counts into `'9' + '000001' + blockCount(6)` only â€” **missing total credit** column.
- **EntryHash** at line 129 is `ed.routingTransitNumber.substring(0,8).padStart(10,'0')` for a single entry â€” NACHA EntryHash is the **sum of the first 8 digits of RTN across all entries**, mod 10^10. For a single entry it's `RTN[0..8]`; substring is 8 chars and padStart to 10 with zeros works for a *single entry* but is misleading.
- **No IAT (International ACH Transaction) support** â€” required for cross-border ACH but not implemented despite being in `AchSecCode` type line 40.

#### Round-trip integrity (NACHA)
**Severely lossy**: outbound always emits `transactionCode: 22, serviceClassCode: '220', secCode: 'CCD'|'PPD'` regardless of inbound values. Trace number is regenerated. Filler fields (`discretionaryData`) lost.

---

### 4.7 FedNow (`fednow-to-canonical.ts`, `canonical-to-fednow.ts`)

#### Field-by-field mapping table

| Canonical | FedNow path | Dir | Transform | Issue |
|---|---|---|---|---|
| `grpHdr.msgId` | `â€¦GrpHdr/MsgId` | â†” | lines 180, 68 outbound | OK |
| `grpHdr.creDtTm` | `â€¦GrpHdr/CreDtTm` | â†” | line 181, 69 outbound uses `now` (regenerated!) | **Bug**: outbound regenerates `CreDtTm` rather than reusing canonical value |
| `grpHdr.nbOfTxs` | `â€¦NbOfTxs` | â†” | line 182, 70 outbound `'1'` literal | OK |
| `grpHdr.sttlmInf.sttlmMtd` | `â€¦SttlmInf/SttlmMtd` | â†” | line 183, 72 outbound `'CLRG'` literal | OK |
| â€” | `â€¦SttlmInf/ClrSys/Cd` `'USABA'` | â€” | line 73 outbound | Required by FedNow âœ“ |
| `pmtId.endToEndId` | `â€¦PmtId/EndToEndId` | â†” | line 186, 79 outbound `.substring(0, 35)` | OK |
| `pmtId.txId` | `â€¦PmtId/TxId` | â†” | line 187, 80 outbound | OK |
| `pmtId.instrId` | `â€¦PmtId/UETR` | â†” | line 188 stores UETR in `instrId`; outbound generates fresh UETR `generateUetr()` line 81 | **Field conflation**: `UETR` is not `InstrId` â€” they have different semantics in pacs.008. Spec drift |
| â€” | `â€¦PmtId/UETR` outbound | â€” | `generateUetr()` line 81 uses `Math.random()` (line 177-183) | **CRITICAL**: not CSPRNG. FedNow rejects malformed/duplicate UETRs |
| `amount.value` | `IntrBkSttlmAmt/value` | â†” | `parseFloat` line 163; `.toFixed(2)` line 86 outbound | OK |
| `amount.currency` | hard-coded `'USD'` | â€” | line 192 inbound; literal line 85 outbound | OK |
| `origin.routingNumber` | `DbtrAgt/â€¦/MmbId` | â†” | line 196, 95 outbound | OK 9-digit |
| `destination.routingNumber` | `CdtrAgt/â€¦/MmbId` | â†” | line 201, 122 outbound | OK |
| `debtor.name` | `Dbtr/Nm` | â†” | line 205, 101 outbound | OK |
| `debtor.country` | `Dbtr/PstlAdr/Ctry` | â†” | line 206 (default `'US'`), 103 outbound (default `'US'`) | Defaulting on inbound is questionable â€” overrides explicit foreign country |
| `debtor.account_id` | composite `${rtn}/${acct}` from `DbtrAcct/Id/Othr/Id` | â†” | line 207, `extractRtnAndAccount` line 161 outbound | Heuristic split |
| `debtor.address` | `Dbtr/PstlAdr/AdrLine[]` | â†” | line 208, 104 outbound | OK |
| `creditor.*` | `Cdtr/*` | â†” | mirror | Same |
| `alias.value` | composite | â†’ | line 218 builds `${rtn}/${acct}` | OK |
| `purpose` | `Purp/Cd` (max 4 chars) | â†” | line 220 default `'P2P'`; 145 outbound `.substring(0, 4)` | `'TRANSF'` â†’ `'TRAN'` truncation drift |
| `remittanceInfo` | `RmtInf/Ustrd` | â†” | lines 222, 147-149 outbound | OK |
| â€” | `LclInstrm/Prtry: 'INST'` | â€” | line 151 outbound | Required by FedNow âœ“ |

Inbound also stores `trace_id ?? uetr` line 224 â€” **OpenTelemetry trace_id conflated with payment UETR**. These are different domain concepts.

#### Spec-compliance findings (FedNow)
- **UETR generation is non-CSPRNG**: `Math.random()` in `generateUetr` line 177-183. Fix: use `crypto.randomUUID()` (Node â‰¥ 14.17).
- **Transaction limit not enforced**: FedNow has a default $500K per-transaction limit and $1M ceiling. No check on `amount.value > 500_000` or `> 1_000_000`.
- **Currency convertion**: line 32-33 outbound does `canonical.amount.value * (canonical.fx?.rate ?? 1)` â€” defaulting `rate` to 1 silently converts non-USD to USD at 1:1, which is dangerous (a 100 EUR payment becomes 100 USD).
- **`Math.round(value * 100)` rounding** missing for `.toFixed(2)` â€” IEEE-754 fp drift on amounts like `0.1 + 0.2`.
- **No business-day check**: FedNow operates 24/7/365 but real FedNow ISO 20022 envelopes carry `BusinessMessageHeader/CreDt` in business-day terms â€” `now` is UTC and may not match Fed Eastern Time settlement window.
- **`MsgDefIdr: 'pacs.008.001.08'`** line 61 â€” this is correct for current FedNow (per FedNow spec v2024.1 line 19), but if FedNow upgrades to v10 (matching CBPR+), the literal would need a flag.

#### Round-trip integrity (FedNow)
**Lossy**:
- `BusinessMessageHeader` is generated on outbound but not parsed on inbound (`fednow-to-canonical.ts:157` only reads `msg.FIToFICstmrCdtTrf`, ignores `BusinessMessageHeader`).
- `UETR` regenerated on outbound (different from input).
- `CreDtTm` regenerated on outbound.
- `Purp.Cd` truncated to 4 chars.

---

## 5. Translator Orchestration

### `translator.ts`
- Clean orchestrator with `toCanonical`/`fromCanonical`/`translate(source, dest)` (`translator.ts:29, 88, 145`).
- Latency timer + structured logger + error-type classification (`translator.ts:35-37, 77`) â€” **good observability discipline**.
- `TranslationError` distinguishes `validation` vs `unexpected` (line 77) â€” feeds metrics correctly.
- **Issue 1**: `toCanonical` accepts `rail: Rail | string` (line 30) but `default` branch (line 68) throws `TranslationError(rail, â€¦)` â€” `rail` may be unknown so the error tag becomes the user-supplied string, which is fine for observability but **enables log-injection** if `rail` contains newlines/control chars.
- **Issue 2**: The signature for PIX/SPEI takes `mappingLoader` (line 44, 47) but SWIFT/ISO20022/ACH/FedNow/BreB do not (lines 50, 56, 60, 63, 66). Architectural asymmetry â€” mapping-loader is only consulted for two rails despite all rails passing through the same orchestrator.
- **Issue 3**: `translate(source, dest, â€¦)` (line 145-158) doesn't short-circuit when `sourceRail === destinationRail` â€” translating PIXâ†’PIX needlessly goes through canonical and back, losing fields each direction. Add a `if (sourceRail === destinationRail) return { canonical: â€¦, translated: payload };` fast-path.
- **Issue 4**: `toCanonical` returns the typed `CanonicalPacs008` but the underlying rail funcs return `Promise<CanonicalPacs008>` already validated. The double-cast `payload as Parameters<typeof swiftMt103ToCanonical>[0]` line 51 is awkward â€” `Parameters<T>[0]` chains a private type. Replace with a discriminated union.

### `mapping-loader.ts`
- Per-instance Map cache with 5-min TTL (`mapping-loader.ts:10, 22-29`).
- **Issue 1**: No eviction. The Map grows until `clearCache()` is called. For (`rail`, `direction`) cardinality of `7 Ã— 2 = 14` it's bounded, but the design is fragile.
- **Issue 2**: TTL check uses `Date.now() - cached.loadedAt < TTL_MS` (line 26) â€” single-process check, no coherency across replicas. In a deployment with N instances, each has its own cache; an admin updating a mapping requires waiting up to TTL_MS on every replica.
- **Issue 3**: Race condition â€” two concurrent `loadMappings` for the same key both hit DB (no in-flight de-duplication). Use a `Map<string, Promise<â€¦>>` for in-flight requests.
- **Issue 4**: `applyTransformation` (`pix-to-canonical.ts:11-31`, duplicated in `spei-to-canonical.ts:11-31`) supports only 8 transformations. No chaining (`uppercase|strip_pix_prefix`), no parametrized transforms (e.g. `substring:0,10`).
- **Issue 5**: `applyValidation` (line 67-84) accepts a regex literal directly from DB-stored string â€” **regex injection** if a malicious admin sets `validation: 'regex:.*((?=.*).*)+$'` (catastrophic backtracking). Mitigate with `safe-regex` or per-rail allowlists.

---

## 6. Cross-Cutting Patterns

### Duplicated code
- **PIX vs SPEI helpers**: `applyTransformation`, `getNestedValue`, `setNestedValue`, `applyValidation` are byte-identical between `pix-to-canonical.ts:11-84` and `spei-to-canonical.ts:11-84`. Fix: extract to `translation/_dynamic-mapping.ts`.
- **Prefix-strip**: `replace(/^(PIX-|SPEI-)/, '')` appears in `canonical-to-ach-nacha.ts:152,154`, `canonical-to-fednow.ts:166,170,173`, `canonical-to-iso20022-mx.ts:133`, `canonical-to-swift-mt103.ts:30,47`, `breb-to-canonical.ts:144`. Should be a single utility `stripRailPrefix(s)`.
- **`.substring(0, N).padEnd(N)`** for fixed-width: NACHA file (`canonical-to-ach-nacha.ts:39, 42, 53, 56, 103, 108, 115`), MT103 (`canonical-to-swift-mt103.ts:31, 49, 77, 80, 92, 96`) â€” encapsulate as `fixedWidth(str, n, padChar = ' ')`.

### Weak randomness
- `Math.random().toString(36).substring(2, 12).toUpperCase().padEnd(10, '0')` (`breb-to-canonical.ts:121`) â€” non-CSPRNG, collision risk.
- `Math.floor(Math.random() * 99999999).toString().padStart(7, '0')` (`ach-nacha-to-canonical.ts:190`) â€” same.
- `Math.floor(Date.now() % 10000000).toString().padStart(7, '0')` (`canonical-to-ach-nacha.ts:33`) â€” deterministic-by-time, collides within same ms.
- `generateUetr` (`canonical-to-fednow.ts:177-183`) â€” non-CSPRNG UUIDv4.
- **Fix**: replace all with `crypto.randomUUID()` or `crypto.randomBytes(N).toString('hex')`.

### Timezone mishandling
- `new Date().toISOString()` everywhere produces UTC: `pix-to-canonical.ts:112`, `spei-to-canonical.ts:96`, `breb-to-canonical.ts:161`, `ach-nacha-to-canonical.ts:185`, `fednow-to-canonical.ts:14, 162`, `swift-mt103-to-canonical.ts:197`, `iso20022-mx-to-canonical.ts:146`, `canonical-to-fednow.ts:14`.
- `breb-to-canonical.ts:119-120` slices `toISOString()` for `YYYYMMDD` and `HHmm` â€” UTC, not BogotÃ¡. A txn at 23:45 BogotÃ¡ May 15 â†’ idTransaccion stamped May 16 04:45.
- `canonical-to-spei.ts:30` does `canonical.created_at.split('T')[0]` â€” UTC date â€” wrong if order placed near midnight in Mexico City (UTC-6).
- **Fix**: introduce `getLocalIsoDate(timeZone)` using `Intl.DateTimeFormat` or `Temporal` (Node 22+).

### Lossy transformations (summary)
| Rail | Fields silently dropped on outbound |
|---|---|
| PIX | `tipoChave` (re-inferred), CPF/CNPJ, account-type, `infoAdicionais` |
| SPEI | All `taxId`, `accountType`, `address`, `agencia`, `email`, `phone`, `institutionCode` |
| Bre-B | `idConfirmacion`, `fechaLiquidacion`, `codigoError`, `descripcionError`, `tipoLlave` (re-inferred) |
| MT103 | `:23B:`, `:71A:`, `:72:`, `:13C:`, `:23E:`, `:33B:`, `:36:`, `:53A:`, `:54A:`, `:55A:`, `:56A:`, `:77B:` |
| ISO 20022 MX | `BtchBookg`, `CtrlSum`, `TtlIntrBkSttlmAmt`, `PmtTpInf`, `ChrgBr`, `IntrmyAgt*`, `UltmtDbtr/Cdtr` |
| ACH NACHA | `transactionCode`, `serviceClassCode`, `secCode`, `discretionaryData`, addenda beyond first |
| FedNow | `BusinessMessageHeader` (regenerated), `UETR` (regenerated), `Purp.Cd` truncated to 4 chars |

### Naming convention drift
The canonical is a hybrid: `payment_id`, `created_at`, `trace_id` use snake_case while `grpHdr`, `pmtId`, `endToEndId`, `nbOfTxs`, `sttlmInf` use camelCase. Pick one (camelCase is idiomatic TS).

### Inconsistent translator architecture
PIX and SPEI use **DB-driven dynamic mappings via MappingLoader**; the other 5 rails use **hand-coded inline logic**. Either commit to dynamic mappings everywhere (and pay the runtime cost) or remove the mapping-loader.

### Truncation without warning
Many fields are silently `.substring(0, N)` with no logged warning when truncation occurs. Examples: `breb-to-canonical.ts:181` (`endToEndId.substring(0, 35)`), `swift-mt103-to-canonical.ts:214`, `iso20022-mx-to-canonical.ts:191-193`, `fednow-to-canonical.ts:79, 145`. Add `if (s.length > N) log.warn(â€¦)`.

---

## 7. What Was Done Well

Despite the gaps above, several design choices deserve preservation in the thesis:

1. **Hub-and-spoke topology**: One canonical model + N Ã— 2 translators is the textbook ISO 20022 interop pattern. Adding a new rail requires only two files. Translator orchestration in `translator.ts` is clean.
2. **Zod-validated output at every translator boundary**: `canonicalPacs008Schema.safeParse(raw)` at the end of every `*ToCanonical` function (`pix-to-canonical.ts:150, 230`, `spei-to-canonical.ts:166`, `breb-to-canonical.ts:256`, etc.) â€” fails fast with structured errors.
3. **Structured logging**: `logger.child({ payment_id, rail, direction })` everywhere â€” excellent observability discipline.
4. **Latency metrics**: `startLatencyTimer('translation_to_canonical')` (`translator.ts:35`) â€” translation latency is a critical KPI for instant-payment hubs and you're already measuring it.
5. **Error taxonomy**: `TranslationError` distinguishes "translation validation" from "unexpected" and increments `recordTranslationError(rail, errorType)` (`translator.ts:78, 135`).
6. **Native-vs-generic dual ingestion** in PIX (`pix-to-canonical.ts:117-159`) and Bre-B (`breb-to-canonical.ts:164-206`) is a clever way to accept both the rail's native message and the platform's generic `CreatePaymentRequest`. Pattern is reusable.
7. **Comprehensive comments and inline doc-comments**: every rail file has a header describing operator, format, version, key fields, and (for Bre-B) error codes (`breb-to-canonical.ts:6-23`, `swift-mt103-to-canonical.ts:6-12`, `fednow-to-canonical.ts:6-20`, `ach-nacha-to-canonical.ts:7-19`). This is thesis-quality documentation.
8. **TypeScript interfaces for each rail's native shape** (`SwiftMt103Message`, `Iso20022Pacs008`, `AchNachaTransaction`, `FedNowPaymentMessage`, `BreBPaymentRequest`) â€” compile-time type-safety per rail.
9. **Inline CLABE mod-10 validator** in `payment-request.ts:4-9` â€” correctly implements the standard SAT weights `[3,7,1,...,3,7]`.
10. **Constants file pattern**: `BREB_ENTITY_CODES` (`breb-to-canonical.ts:100-109`) as a single source of truth for institution codes is the right idea (even though the values themselves contain a duplicate bug).
11. **Default values explicit**: every translator sets defaults for `purpose`, `reference`, `country` rather than relying on undefined â€” predictable behavior.
12. **Separation of structured-object vs serializer**: `canonical-to-swift-mt103.ts:9` returns a structured object; `serializeMt103()` (line 68) converts to FIN. Same for NACHA (`serializeAchNacha`). Clean two-step pipeline.
13. **Composable `wrapInDocument`** (`canonical-to-iso20022-mx.ts:83`) decouples envelope from body.

---

## Sources

- BCB pix-api OpenAPI v2.9.0 â€” https://raw.githubusercontent.com/bacen/pix-api/master/openapi.yaml
- BanRep Bre-B (overview) â€” https://www.banrep.gov.co/es/bre-b
- BanRep Bre-B (quÃ© es) â€” https://www.banrep.gov.co/es/bre-b/que-es
- BanRep Bre-B technical doc, Feb 2026 (binary-only PDF, partial extraction) â€” https://d1b4gd4m8561gs.cloudfront.net/sites/default/files/publicaciones/archivos/documento-tecnico-bre-b-febrero-2026.pdf
- Bancolombia Bre-B llaves guide â€” https://blog.bancolombia.com/educacion-financiera/llaves-sistema-de-pagos-inmediatos/
- STP APIs portal â€” https://stp.mx/en/apis/
- Banxico SPEI â€” https://www.banxico.org.mx/servicios/sistema-pagos-electronicos-in.html
- Banxico MÃ³dulo de InformaciÃ³n SPEI â€” https://www.banxico.org.mx/servicios/modulo-informacion-del-spei_-.html
- IotaFinance MT103 field reference â€” https://www.iotafinance.com/en/SWIFT-ISO15022-Message-type-MT103.html
- Paiementor MT103 format spec â€” https://www.paiementor.com/swift-mt103-format-specifications/
- BNZ MT103 Standards November 2021 â€” https://www.bnz.co.nz/assets/bnz/business-banking/help-and-support/SWIFT-MT103.pdf
- pacs008.com explainer â€” https://pacs008.com/pacs-explained/
- BankingCircle FI-to-FI Credit Transfers (Pacs.008) â€” https://docs.bankingcircleconnect.com/docs/fi-to-fi-credit-transfers-pacs008
- Payments Canada RTR pacs.008.001.08 usage guideline â€” https://www.payments.ca/sites/default/files/RTR_FItoFI_CustomerCreditTransfer_pacs.008.pdf
- Clearstream CBPR+ pacs.008.001.08 usage guideline â€” https://www.clearstream.com/resource/blob/4151636/748b8c7bc59fe132742e3a15955d175d/pacs-008-2-data.pdf
- JPMorgan ISO 20022 mapping guide â€” https://www.jpmorgan.com/content/dam/jpmorgan/documents/payments/iso20022-mapping-guide.pdf
- SWIFT ISO 20022 Market Practice Guidance â€” https://www.swift.com/swift-resource/252216/download
- Karbon Card MT103 mandatory fields â€” https://www.karboncard.com/blog/mt103-mandatory-fields
- ISO 20022 portal â€” https://www.iso20022.org
- Federal Reserve FedNow ISO 20022 spec v2024.1 (reference cited in `fednow-to-canonical.ts:20`)
