# P07 — Observability End-to-End

**Wave**: 4 (downstream)
**Repos afectados**: `mipit-observability`, `mipit-infra`, `mipit-core`, `mipit-adapter-{pix,spei,breb}`, `mipit-ui`
**Branch**: `Auditoria-Claude`
**Estimación**: 3-4 días
**Riesgo**: Medio (cambios en muchos lugares, pero cada uno es localizado)

---

## 1. Objetivo

Hacer que "observable end-to-end" sea real, no marketing. Hoy:

- Prometheus scrapea `:9100` cuando los adapters publican en `:9101`/`:9102`/`:9103` → 2 de 3 down.
- `postgres-exporter` declarado pero NO existe en compose.
- `rule_files:` ausente en `prometheus.yml` → alertas no cargan.
- AlertManager no desplegado.
- OTel collector configurado pero NO desplegado; apps apuntan directo a Jaeger.
- 11/13 paneles Grafana broken (usan métricas con label `rail` inexistente).
- W3C TraceContext NO se inyecta en AMQP headers → traza se corta publisher→adapter.
- 2 trace IDs paralelos (ULID `mipit.trace_id` en DB, OTel auto-traceId en logs) → no correlation.
- UI nunca muestra `trace_id`.
- Pino sin `redact` → PII en logs.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| E40 | **C** | Scrape `adapter-pix:9100` vs real `:9101` |
| E41 | **C** | Scrape `adapter-spei:9100` vs real `:9102` |
| E42 | **C** | `postgres-exporter:9187` declarado pero no existe |
| E43 | **C** | `rule_files:` ausente en `prometheus.yml` |
| E44 | **C** | AlertManager no desplegado |
| E46 | **C** | `mipit-rails.json` 8/8 paneles rotos (label `rail` inexistente) |
| E47 | **C** | `mipit-latency.json` 3/5 rotos |
| E51 | M | OTel collector config existe pero no en compose |
| C49 | H | W3C TraceContext NO inyectado en AMQP |
| C50 | H | Doble bookkeeping ULID vs OTel traceId |
| C51 | H | `recordIdempotencyHit` métrica nunca incrementada |
| C53 | H | Pino sin redact (PII en logs) |
| F5 | H | UI no muestra `trace_id` con link a Jaeger |
| D21 | M | OTel y prom-client registries disjoint (no exemplar-link) |
| H5 | H | ADR-008 promete trace_id propagation que no llega a UI |

---

## 3. Out of scope

- **NO** se implementa Loki + Promtail completo (opcional). Sí se documenta la limitación.
- **NO** se implementa tail-sampling complejo (basic head-sampling OK para PoC).
- **NO** se desplaza Prometheus a remote_write/Thanos.

---

## 4. Dependencias

- **Bloquea**: P11 (UI muestra trace_id).
- **Depende de**: ninguna (puede correr en paralelo a P01-P06).

---

## 5. Tareas detalladas

### 5.1 Fix Prometheus scrape ports

`mipit-observability/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'mipit-core'
    static_configs:
      - targets: ['core:8080']

  - job_name: 'adapter-pix'
    static_configs:
      - targets: ['adapter-pix:9101']  # was :9100

  - job_name: 'adapter-spei'
    static_configs:
      - targets: ['adapter-spei:9102']  # was :9100

  - job_name: 'adapter-breb'
    static_configs:
      - targets: ['adapter-breb:9103']

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['rabbitmq:15692']
    metrics_path: '/metrics'

  # postgres-exporter — decide:
  # Option A (remove):
  # - job_name: 'postgres-exporter'  # commented out
  # Option B (add service):
  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']
```

- [ ] Fix ports
- [ ] Decidir: Opción B agregar `postgres-exporter` service (recomendado)

### 5.2 Add postgres-exporter to compose

`mipit-infra/compose/docker-compose.yml`:

```yaml
  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:v0.15.0
    container_name: mipit-postgres-exporter
    environment:
      DATA_SOURCE_NAME: "postgresql://mipit:${POSTGRES_PASSWORD}@postgres:5432/mipit?sslmode=disable"
    ports:
      - "9187:9187"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - mipit-internal
    restart: unless-stopped
```

- [ ] Agregar servicio
- [ ] env: `POSTGRES_PASSWORD` ya está en env files

### 5.3 Load rule_files + deploy AlertManager

