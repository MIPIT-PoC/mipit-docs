# Plan: mipit-ui

> **Repo GitHub**: https://github.com/MIPIT-PoC/mipit-ui
> **Propósito**: Interfaz web de simulación e inspección end-to-end del PoC. Next.js 15 + TailwindCSS + shadcn/ui.
> **Posición en el flujo**: Punto de entrada humano y "visor". UI ↔ API Core por HTTPS.

---

## 1. Estructura de carpetas

```
mipit-ui/
├── README.md
├── package.json
├── tsconfig.json
├── next.config.ts
├── tailwind.config.ts
├── postcss.config.mjs
├── .eslintrc.json
├── .prettierrc
├── .gitignore
├── .env.example
├── .env.local
├── Dockerfile
├── components.json                  # shadcn/ui config
├── public/
│   ├── favicon.ico
│   └── logo.svg
├── src/
│   ├── app/
│   │   ├── layout.tsx               # Root layout (fonts, providers, nav)
│   │   ├── page.tsx                 # Dashboard / landing
│   │   ├── globals.css              # Tailwind imports + tema custom
│   │   ├── simulate/
│   │   │   └── page.tsx             # Panel de simulación (formulario)
│   │   ├── payments/
│   │   │   └── [id]/
│   │   │       └── page.tsx         # Detalle de pago (inspector + timeline)
│   │   └── history/
│   │       └── page.tsx             # Historial de transacciones
│   ├── components/
│   │   ├── layout/
│   │   │   ├── navbar.tsx           # Navegación principal
│   │   │   ├── sidebar.tsx          # Sidebar (opcional)
│   │   │   └── footer.tsx
│   │   ├── simulate/
│   │   │   ├── rail-selector.tsx    # Selector PIX/SPEI origen + destino
│   │   │   ├── pix-form.tsx         # Formulario campos PIX
│   │   │   ├── spei-form.tsx        # Formulario campos SPEI
│   │   │   └── payment-form.tsx     # Formulario unificado (adapta por riel)
│   │   ├── payments/
│   │   │   ├── flow-timeline.tsx    # Timeline de estados (stepper visual)
│   │   │   ├── message-inspector.tsx # 3 columnas: original/canónico/traducido
│   │   │   ├── payment-status-badge.tsx
│   │   │   ├── rail-ack-panel.tsx   # Panel de respuesta del riel
│   │   │   └── payment-card.tsx     # Card resumen de un pago
│   │   ├── history/
│   │   │   ├── payment-table.tsx    # Tabla de historial
│   │   │   └── filters.tsx          # Filtros por riel, estado, fecha
│   │   ├── dashboard/
│   │   │   ├── stats-cards.tsx      # Cards de estadísticas
│   │   │   ├── recent-payments.tsx  # Últimos pagos
│   │   │   └── service-health.tsx   # Estado de servicios
│   │   └── ui/                      # Componentes shadcn/ui (auto-generados)
│   │       ├── button.tsx
│   │       ├── card.tsx
│   │       ├── input.tsx
│   │       ├── badge.tsx
│   │       ├── select.tsx
│   │       ├── table.tsx
│   │       ├── tabs.tsx
│   │       ├── toast.tsx
│   │       └── ...
│   ├── lib/
│   │   ├── api.ts                   # Client HTTP hacia mipit-core
│   │   ├── types.ts                 # Tipos compartidos (PaymentIntent, Status, etc.)
│   │   ├── utils.ts                 # Utilidades (cn, formatters)
│   │   └── constants.ts             # Constantes UI (colores por estado, etc.)
│   └── hooks/
│       ├── use-payment.ts           # Hook para fetch de un pago
│       ├── use-payments.ts          # Hook para lista de pagos
│       └── use-simulate.ts          # Hook para enviar simulación
└── test/
    └── components/
        └── payment-form.test.tsx
```

---

## 2. Dependencias (package.json)

```json
{
  "name": "mipit-ui",
  "version": "0.1.0",
  "private": true,
  "description": "MiPIT PoC — Simulation & Inspection UI",
  "license": "MIT",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "format": "prettier --write \"src/**/*.{ts,tsx}\""
  },
  "dependencies": {
    "next": "^15.1.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/postcss": "^4.0.0",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.0",
    "tailwind-merge": "^2.6.0",
    "lucide-react": "^0.469.0",
    "sonner": "^1.7.0",
    "zod": "^3.24.0",
    "@radix-ui/react-slot": "^1.1.0",
    "@radix-ui/react-select": "^2.1.0",
    "@radix-ui/react-tabs": "^1.1.0",
    "@radix-ui/react-toast": "^1.2.0",
    "@radix-ui/react-label": "^2.1.0",
    "@radix-ui/react-dialog": "^1.1.0",
    "react-hook-form": "^7.54.0",
    "@hookform/resolvers": "^3.9.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "@types/node": "^22.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "eslint": "^9.0.0",
    "eslint-config-next": "^15.1.0",
    "prettier": "^3.4.0"
  }
}
```

