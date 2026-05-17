# Plan: mipit-observability

> **Repo GitHub**: https://github.com/MIPIT-PoC/mipit-observability
> **Propósito**: Configuraciones de observabilidad — Prometheus, Grafana dashboards, Jaeger, y OTel Collector. Todo listo para demo.
> **Posición en el flujo**: Transversal. Observa core + adaptadores + RabbitMQ + BD.

---

## 1. Estructura de carpetas

```
mipit-observability/
├── README.md
├── .gitignore
├── prometheus/
│   └── prometheus.yml               # Config de scrape
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml     # Prometheus + Jaeger como datasources
│   │   └── dashboards/
│   │       └── dashboards.yaml      # Provisionador de dashboards
│   └── dashboards/
│       ├── mipit-overview.json       # Dashboard principal
│       ├── mipit-latency.json        # Latencia por etapa (p50/p95/p99)
│       └── mipit-rails.json          # Métricas por riel (PIX vs SPEI)
├── otel-collector/
│   └── otel-collector.yaml           # Config del OTel Collector (opcional)
└── alerting/
    └── rules.yaml                    # Reglas de alertas Prometheus (opcional)
```

---

## 2. Archivos — contenido completo

### 2.1 `prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'mipit-core'
    metrics_path: /metrics
    static_configs:
      - targets: ['core:8080']
        labels:
          service: 'mipit-core'

  - job_name: 'adapter-pix'
    metrics_path: /metrics
    static_configs:
      - targets: ['adapter-pix:9100']
        labels:
          service: 'mipit-adapter-pix'

  - job_name: 'adapter-spei'
    metrics_path: /metrics
    static_configs:
      - targets: ['adapter-spei:9100']
        labels:
          service: 'mipit-adapter-spei'

  - job_name: 'rabbitmq'
    metrics_path: /metrics
    static_configs:
      - targets: ['rabbitmq:15692']
        labels:
          service: 'rabbitmq'

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']
        labels:
          service: 'postgres'
```

### 2.2 `grafana/provisioning/datasources/datasources.yaml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    editable: false
```

### 2.3 `grafana/provisioning/dashboards/dashboards.yaml`

```yaml
apiVersion: 1

providers:
  - name: 'MiPIT Dashboards'
    orgId: 1
    folder: 'MiPIT PoC'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

### 2.4 `grafana/dashboards/mipit-overview.json`

Dashboard con los siguientes paneles:
- **Transacciones Totales** (counter): `sum(mipit_payments_total)`
- **Tasa de Éxito** (gauge): `sum(mipit_payments_total{status="COMPLETED"}) / sum(mipit_payments_total) * 100`
- **Transacciones por Estado** (pie chart): `sum by (status)(mipit_payments_total)`
- **Transacciones por Riel** (bar chart): `sum by (origin_rail, destination_rail)(mipit_payments_total)`
- **Errores Recientes** (table): `sum by (status)(mipit_payments_total{status=~"FAILED|REJECTED"})`
- **Duplicados Bloqueados** (stat): `mipit_idempotency_hits_total`
- **Latencia p95 Global** (stat): `histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le))`

```json
{
  "dashboard": {
    "id": null,
    "uid": "mipit-overview",
    "title": "MiPIT — Overview",
    "tags": ["mipit", "overview"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "10s",
    "time": { "from": "now-1h", "to": "now" },
    "panels": [
      {
        "id": 1,
        "title": "Total Transacciones",
        "type": "stat",
        "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
        "targets": [{ "expr": "sum(mipit_payments_total)", "legendFormat": "Total" }],
        "fieldConfig": { "defaults": { "thresholds": { "steps": [{ "value": 0, "color": "blue" }] } } }
      },
      {
        "id": 2,
        "title": "Tasa de Éxito (%)",
        "type": "gauge",
        "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
        "targets": [{ "expr": "sum(mipit_payments_total{status='COMPLETED'}) / sum(mipit_payments_total) * 100", "legendFormat": "%" }],
        "fieldConfig": { "defaults": { "max": 100, "thresholds": { "steps": [{ "value": 0, "color": "red" }, { "value": 95, "color": "yellow" }, { "value": 99, "color": "green" }] } } }
      },
      {
        "id": 3,
        "title": "Duplicados Bloqueados (Idempotencia)",
        "type": "stat",
        "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
        "targets": [{ "expr": "mipit_idempotency_hits_total", "legendFormat": "Duplicados" }]
      },
      {
        "id": 4,
        "title": "Latencia p95 (ms)",
        "type": "stat",
        "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
        "targets": [{ "expr": "histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le))", "legendFormat": "p95" }],
        "fieldConfig": { "defaults": { "unit": "ms" } }
      },
      {
        "id": 5,
        "title": "Transacciones por Estado",
        "type": "piechart",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
        "targets": [{ "expr": "sum by (status)(mipit_payments_total)", "legendFormat": "{{status}}" }]
      },
      {
        "id": 6,
        "title": "Transacciones por Riel",
        "type": "barchart",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
        "targets": [{ "expr": "sum by (origin_rail, destination_rail)(mipit_payments_total)", "legendFormat": "{{origin_rail}} → {{destination_rail}}" }]
      }
    ]
  }
}
```