`mipit-observability/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules/*.yaml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

`mipit-infra/compose/docker-compose.yml`:

```yaml
  prometheus:
    image: prom/prometheus:v2.51.0
    volumes:
      - ../../mipit-observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ../../mipit-observability/prometheus/rules:/etc/prometheus/rules:ro  # NEW
    # ...

  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: mipit-alertmanager
    volumes:
      - ../../mipit-observability/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    ports:
      - "9093:9093"
    networks:
      - mipit-internal
    restart: unless-stopped
```

`mipit-observability/alertmanager/alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 12h

receivers:
  - name: 'default'
    # For PoC: webhook to mipit-core /webhooks/alertmanager (or log-only)
    webhook_configs:
      - url: 'http://core:8080/webhooks/alertmanager'
        send_resolved: true
```

- [ ] Create alertmanager service
- [ ] Create alertmanager.yml
- [ ] Move `rules.yaml` to `rules/mipit-rules.yaml` for clarity

### 5.4 Unify adapter metric naming

Cambiar los 3 adapters a un naming uniforme con `rail` label.

`mipit-adapter-pix/src/observability/metrics.ts`:

```ts
// ANTES (per-rail names, no rail label)
export const pixPaymentsTotal = new Counter({
  name: 'mipit_adapter_pix_payments_total',
  labelNames: ['status'],
});

// DESPUÉS (unified naming)
export const adapterRequestsTotal = new Counter({
  name: 'mipit_adapter_requests_total',
  help: 'Total adapter requests by rail and status',
  labelNames: ['rail', 'status'] as const,
});

export const adapterLatencyMs = new Histogram({
  name: 'mipit_adapter_latency_ms',
  help: 'Adapter request latency in ms',
  labelNames: ['rail'] as const,
  buckets: [50, 100, 250, 500, 1000, 2500, 5000, 10000],
});

export const adapterRetriesTotal = new Counter({
  name: 'mipit_adapter_retries_total',
  help: 'Adapter retries by rail',
  labelNames: ['rail'] as const,
});

export const adapterErrorsTotal = new Counter({
  name: 'mipit_adapter_errors_total',
  help: 'Adapter errors by rail and error code',
  labelNames: ['rail', 'error'] as const,
});
```

- [ ] Replicate exact code in PIX, SPEI, BREB adapter `metrics.ts` (DRY — extract to shared if possible)
- [ ] Worker.ts in each adapter pasa `RAIL` constant como label `rail` en cada inc/observe

### 5.5 Fix Grafana dashboards

Now that metrics have unified naming + `rail` label, las dashboards funcionan.

`mipit-observability/grafana/dashboards/mipit-rails.json`:

- [ ] Verify queries:
  - `sum(rate(mipit_adapter_requests_total{status="SUCCESS"}[5m])) by (rail)` ✓
  - `sum by (rail) (mipit_adapter_errors_total)` ✓
  - etc.
- [ ] Add Bre-B panels mirrored to PIX/SPEI
- [ ] Time range default 1h, refresh 10s

`mipit-observability/grafana/dashboards/mipit-latency.json`:

- [ ] Queries usan `mipit_adapter_latency_ms_bucket{rail="X"}` ✓

- [ ] Validate dashboards rendering en local + VM1 deploy

### 5.6 Deploy OTel Collector

`mipit-infra/compose/docker-compose.yml`:

```yaml
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.95.0
    container_name: mipit-otel-collector
    command: ["--config=/etc/otel-collector/config.yaml"]
    volumes:
      - ../../mipit-observability/otel-collector/otel-collector.yaml:/etc/otel-collector/config.yaml:ro
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP (was Jaeger directly; now proxied)
      - "8889:8889"   # Prometheus exporter
    networks:
      - mipit-internal
    depends_on:
      - jaeger
    restart: unless-stopped
```

- [ ] Add service
- [ ] Apps env: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` (en lugar de `http://jaeger:4318`)
- [ ] Verify `mipit-observability/otel-collector/otel-collector.yaml` exporta a Jaeger correctamente

### 5.7 W3C TraceContext en AMQP

`mipit-core/src/messaging/publisher.ts` (post-P06 refactor):

