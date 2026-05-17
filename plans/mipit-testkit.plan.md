# Plan: mipit-testkit

> **Repo GitHub**: https://github.com/MIPIT-PoC/mipit-testkit
> **Propósito**: Todo lo necesario para probar y demostrar — datasets sintéticos, generadores, pruebas de contrato/integración/E2E, y generación de evidencias.
> **Posición en el flujo**: Transversal. Ejecuta y verifica el flujo completo.

---

## 1. Estructura de carpetas

```
mipit-testkit/
├── README.md
├── package.json
├── tsconfig.json
├── .gitignore
├── .env.example
├── datasets/
│   ├── pix/
│   │   ├── pix-valid-01.json        # Payload PIX válido (caso feliz)
│   │   ├── pix-valid-02.json        # Otro caso feliz con campos diferentes
│   │   ├── pix-invalid-amount.json  # Amount = 0 (debe fallar validación)
│   │   ├── pix-invalid-alias.json   # Alias mal formado
│   │   └── pix-batch-50.json        # Array de 50 payloads para carga
│   ├── spei/
│   │   ├── spei-valid-01.json
│   │   ├── spei-valid-02.json
│   │   ├── spei-invalid-clabe.json  # CLABE con menos de 18 dígitos
│   │   ├── spei-invalid-amount.json
│   │   └── spei-batch-50.json
│   └── expected/
│       ├── pix-to-canonical-01.json  # Resultado esperado de traducción PIX→canónico
│       ├── spei-to-canonical-01.json
│       ├── canonical-to-pix-01.json
│       └── canonical-to-spei-01.json
├── generators/
│   ├── generate-pix.ts              # Generador de payloads PIX sintéticos
│   ├── generate-spei.ts             # Generador de payloads SPEI sintéticos
│   ├── generate-batch.ts            # Generador de batches (N transacciones)
│   └── utils.ts                     # Helpers (random alias, amounts, names)
├── tests/
│   ├── contract/
│   │   ├── openapi-validation.test.ts # Validar respuestas contra OpenAPI spec
│   │   ├── canonical-schema.test.ts   # Validar canónico contra Zod schema
│   │   └── rabbitmq-messages.test.ts  # Validar mensajes RabbitMQ contra schema
│   ├── integration/
│   │   ├── core-api.test.ts           # POST /payments + GET /payments/:id
│   │   ├── translation.test.ts        # Traducción PIX↔canónico, SPEI↔canónico
│   │   ├── routing.test.ts            # Enrutamiento por reglas
│   │   ├── idempotency.test.ts        # Idempotency-Key behavior
│   │   └── pipeline.test.ts           # Flujo completo core (sin adaptadores)
│   └── e2e/
│       ├── pix-to-spei.test.ts        # Flujo completo PIX → SPEI
│       ├── spei-to-pix.test.ts        # Flujo completo SPEI → PIX
│       ├── error-scenarios.test.ts    # Fallo de sandbox, timeout, rechazo
│       ├── idempotency-e2e.test.ts    # Duplicado devuelve misma respuesta
│       └── batch-load.test.ts         # 50-100 transacciones, medir latencias
├── tools/
│   ├── run-e2e.sh                    # Script para correr E2E completo
│   ├── smoke-test.sh                 # Smoke test rápido (1 tx ida y vuelta)
│   ├── generate-evidence.sh          # Exportar logs + trazas + métricas
│   └── report.ts                     # Generador de reporte HTML/JSON
└── evidence/
    └── .gitkeep                      # Los reportes generados van aquí
```

---

## 2. Dependencias (package.json)

```json
{
  "name": "mipit-testkit",
  "version": "0.1.0",
  "private": true,
  "description": "MiPIT PoC — Test suite, datasets, generators, and evidence tools",
  "license": "MIT",
  "scripts": {
    "generate:pix": "tsx generators/generate-pix.ts",
    "generate:spei": "tsx generators/generate-spei.ts",
    "generate:batch": "tsx generators/generate-batch.ts",
    "test:contract": "jest --testPathPattern=tests/contract",
    "test:integration": "jest --testPathPattern=tests/integration",
    "test:e2e": "jest --testPathPattern=tests/e2e --runInBand",
    "test:all": "jest --runInBand",
    "smoke": "bash tools/smoke-test.sh",
    "e2e": "bash tools/run-e2e.sh",
    "evidence": "bash tools/generate-evidence.sh",
    "report": "tsx tools/report.ts"
  },
  "dependencies": {
    "zod": "^3.24.0",
    "ulid": "^2.3.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "tsx": "^4.19.0",
    "@types/node": "^22.0.0",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.0",
    "@types/jest": "^29.5.0"
  }
}
```

