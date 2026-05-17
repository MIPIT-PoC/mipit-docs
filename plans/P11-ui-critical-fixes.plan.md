# P11 — UI Critical Fixes

**Wave**: 4 (downstream)
**Repos afectados**: `mipit-ui`
**Branch**: `Auditoria-Claude`
**Estimación**: 2-3 días
**Riesgo**: Bajo (UI changes, contained)

---

## 1. Objetivo

Cerrar los bugs visibles + drift de la UI. Hoy:

- `<Toaster />` no se monta → toasts perdidas en 4 páginas.
- Origin/dest rail picker decorativo (no se envía al backend).
- SSE no recibe JWT → `/live` muere en producción con auth.
- `globals.css` define solo `--color-card`; el resto referenced pero no declared → app puede romperse en strict build.
- `payments/[id]/page.tsx` no muestra `trace_id` → ADR-008 promesa unmet.
- `__tests__/lib/constants.test.ts` espera 11 statuses; código tiene 14 → test rojo.
- `__tests__/hooks/use-payment.test.ts` mock con type obsoleto.
- 4 component stubs no usados.
- Locale `es-MX` hard-coded para fechas.
- `service-health.tsx` dice "7 rails soportados" cuando tesis es 3.
- Sin error boundary.
- Sin validación client-side de chave/CLABE/llave.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| F1 | **C** | `<Toaster />` nunca montado |
| F2 | H | Rail picker no se envía al backend |
| F3 | H | SSE no recibe JWT |
| F4 | H | `globals.css` CSS vars no declaradas |
| F5 | H | `trace_id` no se muestra en UI (ADR-008) |
| F6 | H | Test rojo (11 vs 14 statuses) |
| F7 | H | Test con type obsoleto |
| F8 | M | Stats client-side over 200-row sample |
| F9 | M | Sin error boundary |
| F10 | H | Sin client-side validation |
| F11 | M | "7 rails soportados" copy incorrecto |
| F12 | H | Locale hard-coded `es-MX` para fechas |
| F13 | M | 4 component stubs dead code |
| F14 | L | No polling visibility-aware |
| F15 | M | rail-ack-panel sin códigos Bre-B |

---

## 3. Out of scope

- **NO** se rediseña la UI (mantiene Next 15 / React 19 / Radix / Tailwind 4).
- **NO** se introduce framework de i18n completo (next-intl), solo helpers locales.
- **NO** se cambia de shadcn-incomplete a otro design system.

---

## 4. Dependencias

- **Bloquea**: nada.
- **Depende de**: P07 (UETR/trace_id en API response), P08 (SSE auth strategy).

---

## 5. Tareas detalladas

### 5.1 Mount `<Toaster />`

`mipit-ui/src/app/layout.tsx`:

```tsx
import { Toaster } from 'sonner';
import './globals.css';
// ...

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body className={inter.className}>
        <Navbar />
        <main className="min-h-screen">{children}</main>
        <Footer />
        <Toaster position="top-right" richColors closeButton />
      </body>
    </html>
  );
}
```

- [ ] Implementar
- [ ] Verify: `toast.success('test')` en cualquier página renderiza

### 5.2 Send origin/dest rail (or remove picker)

**Decisión arquitectónica**: el RouteEngine **infiere** rail desde alias prefix. El picker actual es decorativo. 3 opciones:

**Opción A**: Eliminar el picker entirely; mostrar rail inferido en preview tras typing alias.
**Opción B**: Hacer el picker funcional — enviar `origin_rail`/`destination_rail` hint al backend; backend valida coherence con alias.
**Opción C**: Picker visual + validation client-side de coherence (alias prefix matches picker).

Recomendación: **Opción C** (pragma + clean UX).

`mipit-ui/src/app/simulate/page.tsx`:

