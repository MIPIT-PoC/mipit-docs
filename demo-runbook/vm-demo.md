# Runbook: Demo en VMs (post P12)

## Visión general

Despliegue real en **2 VMs** (no 3 como decía el plan original). El audit de
infra del 2026-05-16 consolidó observabilidad y messaging en VM2 para
simplificar firewall + reducir overhead.

## Topología actual

```
┌────────────────────────────────────────────┐
│            VM1: Frontend + Core            │
│  - mipit-ui (Next.js 15)                   │
│  - mipit-core (Fastify + JWT)              │
│  - PostgreSQL 16                           │
│  - Nginx (TLS termination, reverse proxy)  │
│  IP: <VM1_IP> — credentials in 1Password    │
└────────────────────────────────────────────┘
              │ AMQP 5672 + OTLP 4317 + Prom scrape
              ▼
┌────────────────────────────────────────────┐
│  VM2: Messaging + Adapters + Observability │
│  - RabbitMQ 3.13 (5672 / Mgmt 15672)       │
│  - mipit-adapter-pix   (metrics :9101)     │
│  - mipit-adapter-spei  (metrics :9102)     │
│  - mipit-adapter-breb  (metrics :9103) P04 │
│  - Mock servers (pix:7001, spei:7002,      │
│                  breb:7003)                │
│  - Prometheus  (:9090)                     │
│  - AlertManager (:9093) P07                │
│  - Grafana (:3000)                         │
│  - Jaeger  (:16686 + OTLP :4317)           │
│  IP: <VM2_IP>                              │
└────────────────────────────────────────────┘
```

> IPs reales y credenciales: ver `memory/project_vm_deployment.md`
> (auto-memory) y el .env por VM en `mipit-infra/env/`.

## Pre-requisitos

- 2 VMs Ubuntu 22.04+
- Docker Engine 26+ y Docker Compose v2
- Conectividad VM1↔VM2 en puertos:
  - **5672** AMQP (VM1→VM2)
  - **15672** RabbitMQ Mgmt (operador)
  - **4317** OTLP (VM1→VM2)
  - **9090** Prometheus (VM1→VM2, scrape inverso)
  - **9093** AlertManager (VM1→VM2 webhook)
  - **9101–9103** adapter metrics (Prometheus en VM2)
  - **8080** core HTTP (Nginx en VM1 → core local)
