# P04 — Bre-B Completion & Honest Documentation

**Wave**: 2 (rail-specific)
**Repos afectados**: `mipit-adapter-breb`, `mipit-core`, `mipit-infra`, `mipit-docs`
**Branch**: `Auditoria-Claude`
**Estimación**: 3 días
**Riesgo**: Alto (Bre-B es el rail más débilmente cubierto; muchas cosas a la vez)

---

## 1. Objetivo

Llevar a Bre-B al nivel de cobertura "Option-B full" que tienen PIX y SPEI, con **honestidad académica explícita** sobre que la wire-format spec es invented (BanRep no publicó). Concretamente:

1. **Tipos de llave completos**: agregar **CC (cédula), CE (cédula extranjería), Pasaporte**.
2. **Regex llave alfanumérica acepta `@` prefix** y `.`/`_` (formato BanRep).
3. **Phone `+57 3xx`** only (móvil), no fijos.
4. **Códigos entidad 4-dígitos Superfinanciera** real (no 8-padded inventados).
5. **Timezone Bogotá (UTC-5)** en `idTransaccion`, no UTC.
6. **Crear `retry.ts`** uniforme con PIX/SPEI.
7. **Fix import roto** en `breb-translation.test.ts`.
8. **Agregar contract tests** (cubre el gap "cero contract test").
9. **Cablear `brebRetryCount` metric** (currently dead).
10. **Agregar filas `mapping_table`** Bre-B (P09 hace el schema, P04 agrega data).
11. **Llaves: COP sin decimales** en limits (no 2 decimal float).
12. **Documentar wire-format como "invented"** en header comments.
13. **Operating hours 24/7** (BanRep mandato).

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| B33 | **C** | Cero spec pública; código asserta "BanRep v1.0 (2023)" inexistente |
| B34 | **C** | Llave types: faltan CC, CE, Pasaporte |
| B35 | H | Regex alfanumérica rechaza `@` prefix BanRep |
| B36 | H | Phone +57 acepta fijos (real: solo móviles +57 3xx) |
| B37 | H | Códigos entidad 8-dig vs 4-dig Superfinanciera |
| B38 | H | Límites COP 20M/200M vs real ~10M natural |
| B39 | H | `idTransaccion` UTC vs COT (UTC-5) |
| B40 | H | Operating hours 06-22 vs 24/7 real |
| B41 | M | Triple strip de `BREB-` prefix entre 3 capas |
| B42 | M | Mock no simula directorio Bre-B |
| B43 | M | `valor.original` 2-decimal cuando COP no tiene centavos |
| D1 | **C** | BREB sin `retry.ts` (inlinea backoff) |
| D2 | **C** | `brebRetryCount` métrica nunca incrementada |
| D3 | **C** | Test broken: import `brebToCanonical` from `types` (no exportado) |
| D4 | **C** | Cero contract test |
| D5 | H | `RAIL = 'BRE_B'` underscore cross-system inconsistency |
| E19 | **C** | `mapping_table` 0 rows Bre-B — adapter hard-coded |
| H17 | H | `translation-layer.md` omite Bre-B |
| H16 | M | `architecture-overview.md` solo PIX/SPEI |
| C67 | H | `RAIL_OPERATING_HOURS.BRE_B` weekdays cuando es 24/7 |

---

## 3. Out of scope

- **NO** se conecta a BanRep real (no hay sandbox público).
- **NO** se implementa directorio Bre-B real (simulación PoC). Documentado.
- **NO** se reescribe el shape `BreBPaymentRequest` para matchear el (no-publicado) wire format. **Documentar como "reference implementation pending BanRep spec"**.
- **NO** se cambia `RAIL = 'BRE_B'` (underscore) — eso impactaría cross-system. Documentado como decisión.

---

## 4. Dependencias

- **Bloquea**: P10 (testkit Bre-B fixtures), P12 (docs).
- **Depende de**: P01 (canónico), P09 (DB).

---

## 5. Tareas detalladas

### 5.1 Tipos de llave completos

`mipit-adapter-breb/src/breb/types.ts:12`:

```ts
// ANTES
export type BreBKeyType = 'TELEFONO' | 'NIT' | 'EMAIL' | 'ALIAS';

// DESPUÉS
export type BreBKeyType =
  | 'CC'          // Cédula de ciudadanía (6-10 dígitos)
  | 'CE'          // Cédula de extranjería (6-7 dígitos)
  | 'NIT'         // NIT (9-10 dígitos + dígito verificación)
  | 'PASAPORTE'   // Pasaporte (alphanumérico variable)
  | 'TELEFONO'    // +57 3XX XXX XXXX (móvil only)
  | 'EMAIL'       // RFC 5321
  | 'ALIAS';      // @alphanumérico con `.`/`_` permitidos
```

### 5.2 Regex llaves correctas

`mipit-adapter-breb/src/breb/mock-server.ts:59-64`:

```ts
const LLAVE_VALIDATORS: Record<BreBKeyType, RegExp> = {
  CC: /^\d{6,10}$/,
  CE: /^\d{6,7}$/,
  NIT: /^\d{9,10}-\d$/, // siempre con dígito verificación
  PASAPORTE: /^[A-Z0-9]{6,12}$/i,
  TELEFONO: /^\+573\d{9}$/, // móvil only: +57 3xx XXX XXXX (10 digits after +57)
  EMAIL: /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
  ALIAS: /^@[a-zA-Z0-9._]{3,19}$/, // BanRep: @ prefix + 3-19 alphanumerics + `.`/`_`
};
```

- [ ] Reemplazar regex
- [ ] **Importante**: NIT debería validar dígito de verificación DIAN mod-11 (similar al de CPF/CNPJ). Implementar `isValidNIT(nit)`:

```ts
const NIT_WEIGHTS = [41,37,29,23,19,17,13,7,3]; // 9 digit weights (right-to-left)

export function isValidNIT(nitWithCheck: string): boolean {
  const m = nitWithCheck.match(/^(\d{9,10})-(\d)$/);
  if (!m) return false;
  const digits = m[1].split('').reverse();
  const check = parseInt(m[2]);
  let sum = 0;
  for (let i = 0; i < digits.length; i++) sum += parseInt(digits[i]) * NIT_WEIGHTS[i];
  const rem = sum % 11;
  const expected = rem < 2 ? rem : 11 - rem;
  return expected === check;
}
```

### 5.3 Mapper infer tipoLlave correcto

`mipit-adapter-breb/src/breb/mapper.ts:60-64`:

```ts
function inferTipoLlave(llave: string): BreBKeyType {
  if (/^\+573\d{9}$/.test(llave)) return 'TELEFONO';
  if (/^\d{9,10}-\d$/.test(llave)) return 'NIT';
  if (/^\d{6,7}$/.test(llave)) return 'CE'; // shorter than CC
  if (/^\d{6,10}$/.test(llave)) return 'CC';
  if (/^[A-Z0-9]{6,12}$/i.test(llave)) return 'PASAPORTE'; // careful: could conflict with ALIAS without @
  if (llave.includes('@') && llave.includes('.')) return 'EMAIL';
  if (/^@[a-zA-Z0-9._]{3,19}$/.test(llave)) return 'ALIAS';
  throw new Error(`Unable to infer Bre-B key type for: ${llave}`);
}
```

- [ ] Reemplazar la inferencia
- [ ] **Importante**: si la llave es ambigua (e.g. `1234567` puede ser CC 7-dig o CE 7-dig), **el caller debe explicitar `tipoLlave`** en el canonical. Default a CC para 7-dig en Colombia (más común).
- [ ] Eliminar `else → 'ALIAS'` default (era catch-all que enmascara errores)

### 5.4 Códigos entidad 4-dígitos Superfinanciera

`mipit-adapter-breb/src/breb/types.ts:75-82`. Reemplazar con catálogo real:

```ts
/**
 * Códigos de entidad Superfinanciera (4 dígitos).
 * Source: Banco de la República - Catálogo de participantes SPI / Bre-B.
 */
export const SUPERFIN_ENTITY_CODES = {
  BANCO_DE_BOGOTA: '0001',
  CITIBANK: '0009',
  BANCO_AGRARIO: '0040',
  BANCO_DE_OCCIDENTE: '0023',
  BANCOLOMBIA: '0007',
  BBVA_COLOMBIA: '0013',
  DAVIVIENDA: '0051',
  AV_VILLAS: '0052',
  POPULAR: '0002',
  COLPATRIA: '0019', // ahora Scotiabank Colpatria
  ITAU: '0006',
  FALABELLA: '0058',
  NEQUI: '0507', // SEDPE de Bancolombia
  DAVIPLATA: '0551', // SEDPE de Davivienda
  // PoC simulated
  MIPIT_FINTECH_SIM: '9999', // 9xxx reservado para PoC/simulación
} as const;

export type SuperfinEntityCode = typeof SUPERFIN_ENTITY_CODES[keyof typeof SUPERFIN_ENTITY_CODES];
```

- [ ] Reemplazar `BREB_ENTITY_CODES` (8-dig) con `SUPERFIN_ENTITY_CODES` (4-dig)
- [ ] Mock-server `\d{8}` regex en `:109, 127` → `\d{4}`
- [ ] Mapper en core `canonical-to-breb.ts` usa los códigos 4-dig
- [ ] Actualizar tests fixtures

### 5.5 `idTransaccion` en COT (UTC-5)

`mipit-adapter-breb/src/breb/types.ts:88-96`:

```ts
import { randomBytes } from 'node:crypto';

export function generateBrebTransactionId(codigoEntidad: string, now: Date = new Date()): string {
  if (!/^\d{4}$/.test(codigoEntidad)) {
    throw new Error(`Bre-B entity code must be 4 digits, got: ${codigoEntidad}`);
  }

  // Bogotá time UTC-5 (no DST since 1992)
  const cot = new Date(now.getTime() - 5 * 3600 * 1000);
  const yyyy = cot.getUTCFullYear();
  const mm = String(cot.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(cot.getUTCDate()).padStart(2, '0');
  const hh = String(cot.getUTCHours()).padStart(2, '0');
  const mi = String(cot.getUTCMinutes()).padStart(2, '0');
  const date = `${yyyy}${mm}${dd}`; // 8 chars
  const time = `${hh}${mi}`; // 4 chars

  // 10 chars [A-Z0-9] from CSPRNG
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const bytes = randomBytes(10);
  let suffix = '';
  for (let i = 0; i < 10; i++) suffix += alphabet[bytes[i] % alphabet.length];

  // Note: format is INVENTED for this PoC. BanRep has not published wire-level spec.
  // Structure: BR + entidad(4) + date(8) + time(4) + suffix(10) = 28 chars
  return `BR${codigoEntidad}${date}${time}${suffix}`;
}
```

- [ ] Reemplazar la función
- [ ] **El length cambia**: era 32 chars (BR+8+8+4+10), ahora 28 chars (BR+4+8+4+10). **Actualizar mock regex** en `mock-server.ts:82`:

```ts
const IDTRANSACCION_REGEX = /^BR\d{4}\d{8}\d{4}[A-Z0-9]{10}$/;
```

### 5.6 COP sin decimales

`mipit-adapter-breb/src/breb/mock-server.ts:92`:

```ts
// ANTES
const VALOR_REGEX = /^\d+\.\d{2}$/; // expects 2 decimals
// DESPUÉS
const VALOR_REGEX = /^\d+(\.\d{2})?$/; // COP integer, but allow .00 for backward-compat
```

- [ ] Mapper en `canonical-to-breb.ts` emite COP como integer:

```ts
const valor = canonical.amount.currency === 'COP'
  ? { original: String(Math.round(canonical.amount.value)) } // integer
  : { original: canonical.amount.value.toFixed(2) };
```

### 5.7 Límites COP corregidos

`mipit-adapter-breb/src/breb/mock-server.ts:55-56`:

```ts
// ANTES
const LIMIT_NATURAL_COP = 20_000_000;
const LIMIT_JURIDICA_COP = 200_000_000;
// DESPUÉS — per BanRep at Bre-B launch (2025)
const LIMIT_NATURAL_COP = 10_000_000; // ~ USD 2,500
const LIMIT_JURIDICA_COP = 50_000_000; // initial; scales over time
```

