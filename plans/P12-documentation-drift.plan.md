# P12 — Documentation & Drift Reconciliation

**Wave**: 4 (downstream — last)
**Repos afectados**: `mipit-docs`, `Tesis/` root (plans/, CONTEXTO-MIPIT.md), todos los repos (README/AGENTS)
**Branch**: `Auditoria-Claude`
**Estimación**: 2-3 días
**Riesgo**: Bajo (no toca código)

---

## 1. Objetivo

Reconciliar la documentación con la realidad post-P01..P11. Hoy:

- **OpenAPI** describe mundo de 2 rieles, 11 statuses, 202 response; reality 7 rails, 14 statuses, 201.
- **12 endpoints reales sin documentar**: `/translate*, /analytics/*, /services/*, /events/*, /compensate/*, /mocks/*, /auth/token`.
- **Mapping CSVs** describen flat snake_case canonical vs real nested camelCase.
- **0 CSVs para BRE_B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW**.
- **`route-rules/rules.yaml`** describe alias_type-based; real es prefix-based; sin Bre-B.
- **`architecture-overview.md, translation-layer.md`** omiten Bre-B.
- **`contracts/payment-status-machine.md`** 11 states cuando son 14.
- **`contracts/error-codes.md`** códigos genéricos cuando reality usa BACEN/CECOBAN/BREB reales.
- **`contracts/rabbitmq-messages.md`** queue names viejos.
- **`demo-runbook/*`**: IPs placeholder, queue names obsoletos, wording incorrecto.
- **`CONTEXTO-MIPIT.md`**: dice semana 8 cuando es semana 13-14, dice Vite cuando es Next.js 15, dice RabbitMQ 3.12+ cuando es 3.13.
- **`Propuesta.pdf` vs entrega**: FedNow prometido como evaluable, entregado como translator-only.
- **`SRS.pdf` RF19 (export CSV/JSON)**: no implementado.
- **`Diseno.pdf` §3.1.2**: menciona Spring Boot, drift con ADR-001.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| H1 | M | ADR-001 vs Diseño PDF Spring Boot drift |
| H3 | M | ADR-003 sin Bre-B; queue names viejos en contracts |
| H4 | H | `/auth/token` no en OpenAPI |
| H5 | H | ADR-008 trace_id propagation unmet en UI (P11 fija; P12 doc) |
| H6 | H | POST /payments retorna 201 not 202 in spec |
| H7 | H | `destination` enum [PIX, SPEI] |
| H8 | H | PaymentStatus 11 vs 14 |
| H9 | M | Idempotency-Key required vs optional |
| H10 | **C** | 12 endpoints sin documentar |
| H11 | M | Party.alias sin mencionar prefijos |
| H12 | M | `received_at` vs `created_at` field name |
| H13 | H | 4 CSVs describen flat canonical |
| H14 | H | 0 CSVs para 5 rails restantes |
| H15 | H | rules.yaml describe alias_type-based |
| H16 | M | architecture-overview sin Bre-B |
| H17 | H | translation-layer sin Bre-B |
| H18 | H | payment-status-machine 11 vs 14 |
| H19 | H | error-codes códigos genéricos |
| H20 | M | rabbitmq-messages queue names viejos |
| H21 | M | runbook idempotency wording |
| H22 | H | runbook VM IPs placeholder |
| H23 | M | runbook queue names |
| H24 | H | CONTEXTO-MIPIT semana 8 stale |
| H25 | H | CONTEXTO-MIPIT dice Vite |
| H26 | L | RabbitMQ 3.12+ vs 3.13 |
| H27 | L | "7-step pipeline" vs ~8 |
| H28 | M | Propuesta promete FedNow evaluable |
| H29 | H | SRS RF19 export no implementado |
| H30 | L | API Key vs JWT drift semántico |
| H32 | H | Diseño status enum 4 vs 14 |
| H33 | M | Diseño Spring Boot drift |
| H34 | M | SPMP H4 4 rieles vs 3 |
| H35 | H | fix_testkit.py en root |

---

## 3. Out of scope

- **NO** se regenera la sustentación de tesis ni el manuscrito.
- **NO** se traducen docs a inglés (mantiene es/pt mixed según file).

---

## 4. Dependencias

- **Depende de**: P01-P11 (los planes anteriores cambian código que estos docs describen).
- **Bloquea**: nada — última ola.

---

## 5. Tareas detalladas

### 5.1 OpenAPI rewrite

`mipit-docs/openapi/openapi.yaml`. Major rewrite (mantiene structure, actualiza content):

