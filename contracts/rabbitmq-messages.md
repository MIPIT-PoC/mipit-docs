# Contratos de Mensajes RabbitMQ

## Topología

```
Exchange: mipit.payments (type: topic, durable: true)
├── Binding: route.pix  → Queue: q.adapter.pix   (consumer: mipit-adapter-pix)
├── Binding: route.spei → Queue: q.adapter.spei  (consumer: mipit-adapter-spei)
├── Binding: ack.pix    → Queue: q.core.ack      (consumer: mipit-core)
└── Binding: ack.spei   → Queue: q.core.ack      (consumer: mipit-core)

Exchange: mipit.dlx (type: direct, durable: true)
├── Binding: dlq.pix  → Queue: q.dlq.pix
└── Binding: dlq.spei → Queue: q.dlq.spei
```

## Propiedades comunes de mensajes

| Propiedad | Valor |
|-----------|-------|
| `content_type` | `application/json` |
| `content_encoding` | `utf-8` |
| `delivery_mode` | `2` (persistent) |
| `headers.trace_id` | ID de traza W3C para correlación |
| `headers.source_service` | Nombre del servicio que publica |

---

## Core → Adaptador: `route.{pix|spei}`

Publicado por el core después de canonicalizar y enrutar. El routing key determina qué adaptador consume el mensaje.

```json
{
  "payment_id": "PMT-01HPX9Y3Q9K1Z8G7V2",
  "trace_id": "01HPX9Y3Q9K1Z8G7V3",
  "canonical": {
    "msg_id": "MSG-01HPX9Y3Q9K1Z8G7V5",
    "creation_date_time": "2026-03-01T15:22:10.000Z",
    "number_of_txs": 1,
    "settlement_method": "CLRG",
    "instructing_agent": "BCOBR-MOCK",
    "instructed_agent": "BCOMX-MOCK",
    "debtor": {
      "name": "Maria Silva",
      "alias": "+5511999887766",
      "alias_type": "PHONE",
      "account": "00012345678",
      "agent_id": "BCOBR-MOCK"
    },
    "creditor": {
      "name": "Carlos Mejía",
      "alias": "012180012345678901",
      "alias_type": "CLABE",
      "account": "012180012345678901",
      "agent_id": "BCOMX-MOCK"
    },
    "amount": 1500.00,
    "currency": "BRL",
    "purpose": "P2P",
    "remittance_info": "MIPIT-DEMO-001",
    "source_rail": "PIX"
  },
  "destination_rail": "SPEI",
  "route_rule_applied": "clabe_to_spei",
  "routed_at": "2026-03-01T15:22:10.000Z"
}
```

### Campos

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `payment_id` | string | sí | ID único de la transacción (formato `PMT-{ulid}`) |
| `trace_id` | string | sí | ID de traza para correlación distribuida |
| `canonical` | object | sí | Modelo canónico pacs.008 completo |
| `destination_rail` | string | sí | Riel destino: `PIX` o `SPEI` |
| `route_rule_applied` | string | sí | Nombre de la regla de ruteo que se aplicó |
| `routed_at` | string (ISO 8601) | sí | Timestamp de cuando se enrutó |

---

## Adaptador → Core: `ack.{pix|spei}`

Publicado por el adaptador después de enviar al sandbox/mock del riel y recibir respuesta (o agotar reintentos).

### Ejemplo: Éxito (ACCEPTED)

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
    "raw_response": {
      "claveRastreo": "MIPIT20260301001",
      "estado": "LIQUIDADO"
    }
  },
  "latency_ms": 342,
  "processed_at": "2026-03-01T15:22:10.342Z"
}
```

### Ejemplo: Rechazo (REJECTED)

```json
{
  "payment_id": "PMT-01HPX9Y3Q9K1Z8G7V2",
  "trace_id": "01HPX9Y3Q9K1Z8G7V3",
  "source_rail": "PIX",
  "adapter_id": "adapter-pix",
  "instance_id": "pix-67890",
  "status": "ACKED_BY_RAIL",
  "rail_ack": {
    "rail_tx_id": null,
    "status": "REJECTED",
    "error": {
      "code": "PIX_INVALID_KEY",
      "message": "Chave PIX não encontrada"
    },
    "raw_response": {
      "endToEndId": null,
      "motivo": "CHAVE_NAO_ENCONTRADA"
    }
  },
  "latency_ms": 128,
  "processed_at": "2026-03-01T15:22:10.128Z"
}
```

### Campos

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `payment_id` | string | sí | ID de la transacción original |
| `trace_id` | string | sí | ID de traza para correlación |
| `source_rail` | string | sí | Riel que procesó: `PIX` o `SPEI` |
| `adapter_id` | string | sí | Identificador del tipo de adaptador |
| `instance_id` | string | sí | Identificador de la instancia específica |
| `status` | string | sí | Siempre `ACKED_BY_RAIL` (el core decide el estado final) |
| `rail_ack.rail_tx_id` | string \| null | sí | ID de transacción asignado por el riel |
| `rail_ack.status` | string | sí | `ACCEPTED` o `REJECTED` |
| `rail_ack.error` | object \| null | sí | Detalle del error (null si ACCEPTED) |
| `rail_ack.raw_response` | object | sí | Respuesta cruda del sandbox/mock |
| `latency_ms` | number | sí | Latencia total del procesamiento en el adaptador |
| `processed_at` | string (ISO 8601) | sí | Timestamp de cuando se completó |

---

## Exchange: `mipit.dlx` (Dead Letter)

Mensajes que fallan después de agotar reintentos (default: 3 intentos con backoff exponencial) van a `dlq.pix` o `dlq.spei`. El formato es idéntico al mensaje original de `route.{pix|spei}`, con headers adicionales:

| Header | Descripción |
|--------|-------------|
| `x-death[0].count` | Número de intentos fallidos |
| `x-death[0].reason` | Razón del dead-letter (`rejected`, `expired`) |
| `x-death[0].queue` | Cola original de la que proviene |
| `x-death[0].time` | Timestamp del último intento |
