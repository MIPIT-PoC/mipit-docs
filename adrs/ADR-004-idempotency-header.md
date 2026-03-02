# ADR-004: Idempotencia vía Idempotency-Key header

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

En sistemas de pago, los clientes pueden reintentar solicitudes debido a timeouts o fallos de red.
Sin mecanismo de idempotencia, un reintento podría crear una transacción duplicada.
Se necesita garantizar que una misma solicitud procesada múltiples veces produzca el mismo resultado.

## Decisión

Implementar idempotencia a nivel de API usando un header **`Idempotency-Key`** (UUID) enviado
por el cliente en `POST /payments`. El core almacena el hash del payload junto con la key en
PostgreSQL y devuelve la respuesta cacheada si la key ya existe con el mismo payload.
Si la key existe pero el payload es diferente, se retorna `409 Conflict`.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| Deduplicación por contenido (hash del body) | No requiere header adicional | Dos pagos legítimos con mismo monto/datos serían rechazados |
| Idempotencia en base a campo `reference` | Simple | El campo reference puede repetirse legítimamente |
| **Idempotency-Key header** | Estándar de industria (Stripe, IETF draft), explícito | Requiere que el cliente genere y envíe la key |
| Token pre-generado por el server | Previene replay | Doble round-trip, complejidad innecesaria para PoC |

## Razones

- Patrón estándar de la industria (Stripe, PayPal, IETF draft-ietf-httpapi-idempotency-key-header)
- El cliente tiene control explícito sobre qué constituye "la misma solicitud"
- Implementación simple: tabla `idempotency_keys(key, payload_hash, response, created_at)` con TTL
- Detección de conflictos (misma key, payload diferente) previene errores sutiles
- La UI puede generar UUIDs automáticamente para cada submit

## Consecuencias

- La UI debe generar un UUID único por cada intento de creación de pago
- Se necesita una tabla adicional en PostgreSQL con limpieza periódica (TTL de 24h)
- Los reintentos legítimos reciben la misma respuesta sin reprocesar
- El header es obligatorio en `POST /payments`
