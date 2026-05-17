# Plan: mipit-docs

> **Repo GitHub**: https://github.com/MIPIT-PoC/mipit-docs
> **Propósito**: Fuente de verdad documental — SRS, diseño, ADRs, OpenAPI, tablas de mapeo, reglas de ruteo, runbooks de demo y evidencias.
> **Posición en el flujo**: Transversal. Fija contratos y decisiones para que core/adaptadores/UI no diverjan.

---

## 1. Estructura de carpetas

```
mipit-docs/
├── README.md
├── .gitignore
├── srs/
│   └── SRS_MIPIT.pdf                # Copia versionada del SRS
├── spmp/
│   └── SPMP.pdf                     # Copia versionada del SPMP
├── propuesta/
│   └── propuesta.pdf                # Propuesta del proyecto
├── design/
│   ├── design-inputs.pdf            # Documento de diseño (insumos)
│   ├── architecture-overview.md     # Resumen de la arquitectura (texto)
│   └── diagrams/
│       ├── high-level-architecture.png
│       ├── sequence-pix-to-spei.png
│       ├── sequence-spei-to-pix.png
│       ├── component-diagram.png
│       └── deployment-diagram.png
├── openapi/
│   └── openapi.yaml                 # Contrato OpenAPI 3.1 (fuente de verdad)
├── adrs/
│   ├── README.md                    # Índice de ADRs
│   ├── ADR-001-stack-typescript-node.md
│   ├── ADR-002-canonical-pacs008-json.md
│   ├── ADR-003-rabbitmq-async-messaging.md
│   ├── ADR-004-idempotency-header.md
│   ├── ADR-005-security-poc-jwt-https.md
│   ├── ADR-006-postgres-persistence.md
│   ├── ADR-007-hybrid-modular-architecture.md
│   └── ADR-008-observability-otel-prometheus.md
├── contracts/
│   ├── rabbitmq-messages.md         # Schema de mensajes RabbitMQ
│   ├── payment-status-machine.md    # Máquina de estados PaymentStatus
│   └── error-codes.md              # Catálogo de códigos de error
├── mappings/
│   ├── pix-to-canonical.csv
│   ├── canonical-to-pix.csv
│   ├── spei-to-canonical.csv
│   ├── canonical-to-spei.csv
│   └── canonical-fields.md          # Lista de campos canónicos con reglas
├── route-rules/
│   ├── rules.yaml                   # Reglas en formato procesable
│   └── examples.md                 # Ejemplos de enrutamiento
├── demo-runbook/
│   ├── local-demo.md               # Pasos para demo local completa
│   ├── vm-demo.md                  # Pasos para demo en VMs
│   └── checklist-pre-demo.md       # Checklist antes de presentar
└── evidence/
    ├── dashboards/                  # Capturas de Grafana
    ├── traces/                      # Capturas de Jaeger
    ├── logs/                        # Ejemplos de logs JSON
    └── test-results/                # Reportes de test
```

---

## 2. Archivos clave — contenido

### 2.1 ADR Template (`adrs/ADR-001-stack-typescript-node.md`)

```markdown
# ADR-001: Stack tecnológico — TypeScript + Node.js

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

Se necesita elegir el lenguaje y runtime para el backend del PoC (core + adaptadores).
El equipo tiene experiencia en TypeScript/JavaScript y el proyecto requiere prototipado rápido.

## Decisión

Usar **TypeScript sobre Node.js 22** con **Fastify** como framework HTTP para el core
y workers nativos de Node.js para los adaptadores.

## Alternativas consideradas

| Alternativa       | Pros                              | Contras                          |
|-------------------|-----------------------------------|----------------------------------|
| Java + Spring Boot| Ecosistema enterprise, tipado     | Verbose, setup pesado para PoC   |
| Go                | Performance, binarios ligeros     | Menos ecosistema ISO/financiero  |
| Python + FastAPI  | Rápido de prototipar              | Tipado dinámico, menos robusto   |
| **TypeScript + Node** | Fullstack unificado, tipado, rápido | Single-threaded (no aplica en PoC) |

## Razones

- Stack unificado (backend + frontend ambos TypeScript)
- Ecosistema npm rico para HTTP, messaging, observabilidad
- Tipado estricto con Zod para validación runtime
- Fastify ofrece buen rendimiento y plugin ecosystem
- Suficiente para el volumen del PoC (100 tx por sesión)

## Consecuencias

- Todo el equipo debe manejar TypeScript
- Se limitan opciones de concurrencia real (pero no es requerimiento del PoC)
- Las dependencias deben mantenerse actualizadas
```