---

## 3. Archivos clave — contenido

### 3.1 `generators/utils.ts`

```typescript
import { ulid } from 'ulid';

export function randomAmount(min = 10, max = 10000): number {
  return Math.round((Math.random() * (max - min) + min) * 100) / 100;
}

export function randomPixKey(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-';
  const len = 8 + Math.floor(Math.random() * 20);
  return Array.from({ length: len }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

export function randomClabe(): string {
  return Array.from({ length: 18 }, () => Math.floor(Math.random() * 10)).join('');
}

export function randomName(): string {
  const firstNames = ['Alice', 'Bob', 'Carlos', 'Diana', 'Eduardo', 'Fernanda', 'Gustavo', 'Helena'];
  const lastNames = ['Silva', 'García', 'Rodríguez', 'Martínez', 'López', 'Hernández', 'Pereira'];
  return `${firstNames[Math.floor(Math.random() * firstNames.length)]} ${lastNames[Math.floor(Math.random() * lastNames.length)]}`;
}

export function randomPurpose(): string {
  const purposes = ['P2P', 'TRANSFER', 'PAYMENT', 'REMITTANCE', 'INVOICE'];
  return purposes[Math.floor(Math.random() * purposes.length)];
}

export function paymentId(): string {
  return `PMT-${ulid()}`;
}
```

### 3.2 `generators/generate-pix.ts`

```typescript
import { randomAmount, randomPixKey, randomName, randomPurpose } from './utils.js';
import fs from 'node:fs';

interface PixDataset {
  amount: number;
  currency: string;
  debtor: { alias: string; name: string };
  creditor: { alias: string; name: string };
  purpose: string;
  reference: string;
}

function generatePixPayload(): PixDataset {
  return {
    amount: randomAmount(),
    currency: 'USD',
    debtor: {
      alias: `PIX-${randomPixKey()}`,
      name: randomName(),
    },
    creditor: {
      alias: `SPEI-${Array.from({ length: 18 }, () => Math.floor(Math.random() * 10)).join('')}`,
      name: randomName(),
    },
    purpose: randomPurpose(),
    reference: `MIPIT-POC-${Date.now()}`,
  };
}

const count = parseInt(process.argv[2] ?? '10', 10);
const output = Array.from({ length: count }, generatePixPayload);

const filename = `datasets/pix/pix-generated-${count}.json`;
fs.mkdirSync('datasets/pix', { recursive: true });
fs.writeFileSync(filename, JSON.stringify(output, null, 2));
console.log(`Generated ${count} PIX payloads → ${filename}`);
```

### 3.3 `generators/generate-spei.ts`

```typescript
import { randomAmount, randomClabe, randomName, randomPurpose } from './utils.js';
import fs from 'node:fs';

function generateSpeiPayload() {
  return {
    amount: randomAmount(),
    currency: 'USD',
    debtor: {
      alias: `SPEI-${randomClabe()}`,
      name: randomName(),
    },
    creditor: {
      alias: `PIX-${Array.from({ length: 12 }, () => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 62)]).join('')}`,
      name: randomName(),
    },
    purpose: randomPurpose(),
    reference: `MIPIT-POC-${Date.now()}`,
  };
}

const count = parseInt(process.argv[2] ?? '10', 10);
const output = Array.from({ length: count }, generateSpeiPayload);

const filename = `datasets/spei/spei-generated-${count}.json`;
fs.mkdirSync('datasets/spei', { recursive: true });
fs.writeFileSync(filename, JSON.stringify(output, null, 2));
console.log(`Generated ${count} SPEI payloads → ${filename}`);
```

### 3.4 `datasets/pix/pix-valid-01.json`

