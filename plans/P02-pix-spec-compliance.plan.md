# P02 — PIX Spec Compliance

**Wave**: 2 (rail-specific, post-canónico)
**Repos afectados**: `mipit-adapter-pix`, `mipit-core`
**Branch**: `Auditoria-Claude`
**Estimación**: 2-3 días
**Riesgo**: Medio (cambios en hot-path del adapter; tests existentes pueden romper)

---

## 1. Objetivo

Hacer que la implementación de PIX sea **fiel a la BCB Manual de Padrões para Iniciação do Pix v2.9.0**, dentro de lo posible para un PoC mock. Concretamente:

1. **EndToEndId con formato BCB exacto**: `E + ISPB(8) + YYYYMMDDHHMM(BRT) + 11 alnum = 32 chars`.
2. **Timezone Brasília (UTC-3)** en todos los IDs y timestamps generados, no UTC.
3. **Preservar `horario`** (timestamp de completed) end-to-end — no clobberearlo en el normalizer.
4. **Validar CPF/CNPJ con checksum mod-11**, no solo longitud regex.
5. **ISPB como first-class** en el modelo canónico, no opcional.
6. **Documentar explícitamente** que el endpoint `/spi/v2/pagamentos` es inventado (BCB SPI real es XML/RSFN, no REST).

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| B1 | **C** | EndToEndId mal formado (E2E-${ulid()} en lugar de E+ISPB+YYYYMMDDHHMM+11alnum) |
| B2 | **C** | EndToEndId en UTC en lugar de BRT |
| B3 | **C** | `horario` descartado en pix-to-canonical:117-148 |
| B4 | **C** | Endpoint `/spi/v2/pagamentos` no existe en BCB |
| B5 | H | OAuth scope `'spi.pagamentos'` inventada |
| B6 | H | Sin mTLS / certificados ICP-Brasil (documented limitation) |
| B7 | H | CPF/CNPJ sin checksum mod-11 |
| B8 | H | DICT consultation no implementada |
| B9 | M | `valor.original` como number, BCB exige string 2-decimal |
| B10 | M | `currency` variable cuando PIX es BRL-only |
| B11 | H | ISPB hard-coded sin marca "simulado" |
| B12 | M | EVP no validado como UUIDv4 |
| B13 | M | `tipo` hard-coded `'TRANSF'`, nunca COBR/DBOL |
| B14 | H | EM_PROCESSAMENTO → status 'ERROR' (debe ser pendiente+poll) |
| B16 | M | Suffix con `Math.random().padEnd(11,'0')` degrada entropía |
| C66 | H | `RAIL_OPERATING_HOURS.PIX` weekdays cuando es 24/7/365 |

---

## 3. Out of scope

- **NO** se implementa mTLS / ICP-Brasil certs (académico, documentado como limitación).
- **NO** se implementa endpoint real `/v2/cob` PSP-side (PoC simula SPI internal, no PSP frontend).
- **NO** se implementa DICT real (`GET /v2/dict/{key}`). Documentado.
- **NO** se implementa BR Code (`pixCopiaECola`) con CRC-16/CCITT-FALSE. Documentado.
- **NO** se implementa devoluções (`/v2/pix/{e2eid}/devolucao`). Documentado.

---

## 4. Dependencias

- **Bloquea**: P10 (testkit fixtures), P12 (docs).
- **Depende de**: P01 (canónico tiene UETR y status enum), P09 (DB tiene columnas ISO).

---

## 5. Tareas detalladas

### 5.1 `mipit-adapter-pix/src/pix/types.ts:182-188` — `generatePixEndToEndId`

**Spec BCB**: `E + ISPB(8 digits) + YYYYMMDDHHMM(BRT, 12 chars) + 11 alphanumeric = 32 chars total`.