### 2.2 `adrs/ADR-002-canonical-pacs008-json.md`

```markdown
# ADR-002: Modelo canónico basado en pacs.008 (JSON)

**Estado**: Aceptado
**Fecha**: 2026-03-01

## Contexto

Se necesita una "lengua franca" para representar instrucciones de crédito
entre rieles heterogéneos (PIX y SPEI).

## Decisión

Usar **pacs.008 (Customer Credit Transfer)** como base del modelo canónico,
representado en **JSON interno** (no XML ISO literal), pero alineado
semánticamente a la estructura de pacs.008.

Para respuestas/confirmaciones del riel destino, se define un modelo
**inspirado en pacs.002 (Status Report)**.

## Razones

- pacs.008 encaja naturalmente con "transferencia de crédito entre rieles"
- JSON es más ergonómico que XML para el PoC y la UI
- La alineación semántica permite documentar el mapeo ISO 20022
- pacs.002-like permite representar ACCEPTED/REJECTED del riel

## Consecuencias

- No se valida contra XSD ISO 20022 real (solo subset)
- El modelo canónico es propio del middleware (no interoperable con sistemas ISO reales)
- Se documenta como limitación aceptada del PoC
```

### 2.3 `contracts/payment-status-machine.md`

```markdown
# Máquina de Estados — PaymentStatus

## Estados

| Estado               | Descripción                                          |
|----------------------|------------------------------------------------------|
| RECEIVED             | API aceptó la solicitud                              |
| VALIDATED            | Payload validado (formato, campos obligatorios)       |
| CANONICALIZED        | Mensaje canónico pacs.008 generado                   |
| ROUTED               | Destino decidido por motor de reglas                 |
| QUEUED               | Mensaje publicado a RabbitMQ                         |
| SENT_TO_DESTINATION  | Adaptador envió al sandbox/mock                      |
| ACKED_BY_RAIL        | Respuesta del riel recibida                          |
| COMPLETED            | Flujo exitoso finalizado                             |
| FAILED               | Fallo no recuperable                                 |
| REJECTED             | Riel rechazó la transacción                          |
| DUPLICATE            | Idempotencia detectó duplicado                       |

## Transiciones válidas

```
RECEIVED → VALIDATED → CANONICALIZED → ROUTED → QUEUED → SENT_TO_DESTINATION → ACKED_BY_RAIL → COMPLETED
                                                                                            → REJECTED
RECEIVED → DUPLICATE (idempotencia)
* → FAILED (cualquier etapa puede fallar)
```

## Reglas

- Solo el **core** puede transicionar estados
- Los **adaptadores** reportan vía ack message, el core decide estado final
- **FAILED** es terminal — no se reintenta desde core (el adaptador ya agotó reintentos)
- **DUPLICATE** es terminal — se devuelve la respuesta cacheada
```

### 2.4 `contracts/rabbitmq-messages.md`