```json
{
  "amount": 150.25,
  "currency": "USD",
  "debtor": {
    "alias": "PIX-alice.silva.2026",
    "name": "Alice Silva"
  },
  "creditor": {
    "alias": "SPEI-012345678901234567",
    "name": "Bob García"
  },
  "purpose": "P2P",
  "reference": "MIPIT-POC demo 01"
}
```

### 3.5 `datasets/spei/spei-valid-01.json`

```json
{
  "amount": 500.00,
  "currency": "USD",
  "debtor": {
    "alias": "SPEI-987654321098765432",
    "name": "Carlos Rodríguez"
  },
  "creditor": {
    "alias": "PIX-fernanda.pereira.br",
    "name": "Fernanda Pereira"
  },
  "purpose": "REMITTANCE",
  "reference": "MIPIT-POC demo 02"
}
```

### 3.6 `tests/e2e/pix-to-spei.test.ts`

```typescript
const API_URL = process.env.API_URL ?? 'http://localhost:8080';

describe('E2E: PIX → SPEI', () => {
  it('should complete a PIX to SPEI payment end-to-end', async () => {
    // 1. Create payment
    const createRes = await fetch(`${API_URL}/payments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Idempotency-Key': crypto.randomUUID(),
      },
      body: JSON.stringify({
        amount: 150.25,
        currency: 'USD',
        debtor: { alias: 'PIX-alice.silva.2026', name: 'Alice Silva' },
        creditor: { alias: 'SPEI-012345678901234567', name: 'Bob García' },
        purpose: 'P2P',
        reference: 'E2E-TEST',
      }),
    });

    expect(createRes.status).toBe(202);
    const { payment_id, status, destination } = await createRes.json();
    expect(payment_id).toMatch(/^PMT-/);
    expect(status).toBe('RECEIVED');
    expect(destination).toBe('SPEI');

    // 2. Poll for completion (max 30s)
    let detail;
    const maxWait = 30_000;
    const start = Date.now();

    while (Date.now() - start < maxWait) {
      const getRes = await fetch(`${API_URL}/payments/${payment_id}`);
      detail = await getRes.json();

      if (['COMPLETED', 'REJECTED', 'FAILED'].includes(detail.status)) break;
      await new Promise((r) => setTimeout(r, 1000));
    }

    // 3. Verify final state
    expect(detail).toBeDefined();
    expect(['COMPLETED', 'REJECTED']).toContain(detail.status);
    expect(detail.origin).toBe('PIX');
    expect(detail.destination).toBe('SPEI');

    // 4. Verify payloads exist
    expect(detail.original).toBeTruthy();
    expect(detail.canonical).toBeTruthy();

    // 5. Verify timestamps progression
    expect(detail.timestamps.created_at).toBeTruthy();

    // 6. If completed, verify rail_ack
    if (detail.status === 'COMPLETED') {
      expect(detail.rail_ack).toBeTruthy();
      expect(detail.rail_ack.status).toBe('ACCEPTED');
      expect(detail.rail_ack.rail_tx_id).toMatch(/^SPEI-/);
    }
  }, 35_000);

  it('should handle idempotency (same key = same response)', async () => {
    const idempotencyKey = crypto.randomUUID();
    const body = {
      amount: 100,
      currency: 'USD',
      debtor: { alias: 'PIX-test.idem.key', name: 'Test' },
      creditor: { alias: 'SPEI-111111111111111111', name: 'Test Dest' },
    };

    const res1 = await fetch(`${API_URL}/payments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey },
      body: JSON.stringify(body),
    });
    const data1 = await res1.json();

    const res2 = await fetch(`${API_URL}/payments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey },
      body: JSON.stringify(body),
    });
    const data2 = await res2.json();

    expect(data1.payment_id).toBe(data2.payment_id);
  });

  it('should reject different payload with same idempotency key', async () => {
    const idempotencyKey = crypto.randomUUID();

    await fetch(`${API_URL}/payments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey },
      body: JSON.stringify({
        amount: 200,
        currency: 'USD',
        debtor: { alias: 'PIX-conflict.test' },
        creditor: { alias: 'SPEI-222222222222222222' },
      }),
    });

    const res2 = await fetch(`${API_URL}/payments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey },
      body: JSON.stringify({
        amount: 999,
        currency: 'USD',
        debtor: { alias: 'PIX-conflict.test' },
        creditor: { alias: 'SPEI-333333333333333333' },
      }),
    });

    expect(res2.status).toBe(409);
  });
});
```

### 3.7 `tests/e2e/batch-load.test.ts`

```typescript
import fs from 'node:fs';

