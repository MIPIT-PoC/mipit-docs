# P10 — Testkit Completeness

**Wave**: 4 (downstream, después de specs)
**Repos afectados**: `mipit-testkit`
**Branch**: `Auditoria-Claude`
**Estimación**: 3-4 días
**Riesgo**: Bajo (test code, no toca producción)

---

## 1. Objetivo

Llevar el testkit de "11/11 green con asteriscos" a "11/11 green honesto + coverage matrix 6/6 rail-pairs + resilience scenarios reales". Hoy:

- 2 archivos contract test son **100% placeholders** (`expect(true).toBe(true)`).
- 3 escenarios de la suite son "históricos" no re-ejecutados (`durationMs: 0`).
- Tests E2E esperan `202` cuando el real es `201` (fix_testkit.py aplicó en VM, no en working copy).
- Fixtures con CLABE check digits **inválidos**.
- Fixtures con `currency: 'USD'` cuando PIX es BRL-only.
- "PIX keys" generados son random base64 (no CPF/CNPJ válidos).
- 0 datasets / generators / tests Bre-B.
- 5/13 resilience scenarios cubiertos; faltan broker outage, DB primary down, DLQ requeue specific, out-of-order ACK, compensation E2E.
- Sin SLO assertions (`<10s` p95 per rail).

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| G1 | **C** | `openapi-validation.test.ts` 100% placebo |
| G2 | **C** | `rabbitmq-messages.test.ts` 100% placebo |
| G3 | **C** | Cero datasets Bre-B |
| G4 | H | E2E espera 202 vs real 201 |
| G5 | H | spei-to-pix mismo drift |
| G6 | H | core-api mismo drift |
| G7 | H | CLABE inválidas en fixtures |
| G8 | H | "11/11 green" cuenta históricos no ejecutados |
| G9 | M | smoke-test.sh sin Authorization header |
| G10 | M | E2E poll 30s sin SLO |
| G11 | H | 5/13 resilience scenarios |
| G12 | M | Sin tests 6 pares de rieles completos |
| G13 | H | PIX keys random base64 (no CPF/CNPJ válidos) |
| G14 | H | Fixtures `currency: 'USD'` para PIX/SPEI |
| G15 | M | translation.test.ts shape obsoleta |
| H35 | H | fix_testkit.py no aplicado en working copy Windows |

---

## 3. Out of scope

- **NO** se introduce framework de mutation testing.
- **NO** se reemplaza Jest por Vitest.
- **NO** se hace load test con k6 / Gatling profesional.

---

## 4. Dependencias

- **Bloquea**: nada — es testing.
- **Depende de**: P01 (canonical), P02 (PIX EndToEndId real), P03 (SPEI 5-dig), P04 (Bre-B llaves), P09 (DB constraints) — necesita las specs reales antes de generar fixtures válidos.

---

## 5. Tareas detalladas

### 5.1 Port `fix_testkit.py` a Windows + apply

`fix_testkit.py` actualmente con paths `/home/estudiante/tesis/...`. Portar:

- [ ] Crear `mipit-testkit/scripts/fix-testkit-for-windows.ts` con la misma lógica:
  1. Fix CLABE check digits en datasets
  2. Inject `authedFetch` wrapper + `beforeAll(/auth/token)` in Jest tests
  3. Replace `expect().toBe(202)` con `.toBe(201)`
  4. Remove broken `helpers/auth.js` import
  5. (Opcional) Update VM IPs en `ui.env` no en testkit
- [ ] Run on local working copy
- [ ] Commit changes
- [ ] Move `fix_testkit.py` to `mipit-testkit/scripts/legacy/` para archival

### 5.2 Replace placebo contract tests

`mipit-testkit/tests/contract/openapi-validation.test.ts`:

```ts
import { describe, it, expect, beforeAll } from '@jest/globals';
import SwaggerParser from '@apidevtools/swagger-parser';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';

const ajv = new Ajv({ strict: false });
addFormats(ajv);

const API_URL = process.env.API_URL ?? 'http://localhost:8080';
const OPENAPI_PATH = '../mipit-docs/openapi/openapi.yaml';

describe('OpenAPI contract validation', () => {
  let spec: any;

  beforeAll(async () => {
    spec = await SwaggerParser.dereference(OPENAPI_PATH);
  });

  it('OpenAPI spec is structurally valid', async () => {
    await SwaggerParser.validate(OPENAPI_PATH);
  });

  it('POST /payments response 201 matches schema', async () => {
    const res = await fetch(`${API_URL}/payments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await getToken()}`, 'Idempotency-Key': `IK-${Date.now()}` },
      body: JSON.stringify(samplePayment()),
    });
    expect(res.status).toBe(201);
    const body = await res.json();
    const schema = spec.components.schemas.PaymentReceipt;
    const validate = ajv.compile(schema);
    const valid = validate(body);
    expect(validate.errors ?? []).toEqual([]);
    expect(valid).toBe(true);
  });

  it('GET /payments/:id response schema matches', async () => {
    /* ... real test ... */
  });

  it('GET /health response shape matches', async () => {
    const res = await fetch(`${API_URL}/health`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toMatchObject({ status: expect.stringMatching(/^(ok|degraded)$/) });
  });

  it('Rail enum in spec matches code constants', () => {
    const rails = spec.components.schemas.Rail.enum;
    expect(rails).toEqual(['PIX','SPEI','BRE_B','SWIFT_MT103','ISO20022_MX','ACH_NACHA','FEDNOW']);
  });

  it('PaymentStatus enum in spec has 14 values', () => {
    const statuses = spec.components.schemas.PaymentStatus.enum;
    expect(statuses).toHaveLength(14);
  });
});
```

- [ ] Reemplazar el archivo completo (eliminar `expect(true).toBe(true)`)
- [ ] Mismo para `rabbitmq-messages.test.ts`:

```ts
import amqp from 'amqplib';

describe('RabbitMQ message contracts', () => {
  let conn: amqp.Connection;
  let ch: amqp.Channel;

  beforeAll(async () => {
    conn = await amqp.connect(process.env.RABBITMQ_URL!);
    ch = await conn.createChannel();
  });
  afterAll(async () => { await ch.close(); await conn.close(); });

  it('mipit.payments exchange is topic durable', async () => {
    await ch.checkExchange('mipit.payments'); // throws if wrong
  });

  it('payments.route.pix queue exists and is durable', async () => {
    const info = await ch.checkQueue('payments.route.pix');
    expect(info.queue).toBe('payments.route.pix');
  });

  it('payments.route.{spei,breb} exist', async () => {
    await ch.checkQueue('payments.route.spei');
    await ch.checkQueue('payments.route.breb');
  });

  it('payments.ack has DLX configured', async () => {
    const info = await ch.checkQueue('payments.ack');
    // arguments come back from broker
    // can only verify via Management API; spot-check with publish-to-dlx
    expect(info.queue).toBe('payments.ack');
  });

  it('dlq queues exist', async () => {
    await ch.checkQueue('dlq.pix');
    await ch.checkQueue('dlq.spei');
    await ch.checkQueue('dlq.breb');
    await ch.checkQueue('dlq.ack');
  });

  it('canonical message published to route.pix has expected shape', async () => {
    // POST /payments PIX → poll route.pix queue once → verify shape
    /* ... */
  });
});
```

### 5.3 Bre-B datasets + generator

Crear `mipit-testkit/generators/generate-breb.ts`:

```ts
import { randomInt, randomBytes } from 'node:crypto';

export function generateNIT(): string {
  const digits = Array.from({ length: 9 }, () => randomInt(10)).join('');
  const checkDigit = computeNITCheckDigit(digits);
  return `${digits}-${checkDigit}`;
}

export function generateCC(): string {
  // 6-10 digits
  const len = randomInt(6, 11);
  return Array.from({ length: len }, () => randomInt(10)).join('');
}

export function generatePhoneMobile(): string {
  // +57 3xx XXX XXXX
  return '+573' + Array.from({ length: 9 }, () => randomInt(10)).join('');
}

export function generateEmail(): string {
  const prefix = randomBytes(4).toString('hex');
  return `user.${prefix}@mipit.test`;
}

export function generateAlias(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789._';
  let s = '@';
  for (let i = 0; i < randomInt(3, 20); i++) s += chars[randomInt(chars.length)];
  return s;
}

function computeNITCheckDigit(nineDigits: string): string {
  const weights = [41,37,29,23,19,17,13,7,3];
  const reversed = nineDigits.split('').reverse();
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += parseInt(reversed[i]) * weights[i];
  const rem = sum % 11;
  return String(rem < 2 ? rem : 11 - rem);
}

export function generateBrebPayment(): BrebPayment {
  const llaveType = ['CC','NIT','TELEFONO','EMAIL','ALIAS'][randomInt(5)];
  const llave = {
    CC: generateCC(),
    NIT: generateNIT(),
    TELEFONO: generatePhoneMobile(),
    EMAIL: generateEmail(),
    ALIAS: generateAlias(),
  }[llaveType];

  return {
    amount: randomInt(1000, 10_000_000), // COP integer
    currency: 'COP',
    debtor: { alias: `BREB-${llave}`, name: 'Test Debtor', country: 'CO' },
    creditor: { alias: `BREB-${generatePhoneMobile()}`, name: 'Test Creditor', country: 'CO' },
    purpose: 'P2P',
    reference: `TEST-${Date.now()}`,
  };
}
```

- [ ] Crear archivo
- [ ] Crear `datasets/breb/breb-valid-01.json` con un payload válido manual (NIT con check digit real, CLABE-equivalent, etc.)
- [ ] `datasets/breb/breb-invalid-llave-type.json`
- [ ] `datasets/breb/breb-invalid-nit-checksum.json`
- [ ] `datasets/breb/breb-batch-50.json` (50 entries generated)
- [ ] `datasets/expected/canonical-to-breb-01.json` con shape correcto nested camelCase

### 5.4 Fix PIX fixtures — real CPF/CNPJ/email/phone

`mipit-testkit/generators/generate-pix.ts`:

```ts
import { randomInt, randomBytes } from 'node:crypto';

export function generateCPF(): string {
  // 9 random digits + 2 check digits per mod-11 algorithm
  const base = Array.from({ length: 9 }, () => randomInt(10));
  // First check
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += base[i] * (10 - i);
  let d1 = 11 - (sum % 11);
  if (d1 >= 10) d1 = 0;
  base.push(d1);
  // Second check
  sum = 0;
  for (let i = 0; i < 10; i++) sum += base[i] * (11 - i);
  let d2 = 11 - (sum % 11);
  if (d2 >= 10) d2 = 0;
  base.push(d2);
  return base.join('');
}

export function generateCNPJ(): string {
  const base = Array.from({ length: 12 }, () => randomInt(10));
  const w1 = [5,4,3,2,9,8,7,6,5,4,3,2];
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += base[i] * w1[i];
  let d1 = 11 - (sum % 11);
  if (d1 >= 10) d1 = 0;
  base.push(d1);
  const w2 = [6,5,4,3,2,9,8,7,6,5,4,3,2];
  sum = 0;
  for (let i = 0; i < 13; i++) sum += base[i] * w2[i];
  let d2 = 11 - (sum % 11);
  if (d2 >= 10) d2 = 0;
  base.push(d2);
  return base.join('');
}

export function generatePixPhone(): string {
  return '+5511' + Array.from({ length: 9 }, () => randomInt(10)).join('');
}

export function generateEVP(): string {
  // UUIDv4
  return crypto.randomUUID();
}

export function generatePixPayment(keyType: 'CPF'|'CNPJ'|'EMAIL'|'PHONE'|'EVP' = 'CPF'): PixPayment {
  const chave = {
    CPF: generateCPF(),
    CNPJ: generateCNPJ(),
    EMAIL: `user.${randomBytes(4).toString('hex')}@mipit.test`,
    PHONE: generatePixPhone(),
    EVP: generateEVP(),
  }[keyType];

  return {
    amount: parseFloat((randomInt(100, 1_000_000) / 100).toFixed(2)),
    currency: 'BRL', // PIX always BRL
    debtor: { alias: `PIX-${chave}`, name: 'Test Debtor', country: 'BR' },
    creditor: { alias: `PIX-${generateCPF()}`, name: 'Test Creditor', country: 'BR' },
    purpose: 'P2P',
    reference: `TEST-${Date.now()}`,
  };
}
```