```tsx
const formSchema = z.object({
  amount: z.number().positive(),
  currency: z.string().length(3),
  originRail: z.enum(RAILS),
  destRail: z.enum(RAILS),
  debtorAlias: z.string().min(3),
  creditorAlias: z.string().min(3),
  // ...
}).refine(d => d.originRail !== d.destRail, { message: 'Origin and destination must differ', path: ['destRail']})
  .refine(d => {
    const expected = RAIL_CONFIG[d.originRail].aliasPattern;
    return expected.test(d.debtorAlias);
  }, { message: 'Debtor alias does not match origin rail format', path: ['debtorAlias'] })
  .refine(d => {
    const expected = RAIL_CONFIG[d.destRail].aliasPattern;
    return expected.test(d.creditorAlias);
  }, { message: 'Creditor alias does not match destination rail format', path: ['creditorAlias'] });
```

- [ ] Implementar Zod refinements
- [ ] Real submit handler **sí** envía `originRail` y `destRail` como hints opcionales (backend puede ignore o validate)
- [ ] OR el picker se vuelve "computed" — read-only que actualiza al typing alias

### 5.3 SSE con JWT (coord P08)

`mipit-ui/src/hooks/use-sse.ts`:

```ts
import { getToken } from '@/lib/api';

export function useSse(paymentId?: string, maxEvents = 100) {
  const [events, setEvents] = useState<PaymentEvent[]>([]);
  const [connected, setConnected] = useState(false);

  const connect = useCallback(async () => {
    const token = await getToken();
    const url = paymentId
      ? `/api/events/payments/${paymentId}?token=${encodeURIComponent(token)}`
      : `/api/events/payments?token=${encodeURIComponent(token)}`;

    const sse = new EventSource(url);
    sse.addEventListener('connected', () => setConnected(true));
    sse.addEventListener('payment_update', (e: MessageEvent) => {
      const data = JSON.parse(e.data);
      setEvents(prev => [data, ...prev].slice(0, maxEvents));
    });
    sse.onerror = () => { setConnected(false); /* reconnect logic */ };
    return sse;
  }, [paymentId, maxEvents]);

  useEffect(() => {
    let sse: EventSource | null = null;
    connect().then(s => { sse = s; });
    return () => sse?.close();
  }, [connect]);

  return { events, connected };
}
```

- [ ] Implementar
- [ ] Note: EventSource no permite custom headers — auth via query string (coord P08)
- [ ] Reconnect 3s on error

### 5.4 CSS vars

`mipit-ui/src/app/globals.css`:

```css
@import "tailwindcss";

@theme {
  --color-background: #ffffff;
  --color-foreground: #0a0a0a;
  --color-card: #ffffff;
  --color-card-foreground: #0a0a0a;
  --color-primary: #2563eb;
  --color-primary-foreground: #ffffff;
  --color-secondary: #f3f4f6;
  --color-secondary-foreground: #0a0a0a;
  --color-muted: #f3f4f6;
  --color-muted-foreground: #6b7280;
  --color-accent: #f3f4f6;
  --color-accent-foreground: #0a0a0a;
  --color-destructive: #dc2626;
  --color-destructive-foreground: #ffffff;
  --color-border: #e5e7eb;
  --color-input: #e5e7eb;
  --color-ring: #2563eb;
}

.dark, [data-theme="dark"] {
  --color-background: #0a0a0a;
  --color-foreground: #ededed;
  --color-card: #171717;
  --color-card-foreground: #ededed;
  --color-primary: #3b82f6;
  --color-primary-foreground: #0a0a0a;
  --color-secondary: #1f2937;
  --color-secondary-foreground: #ededed;
  --color-muted: #1f2937;
  --color-muted-foreground: #9ca3af;
  --color-accent: #1f2937;
  --color-accent-foreground: #ededed;
  --color-destructive: #ef4444;
  --color-destructive-foreground: #0a0a0a;
  --color-border: #374151;
  --color-input: #374151;
  --color-ring: #3b82f6;
}
```

- [ ] Definir todas las CSS variables referenced
- [ ] Verify build prod no rompe

### 5.5 Show `trace_id` and UETR (coord P07)