```yaml
openapi: 3.0.3
info:
  title: MiPIT — Middleware de Integración de Pagos Internacionales en Tiempo Real
  version: 0.2.0
  description: |
    PoC académico de interoperabilidad entre pasarelas de pagos instantáneos.

    **Modelo canónico**: pacs.008-derived (JSON subset pragmático, NO interoperable
    con sistemas ISO 20022 reales sin extensión). Ver ADR-002 en mipit-docs/adrs/.

    **Rails soportados**:
    - Option B (full mock + adapter): PIX (BR), SPEI (MX), Bre-B (CO)
    - Option A (translator only): SWIFT MT103, ISO 20022 MX, ACH NACHA, FedNow

    **Limitaciones conocidas**: ver `mipit-docs/LIMITATIONS.md`.

servers:
  - url: http://localhost:8080
    description: Local dev
  - url: https://10.43.101.28
    description: VM1 deploy

security:
  - bearerAuth: []

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    Rail:
      type: string
      enum: [PIX, SPEI, BRE_B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW]

    PaymentStatus:
      type: string
      enum:
        - RECEIVED
        - VALIDATED
        - CANONICALIZED
        - NORMALIZED
        - ROUTED
        - QUEUED
        - SENT_TO_DESTINATION
        - ACKED_BY_RAIL
        - COMPLETED
        - FAILED
        - REJECTED
        - DUPLICATE
        - COMPENSATING
        - COMPENSATED
        - DEAD_LETTER

    ChargeBearer:
      type: string
      enum: [DEBT, CRED, SHAR, SLEV]
      description: ISO 20022 ChrgBr code

    CreatePaymentRequest:
      type: object
      required: [amount, currency, debtor, creditor]
      properties:
        amount: { type: number, minimum: 0.01 }
        currency: { type: string, pattern: '^[A-Z]{3}$', example: BRL }
        debtor:
          $ref: '#/components/schemas/Party'
        creditor:
          $ref: '#/components/schemas/Party'
        purpose: { type: string, maxLength: 35, example: P2P }
        reference: { type: string, maxLength: 35 }
        chargeBearer:
          $ref: '#/components/schemas/ChargeBearer'

    Party:
      type: object
      required: [alias, name, country]
      properties:
        alias:
          type: string
          description: |
            Rail-specific alias with optional prefix:
            - PIX: `PIX-<chave>` where chave is CPF (11d) / CNPJ (14d) / email / +55phone / EVP uuid
            - SPEI: `SPEI-<clabe18>`
            - Bre-B: `BREB-<llave>` where llave is CC / CE / NIT / pasaporte / +57phone / email / @alias
          examples:
            pix_cpf: 'PIX-12345678909'
            spei_clabe: 'SPEI-072180000118359719'
            breb_phone: 'BREB-+573001234567'
        name: { type: string, maxLength: 140 }
        country: { type: string, pattern: '^[A-Z]{2}$' }
        taxId: { type: string }
        email: { type: string, format: email }
        phone: { type: string }
        address:
          type: array
          items: { type: string }

    PaymentReceipt:
      type: object
      required: [payment_id, status, created_at]
      properties:
        payment_id: { type: string, pattern: '^PMT-[A-Z0-9]{10,40}$' }
        status: { $ref: '#/components/schemas/PaymentStatus' }
        created_at: { type: string, format: date-time }
        trace_id: { type: string }

    PaymentDetail:
      allOf:
        - $ref: '#/components/schemas/PaymentReceipt'
        - type: object
          properties:
            origin_rail: { $ref: '#/components/schemas/Rail' }
            destination_rail: { $ref: '#/components/schemas/Rail' }
            amount: { type: number }
            currency: { type: string }
            debtor: { $ref: '#/components/schemas/Party' }
            creditor: { $ref: '#/components/schemas/Party' }
            uetr: { type: string, format: uuid, description: 'ISO 20022 UETR' }
            end_to_end_id: { type: string, maxLength: 35 }
            charge_bearer: { $ref: '#/components/schemas/ChargeBearer' }
            interbank_settlement_date: { type: string, format: date }
            instructed_amount: { type: number }
            instructed_currency: { type: string }
            settlement_amount: { type: number }
            settlement_currency: { type: string }
            exchange_rate: { type: number }
            timestamps:
              type: object
              properties:
                received_at: { type: string, format: date-time }
                validated_at: { type: string, format: date-time }
                canonicalized_at: { type: string, format: date-time }
                routed_at: { type: string, format: date-time }
                queued_at: { type: string, format: date-time }
                completed_at: { type: string, format: date-time }
                failed_at: { type: string, format: date-time }
                compensated_at: { type: string, format: date-time }
                dead_letter_at: { type: string, format: date-time }
            audit_events:
              type: array
              items: { $ref: '#/components/schemas/AuditEvent' }
            rail_ack: { type: object, description: 'pacs.002-derived ack' }

paths:
  /auth/token:
    get:
      summary: Get JWT token (non-production only)
      security: []
      responses:
        '200':
          description: Token issued
          content:
            application/json:
              schema:
                type: object
                properties:
                  token: { type: string }
                  expires_in: { type: integer }
        '404':
          description: Endpoint disabled in production

  /payments:
    post:
      summary: Create payment
      parameters:
        - in: header
          name: Idempotency-Key
          required: false
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CreatePaymentRequest' }
      responses:
        '201':
          description: Payment created
          content:
            application/json:
              schema: { $ref: '#/components/schemas/PaymentReceipt' }
        '200':
          description: Idempotent replay (cached response)
        '400':
          description: Validation error
        '409':
          description: Idempotency conflict (RFC 7807)
        '429':
          description: Rate limited (Retry-After header)

    get:
      summary: List recent payments
      parameters:
        - { in: query, name: status, schema: { $ref: '#/components/schemas/PaymentStatus' } }
        - { in: query, name: rail, schema: { $ref: '#/components/schemas/Rail' } }
        - { in: query, name: limit, schema: { type: integer, default: 50 } }
      responses:
        '200':
          description: List
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/PaymentDetail' }

  /payments/{paymentId}:
    get:
      summary: Get payment detail
      parameters:
        - { in: path, name: paymentId, required: true, schema: { type: string } }
      responses:
        '200':
          content:
            application/json:
              schema: { $ref: '#/components/schemas/PaymentDetail' }

  /translate:
    post:
      summary: Translate payload to canonical OR rail-specific output
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                source_rail: { $ref: '#/components/schemas/Rail' }
                destination_rail: { $ref: '#/components/schemas/Rail' }
                payload: { type: object }
      responses:
        '200':
          description: Translated
          content:
            application/json:
              schema:
                type: object
                properties:
                  canonical: { type: object }
                  translated: { type: object }

  /translate/preview:
    post:
      summary: Preview translation without persisting
      # ... similar to /translate ...

  /translate/rails:
    get:
      summary: List supported rails
      responses:
        '200':
          content:
            application/json:
              schema:
                type: array
                items: { $ref: '#/components/schemas/Rail' }

  /analytics/summary:
    get:
      summary: Aggregate payment stats
      responses:
        '200':
          content:
            application/json:
              schema:
                type: object
                properties:
                  total_payments: { type: integer }
                  success_rate: { type: number }
                  by_status: { type: object, additionalProperties: { type: integer } }
                  by_rail: { type: object, additionalProperties: { type: integer } }

  /analytics/latency:
    get: { /* p50/p95/p99 by stage */ }

  /analytics/circuit-breakers:
    get: { /* per-rail breaker state */ }

  /analytics/rate-limits:
    get: { /* per-rail bucket state */ }

  /analytics/reconciliation:
    get: { /* latest reconciliation reports */ }

  /services/{rail}/health:
    get:
      parameters:
        - { in: path, name: rail, required: true, schema: { $ref: '#/components/schemas/Rail' } }
      responses:
        '200': { /* health */ }
        '503': { /* degraded */ }

  /compensate/{paymentId}:
    post:
      summary: Compensate single payment (emit pacs.004)
      parameters:
        - { in: path, name: paymentId, required: true, schema: { type: string } }
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                reason: { type: string, enum: [duplicate, fraud, insufficient_funds, closed_account, invalid_account] }
      responses: { '200': { /* OK */ } }

  /compensate/batch:
    post:
      summary: Compensate multiple payments
      # ...

  /events/payments:
    get:
      summary: SSE stream of all payment events (requires ?token=JWT)
      parameters:
        - { in: query, name: token, required: true, schema: { type: string } }
      responses:
        '200':
          description: text/event-stream
          content:
            text/event-stream: {}

  /events/payments/{paymentId}:
    get:
      summary: SSE stream for single payment
      # ...

  /mocks/{rail}/admin/config:
    get: { /* get mock config */ }
    post: { /* set mock config; requires role admin */ }

  /mocks/{rail}/admin/reject-next:
    post: { /* force next request rejected; requires role admin */ }

  /mocks/{rail}/admin/timeout-next:
    post: { /* force next request to timeout */ }

  /mocks/{rail}/admin/reset:
    post: { /* reset mock stats */ }

  /mocks/{rail}/admin/stats:
    get: { /* counters */ }

  /mocks/{rail}/health:
    get: { /* mock health */ }

  /health:
    get:
      security: []
      summary: Health check (deep)
      responses:
        '200': { /* ok */ }
        '503': { /* degraded */ }

  /metrics:
    get:
      security: []
      summary: Prometheus metrics
      responses:
        '200':
          content:
            text/plain: {}
```