- [ ] Reemplazar generator
- [ ] Regenerar todos los fixtures PIX
- [ ] Asegurar `currency: 'BRL'` siempre

### 5.5 Fix SPEI fixtures — real CLABE checksums

`mipit-testkit/generators/generate-spei.ts`:

```ts
import { randomInt } from 'node:crypto';

const CLABE_WEIGHTS = [3,7,1,3,7,1,3,7,1,3,7,1,3,7,1,3,7];

export function generateCLABE(bankPrefix3 = '072'): string {
  const base = bankPrefix3 + Array.from({ length: 14 }, () => randomInt(10)).join('');
  let sum = 0;
  for (let i = 0; i < 17; i++) sum += parseInt(base[i]) * CLABE_WEIGHTS[i];
  const checkDigit = (10 - (sum % 10)) % 10;
  return base + checkDigit;
}

export function generateSpeiPayment(): SpeiPayment {
  return {
    amount: parseFloat((randomInt(100, 100_000_000) / 100).toFixed(2)),
    currency: 'MXN', // SPEI always MXN
    debtor: { alias: `SPEI-${generateCLABE('072')}`, name: 'Test Debtor', country: 'MX' },
    creditor: { alias: `SPEI-${generateCLABE('012')}`, name: 'Test Creditor', country: 'MX' },
    purpose: 'P2P',
    reference: `TEST-${Date.now()}`,
  };
}
```

- [ ] Reemplazar generator
- [ ] Regenerar fixtures
- [ ] `currency: 'MXN'` siempre

### 5.6 Cross-currency fixtures

Para tests cross-border:

```ts
export function generateCrossCurrencyPayment(originRail, destRail, originCcy, destCcy): CrossCurrencyPayment {
  // amount in originCcy; expected target in destCcy after FX
  const amount = randomInt(100, 10000);
  return {
    amount,
    currency: originCcy,
    debtor: { alias: prefixedAlias(originRail), country: countryFromRail(originRail) },
    creditor: { alias: prefixedAlias(destRail), country: countryFromRail(destRail) },
    expected_destination_rail: destRail,
    expected_settlement_currency: destCcy,
    expected_fx_applied: true,
    purpose: 'P2P',
  };
}
```

- [ ] Fixtures `cross-currency/brl-to-mxn-01.json`, `brl-to-cop-01.json`, `mxn-to-cop-01.json`, etc.

### 5.7 Coverage matrix 6/6 rail-pairs

`mipit-testkit/tests/integration/routing.test.ts` ya cubre 5/6. Falta `SPEI→Bre-B`. Validar:

| From\To | PIX | SPEI | Bre-B |
|---|---|---|---|
| PIX | n/a | ✓ | ✓ |
| SPEI | ✓ | n/a | **needs explicit test** |
| Bre-B | ✓ | ? | n/a |

- [ ] Agregar test `SPEI→Bre-B` explícito
- [ ] Agregar test `Bre-B→SPEI` explícito

### 5.8 SLO assertions

`mipit-testkit/e2e-benchmark-latency.mjs`. Agregar:

```js
const SLOS = {
  PIX: { p95_ms: 5000, p99_ms: 8000 },
  SPEI: { p95_ms: 5000, p99_ms: 8000 },
  BRE_B: { p95_ms: 5000, p99_ms: 8000 },
};

for (const [rail, slo] of Object.entries(SLOS)) {
  const stats = computeStats(railSamples[rail]);
  console.log(`${rail}: p95=${stats.p95}ms p99=${stats.p99}ms`);
  if (stats.p95 > slo.p95_ms) throw new Error(`${rail} p95 ${stats.p95}ms exceeds SLO ${slo.p95_ms}ms`);
  if (stats.p99 > slo.p99_ms) throw new Error(`${rail} p99 ${stats.p99}ms exceeds SLO ${slo.p99_ms}ms`);
}
```

