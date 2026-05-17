# P05 — FX Cross-Currency Implementation

**Wave**: 3 (cross-cutting, post rail-specific)
**Repos afectados**: `mipit-core`, `mipit-adapter-pix`, `mipit-adapter-spei`, `mipit-adapter-breb`
**Branch**: `Auditoria-Claude`
**Estimación**: 2-3 días
**Riesgo**: Alto (el claim "cross-border" del proyecto depende de esto)

---

## 1. Objetivo

Hacer que la conversión de divisa **realmente funcione end-to-end**. Hoy el `FxService` calcula `local_amount` y `target_currency` en el canónico pero **los outbound translators de PIX/SPEI/Bre-B lo ignoran** — solo FedNow lo usa. Un pago BRL→MXN llega a SPEI como 100 BRL en vez de 100 BRL × FX rate.

Esto rompe el claim "cross-border / cross-currency interoperability" estructuralmente.

Plan:
1. **Adapters consumen `canonical.fx.local_amount` y `target_currency`** cuando existen.
2. **Precision per currency** (COP/JPY/HUF: 0 decimales; BRL/MXN/USD: 2; KWD: 3).
3. **Multi-leg conversion** opcional (BRL→USD→MXN reportado como rate compuesto).
4. **Persistir `XchgRate`, `InstdAmt`, `IntrBkSttlmAmt`** alineados con ISO 20022.
5. **Multi-source FX** con failover.
6. **Decimal arithmetic** (no `parseFloat` raw para FX).

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| C24 | **C** | `canonical.fx.local_amount` se calcula pero adapters PIX/SPEI/Bre-B lo ignoran |
| C25 | M | `Math.round(x*100)/100` fuerza 2 decimales (wrong COP/JPY/KWD) |
| C26 | M | `getRate('XYZ','USD')` falla a 1 — divisas desconocidas pasan 1:1 |
| C27 | M | Una sola fuente FX (openexchangerates free tier), sin failover |
| C28 | M | Sin multi-leg — BRL→COP via USD single division |
| B56 | H | FedNow `value * (rate ?? 1)` peligroso |

---

## 3. Out of scope

- **NO** se conecta a múltiples APIs FX reales (open-source rates ya existen y son free). Implementar 2 fuentes opcional.
- **NO** se implementa hedging / lock-in rate. Cada pago tiene su FX rate at-time-of-execution.
- **NO** se implementa multi-currency wallet / settlement. Cada rail es mono-moneda.

---

## 4. Dependencias

- **Bloquea**: P10 (testkit con tests cross-currency reales).
- **Depende de**: P01 (canónico tiene los campos), P02/P03/P04 (adapters refactored para mejor wire-format).

---

## 5. Tareas detalladas

### 5.1 Currency metadata

Crear `mipit-core/src/fx/currency-metadata.ts`:

```ts
/**
 * ISO 4217 currency precision (number of decimal places).
 * Source: ISO 4217 List One.
 */
export const CURRENCY_DECIMALS: Record<string, number> = {
  // 0 decimals
  BIF: 0, CLP: 0, COP: 0, DJF: 0, GNF: 0, ISK: 0, JPY: 0, KMF: 0, KRW: 0,
  PYG: 0, RWF: 0, UGX: 0, UYI: 0, VND: 0, VUV: 0, XAF: 0, XOF: 0, XPF: 0,

  // 3 decimals
  BHD: 3, IQD: 3, JOD: 3, KWD: 3, LYD: 3, OMR: 3, TND: 3,

  // 4 decimals
  CLF: 4, UYW: 4,

  // 2 decimals (default for the rest)
  BRL: 2, MXN: 2, USD: 2, EUR: 2, GBP: 2, ARS: 2, PEN: 2, CHF: 2, CAD: 2,
};

export function getCurrencyDecimals(ccy: string): number {
  return CURRENCY_DECIMALS[ccy.toUpperCase()] ?? 2;
}

export function isValidCurrencyCode(ccy: string): boolean {
  return /^[A-Z]{3}$/.test(ccy);
}

/**
 * Round amount to currency's required precision.
 * Uses banker's rounding (round-half-to-even) for fairness.
 */
export function roundToCurrency(amount: number, ccy: string): number {
  const decimals = getCurrencyDecimals(ccy);
  const factor = Math.pow(10, decimals);
  // Banker's rounding
  const scaled = amount * factor;
  const floor = Math.floor(scaled);
  const diff = scaled - floor;
  if (Math.abs(diff - 0.5) < 1e-9) {
    return (floor % 2 === 0 ? floor : floor + 1) / factor;
  }
  return Math.round(scaled) / factor;
}

/**
 * Format amount per currency for wire-format emission.
 * COP "1000" (no decimals), BRL "1000.00", KWD "1000.000".
 */
export function formatAmount(amount: number, ccy: string): string {
  const decimals = getCurrencyDecimals(ccy);
  return roundToCurrency(amount, ccy).toFixed(decimals);
}
```