- [ ] Reescribir el archivo
- [ ] Validate con `openapi-cli validate openapi.yaml`
- [ ] Coord con P10 contract tests

### 5.2 Mapping CSVs regenerate

Para los 7 rails × 2 directions = 14 CSVs.

```bash
mipit-docs/mappings/
├── canonical-fields.md       # Master schema doc
├── pix-to-canonical.csv      # regenerated against pix-to-canonical.ts
├── canonical-to-pix.csv      # regenerated
├── spei-to-canonical.csv     # regenerated
├── canonical-to-spei.csv     # regenerated
├── breb-to-canonical.csv     # NEW
├── canonical-to-breb.csv     # NEW
├── swift-mt103-to-canonical.csv  # NEW
├── canonical-to-swift-mt103.csv  # NEW
├── iso20022-mx-to-canonical.csv  # NEW
├── canonical-to-iso20022-mx.csv  # NEW
├── ach-nacha-to-canonical.csv    # NEW
├── canonical-to-ach-nacha.csv    # NEW
├── fednow-to-canonical.csv       # NEW
└── canonical-to-fednow.csv       # NEW
```

CSV format:

```csv
Source field,Target field,Transformation,Validation rule,Notes
"alias.value (PIX-stripped)","chave","strip_prefix(PIX-)","chave_format_per_type","Chave is auto-classified into CPF/CNPJ/EMAIL/PHONE/EVP"
"amount.value","valor.original","number_to_2decimal_string","^\d+\.\d{2}$","BCB requires string format"
...
```

