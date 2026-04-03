# Guía: Agregar un Nuevo Riel de Pago

Esta guía documenta exactamente los pasos necesarios para incorporar un nuevo riel financiero a MiPIT, tanto en la capa de traducción (Option A) como en el adapter completo (Option B).

---

## Ejemplo: Agregar Bizum (España)

Bizum es un sistema de pagos inmediatos español operado por el Banco de España, basado en ISO 20022 con identificación por número de teléfono (+34...). Se usa como ejemplo ilustrativo.

---

## Option A — Solo capa de traducción

**Tiempo estimado: 2–4 horas**

### Paso 1: Declarar el riel en las constantes

```typescript
// mipit-core/src/config/constants.ts
export const RAILS = {
  // ... rieles existentes ...
  BIZUM: 'BIZUM',
} as const;

export const RAIL_METADATA = {
  // ... existentes ...
  BIZUM: {
    label: 'Bizum (España)',
    description: 'Sistema de pagos inmediatos del Banco de España',
    currency: 'EUR',
    region: 'Europa',
  },
};
```

### Paso 2: Actualizar el modelo canónico

```typescript
// mipit-core/src/domain/models/canonical.ts
export const SUPPORTED_RAILS = [
  'PIX', 'SPEI', 'SWIFT_MT103', 'ISO20022_MX', 'ACH_NACHA', 'FEDNOW',
  'BIZUM',  // ← añadir aquí
] as const;
```

### Paso 3: Crear el módulo de traducción

```
mipit-core/src/translation/
├── bizum-to-canonical.ts      ← NUEVO
└── canonical-to-bizum.ts      ← NUEVO
```

**`bizum-to-canonical.ts`** — estructura mínima:

```typescript
import { canonicalPacs008Schema, type CanonicalPacs008 } from '../domain/models/canonical.js';
import { TranslationError } from '../domain/errors/index.js';

export interface BizumPayment {
  // Los campos del protocolo real de Bizum
  idOperacion: string;
  importe: number;           // en euros, decimales
  concepto?: string;
  telefonoOrigen: string;    // +34XXXXXXXXX
  telefonoDestino: string;
  fechaOperacion: string;    // YYYY-MM-DD
  // ...
}

export async function bizumToCanonical(
  payload: BizumPayment | Record<string, unknown>,
  paymentId: string,
  traceId?: string,
): Promise<CanonicalPacs008> {
  const msg = payload as BizumPayment;

  const raw = {
    payment_id: paymentId,
    created_at: new Date().toISOString(),
    grpHdr: { msgId: msg.idOperacion, creDtTm: new Date().toISOString(), nbOfTxs: 1 },
    pmtId: { endToEndId: msg.idOperacion.substring(0, 35) },
    amount: { value: msg.importe, currency: 'EUR' },
    origin: { rail: 'BIZUM' as const },
    destination: { rail: undefined },
    debtor: { account_id: msg.telefonoOrigen, country: 'ES' },
    creditor: { account_id: msg.telefonoDestino, country: 'ES' },
    alias: { type: 'ACCOUNT' as const, value: msg.telefonoDestino },
    purpose: 'P2P',
    reference: msg.idOperacion,
    remittanceInfo: msg.concepto,
    status: 'RECEIVED',
    trace_id: traceId,
  };

  const result = canonicalPacs008Schema.safeParse(raw);
  if (!result.success) {
    throw new TranslationError('BIZUM', 'Validación fallida', { zodErrors: result.error.flatten() });
  }
  return result.data;
}
```

### Paso 4: Registrar en el Translator

```typescript
// mipit-core/src/translation/translator.ts
import { bizumToCanonical } from './bizum-to-canonical.js';
import { canonicalToBizum } from './canonical-to-bizum.js';

// En toCanonical():
case 'BIZUM':
  result = await bizumToCanonical(payload as BizumPayment, paymentId, traceId);
  break;

// En fromCanonical():
case 'BIZUM':
  result = await canonicalToBizum(canonical);
  break;
```

### Paso 5: Actualizar la UI

```typescript
// mipit-ui/src/lib/constants.ts
BIZUM: {
  label: 'Bizum (España)',
  flag: '🇪🇸',
  currency: 'EUR',
  aliasPrefix: '',
  aliasPattern: /^\+34\d{9}$/,
  region: 'Europa',
},
```

### Paso 6: Escribir tests

```
mipit-core/test/unit/translation/bizum.test.ts
```

Al terminar estos 6 pasos, el endpoint `POST /translate/preview` automáticamente incluirá Bizum en las traducciones sin más cambios.

---

## Option B — Adapter completo (envío real)

**Tiempo estimado: 1–2 días**

Requiere además un nuevo repositorio (o directorio si es monorepo):

### Estructura del adapter

