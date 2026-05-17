# Plan: mipit-adapter-pix

> **Repo GitHub**: https://github.com/MIPIT-PoC/mipit-adapter-pix
> **Propósito**: Adaptador para el riel PIX (Brasil). Consume mensajes canónicos desde RabbitMQ, los traduce a payload PIX, llama al sandbox/mock, maneja reintentos, normaliza respuesta y publica ack de vuelta al core.
> **Posición en el flujo**: Después del enrutador. Core → RabbitMQ → `adapter-pix` → sandbox/mock PIX → ack → Core.

---

## 1. Estructura de carpetas

```
mipit-adapter-pix/
├── README.md
├── package.json
├── tsconfig.json
├── .eslintrc.json
├── .prettierrc
├── .gitignore
├── .env.example
├── Dockerfile
├── src/
│   ├── index.ts                     # Entry point — bootstrap worker
│   ├── config/
│   │   ├── env.ts                   # Validación env vars (Zod)
│   │   └── constants.ts             # Constantes (queue names, timeouts)
│   ├── worker.ts                    # Consumidor RabbitMQ principal
│   ├── pix/
│   │   ├── client.ts                # HTTP client para sandbox/mock PIX
│   │   ├── mock-server.ts           # Mock server embebido (Express mini)
│   │   ├── mapper.ts                # Canónico → payload PIX
│   │   ├── response-mapper.ts       # Respuesta PIX → ack canónico (pacs.002-like)
│   │   ├── retry.ts                 # Retry con backoff exponencial
│   │   └── types.ts                 # Tipos PIX (request/response)
│   ├── messaging/
│   │   ├── rabbitmq.ts              # Conexión a RabbitMQ
│   │   ├── consumer.ts              # Consume de payments.route.pix
│   │   └── publisher.ts             # Publica ack a mipit.payments con routing key ack.pix
│   └── observability/
│       ├── otel.ts                  # OpenTelemetry setup
│       ├── logger.ts                # Pino logger
│       └── metrics.ts               # Prometheus metrics
├── test/
│   ├── unit/
│   │   ├── mapper.test.ts
│   │   ├── response-mapper.test.ts
│   │   └── retry.test.ts
│   └── contract/
│       └── pix-mock.test.ts         # Tests contra el mock
└── jest.config.ts
```

---

## 2. Dependencias (package.json)

```json
{
  "name": "mipit-adapter-pix",
  "version": "0.1.0",
  "private": true,
  "description": "MiPIT PoC — PIX rail adapter (consumer/worker)",
  "license": "MIT",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "mock": "tsx src/pix/mock-server.ts",
    "lint": "eslint src/ --ext .ts",
    "format": "prettier --write \"src/**/*.ts\"",
    "test": "jest --passWithNoTests",
    "test:watch": "jest --watch"
  },
  "dependencies": {
    "amqplib": "^0.10.4",
    "zod": "^3.24.0",
    "pino": "^9.6.0",
    "prom-client": "^15.1.0",
    "ulid": "^2.3.0",
    "@opentelemetry/sdk-node": "^0.57.0",
    "@opentelemetry/auto-instrumentations-node": "^0.55.0",
    "@opentelemetry/exporter-trace-otlp-http": "^0.57.0",
    "@opentelemetry/resources": "^1.30.0",
    "@opentelemetry/semantic-conventions": "^1.28.0",
    "dotenv": "^16.4.0",
    "express": "^4.21.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "tsx": "^4.19.0",
    "@types/node": "^22.0.0",
    "@types/amqplib": "^0.10.0",
    "@types/express": "^5.0.0",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.0",
    "@types/jest": "^29.5.0",
    "eslint": "^9.0.0",
    "prettier": "^3.4.0",
    "@typescript-eslint/parser": "^8.0.0",
    "@typescript-eslint/eslint-plugin": "^8.0.0"
  }
}
```

---

## 3. Archivos clave — contenido esqueleto

### 3.1 `src/config/env.ts`

