# MiPIT — Contexto del Proyecto para Cursor

Este archivo sirve como prompt de contexto para abrir el proyecto MiPIT en cualquier máquina con Cursor.

---

## Proyecto

**MiPIT** — Middleware de Integración de Pagos Internacionales en Tiempo Real
- **Tipo:** Proof of Concept (PoC) para Tesis
- **Desarrolladores:** Carlos, Nicolas
- **Duración real:** 13+ semanas de desarrollo activo (el plan original era 17; ver `mipit-docs/spmp/`)
- **Estado actual (2026-05-17):** Stack desplegado en VM1+VM2, suite de validación 11/11 verde, auditoría profunda 2026-05-16 cerrada con Waves 1–4 ejecutadas (P01–P12). Detalle en `mipit-docs/evidence/`.

---

## Repositorios

Todos los repos están bajo la organización **MIPIT-PoC** en GitHub.

| # | Repositorio | URL | Descripción | Stack |
|---|---|---|---|---|
| 1 | **mipit-core** | https://github.com/MIPIT-PoC/mipit-core.git | Core del middleware: pipeline de pagos, traducción ISO 20022, normalización, routing, mensajería, compensación, reconciliación | TypeScript, Node.js 20+, Fastify, PostgreSQL 16, RabbitMQ 3.13, Zod, Pino, OpenTelemetry |
| 2 | **mipit-infra** | https://github.com/MIPIT-PoC/mipit-infra.git | Infraestructura: Docker Compose (~16 servicios), schemas SQL + migraciones, seed data, configs | Docker, PostgreSQL 16, RabbitMQ 3.13, Jaeger, Prometheus, Grafana, AlertManager |
| 3 | **mipit-adapter-pix** | https://github.com/MIPIT-PoC/mipit-adapter-pix.git | Adaptador PIX 🇧🇷: consume de RabbitMQ, traduce a formato PIX (DICT/BCB), envía al mock server | TypeScript, Node.js, amqplib, prom-client |
| 4 | **mipit-adapter-spei** | https://github.com/MIPIT-PoC/mipit-adapter-spei.git | Adaptador SPEI 🇲🇽: consume de RabbitMQ, traduce a formato SPEI (STP/CECOBAN), envía al mock server | TypeScript, Node.js, amqplib, prom-client |
| 5 | **mipit-adapter-breb** | https://github.com/MIPIT-PoC/mipit-adapter-breb.git | Adaptador Bre-B 🇨🇴 (nuevo en P04, GA 2025-10-06 por BanRep): consume RabbitMQ, traduce a llave Bre-B (TR-002), envía al mock | TypeScript, Node.js, amqplib, prom-client |
| 6 | **mipit-ui** | https://github.com/MIPIT-PoC/mipit-ui.git | Interfaz web: simulación, historial, detalle de pagos con trazabilidad ISO 20022 (UETR, ChrgBr, trace_id → Jaeger) | **Next.js 15 (App Router)**, React 19, TypeScript, Tailwind, sonner |
| 7 | **mipit-docs** | https://github.com/MIPIT-PoC/mipit-docs.git | Documentación: ADRs, SRS, SPMP, mappings, route-rules, demo-runbook, evidence | Markdown, YAML (OpenAPI) |
| 8 | **mipit-observability** | https://github.com/MIPIT-PoC/mipit-observability.git | Dashboards Grafana, recording rules + alert rules Prometheus, config AlertManager | YAML, JSON |
| 9 | **mipit-testkit** | https://github.com/MIPIT-PoC/mipit-testkit.git | Kit de testing: generators (CPF/CLABE/NIT con checksum), fixtures por riel, contract tests, e2e, smoke, validación | TypeScript, Jest, zod, ulid |

---

## Clonar todos los repos

```bash
mkdir -p ~/Documents/Tesis && cd ~/Documents/Tesis

for r in mipit-core mipit-infra mipit-adapter-pix mipit-adapter-spei mipit-adapter-breb mipit-ui mipit-docs mipit-observability mipit-testkit; do
  git clone "https://github.com/MIPIT-PoC/$r.git"
done
```

---

## Arquitectura del proyecto

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│   mipit-ui   │────▶│  mipit-core  │────▶│   RabbitMQ 3.13  │
│ Next.js 15   │     │   Fastify    │     │  topic exchange  │
│ App Router   │     │  (JWT auth)  │     │   mipit.payments │
└─────────────┘     └───────┬──────┘     └────────┬─────────┘
                            │                      │
                    ┌───────┴───────┐    ┌─────────┼─────────┐
                    │  PostgreSQL   │    │         │         │
                    │      16       │  ┌─▼──┐ ┌────▼─┐ ┌─────▼┐
                    │  + WAL audit  │  │PIX │ │SPEI  │ │BRE_B │
                    └───────────────┘  │adp │ │adp   │ │adp   │
                                       └─┬──┘ └──┬───┘ └──┬───┘
                                       ┌─▼──┐ ┌──▼───┐ ┌──▼───┐
                                       │PIX │ │ STP  │ │BanRep│
                                       │Mock│ │ Mock │ │ Mock │
                                       └────┘ └──────┘ └──────┘

  Observabilidad transversal:
    OpenTelemetry → Jaeger (traces)
    prom-client   → Prometheus → Grafana + AlertManager
    Pino JSON     → stdout (con redact de PII)