- [ ] Crear `scripts/generate-mappings.ts` que lee el código de translation y emite CSV
- [ ] OR manually write basados en `mipit-core/src/translation/<rail>-*.ts`
- [ ] **`canonical-fields.md`**: regenerar from Zod schema (P01 covers)

### 5.3 Route rules YAML

`mipit-docs/route-rules/rules.yaml`. Reemplazar con prefix-based + Bre-B:

```yaml
# MiPIT Routing Rules
# These rules are seeded into route_rules table at first DB init.
# The RouteEngine selects the highest-priority matching rule.

rules:
  # ===== Priority 1: explicit prefix match =====
  - name: pix_prefix
    priority: 1
    condition_field: 'creditor.alias_prefix'
    condition_value: 'PIX-'
    action: ROUTE
    destination_rail: PIX

  - name: spei_prefix
    priority: 1
    condition_field: 'creditor.alias_prefix'
    condition_value: 'SPEI-'
    action: ROUTE
    destination_rail: SPEI

  - name: breb_prefix
    priority: 1
    condition_field: 'creditor.alias_prefix'
    condition_value: 'BREB-'
    action: ROUTE
    destination_rail: BRE_B

  # ===== Priority 2: country-based fallback =====
  - name: country_br_to_pix
    priority: 2
    condition_field: 'creditor.country'
    condition_value: 'BR'
    action: ROUTE
    destination_rail: PIX

  - name: country_mx_to_spei
    priority: 2
    condition_field: 'creditor.country'
    condition_value: 'MX'
    action: ROUTE
    destination_rail: SPEI

  - name: country_co_to_breb
    priority: 2
    condition_field: 'creditor.country'
    condition_value: 'CO'
    action: ROUTE
    destination_rail: BRE_B

  # ===== Priority 3: heuristic =====
  - name: phone_co_to_breb
    priority: 3
    condition_field: 'creditor.alias.starts_with'
    condition_value: '+57'
    action: ROUTE
    destination_rail: BRE_B

  # ===== Fallback =====
  - name: fallback_unroutable
    priority: 99
    condition_field: '*'
    condition_value: '*'
    action: REJECT
    notes: 'No matching rail; payment cannot be routed.'
```

- [ ] Reescribir
- [ ] Match exactly el seed SQL en `mipit-infra/db/init/002_seed_route_rules.sql`

### 5.4 Architecture overview con Bre-B

`mipit-docs/design/architecture-overview.md:14-36`:

```
┌──────────────┐     HTTPS/REST      ┌──────────────────────────────────────────────────┐
│   mipit-ui   │ ◄──────────────────► │                  mipit-core                      │
└──────────────┘                      │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
                                      │  │ Validator │→│Translator│→│ Routing Engine   │  │
                                      │  └──────────┘ └──────────┘ └──────────────────┘  │
                                      │        ↓             ↓              ↓             │
                                      │  ┌───────────────────────────────────────────┐   │
                                      │  │          State Machine + Postgres         │   │
                                      │  │              + Outbox + Audit             │   │
                                      │  └───────────────────────────────────────────┘   │
                                      └────────────────────┬───────────────────────────┘
                                                           │ RabbitMQ topic exchange
                                       ┌──────────────────┼──────────────────┐
                                       ▼                  ▼                  ▼
                            ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
                            │ mipit-adapter-pix │ │mipit-adapter-spei│ │mipit-adapter-breb│
                            │   (Worker)        │ │   (Worker)        │ │   (Worker)        │
                            └────────┬─────────┘ └────────┬──────────┘ └────────┬──────────┘
                                     ▼                    ▼                     ▼
                              PIX SPI Mock        SPEI/STP Mock          Bre-B SPI Mock
                              (BACEN sim)         (Banxico sim)          (BanRep sim)
```

- [ ] Update diagrama
- [ ] Sección "Rails" lista los 7 (3 Option-B, 4 Option-A translator-only)
- [ ] Sección "Limitaciones" lista las acknowledged limitations (link a LIMITATIONS.md)