---

## 3. Archivos clave — contenido esqueleto

### 3.1 `src/lib/types.ts`

```typescript
export type Rail = 'PIX' | 'SPEI';

export type PaymentStatus =
  | 'RECEIVED'
  | 'VALIDATED'
  | 'CANONICALIZED'
  | 'ROUTED'
  | 'QUEUED'
  | 'SENT_TO_DESTINATION'
  | 'ACKED_BY_RAIL'
  | 'COMPLETED'
  | 'FAILED'
  | 'REJECTED'
  | 'DUPLICATE';

export interface PaymentSummary {
  payment_id: string;
  status: PaymentStatus;
  received_at: string;
  destination: Rail;
}

export interface PaymentDetail {
  payment_id: string;
  status: PaymentStatus;
  origin: Rail;
  destination: Rail;
  amount: number;
  currency: string;
  original: Record<string, unknown>;
  canonical: Record<string, unknown>;
  translated: Record<string, unknown>;
  rail_ack: {
    rail_tx_id?: string;
    status: 'ACCEPTED' | 'REJECTED' | 'ERROR';
    error?: { code: string; message: string };
  } | null;
  timestamps: {
    created_at: string;
    validated_at?: string;
    canonicalized_at?: string;
    routed_at?: string;
    queued_at?: string;
    sent_at?: string;
    acked_at?: string;
    completed_at?: string;
  };
}

export interface CreatePaymentBody {
  amount: number;
  currency: string;
  debtor: { alias: string; name?: string };
  creditor: { alias: string; name?: string };
  purpose?: string;
  reference?: string;
}
```

### 3.2 `src/lib/api.ts`

```typescript
import type { PaymentSummary, PaymentDetail, CreatePaymentBody } from './types';

const BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080';

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...init?.headers,
    },
  });

  if (!res.ok) {
    const error = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(error.message ?? `API error ${res.status}`);
  }

  return res.json() as Promise<T>;
}

export const api = {
  createPayment: (body: CreatePaymentBody, idempotencyKey?: string) =>
    apiFetch<PaymentSummary>('/payments', {
      method: 'POST',
      body: JSON.stringify(body),
      headers: idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {},
    }),

  getPayment: (id: string) =>
    apiFetch<PaymentDetail>(`/payments/${id}`),

  listPayments: (params?: { status?: string; rail?: string; limit?: number }) => {
    const query = new URLSearchParams();
    if (params?.status) query.set('status', params.status);
    if (params?.rail) query.set('rail', params.rail);
    if (params?.limit) query.set('limit', String(params.limit));
    return apiFetch<PaymentDetail[]>(`/payments?${query.toString()}`);
  },

  getHealth: () => apiFetch<{ status: string; uptime: number }>('/health'),
};
```

### 3.3 `src/lib/constants.ts`

```typescript
import type { PaymentStatus } from './types';

export const STATUS_CONFIG: Record<PaymentStatus, { label: string; color: string; step: number }> = {
  RECEIVED:             { label: 'Recibido',        color: 'bg-blue-500',    step: 1 },
  VALIDATED:            { label: 'Validado',        color: 'bg-blue-600',    step: 2 },
  CANONICALIZED:        { label: 'Canonicalizado',  color: 'bg-indigo-500',  step: 3 },
  ROUTED:               { label: 'Enrutado',        color: 'bg-purple-500',  step: 4 },
  QUEUED:               { label: 'En Cola',         color: 'bg-yellow-500',  step: 5 },
  SENT_TO_DESTINATION:  { label: 'Enviado al Riel', color: 'bg-orange-500',  step: 6 },
  ACKED_BY_RAIL:        { label: 'ACK del Riel',    color: 'bg-teal-500',    step: 7 },
  COMPLETED:            { label: 'Completado',      color: 'bg-green-500',   step: 8 },
  FAILED:               { label: 'Fallido',         color: 'bg-red-500',     step: -1 },
  REJECTED:             { label: 'Rechazado',       color: 'bg-red-400',     step: -1 },
  DUPLICATE:            { label: 'Duplicado',       color: 'bg-gray-500',    step: -1 },
};

export const RAIL_CONFIG = {
  PIX:  { label: 'PIX (Brasil)',  flag: '🇧🇷', currency: 'BRL', aliasPrefix: 'PIX-',  aliasPattern: /^PIX-[A-Za-z0-9._-]{6,64}$/ },
  SPEI: { label: 'SPEI (México)', flag: '🇲🇽', currency: 'MXN', aliasPrefix: 'SPEI-', aliasPattern: /^SPEI-\d{18}$/ },
} as const;
```