```typescript
import { z } from 'zod';
import 'dotenv/config';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  RABBITMQ_URL: z.string(),
  QUEUE_NAME: z.string().default('payments.route.pix'),
  ACK_ROUTING_KEY: z.string().default('ack.pix'),
  EXCHANGE_NAME: z.string().default('mipit.payments'),
  PIX_SANDBOX_URL: z.string().url().default('http://localhost:9001'),
  PIX_MODE: z.enum(['sandbox', 'mock']).default('mock'),
  PIX_MOCK_PORT: z.coerce.number().default(9001),
  PIX_TIMEOUT_MS: z.coerce.number().default(10000),
  PIX_MAX_RETRIES: z.coerce.number().default(3),
  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),
  OTEL_SERVICE_NAME: z.string().default('mipit-adapter-pix'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  INSTANCE_ID: z.string().default(`pix-${process.pid}`),
});

export const env = envSchema.parse(process.env);
```

### 3.2 `src/config/constants.ts`

```typescript
export const ADAPTER_ID = 'adapter-pix';
export const RAIL = 'PIX' as const;
```

### 3.3 `src/pix/types.ts`

```typescript
export interface PixPaymentRequest {
  pix_tx_ref: string;
  valor: number;
  moeda: string;
  chaveOrigem: string;
  chaveDestino: string;
  nomePagador?: string;
  nomeRecebedor?: string;
  finalidade?: string;
  mensagem?: string;
  timestamp?: string;
  tipoChave: string;
  origem: string;
  destino: string;
  trace?: string;
}

export interface PixPaymentResponse {
  pix_tx_id: string;
  status: 'ACCEPTED' | 'REJECTED';
  valor: number;
  moeda: string;
  timestamp: string;
  erro_codigo?: string;
  erro_mensagem?: string;
}
```

### 3.4 `src/pix/mapper.ts`

```typescript
import type { PixPaymentRequest } from './types.js';

interface CanonicalPacs008 {
  payment_id: string;
  amount: { value: number; currency: string };
  fx?: { source_currency?: string; rate?: number };
  debtor: { account_id: string; name?: string };
  creditor: { account_id: string; name?: string };
  alias: { type: string; value: string };
  purpose?: string;
  reference?: string;
  origin: { rail: string };
  destination: { rail?: string };
  trace_id?: string;
}

export function canonicalToPixPayload(canonical: CanonicalPacs008): PixPaymentRequest {
  const fxRate = canonical.fx?.rate ?? 1;
  const localAmount = canonical.amount.value * fxRate;

  return {
    pix_tx_ref: canonical.payment_id,
    valor: Math.round(localAmount * 100) / 100,
    moeda: 'BRL',
    chaveOrigem: canonical.debtor.account_id.replace(/^PIX-/, ''),
    chaveDestino: canonical.creditor.account_id.replace(/^PIX-/, ''),
    nomePagador: canonical.debtor.name,
    nomeRecebedor: canonical.creditor.name,
    finalidade: canonical.purpose?.substring(0, 35),
    mensagem: canonical.reference?.substring(0, 140),
    tipoChave: 'PIX_KEY',
    origem: canonical.origin.rail,
    destino: canonical.destination.rail ?? 'PIX',
    trace: canonical.trace_id,
  };
}
```

### 3.5 `src/pix/response-mapper.ts`

```typescript
import type { PixPaymentResponse } from './types.js';

interface RailAck {
  rail_tx_id?: string;
  status: 'ACCEPTED' | 'REJECTED' | 'ERROR';
  error?: { code: string; message: string };
  raw_response?: Record<string, unknown>;
}

export function pixResponseToAck(response: PixPaymentResponse): RailAck {
  return {
    rail_tx_id: response.pix_tx_id,
    status: response.status === 'ACCEPTED' ? 'ACCEPTED' : 'REJECTED',
    error: response.erro_codigo
      ? { code: response.erro_codigo, message: response.erro_mensagem ?? 'Unknown PIX error' }
      : undefined,
    raw_response: response as unknown as Record<string, unknown>,
  };
}
```

### 3.6 `src/pix/retry.ts`

```typescript
import { logger } from '../observability/logger.js';

interface RetryOptions {
  maxRetries: number;
  baseDelayMs?: number;
}

export async function withRetry<T>(
  fn: () => Promise<T>,
  opts: RetryOptions,
): Promise<T> {
  const { maxRetries, baseDelayMs = 500 } = opts;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt === maxRetries) throw err;

      const delay = baseDelayMs * Math.pow(2, attempt - 1);
      logger.warn({ attempt, maxRetries, delay, err }, 'Retry after failure');
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  throw new Error('Unreachable');
}
```