Reemplazar:
```ts
// ANTES (incorrecto - UTC, padEnd degrada entropía)
export function generatePixEndToEndId(ispb: string): string {
  const now = new Date();
  const date = now.toISOString().slice(0, 10).replace(/-/g, ''); // UTC!
  const time = now.toISOString().slice(11, 16).replace(':', ''); // UTC!
  const unique = Math.random().toString(36).substring(2, 13).toUpperCase().padEnd(11, '0');
  return `E${ispb.padStart(8, '0')}${date}${time}${unique}`;
}

// DESPUÉS
import { randomBytes } from 'node:crypto';

export function generatePixEndToEndId(ispb: string, now: Date = new Date()): string {
  const ispbPadded = ispb.padStart(8, '0');
  if (!/^\d{8}$/.test(ispbPadded)) throw new Error(`Invalid ISPB: ${ispb}`);

  // Brasília time (UTC-3, no DST since 2019)
  const brtMs = now.getTime() - 3 * 3600 * 1000;
  const brt = new Date(brtMs);
  const yyyy = brt.getUTCFullYear();
  const mm = String(brt.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(brt.getUTCDate()).padStart(2, '0');
  const hh = String(brt.getUTCHours()).padStart(2, '0');
  const mi = String(brt.getUTCMinutes()).padStart(2, '0');
  const timestamp = `${yyyy}${mm}${dd}${hh}${mi}`; // 12 chars

  // 11 chars [A-Z0-9] from CSPRNG; if collision-rate matters, swap to 11-char base36
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const bytes = randomBytes(11);
  let suffix = '';
  for (let i = 0; i < 11; i++) suffix += alphabet[bytes[i] % alphabet.length];

  const id = `E${ispbPadded}${timestamp}${suffix}`;
  if (id.length !== 32) throw new Error(`EndToEndId length ${id.length} != 32`);
  return id;
}
```

- [ ] Reemplazar la función
- [ ] Marcar `MIPIT_FAKE_ISPB: '26264220'` con comentario inline: `// Fictitious ISPB for PoC; not registered with BACEN STR. Document in tesis.`
- [ ] Test unitario: el ID matches `/^E\d{8}\d{12}[A-Z0-9]{11}$/` y length === 32
- [ ] Test unitario: a las 23:30 BRT del 2026-05-15, el ID contiene `20260515` (no `20260516` UTC)
- [ ] Test unitario: 10000 IDs generados, todos únicos

### 5.2 `mipit-adapter-pix/src/pix/mock-server.ts:110` — relajar regex EndToEndId

BCB Manual permite `[A-Za-z0-9]` en el suffix; nuestro mock solo aceptaba uppercase.

```ts
// ANTES
const ENDTOENDID_REGEX = /^E\d{8}\d{8}\d{4}[A-Z0-9]{11}$/;

// DESPUÉS - case-insensitive suffix, plus split timestamp into date/time correctly
const ENDTOENDID_REGEX = /^E\d{8}\d{12}[A-Za-z0-9]{11}$/;
```

- [ ] Cambiar regex
- [ ] Documentar en comentario que la regex original era too strict

### 5.3 `mipit-adapter-pix/src/pix/mapper.ts:78-94` — preservar `dataHora` y eliminar UTC

- [ ] Eliminar generación de `dataHora: new Date().toISOString()`. En su lugar, usar `canonical.created_at` o el campo `horario` si viene del input.
- [ ] Si el caller sí necesita un `dataHora` nuevo (PoC translation step), generarlo con BRT (no UTC).

```ts
function brtIsoString(d: Date = new Date()): string {
  const brt = new Date(d.getTime() - 3 * 3600 * 1000);
  return brt.toISOString().replace(/Z$/, '-03:00');
}
```

### 5.4 `mipit-core/src/translation/pix-to-canonical.ts:117-148` — preservar `horario`

Native PIX payload tiene `horario` (timestamp del completed). Actualmente se descarta.

- [ ] Si el input tiene `horario`, mapearlo a `canonical.grpHdr.creDtTm` (no `created_at` que es interno MiPIT)
- [ ] Si no tiene horario, generar con BRT (no `new Date().toISOString()` que es UTC)

### 5.5 `mipit-core/src/normalization/rules/date-rules.ts:19` — NO clobberear si input ya es válido

```ts
// ANTES
canonical.grpHdr.creDtTm = safeToISO(canonical.grpHdr.creDtTm);

// DESPUÉS — preserve if valid ISO 8601
if (!canonical.grpHdr.creDtTm) {
  canonical.grpHdr.creDtTm = new Date().toISOString();
} else if (!isValidIsoDateTime(canonical.grpHdr.creDtTm)) {
  // Try to parse and re-emit ISO
  const parsed = new Date(canonical.grpHdr.creDtTm);
  if (isNaN(parsed.getTime())) {
    throw new ValidationError(`Invalid creDtTm: ${canonical.grpHdr.creDtTm}`);
  }
  canonical.grpHdr.creDtTm = parsed.toISOString();
}
// else: keep as-is
```