`mipit-ui/src/lib/types.ts`:

```ts
export interface PaymentDetail {
  payment_id: string;
  status: PaymentStatus;
  origin_rail: Rail;
  destination_rail: Rail;
  amount: number;
  currency: string;
  // ...
  trace_id?: string;
  uetr?: string;
  charge_bearer?: 'DEBT'|'CRED'|'SHAR'|'SLEV';
  instructed_amount?: number;
  instructed_currency?: string;
  settlement_amount?: number;
  settlement_currency?: string;
  exchange_rate?: number;
}
```

`mipit-ui/src/lib/constants.ts`:

```ts
export const JAEGER_BASE_URL = process.env.NEXT_PUBLIC_JAEGER_URL ?? 'http://localhost:16686';
```

`mipit-ui/src/app/payments/[id]/page.tsx`:

```tsx
<section className="border rounded p-4 space-y-2">
  <h3 className="font-semibold">Trazabilidad</h3>

  {payment.uetr && (
    <div className="flex items-center gap-2">
      <span className="text-xs text-muted-foreground">UETR (ISO 20022):</span>
      <code className="text-xs">{payment.uetr}</code>
      <button onClick={() => navigator.clipboard.writeText(payment.uetr!)}>Copy</button>
    </div>
  )}

  {payment.trace_id && (
    <div className="flex items-center gap-2">
      <span className="text-xs text-muted-foreground">Trace ID:</span>
      <code className="text-xs font-mono">{payment.trace_id}</code>
      <a
        href={`${JAEGER_BASE_URL}/trace/${payment.trace_id}`}
        target="_blank" rel="noopener noreferrer"
        className="text-blue-500 underline text-xs"
      >
        Ver en Jaeger ↗
      </a>
    </div>
  )}

  {payment.exchange_rate && (
    <div className="border-l-2 pl-2 mt-2">
      <div className="text-xs">
        Instructed: {formatCurrency(payment.instructed_amount!, payment.instructed_currency!)}
      </div>
      <div className="text-xs">
        × Rate: {payment.exchange_rate.toFixed(6)}
      </div>
      <div className="text-xs font-semibold">
        Settled: {formatCurrency(payment.settlement_amount!, payment.settlement_currency!)}
      </div>
    </div>
  )}
</section>
```

- [ ] Implementar
- [ ] `formatCurrency(amount, ccy)` helper en `lib/utils.ts` que usa `Intl.NumberFormat` con locale per currency

### 5.6 Fix `__tests__/lib/constants.test.ts`

```ts
// ANTES (fails — esperaba 11)
expect(Object.keys(STATUS_CONFIG)).toHaveLength(11);

// DESPUÉS
expect(Object.keys(STATUS_CONFIG)).toHaveLength(14);

// Y verificar cada uno
const EXPECTED_STATUSES = [
  'RECEIVED', 'VALIDATED', 'CANONICALIZED', 'NORMALIZED', 'ROUTED',
  'QUEUED', 'SENT_TO_DESTINATION', 'ACKED_BY_RAIL', 'COMPLETED',
  'FAILED', 'REJECTED', 'DUPLICATE', 'COMPENSATING', 'COMPENSATED',
  'DEAD_LETTER',
];
EXPECTED_STATUSES.forEach(s => expect(STATUS_CONFIG).toHaveProperty(s));
```

- [ ] Update test

### 5.7 Fix `use-payment.test.ts` mock shape

```ts
// ANTES
mockApi.getPayment.mockResolvedValue({
  id: 'PMT-X',
  origin: 'PIX',
  destination: 'SPEI',
  // ...
});

// DESPUÉS (matchea real PaymentDetail type)
mockApi.getPayment.mockResolvedValue({
  payment_id: 'PMT-XYZ',
  origin_rail: 'PIX',
  destination_rail: 'SPEI',
  status: 'COMPLETED',
  amount: 100,
  currency: 'BRL',
  // ...
});
```

- [ ] Update