```ts
import { context, propagation, trace } from '@opentelemetry/api';

async publish(exchange: string, routingKey: string, payload: any, baseHeaders: any = {}): Promise<void> {
  const headers = { ...baseHeaders };
  // Inject W3C TraceContext into AMQP headers
  propagation.inject(context.active(), headers, {
    set: (carrier, key, value) => { carrier[key] = value; }
  });

  return new Promise((resolve, reject) => {
    this.channel.publish(exchange, routingKey, Buffer.from(JSON.stringify(payload)),
      { persistent: true, contentType: 'application/json', headers },
      (err) => err ? reject(err) : resolve()
    );
  });
}
```

Y el consumer side (en adapters):

```ts
import { context, propagation, trace } from '@opentelemetry/api';

channel.consume(queue, async (msg) => {
  // Extract W3C TraceContext from AMQP headers
  const parentContext = propagation.extract(context.active(), msg.properties.headers ?? {}, {
    get: (carrier, key) => carrier[key],
    keys: (carrier) => Object.keys(carrier),
  });

  // Start span as child of extracted context
  const tracer = trace.getTracer('mipit-adapter');
  await context.with(parentContext, async () => {
    const span = tracer.startSpan(`adapter.${RAIL}.process`);
    try {
      // ... processing ...
    } finally {
      span.end();
    }
  });
});
```

- [ ] Implementar en core publisher
- [ ] Implementar en los 3 adapters consumers
- [ ] Verify Jaeger UI muestra traza continua publisher→adapter

### 5.8 Single trace_id (drop ULID)

Decisión: **OTel traceId is the source of truth**. La columna `payments.trace_id TEXT` se llena con `traceId` de OTel (32-char hex), no ULID.

`mipit-core/src/api/middleware/tracing.ts`:

```ts
import { trace, context } from '@opentelemetry/api';

export function tracingMiddleware(req, reply, done) {
  // Prefer client-provided X-Trace-ID for cross-system, else use OTel auto
  const span = trace.getActiveSpan();
  const otelTraceId = span?.spanContext().traceId; // 32-char hex
  const trace_id = req.headers['x-trace-id'] || otelTraceId || generateUlid();

  // Attach to OTel as attribute too
  span?.setAttribute('mipit.trace_id', trace_id);
  req.traceId = trace_id;
  reply.header('X-Trace-ID', trace_id);
  done();
}
```

- [ ] Refactor
- [ ] DB column `trace_id` stores 32-char hex (OTel) — column already TEXT, no schema change

### 5.9 Pino redact (PII)

`mipit-core/src/observability/logger.ts`:

```ts
import pino from 'pino';

export const logger = pino({
  level: env.LOG_LEVEL,
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: {
    paths: [
      '*.debtor.taxId',
      '*.debtor.name',
      '*.debtor.email',
      '*.debtor.phone',
      '*.creditor.taxId',
      '*.creditor.name',
      '*.creditor.email',
      '*.creditor.phone',
      '*.alias.value',
      'req.headers.authorization',
      'req.headers["idempotency-key"]',
      'jwt',
      'token',
      'secret',
      'password',
    ],
    censor: '[REDACTED]',
  },
  mixin() {
    const span = trace.getActiveSpan();
    if (span) {
      const ctx = span.spanContext();
      return { trace_id: ctx.traceId, span_id: ctx.spanId };
    }
    return {};
  },
});
```

- [ ] Aplicar redact paths
- [ ] Replicar en logger de los 3 adapters

### 5.10 `recordIdempotencyHit` wire-up

`mipit-core/src/api/routes/payments.ts`:

```ts
import { recordIdempotencyHit } from '../../observability/metrics';

// On cache hit (replay):
if (existing.response_status !== null) {
  recordIdempotencyHit('cache_hit');
  return reply.code(existing.response_status).send(existing.response_body);
}

// On 409 conflict:
if (existing.request_hash !== requestHash) {
  recordIdempotencyHit('conflict');
  return reply.code(409).send(/* ... */);
}

// On in-flight:
recordIdempotencyHit('in_flight');
return reply.code(409).header('Retry-After', '2').send(/* ... */);
```

- [ ] Cablear en cada path
- [ ] Update metric labels: `mipit_idempotency_hits_total` with label `{outcome: 'cache_hit'|'conflict'|'in_flight'}`

### 5.11 UI muestra trace_id con link a Jaeger

`mipit-ui/src/lib/types.ts`:

```ts
export interface PaymentDetail {
  // ...existing fields...
  trace_id?: string;
  uetr?: string;
}
```