Documentar como "valores iniciales BanRep Bre-B 2025; ajustable por env var en producción real".

### 5.8 Operating hours 24/7

`mipit-core/src/config/constants.ts:142`:

```ts
// ANTES
BRE_B: { days: [1,2,3,4,5], startHhmm: 600, endHhmm: 2200 }
// DESPUÉS
BRE_B: { days: [0,1,2,3,4,5,6], startHhmm: 0, endHhmm: 2400 } // 24/7/365 per BanRep
```

Mock-server ya no enforça hours (correcto). Eliminar cualquier branch que lo haga.

### 5.9 Crear `retry.ts` uniforme

Crear `mipit-adapter-breb/src/breb/retry.ts` espejo de PIX:

```ts
import { brebRetryCount } from '../observability/metrics';

export interface RetryOptions {
  maxAttempts?: number;
  baseDelayMs?: number;
  jitter?: boolean;
}

export async function withRetry<T>(
  fn: (attempt: number) => Promise<T>,
  opts: RetryOptions = {}
): Promise<T> {
  const maxAttempts = opts.maxAttempts ?? 3;
  const baseDelayMs = opts.baseDelayMs ?? 500;
  const jitter = opts.jitter ?? true;

  let lastErr: unknown;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const result = await fn(attempt);
      if (attempt > 1) brebRetryCount.inc({ status: 'recovered' });
      return result;
    } catch (err) {
      lastErr = err;
      brebRetryCount.inc({ status: 'failed' });

      // Classify: 4xx is permanent
      const isPermanent = err instanceof BreBPermanentError;
      if (isPermanent || attempt === maxAttempts) throw err;

      const expDelay = baseDelayMs * Math.pow(2, attempt - 1);
      const delay = jitter ? Math.random() * expDelay : expDelay;
      await new Promise(r => setTimeout(r, delay));
    }
  }
  throw lastErr;
}

export class BreBPermanentError extends Error {
  constructor(message: string, public statusCode: number, public body: unknown) {
    super(message);
  }
}
```

- [ ] Crear archivo
- [ ] Refactorizar `client.ts:48-116` para usar `withRetry`
- [ ] Eliminar el loop inline
- [ ] **`brebRetryCount.inc()` ahora se llama** — cerrando D2

### 5.10 Fix import roto en test

`mipit-adapter-breb/test/unit/breb-translation.test.ts:6`:

```ts
// ANTES (broken)
import { brebToCanonical } from '../../src/breb/types';

// DESPUÉS — el helper estaba en mapper.ts o no existía
// Si la función no existe, crearla en mapper.ts o eliminar el test
```

- [ ] Auditar qué quería testear este archivo
- [ ] Si era para `canonicalToBrebPayload` o `brebToCanonical`, importar desde `mapper.ts`
- [ ] Si era placeholder, eliminar o reescribir

### 5.11 Contract tests

Crear `mipit-adapter-breb/test/contract/breb-mock.test.ts` (mirror de pix-mock.test.ts y spei-mock.test.ts):

```ts
describe('Bre-B mock server contract', () => {
  it('rejects llave CC con dígitos no válidos');
  it('rejects llave NIT sin dígito verificación');
  it('rejects llave NIT con check digit incorrecto');
  it('rejects telefono fijo (+57 1...)');
  it('accepts telefono móvil (+57 3...)');
  it('rejects alias sin @ prefix');
  it('rejects codigoEntidad 8-digit (real es 4)');
  it('idempotency por idTransaccion: segunda request retorna cached');
  it('OAuth: valid client returns token, invalid 401');
  it('admin force-reject works');
  it('admin reset works');
  it('amount over COP limit returns BREB003 LIMIT_EXCEEDED');
});
```

- [ ] Crear archivo con todos los casos
- [ ] Verificar que pasen

### 5.12 Eliminar triple strip `BREB-` prefix

El prefijo se inyecta en core API schema → strip-ea en `canonical-to-breb.ts:43` → re-strip en `adapter/mapper.ts:58`. **Una sola capa**:

- [ ] **Decisión**: el canónico NO debe contener prefijo. El prefijo es **routing concern** solo.
- [ ] `mipit-core/src/translation/breb-to-canonical.ts` y `pix-to-canonical.ts`, `spei-to-canonical.ts`: al canonicalize, **strip prefix una vez**.
- [ ] `mipit-core/src/translation/canonical-to-{breb,pix,spei}.ts`: al emitir, **no agregar prefix** (es responsabilidad del API public schema, no del canónico interno).
- [ ] Adapter mapper: **trust input, no strip**. Si el adapter recibe un prefix, es bug del core upstream — log warning, no strip.

### 5.13 mapping_table rows para BRE_B

Crear migration `mipit-infra/db/init/006_seed_breb_mappings.sql`:

```sql
-- Bre-B → canonical (TO_CANONICAL direction)
INSERT INTO mapping_table (rail, direction, source_field, target_field, transformation, validation_rule, notes) VALUES
('BRE_B', 'TO_CANONICAL', 'idTransaccion', 'pmtId.endToEndId', 'copy', 'len_eq_28', 'Bre-B transaction ID 28 chars'),
('BRE_B', 'TO_CANONICAL', 'fechaHora', 'grpHdr.creDtTm', 'copy', 'iso_8601', 'Bre-B emission time'),
('BRE_B', 'TO_CANONICAL', 'valor.original', 'amount.value', 'parse_decimal', NULL, 'COP integer or 2-decimal'),
('BRE_B', 'TO_CANONICAL', 'pagador.nombre', 'debtor.name', 'truncate_140', 'len_0_140', NULL),
('BRE_B', 'TO_CANONICAL', 'pagador.codigoEntidad', 'origin.institutionCode', 'copy', 'len_eq_4', 'Superfinanciera code'),
('BRE_B', 'TO_CANONICAL', 'pagador.nit', 'debtor.taxId', 'copy', 'nit_format', NULL),
('BRE_B', 'TO_CANONICAL', 'pagador.cc', 'debtor.taxId', 'copy', 'cc_format', NULL),
('BRE_B', 'TO_CANONICAL', 'pagador.tipoCuenta', 'debtor.accountType', 'copy', NULL, NULL),
('BRE_B', 'TO_CANONICAL', 'beneficiario.nombre', 'creditor.name', 'truncate_140', 'len_0_140', NULL),
('BRE_B', 'TO_CANONICAL', 'beneficiario.codigoEntidad', 'destination.institutionCode', 'copy', 'len_eq_4', NULL),
('BRE_B', 'TO_CANONICAL', 'llave', 'alias.value', 'copy', NULL, NULL),
('BRE_B', 'TO_CANONICAL', 'tipoLlave', 'alias.subtype', 'copy', NULL, 'CC/CE/NIT/PASAPORTE/TELEFONO/EMAIL/ALIAS'),
('BRE_B', 'TO_CANONICAL', 'concepto', 'remittanceInfo', 'truncate_140', 'len_0_140', NULL);

-- canonical → Bre-B (FROM_CANONICAL direction)
INSERT INTO mapping_table (rail, direction, source_field, target_field, transformation, validation_rule, notes) VALUES
('BRE_B', 'FROM_CANONICAL', 'pmtId.endToEndId', 'idTransaccion', 'regenerate_if_invalid', 'len_eq_28', 'Regenerate if not Bre-B format'),
('BRE_B', 'FROM_CANONICAL', 'grpHdr.creDtTm', 'fechaHora', 'copy', NULL, NULL),
('BRE_B', 'FROM_CANONICAL', 'amount.value', 'valor.original', 'cop_integer_or_2dec', NULL, 'COP no centavos'),
('BRE_B', 'FROM_CANONICAL', 'amount.currency', '_implied_COP', 'force_COP', 'eq_COP', 'Bre-B is COP only'),
('BRE_B', 'FROM_CANONICAL', 'debtor.name', 'pagador.nombre', 'truncate_140', NULL, NULL),
('BRE_B', 'FROM_CANONICAL', 'origin.institutionCode', 'pagador.codigoEntidad', 'copy', 'len_eq_4', NULL),
('BRE_B', 'FROM_CANONICAL', 'debtor.taxId', 'pagador.nit_or_cc', 'route_by_format', NULL, NULL),
('BRE_B', 'FROM_CANONICAL', 'creditor.name', 'beneficiario.nombre', 'truncate_140', NULL, NULL),
('BRE_B', 'FROM_CANONICAL', 'destination.institutionCode', 'beneficiario.codigoEntidad', 'copy', 'len_eq_4', NULL),
('BRE_B', 'FROM_CANONICAL', 'alias.value', 'llave', 'copy', NULL, NULL),
('BRE_B', 'FROM_CANONICAL', 'remittanceInfo', 'concepto', 'truncate_140', NULL, NULL);
```