### 3.4 `src/components/simulate/rail-selector.tsx`

```tsx
'use client';

import { RAIL_CONFIG } from '@/lib/constants';
import type { Rail } from '@/lib/types';

interface Props {
  label: string;
  value: Rail;
  onChange: (rail: Rail) => void;
}

export function RailSelector({ label, value, onChange }: Props) {
  return (
    <div className="space-y-2">
      <label className="text-sm font-medium text-muted-foreground">{label}</label>
      <div className="flex gap-3">
        {(Object.entries(RAIL_CONFIG) as [Rail, typeof RAIL_CONFIG.PIX][]).map(
          ([rail, config]) => (
            <button
              key={rail}
              type="button"
              onClick={() => onChange(rail)}
              className={`flex items-center gap-2 px-4 py-3 rounded-lg border-2 transition-all ${
                value === rail
                  ? 'border-primary bg-primary/10 font-semibold'
                  : 'border-border hover:border-muted-foreground/40'
              }`}
            >
              <span className="text-xl">{config.flag}</span>
              <span>{config.label}</span>
            </button>
          ),
        )}
      </div>
    </div>
  );
}
```

### 3.5 `src/components/payments/flow-timeline.tsx`

```tsx
'use client';

import { STATUS_CONFIG } from '@/lib/constants';
import type { PaymentStatus, PaymentDetail } from '@/lib/types';

const TIMELINE_STEPS: PaymentStatus[] = [
  'RECEIVED', 'VALIDATED', 'CANONICALIZED', 'ROUTED',
  'QUEUED', 'SENT_TO_DESTINATION', 'ACKED_BY_RAIL', 'COMPLETED',
];

interface Props {
  currentStatus: PaymentStatus;
  timestamps: PaymentDetail['timestamps'];
}

export function FlowTimeline({ currentStatus, timestamps }: Props) {
  const currentStep = STATUS_CONFIG[currentStatus]?.step ?? 0;
  const isFailed = currentStep === -1;

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold">Flujo de la Transacción</h3>
      <div className="flex items-center gap-1">
        {TIMELINE_STEPS.map((step, i) => {
          const config = STATUS_CONFIG[step];
          const isActive = config.step <= currentStep && !isFailed;
          const isCurrent = step === currentStatus;

          return (
            <div key={step} className="flex items-center flex-1">
              <div className="flex flex-col items-center w-full">
                <div
                  className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold text-white transition-all ${
                    isCurrent ? `${config.color} ring-4 ring-offset-2 ring-current` :
                    isActive ? config.color : 'bg-muted'
                  }`}
                >
                  {i + 1}
                </div>
                <span className="text-[10px] mt-1 text-center text-muted-foreground">
                  {config.label}
                </span>
              </div>
              {i < TIMELINE_STEPS.length - 1 && (
                <div className={`h-0.5 w-full ${isActive ? 'bg-primary' : 'bg-muted'}`} />
              )}
            </div>
          );
        })}
      </div>
      {isFailed && (
        <div className={`text-center py-2 rounded ${STATUS_CONFIG[currentStatus].color} text-white text-sm font-semibold`}>
          {STATUS_CONFIG[currentStatus].label}
        </div>
      )}
    </div>
  );
}
```

### 3.6 `src/components/payments/message-inspector.tsx`

```tsx
'use client';

interface Props {
  original: Record<string, unknown> | null;
  canonical: Record<string, unknown> | null;
  translated: Record<string, unknown> | null;
}

export function MessageInspector({ original, canonical, translated }: Props) {
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold">Inspector de Mensajes</h3>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <MessageColumn title="Original (Riel Origen)" data={original} color="border-blue-500" />
        <MessageColumn title="Canónico (pacs.008)" data={canonical} color="border-purple-500" />
        <MessageColumn title="Traducido (Riel Destino)" data={translated} color="border-green-500" />
      </div>
    </div>
  );
}

function MessageColumn({
  title,
  data,
  color,
}: {
  title: string;
  data: Record<string, unknown> | null;
  color: string;
}) {
  return (
    <div className={`border-t-4 ${color} rounded-lg bg-muted/50 p-4`}>
      <h4 className="text-sm font-semibold mb-3">{title}</h4>
      <pre className="text-xs overflow-auto max-h-96 bg-background p-3 rounded font-mono">
        {data ? JSON.stringify(data, null, 2) : 'Pendiente...'}
      </pre>
    </div>
  );
}
```

### 3.7 `src/app/simulate/page.tsx` (esqueleto)

```tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { RailSelector } from '@/components/simulate/rail-selector';
import { api } from '@/lib/api';
import { RAIL_CONFIG } from '@/lib/constants';
import type { Rail } from '@/lib/types';