`mipit-ui/src/lib/constants.ts`:

```ts
export const JAEGER_BASE_URL = process.env.NEXT_PUBLIC_JAEGER_URL ?? 'http://localhost:16686';
```

`mipit-ui/src/app/payments/[id]/page.tsx`:

```tsx
{payment.trace_id && (
  <div className="flex items-center gap-2">
    <span className="text-sm font-mono">{payment.trace_id}</span>
    <a
      href={`${JAEGER_BASE_URL}/trace/${payment.trace_id}`}
      target="_blank" rel="noopener noreferrer"
      className="text-blue-500 underline"
    >
      Ver en Jaeger →
    </a>
  </div>
)}
{payment.uetr && (
  <div>
    <span className="text-sm font-mono">UETR: {payment.uetr}</span>
  </div>
)}
```

- [ ] Implementar
- [ ] (Coord P11 — más cambios UI)

### 5.12 SLO-based alerts

`mipit-observability/prometheus/rules/mipit-slo.yaml`:

```yaml
groups:
  - name: mipit-slo
    interval: 30s
    rules:
      # SLO: 99% of payments complete < 10s p95 over 30d
      # Multi-window burn-rate
      - alert: PaymentLatencySloBurnRateHigh
        expr: |
          (
            histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le)) > 10000
          ) and (
            histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[1h])) by (le)) > 10000
          )
        for: 2m
        labels:
          severity: critical
          owner: payments-team
        annotations:
          summary: "Payment latency SLO burn rate too high"
          runbook_url: "https://github.com/MIPIT-PoC/mipit-docs/blob/master/runbooks/latency-slo.md"

      # Error budget burn rate
      - alert: PaymentErrorRateSloBurnRateHigh
        expr: |
          (
            sum(rate(mipit_payments_total{status=~"FAILED|REJECTED"}[5m])) / sum(rate(mipit_payments_total[5m])) > 0.01
          ) and (
            sum(rate(mipit_payments_total{status=~"FAILED|REJECTED"}[1h])) / sum(rate(mipit_payments_total[1h])) > 0.01
          )
        for: 2m
        labels:
          severity: critical
          owner: payments-team
        annotations:
          summary: "Payment error rate SLO burn rate too high"
          runbook_url: "https://github.com/MIPIT-PoC/mipit-docs/blob/master/runbooks/error-rate-slo.md"

      # Adapter health
      - alert: AdapterUnreachable
        expr: up{job=~"adapter-.*"} == 0
        for: 1m
        labels:
          severity: warning
          owner: payments-team
        annotations:
          summary: "Adapter {{ $labels.job }} unreachable"

      # Queue backlog
      - alert: PaymentsRouteQueueBacklog
        expr: rabbitmq_queue_messages{queue=~"payments\\.route\\..*"} > 100
        for: 5m
        labels:
          severity: warning
          owner: payments-team
        annotations:
          summary: "Route queue {{ $labels.queue }} backlog > 100"
```

- [ ] Crear archivo
- [ ] Eliminar el viejo `alerting/rules.yaml` (move content here)

### 5.13 Recording rules

`mipit-observability/prometheus/rules/mipit-recording.yaml`:

```yaml
groups:
  - name: mipit-recording
    interval: 30s
    rules:
      - record: mipit:payment_latency:p50
        expr: histogram_quantile(0.5, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le))
      - record: mipit:payment_latency:p95
        expr: histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le))
      - record: mipit:payment_latency:p99
        expr: histogram_quantile(0.99, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le))
      - record: mipit:payment_success_rate
        expr: sum(rate(mipit_payments_total{status="COMPLETED"}[5m])) / sum(rate(mipit_payments_total[5m]))
      - record: mipit:adapter_success_rate:by_rail
        expr: sum by (rail) (rate(mipit_adapter_requests_total{status="success"}[5m])) / sum by (rail) (rate(mipit_adapter_requests_total[5m]))
```

- [ ] Crear archivo
- [ ] Dashboards usan estos `mipit:*` series para queries más rápidas

### 5.14 (Opcional) Loki + Promtail

Si tiempo permite:

```yaml
  loki:
    image: grafana/loki:2.9.0
    ports: ["3100:3100"]
    networks: [mipit-internal]

  promtail:
    image: grafana/promtail:2.9.0
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ../../mipit-observability/promtail/promtail.yaml:/etc/promtail/config.yaml:ro
    networks: [mipit-internal]
```