const API_URL = process.env.API_URL ?? 'http://localhost:8080';

describe('E2E: Batch Load Test', () => {
  it('should process 50 transactions and measure latencies', async () => {
    const batch = JSON.parse(fs.readFileSync('datasets/pix/pix-batch-50.json', 'utf-8'));
    const results: { payment_id: string; latency_ms: number; status: string }[] = [];

    // Send all payments
    const promises = batch.map(async (payload: any, i: number) => {
      const start = Date.now();
      const res = await fetch(`${API_URL}/payments`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': crypto.randomUUID(),
        },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      return { payment_id: data.payment_id, sent_at: start };
    });

    const sent = await Promise.all(promises);

    // Wait for all to complete (max 60s)
    await new Promise((r) => setTimeout(r, 15_000));

    // Check status of all
    for (const { payment_id, sent_at } of sent) {
      const res = await fetch(`${API_URL}/payments/${payment_id}`);
      const detail = await res.json();
      results.push({
        payment_id,
        latency_ms: Date.now() - sent_at,
        status: detail.status,
      });
    }

    // Report
    const completed = results.filter((r) => r.status === 'COMPLETED').length;
    const failed = results.filter((r) => r.status === 'FAILED').length;
    const rejected = results.filter((r) => r.status === 'REJECTED').length;
    const latencies = results.map((r) => r.latency_ms).sort((a, b) => a - b);
    const p50 = latencies[Math.floor(latencies.length * 0.5)];
    const p95 = latencies[Math.floor(latencies.length * 0.95)];
    const p99 = latencies[Math.floor(latencies.length * 0.99)];

    console.log(`\n=== Batch Load Results ===`);
    console.log(`Total:     ${results.length}`);
    console.log(`Completed: ${completed}`);
    console.log(`Failed:    ${failed}`);
    console.log(`Rejected:  ${rejected}`);
    console.log(`Latency p50: ${p50}ms`);
    console.log(`Latency p95: ${p95}ms`);
    console.log(`Latency p99: ${p99}ms`);

    // Save evidence
    fs.mkdirSync('evidence', { recursive: true });
    fs.writeFileSync('evidence/batch-load-results.json', JSON.stringify({ results, summary: { completed, failed, rejected, p50, p95, p99 } }, null, 2));

    // Assert SRS requirement: >= 99.9% success (for 50 tx, allow 0 failures from the system)
    const successRate = completed / results.length;
    expect(successRate).toBeGreaterThanOrEqual(0.9); // Relaxed for mock (10% random fail)
  }, 90_000);
});
```

### 3.8 `tools/smoke-test.sh`

```bash
#!/bin/bash
set -euo pipefail

API_URL="${API_URL:-http://localhost:8080}"

echo "==> Smoke Test: MiPIT PoC"
echo "    API: $API_URL"
echo ""

# Health check
echo "1. Health check..."
curl -sf "$API_URL/health" | jq .
echo ""

# Create PIX → SPEI payment
echo "2. Creating PIX → SPEI payment..."
IDEM_KEY=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "test-$(date +%s)")

RESPONSE=$(curl -sf -X POST "$API_URL/payments" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $IDEM_KEY" \
  -d '{
    "amount": 100.50,
    "currency": "USD",
    "debtor": { "alias": "PIX-smoke.test.key", "name": "Smoke Test" },
    "creditor": { "alias": "SPEI-012345678901234567", "name": "Smoke Dest" },
    "purpose": "P2P",
    "reference": "SMOKE-TEST"
  }')

PAYMENT_ID=$(echo "$RESPONSE" | jq -r '.payment_id')
echo "   payment_id: $PAYMENT_ID"
echo "   status: $(echo "$RESPONSE" | jq -r '.status')"
echo ""

# Wait and poll
echo "3. Waiting for completion (max 30s)..."
for i in $(seq 1 30); do
  DETAIL=$(curl -sf "$API_URL/payments/$PAYMENT_ID")
  STATUS=$(echo "$DETAIL" | jq -r '.status')

  if [ "$STATUS" = "COMPLETED" ] || [ "$STATUS" = "REJECTED" ] || [ "$STATUS" = "FAILED" ]; then
    echo "   Final status: $STATUS (after ${i}s)"
    echo "$DETAIL" | jq .
    break
  fi

  sleep 1
