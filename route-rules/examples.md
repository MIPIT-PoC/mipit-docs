# Ejemplos de Enrutamiento

## Ejemplo 1: PIX → SPEI

Un usuario en Brasil envía dinero a un destinatario en México usando su CLABE.

### Input (después de canonicalización)

```json
{
  "canonical": {
    "debtor": {
      "alias": "+5511999887766",
      "alias_type": "PHONE"
    },
    "creditor": {
      "alias": "012180012345678901",
      "alias_type": "CLABE"
    },
    "amount": 1500.00,
    "currency": "BRL",
    "source_rail": "PIX"
  }
}
```

### Evaluación de reglas

| Regla | Condición | Match |
|-------|-----------|-------|
| `clabe_to_spei` | `creditor.alias_type == CLABE` | **SÍ** |
| `cpf_to_pix` | `creditor.alias_type in [CPF, CNPJ, EVP]` | NO |
| `phone_br_to_pix` | `creditor.alias_type == PHONE` | NO (es CLABE) |
| `phone_mx_to_spei` | `creditor.alias_type == PHONE_MX` | NO |
| `email_to_pix` | `creditor.alias_type == EMAIL` | NO |

### Resultado

- **Regla aplicada**: `clabe_to_spei`
- **Destino**: `SPEI`
- **Cola RabbitMQ**: `route.spei`
- **Estado**: `ROUTED`

---

## Ejemplo 2: SPEI → PIX

Un usuario en México envía dinero a un destinatario en Brasil usando su CPF como clave PIX.

### Input (después de canonicalización)

```json
{
  "canonical": {
    "debtor": {
      "alias": "012180098765432101",
      "alias_type": "CLABE"
    },
    "creditor": {
      "alias": "12345678901",
      "alias_type": "CPF"
    },
    "amount": 5000.00,
    "currency": "MXN",
    "source_rail": "SPEI"
  }
}
```

### Evaluación de reglas

| Regla | Condición | Match |
|-------|-----------|-------|
| `clabe_to_spei` | `creditor.alias_type == CLABE` | NO (es CPF) |
| `cpf_to_pix` | `creditor.alias_type in [CPF, CNPJ, EVP]` | **SÍ** |
| `phone_br_to_pix` | `creditor.alias_type == PHONE` | NO |
| `phone_mx_to_spei` | `creditor.alias_type == PHONE_MX` | NO |
| `email_to_pix` | `creditor.alias_type == EMAIL` | NO |

### Resultado

- **Regla aplicada**: `cpf_to_pix`
- **Destino**: `PIX`
- **Cola RabbitMQ**: `route.pix`
- **Estado**: `ROUTED`

---

## Ejemplo 3: Adaptador caído (adapter down)

Un pago enrutado a SPEI pero el adaptador no está disponible (contenedor detenido o sin consumers en la cola).

### Input

Misma transacción del Ejemplo 1 (PIX → SPEI), pero `mipit-adapter-spei` está detenido.

### Flujo

1. El core evalúa reglas normalmente → regla `clabe_to_spei` matched → destino SPEI
2. El core publica en `route.spei` → estado pasa a `QUEUED`
3. El mensaje queda en la cola `q.adapter.spei` **sin consumer activo**
4. RabbitMQ mantiene el mensaje en la cola (es persistente/durable)
5. Después de que el TTL de la cola expira (configurable, default 60s para PoC):
   - El mensaje va al dead-letter exchange `mipit.dlx`
   - Se enruta a `q.dlq.spei`
6. El core detecta el timeout vía un health check periódico o cuando el mensaje aparece en DLQ
7. Estado final: `FAILED` con error `RAIL_UNAVAILABLE`

### Respuesta al consultar `GET /payments/{payment_id}`

```json
{
  "payment_id": "PMT-01HPX9Y3Q9K1Z8G7V2",
  "status": "FAILED",
  "origin": "PIX",
  "destination": "SPEI",
  "amount": 1500.00,
  "currency": "BRL",
  "rail_ack": null,
  "timestamps": {
    "received_at": "2026-03-01T15:22:10.000Z",
    "validated_at": "2026-03-01T15:22:10.012Z",
    "canonicalized_at": "2026-03-01T15:22:10.025Z",
    "routed_at": "2026-03-01T15:22:10.030Z",
    "queued_at": "2026-03-01T15:22:10.045Z",
    "completed_at": null
  }
}
```

### Recuperación

Una vez que se reinicia el adaptador SPEI:
- Mensajes nuevos se procesan normalmente
- Mensajes en DLQ pueden reprocesarse manualmente (fuera de alcance del PoC)
- El pago fallido debe ser reintentado por el usuario creando una nueva transacción