### 5.6 CPF/CNPJ checksum validation

Crear `mipit-adapter-pix/src/pix/cpf-cnpj-validator.ts`:

```ts
export function isValidCPF(cpf: string): boolean {
  const digits = cpf.replace(/\D/g, '');
  if (digits.length !== 11) return false;
  if (/^(\d)\1+$/.test(digits)) return false; // all same digit (00000000000, 11111111111)
  // mod-11 weights [10..2] for first check digit
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += parseInt(digits[i]) * (10 - i);
  let d1 = 11 - (sum % 11);
  if (d1 >= 10) d1 = 0;
  if (d1 !== parseInt(digits[9])) return false;
  // mod-11 weights [11..2] for second check digit
  sum = 0;
  for (let i = 0; i < 10; i++) sum += parseInt(digits[i]) * (11 - i);
  let d2 = 11 - (sum % 11);
  if (d2 >= 10) d2 = 0;
  return d2 === parseInt(digits[10]);
}

export function isValidCNPJ(cnpj: string): boolean {
  const digits = cnpj.replace(/\D/g, '');
  if (digits.length !== 14) return false;
  if (/^(\d)\1+$/.test(digits)) return false;
  // mod-11 weights for first check digit: [5,4,3,2,9,8,7,6,5,4,3,2]
  const w1 = [5,4,3,2,9,8,7,6,5,4,3,2];
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += parseInt(digits[i]) * w1[i];
  let d1 = 11 - (sum % 11);
  if (d1 >= 10) d1 = 0;
  if (d1 !== parseInt(digits[12])) return false;
  // mod-11 weights for second check digit: [6,5,4,3,2,9,8,7,6,5,4,3,2]
  const w2 = [6,5,4,3,2,9,8,7,6,5,4,3,2];
  sum = 0;
  for (let i = 0; i < 13; i++) sum += parseInt(digits[i]) * w2[i];
  let d2 = 11 - (sum % 11);
  if (d2 >= 10) d2 = 0;
  return d2 === parseInt(digits[13]);
}
```

- [ ] Crear archivo y exportar
- [ ] Tests unitarios con casos conocidos válidos (`12345678909` CPF, `12345678000195` CNPJ — check digits reales) y inválidos
- [ ] Usar en `mock-server.ts` CHAVE_VALIDATORS para CPF/CNPJ
- [ ] Usar en `mapper.ts:116-122` `buildPixIdentity` para validar antes de mapper

### 5.7 EVP validation (UUIDv4 variant/version bits)

`mipit-adapter-pix/src/pix/mock-server.ts:62`. UUID v4 format spec: bits del 7° byte `0100xxxx`, bits del 9° byte `10xxxxxx`.

```ts
const UUIDV4_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
```

- [ ] Actualizar regex EVP
- [ ] En mapper, si la chave no matches ningún tipo conocido, **rechazar con MAPPING_ERROR** en lugar de defaultear a 'EVP' (B12).

### 5.8 `valor.original` como string

`mipit-adapter-pix/src/pix/mapper.ts:40` y client.ts:

```ts
// BCB: valor.original es string con punto decimal exacto 2 decimales: "100.50"
// const valor = { original: canonical.amount.value }; // ANTES: number
const valor = { original: canonical.amount.value.toFixed(2) }; // DESPUÉS: string
```

- [ ] Actualizar mapper para emitir string 2-decimal
- [ ] Mock-server regex acepta `^\d+\.\d{2}$` (ya lo hace)

### 5.9 Hardcodear currency = BRL

```ts
// mapper.ts
if (canonical.amount.currency !== 'BRL') {
  throw new Error(`PIX rail only supports BRL, got ${canonical.amount.currency}`);
}
// Output no incluye currency — implícito
```

### 5.10 ISPB en canonical model

Coordinar con P01. `canonical.origin.ispb` ya existe pero opcional. Cambios:

- [ ] Para mensajes PIX, hacer mandatorio
- [ ] Default `ENV.MIPIT_FAKE_ISPB` si no viene
- [ ] Persistir en `payments.metadata` JSONB o agregar columna `origin_ispb VARCHAR(8)` (decidir con P09)
- [ ] Test que verifica round-trip preserva ISPB