- [ ] Crear archivo + tests
- [ ] Reemplazar todos los `.toFixed(2)` en translators con `formatAmount(value, currency)`

### 5.2 FxService refactor

`mipit-core/src/fx/fx-service.ts`:

```ts
import { roundToCurrency, getCurrencyDecimals } from './currency-metadata';

interface FxRate {
  base: string;
  rates: Record<string, number>;
  fetchedAt: number;
  source: string;
}

export class FxService {
  private cache: FxRate | null = null;
  private static CACHE_TTL = 5 * 60 * 1000; // 5 min

  constructor(
    private fetchFn: typeof fetch = fetch,
    private apiKey?: string,
    private sources: Array<'openexchangerates' | 'ecb' | 'fallback'> = ['openexchangerates', 'ecb', 'fallback']
  ) {}

  /**
   * Get rate from sourceCcy to targetCcy.
   * Multi-leg via USD when needed: BRL→USD→MXN.
   * Returns 1.0 if same currency.
   */
  async getRate(source: string, target: string): Promise<{ rate: number; via: 'direct' | 'usd'; source_provider: string }> {
    if (source === target) return { rate: 1, via: 'direct', source_provider: 'identity' };

    const rates = await this.getRatesCached();
    const sourceToUsd = source === 'USD' ? 1 : rates.rates[source];
    const targetToUsd = target === 'USD' ? 1 : rates.rates[target];

    if (!sourceToUsd) throw new FxError(`No rate available for currency ${source}`);
    if (!targetToUsd) throw new FxError(`No rate available for currency ${target}`);

    // rates[X] is X/USD; so USD = source / sourceToUsd; target = USD * targetToUsd
    const usdAmount = 1 / sourceToUsd;
    const targetAmount = usdAmount * targetToUsd;
    const via = source === 'USD' || target === 'USD' ? 'direct' : 'usd';

    return { rate: targetAmount, via, source_provider: rates.source };
  }

  async convert(amount: number, sourceCcy: string, targetCcy: string): Promise<{
    sourceAmount: number;
    sourceCcy: string;
    targetAmount: number;
    targetCcy: string;
    rate: number;
    via: 'direct' | 'usd';
    source_provider: string;
    timestamp: string;
  }> {
    const { rate, via, source_provider } = await this.getRate(sourceCcy, targetCcy);
    const targetAmount = roundToCurrency(amount * rate, targetCcy);
    return {
      sourceAmount: amount,
      sourceCcy,
      targetAmount,
      targetCcy,
      rate,
      via,
      source_provider,
      timestamp: new Date().toISOString()
    };
  }

  private async getRatesCached(): Promise<FxRate> {
    if (this.cache && Date.now() - this.cache.fetchedAt < FxService.CACHE_TTL) {
      return this.cache;
    }
    for (const src of this.sources) {
      try {
        const rate = await this.fetchSource(src);
        this.cache = rate;
        return rate;
      } catch (err) {
        // try next source
        logger.warn({ err, src }, 'FX source failed, trying next');
      }
    }
    throw new FxError('All FX sources failed');
  }

  private async fetchSource(src: 'openexchangerates' | 'ecb' | 'fallback'): Promise<FxRate> {
    switch (src) {
      case 'openexchangerates': return this.fetchOpenExchangeRates();
      case 'ecb': return this.fetchECB();
      case 'fallback': return this.staticFallback();
    }
  }

  private async fetchOpenExchangeRates(): Promise<FxRate> {
    if (!this.apiKey) throw new Error('OXR_API_KEY not set');
    const res = await this.fetchFn(`https://openexchangerates.org/api/latest.json?app_id=${this.apiKey}`);
    if (!res.ok) throw new Error(`OXR ${res.status}`);
    const data = await res.json() as any;
    return { base: data.base, rates: data.rates, fetchedAt: Date.now(), source: 'openexchangerates' };
  }

  private async fetchECB(): Promise<FxRate> {
    // ECB serves EUR-base XML; we'd need to convert. Stub for now.
    throw new Error('ECB FX source not implemented yet');
  }

  private staticFallback(): FxRate {
    return {
      base: 'USD',
      rates: {
        USD: 1.0,
        BRL: 5.02,
        MXN: 17.43,
        COP: 4180.0,
        EUR: 0.92,
        GBP: 0.79,
        ARS: 1010,
        PEN: 3.75,
      },
      fetchedAt: Date.now(),
      source: 'static-fallback'
    };
  }
}