### 5.5 translation-layer.md

`mipit-docs/design/translation-layer.md`. Cambios:

- [ ] Listar Bre-B explícitamente
- [ ] Actualizar shape canonical a nested camelCase (post-P01)
- [ ] Sección "Mock fidelity matrix" con scores 2.5/5 PIX, 1.5/5 SPEI, 1.0/5 Bre-B + targets post-P02/P03/P04

### 5.6 payment-status-machine.md 14 states

`mipit-docs/contracts/payment-status-machine.md`. Actualizar:

```markdown
# Payment Status Machine

States and transitions:

| Status | Description |
|---|---|
| RECEIVED | Initial state on POST /payments |
| VALIDATED | Zod schema passed |
| CANONICALIZED | Translated to canonical (pacs.008-derived) |
| NORMALIZED | Currency uppercase, FX applied, IDs normalized |
| ROUTED | RouteEngine determined destination_rail |
| QUEUED | Message published to RabbitMQ route queue |
| SENT_TO_DESTINATION | Adapter began processing (not currently emitted) |
| ACKED_BY_RAIL | Adapter received ACK from rail mock |
| COMPLETED | Terminal — ACCEPTED rail status |
| REJECTED | Terminal — rail returned REJECTED |
| FAILED | Terminal — internal pipeline error |
| DUPLICATE | Duplicate detected via idempotency or DLQ |
| COMPENSATING | Compensation flow in progress (pacs.004 emitted) |
| COMPENSATED | Compensation complete |
| DEAD_LETTER | Message moved to DLQ |

Transitions:

RECEIVED → VALIDATED (Zod ok)
RECEIVED → FAILED (Zod failed)
VALIDATED → CANONICALIZED (translator ok)
CANONICALIZED → NORMALIZED (normalizer ok)
NORMALIZED → ROUTED (RouteEngine matched)
ROUTED → QUEUED (publisher confirms)
QUEUED → ACKED_BY_RAIL (consumer received ack)
ACKED_BY_RAIL → COMPLETED | REJECTED | FAILED (per ack txSts)
* → DEAD_LETTER (DLQ handler)
DEAD_LETTER | FAILED | QUEUED → COMPENSATING (compensate endpoint)
COMPENSATING → COMPENSATED
```

### 5.7 error-codes.md real

`mipit-docs/contracts/error-codes.md`. Reemplazar genéricos con códigos reales:

```markdown
# Error Codes Per Rail

## PIX (BACEN Manual de Padrões)

| Code | Description | Mock-triggered? |
|---|---|---|
| AM01 | Saldo insuficiente | yes (random) |
| AM02 | Limite excedido | yes |
| AM04 | Sem fundos disponíveis | yes (most common) |
| AC01 | Conta credora não existe | yes |
| AC03 | Conta credora inválida (DICT) | yes |
| AB03 | Pagador não admitido | yes |
| BE01 | Beneficiário inconsistente | yes |
| DS04 | Disputa pelo recebedor | yes |
| RR04 | Recebedor recusou | yes |

## SPEI (Banxico/CECOBAN)

| Code | Description |
|---|---|
| R01 | CLABE destino incorrecta |
| R02 | Cuenta destino bloqueada |
| R03 | Datos incompletos |
| R04 | Beneficiario erróneo |
| R05 | claveRastreo duplicada |
| R08 | Error general |
| LIM | Excede límite session |

## Bre-B (BanRep — invented for PoC)

> **NOTE**: Los códigos `BREB001-BREB005` son invented for this PoC. BanRep
> no ha publicado catálogo de error codes para Bre-B. Documentar como
> "placeholder pending BanRep specification publication".

| Code | Description |
|---|---|
| BREB001 | Fondos insuficientes |
| BREB002 | Límite excedido |
| BREB003 | Receptor no registrado en Bre-B |
| BREB004 | Llave inválida |
| BREB005 | Bre-B no disponible |
```

### 5.8 rabbitmq-messages.md queue names

`mipit-docs/contracts/rabbitmq-messages.md`. Actualizar:

```markdown
# RabbitMQ Topology

## Exchanges
- `mipit.payments` (topic, durable) — main routing
- `mipit.dlx` (topic, durable) — dead-letter exchange
- `mipit.unrouted` (fanout, durable) — alternate-exchange for unbound routing keys

## Queues (all quorum, durable)

| Queue | Bound to | Routing key | DLX | TTL |
|---|---|---|---|---|
| `payments.route.pix` | mipit.payments | `route.pix` | dlq.pix | 1h |
| `payments.route.spei` | mipit.payments | `route.spei` | dlq.spei | 1h |
| `payments.route.breb` | mipit.payments | `route.breb` | dlq.breb | 1h |
| `payments.ack` | mipit.payments | `ack.#` | dlq.ack | 1h |
| `dlq.pix` | mipit.dlx | `dlq.pix` | — | — |
| `dlq.spei` | mipit.dlx | `dlq.spei` | — | — |
| `dlq.breb` | mipit.dlx | `dlq.breb` | — | — |
| `dlq.ack` | mipit.dlx | `dlq.ack` | — | — |
| `unrouted` | mipit.unrouted | `*` | — | — |