### 5.11 `tipo` enum complete

`mipit-adapter-pix/src/pix/mock-server.ts:164` acepta `['TRANSF','COBR','DBOL']`. Agregar `DEVOL` (devolução):

- [ ] `mock-server.ts:164` enum incluye `'DEVOL'`
- [ ] Mapper en `mipit-core/src/translation/canonical-to-pix.ts` setea `tipo` basado en `canonical.purpose` o canonical heuristic:
  - `purpose = 'REFUND'` → `DEVOL`
  - `purpose = 'COBR'` o tiene `txid` → `COBR`
  - `purpose = 'DEPOSIT'` → `DBOL` (boleto)
  - default → `TRANSF`

### 5.12 EM_PROCESSAMENTO → status PENDING (no ERROR)

`mipit-adapter-pix/src/pix/response-mapper.ts:51-60`:

```ts
// ANTES
case 'EM_PROCESSAMENTO':
  return { status: 'ERROR', code: 'PIX_PENDING', message: 'Pagamento em processamento' };

// DESPUÉS
case 'EM_PROCESSAMENTO':
  return {
    status: 'PENDING', // requires updating RailAck type to include PENDING
    code: 'PIX_PENDING',
    message: 'Pagamento em processamento',
    poll_after_ms: 5000 // hint to retry
  };
```

- [ ] Agregar `PENDING` al `RailAck` type
- [ ] Core consumer maneja PENDING: no marca como FAILED, dispara polling (siguiente plan o stub para ahora)
- [ ] Por simplicidad PoC: PENDING → mensaje vuelve a route queue tras 5s (NACK + requeue una vez)

### 5.13 RAIL_OPERATING_HOURS — PIX 24/7

`mipit-core/src/config/constants.ts:140`:

```ts
// ANTES
PIX: { days: [1,2,3,4,5,6], startHhmm: 700, endHhmm: 2359 }

// DESPUÉS
PIX: { days: [0,1,2,3,4,5,6], startHhmm: 0, endHhmm: 2400 } // 24/7/365 per BACEN Resolução 1/2020
```

- [ ] Actualizar
- [ ] Test que `isRailOpen('PIX', anyTime)` siempre retorna `true`

### 5.14 Documentar endpoint y mock como invented

`mipit-adapter-pix/src/pix/mock-server.ts:8-15` header comment. Reemplazar:

```ts
/**
 * PIX SPI Mock Server
 *
 * NOTE (PoC limitation): The endpoint `POST /spi/v2/pagamentos` is **invented**.
 * The real BCB PIX architecture exposes:
 *   - `/v2/cob{txid}`, `/v2/cobv/{txid}`, `/v2/pix/{e2eid}` etc. on the PSP-side
 *     (REST + OAuth2 client_credentials + mTLS with ICP-Brasil certificate)
 *   - SPI itself (Sistema de Pagamentos Instantâneos) is XML messages over RSFN
 *     (Rede do Sistema Financeiro Nacional), not a public REST API.
 *
 * This mock provides a stylized "SPI settlement" REST API for academic interop
 * demonstration. The shapes (field names, EndToEndId format, chave types,
 * BACEN error codes) follow BCB Manual de Padrões para Iniciação do Pix v2.9.0
 * to the extent possible.
 *
 * For thesis-defense honesty: explicitly cite this gap in the Limitations
 * section of the dissertation.
 */
```

### 5.15 OAuth scope — alinear con BCB real

`mipit-adapter-pix/src/pix/client.ts:20` scope `'spi.pagamentos'`. Real scope BCB: `'cob.write cob.read cobv.write cobv.read pix.read pix.write'`.

Decisión PoC: dejar `'spi.pagamentos'` como invented scope (no es PSP-facing) **pero agregar comentario inline** que cite los scopes reales BCB:

```ts
// scope 'spi.pagamentos' is invented for this PoC SPI-level mock.
// Real BCB PSP-facing scopes: 'cob.write cob.read cobv.write cobv.read pix.read pix.write'
// See: https://bacen.github.io/pix-api/
```

---

## 6. Acceptance criteria