```markdown
# Contratos de Mensajes RabbitMQ

## Exchange: `mipit.payments` (topic)

### Core → Adaptador: `route.{pix|spei}`

```json
{
  "payment_id": "PMT-01HPX9Y3Q9K1Z8G7V2",
  "trace_id": "01HPX9Y3Q9K1Z8G7V3",
  "canonical": { /* CanonicalPacs008 completo */ },
  "destination_rail": "SPEI",
  "route_rule_applied": "clabe_to_spei",
  "routed_at": "2026-03-01T15:22:10.000Z"
}
```

### Adaptador → Core: `ack.{pix|spei}`

```json
{
  "payment_id": "PMT-01HPX9Y3Q9K1Z8G7V2",
  "trace_id": "01HPX9Y3Q9K1Z8G7V3",
  "source_rail": "SPEI",
  "adapter_id": "adapter-spei",
  "instance_id": "spei-12345",
  "status": "ACKED_BY_RAIL",
  "rail_ack": {
    "rail_tx_id": "SPEI-01HPX9Y3Q9K1Z8G7V4",
    "status": "ACCEPTED",
    "error": null,
    "raw_response": {}
  },
  "latency_ms": 342,
  "processed_at": "2026-03-01T15:22:10.342Z"
}
```

## Exchange: `mipit.dlx` (Dead Letter)

Mensajes que fallan después de agotar reintentos van a `dlq.pix` o `dlq.spei`.
Mismo formato que el mensaje original.
```

### 2.5 `contracts/error-codes.md`

```markdown
# Catálogo de Códigos de Error

| Code                    | HTTP | Descripción                                    |
|-------------------------|------|------------------------------------------------|
| VALIDATION_ERROR        | 400  | Payload inválido (campos, formato)             |
| UNAUTHORIZED            | 401  | JWT inválido o ausente                         |
| FORBIDDEN               | 403  | Token válido pero sin permisos                 |
| NOT_FOUND               | 404  | payment_id no existe                           |
| IDEMPOTENCY_CONFLICT    | 409  | Idempotency-Key con payload diferente          |
| UNPROCESSABLE_ENTITY    | 422  | Datos hard-required no resolubles              |
| RATE_LIMITED             | 429  | Demasiadas solicitudes (opcional)              |
| INTERNAL_ERROR          | 500  | Error interno no esperado                      |
| RAIL_UNAVAILABLE        | 502  | Adaptador/sandbox no disponible                |
| RAIL_TIMEOUT            | 504  | Sandbox no respondió en tiempo                 |
| TRANSLATION_ERROR       | 500  | Error en traducción canónica                   |
| ROUTING_ERROR           | 500  | Error en motor de enrutamiento                 |
| ADAPTER_ERROR           | 500  | Error genérico del adaptador                   |
| PIX_INSUFFICIENT_FUNDS  | —    | Error específico PIX (en rail_ack.error.code)  |
| PIX_INVALID_KEY         | —    | Error específico PIX                           |
| SPEI_INVALID_CLABE      | —    | Error específico SPEI                          |
| SPEI_TIMEOUT            | —    | Error específico SPEI                          |
```

### 2.6 `openapi/openapi.yaml` (resumido)