## Message shapes

### Outbound (route.<rail>)
```json
{
  "payment_id": "PMT-...",
  "canonical": { /* pacs.008-derived; see canonical-fields.md */ },
  "trace_id": "...",
  "uetr": "uuid-v4"
}
```

### Inbound ACK (ack.<rail>)
```json
{
  "payment_id": "PMT-...",
  "uetr": "uuid-v4",
  "rail_tx_id": "...",
  "txSts": "ACSC" | "RJCT" | "PART" | "PDNG",
  "stsRsnInf": { "rsn": { "cd": "AM04" } } /* if RJCT */,
  "rail_response": { /* raw rail response */ },
  "processed_at": "iso8601"
}
```

## AMQP headers (W3C TraceContext)
- `traceparent` — injected by publisher, consumed by adapter
- `tracestate` — vendor-specific trace state
- `mipit-uetr` — convenience header for UETR
```

### 5.9 Demo runbook update

`mipit-docs/demo-runbook/local-demo.md`:

- [ ] Reemplazar nombre cola `q.adapter.pix` → `payments.route.pix`
- [ ] Idempotency wording: "el estado del segundo POST muestra el mismo payment_id que el primero; el response es cached" (no "estado DUPLICATE")
- [ ] Update endpoint examples con paths reales

`mipit-docs/demo-runbook/vm-demo.md`:

- [ ] VM IPs reales: `10.43.101.28` (VM1) y `10.43.101.29` (VM2)
- [ ] Queue names actuales

`mipit-docs/demo-runbook/checklist-pre-demo.md`:

- [ ] Update queue names

### 5.10 ADRs update

`mipit-docs/adrs/ADR-003-rabbitmq-async-messaging.md`:

- [ ] Agregar Bre-B en la sección rails
- [ ] Reflect quorum queues + DLX en payments.ack
- [ ] Queue names actualizados (`payments.route.*`)

`mipit-docs/adrs/ADR-008-observability-otel-prometheus.md`:

- [ ] Agregar sección "Implementación post-P07": OTel collector deployed, UI muestra trace_id, AlertManager presente

`mipit-docs/adrs/ADR-002-canonical-pacs008-json.md`:

- [ ] Cubierto en P01 — sección Limitations agregada

### 5.11 LIMITATIONS.md master

`mipit-docs/LIMITATIONS.md` (nuevo):

```markdown
# MiPIT — Limitaciones Documentadas del PoC

Este documento enumera explícitamente las brechas conocidas entre el PoC y
una implementación de producción. Es referencia para defensa académica y
para futuros maintainers.

## 1. Canónico ISO 20022

- Modelo es "pacs.008-derived", **NO** pacs.008.001.10 estricto.
- Implementa: GrpHdr.{MsgId, CreDtTm, NbOfTxs, SttlmInf.SttlmMtd}; CdtTrfTxInf.PmtId.{InstrId, EndToEndId, TxId, UETR}; IntrBkSttlmAmt + IntrBkSttlmDt; ChrgBr; Dbtr/Cdtr.{Nm, PstlAdr.{Ctry, AdrLine}, Id (taxId), CtctDtls.{EmailAdr, PhneNb}}; DbtrAcct/CdtrAcct.Id; DbtrAgt/CdtrAgt.BICFI; Purp; RmtInf.Ustrd.
- NO implementa: CtrlSum, TtlIntrBkSttlmAmt, BtchBookg, InitgPty, InstgAgt, InstdAgt, SttlmInf.{SttlmAcct, ClrSys.Cd (hard-coded por rail), InstgRmbrsmntAgt, InstdRmbrsmntAgt}; PmtTpInf.{InstrPrty, ClrChanl, SvcLvl.Cd, LclInstrm.Prtry, CtgyPurp}; SttlmPrty, SttlmTmIndctn, SttlmTmReq, AccptncDtTm, PoolgAdjstmntDt; ChrgsInf, PrvsInstgAgt1-3, IntrmyAgt1-3, UltmtDbtr, UltmtCdtr; InstrForCdtrAgt, InstrForNxtAgt, RgltryRptg, Tax, RltdRmtInf, SplmtryData; Dbtr/Cdtr.{Id.PrvtId/OrgId structured, CtryOfRes}; PstlAdr structured fields (Dept, SubDept, StrtNm, etc.); RmtInf.Strd; XML serialization (output is JSON object, not XML); XSD validation.

## 2. PIX (BACEN)