- [ ] `generatePixEndToEndId` produce IDs de 32 chars exactos, regex `^E\d{8}\d{12}[A-Z0-9]{11}$`
- [ ] Timestamp embebido en EndToEndId está en BRT (test con `2026-05-15T23:30:00-03:00` → contiene `20260515`)
- [ ] `pix-to-canonical.ts` preserva `horario` cuando viene en input
- [ ] CPF inválido (`12345678901`, checksum wrong) es rechazado por el mock con AC03
- [ ] CNPJ inválido es rechazado
- [ ] EVP malformado (no UUIDv4) es rechazado
- [ ] EM_PROCESSAMENTO no produce ACK FAILED — el payment queda en QUEUED/PENDING
- [ ] `RAIL_OPERATING_HOURS.PIX` permite 24/7
- [ ] Test E2E PIX→SPEI verde con el nuevo EndToEndId
- [ ] Test E2E SPEI→PIX verde
- [ ] Mock-server comment menciona la limitación del endpoint inventado
- [ ] Suite `validate:suite` 11/11 verde
- [ ] **EndToEndId persistido en `payments.metadata` o `payments.end_to_end_id` column** (coord. P09)

---

## 7. Testing plan

### Unit tests (`mipit-adapter-pix/test/unit/`)
- `pix/end-to-end-id.test.ts` — formato, length, timezone BRT, uniqueness
- `pix/cpf-validator.test.ts` — valid + invalid known CPFs
- `pix/cnpj-validator.test.ts` — same
- `pix/evp-validator.test.ts` — UUIDv4 variant/version bits

### Mock test (`mipit-adapter-pix/test/contract/pix-mock.test.ts`)
- POST con EndToEndId malformado → 400
- POST con CPF inválido → 400 AC03
- POST con EVP no UUIDv4 → 400
- POST con `valor.original` como number (no string) → 400
- POST con `tipo: 'DEVOL'` → 200

### Integration test (`mipit-testkit/tests/integration/`)
- `pix-end-to-end-id-format.test.ts` — POST /payments PIX→SPEI, GET retorna pago, EndToEndId matches regex BCB
- `pix-horario-preservation.test.ts` — POST con `horario`, GET retorna `creDtTm` igual

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Tests existentes con EndToEndId fake `E1234567820260413120501234567890` (digits only) fallan | Actualizar fixtures a EndToEndId con suffix alphanumeric `[A-Z0-9]{11}` |
| `dataHora` change rompe response-mapper | Cubierto por contract test |
| `EM_PROCESSAMENTO → PENDING` rompe state machine | P06 actualiza state machine; mientras tanto, PENDING = stay in QUEUED + requeue once |
| Adapter no recibe el ISPB desde canonical | P01 lo persiste, mapper hace fallback a `ENV.MIPIT_FAKE_ISPB` |

---

## 9. Commits sugeridos

1. `feat(pix): generate EndToEndId per BCB Manual de Padrões (E+ISPB+BRT+11alnum)`
2. `feat(pix): validate CPF and CNPJ mod-11 checksum`
3. `feat(pix): validate EVP as UUIDv4 with variant/version bits`
4. `fix(pix): preserve horario timestamp through canonical pipeline`
5. `fix(pix): valor.original emitted as 2-decimal string, not number`
6. `fix(pix): EM_PROCESSAMENTO → PENDING (not ERROR)`
7. `fix(pix): tipo enum includes DEVOL; mapper sets from purpose`
8. `fix(config): PIX operating hours 24/7/365 per BACEN Resolução 1/2020`
9. `docs(pix): document mock as invented endpoint not BCB PSP-compatible`
10. `chore(pix): mark MIPIT_FAKE_ISPB as simulated in comments`

---

## 10. Notas para el dev

- **BRT is UTC-3 with no DST** since 2019. Hard-code `-3*3600*1000`. Do NOT use `Intl.DateTimeFormat('America/Sao_Paulo')` for ID generation (too slow at hot-path; spec is fixed).
- **`MIPIT_FAKE_ISPB = '26264220'`** must be marked as "simulado" in code, in README, in tesis.
- **DICT consultation gap** → mock should at least return reasonable resolved party data when chave is queried (the mapper already fills placeholders; document this is "DICT-lookup simulated by mock").
- **`pixCopiaECola` BR Code**: NOT implementing CRC-16/CCITT-FALSE; explicit `// TODO P15` comment.