- Certificado TLS en VM1 (autofirmado para demo o Let's Encrypt si tiene DNS)

## VM1: Frontend + Core

### Configuración

```bash
git clone https://github.com/MIPIT-PoC/mipit-infra.git
git clone https://github.com/MIPIT-PoC/mipit-core.git
git clone https://github.com/MIPIT-PoC/mipit-ui.git
```

### Variables de entorno

`mipit-core/.env`:
```bash
DATABASE_URL=postgres://mipit:mipit_pwd@localhost:5433/mipit   # 5433 host-side, 5432 in-container
RABBITMQ_URL=amqp://mipit:mipit_secret@<VM2_IP>:5672
OTEL_EXPORTER_OTLP_ENDPOINT=http://<VM2_IP>:4317
JWT_SECRET=<set-in-secrets-vault>
NODE_ENV=staging
CORS_ALLOWED_ORIGINS=https://<VM1_DNS>,http://localhost:3001
HTTP_RATE_LIMIT_MAX=120
HTTP_RATE_LIMIT_WINDOW_MS=60000
```

`mipit-ui/.env.local`:
```bash
NEXT_PUBLIC_API_URL=https://<VM1_DNS>/api
NEXT_PUBLIC_JAEGER_URL=http://<VM2_IP>:16686    # P11 — link directo desde detalle de pago
```

### Levantar
```bash
cd mipit-infra
docker compose -f compose/docker-compose.vm1.yml up -d
```

### Verificación
```bash
curl -k https://<VM1_DNS>/api/health
curl http://localhost:8080/health
curl -X POST http://localhost:8080/auth/token -H 'Content-Type: application/json' -d '{}' | jq .access_token
```

## VM2: Messaging + Adapters + Observability

### Configuración
```bash
git clone https://github.com/MIPIT-PoC/mipit-infra.git
git clone https://github.com/MIPIT-PoC/mipit-adapter-pix.git
git clone https://github.com/MIPIT-PoC/mipit-adapter-spei.git
git clone https://github.com/MIPIT-PoC/mipit-adapter-breb.git
git clone https://github.com/MIPIT-PoC/mipit-observability.git
```

### Variables de entorno (cada adapter)
```bash
RABBITMQ_URL=amqp://mipit:mipit_secret@localhost:5672
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
CORE_CALLBACK_URL=http://<VM1_IP>:8080            # para reintentos de ack
PIX_MOCK_URL=http://pix-mock:7001                 # adapter-pix
SPEI_MOCK_URL=http://spei-mock:7002               # adapter-spei
BREB_MOCK_URL=http://breb-mock:7003               # adapter-breb (P04)
```

### Prometheus targets

`mipit-observability/prometheus/prometheus.yml` debe scrappear (P07 corrigió los puertos):
- `core:8080` → métricas HTTP core
- `adapter-pix:9101`, `adapter-spei:9102`, `adapter-breb:9103` → métricas adapters
- `rabbitmq:15692` → rabbitmq_prometheus plugin

`rule_files: [/etc/prometheus/rules/*.yaml]` se monta desde
`mipit-observability/prometheus/rules/` (recording + alert rules — P07).

`alertmanager.yml` apunta al webhook del core: `http://<VM1_IP>:8080/webhooks/alertmanager`.

### Levantar
```bash
docker compose -f compose/docker-compose.vm2.yml up -d
```

### Verificación
```bash
# RabbitMQ topology (P10 contract-test la valida automáticamente)
curl -u mipit:mipit_secret http://localhost:15672/api/exchanges/%2F/mipit.payments
curl -u mipit:mipit_secret http://localhost:15672/api/queues/%2F/payments.ack/bindings

# Adapter metrics
curl http://localhost:9101/metrics | grep mipit_adapter_requests_total
curl http://localhost:9102/metrics | grep mipit_adapter_requests_total
curl http://localhost:9103/metrics | grep mipit_adapter_requests_total

# Recording rules + alerts cargadas
curl http://localhost:9090/api/v1/rules | jq '.data.groups[].name'

# AlertManager
curl http://localhost:9093/api/v2/status
```

## Ejecución de demo

Seguir [local-demo.md](local-demo.md) reemplazando `localhost` por las IPs:

| Servicio | URL |
|---|---|
| **UI** | https://`<VM1_DNS>` |
| **Core API** | https://`<VM1_DNS>`/api (Nginx) |
| **Grafana** | http://`<VM2_IP>`:3000 |
| **Prometheus** | http://`<VM2_IP>`:9090 |
| **AlertManager** | http://`<VM2_IP>`:9093 |
| **RabbitMQ Mgmt** | http://`<VM2_IP>`:15672 |
| **Jaeger** | http://`<VM2_IP>`:16686 |

## Smoke test desde VM1
```bash
cd mipit-testkit
API_URL=https://<VM1_DNS>/api npm run smoke
API_URL=https://<VM1_DNS>/api RABBITMQ_MGMT_URL=http://mipit:mipit_secret@<VM2_IP>:15672 npm run test:contract
```

## Troubleshooting

| Problema | Verificar |
|---|---|
| Core no conecta a RabbitMQ | Firewall puerto 5672 entre VM1 y VM2 |
| Trazas no aparecen en Jaeger | Firewall puerto 4317 entre VM1 y VM2 |
| Prometheus sin targets | `docker compose logs prometheus` — confirmar rule_files loaded |
| Adapter sin métricas en Prometheus | Verificar que `mipit_adapter_*_total` esté presente en `/metrics` del adapter; P07 unificó nombres |
| AlertManager no entrega webhooks | `curl -u mipit:mipit_pwd http://<VM2_IP>:9093/api/v2/alerts`; revisar receiver en `alertmanager.yml` |
| UI sin toasts en errores | Verificar que `<Toaster />` esté montado en `mipit-ui/src/app/layout.tsx` (P11) |
| UI sin link a Jaeger | Verificar `NEXT_PUBLIC_JAEGER_URL` en `.env.local` (P11) |
| Smoke test recibe 401 | El smoke ahora hace `POST /auth/token` primero (P10); si vuelve a fallar, `NODE_ENV` está en `production` y el endpoint está deshabilitado |
| Bre-B keys rechazadas | Verificar prefijo `+573` (mobile only) y CLABE/NIT con checksum correcto — `mipit-testkit/generators/utils.ts` produce muestras válidas |
