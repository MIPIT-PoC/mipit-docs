# P03 — SPEI Spec Compliance

**Wave**: 2 (rail-specific)
**Repos afectados**: `mipit-adapter-spei`, `mipit-core`
**Branch**: `Auditoria-Claude`
**Estimación**: 2-3 días
**Riesgo**: Alto (auth paradigm change + 3-vs-5 digit institution codes son cambios cross-cutting)

---

## 1. Objetivo

Alinear SPEI con **Banxico Circular 14/2017 + STP WADL + cuenca-mx/stpmex-python**, dentro de límites PoC:

1. **Códigos institución 5-dígitos** del catálogo Banxico real (`40072`, `40012`, `90646`, etc.), no los 3-dígitos del CLABE prefix.
2. **`claveRastreo` solo alfanumérico** (sin guion, sin underscore), formato `[A-Za-z0-9]{1,30}`.
3. **Generar `claveRastreo` propio** en el mapper (no reusar `endToEndId` del core).
4. **RFC/CURP con checksum verification** (no solo regex de forma).
5. **`tipoPago` catalogue completo** (31 valores Banxico, no hard-coded a 1).
6. **Fix `settlementDelayMs` bug** (mock devuelve 202 EN_PROCESO → adapter falla).
7. **Operating hours correctos** (M-F 06:00-17:55 CT, no 07:00-17:30).
8. **Documentar explícitamente** que STP real usa firma RSA-SHA256, no OAuth2 (gap conocido, no resolvable en PoC mock).

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| B17 | **C** | Códigos institución 3-dig vs 5-dig Banxico real |
| B18 | **C** | Endpoint `/spei/v3/transferencias` no existe (STP real es SOAP) |
| B19 | **C** | STP no usa OAuth2, usa firma RSA |
| B20 | **C** | `claveRastreo` acepta `[A-Z0-9a-z\-_]` cuando CECOBAN solo permite alfanumérico |
| B21 | **C** | Core envía `endToEndId = E2E-${ulid()}` con guion como claveRastreo |
| B22 | H | `tipoPago` hard-coded 1; catálogo Banxico tiene 31 |
| B23 | M | `tipoCuentaBeneficiario` hard-coded 40; faltan 3/10/99 |
| B24 | M | RFC y CURP solo regex de forma, sin checksum |
| B25 | M | `conceptoPago` no strip-diacritics |
| B26 | H | Operating hours mock M-F 07:00-17:30 vs Banxico 06:00-17:55 |
| B27 | **C** | settlementDelayMs bug end-to-end |
| B28 | M | `referenciaNumerica` permite 0 (real 1-9_999_999) |
| B29 | **C** | `firma` RSA ausente (documented limitation) |
| B30 | H | CLABE no re-validada en emit (core/canonical-to-spei) |
| B31 | M | `monto` como number, STP espera string 2-decimal |
| B32 | H | Sin uniqueness check claveRastreo per institucion/día |

---

## 3. Out of scope

- **NO** se implementa firma RSA-PKCS#1 v1.5 SHA-256 (requeriría reescribir el mock como SOAP). **Documentado**.
- **NO** se cambia REST → SOAP en el mock (PoC scope).
- **NO** se implementa la cola de devoluciones SPEI tipo 4 (8=Devolución no acreditada, 12=Devolución extemporánea). Documentado.
- **NO** se conecta a STP demo real.

---

## 4. Dependencias

- **Bloquea**: P10 (testkit fixtures con CLABE válidas), P12 (docs).
- **Depende de**: P01 (canónico), P09 (DB).

---

## 5. Tareas detalladas

### 5.1 Catálogo Banxico 5-dígitos

Crear `mipit-adapter-spei/src/spei/banxico-catalog.ts`:

```ts
/**
 * Banxico SPEI participant codes (5-digit).
 * Source: https://www.banxico.org.mx/servicios/participantes-spei-banco-me.html
 *
 * Note: CLABE bank prefix (3 first digits) maps to a 5-digit institution code
 * via Banxico catalog. NOT the same number.
 */
export const BANXICO_INSTITUTION_CODES = {
  BANAMEX: '40002',
  BANCOMER: '40012', // BBVA Bancomer
  SANTANDER: '40014',
  HSBC: '40021',
  INBURSA: '40036',
  BAJIO: '40030',
  BANREGIO: '40058',
  AFIRME: '40062',
  BANORTE: '40072',
  SCOTIABANK: '40044',
  // Non-bank participants (PSPs / SOFOMs / SOFIPOs)
  STP: '90646',
  INTERCAM: '40136',
  CONSUBANCO: '40140',
  MIFEL: '40042',
  // ... (extender per catalog completo, ~200 entries)

  // Simulado para el PoC
  MIPIT_SIM: '90999', // 90xxx range is for non-bank participants
} as const;

/**
 * CLABE bank prefix (3 digits) → Banxico institution code (5 digits).
 * The mapping is many-to-one in some cases (multi-product banks share CLABE prefix).
 */
export const CLABE_PREFIX_TO_BANXICO: Record<string, string> = {
  '002': BANXICO_INSTITUTION_CODES.BANAMEX,
  '012': BANXICO_INSTITUTION_CODES.BANCOMER,
  '014': BANXICO_INSTITUTION_CODES.SANTANDER,
  '021': BANXICO_INSTITUTION_CODES.HSBC,
  '036': BANXICO_INSTITUTION_CODES.INBURSA,
  '030': BANXICO_INSTITUTION_CODES.BAJIO,
  '058': BANXICO_INSTITUTION_CODES.BANREGIO,
  '062': BANXICO_INSTITUTION_CODES.AFIRME,
  '072': BANXICO_INSTITUTION_CODES.BANORTE,
  '044': BANXICO_INSTITUTION_CODES.SCOTIABANK,
  '646': BANXICO_INSTITUTION_CODES.STP,
  '136': BANXICO_INSTITUTION_CODES.INTERCAM,
  '140': BANXICO_INSTITUTION_CODES.CONSUBANCO,
  '042': BANXICO_INSTITUTION_CODES.MIFEL,
  '999': BANXICO_INSTITUTION_CODES.MIPIT_SIM,
};

export function clabeToInstitutionCode(clabe: string): string | undefined {
  const prefix = clabe.slice(0, 3);
  return CLABE_PREFIX_TO_BANXICO[prefix];
}
```

- [ ] Crear archivo con catálogo (mínimo 20 entries cubriendo principales)
- [ ] Tests unitarios para mapping correcto
- [ ] Reemplazar uso de `SPEI_BANXICO_CODES` (constants 3-dig) en `types.ts:157-168` — **borrar esa constante**, todo va por el catálogo nuevo

### 5.2 Mapper usa código 5-dígitos

`mipit-adapter-spei/src/spei/mapper.ts:53-54`:

```ts
// ANTES
const institucionContraparte = canonical.destination.institutionCode ?? clabeDestino.substring(0, 3);

// DESPUÉS
import { clabeToInstitutionCode, BANXICO_INSTITUTION_CODES } from './banxico-catalog';

let institucionContraparte = canonical.destination.institutionCode;
if (!institucionContraparte) {
  institucionContraparte = clabeToInstitutionCode(clabeDestino);
  if (!institucionContraparte) {
    throw new Error(`Cannot resolve Banxico institution code for CLABE ${clabeDestino}`);
  }
}
if (!/^\d{5}$/.test(institucionContraparte)) {
  throw new Error(`institucionContraparte must be 5 digits, got: ${institucionContraparte}`);
}
```

### 5.3 Mock-server acepta 5-dígitos (y rechaza 3)

`mipit-adapter-spei/src/spei/mock-server.ts:171`:

```ts
// ANTES
const INSTITUCION_REGEX = /^\d{3,5}$/;

// DESPUÉS
const INSTITUCION_REGEX = /^\d{5}$/;
```

### 5.4 `claveRastreo` solo alfanumérico

`mipit-adapter-spei/src/spei/mock-server.ts:109`:

```ts
// ANTES
const CLAVERASTREO_REGEX = /^[A-Z0-9a-z\-_]{1,30}$/;

// DESPUÉS
const CLAVERASTREO_REGEX = /^[A-Za-z0-9]{1,30}$/;
```

### 5.5 Mapper genera `claveRastreo` propio (no reusa endToEndId con guion)

`mipit-adapter-spei/src/spei/mapper.ts:65` ya llama `generateSpeiClaveRastreo('MIPIT')`. **Bien**.

Pero el **core** `mipit-core/src/translation/canonical-to-spei.ts:20` re-envía `endToEndId` (que tiene guion E2E-XXX). El adapter actualmente lo ignora y genera el suyo en `mapper.ts:65`, pero la confusion entre `endToEndId` y `claveRastreo` queda.

- [ ] `canonical-to-spei.ts:20` **dejar de emitir** `claveRastreo`. El adapter lo genera.
- [ ] Output del core es `{ canonical, destination_rail }` ya — el adapter no lee `claveRastreo` del payload del core.

### 5.6 RFC checksum

Crear `mipit-adapter-spei/src/spei/rfc-curp-validator.ts`:

```ts
// RFC: 4 chars + 6 dígitos + 3 chars homoclave
// Last char (homoclave[2]) is mod-11 check on base-37 encoding of first 12 chars

const RFC_BASE37 = '0123456789ABCDEFGHIJKLMN&OPQRSTUVWXYZ '; // 37 chars
const RFC_BASE37_WEIGHTS = [13,12,11,10,9,8,7,6,5,4,3,2];

export function isValidRFC(rfc: string): boolean {
  const r = rfc.toUpperCase().trim();
  // Length 12 (juridica) or 13 (fisica)
  if (!/^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$/.test(r)) return false;

  // Padding: persona física (13 chars) skip the first char for checksum calc
  const padded = r.length === 12 ? ' ' + r : r; // 13 chars total
  const data = padded.slice(0, 12); // first 12 are checked
  const expectedCheck = r.slice(12); // homoclave[2] is check
  let sum = 0;
  for (let i = 0; i < 12; i++) {
    const idx = RFC_BASE37.indexOf(data[i]);
    if (idx === -1) return false;
    sum += idx * RFC_BASE37_WEIGHTS[i];
  }
  let check = 11 - (sum % 11);
  let checkChar = check === 11 ? '0' : (check === 10 ? 'A' : String(check));
  return r[12] === checkChar; // last homoclave char
}

// CURP: 18 chars. Last digit is mod-10 with weights and special encoding.
const CURP_VALUES: Record<string, number> = (() => {
  const chars = '0123456789ABCDEFGHIJKLMNÑOPQRSTUVWXYZ';
  const map: Record<string, number> = {};
  for (let i = 0; i < chars.length; i++) map[chars[i]] = i;
  return map;
})();

export function isValidCURP(curp: string): boolean {
  const c = curp.toUpperCase().trim();
  if (!/^[A-Z]{4}\d{6}[HM][A-Z]{5}[0-9A-Z]\d$/.test(c)) return false;
  // Mod-10 weighted sum, weights 18..1, on first 17 chars
  let sum = 0;
  for (let i = 0; i < 17; i++) {
    const v = CURP_VALUES[c[i]];
    if (v === undefined) return false;
    sum += v * (18 - i);
  }
  const check = (10 - (sum % 10)) % 10;
  return check === parseInt(c[17]);
}
```

- [ ] Crear archivo y tests con RFC/CURP conocidos reales
- [ ] Usar en `mock-server.ts:53-60` reemplazando los regex puros

### 5.7 `tipoPago` catalogue completo

`mipit-adapter-spei/src/spei/types.ts:63` actual: `1|2|3|4`. Reemplazar:

```ts
export const TIPO_PAGO_VALUES = [
  1, // SPEI Tercero a tercero (default)
  3, // SPEI Tercero a tercero entre cuentas propias
  4, // SPEI Mismo banco
  5, // Pago de nómina
  8, // Devolución no acreditada
  11, // Cobranza
  12, // Devolución extemporánea
  13, // Pago de servicios
  14, // Pago de impuestos federales
  15, // Pago de impuestos estatales
  16, // Tarjeta de débito
  17, // Tarjeta de crédito
  // ... up to 31 per Banxico catalog
] as const;

export type TipoPago = typeof TIPO_PAGO_VALUES[number];
```

- [ ] Reemplazar enum
- [ ] Mapper en core (`canonical-to-spei.ts`) infiere `tipoPago` desde `canonical.purpose`:
  - `SALA` → 5 (nómina)
  - `TAXS` → 14
  - `SUPP/COBR` → 11
  - default → 1
- [ ] `mock-server.ts` valida que `tipoPago ∈ TIPO_PAGO_VALUES`

### 5.8 `tipoCuentaBeneficiario` validation

- [ ] Mapper acepta `40|3|10|99` y los emite según `canonical.destination.account_type`:
  - account_id 18-digit numeric → 40 (CLABE)
  - account_id 16-digit numeric → 3 (tarjeta)
  - account_id `+52\d{10}` → 10 (celular)
  - default → 99
- [ ] Mock valida formato del account_id según `tipoCuentaBeneficiario` (currently solo valida CLABE)

### 5.9 `conceptoPago` strip-diacritics

`mipit-adapter-spei/src/spei/mapper.ts:58`:

```ts
import { remove as removeDiacritics } from 'diacritics'; // o impl inline

const concepto = (canonical.purpose ?? 'PAGO').slice(0, 39);
const conceptoAscii = removeDiacritics(concepto).replace(/[^\x20-\x7E]/g, '');
```

- [ ] Inline impl si se evita dependencia
- [ ] Test que "Pago de café" → "Pago de cafe"