```yaml
openapi: 3.1.0
info:
  title: MiPIT — API Unificada
  version: 0.1.0
  description: API del middleware de interoperabilidad para pagos instantáneos transfronterizos

servers:
  - url: https://mipit.local/api
    description: Local (via Nginx)
  - url: http://localhost:8080
    description: Direct core

security:
  - bearerAuth: []

paths:
  /payments:
    post:
      summary: Crear una transacción simulada
      operationId: createPayment
      parameters:
        - name: Idempotency-Key
          in: header
          schema: { type: string, format: uuid }
        - name: X-Trace-ID
          in: header
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CreatePaymentRequest' }
      responses:
        '202':
          description: Payment accepted for processing
          content:
            application/json:
              schema: { $ref: '#/components/schemas/PaymentSummary' }
        '400': { description: Validation error }
        '409': { description: Idempotency conflict }

  /payments/{payment_id}:
    get:
      summary: Consultar estado y detalle de una transacción
      operationId: getPayment
      parameters:
        - name: payment_id
          in: path
          required: true
          schema: { type: string }
      responses:
        '200':
          description: Payment detail
          content:
            application/json:
              schema: { $ref: '#/components/schemas/PaymentDetail' }
        '404': { description: Payment not found }

  /health:
    get:
      summary: Health check
      security: []
      responses:
        '200':
          description: Service healthy

  /metrics:
    get:
      summary: Prometheus metrics
      security: []
      responses:
        '200':
          description: Prometheus text metrics

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    CreatePaymentRequest:
      type: object
      required: [amount, debtor, creditor]
      properties:
        amount: { type: number, minimum: 0.01 }
        currency: { type: string, default: USD, minLength: 3, maxLength: 3 }
        debtor:
          type: object
          required: [alias]
          properties:
            alias: { type: string }
            name: { type: string, maxLength: 140 }
        creditor:
          type: object
          required: [alias]
          properties:
            alias: { type: string }
            name: { type: string, maxLength: 140 }
        purpose: { type: string, maxLength: 35, default: P2P }
        reference: { type: string, maxLength: 140, default: MIPIT-POC }

    PaymentSummary:
      type: object
      properties:
        payment_id: { type: string }
        status: { type: string }
        received_at: { type: string, format: date-time }
        destination: { type: string, enum: [PIX, SPEI] }

    PaymentDetail:
      type: object
      properties:
        payment_id: { type: string }
        status: { $ref: '#/components/schemas/PaymentStatus' }
        origin: { type: string }
        destination: { type: string }
        amount: { type: number }
        currency: { type: string }
        original: { type: object }
        canonical: { type: object }
        translated: { type: object }
        rail_ack: { type: object, nullable: true }
        timestamps: { type: object }

    PaymentStatus:
      type: string
      enum:
        - RECEIVED
        - VALIDATED
        - CANONICALIZED
        - ROUTED
        - QUEUED
        - SENT_TO_DESTINATION
        - ACKED_BY_RAIL
        - COMPLETED
        - FAILED
        - REJECTED
        - DUPLICATE
```

### 2.7 `demo-runbook/local-demo.md`

```markdown
# Runbook: Demo Local Completa

## Pre-requisitos
- Docker Engine 26+ y Docker Compose instalados
- Repos clonados: mipit-infra, mipit-core, mipit-adapter-pix, mipit-adapter-spei, mipit-ui, mipit-observability
- Todos al mismo nivel de directorio

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

### 3. Abrir UIs
- **MiPIT UI**: https://localhost
- **Grafana**: http://localhost:3000 (admin/mipit2026)
- **RabbitMQ**: http://localhost:15672 (mipit/mipit_secret)
- **Jaeger**: http://localhost:16686

### 4. Ejecutar transacción PIX → SPEI
1. Ir a UI → Simulación
2. Origen: PIX, Destino: SPEI
3. Llenar formulario con datos sintéticos
4. Click "Iniciar Transacción"
5. Observar timeline de estados

### 5. Inspeccionar
- **Inspector**: Ver original / canónico / traducido
- **Grafana**: Ver métricas en dashboard "MiPIT Overview"
- **Jaeger**: Buscar por trace_id la traza completa

### 6. Ejecutar transacción inversa SPEI → PIX
- Repetir con origen SPEI, destino PIX

### 7. Probar idempotencia
- Repetir misma transacción con mismo Idempotency-Key
- Verificar que devuelve misma respuesta sin procesar de nuevo

### 8. Probar fallo
- Esperar a que el mock rechace (~10% de las veces)
- Verificar estado REJECTED y rail_ack con error

### 9. Reset
```bash
bash scripts/reset.sh
```
```

---

## 3. Orden de ejecución al construir

1. Crear estructura de carpetas
2. Copiar PDFs existentes a srs/, spmp/, propuesta/
3. Crear ADRs (8 decisiones)
4. Crear contratos (mensajes, estados, errores)
5. Crear OpenAPI spec
6. Crear tablas de mapeo (CSV)
7. Crear runbooks
8. `git init && git add . && git commit -m "chore: initial mipit-docs scaffold"`
9. `git remote add origin https://github.com/MIPIT-PoC/mipit-docs.git && git push -u origin main`