### 5.8 Stats from analytics endpoint (not client-side)

`mipit-ui/src/components/dashboard/stats-cards.tsx`:

```tsx
'use client';
import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api';

export function StatsCards() {
  const [stats, setStats] = useState<AnalyticsSummary | null>(null);
  useEffect(() => {
    apiFetch('/analytics/summary').then(setStats);
    const t = setInterval(() => apiFetch('/analytics/summary').then(setStats), 10_000);
    return () => clearInterval(t);
  }, []);
  // render from server-computed stats
}
```

- [ ] Reemplazar client-side aggregation
- [ ] Same para `payment-table.tsx` (paginar server-side)

### 5.9 Error boundary

`mipit-ui/src/app/error.tsx` (Next 15 convention):

```tsx
'use client';
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <div className="container py-8">
      <h2 className="text-xl font-semibold">Algo salió mal</h2>
      <p className="text-sm text-muted-foreground mt-2">{error.message}</p>
      <button onClick={reset} className="mt-4 px-4 py-2 bg-blue-500 text-white rounded">
        Intentar de nuevo
      </button>
    </div>
  );
}
```

`mipit-ui/src/app/global-error.tsx`:

```tsx
'use client';
export default function GlobalError({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <html><body>
      <div className="container py-8 text-red-500">
        <h2 className="text-xl font-semibold">Error crítico</h2>
        <p>{error.message}</p>
        <button onClick={reset}>Recargar</button>
      </div>
    </body></html>
  );
}
```

- [ ] Crear ambos

### 5.10 Client-side validation patterns

`mipit-ui/src/lib/validators/`:

```ts
// rail-aliases.ts
export const PIX_ALIAS_PATTERNS = [
  { name: 'CPF', regex: /^\d{11}$/, label: 'CPF (11 dígitos)' },
  { name: 'CNPJ', regex: /^\d{14}$/, label: 'CNPJ (14 dígitos)' },
  { name: 'EMAIL', regex: /^[^@]+@[^@]+\.[^@]+$/, label: 'Email' },
  { name: 'PHONE', regex: /^\+55\d{10,11}$/, label: 'Teléfono BR' },
  { name: 'EVP', regex: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i, label: 'EVP (UUID)' },
];

export function classifyPixAlias(s: string): { type: string; valid: boolean } {
  const stripped = s.replace(/^PIX-/, '');
  for (const p of PIX_ALIAS_PATTERNS) {
    if (p.regex.test(stripped)) return { type: p.name, valid: true };
  }
  return { type: 'UNKNOWN', valid: false };
}

// Similar for SPEI (CLABE checksum), Bre-B (NIT checksum, etc.)
```

- [ ] Crear validators per rail
- [ ] Usar en Zod refinements de simulate page

### 5.11 "7 rails soportados" → "3 rails"

`mipit-ui/src/components/dashboard/service-health.tsx:119`:

```tsx
// ANTES
<p className="text-xs text-muted-foreground mt-4">7 rails soportados</p>

// DESPUÉS
<p className="text-xs text-muted-foreground mt-4">
  3 rieles activos (PIX, SPEI, Bre-B) · 4 traductores (SWIFT MT103, ISO 20022 MX, ACH NACHA, FedNow)
</p>
```

- [ ] Update

### 5.12 Locale handling per rail

`mipit-ui/src/lib/format.ts`:

```ts
export const RAIL_LOCALE: Record<Rail, string> = {
  PIX: 'pt-BR',
  SPEI: 'es-MX',
  BRE_B: 'es-CO',
  SWIFT_MT103: 'en-US',
  ISO20022_MX: 'es-MX',
  ACH_NACHA: 'en-US',
  FEDNOW: 'en-US',
};

export const RAIL_CURRENCY: Record<Rail, string> = {
  PIX: 'BRL',
  SPEI: 'MXN',
  BRE_B: 'COP',
  SWIFT_MT103: 'USD',
  ISO20022_MX: 'EUR',
  ACH_NACHA: 'USD',
  FEDNOW: 'USD',
};

export function formatAmount(amount: number, currency: string, locale?: string): string {
  return new Intl.NumberFormat(locale ?? 'es-CO', {
    style: 'currency',
    currency,
    minimumFractionDigits: ['JPY', 'KRW', 'COP'].includes(currency) ? 0 : 2,
    maximumFractionDigits: ['JPY', 'KRW', 'COP'].includes(currency) ? 0 : 2,
  }).format(amount);
}

export function formatDate(iso: string, locale?: string): string {
  return new Intl.DateTimeFormat(locale ?? 'es-CO', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).format(new Date(iso));
}
```

- [ ] Crear
- [ ] Reemplazar todos los `Intl.NumberFormat('en-US')` y `Intl.DateTimeFormat('es-MX')` hard-coded
- [ ] `payment-table.tsx`, `payments/[id]/page.tsx`, etc. usan `formatAmount(p.amount, p.currency, RAIL_LOCALE[p.origin_rail])`

### 5.13 Eliminate dead stubs

- [ ] Delete `src/components/simulate/payment-form.tsx`
- [ ] Delete `src/components/simulate/pix-form.tsx`
- [ ] Delete `src/components/simulate/spei-form.tsx`
- [ ] Delete `src/components/payments/payment-card.tsx`
- [ ] Decide on `rail-selector.tsx`: keep or delete (currently `simulate/page.tsx` inlinea su propio `RailPicker`). Recommend: delete inline, use shared `<RailSelector />`.

### 5.14 Visibility-aware polling

`mipit-ui/src/hooks/use-polling.ts` (nuevo):

```ts
import { useEffect } from 'react';

export function usePolling(fn: () => void | Promise<void>, intervalMs: number) {
  useEffect(() => {
    let active = true;
    let timer: number;

    const tick = async () => {
      if (!active) return;
      if (document.visibilityState === 'visible') {
        try { await fn(); } catch {}
      }
      timer = window.setTimeout(tick, intervalMs);
    };

    tick();
    return () => { active = false; clearTimeout(timer); };
  }, [fn, intervalMs]);
}
```

- [ ] Replace `setInterval(...)` patterns en `analytics`, `simulator`, `dashboard` con `usePolling`

### 5.15 rail-ack-panel adds Bre-B codes

`mipit-ui/src/components/payments/rail-ack-panel.tsx:31-43`:

```tsx
const ERROR_CODES: Record<Rail, Record<string, string>> = {
  PIX: {
    AM01: 'Fondos insuficientes',
    AM04: 'Sin fondos disponibles',
    AC01: 'Cuenta incorrecta',
    AC03: 'Cuenta no válida (DICT)',
    AB03: 'Pagador no admitido',
    RR04: 'Devuelto por receptor',
    BE01: 'Beneficiario inconsistente',
    DS04: 'Disputa receptor',
  },
  SPEI: {
    R01: 'CLABE incorrecta',
    R02: 'Cuenta destino bloqueada',
    R03: 'Datos incompletos',
    R04: 'Beneficiario erróneo',
    R05: 'claveRastreo duplicada',
    R08: 'Error general',
    LIM: 'Excede límite',
  },
  BRE_B: {
    BREB001: 'Fondos insuficientes',
    BREB002: 'Límite excedido',
    BREB003: 'Receptor no registrado en Bre-B',
    BREB004: 'Llave inválida',
    BREB005: 'Bre-B no disponible',
  },
};
```

- [ ] Add Bre-B section

### 5.16 Update `mipit-ui/AGENTS.md`

- [ ] Reference current test structure (`src/__tests__/`, not `test/components/`)
- [ ] Update Vite reference if exists → Next.js

---

## 6. Acceptance criteria