- Endpoint mock `POST /spi/v2/pagamentos` es **invented**. Real BCB exposes `/v2/cob/{txid}`, `/v2/cobv/{txid}`, `/v2/pix/{e2eid}` (PSP-side) y SPI internal es XML/RSFN (no REST).
- OAuth2 mock sin **mTLS + ICP-Brasil cert** (real requiere ambos).
- DICT consultation (`GET /v2/dict/{key}`) no implementada.
- BR Code `pixCopiaECola` con CRC-16/CCITT-FALSE no generado.
- Devoluções no soportadas (sin endpoint `/v2/pix/{e2eid}/devolucao`).
- ISPB simulado `26264220` no registrado con BACEN STR.

## 3. SPEI (Banxico/STP)

- Endpoint mock `POST /spei/v3/transferencias` es **invented**. Real STP es SOAP en `:7024/speiws/rest/...`.
- Auth mock OAuth2 — real STP usa **RSA-PKCS#1 v1.5 SHA-256 firma** sobre canonical pipe-joined string (no OAuth2 en absoluto).
- Catálogo `tipoPago` parcial (12 valores vs 31 real).
- Devoluciones tipo 8/12 no implementadas.

## 4. Bre-B (BanRep)

- BanRep **no ha publicado** spec wire-format pública. Todo el wire format del adapter Bre-B es **invented for this PoC**. Field names, error codes BREB001-005, OAuth flow, idTransaccion format — todos son educated guesses NOT verified against BanRep documentation.
- Directorio Bre-B (análogo DICT) no simulado.
- Subset de llave types soportado: CC, CE, NIT, PASAPORTE, TELEFONO (+57 3xx móvil), EMAIL, ALIAS (@-prefix).

## 5. Cross-border / FX

- FX rates de **una sola fuente** (openexchangerates.org free tier) + static fallback.
- Multi-leg conversion via USD pivot (no triangular arbitrage).
- No hedging / lock-in rate.

## 6. Reliability

- Single broker, single DB (no HA cluster).
- Quorum queues configured pero en single-broker no aplican replication real.
- Reconnect tested; outbox tested; multi-replica deployment no probado.

## 7. Security

- JWT HS256 con secret compartido (no asymmetric).
- Self-signed TLS certs (no public CA).
- Adapter admin endpoints behind `X-Admin-Token` (no OIDC / mTLS).
- No HSM / KMS para secret management.
- Single `admin` role (no RBAC fine-grained).

## 8. Compliance

- Sin AML/KYC checks.
- Sin sanctions screening.
- Sin transaction monitoring para fraud detection.
- No retention/deletion policy de PII (GDPR/LGPD aware-only).

## 9. Operations

- Backups no automated.
- Restore procedure no tested.
- Capacity planning no executed (load test es sintético).
- Runbook coverage parcial (algunos errores no documented).
```

- [ ] Crear archivo
- [ ] Cross-reference desde OpenAPI, ADRs, READMEs

### 5.12 CONTEXTO-MIPIT.md update

`C:\Users\nicog\Documents\Tesis\CONTEXTO-MIPIT.md`. Rewrite completo:

- [ ] Status: "Semanas 5-13 completadas. Auditoría Claude 2026-05-16 ejecutada (12 planes de remediación)."
- [ ] mipit-ui: Next.js 15 / React 19 / Radix / Tailwind 4 (no Vite)
- [ ] RabbitMQ 3.13
- [ ] Pipeline ~8 steps (no 7)
- [ ] Add Bre-B en la architecture diagram
- [ ] Add `Auditoria-Claude` branch info en la sección Branches

### 5.13 plans/ index

`C:\Users\nicog\Documents\Tesis\plans\README.md` (nuevo, cubierto en next step).

### 5.14 SRS RF19 export — implementar OR documentar gap

**Decisión**: Implementar minimal CSV/JSON export en UI.

`mipit-ui/src/app/history/page.tsx`:

```tsx
<button onClick={() => exportPayments('csv')}>Export CSV</button>
<button onClick={() => exportPayments('json')}>Export JSON</button>
```

`mipit-core/src/api/routes/payments.ts`:

```ts
app.get('/payments/export', { preHandler: requireAuth }, async (req, reply) => {
  const format = req.query.format ?? 'csv';
  const payments = await paymentRepo.findRecent(req.query);
  if (format === 'json') {
    reply.header('Content-Disposition', 'attachment; filename=payments.json');
    return payments;
  }
  if (format === 'csv') {
    reply.header('Content-Type', 'text/csv');
    reply.header('Content-Disposition', 'attachment; filename=payments.csv');
    return paymentsToCSV(payments);
  }
});
```

- [ ] Implementar
- [ ] Marca RF19 ✓ en SRS table

### 5.15 Move `fix_testkit.py`

```bash
mv fix_testkit.py mipit-testkit/scripts/legacy/fix-testkit-for-vm.py
```

- [ ] Coord P10

### 5.16 ADR-009 (nuevo) — auditoría

`mipit-docs/adrs/ADR-009-audit-remediation.md`:

```markdown
# ADR-009: Auditoría externa + remediation plan

