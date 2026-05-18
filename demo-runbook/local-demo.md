# Runbook: Demo Local Completa

## Pre-requisitos
- Docker Engine 26+ y Docker Compose v2 instalados
- Repos clonados al mismo nivel de directorio:
  `mipit-infra`, `mipit-core`, `mipit-adapter-pix`, `mipit-adapter-spei`,
  **`mipit-adapter-breb`** (P04 — Bre-B), `mipit-ui` (Next.js 15), `mipit-observability`, `mipit-testkit`.

## Pasos

### 1. Levantar infraestructura
```bash
cd mipit-infra
bash scripts/up.sh
```

### 2. Verificar servicios
```bash
bash scripts/health-check.sh
```

Salida esperada:
```
✓ PostgreSQL    → localhost:5432   (mipit/mipit_pwd, db mipit)
✓ RabbitMQ      → localhost:5672   (AMQP) / localhost:15672 (Mgmt — mipit/mipit_secret)
✓ Prometheus    → localhost:9090
✓ AlertManager  → localhost:9093   (P07)
✓ Grafana       → localhost:3000   (admin / mipit2026)
✓ Jaeger        → localhost:16686
✓ Nginx         → localhost:443
✓ mipit-core    → localhost:8080
✓ adapter-pix   → metrics :9101 / bound q.adapter.pix
✓ adapter-spei  → metrics :9102 / bound q.adapter.spei
✓ adapter-breb  → metrics :9103 / bound q.adapter.breb     (P04)
✓ mipit-ui      → http://localhost:3001 (Next.js 15)
```

Topología RabbitMQ canónica (P10 contract-test la valida):
- Exchange `mipit.payments` (topic) + DLX `mipit.dlx`
- Queue `payments.ack` con bindings `ack.pix`, `ack.spei`, `ack.breb`
- Queue `payments.dlq` (TTL 1 día, max-length 100k)

### 3. Abrir UIs
- **MiPIT UI**: https://localhost
- **Grafana**: http://localhost:3000 (admin / mipit2026) — dashboard "MiPIT Overview"
- **RabbitMQ Mgmt**: http://localhost:15672 (mipit / mipit_secret)
- **Jaeger**: http://localhost:16686
- **Prometheus**: http://localhost:9090
- **AlertManager**: http://localhost:9093

### 4. Ejecutar transacciones (los 6 rail-pairs)

Desde la UI o desde la API (`mipit-testkit/tools/smoke-test.sh` lo hace en un comando).

| # | Origen → Destino | Currency | Debtor alias | Creditor alias |
|---|---|---|---|---|
| 1 | PIX → SPEI    | BRL→MXN | `PIX-+5511999887766`         | `SPEI-012180001234567899` |
| 2 | SPEI → PIX    | MXN→BRL | `SPEI-987654321098765437`    | `PIX-fernanda.pereira.br` |
| 3 | PIX → BRE_B   | BRL→COP | `PIX-+5521999887766`         | `BREB-+573001234567`      |
| 4 | BRE_B → PIX   | COP→BRL | `BREB-@helena.medellin`      | `PIX-12345678909`         |
| 5 | SPEI → BRE_B  | MXN→COP | `SPEI-012180001234567899`    | `BREB-900123456-8`        |
| 6 | BRE_B → SPEI  | COP→MXN | `BREB-+573670859027`         | `SPEI-987654321098765437` |

> **Nota P10:** todos los alias arriba usan checksums **válidos** (CPF mod-11, CLABE mod-10, NIT mod-11). El generator `mipit-testkit/generators/utils.ts` produce muestras infinitas.

### 5. Inspeccionar
- **Inspector** (UI): 3 tabs — original / canónico / traducido.
- **Trazabilidad ISO 20022** (UI, P11): UETR, EndToEndId, ChrgBr, IntrBkSttlmDt, trace_id con link directo a Jaeger.
- **FX cross-currency** (UI, P05): bloque Instructed → Rate → Settled cuando hay conversión.
- **Grafana → MiPIT Overview**: pagos por estado, latencia P50/P95/P99 (recording rules P07), success rate por rail-pair, AlertManager.
- **Jaeger**: pegar `trace_id` para ver spans API → validator → translator → router → publisher → adapter → ack.

### 6. Probar idempotencia
- Re-enviar la misma transacción con mismo `Idempotency-Key`.
- Verificar respuesta `200 OK` (replay idempotente) o `DUPLICATE` en el detalle.
- Cambiar el body con la misma key → `409 Conflict`.

### 7. Probar fallo + DLQ
- Detener `docker stop mipit-adapter-spei` y enviar PIX→SPEI → estado `FAILED` tras retries (max 3, P09).
- Verificar mensaje en `payments.dlq` (RabbitMQ Mgmt). DLQ handler vuelve a publicarlo cuando el adapter regrese.
- AlertManager debe disparar `AdapterUnreachable` tras ~1 min (P07).

### 8. Probar compensación
```bash
TOKEN=$(curl -sf -X POST http://localhost:8080/auth/token -d '{}' -H 'Content-Type: application/json' | jq -r .access_token)
curl -X POST -H "Authorization: Bearer $TOKEN" http://localhost:8080/compensate/PMT-XXX
```

### 9. Reset
```bash
bash scripts/reset.sh
```

Limpia DB, queues, métricas. Mantiene dashboards Grafana.

---

## Smoke + contract suite (P10)

```bash
cd mipit-testkit
npm install
npm run smoke              # PIX→SPEI, SPEI→BRE_B, BRE_B→PIX con JWT
npm run test:contract      # offline (zod + schema); live si la stack está arriba
npm run validate:suite     # full E2E (~5 min)
```
