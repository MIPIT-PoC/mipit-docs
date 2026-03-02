# mipit-docs

> Fuente de verdad documental del proyecto **MiPIT** — Middleware de Interoperabilidad para Pagos Instantáneos Transfronterizos.

Este repositorio centraliza toda la documentación del PoC: especificaciones, decisiones arquitectónicas, contratos, mapeos, reglas de ruteo, runbooks de demostración y evidencias.

## Índice de contenidos

### Documentos formales

| Carpeta | Contenido |
|---------|-----------|
| [`srs/`](srs/) | Software Requirements Specification (PDF) |
| [`spmp/`](spmp/) | Software Project Management Plan (PDF) |
| [`propuesta/`](propuesta/) | Propuesta del proyecto (PDF) |

### Diseño y arquitectura

| Archivo | Contenido |
|---------|-----------|
| [`design/architecture-overview.md`](design/architecture-overview.md) | Resumen de la arquitectura híbrida modular |
| [`design/diagrams/`](design/diagrams/) | Diagramas: alto nivel, secuencia, componentes, despliegue |

### Especificación de API

| Archivo | Contenido |
|---------|-----------|
| [`openapi/openapi.yaml`](openapi/openapi.yaml) | Contrato OpenAPI 3.1 — fuente de verdad para la API REST |

### Decisiones arquitectónicas (ADRs)

| ADR | Tema |
|-----|------|
| [ADR-001](adrs/ADR-001-stack-typescript-node.md) | Stack tecnológico: TypeScript + Node.js |
| [ADR-002](adrs/ADR-002-canonical-pacs008-json.md) | Modelo canónico basado en pacs.008 (JSON) |
| [ADR-003](adrs/ADR-003-rabbitmq-async-messaging.md) | RabbitMQ como broker de mensajería asíncrona |
| [ADR-004](adrs/ADR-004-idempotency-header.md) | Idempotencia vía Idempotency-Key header |
| [ADR-005](adrs/ADR-005-security-poc-jwt-https.md) | Seguridad del PoC: JWT + HTTPS |
| [ADR-006](adrs/ADR-006-postgres-persistence.md) | PostgreSQL como capa de persistencia |
| [ADR-007](adrs/ADR-007-hybrid-modular-architecture.md) | Arquitectura híbrida modular |
| [ADR-008](adrs/ADR-008-observability-otel-prometheus.md) | Observabilidad: OpenTelemetry + Prometheus + Grafana |

### Contratos

| Archivo | Contenido |
|---------|-----------|
| [`contracts/rabbitmq-messages.md`](contracts/rabbitmq-messages.md) | Esquemas de mensajes RabbitMQ (core ↔ adaptadores) |
| [`contracts/payment-status-machine.md`](contracts/payment-status-machine.md) | Máquina de estados PaymentStatus |
| [`contracts/error-codes.md`](contracts/error-codes.md) | Catálogo de códigos de error |

### Mapeos

| Archivo | Contenido |
|---------|-----------|
| [`mappings/canonical-fields.md`](mappings/canonical-fields.md) | Campos canónicos: tipos, validaciones, obligatoriedad |
| [`mappings/pix-to-canonical.csv`](mappings/pix-to-canonical.csv) | Mapeo PIX → Modelo canónico |
| [`mappings/canonical-to-pix.csv`](mappings/canonical-to-pix.csv) | Mapeo Modelo canónico → PIX |
| [`mappings/spei-to-canonical.csv`](mappings/spei-to-canonical.csv) | Mapeo SPEI → Modelo canónico |
| [`mappings/canonical-to-spei.csv`](mappings/canonical-to-spei.csv) | Mapeo Modelo canónico → SPEI |

### Reglas de enrutamiento

| Archivo | Contenido |
|---------|-----------|
| [`route-rules/rules.yaml`](route-rules/rules.yaml) | Reglas de enrutamiento en formato YAML |
| [`route-rules/examples.md`](route-rules/examples.md) | Ejemplos de enrutamiento: PIX→SPEI, SPEI→PIX, adapter down |

### Runbooks de demostración

| Archivo | Contenido |
|---------|-----------|
| [`demo-runbook/local-demo.md`](demo-runbook/local-demo.md) | Pasos para demo local completa con Docker Compose |
| [`demo-runbook/vm-demo.md`](demo-runbook/vm-demo.md) | Pasos para demo distribuida en 3 VMs |
| [`demo-runbook/checklist-pre-demo.md`](demo-runbook/checklist-pre-demo.md) | Checklist de verificación antes de presentar |

### Evidencias

| Carpeta | Contenido |
|---------|-----------|
| [`evidence/dashboards/`](evidence/dashboards/) | Capturas de dashboards Grafana |
| [`evidence/traces/`](evidence/traces/) | Capturas de trazas Jaeger |
| [`evidence/logs/`](evidence/logs/) | Ejemplos de logs JSON estructurados |
| [`evidence/test-results/`](evidence/test-results/) | Reportes de ejecución de tests |

## Repos relacionados

| Repo | Descripción |
|------|-------------|
| [mipit-infra](https://github.com/MIPIT-PoC/mipit-infra) | Docker Compose, Nginx, scripts de infraestructura |
| [mipit-core](https://github.com/MIPIT-PoC/mipit-core) | Motor de orquestación, enrutamiento, estados |
| [mipit-adapter-pix](https://github.com/MIPIT-PoC/mipit-adapter-pix) | Adaptador para el riel PIX (Brasil) |
| [mipit-adapter-spei](https://github.com/MIPIT-PoC/mipit-adapter-spei) | Adaptador para el riel SPEI (México) |
| [mipit-ui](https://github.com/MIPIT-PoC/mipit-ui) | Frontend React — simulación y monitoreo |
| [mipit-observability](https://github.com/MIPIT-PoC/mipit-observability) | Configuración de Grafana, Prometheus, Jaeger |
| [mipit-testkit](https://github.com/MIPIT-PoC/mipit-testkit) | Tests E2E, generador de datos, comparador |