export class FxError extends Error {
  constructor(message: string) { super(message); this.name = 'FxError'; }
}
```

- [ ] Refactor `fx-service.ts`
- [ ] Eliminar `Math.round(x*100)/100` (B25)
- [ ] **No falla silentemente a 1.0** para divisas desconocidas — throws `FxError`

### 5.3 Normalizer aplica FX correctamente

`mipit-core/src/normalization/rules/currency-rules.ts:23-73`. Refactor:

```ts
import { FxService } from '../../fx/fx-service';
import { getCurrencyDecimals, roundToCurrency } from '../../fx/currency-metadata';

const fxService = new FxService(/* injected */);

// Per destination rail: native currency
const RAIL_NATIVE_CURRENCY: Record<string, string> = {
  PIX: 'BRL',
  SPEI: 'MXN',
  BRE_B: 'COP',
  SWIFT_MT103: '*', // any
  ISO20022_MX: '*',
  ACH_NACHA: 'USD',
  FEDNOW: 'USD',
};

export async function applyFxRules(canonical: any, destinationRail: string): Promise<any> {
  const nativeCcy = RAIL_NATIVE_CURRENCY[destinationRail];
  if (!nativeCcy || nativeCcy === '*') return canonical; // no conversion needed

  const sourceCcy = canonical.amount.currency.toUpperCase();
  if (sourceCcy === nativeCcy) {
    // No FX needed; still populate ISO 20022 InstdAmt = IntrBkSttlmAmt
    canonical.amount.instdAmt = canonical.amount.value;
    canonical.amount.instdAmtCcy = sourceCcy;
    return canonical;
  }

  // Cross-currency: convert
  const result = await fxService.convert(canonical.amount.value, sourceCcy, nativeCcy);

  canonical.fx = {
    source_currency: result.sourceCcy,
    target_currency: result.targetCcy,
    rate: result.rate,
    local_amount: result.targetAmount,
    via: result.via,
    source_provider: result.source_provider,
    timestamp: result.timestamp,
  };

  // ISO 20022 semantics:
  //   InstdAmt = original instruction amount (in originator's currency)
  //   IntrBkSttlmAmt = settlement amount (in target rail's currency)
  canonical.amount.instdAmt = canonical.amount.value;
  canonical.amount.instdAmtCcy = sourceCcy;
  // IntrBkSttlmAmt overrides amount.value/currency:
  canonical.amount.value = result.targetAmount;
  canonical.amount.currency = result.targetCcy;

  return canonical;
}
```

- [ ] Refactorizar `currency-rules.ts`
- [ ] **`canonical.amount.value` ya viene en target currency** después del normalizer
- [ ] Adapters NO necesitan cambiar lógica de amount — ya viene correcto

### 5.4 Adapters: refactor liviano

PIX, SPEI, Bre-B mappers usan `canonical.amount.value` y `canonical.amount.currency`. Ya viene en native currency tras normalizer.

**Pero** los mappers deben **rechazar** si la moneda no coincide con su rail (defensive check):

```ts
// mipit-adapter-pix/src/pix/mapper.ts
if (canonical.amount.currency !== 'BRL') {
  throw new Error(`PIX adapter received non-BRL canonical (got ${canonical.amount.currency}). FX normalization step skipped?`);
}
```

- [ ] Agregar check defensivo en PIX (BRL), SPEI (MXN), Bre-B (COP)
- [ ] Adapters usan `formatAmount(value, currency)` de `currency-metadata.ts` (vía shared lib o duplicado)

### 5.5 FedNow corrección

`mipit-core/src/translation/canonical-to-fednow.ts:31-33`:

```ts
// ANTES (peligroso)
const amount = canonical.amount.value * (canonical.fx?.rate ?? 1);
// DESPUÉS — confiar en que el normalizer ya hizo conversion
if (canonical.amount.currency !== 'USD') {
  throw new Error(`FedNow requires USD canonical (got ${canonical.amount.currency})`);
}
const amount = canonical.amount.value;
```

### 5.6 Persistir XchgRate, InstdAmt, IntrBkSttlmAmt en DB

Coordina con P09 — agregar columnas:

```sql
ALTER TABLE payments
  ADD COLUMN instructed_amount NUMERIC(18,5),
  ADD COLUMN instructed_currency CHAR(3),
  ADD COLUMN settlement_amount NUMERIC(18,5),
  ADD COLUMN settlement_currency CHAR(3),
  ADD COLUMN exchange_rate NUMERIC(18,8),
  ADD COLUMN exchange_rate_source VARCHAR(50);