### 2.5 `grafana/dashboards/mipit-latency.json`

Dashboard con:
- **Latencia por Etapa** (heatmap): `histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le, stage))`
- **p50 / p95 / p99 Time Series**: una línea por percentil, agrupado por `stage`
- **Latencia Adaptador PIX** (histogram)
- **Latencia Adaptador SPEI** (histogram)
- **Routing Decision Latency** (stat)

### 2.6 `grafana/dashboards/mipit-rails.json`

Dashboard con:
- **Tasa de éxito PIX vs SPEI** (bar gauge)
- **Errores por riel** (table)
- **Reintentos por adaptador** (counter)
- **Errores más frecuentes** (top-k table)

### 2.7 `otel-collector/otel-collector.yaml`

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true

  prometheus:
    endpoint: 0.0.0.0:8889
    namespace: mipit

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

### 2.8 `alerting/rules.yaml` (opcional)

```yaml
groups:
  - name: mipit-alerts
    rules:
      - alert: HighErrorRate
        expr: sum(rate(mipit_payments_total{status=~"FAILED|REJECTED"}[5m])) / sum(rate(mipit_payments_total[5m])) > 0.01
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Error rate superior al 1%"

      - alert: HighLatency
        expr: histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket[5m])) by (le)) > 2000
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "Latencia p95 superior a 2 segundos"

      - alert: RabbitMQQueueBacklog
        expr: rabbitmq_queue_messages > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Cola RabbitMQ con más de 100 mensajes pendientes"
```

---

## 3. Métricas que cada servicio debe exponer

### Core (`mipit-core`)
| Métrica                          | Tipo      | Labels                              |
|----------------------------------|-----------|-------------------------------------|
| `mipit_payments_total`           | Counter   | status, origin_rail, destination_rail |
| `mipit_payment_latency_ms`       | Histogram | stage                               |
| `mipit_translation_errors_total` | Counter   | rail, error_type                    |
| `mipit_routing_decisions_total`  | Counter   | rule, destination_rail              |
| `mipit_idempotency_hits_total`   | Counter   | —                                   |

### Adaptadores (`adapter-pix`, `adapter-spei`)
| Métrica                              | Tipo      | Labels       |
|--------------------------------------|-----------|-------------|
| `mipit_adapter_requests_total`       | Counter   | status, rail |
| `mipit_adapter_latency_ms`           | Histogram | rail         |
| `mipit_adapter_retries_total`        | Counter   | rail         |
| `mipit_adapter_errors_total`         | Counter   | rail, error  |

---

## 4. Trazas (OpenTelemetry spans esperados)

Flujo de spans para una transacción exitosa:
```
[mipit-core] POST /payments
  └── [mipit-core] validate_request
  └── [mipit-core] check_idempotency
  └── [mipit-core] translate_to_canonical
  └── [mipit-core] normalize
  └── [mipit-core] route_decision
  └── [mipit-core] publish_to_rabbitmq
      └── [mipit-adapter-spei] consume_message
          └── [mipit-adapter-spei] translate_to_rail
          └── [mipit-adapter-spei] send_to_sandbox
          └── [mipit-adapter-spei] process_response
          └── [mipit-adapter-spei] publish_ack
              └── [mipit-core] consume_ack
                  └── [mipit-core] update_payment_status
```

Cada span debe incluir attributes:
- `payment_id`
- `trace_id`
- `origin_rail`
- `destination_rail`
- `stage`

---

## 5. Orden de ejecución al construir

1. Crear estructura de carpetas
2. Crear todos los archivos YAML/JSON
3. Los dashboards JSON completos se construirán manualmente en Grafana y se exportarán
4. `git init && git add . && git commit -m "chore: initial mipit-observability scaffold"`
5. `git remote add origin https://github.com/MIPIT-PoC/mipit-observability.git && git push -u origin main`