- [ ] Crear archivo
- [ ] Verificar `validation_rule` y `transformation` matchean lo que el código de translation soporta

### 5.14 Cablear `brebRetryCount` metric (cerrado por 5.9)

Cubierto por `withRetry` que llama `brebRetryCount.inc()`.

### 5.15 Headers documentando "invented spec"

`mipit-adapter-breb/src/breb/mock-server.ts:1-15` header:

```ts
/**
 * Bre-B Mock Server (Banco de la República, Colombia)
 *
 * CRITICAL NOTE (PoC limitation):
 * - As of audit date (2026-05-16), Banco de la República has NOT published a
 *   public wire-format specification for Bre-B SPI participant integration.
 *   The only public documents are:
 *     - https://www.banrep.gov.co/es/bre-b (overview)
 *     - https://www.banrep.gov.co/es/bre-b/que-es (llave types)
 *     - "Documento técnico Bre-B" Feb 2026 (operational document, not wire format)
 *
 * - This mock implements a REST API (`POST /breb/v1/pagos`) that is **invented**
 *   for academic demonstration. Field names (`idTransaccion`, `pagador`,
 *   `beneficiario`, `llave`, `tipoLlave`, `concepto`), error codes
 *   (BREB001-BREB005), OAuth2 flow with scope `breb.pagos`, and idTransaccion
 *   format (`BR + entidad(4) + COT date(8) + time(4) + suffix(10) = 28 chars`)
 *   are educated guesses NOT verified against BanRep documentation.
 *
 * - When BanRep publishes the actual integration spec, this adapter should be
 *   reviewed against it. Llave types (CC/CE/NIT/PASAPORTE/TELEFONO/EMAIL/ALIAS),
 *   Superfinanciera 4-digit entity codes, and 24/7 operation are based on public
 *   BanRep announcements and are stable.
 *
 * For thesis-defense honesty: explicitly cite this PoC limitation. The Bre-B
 * adapter is a "reference implementation pending official spec publication".
 */
```

### 5.16 `architecture-overview.md` y `translation-layer.md` incluyen Bre-B

`mipit-docs/design/architecture-overview.md:14-36` y `translation-layer.md:22-32`:

- [ ] Actualizar diagrama ASCII para incluir `adapter-breb`
- [ ] Listar Bre-B en la sección "Rails"
- [ ] Agregar "Bre-B (Banco de la República, COP, 24/7)" en lista

### 5.17 RFC 8141 / RAIL constant uniformity (decisión doc)

`RAIL = 'BRE_B'` (underscore) vs `'PIX'`/`'SPEI'`. Decisión:

- [ ] **NO cambiar** la constante (impactaría cross-system y core code `inferRail`).
- [ ] **Agregar al README de cada adapter** una nota explicando: "Bre-B uses `BRE_B` with underscore for compatibility with SQL identifiers and TypeScript discriminated unions. Display-name is `Bre-B`."

---

## 6. Acceptance criteria

