# Máquina de Estados — PaymentStatus

## Estados

| Estado | Descripción |
|--------|-------------|
| RECEIVED | API aceptó la solicitud |
| VALIDATED | Payload validado (formato, campos obligatorios) |
| CANONICALIZED | Mensaje canónico pacs.008 generado |
| ROUTED | Destino decidido por motor de reglas |
| QUEUED | Mensaje publicado a RabbitMQ |
| SENT_TO_DESTINATION | Adaptador envió al sandbox/mock |
| ACKED_BY_RAIL | Respuesta del riel recibida |
| COMPLETED | Flujo exitoso finalizado |
| FAILED | Fallo no recuperable |
| REJECTED | Riel rechazó la transacción |
| DUPLICATE | Idempotencia detectó duplicado |

## Diagrama de transiciones

```
                    ┌──────────┐
                    │ RECEIVED │
                    └────┬─────┘
                         │
                    ┌────▼──────┐
              ┌─────│ VALIDATED │
              │     └────┬──────┘
              │          │
              │  ┌───────▼────────┐
              │  │ CANONICALIZED  │
              │  └───────┬────────┘
              │          │
              │     ┌────▼───┐
              │     │ ROUTED │
              │     └────┬───┘
              │          │
              │     ┌────▼───┐
              │     │ QUEUED │
              │     └────┬───┘
              │          │
              │  ┌───────▼────────────┐
              │  │ SENT_TO_DESTINATION│
              │  └───────┬────────────┘
              │          │
              │  ┌───────▼────────┐
              │  │ ACKED_BY_RAIL  │
              │  └───┬────────┬───┘
              │      │        │
              │ ┌────▼─────┐ ┌▼─────────┐
              │ │COMPLETED │ │ REJECTED  │
              │ └──────────┘ └───────────┘
              │
     ┌────────▼──┐     ┌───────────┐
     │  FAILED   │     │ DUPLICATE │
     └───────────┘     └───────────┘
    (desde cualquier     (desde RECEIVED
     estado)              si key existe)
```

## Transiciones válidas

```
RECEIVED → VALIDATED → CANONICALIZED → ROUTED → QUEUED → SENT_TO_DESTINATION → ACKED_BY_RAIL → COMPLETED
                                                                                             → REJECTED
RECEIVED → DUPLICATE (idempotencia)
* → FAILED (cualquier etapa puede fallar)
```

## Tabla de transiciones

| Estado origen | Estado destino | Trigger | Actor |
|---------------|----------------|---------|-------|
| — | RECEIVED | `POST /payments` aceptado | Core (API handler) |
| RECEIVED | DUPLICATE | Idempotency-Key ya existe con mismo payload | Core (idempotency check) |
| RECEIVED | VALIDATED | Validación Zod exitosa | Core (validator) |
| RECEIVED | FAILED | Validación falla | Core (validator) |
| VALIDATED | CANONICALIZED | Traducción a pacs.008 exitosa | Core (translator) |
| VALIDATED | FAILED | Error de traducción | Core (translator) |
| CANONICALIZED | ROUTED | Regla de enrutamiento matched | Core (router) |
| CANONICALIZED | FAILED | Sin regla de enrutamiento aplicable | Core (router) |
| ROUTED | QUEUED | Mensaje publicado a RabbitMQ | Core (publisher) |
| ROUTED | FAILED | RabbitMQ no disponible | Core (publisher) |
| QUEUED | SENT_TO_DESTINATION | Adaptador tomó el mensaje | Adaptador (consumer) |
| SENT_TO_DESTINATION | ACKED_BY_RAIL | Riel respondió | Adaptador (processor) |
| SENT_TO_DESTINATION | FAILED | Adaptador agotó reintentos | Adaptador (retry logic) |
| ACKED_BY_RAIL | COMPLETED | `rail_ack.status == ACCEPTED` | Core (ack handler) |
| ACKED_BY_RAIL | REJECTED | `rail_ack.status == REJECTED` | Core (ack handler) |

## Reglas

- Solo el **core** puede transicionar estados (excepto SENT_TO_DESTINATION que lo reporta el adaptador)
- Los **adaptadores** reportan vía ack message, el core decide estado final
- **FAILED** es terminal — no se reintenta desde core (el adaptador ya agotó reintentos)
- **DUPLICATE** es terminal — se devuelve la respuesta cacheada
- **COMPLETED** es terminal — la transacción finalizó exitosamente
- **REJECTED** es terminal — el riel rechazó la transacción
- Cada transición actualiza el campo `timestamps.{estado}_at` en la base de datos
- Cada transición emite un span de OpenTelemetry para trazabilidad