- [ ] `<Toaster />` mounted en `layout.tsx`
- [ ] Toast en simulate / translator / simulator pages aparece visiblemente
- [ ] Origin/dest rail picker funciona (Opción C — Zod refinement valida alias matches rail)
- [ ] SSE recibe JWT via query string; `/live` funciona con auth
- [ ] `globals.css` define todas las CSS vars usadas
- [ ] `payment/[id]` muestra `trace_id` con link a Jaeger; UETR copyable; FX breakdown
- [ ] `constants.test.ts` espera 14 statuses
- [ ] `use-payment.test.ts` mock con shape correcto
- [ ] StatsCards y PaymentTable usan `/analytics/*` endpoints
- [ ] Error boundary `app/error.tsx` + `app/global-error.tsx`
- [ ] Validators per-rail con CLABE checksum, NIT checksum
- [ ] "3 rails activos · 4 traductores" copy
- [ ] Locale per rail (BRL es pt-BR; MXN es es-MX; COP es es-CO)
- [ ] Dead stubs eliminados
- [ ] `usePolling` con visibility check
- [ ] rail-ack-panel con códigos Bre-B
- [ ] `jest` UI 100% verde
- [ ] Manual: navegar todas las páginas en dev mode sin console errors

---

## 7. Testing plan

### Manual
- Smoke test: `npm run dev`; visit each page; check console (Errors and Warnings)
- Toast: click any button that triggers success/error; verify visible
- SSE: open /live; verify "connected" badge; POST a payment; verify event appears
- Payment detail: click payment in /history; verify trace_id link works (opens Jaeger)
- Simulate: enter PIX-12345678901 / SPEI-072... ; verify accepted; enter garbage; verify rejected with clear message

### Automated
- `jest`: 100% verde post-fix
- E2E (Playwright opcional): scripted browser flow simulate→history→detail

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Toaster positioning conflicts con navbar | Use `position="bottom-right"` o adjust z-index |
| SSE token-in-URL log leak | Document; alternative: cookie auth (out of scope) |
| Locale `Intl.NumberFormat` may not be available in older Node SSR | Next 15 + Node 22 OK |
| CSS vars changes break dark mode | Test both themes |
| Test fixes mask other issues | Re-run testkit suite post-changes |

---

## 9. Commits sugeridos

1. `feat(ui): mount <Toaster /> in root layout`
2. `feat(ui): client-side rail/alias coherence validation in simulate form`
3. `fix(ui): SSE auth via JWT in query string`
4. `feat(ui): declare all CSS variables in globals.css`
5. `feat(ui): display trace_id with Jaeger link and UETR on payment detail`
6. `feat(ui): show FX instructed→settlement breakdown`
7. `fix(ui): constants test expects 14 statuses (not 11)`
8. `fix(ui): use-payment test mock shape matches PaymentDetail type`
9. `refactor(ui): stats and table fetch from /analytics/* (server-aggregated)`
10. `feat(ui): error boundary error.tsx + global-error.tsx`
11. `feat(ui): client-side validators per rail (CPF/CLABE/NIT checksum)`
12. `fix(ui): update copy "3 rails activos · 4 traductores" (was 7 rails)`
13. `feat(ui): locale per rail; Intl currency formatting`
14. `chore(ui): remove dead component stubs (4 files)`
15. `feat(ui): usePolling with visibility-aware pause`
16. `feat(ui): rail-ack-panel includes Bre-B error codes`
17. `docs(ui): update AGENTS.md to reflect Next.js + current test paths`

---

## 10. Notas para el dev

- **Toaster es la fix más alta ROI** — 5 minutos de trabajo arregla "el demo se ve roto" en 4 páginas.
- **trace_id en UI** es la fix más vendible — un panel que vea "Ver en Jaeger" → clic → traza completa se va a impresionar.
- **Locale per rail**: regla simple — el locale del **origin rail** define la presentación (un BRL aparece como `R$ 1.234,56`, un MXN como `$1,234.56`, un COP como `$ 1.234`).
- **SSE token-in-URL**: caveat de seguridad pero acceptable PoC. Document explicitly.
- **Dead stubs delete**: don't be sentimental. If grep finds zero imports, delete.
