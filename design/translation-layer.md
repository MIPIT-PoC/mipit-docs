# Capa de Traducción — Diseño e Implementación

## Propósito

La capa de traducción de MiPIT es el núcleo intelectual del middleware. Su función es convertir mensajes de pago de cualquier formato nativo de un riel financiero a un modelo canónico interno (basado en ISO 20022 pacs.008), y de vuelta hacia cualquier otro formato nativo.

Este diseño implementa el patrón **hub-and-spoke**:

```
        PIX ──────────────────┐
        SPEI ─────────────────┤
        SWIFT MT103 ──────────┤──► Canonical pacs.008 ──► cualquier destino
        ISO 20022 MX ─────────┤
        ACH NACHA ────────────┤
        FedNow ───────────────┘
```

Sin este patrón, N formatos requerirían N×(N-1) traductores bilaterales. Con el modelo canónico, solo se necesitan 2×N (N hacia canónico + N desde canónico).

---

## Rieles soportados

| Rail | Protocolo real | Región | Moneda base | Estándar |
|------|---------------|--------|-------------|---------|
| PIX | BACEN SPI v2 (REST/JSON) | Brasil | BRL | ISO 20022 |
| SPEI | BANXICO CECOBAN (REST/JSON) | México | MXN | Propio |
| SWIFT_MT103 | SWIFT FIN text (bloques `:NN:`) | Internacional | USD/EUR/cualquiera | MT (legacy) |
| ISO20022_MX | pacs.008.001.08 (XML/JSON) | Internacional | EUR/cualquiera | ISO 20022 |
| ACH_NACHA | NACHA fixed-width 94 chars/línea | EE.UU. | USD | NACHA |
| FEDNOW | pacs.008.001.08 JSON + BAH | EE.UU. | USD | ISO 20022 |

---

## Modelo Canónico (CanonicalPacs008)

El modelo canónico es un objeto JSON validado con Zod que captura los campos semánticamente equivalentes entre todos los rieles:

```typescript
{
  payment_id: string,          // PMT-{ULID}
  grpHdr: {
    msgId: string,
    creDtTm: string,           // ISO 8601
    nbOfTxs: number,
    sttlmInf?: { sttlmMtd }   // CLRG | INDA | etc.
  },
  pmtId: {
    endToEndId: string,        // max 35 chars
    instrId?: string,
    txId?: string,
  },
  amount: {
    value: number,             // decimal, ej: 1500.00
    currency: string,          // ISO 4217: "USD", "BRL", "MXN"
    instdAmt?: number,         // monto instruido (antes de FX)
    instdAmtCcy?: string,
  },
  fx?: { rate, source_currency, local_amount },
  origin: {
    rail: Rail,                // riel de origen
    bic?: string,
    routingNumber?: string,    // ABA RTN (9 dígitos)
    ispb?: string,             // BACEN ISPB (8 dígitos)
    institutionCode?: string,  // BANXICO 3 dígitos
  },
  destination: { rail?, bic?, routingNumber?, ... },
  debtor: {
    name?: string,
    country?: string,
    account_id: string,
    taxId?: string,            // CPF/CNPJ/RFC/CURP/SSN/EIN
    agencia?: string,          // PIX: agencia bancaria
    email?: string,
    phone?: string,
  },
  creditor: { ...same as debtor },
  alias: {
    type: 'PIX_KEY'|'CLABE'|'IBAN'|'ACCOUNT'|'ABA_ROUTING'|'BIC',
    value: string,
  },
  purpose: string,
  reference: string,
  remittanceInfo?: string,
  status: PaymentStatus,
  trace_id?: string,
}
```

---

## Arquitectura de archivos

```
mipit-core/src/translation/
├── translator.ts                      ← Clase Translator (orquestador)
├── pix-to-canonical.ts                ← PIX SPI → canonical
├── canonical-to-pix.ts                ← canonical → PIX SPI
├── spei-to-canonical.ts               ← SPEI CECOBAN → canonical
├── canonical-to-spei.ts               ← canonical → SPEI CECOBAN
├── swift-mt103-to-canonical.ts        ← SWIFT MT103 FIN → canonical
├── canonical-to-swift-mt103.ts        ← canonical → SWIFT MT103 FIN
├── iso20022-mx-to-canonical.ts        ← ISO 20022 pacs.008 → canonical
├── canonical-to-iso20022-mx.ts        ← canonical → ISO 20022 pacs.008
├── ach-nacha-to-canonical.ts          ← NACHA records → canonical
├── canonical-to-ach-nacha.ts          ← canonical → NACHA records
├── fednow-to-canonical.ts             ← FedNow JSON → canonical
├── canonical-to-fednow.ts             ← canonical → FedNow JSON
└── mapping-loader.ts                  ← carga reglas de mapeo dinámico desde BD
```

---

## Clase Translator