- [ ] Implementar SLO check
- [ ] Fallar el script si SLO violado
- [ ] `tests/e2e/pix-to-spei.test.ts` también verifica latencia < 10s

### 5.9 Resilience scenarios completos

`mipit-testkit/e2e-resilience.mjs` actual mata adapter-pix only. Extender:

```js
const scenarios = [
  { name: 'broker_outage', target: 'mipit-rabbitmq', method: 'docker stop', recovery: 'docker start', expected: 'pipeline_recovers_no_loss' },
  { name: 'db_primary_down', target: 'mipit-postgres', method: 'docker pause', recovery: 'docker unpause', expected: 'pipeline_503_then_recover' },
  { name: 'adapter_pix_dies', target: 'mipit-adapter-pix', method: 'docker kill --signal=SIGKILL', recovery: 'docker start', expected: 'messages_redelivered' },
  { name: 'adapter_spei_dies', target: 'mipit-adapter-spei', /* ... */ },
  { name: 'adapter_breb_dies', target: 'mipit-adapter-breb', /* ... */ },
  { name: 'dlq_requeue', /* publish bad message; verify DLQ has it; requeue; verify processed */ },
  { name: 'ack_out_of_order', /* publish acks A,B,C but in order C,A,B */ },
  { name: 'compensation_flow', /* POST /compensate; verify pacs.004 in outbox */ },
  { name: 'webhook_delivery_retry', /* TODO P06+P07 */ },
];

for (const scenario of scenarios) {
  await runScenario(scenario);
}
```

- [ ] Implementar cada scenario
- [ ] Documentar el expected y verificar
- [ ] Algunos requieren P06 (compensation, outbox) — depend appropriately

### 5.10 Smoke test con auth

`mipit-testkit/tools/smoke-test.sh`:

```bash
#!/bin/bash
set -e

BASE_URL=${BASE_URL:-http://localhost:8080}

# Get JWT
TOKEN=$(curl -s "$BASE_URL/auth/token" | jq -r .token)
if [ -z "$TOKEN" ]; then echo "Failed to get token"; exit 1; fi

# Health
curl -s "$BASE_URL/health" | jq

# Create payment with auth
curl -s -X POST "$BASE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: smoke-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678901","country":"BR","name":"Test"},"creditor":{"alias":"SPEI-072123456789012345","country":"MX","name":"Test"},"purpose":"P2P"}' | jq
```

- [ ] Update con Authorization header
- [ ] Use real CPF (algorithm) + real CLABE (algorithm) en payload

### 5.11 Mark "historical" entries clearly

`mipit-testkit/tools/run-validation-suite.ts:487-509`. Decisión:

**Opción A**: Eliminar las entradas históricas; re-ejecutar todo siempre.
**Opción B**: Mantener pero **rename** a `historical_load_documented`, `historical_routing_documented`, `historical_verifications_documented` y en el reporte markdown headline mostrar "8 ejecutados + 3 históricos documentados".

Recomendación: **Opción B** (mantener honestidad documental).

- [ ] Rename en el código
- [ ] Update markdown report template para mostrar "8 executed + 3 historical (not re-run)"
- [ ] La columna `durationMs: 0` en JSON queda igual; agregar campo `executed: false`

### 5.12 OpenAPI validation against running API

Crear `mipit-testkit/tools/check-openapi-conformance.ts`:

```ts
// Walk every path in openapi.yaml; for each operation, send a real request and compare response shape to schema
```

- [ ] Implementar
- [ ] Add to validation suite scenarios

### 5.13 Fix `translation.test.ts` shape obsoleto

`mipit-testkit/tests/integration/translation.test.ts`:

- [ ] Replace `detail.canonical.debtor.rail` with `detail.canonical.origin.rail`
- [ ] Replace cualquier flat snake_case con nested camelCase
- [ ] Asegurar tests pasan contra P01 canonical

---

## 6. Acceptance criteria