```
mipit-adapter-bizum/
├── src/
│   ├── bizum/
│   │   ├── types.ts              ← Interfaces del protocolo Bizum
│   │   ├── mapper.ts             ← canonical → BizumPaymentRequest
│   │   ├── client.ts             ← HTTP client → POST /bizum/v1/pagos
│   │   ├── mock-server.ts        ← Servidor mock que simula el Banco de España
│   │   └── response-mapper.ts   ← BizumResponse → AckStatus
│   ├── messaging/
│   │   └── publisher.ts          ← Publica ACK en payments.ack
│   ├── worker.ts                 ← Consumer RabbitMQ: payments.route.BIZUM
│   └── index.ts                  ← Entry point
├── test/unit/
│   ├── mapper.test.ts
│   ├── response-mapper.test.ts
│   └── mock-server.test.ts
├── Dockerfile
└── package.json
```

### Contrato del worker

```typescript
// src/worker.ts — patrón igual que mipit-adapter-pix
channel.consume('payments.route.BIZUM', async (msg) => {
  const canonical = JSON.parse(msg.content.toString()) as CanonicalPacs008;
  const bizumReq = canonicalToBizumPayload(canonical);
  const response = await bizumClient.send(bizumReq);
  const ackStatus = mapBizumResponse(response);

  await publisher.publishAck({
    payment_id: canonical.payment_id,
    rail: 'BIZUM',
    status: ackStatus,           // ACCEPTED | REJECTED | ERROR
    rail_tx_id: response.idConfirmacion,
    error: ackStatus !== 'ACCEPTED' ? { code: response.codigoError, message: response.descripcion } : undefined,
  });

  channel.ack(msg);
});
```

### Mock del endpoint del banco

El mock simula el endpoint real del Banco de España:

```typescript
// src/bizum/mock-server.ts
app.post('/bizum/v1/pagos', (req, res) => {
  const { telefonoDestino, importe } = req.body;

  // Simular errores reales del sistema Bizum
  const rand = Math.random();
  if (rand < 0.05) return res.status(422).json({ codigoError: 'BIZ001', descripcion: 'Receptor no registrado en Bizum' });
  if (rand < 0.08) return res.status(422).json({ codigoError: 'BIZ002', descripcion: 'Límite diario excedido' });

  res.status(200).json({
    idConfirmacion: `BIZ${Date.now()}`,
    estado: 'ACEPTADA',
    fechaLiquidacion: new Date().toISOString(),
  });
});
```

### Configuración de infraestructura

```yaml
# mipit-infra/compose/docker-compose.yml — añadir:
adapter-bizum:
  image: ghcr.io/mipit-poc/mipit-adapter-bizum:latest
  build:
    context: ../../mipit-adapter-bizum
    dockerfile: Dockerfile
  container_name: mipit-adapter-bizum
  restart: unless-stopped
  env_file: ../env/bizum.env
  depends_on:
    rabbitmq:
      condition: service_healthy
  networks:
    - mipit-internal
```

### Regla de ruteo en base de datos

```sql
-- mipit-infra/db/init/seed-routes.sql — añadir:
INSERT INTO route_rules (name, condition_json, destination_rail, priority)
VALUES (
  'bizum-es-route',
  '{"creditor_alias_prefix": "+34", "currency": "EUR"}',
  'BIZUM',
  10
);
```

---

## Checklist de integración

Use esta lista al agregar cualquier nuevo riel:

### Option A (traducción)
- [ ] Declarado en `RAILS` y `RAIL_METADATA` (`constants.ts`)
- [ ] Añadido a `SUPPORTED_RAILS` (`canonical.ts`)
- [ ] `{rail}-to-canonical.ts` creado con tipos del protocolo real
- [ ] `canonical-to-{rail}.ts` creado
- [ ] Casos `switch` en `Translator.toCanonical()` y `fromCanonical()`
- [ ] Tests unitarios con payload de ejemplo real
- [ ] Añadido a `RAIL_CONFIG` en `mipit-ui/src/lib/constants.ts`
- [ ] Payload de ejemplo añadido en `src/app/translator/page.tsx`

### Option B (adapter)
- [ ] Todo lo de Option A ✓
- [ ] Nuevo repo/directorio `mipit-adapter-{rail}`
- [ ] `types.ts` con interfaces del protocolo real
- [ ] `mapper.ts` valida campos requeridos, genera IDs únicos
- [ ] `mock-server.ts` con endpoints reales y errores simulados realistas
- [ ] `client.ts` apunta al mock por defecto, al real en producción
- [ ] `response-mapper.ts` mapea todos los estados posibles
- [ ] `worker.ts` consume `payments.route.{RAIL}` y publica en `payments.ack`
- [ ] `Dockerfile` con multi-stage build
- [ ] Entrada en `docker-compose.yml`
- [ ] Regla de ruteo en BD (`route_rules`)
- [ ] Variables de entorno en `mipit-infra/env/{rail}.env.example`
- [ ] Entrada en GitHub Actions CI (`.github/workflows/ci.yml`)

---

## Decisión: ¿Option A o Option B primero?

La recomendación es siempre implementar Option A primero. Esto permite:

1. Validar que el **modelo de datos del protocolo** es correcto antes de construir el adapter
2. Usar `POST /translate/preview` para verificar que las traducciones son coherentes
3. Tener tests pasando del módulo de traducción
4. Construir el adapter con mayor confianza en el formato esperado

El adapter (Option B) puede agregarse en sprint separado una vez que la traducción esté validada.
