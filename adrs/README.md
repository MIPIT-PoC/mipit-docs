# Architecture Decision Records (ADRs)

Registro de decisiones arquitectónicas del proyecto MiPIT. Cada ADR documenta una decisión significativa, su contexto, alternativas evaluadas y consecuencias.

## Índice

| ADR | Título | Estado | Fecha |
|-----|--------|--------|-------|
| [ADR-001](ADR-001-stack-typescript-node.md) | Stack tecnológico: TypeScript + Node.js | Aceptado | 2026-03-01 |
| [ADR-002](ADR-002-canonical-pacs008-json.md) | Modelo canónico basado en pacs.008 (JSON) | Aceptado | 2026-03-01 |
| [ADR-003](ADR-003-rabbitmq-async-messaging.md) | RabbitMQ como broker de mensajería asíncrona | Aceptado | 2026-03-01 |
| [ADR-004](ADR-004-idempotency-header.md) | Idempotencia vía Idempotency-Key header | Aceptado | 2026-03-01 |
| [ADR-005](ADR-005-security-poc-jwt-https.md) | Seguridad del PoC: JWT + HTTPS | Aceptado | 2026-03-01 |
| [ADR-006](ADR-006-postgres-persistence.md) | PostgreSQL como capa de persistencia | Aceptado | 2026-03-01 |
| [ADR-007](ADR-007-hybrid-modular-architecture.md) | Arquitectura híbrida modular | Aceptado | 2026-03-01 |
| [ADR-008](ADR-008-observability-otel-prometheus.md) | Observabilidad: OpenTelemetry + Prometheus + Grafana | Aceptado | 2026-03-01 |

## Template

Cada ADR sigue la estructura:

1. **Estado** — Aceptado / Propuesto / Reemplazado
2. **Fecha** — Fecha de la decisión
3. **Autores** — Quiénes participaron
4. **Contexto** — El problema o necesidad que motivó la decisión
5. **Decisión** — Qué se eligió
6. **Alternativas consideradas** — Tabla comparativa de opciones
7. **Razones** — Por qué se tomó esta decisión
8. **Consecuencias** — Impacto positivo y negativo