- [ ] `tests/contract/openapi-validation.test.ts` con assertions reales (no `expect(true).toBe(true)`)
- [ ] `tests/contract/rabbitmq-messages.test.ts` ditto
- [ ] Datasets PIX con CPF/CNPJ checksums válidos
- [ ] Datasets SPEI con CLABE check digit válidos
- [ ] Datasets Bre-B existen (`datasets/breb/*`)
- [ ] Generator Bre-B
- [ ] Generator PIX con CPF/CNPJ válidos
- [ ] Generator SPEI con CLABE válida
- [ ] Currency siempre matches rail (BRL→PIX, MXN→SPEI, COP→Bre-B)
- [ ] Cross-currency fixtures existen
- [ ] Matrix 6/6 rail-pairs covered
- [ ] SLO assertions en benchmark + E2E tests
- [ ] 13/13 resilience scenarios cubiertos
- [ ] smoke-test.sh con Authorization
- [ ] "Historical" entries renamed + marked en reporte
- [ ] translation.test.ts shape actualizado
- [ ] Suite `validate:suite` produce un reporte con "8 executed + 3 historical (documented)" claramente
- [ ] Todos los tests E2E expect 201 (no 202)

---

## 7. Testing plan

Self-referential (es el testkit). Validación:

- Run `validate:suite` en local; verify pass
- Run `validate:suite` en VM1; verify pass
- Compare `evidence/suite/<latest>` antes y después: assertions count should be **higher** post-P10 (no es solo 76 — debería ser >150 assertions reales contando los nuevos contract tests + resilience + cross-currency)

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Resilience scenarios requieren Docker en CI | Mark como `@requires-docker`; skip en CI sin Docker; run en VM1 |
| Fixtures con checksums reales rompen tests antiguos | Reemplazar masivamente; tests verifican checksum, ya no aceptan fake |
| Cross-currency tests dependen de FX (P05) | Depends on P05; tests sin P05 usan static rates |
| Contract tests fail si OpenAPI desactualizado | Bueno — exposes drift |

---

## 9. Commits sugeridos

1. `chore(testkit): port fix_testkit.py to TypeScript and run on Windows working copy`
2. `test(contract): replace openapi-validation placebos with real schema assertions`
3. `test(contract): replace rabbitmq-messages placebos with real queue introspection`
4. `feat(testkit): Bre-B generator + fixtures with valid NIT/CC/phone`
5. `feat(testkit): PIX generator with real CPF/CNPJ mod-11 checksums`
6. `feat(testkit): SPEI generator with real CLABE mod-10 check digit`
7. `fix(fixtures): currency aligned per rail (BRL/MXN/COP)`
8. `feat(testkit): cross-currency fixtures and tests (BRL→MXN, BRL→COP, MXN→COP)`
9. `feat(testkit): explicit SPEI↔Bre-B routing tests (close 6/6 matrix)`
10. `feat(testkit): SLO assertions in benchmark + E2E (<10s p95 per rail)`
11. `feat(testkit): full 13/13 resilience scenarios (broker, DB, adapters, DLQ, compensation)`
12. `fix(testkit): smoke-test.sh sends Authorization header`
13. `chore(testkit): rename historical scenarios; mark "executed:false" in JSON report`
14. `fix(testkit): translation.test.ts uses nested camelCase canonical shape`
15. `chore(testkit): move legacy fix_testkit.py to scripts/legacy/`

---

## 10. Notas para el dev

- **El testkit es la evidencia más visible**. Un panel que abra `evidence/suite/<latest>/validation-suite-report.md` debe ver assertions reales, no placeholders.
- **CLABE checksum**: weights `[3,7,1,3,7,1,...]` por 17 dígitos. Mod-10. Check digit = `(10 - sum%10) % 10`.
- **CPF mod-11**: pesos `[10,9,8,7,6,5,4,3,2]` para primer check; `[11,10,...,2]` para segundo. Si check ≥ 10 → 0.
- **NIT DIAN**: pesos `[41,37,29,23,19,17,13,7,3]` aplicados a los 9 dígitos right-to-left.
- Si los resilience scenarios son muy lentos, `--only=happy-path-fast` flag para CI rápido.