```typescript
// Uso típico desde la API
const translator = new Translator(mappingLoader);

// Traducción directa entre dos rieles
const { canonical, translated } = await translator.translate(
  'PIX',           // sourceRail
  'SWIFT_MT103',   // destinationRail
  pixPayload,      // payload nativo
  'PMT-XXXX...',  // paymentId
  traceId,
);

// Solo convertir a canónico
const canonical = await translator.toCanonical('FEDNOW', fednowMsg, paymentId);

// Solo convertir desde canónico
const speiMsg = await translator.fromCanonical('SPEI', canonical);
```

---

## API endpoints de traducción

### `POST /translate`
Convierte entre dos rieles específicos. No persiste el pago.

```json
// Request
{
  "sourceRail": "PIX",
  "destinationRail": "SWIFT_MT103",
  "payload": { ...mensaje PIX nativo... },
  "options": { "includeCanonical": true }
}

// Response
{
  "paymentId": "PMT-...",
  "sourceRail": "PIX",
  "destinationRail": "SWIFT_MT103",
  "translated": { ...mensaje SWIFT MT103... },
  "canonical": { ...modelo canónico... },
  "translatedAt": "2023-06-01T12:00:00Z"
}
```

### `GET /translate/rails`
Devuelve metadatos de todos los rieles soportados.

### `POST /translate/preview`
Convierte a **todos los otros rieles simultáneamente** usando `Promise.allSettled()`. Útil para la UI del traductor.

```json
// Response
{
  "sourceRail": "PIX",
  "canonical": { ... },
  "translations": {
    "SPEI":        { "success": true,  "data": { ... } },
    "SWIFT_MT103": { "success": true,  "data": { ... } },
    "ISO20022_MX": { "success": true,  "data": { ... } },
    "ACH_NACHA":   { "success": true,  "data": { ... } },
    "FEDNOW":      { "success": false, "error": "..." }
  }
}
```

---

## Detalles de cada formato

### PIX (BACEN SPI v2)
- **EndToEndId**: `E{ISPB_8dig}{YYYYMMDD}{HHmm}{11_alphanum}` = 32 chars exactos
- **Identificación**: CPF (11 dígitos), CNPJ (14), PHONE (+55...), EMAIL, EVP (UUID)
- **Estado**: CONCLUIDA | NAO_REALIZADA | DEVOLVIDA | EM_PROCESSAMENTO
- **Errores**: AM04 (fondos), RR04 (propósito), DS04 (destino inaccesible)

### SPEI (BANXICO CECOBAN)
- **CLABE**: 18 dígitos, check digit = `(10 - (Σ dígito×peso[i]) mod 10) mod 10`
  - Pesos: [3,7,1,3,7,1,3,7,1,3,7,1,3,7,1,3,7]
  - Primeros 3 dígitos = código banco BANXICO (012=BBVA, 002=Banamex...)
- **claveRastreo**: max 30 chars alfanumérico
- **referenciaNumerica**: 7 dígitos
- **Errores**: R01 (fondos), R03 (cuenta no encontrada), LIM (límite excedido)

### SWIFT MT103
- Formato FIN text: `{1:...}{2:...}{4:\n:20:REF\n:23B:CRED\n...-}`
- Campos: `:20:` (ref), `:23B:` (op code), `:32A:` (fecha+moneda+monto), `:50K:` (ordenante), `:57A:` (banco intermediario), `:59:` (beneficiario), `:70:` (remittance), `:71A:` (cargos SHA/OUR/BEN)
- Monto: `230601USD1500,00` (coma como separador decimal)

### ISO 20022 MX (pacs.008.001.08)
- Estructura: `GrpHdr` + `CdtTrfTxInf`
- Agentes identificados por BICFI o ABA RTN (ClrSysMmbId)
- Cuentas: IBAN (starts con 2 letras) o Othr.Id
- Soporta FX: `XchgRate` + `InstdAmt`

### ACH NACHA
- Registros de 94 chars de ancho fijo, tipos: 1(File Header), 5(Batch), 6(Entry), 7(Addenda), 8(Batch Control), 9(File Control)
- Monto en centavos (entero, sin punto decimal)
- SEC codes: PPD (consumidor), CCD (empresa), IAT (internacional)
- Archivos deben tener múltiplos de 10 líneas (relleno con '9'×94)

### FedNow
- ISO 20022 JSON + Business Application Header (BAH)
- Solo USD, solo doméstico EE.UU.
- `UETR`: UUID v4 único por transacción
- Clearing: USABA (ABA routing 9 dígitos)
- `LclInstrm.Prtry: 'INST'` para pagos instantáneos

---

## Option A vs Option B

### Option A (implementado) — Solo traducción

Los rieles SWIFT, ISO20022, ACH, FedNow solo tienen **capa de traducción**. El sistema puede convertir sus formatos pero no envía pagos reales a esos rieles.

```
POST /translate → Translator.translate() → formato destino
```

### Option B (diseño futuro) — Adapter completo

Para enviar pagos reales a un nuevo riel se necesita un adapter con:
- Consumer RabbitMQ escuchando `payments.route.{RAIL}`
- Cliente HTTP que llama al endpoint real/mock del banco
- Publisher ACK a `payments.ack`

PIX y SPEI ya están implementados como Option B completo.
