# Plan: mipit-adapter-spei

> **Repo GitHub**: https://github.com/MIPIT-PoC/mipit-adapter-spei
> **Propósito**: Adaptador para el riel SPEI (México). Simétrico a adapter-pix pero con payload y sandbox SPEI.
> **Posición en el flujo**: Core → RabbitMQ → `adapter-spei` → sandbox/mock SPEI → ack → Core.

---

## 1. Estructura de carpetas

```
mipit-adapter-spei/
├── README.md
├── package.json
├── tsconfig.json
├── .eslintrc.json
├── .prettierrc
├── .gitignore
├── .env.example
├── Dockerfile
├── src/
│   ├── index.ts
│   ├── config/
│   │   ├── env.ts
│   │   └── constants.ts
│   ├── worker.ts
│   ├── spei/
│   │   ├── client.ts                # HTTP client sandbox/mock SPEI
│   │   ├── mock-server.ts           # Mock SPEI embebido
│   │   ├── mapper.ts                # Canónico → payload SPEI
│   │   ├── response-mapper.ts       # Respuesta SPEI → ack canónico
│   │   ├── retry.ts                 # Retry con backoff (reutilizable)
│   │   └── types.ts                 # Tipos SPEI (request/response)
│   ├── messaging/
│   │   ├── rabbitmq.ts
│   │   ├── consumer.ts
│   │   └── publisher.ts
│   └── observability/
│       ├── otel.ts
│       ├── logger.ts
│       └── metrics.ts
├── test/
│   ├── unit/
│   │   ├── mapper.test.ts
│   │   ├── response-mapper.test.ts
│   │   └── retry.test.ts
│   └── contract/
│       └── spei-mock.test.ts
└── jest.config.ts
```

---

## 2. Dependencias

Idénticas a `mipit-adapter-pix` (mismas versiones). Solo cambian:
- `"name": "mipit-adapter-spei"`
- `"description": "MiPIT PoC — SPEI rail adapter (consumer/worker)"`
- Script `"mock"`: `"tsx src/spei/mock-server.ts"`

---

## 3. Archivos clave — diferencias con PIX

### 3.1 `src/config/env.ts`

```typescript
import { z } from 'zod';
import 'dotenv/config';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  RABBITMQ_URL: z.string(),
  QUEUE_NAME: z.string().default('payments.route.spei'),
  ACK_ROUTING_KEY: z.string().default('ack.spei'),
  EXCHANGE_NAME: z.string().default('mipit.payments'),
  SPEI_SANDBOX_URL: z.string().url().default('http://localhost:9002'),
  SPEI_MODE: z.enum(['sandbox', 'mock']).default('mock'),
  SPEI_MOCK_PORT: z.coerce.number().default(9002),
  SPEI_TIMEOUT_MS: z.coerce.number().default(10000),
  SPEI_MAX_RETRIES: z.coerce.number().default(3),
  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),
  OTEL_SERVICE_NAME: z.string().default('mipit-adapter-spei'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  INSTANCE_ID: z.string().default(`spei-${process.pid}`),
});

export const env = envSchema.parse(process.env);
```

### 3.2 `src/config/constants.ts`

```typescript
export const ADAPTER_ID = 'adapter-spei';
export const RAIL = 'SPEI' as const;
```

### 3.3 `src/spei/types.ts`

```typescript
export interface SpeiPaymentRequest {
  spei_tx_ref: string;
  monto: number;
  moneda: string;
  clabe_origen: string;
  clabe_destino: string;
  nombre_ordenante?: string;
  nombre_beneficiario?: string;
  concepto_pago?: string;
  referencia_numerica?: string;
  tipo_cuenta: string;
  origen: string;
  destino: string;
  trace?: string;
  tipo_cambio?: number;
}

export interface SpeiPaymentResponse {
  spei_tx_id: string;
  estatus: 'ACEPTADO' | 'RECHAZADO';
  monto: number;
  moneda: string;
  timestamp: string;
  codigo_error?: string;
  mensaje_error?: string;
}
```

### 3.4 `src/spei/mapper.ts`

```typescript
import type { SpeiPaymentRequest } from './types.js';

export function canonicalToSpeiPayload(canonical: any): SpeiPaymentRequest {
  const fxRate = canonical.fx?.rate ?? 1;
  const localAmount = canonical.amount.value * fxRate;

  return {
    spei_tx_ref: canonical.payment_id,
    monto: Math.round(localAmount * 100) / 100,
    moneda: 'MXN',
    clabe_origen: canonical.debtor.account_id.replace(/^SPEI-/, ''),
    clabe_destino: canonical.creditor.account_id.replace(/^SPEI-/, ''),
    nombre_ordenante: canonical.debtor.name,
    nombre_beneficiario: canonical.creditor.name,
    concepto_pago: canonical.purpose?.substring(0, 35),
    referencia_numerica: canonical.reference?.substring(0, 140),
    tipo_cuenta: 'CLABE',
    origen: canonical.origin.rail,
    destino: canonical.destination.rail ?? 'SPEI',
    trace: canonical.trace_id,
    tipo_cambio: canonical.fx?.rate,
  };
}
```