- [ ] 7 tipos de llave soportados: CC, CE, NIT, PASAPORTE, TELEFONO, EMAIL, ALIAS
- [ ] NIT validation con DIAN mod-11 checksum
- [ ] Phone +57 rechaza fijos, acepta móviles
- [ ] Entity codes 4-dig (catálogo Superfin)
- [ ] `idTransaccion` formato BR+4+8+4+10 = 28 chars en COT (no UTC)
- [ ] COP emitido como integer (no decimal)
- [ ] Límites 10M / 50M COP
- [ ] Operating hours 24/7 (core constants)
- [ ] `retry.ts` existe, `brebRetryCount` incrementa
- [ ] Test broken `breb-translation.test.ts` arreglado o eliminado
- [ ] Contract test `breb-mock.test.ts` existe con 12+ casos
- [ ] Triple strip `BREB-` eliminado — solo strip una vez en `breb-to-canonical.ts`
- [ ] `mapping_table` tiene 24 rows Bre-B (12 TO + 12 FROM)
- [ ] Mock header documenta invented wire format
- [ ] Tests E2E PIX↔Bre-B y SPEI↔Bre-B verdes
- [ ] `mipit-docs/design/{architecture-overview,translation-layer}.md` incluyen Bre-B

---

## 7. Testing plan

### Unit
- `breb/key-types.test.ts` — los 7 tipos detectados correctamente
- `breb/nit-validator.test.ts` — DIAN checksum
- `breb/entity-codes.test.ts` — mapping Superfin
- `breb/idtransaccion.test.ts` — formato + COT timezone
- `breb/retry.test.ts` — exponential, jitter, 4xx no-retry, brebRetryCount inc

### Contract
- `breb/mock-server.contract.test.ts` — 12 casos descritos en 5.11

### Integration
- `mipit-testkit/tests/integration/breb-routing.test.ts` — PIX→Bre-B, SPEI→Bre-B, Bre-B→PIX, Bre-B→SPEI
- `mipit-testkit/tests/integration/breb-llave-types.test.ts` — los 7 tipos round-trip

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Cambio length 32→28 en idTransaccion rompe DB existente | Migración limpia (PoC); evidencia previa puede regenerarse |
| 4-dig entity codes rompen tests con valores 8-dig | Actualizar todos los fixtures masivamente |
| NIT checksum estricto rompe fixtures con NIT inventados | Generar NITs válidos en el generator de testkit |
| RAIL constant `BRE_B` underscore sigue siendo cross-system issue | Documentado; aceptado como limitación |

---

## 9. Commits sugeridos

1. `feat(breb): add CC, CE, PASAPORTE llave types`
2. `fix(breb): alias regex requires @ prefix per BanRep`
3. `fix(breb): phone +57 must be mobile (3xx prefix only)`
4. `feat(breb): NIT mod-11 DIAN checksum validation`
5. `refactor(breb): 4-digit Superfinanciera entity codes (was 8-padded)`
6. `fix(breb): idTransaccion in COT (UTC-5), not UTC; length 28`
7. `fix(breb): COP emitted as integer (no centavos)`
8. `fix(breb): COP limits 10M/50M per BanRep launch values`
9. `fix(config): BRE_B operating hours 24/7/365`
10. `feat(breb): retry.ts uniform with PIX/SPEI; brebRetryCount wired`
11. `fix(breb): repair broken test import in breb-translation.test.ts`
12. `test(breb): add contract test for mock server (12 cases)`
13. `refactor(translation): strip rail prefix once (eliminate triple-strip)`
14. `feat(infra): seed mapping_table with 24 Bre-B rows`
15. `docs(breb): document mock as invented wire format pending BanRep spec`
16. `docs(design): include Bre-B in architecture-overview and translation-layer`

---

## 10. Notas para el dev

- **La transparencia académica es la feature**. El header comment del mock es probablemente el cambio de más impacto de todo P04. Un panel que abra `mock-server.ts:8-15` lee directamente: "esto es invented, no es una mock fiel a BanRep porque BanRep no publicó nada".
- **NIT checksum**: las weights DIAN son `[41,37,29,23,19,17,13,7,3]` (right-to-left). Si el NIT tiene 10 dígitos, los pesos se asignan a los 10 dígitos (no pad).
- **Phone +57 3xx**: en Colombia, móviles empiezan en `3` y tienen exactamente 10 dígitos. Landline `+57 1 xxxxxxx` (Bogotá) no debería ser válido como llave Bre-B.
- **Eliminar el "ALIAS catch-all"** en `inferTipoLlave` es importante — actualmente cualquier string que no matches otros tipos se label-ea como ALIAS y el mock lo acepta. Esto enmascara errores upstream.