### 3.7 `src/pix/client.ts`

```typescript
import { env } from '../config/env.js';
import { withRetry } from './retry.js';
import type { PixPaymentRequest, PixPaymentResponse } from './types.js';
import { logger } from '../observability/logger.js';

export async function sendPixPayment(payload: PixPaymentRequest): Promise<PixPaymentResponse> {
  return withRetry(async () => {
    const url = `${env.PIX_SANDBOX_URL}/pix/payments`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), env.PIX_TIMEOUT_MS);

    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });

      if (!res.ok) {
        const body = await res.text();
        throw new Error(`PIX sandbox error: ${res.status} — ${body}`);
      }

      return (await res.json()) as PixPaymentResponse;
    } finally {
      clearTimeout(timeout);
    }
  }, { maxRetries: env.PIX_MAX_RETRIES });
}
```

### 3.8 `src/pix/mock-server.ts` (mock embebido)

```typescript
import express from 'express';
import { ulid } from 'ulid';
import { env } from '../config/env.js';
import { logger } from '../observability/logger.js';

const app = express();
app.use(express.json());

app.post('/pix/payments', (req, res) => {
  const { valor, chaveOrigem, chaveDestino } = req.body;

  // Simular fallo aleatorio (~10% de las veces)
  const shouldFail = Math.random() < 0.1;

  if (shouldFail) {
    return res.status(200).json({
      pix_tx_id: `PIX-${ulid()}`,
      status: 'REJECTED',
      valor,
      moeda: 'BRL',
      timestamp: new Date().toISOString(),
      erro_codigo: 'PIX_INSUFFICIENT_FUNDS',
      erro_mensagem: 'Saldo insuficiente na conta de origem',
    });
  }

  // Simular latencia (100-500ms)
  const latency = 100 + Math.random() * 400;
  setTimeout(() => {
    res.status(200).json({
      pix_tx_id: `PIX-${ulid()}`,
      status: 'ACCEPTED',
      valor,
      moeda: 'BRL',
      timestamp: new Date().toISOString(),
    });
  }, latency);
});

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'pix-mock' }));

export function startMockServer() {
  const port = env.PIX_MOCK_PORT;
  app.listen(port, () => logger.info(`PIX mock sandbox running on port ${port}`));
}

// Ejecutar directamente si se invoca como script
if (process.argv[1]?.includes('mock-server')) {
  startMockServer();
}
```

### 3.9 `src/worker.ts`

