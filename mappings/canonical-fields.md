# Campos del Modelo Canónico (CanonicalPacs008)

Modelo interno inspirado en ISO 20022 pacs.008 (Customer Credit Transfer).
Todos los campos se validan con Zod en el core antes de persistir.

## Campos de cabecera

| Campo | Tipo | Requerido | Validación | Descripción |
|-------|------|-----------|------------|-------------|
| `msg_id` | string | sí | Non-empty, max 35 chars | Identificador único del mensaje canónico. Generado como `MSG-{ulid}` |
| `creation_date_time` | string (ISO 8601) | sí | Valid ISO 8601 datetime | Timestamp de creación del mensaje canónico |
| `number_of_txs` | integer | sí | Siempre `1` | Número de transacciones en el mensaje (siempre 1 para el PoC) |
| `settlement_method` | string | sí | Enum: `CLRG` | Método de liquidación. Fijo en `CLRG` (clearing) para el PoC |
| `instructing_agent` | string | sí | Non-empty, max 35 chars | BIC mock o identificador del agente/banco ordenante |
| `instructed_agent` | string | sí | Non-empty, max 35 chars | BIC mock o identificador del agente/banco beneficiario |

## Campos del deudor (debtor)

| Campo | Tipo | Requerido | Validación | Descripción |
|-------|------|-----------|------------|-------------|
| `debtor.name` | string | no | Max 140 chars, trimmed | Nombre completo del ordenante |
| `debtor.alias` | string | sí | Non-empty | Identificador principal: clave PIX, CLABE, teléfono, email |
| `debtor.alias_type` | string | sí | Enum: `CPF`, `CNPJ`, `PHONE`, `EMAIL`, `EVP`, `CLABE`, `PHONE_MX`, `CARD` | Tipo de alias, detectado automáticamente por el translator |
| `debtor.account` | string | no | Max 34 chars (IBAN-compatible length) | Número de cuenta bancaria |
| `debtor.agent_id` | string | sí | Non-empty | Identificador de la institución financiera del deudor (ISPB o código SPEI) |

## Campos del acreedor (creditor)

| Campo | Tipo | Requerido | Validación | Descripción |
|-------|------|-----------|------------|-------------|
| `creditor.name` | string | no | Max 140 chars, trimmed | Nombre completo del beneficiario |
| `creditor.alias` | string | sí | Non-empty | Identificador principal: clave PIX, CLABE, teléfono, email |
| `creditor.alias_type` | string | sí | Enum: `CPF`, `CNPJ`, `PHONE`, `EMAIL`, `EVP`, `CLABE`, `PHONE_MX`, `CARD` | Tipo de alias, detectado automáticamente |
| `creditor.account` | string | no | Max 34 chars | Número de cuenta bancaria |
| `creditor.agent_id` | string | sí | Non-empty | Identificador de la institución financiera del acreedor |

## Campos de transacción

| Campo | Tipo | Requerido | Validación | Descripción |
|-------|------|-----------|------------|-------------|
| `amount` | number | sí | > 0, max 2 decimales | Monto de la transacción en la moneda original |
| `currency` | string | sí | ISO 4217, 3 chars (e.g. `BRL`, `MXN`, `USD`) | Código de moneda |
| `purpose` | string | no | Max 35 chars | Propósito del pago: `P2P`, `B2B`, `B2P`, etc. Default: `P2P` |
| `remittance_info` | string | no | Max 140 chars | Referencia o concepto de pago libre |
| `source_rail` | string | sí | Enum: `PIX`, `SPEI` | Riel de origen de la transacción |

## Reglas de detección de alias_type

| Patrón | alias_type | Ejemplo |
|--------|------------|---------|
| 11 dígitos numéricos | `CPF` | `12345678901` |
| 14 dígitos numéricos | `CNPJ` | `12345678000190` |
| `+55` seguido de 10-11 dígitos | `PHONE` | `+5511999887766` |
| `+52` seguido de 10 dígitos | `PHONE_MX` | `+5215512345678` |
| Contiene `@` | `EMAIL` | `maria@email.com` |
| 18 dígitos numéricos | `CLABE` | `012180012345678901` |
| UUID v4 format | `EVP` | `550e8400-e29b-41d4-a716-446655440000` |
| 16 dígitos numéricos | `CARD` | `4111111111111111` |

## Notas

- El modelo canónico es **interno** al middleware — no es interoperable con sistemas ISO 20022 reales
- La validación se ejecuta con **Zod schemas** en el módulo translator del core
- Los campos `instructing_agent` e `instructed_agent` usan identificadores mock (e.g. `BCOBR-MOCK`)
- La detección de `alias_type` es heurística y puede no cubrir todos los formatos reales