### 5.10 Operating hours

`mipit-adapter-spei/src/spei/mock-server.ts:64-73` + `mipit-core/src/config/constants.ts:142`:

```ts
// Banxico Circular 14/2017: SPEI sessions M-F 06:00-17:55 CT (settlement to 18:00)
SPEI: { days: [1,2,3,4,5], startHhmm: 600, endHhmm: 1755 }
```

- [ ] Actualizar en ambos lados (mock y core constants)

### 5.11 Fix `settlementDelayMs` bug

`mipit-adapter-spei/src/spei/mock-server.ts:288-312`. **Opciones**:

**Opción A (rápida)**: Eliminar la feature `settlementDelayMs`. El mock siempre responde síncrono con LIQUIDADA o RECHAZADA.

**Opción B (correcta)**: Cuando `settlementDelayMs > 0`:
- HTTP response 202 con `estatus: 'EN_PROCESO'`
- `response-mapper.ts` debe mapear EN_PROCESO → status `PENDING` (no ERROR)
- Worker debe NACK con requeue después de `pollAfterMs`
- Después de la espera, mock actualiza el cached response a `LIQUIDADA`
- Próximo retry hace GET `/spei/v3/transferencias/:claveRastreo` y obtiene la respuesta final

**Recomendación**: Opción A para PoC (más rápido). Marcar Opción B como TODO P15.

- [ ] Eliminar branch `settlementDelayMs > 0` en mock
- [ ] Eliminar `settlementDelayMs` de admin endpoints en `admin-routes.ts:22, 74-76`
- [ ] Eliminar del UI Simulator page el slider settlementDelayMs (P11)

### 5.12 `monto` como string

`mipit-adapter-spei/src/spei/mapper.ts:80`:

```ts
// ANTES: monto: canonical.amount.value (number)
// DESPUÉS: monto: canonical.amount.value.toFixed(2) (string "100.50")
```

### 5.13 `referenciaNumerica` 1-9_999_999

`mock-server.ts:136`:

```ts
// ANTES: 0 ≤ x ≤ 9_999_999
// DESPUÉS: 1 ≤ x ≤ 9_999_999
if (refNum < 1 || refNum > 9_999_999) return reject('R03', 'Referencia inválida');
```

Y `types.ts:179`:

```ts
// ANTES
export function generateSpeiReferencia(): number {
  return Math.floor(Math.random() * 9999999);
}
// DESPUÉS
import { randomInt } from 'node:crypto';
export function generateSpeiReferencia(): number {
  return randomInt(1, 10_000_000); // 1..9_999_999
}
```

### 5.14 Uniqueness `claveRastreo` per día

Mock añade Map `claveRastreoByDay: Map<string, Set<string>>` keyed por `YYYYMMDD`:

```ts
const day = new Date().toISOString().slice(0, 10).replace(/-/g, '');
const dailySet = claveRastreoByDay.get(day) ?? new Set();
if (dailySet.has(claveRastreo)) {
  return reject('R05', 'claveRastreo duplicada en el día');
}
dailySet.add(claveRastreo);
claveRastreoByDay.set(day, dailySet);
```

- [ ] Implementar
- [ ] Test: dos POSTs mismo día con misma claveRastreo → segundo R05

### 5.15 CLABE validation en emit (core-side)

`mipit-core/src/translation/canonical-to-spei.ts:21` blindly emit. Agregar:

```ts
import { isValidCLABE } from '../../adapters/clabe-validator'; // o re-export desde adapter

if (!isValidCLABE(canonical.creditor.account_id)) {
  throw new Error(`Outbound SPEI requires valid CLABE, got: ${canonical.creditor.account_id}`);
}
```

(O importar el `validateClabeDetailed` que existe en el adapter como utility shared.)

### 5.16 Documentar gap STP-OAuth vs RSA

`mipit-adapter-spei/src/spei/mock-server.ts` header comment + `oauth-mock.ts` header:

```ts
/**
 * STP/SPEI Mock Server
 *
 * KNOWN GAP (PoC limitation):
 * - The endpoint `POST /spei/v3/transferencias` is **invented**. The real STP
 *   API exposes SOAP at `:7024/speiws/rest/...` with WADL spec.
 * - Real STP **does NOT use OAuth2**. STP uses RSA-PKCS#1 v1.5 + SHA-256
 *   signature on a canonical pipe-joined string of fields:
 *     empresa|claveRastreo|conceptoPago|cuentaBeneficiario|...|monto|...
 *   The signature is sent as a `firma` field alongside the order.
 *
 * This mock provides OAuth2 client_credentials for protocol uniformity across
 * the 3 rails in the PoC. For thesis honesty: document this gap.
 *
 * See: https://stp.mx/en/apis/
 *      https://github.com/cuenca-mx/stpmex-python
 */
```

