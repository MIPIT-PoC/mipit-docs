# Catálogo de Códigos de Error

## Errores de API (retornados en HTTP response)

| Code | HTTP | Descripción | Ejemplo |
|------|------|-------------|---------|
| VALIDATION_ERROR | 400 | Payload inválido (campos, formato) | `debtor.alias is required` |
| UNAUTHORIZED | 401 | JWT inválido o ausente | `Authorization header missing` |
| FORBIDDEN | 403 | Token válido pero sin permisos | `Insufficient permissions` |
| NOT_FOUND | 404 | payment_id no existe | `Payment PMT-xxx not found` |
| IDEMPOTENCY_CONFLICT | 409 | Idempotency-Key con payload diferente | `Key already used with different payload` |
| UNPROCESSABLE_ENTITY | 422 | Datos hard-required no resolubles | `Cannot determine destination rail` |
| RATE_LIMITED | 429 | Demasiadas solicitudes (opcional) | `Too many requests, retry after 60s` |
| INTERNAL_ERROR | 500 | Error interno no esperado | `Unexpected error processing payment` |
| RAIL_UNAVAILABLE | 502 | Adaptador/sandbox no disponible | `SPEI adapter not responding` |
| RAIL_TIMEOUT | 504 | Sandbox no respondió en tiempo | `PIX sandbox timeout after 30s` |

## Errores internos (en logs y trazas, no expuestos directamente al cliente)

| Code | Descripción | Componente |
|------|-------------|------------|
| TRANSLATION_ERROR | Error en traducción canónica (campo no mapeado, tipo incompatible) | Core (translator) |
| ROUTING_ERROR | Error en motor de enrutamiento (sin regla aplicable, regla ambigua) | Core (router) |
| ADAPTER_ERROR | Error genérico del adaptador (conexión, serialización) | Adaptador |
| QUEUE_PUBLISH_ERROR | Error al publicar mensaje a RabbitMQ | Core (publisher) |
| QUEUE_CONSUME_ERROR | Error al consumir mensaje de RabbitMQ | Adaptador (consumer) |
| DB_ERROR | Error de base de datos (conexión, constraint violation) | Core (repository) |

## Errores específicos de rieles (en `rail_ack.error.code`)

Estos códigos aparecen en el ack del adaptador cuando el riel rechaza la transacción.

### PIX

| Code | Descripción | Acción sugerida |
|------|-------------|-----------------|
| PIX_INSUFFICIENT_FUNDS | Fondos insuficientes en cuenta origen | Informar al usuario |
| PIX_INVALID_KEY | Clave PIX no encontrada | Verificar alias del creditor |
| PIX_ACCOUNT_BLOCKED | Cuenta bloqueada por el banco | Contactar al banco |
| PIX_DAILY_LIMIT | Límite diario de transferencias excedido | Reintentar al día siguiente |
| PIX_TIMEOUT | Timeout del sandbox PIX | Reintento automático por adaptador |

### SPEI

| Code | Descripción | Acción sugerida |
|------|-------------|-----------------|
| SPEI_INVALID_CLABE | CLABE inválida o inexistente | Verificar alias del creditor |
| SPEI_TIMEOUT | Timeout del sandbox SPEI | Reintento automático por adaptador |
| SPEI_BANK_REJECTED | Banco destino rechazó la transferencia | Verificar datos del creditor |
| SPEI_MAINTENANCE | Sistema SPEI en mantenimiento | Reintentar más tarde |
| SPEI_DAILY_LIMIT | Límite diario excedido | Reintentar al día siguiente |

## Formato de respuesta de error

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "debtor.alias is required",
    "details": {
      "field": "debtor.alias",
      "constraint": "required",
      "received": null
    }
  }
}
```

El campo `details` es opcional y su estructura varía según el tipo de error. Para errores de validación contiene el campo y constraint violado. Para otros errores puede estar ausente o contener información contextual.