done

echo ""
echo "==> Smoke test complete!"
```

### 3.9 `tools/run-e2e.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "==> MiPIT E2E Test Suite"
echo ""

# Ensure API is up
API_URL="${API_URL:-http://localhost:8080}"
echo "Checking API at $API_URL..."
curl -sf "$API_URL/health" > /dev/null || { echo "ERROR: API not reachable"; exit 1; }

echo "Running E2E tests..."
npx jest --testPathPattern=tests/e2e --runInBand --verbose

echo ""
echo "==> E2E tests complete. Evidence saved in evidence/"
```

### 3.10 `tools/generate-evidence.sh`

```bash
#!/bin/bash
set -euo pipefail

EVIDENCE_DIR="evidence/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

echo "==> Generating evidence bundle in $EVIDENCE_DIR"

# 1. API health
curl -sf http://localhost:8080/health > "$EVIDENCE_DIR/health.json" 2>/dev/null || echo '{"error":"unreachable"}' > "$EVIDENCE_DIR/health.json"

# 2. Prometheus metrics snapshot
curl -sf http://localhost:9090/api/v1/query?query=mipit_payments_total > "$EVIDENCE_DIR/metrics-payments-total.json" 2>/dev/null || true
curl -sf "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,sum(rate(mipit_payment_latency_ms_bucket[1h]))by(le))" > "$EVIDENCE_DIR/metrics-latency-p95.json" 2>/dev/null || true

# 3. Recent audit events (via API or direct DB query)
echo "Evidence bundle saved: $EVIDENCE_DIR"
echo "Contents:"
ls -la "$EVIDENCE_DIR"
```

---

## 4. `.env.example`

```env
API_URL=http://localhost:8080
```

---

## 5. Verificaciones que los tests deben cubrir

| Categoría       | Test                                    | Qué verifica                                                |
|----------------|-----------------------------------------|-------------------------------------------------------------|
| Contrato       | OpenAPI validation                       | Respuestas cumplen el schema OpenAPI                       |
| Contrato       | Canonical schema                         | pacs.008 JSON cumple Zod schema                            |
| Contrato       | RabbitMQ messages                        | Mensajes route/ack cumplen schema                          |
| Integración    | POST /payments                           | Crea pago y devuelve 202                                   |
| Integración    | GET /payments/:id                        | Devuelve detalle correcto                                   |
| Integración    | Traducción PIX → Canónico               | Mapeo correcto de todos los campos                          |
| Integración    | Traducción SPEI → Canónico              | Mapeo correcto de todos los campos                          |
| Integración    | Enrutamiento por alias                   | PIX_KEY → PIX, CLABE → SPEI                               |
| Integración    | Idempotencia (mismo payload)             | Devuelve misma respuesta                                    |
| Integración    | Idempotencia (payload diferente)         | Devuelve 409                                                |
| E2E            | PIX → SPEI completo                     | Flujo end-to-end hasta COMPLETED                           |
| E2E            | SPEI → PIX completo                     | Bidireccionalidad                                           |
| E2E            | Error de sandbox                         | Estado REJECTED con rail_ack.error                         |
| E2E            | Batch 50 transacciones                   | Tasa éxito + latencias p50/p95/p99                         |
| E2E            | audit_events consistentes                | Cada etapa tiene audit_event con trace_id                  |
| E2E            | trace_id propagado                       | Mismo trace_id en core y adaptador                         |

---

## 6. Orden de ejecución al construir

1. Crear estructura de carpetas
2. Crear package.json e instalar dependencias
3. Crear generadores y datasets estáticos
4. Generar datasets dinámicos: `npm run generate:pix -- 50`
5. Crear tests de contrato/integración/E2E
6. Crear scripts de herramientas
7. Verificar que los tests compilan: `npx tsc --noEmit`
8. `git init && git add . && git commit -m "chore: initial mipit-testkit scaffold"`
9. `git remote add origin https://github.com/MIPIT-PoC/mipit-testkit.git && git push -u origin main`