```

Pipeline persiste estos campos después de normalize step.

### 5.7 Multi-leg conversion

El servicio FX siempre va via USD si no es directo. Esto se reporta como `via: 'usd'` y un solo rate composite es returned. La trazabilidad queda en logs.

Para multi-leg explícito (e.g. BRL→EUR→COP), no implementar en PoC. Documentar como limitación.

### 5.8 Update OpenAPI

`mipit-docs/openapi/openapi.yaml` (coord P12):

- [ ] `PaymentDetail` agrega: `instructed_amount`, `instructed_currency`, `settlement_amount`, `settlement_currency`, `exchange_rate`
- [ ] Documentar que el `amount`/`currency` del request son **instructed** (originator's currency)

### 5.9 Update UI a mostrar conversion

`mipit-ui/src/app/payments/[id]/page.tsx` (coord P11):

- [ ] Si `payment.exchange_rate` está set, mostrar:
  ```
  Instructed: 100.00 BRL
  ↓ × 0.198213 (USD pivot)
  Settled:    348.91 MXN
  ```

---

## 6. Acceptance criteria

- [ ] `FxService.getRate` lanza FxError para divisas desconocidas (no falla a 1.0)
- [ ] `getCurrencyDecimals('COP') === 0` y `formatAmount(1000.5, 'COP') === '1001'`
- [ ] `getCurrencyDecimals('JPY') === 0`
- [ ] `getCurrencyDecimals('KWD') === 3`
- [ ] FxService falla over: si OXR falla, usa ECB; si ECB falla, usa static fallback
- [ ] Normalizer aplica FX y deja `canonical.amount.value` en native currency del destino
- [ ] PIX adapter rechaza canonical no-BRL
- [ ] SPEI rechaza no-MXN
- [ ] Bre-B rechaza no-COP
- [ ] FedNow rechaza no-USD
- [ ] DB persiste `instructed_*, settlement_*, exchange_rate_*`
- [ ] Test E2E PIX→SPEI con `amount: 100, currency: 'BRL'` → SPEI adapter recibe `monto: '348.91'` (MXN, calculado), no `100 BRL`
- [ ] UI muestra el desglose instructed→settled
- [ ] Suite `validate:suite` 11/11 verde

---

## 7. Testing plan

### Unit
- `fx/currency-metadata.test.ts` — decimals, rounding, formatting
- `fx/fx-service.test.ts` — multi-leg via USD, source failover, identity (same currency)
- `normalization/currency-rules.test.ts` — FX applied, original preserved as InstdAmt

### Integration
- `tests/integration/fx-cross-currency.test.ts` — POST BRL→SPEI, verify SPEI adapter receives MXN amount calculated
- `tests/integration/fx-no-conversion-same-rail.test.ts` — BRL→PIX no conversion
- `tests/integration/fx-cop-no-decimals.test.ts` — COP integer rendering

### E2E
- `mipit-testkit/e2e-fx-conversion.mjs` — sostained load, verify FX rate consistent across 1000 pagos

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| OXR free tier rate-limit (1000 req/mes) | Cache 5min agresivo, fallback estático |
| Banker's rounding diff vs `Math.round` | Tests con casos conocidos (1.005 → 1.00, 1.015 → 1.02) |
| Multi-leg path through USD adds drift | Documentar como "single-leg via USD pivot, no triangular arbitrage" |
| Adapters break if normalizer no se aplicó | Defensive check throws — log loud y claro |

---

## 9. Commits sugeridos

1. `feat(fx): currency-metadata with ISO 4217 decimals and banker rounding`
2. `refactor(fx): FxService with multi-source failover and explicit errors`
3. `fix(fx): normalizer applies FX and sets canonical to native currency`
4. `fix(fx): adapters reject non-native currency defensively`
5. `fix(fednow): require USD canonical (no inline rate multiply)`
6. `feat(persistence): persist instructed/settlement amounts and FX rate`
7. `feat(ui): display instructed→settlement breakdown on payment detail`
8. `docs(fx): document USD-pivot single-leg conversion limitation`

---

## 10. Notas para el dev

- **`canonical.amount.value` después del normalizer = settlement amount (target rail's currency)**. `instdAmt` preserva el original.
- **ISO 20022 semantics**:
  - `InstdAmt`: lo que el ordenante instruyó pagar (originator's currency)
  - `IntrBkSttlmAmt`: lo que se settle entre bancos (rail's currency)
  - `XchgRate`: la rate aplicada
- **COP**: `1000.5 COP` no existe. Banco de la República exige integer. La función `formatAmount(1000.5, 'COP')` retorna `'1001'`.
- **OXR API key**: setear `OXR_API_KEY` en env. Free tier dura para PoC.