```

### Flujo de un pago (8 pasos en mipit-core)

1. **Validar + auth** (JWT, idempotencia por Idempotency-Key, rate-limit por IP)
2. **Inferir rail** origen del alias del debtor (PIX-, SPEI-, BREB-, o por formato — CPF/CLABE/NIT/+55/+57)
3. **Persistir** pago: status `RECEIVED` → `VALIDATED` → `CANONICALIZED`
4. **Traducir** a canónico ISO 20022 pacs.008.001.10 (subset JSON) con UETR + EndToEndId + ChrgBr
5. **Normalizar** (fechas ISO 8601 UTC, FX rules si cross-currency, ChrgBr default SLEV)
6. **Rutear** via `RouteEngine` (reglas en DB por prioridad; cache TTL 5 min)
7. **Traducir** a formato destino (PIX nativo, SPEI nativo, o Bre-B llave)
8. **Publicar** a RabbitMQ `route.<rail>` → adapter consume, llama al mock, publica `ack.<rail>`

Compensación + reconciliación corren como jobs en background.

---

## Stack técnico

| Componente | Tecnología |
|---|---|
| Backend | TypeScript, Node.js 20+, Fastify |
| Auth | JWT HS256 (iss=`mipit-core`, aud=`mipit-ui`, exp 24 h), `/auth/token` dev-only |
| Base de datos | PostgreSQL 16 (`pg`), migraciones idempotentes |
| Mensajería | RabbitMQ 3.13 (`amqplib`), confirm channels, DLQ con retries=3 |
| Modelo canónico | ISO 20022 pacs.008.001.10 (subset documentado en `ADR-002`) |
| Validación | Zod (incluye checksum mod-11 CPF, mod-10 CLABE, mod-11 NIT) |
| Logging | Pino structured JSON con `redact` de PII (debtor/creditor names, taxIds, alias, headers.authorization) |
| Tracing | OpenTelemetry → Jaeger; `trace_id` propagado a la UI y enlazado a Jaeger |
| Métricas | Prometheus + recording rules + alert rules → Grafana + AlertManager (webhook a `/webhooks/alertmanager`) |
| Testing | Jest, ts-jest, Testing Library (UI), generators con checksums válidos (testkit) |
| Frontend | **Next.js 15 App Router**, React 19, TypeScript, Tailwind, sonner (toasts) |
| Infra | Docker Compose (~16 servicios incluyendo AlertManager, Jaeger, Postgres-exporter opcional) |

---

## Rieles soportados (7 totales, 3 productivos)

| Riel | Estado | Moneda | Pais | Notas |
|---|---|---|---|---|
| **PIX** | Productivo | BRL | 🇧🇷 | 24/7/365 (BACEN Res. 1/2020 art. 24). DICT keys: CPF (mod-11), CNPJ, +55 phone, email, EVP (UUIDv4). |
| **SPEI** | Productivo | MXN | 🇲🇽 | L-V 06:00–17:55 CT (Banxico Circular 14/2017). CLABE 18 dígitos + mod-10 weighted. |
| **BRE_B** | Productivo | COP | 🇨🇴 | 24/7/365 (BanRep TR-002, GA 2025-10-06). Llaves: CC, NIT (mod-11), +57 *móvil*, email, ALIAS (`@xxx`). |
| ISO20022_MX | Traducción | — | — | Pacs.008 MX-CBPR+. |
| SWIFT_MT103 | Traducción | — | — | MT103 ↔ pacs.008. |
| ACH_NACHA | Traducción | USD | 🇺🇸 | NACHA fixed-width. |
| FEDNOW | Traducción | USD | 🇺🇸 | pacs.008 (USABA ClrSysCd). |

---

## Lifecycle de pago — 14 estados

`RECEIVED, VALIDATED, CANONICALIZED, NORMALIZED, ROUTED, QUEUED, SENT_TO_DESTINATION, ACKED_BY_RAIL, COMPLETED, FAILED, REJECTED, DUPLICATE, COMPENSATING, COMPENSATED, DEAD_LETTER`

(15 si se cuenta `NORMALIZED`; la UI agrupa NORMALIZED dentro de CANONICALIZED → 14 chips visibles.)
Fuente de verdad: `mipit-core/src/domain/models/canonical.ts:PAYMENT_STATUS_ENUM` y la migración `008_payments_constraints_and_iso.sql`.

---

## Endpoints HTTP (resumen)

Documentación canónica en `mipit-docs/openapi/openapi.yaml`. Hay **25+ endpoints** activos agrupados así:

- **Public:** `GET /health`, `GET /metrics`, `POST /auth/token` (dev/staging únicamente)
- **Payments:** `POST /payments`, `GET /payments/:id`, `GET /payments`, `POST /compensate/:id`, `POST /compensate/batch`
- **Translate (debug):** `POST /translate/canonical-to/:rail`, `POST /translate/from/:rail`
- **Analytics:** `GET /analytics/throughput`, `GET /analytics/success-rate`, `GET /analytics/rate-limits`, `GET /analytics/reconciliation`
- **UI proxy:** `GET /ui/*` (router-rules, rail-config, status-config)
- **SSE:** `GET /stream/payments?token=…` (EventSource; token via query string porque no soporta headers)
- **Webhooks:** `POST /webhooks/alertmanager`, `POST /webhooks/payment-completed`

---

## Progreso real (post-auditoría)

| Bloque | Tickets | Estado |
|---|---|---|
| Wave 1 (P01, P06, P08, P09) | seguridad + Postgres ergonomics + RabbitMQ confirms + idempotencia | ✅ |
| Wave 2 (P02, P03, P04) | PIX 24/7, SPEI hours fix, Bre-B onboarding completo | ✅ |
| Wave 3 (P05) | FX cross-currency rules + rail-aware normalization | ✅ |
| **Wave 4 (P07, P11, P10, P12)** | Observabilidad unificada + UI fixes + testkit checksums + docs | ✅ |

Detalle: `AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md` + `mipit-docs/evidence/wave-*-validation.md`.

---

## Documentos de referencia

Ubicados en la carpeta `plans/` (fuera de los repos git) y `mipit-docs/`:

| Archivo | Descripción |
|---|---|
| `mipit-docs/openapi/openapi.yaml` | Contrato HTTP completo (25+ endpoints) |
| `mipit-docs/adrs/ADR-002-canonical-pacs008-json.md` | Subset pacs.008.001.10 implementado + limitaciones |
| `mipit-docs/demo-runbook/local-demo.md` | Procedimiento de demo local (docker compose) |
| `mipit-docs/demo-runbook/vm-demo.md` | Demo en VM1 + VM2 (IPs, puertos, credenciales) |
| `mipit-docs/LIMITATIONS.md` | Limitaciones explícitas del PoC (P12) |
| `AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md` | Auditoría forense de 5 agentes |

Documentos PDF en la raíz:
- `Diseno_MIPIT.pdf` — Documento de diseño del PoC
- `SRS_MIPIT.pdf` — Software Requirements Specification
- `SPMP.pdf` — Software Project Management Plan

---

## Comandos útiles

```bash
# mipit-core
npm install
npx jest --verbose
npx tsc --noEmit
npm start | npx pino-pretty

# mipit-infra
docker compose -f compose/docker-compose.yml up -d

# mipit-testkit (testkit canónico, con checksums válidos)
npm run generate:pix 50
npm run generate:spei 50
npm run generate:breb 50 RANDOM
npm run generate:batch 100        # 6 rail-pairs balanceados
npm run smoke                     # incluye PIX→SPEI, SPEI→BRE_B, BRE_B→PIX
npm run test:contract             # offline, sin stack
npm run validate:suite            # full E2E (necesita stack levantado)
```

---

## Notas importantes (post-auditoría)

- Los sandboxes oficiales de PIX (BCB DICT), SPEI (Banxico STP/CECOBAN) y Bre-B (BanRep) requieren licencia financiera. Usamos **mock servers propios** alineados con los esquemas reales.
- El `RouteEngine` infiere el rail destino del alias del creditor o del país (no se envía en el request salvo override).
- La API canónica es **`POST /payments`** (el diseño original decía `/transactions`).
- Auth obligatorio: todo endpoint bajo `/payments`, `/translate`, `/analytics`, `/compensate` requiere `Authorization: Bearer <JWT>`. `/auth/token` (dev) devuelve un token; en prod responde 404.
- Cache TTL de 5 minutos en `MappingLoader` y `RuleLoader`.
- Branch principal en todos los repos: `master` (no `main`).
- **Bre-B mobile-only:** `+57` keys deben ser teléfonos móviles colombianos (prefijo `3`), no fijos. BanRep TR-002.
- **PII redaction:** Pino tiene `redact` configurado; nunca loguear `debtor.name`, `creditor.taxId`, `headers.authorization`, ni equivalentes nativos por riel (`pagador.cpf`, `beneficiario.nombre`, `alias.value`, `chave`, `cuentaBeneficiario`, `llave`).