**Status**: Accepted
**Date**: 2026-05-16
**Authors**: Nicolás (coord. con auditoría Claude)

## Context

Auditoría profunda (5 agentes paralelos) ejecutada el 2026-05-16 sobre los 9 repos. Resultado: ~195 hallazgos (25 críticos, 50 altos, 80 medios, 40 bajos).

Reportes raw en `AUDIT-RAW-{translation,adapters,ui-docs}.md`. Índice en `AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md`.

## Decision

Ejecutar 12 planes de remediación en 4 olas (`plans/P01..P12.plan.md`). Cada plan tiene:
- Findings cerrados
- Tareas detalladas con file:line
- Acceptance criteria
- Testing plan
- Commits sugeridos

## Consequences

- Branch `Auditoria-Claude` en los 9 repos para desacoplar.
- Sección "Limitations" explícita en docs (LIMITATIONS.md).
- 0 critical / 0 high npm vulns (P08).
- Mocks documentados como "invented endpoints, not byte-fidelity to real APIs".
- Tesis defensible con honestidad académica.
```

---

## 6. Acceptance criteria

- [ ] OpenAPI describe los 7 rails, 14 statuses, 201 response, los 25+ endpoints reales
- [ ] OpenAPI valida con `openapi-cli validate`
- [ ] 14 CSVs en `mipit-docs/mappings/` (7 rails × 2 directions)
- [ ] `canonical-fields.md` regenerado contra Zod schema actual
- [ ] `route-rules/rules.yaml` matchea seed SQL real
- [ ] `architecture-overview.md` y `translation-layer.md` incluyen Bre-B
- [ ] `payment-status-machine.md` 14 estados con transiciones
- [ ] `error-codes.md` con BACEN/CECOBAN reales + Bre-B "invented for PoC"
- [ ] `rabbitmq-messages.md` queue names actualizados, quorum, DLX, headers W3C
- [ ] `demo-runbook/*` actualizados
- [ ] ADR-003, ADR-008 actualizados; ADR-009 creado
- [ ] `LIMITATIONS.md` master existe
- [ ] `CONTEXTO-MIPIT.md` reescrito al estado real
- [ ] `plans/README.md` index existe
- [ ] RF19 export implementado en UI
- [ ] `fix_testkit.py` archivado en `mipit-testkit/scripts/legacy/`

---

## 7. Testing plan

- Validate OpenAPI: `npx @apidevtools/swagger-cli validate openapi.yaml`
- Manual: read each updated doc, verify no anachronistic claims
- Cross-check: `grep -r "Vite\|Spring Boot\|RabbitMQ 3.12\|q.adapter" mipit-docs/` returns 0 results (or only intentional history refs)

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Doc updates lag implementation | P12 corre **última** en Wave 4 |
| OpenAPI YAML invalid | Validate antes de commit |
| Markdown links broken | Run linkcheck (`markdown-link-check`) |

---

## 9. Commits sugeridos

1. `docs(openapi): rewrite for 7 rails, 14 statuses, 25+ endpoints`
2. `docs(mappings): regenerate CSVs for all 7 rails (14 files)`
3. `docs(mappings): regenerate canonical-fields.md from Zod schema`
4. `docs(route-rules): rules.yaml prefix-based + Bre-B`
5. `docs(design): architecture-overview includes Bre-B diagram`
6. `docs(design): translation-layer includes Bre-B section`
7. `docs(contracts): payment-status-machine 14 states with full transition table`
8. `docs(contracts): error-codes real BACEN/CECOBAN + Bre-B invented disclaimer`
9. `docs(contracts): rabbitmq-messages queue names actualizados + quorum + W3C headers`
10. `docs(demo-runbook): update queue names, VM IPs, idempotency wording`
11. `docs(adrs): update ADR-003 with Bre-B + quorum`
12. `docs(adrs): update ADR-008 with collector deployed + UI trace link`
13. `docs(adrs): new ADR-009 — audit remediation plan`
14. `docs: LIMITATIONS.md master document`
15. `docs: rewrite CONTEXTO-MIPIT.md to current state (semana 13-14, Next.js 15, etc.)`
16. `feat(export): RF19 CSV/JSON export endpoint + UI buttons`
17. `chore: move fix_testkit.py to mipit-testkit/scripts/legacy/`
18. `docs(plans): README index of P01-P12 plans`

---

## 10. Notas para el dev

- **OpenAPI**: si gente externa va a integrarse, este es el contrato. Vale la pena el tiempo invertido.
- **LIMITATIONS.md** es probablemente el doc más alto-ROI de toda la auditoría — un panel que lo lee, ve que **sabés** dónde están las brechas. Eso es lo que un examiner quiere ver.
- **`fix_testkit.py` legacy**: no borrar — útil como referencia histórica de la migration VM.
- **CONTEXTO-MIPIT.md**: este archivo está en el root, no en mipit-docs. Lo abrirá cualquier nueva sesión de Cursor — actualizar primero.