---

## 6. Acceptance criteria

- [ ] `institucionContraparte` siempre 5 dígitos, mapeado correctamente desde CLABE prefix
- [ ] `claveRastreo` regex `^[A-Za-z0-9]{1,30}$`
- [ ] RFC checksum verificado
- [ ] CURP checksum verificado
- [ ] `tipoPago` enum extendido a 12+ valores, mapeado desde `canonical.purpose`
- [ ] `tipoCuentaBeneficiario` validation per format del account
- [ ] `conceptoPago` strip-diacritics
- [ ] Operating hours M-F 06:00-17:55 CT
- [ ] `settlementDelayMs` removido o correctamente manejado como PENDING
- [ ] `monto` como string 2-decimal
- [ ] `referenciaNumerica` 1-9_999_999
- [ ] Uniqueness check claveRastreo per día
- [ ] CLABE re-validada en core emit
- [ ] Mock header comment documenta gap OAuth-vs-firma RSA
- [ ] Test E2E PIX→SPEI verde con código institución 5-dig
- [ ] Test E2E SPEI→Bre-B verde

---

## 7. Testing plan

### Unit tests (`mipit-adapter-spei/test/unit/`)
- `spei/banxico-catalog.test.ts` — clabeToInstitutionCode known mappings
- `spei/rfc-validator.test.ts` — valid + invalid RFCs (incluye `SACR850101HDF` con check digit real)
- `spei/curp-validator.test.ts` — same
- `spei/claverastreo-uniqueness.test.ts` — dedup por día
- `spei/tipo-pago-inference.test.ts` — desde purpose

### Contract tests
- `test/contract/spei-mock.test.ts` — POST con institucionContraparte 3-dig rechazado; 5-dig accepted
- POST con claveRastreo con guion rechazado
- POST con RFC checksum inválido rechazado
- POST con `monto` number rechazado, string aceptado

### Integration tests
- `mipit-testkit/tests/integration/spei-institution-code.test.ts`
- `mipit-testkit/tests/integration/spei-clave-rastreo-format.test.ts`

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Tests existentes con `institucionContraparte: '072'` fallan | Actualizar fixtures masivamente; el cambio 3→5 dig es global |
| Core canonical-to-spei envío con CLABE inválida (de SWIFT translation) | P05 (FX) y P01 cubren propagation. Hasta entonces, reject early con clear error |
| `settlementDelayMs` removido rompe UI Simulator | Coord. P11 |
| RFC/CURP regex demasiado estrictos rompen fixtures | Permitir bypass en mock con `ENV.SPEI_MOCK_SKIP_CHECKSUM=true` para PoC |

---

## 9. Commits sugeridos

1. `feat(spei): introduce banxico catalog (5-digit institution codes)`
2. `fix(spei): claveRastreo must be alphanumeric only (no hyphen)`
3. `feat(spei): generate claveRastreo in adapter (not reuse endToEndId)`
4. `feat(spei): validate RFC mod-11 checksum`
5. `feat(spei): validate CURP mod-10 checksum`
6. `feat(spei): tipoPago catalog with 12+ values; inferred from purpose`
7. `feat(spei): tipoCuentaBeneficiario validation per account format`
8. `fix(spei): strip diacritics from conceptoPago`
9. `fix(spei): operating hours M-F 06:00-17:55 CT per Circular 14/2017`
10. `fix(spei): remove broken settlementDelayMs branch (or PENDING handling)`
11. `fix(spei): emit monto as 2-decimal string`
12. `fix(spei): referenciaNumerica range 1..9_999_999`
13. `feat(spei): claveRastreo uniqueness per day`
14. `fix(core): validate CLABE on outbound SPEI translation`
15. `docs(spei): document OAuth vs RSA-firma gap and invented endpoint`

---

## 10. Notas para el dev

- **No es producción**: el mock sigue siendo OAuth2 JSON. El cambio importante es la **honestidad documental**.
- **Catálogo Banxico**: el archivo `banxico-catalog.ts` puede crecer; el inicial cubre los principales. Plan futuro: cargar el catálogo desde un JSON externo descargado de banxico.org.mx.
- **`firma` RSA implementation futura**: requiere generar par de claves RSA, registrar pubkey en STP demo, firmar canonical string. Fuera de scope P03.
- **Para tesis**: enfatizar que `institucionContraparte` 5-dig es lo que un examinador con conocimiento de SPEI cazaría primero. Es la mejora visible más alta-ROI.