### 3.5 `src/spei/response-mapper.ts`

```typescript
import type { SpeiPaymentResponse } from './types.js';

export function speiResponseToAck(response: SpeiPaymentResponse) {
  return {
    rail_tx_id: response.spei_tx_id,
    status: response.estatus === 'ACEPTADO' ? 'ACCEPTED' as const : 'REJECTED' as const,
    error: response.codigo_error
      ? { code: response.codigo_error, message: response.mensaje_error ?? 'Error SPEI desconocido' }
      : undefined,
    raw_response: response as unknown as Record<string, unknown>,
  };
}
```

### 3.6 `src/spei/mock-server.ts`

```typescript
import express from 'express';
import { ulid } from 'ulid';
import { env } from '../config/env.js';
import { logger } from '../observability/logger.js';

const app = express();
app.use(express.json());

app.post('/spei/payments', (req, res) => {
  const { monto, clabe_origen, clabe_destino } = req.body;

  // Validar CLABE (18 dígitos)
  if (clabe_destino && !/^\d{18}$/.test(clabe_destino)) {
    return res.status(200).json({
      spei_tx_id: `SPEI-${ulid()}`,
      estatus: 'RECHAZADO',
      monto,
      moneda: 'MXN',
      timestamp: new Date().toISOString(),
      codigo_error: 'SPEI_INVALID_CLABE',
      mensaje_error: 'CLABE destino inválida (debe tener 18 dígitos)',
    });
  }

  // Simular fallo aleatorio (~10%)
  const shouldFail = Math.random() < 0.1;

  if (shouldFail) {
    return res.status(200).json({
      spei_tx_id: `SPEI-${ulid()}`,
      estatus: 'RECHAZADO',
      monto,
      moneda: 'MXN',
      timestamp: new Date().toISOString(),
      codigo_error: 'SPEI_TIMEOUT',
      mensaje_error: 'Timeout en la red SPEI',
    });
  }

  const latency = 100 + Math.random() * 400;
  setTimeout(() => {
    res.status(200).json({
      spei_tx_id: `SPEI-${ulid()}`,
      estatus: 'ACEPTADO',
      monto,
      moneda: 'MXN',
      timestamp: new Date().toISOString(),
    });
  }, latency);
});

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'spei-mock' }));

export function startMockServer() {
  const port = env.SPEI_MOCK_PORT;
  app.listen(port, () => logger.info(`SPEI mock sandbox running on port ${port}`));
}

if (process.argv[1]?.includes('mock-server')) {
  startMockServer();
}
```

### 3.7 `src/worker.ts`

Idéntico al de adapter-pix pero:
- Importa `canonicalToSpeiPayload` en lugar de `canonicalToPixPayload`
- Importa `speiResponseToAck` en lugar de `pixResponseToAck`
- Importa `sendSpeiPayment` de `./spei/client.js`
- `ADAPTER_ID = 'adapter-spei'`, `RAIL = 'SPEI'`

### 3.8 `src/spei/client.ts`

```typescript
import { env } from '../config/env.js';
import { withRetry } from './retry.js';
import type { SpeiPaymentRequest, SpeiPaymentResponse } from './types.js';

export async function sendSpeiPayment(payload: SpeiPaymentRequest): Promise<SpeiPaymentResponse> {
  return withRetry(async () => {
    const url = `${env.SPEI_SANDBOX_URL}/spei/payments`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), env.SPEI_TIMEOUT_MS);

    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });

      if (!res.ok) {
        const body = await res.text();
        throw new Error(`SPEI sandbox error: ${res.status} — ${body}`);
      }

      return (await res.json()) as SpeiPaymentResponse;
    } finally {
      clearTimeout(timeout);
    }
  }, { maxRetries: env.SPEI_MAX_RETRIES });
}
```

---

## 4. Dockerfile

Idéntico al de adapter-pix.

---

## 5. `.env.example`

```env
NODE_ENV=development
RABBITMQ_URL=amqp://mipit:mipit_secret@localhost:5672/mipit
QUEUE_NAME=payments.route.spei
ACK_ROUTING_KEY=ack.spei
EXCHANGE_NAME=mipit.payments
SPEI_SANDBOX_URL=http://localhost:9002
SPEI_MODE=mock
SPEI_MOCK_PORT=9002
SPEI_TIMEOUT_MS=10000
SPEI_MAX_RETRIES=3
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=mipit-adapter-spei
LOG_LEVEL=info
```

---

## 6. Orden de ejecución al construir

1. Crear estructura (puede copiar adapter-pix como base)
2. Ajustar nombres, tipos SPEI, mappers, mock
3. `npm install && npm run build`
4. Probar mock: `npm run mock` → `curl http://localhost:9002/health`
5. `git init && git add . && git commit -m "chore: initial mipit-adapter-spei scaffold"`
6. `git remote add origin https://github.com/MIPIT-PoC/mipit-adapter-spei.git && git push -u origin main`