export default function SimulatePage() {
  const router = useRouter();
  const [originRail, setOriginRail] = useState<Rail>('PIX');
  const [destRail, setDestRail] = useState<Rail>('SPEI');
  const [amount, setAmount] = useState(150.25);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);

    try {
      const formData = new FormData(e.currentTarget);
      const result = await api.createPayment({
        amount,
        currency: 'USD',
        debtor: {
          alias: formData.get('debtor_alias') as string,
          name: formData.get('debtor_name') as string,
        },
        creditor: {
          alias: formData.get('creditor_alias') as string,
          name: formData.get('creditor_name') as string,
        },
        purpose: formData.get('purpose') as string || 'P2P',
        reference: formData.get('reference') as string || 'MIPIT-POC',
      });

      router.push(`/payments/${result.payment_id}`);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-3xl mx-auto space-y-8 p-8">
      <div>
        <h1 className="text-3xl font-bold">Simulación de Pago</h1>
        <p className="text-muted-foreground mt-2">
          Inicia una transacción transfronteriza entre rieles de pago
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-2 gap-6">
          <RailSelector label="Riel Origen" value={originRail} onChange={setOriginRail} />
          <RailSelector label="Riel Destino" value={destRail} onChange={setDestRail} />
        </div>

        {/* Amount + Currency */}
        {/* Dynamic form fields based on originRail/destRail */}
        {/* Debtor fields */}
        {/* Creditor fields */}
        {/* Purpose + Reference */}
        {/* Submit button */}

        <button
          type="submit"
          disabled={loading}
          className="w-full py-3 bg-primary text-primary-foreground rounded-lg font-semibold hover:bg-primary/90 disabled:opacity-50"
        >
          {loading ? 'Procesando...' : 'Iniciar Transacción'}
        </button>
      </form>
    </div>
  );
}
```

### 3.8 `src/app/payments/[id]/page.tsx` (esqueleto)

```tsx
import { api } from '@/lib/api';
import { FlowTimeline } from '@/components/payments/flow-timeline';
import { MessageInspector } from '@/components/payments/message-inspector';

interface Props {
  params: Promise<{ id: string }>;
}

export default async function PaymentDetailPage({ params }: Props) {
  const { id } = await params;
  const payment = await api.getPayment(id);

  return (
    <div className="max-w-6xl mx-auto space-y-8 p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold font-mono">{payment.payment_id}</h1>
          <p className="text-muted-foreground">
            {payment.origin} → {payment.destination}
          </p>
        </div>
        {/* Status badge */}
      </div>

      <FlowTimeline currentStatus={payment.status} timestamps={payment.timestamps} />

      <MessageInspector
        original={payment.original}
        canonical={payment.canonical}
        translated={payment.translated}
      />

      {/* Rail ACK panel */}
      {/* Timestamps detail */}
    </div>
  );
}
```

---

## 4. Dockerfile

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
EXPOSE 3000
CMD ["node", "server.js"]
```

### `next.config.ts`

```typescript
import type { NextConfig } from 'next';

const config: NextConfig = {
  output: 'standalone',
  experimental: {
    serverActions: { bodySizeLimit: '2mb' },
  },
};

export default config;
```

---

## 5. `.env.example`

```env
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
NEXT_PUBLIC_APP_NAME=MiPIT PoC
```

---

## 6. Pantallas previstas (resumen)

| Ruta               | Pantalla                    | Descripción                                           |
|--------------------|-----------------------------|-------------------------------------------------------|
| `/`                | Dashboard                   | Estadísticas, servicios, últimas transacciones        |
| `/simulate`        | Panel de Simulación         | Selector riel + formulario dinámico + envío            |
| `/payments/[id]`   | Detalle de Pago             | Timeline + Inspector 3 columnas + Rail ACK + tiempos  |
| `/history`         | Historial                   | Tabla con filtros por riel/estado/fecha                |

---

## 7. Orden de ejecución al construir

1. `npx create-next-app@latest mipit-ui --typescript --tailwind --eslint --app --src-dir`
2. Instalar dependencias adicionales (radix, lucide, etc.)
3. `npx shadcn@latest init` + agregar componentes base
4. Crear estructura de carpetas y componentes
5. Crear tipos, API client, constantes
6. Implementar cada página
7. `npm run build` para verificar
8. `git init && git add . && git commit -m "chore: initial mipit-ui scaffold"`
9. `git remote add origin https://github.com/MIPIT-PoC/mipit-ui.git && git push -u origin main`