```typescript
import type { Channel, ConsumeMessage } from 'amqplib';
import { env } from './config/env.js';
import { ADAPTER_ID, RAIL } from './config/constants.js';
import { canonicalToPixPayload } from './pix/mapper.js';
import { pixResponseToAck } from './pix/response-mapper.js';
import { sendPixPayment } from './pix/client.js';
import { logger } from './observability/logger.js';

interface PaymentRouteMessage {
  payment_id: string;
  trace_id: string;
  canonical: Record<string, unknown>;
  destination_rail: string;
  route_rule_applied: string;
  routed_at: string;
}

interface PaymentAckMessage {
  payment_id: string;
  trace_id: string;
  source_rail: string;
  adapter_id: string;
  instance_id: string;
  status: 'ACKED_BY_RAIL' | 'REJECTED' | 'FAILED';
  rail_ack: {
    rail_tx_id?: string;
    status: 'ACCEPTED' | 'REJECTED' | 'ERROR';
    error?: { code: string; message: string };
    raw_response?: Record<string, unknown>;
  };
  latency_ms: number;
  processed_at: string;
}

export async function startWorker(channel: Channel) {
  await channel.prefetch(1);

  logger.info({ queue: env.QUEUE_NAME }, 'Waiting for messages...');

  await channel.consume(env.QUEUE_NAME, async (msg: ConsumeMessage | null) => {
    if (!msg) return;

    const startTime = Date.now();
    let routeMsg: PaymentRouteMessage;

    try {
      routeMsg = JSON.parse(msg.content.toString());
    } catch {
      logger.error('Invalid message format, discarding');
      channel.nack(msg, false, false);
      return;
    }

    logger.info({ payment_id: routeMsg.payment_id, trace_id: routeMsg.trace_id }, 'Processing PIX payment');

    try {
      const pixPayload = canonicalToPixPayload(routeMsg.canonical as any);
      const pixResponse = await sendPixPayment(pixPayload);
      const railAck = pixResponseToAck(pixResponse);
      const latencyMs = Date.now() - startTime;

      const ackMessage: PaymentAckMessage = {
        payment_id: routeMsg.payment_id,
        trace_id: routeMsg.trace_id,
        source_rail: RAIL,
        adapter_id: ADAPTER_ID,
        instance_id: env.INSTANCE_ID,
        status: railAck.status === 'ACCEPTED' ? 'ACKED_BY_RAIL' : 'REJECTED',
        rail_ack: railAck,
        latency_ms: latencyMs,
        processed_at: new Date().toISOString(),
      };

      channel.publish(
        env.EXCHANGE_NAME,
        env.ACK_ROUTING_KEY,
        Buffer.from(JSON.stringify(ackMessage)),
        { persistent: true },
      );

      logger.info({
        payment_id: routeMsg.payment_id,
        status: railAck.status,
        latency_ms: latencyMs,
      }, 'PIX payment processed');

      channel.ack(msg);
    } catch (err) {
      const latencyMs = Date.now() - startTime;
      logger.error({ payment_id: routeMsg.payment_id, err }, 'PIX payment failed after retries');

      const failAck: PaymentAckMessage = {
        payment_id: routeMsg.payment_id,
        trace_id: routeMsg.trace_id,
        source_rail: RAIL,
        adapter_id: ADAPTER_ID,
        instance_id: env.INSTANCE_ID,
        status: 'FAILED',
        rail_ack: {
          status: 'ERROR',
          error: { code: 'ADAPTER_ERROR', message: String(err) },
        },
        latency_ms: latencyMs,
        processed_at: new Date().toISOString(),
      };

      channel.publish(
        env.EXCHANGE_NAME,
        env.ACK_ROUTING_KEY,
        Buffer.from(JSON.stringify(failAck)),
        { persistent: true },
      );

      channel.nack(msg, false, false); // Goes to DLQ
    }
  });
}
```

### 3.10 `src/index.ts`

```typescript
import { initTelemetry } from './observability/otel.js';
const sdk = initTelemetry();

import { connectRabbitMQ } from './messaging/rabbitmq.js';
import { startWorker } from './worker.js';
import { startMockServer } from './pix/mock-server.js';
import { env } from './config/env.js';
import { logger } from './observability/logger.js';

async function main() {
  // Start mock server if in mock mode
  if (env.PIX_MODE === 'mock') {
    startMockServer();
    logger.info('PIX mock sandbox started');
  }

  const { channel } = await connectRabbitMQ(env.RABBITMQ_URL);
  await startWorker(channel);
  logger.info(`mipit-adapter-pix worker started (instance: ${env.INSTANCE_ID})`);

  const shutdown = async () => {
    logger.info('Shutting down adapter-pix...');
    await channel.close();
    await sdk.shutdown();
    process.exit(0);
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err) => {
  logger.fatal(err, 'Failed to start adapter-pix');
  process.exit(1);
});
```

---

## 4. Dockerfile

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
CMD ["node", "dist/index.js"]
```

---

## 5. `.env.example`

```env
NODE_ENV=development
RABBITMQ_URL=amqp://mipit:mipit_secret@localhost:5672/mipit
QUEUE_NAME=payments.route.pix
ACK_ROUTING_KEY=ack.pix
EXCHANGE_NAME=mipit.payments
PIX_SANDBOX_URL=http://localhost:9001
PIX_MODE=mock
PIX_MOCK_PORT=9001
PIX_TIMEOUT_MS=10000
PIX_MAX_RETRIES=3
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=mipit-adapter-pix
LOG_LEVEL=info
```

---

## 6. Orden de ejecución al construir

1. Crear estructura de carpetas
2. Crear package.json e instalar dependencias
3. Crear todos los archivos TypeScript
4. Verificar build: `npm run build`
5. Probar mock: `npm run mock` → `curl http://localhost:9001/health`
6. `git init && git add . && git commit -m "chore: initial mipit-adapter-pix scaffold"`
7. `git remote add origin https://github.com/MIPIT-PoC/mipit-adapter-pix.git && git push -u origin main`