Grafana datasource: Loki. Tracegrabber correlate log lines con `trace_id`.

- [ ] Implementar OR documentar como TODO P15

---

## 6. Acceptance criteria

- [ ] `prometheus.yml` scrape targets coinciden con puertos reales (9101/9102/9103)
- [ ] `postgres-exporter` deployed y scraping verde
- [ ] `rule_files: - /etc/prometheus/rules/*.yaml` cargado
- [ ] AlertManager corriendo en :9093
- [ ] OTel collector deployed; apps apuntan a él
- [ ] 3 adapter metrics renamed: `mipit_adapter_{requests,latency,retries,errors}_*` con label `rail`
- [ ] `mipit-rails.json` 8/8 paneles populan
- [ ] `mipit-latency.json` 5/5 paneles populan
- [ ] Bre-B panels existen en ambos dashboards
- [ ] W3C TraceContext propagated en AMQP headers
- [ ] Jaeger UI muestra traza continua HTTP→pipeline→AMQP→adapter
- [ ] Logs (pino) tienen `trace_id` igual a OTel traceId
- [ ] PII redacted en logs (verificar con búsqueda de "taxId" en log output)
- [ ] `recordIdempotencyHit` se incrementa por outcome
- [ ] UI muestra `trace_id` en payment detail con link a Jaeger
- [ ] SLO alerts cargadas, AlertManager las recibe
- [ ] Test: kill RabbitMQ container, verify Jaeger no muestra traza (correctly drops)
- [ ] Test: simulate latency > 10s p95 1h, verify SLO alert fires

---

## 7. Testing plan

### Manual
- `docker compose up`; abrir Prometheus UI `/targets`; verify TODOS verdes
- Abrir AlertManager UI; verify reglas cargadas
- Abrir Jaeger UI; POST a `/payments`; buscar traza; verify spans cubre HTTP→pipeline→AMQP→adapter
- Abrir Grafana mipit-rails dashboard; verify panels populan tras N payments
- Curl `/metrics` from core, adapters; verify métricas tienen labels esperados

### Automated
- `mipit-testkit/tools/check-observability.sh` (nuevo): valida targets, rules, dashboards via API
- `mipit-observability/tests/dashboard-queries.test.ts`: cada query Grafana debe matchear al menos una serie en Prometheus

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| OTel collector adds latency (batching 5s) | Tunable; default 1s para PoC |
| W3C TraceContext propagation needs amqplib instrumentation update | Use `@opentelemetry/instrumentation-amqplib` (already enabled) |
| Adapter metric rename breaks alerts/dashboards mid-deploy | Deploy en orden: adapter metrics → dashboards → alerts |
| Loki en compose adds RAM | Opcional; skip si recursos limitados |

---

## 9. Commits sugeridos

1. `fix(observability): correct adapter scrape ports 9101/9102/9103`
2. `feat(infra): add postgres-exporter service`
3. `feat(observability): load rule_files and deploy AlertManager`
4. `refactor(adapters): unify metric naming with rail label`
5. `fix(dashboards): align panel queries to unified metric names; add Bre-B`
6. `feat(infra): deploy OTel collector; apps route via collector`
7. `feat(observability): inject W3C TraceContext into AMQP headers`
8. `refactor(observability): consolidate trace_id to OTel traceId`
9. `feat(observability): pino redact PII paths`
10. `feat(observability): wire recordIdempotencyHit with outcome label`
11. `feat(ui): display trace_id and UETR with Jaeger link on payment detail`
12. `feat(observability): SLO burn-rate alerts and recording rules`
13. `docs(observability): runbook stubs for latency and error-rate SLOs`

---

## 10. Notas para el dev

- **Trace propagation es la feature**. Si OTel collector está deployed y W3C headers fluyen, Jaeger UI muestra una traza linda end-to-end. Eso es lo que un panel de defensa quiere ver.
- **Metric naming rename es breaking** para anyone que tenga queries custom en Grafana. Comunicar antes.
- **Postgres-exporter** trae métricas valiosas: `pg_stat_database_*, pg_stat_user_tables_*`. Cero costo, alto ROI.
- **Pino redact**: si el JSON profundo no permite path-based (Pino limitation con nested arrays), agregar `serializers` custom.
