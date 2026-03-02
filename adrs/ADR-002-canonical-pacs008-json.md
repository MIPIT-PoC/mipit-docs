# ADR-002: Modelo canónico basado en pacs.008 (JSON)

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

Se necesita una "lengua franca" para representar instrucciones de crédito
entre rieles heterogéneos (PIX y SPEI).

## Decisión

Usar **pacs.008 (Customer Credit Transfer)** como base del modelo canónico,
representado en **JSON interno** (no XML ISO literal), pero alineado
semánticamente a la estructura de pacs.008.

Para respuestas/confirmaciones del riel destino, se define un modelo
**inspirado en pacs.002 (Status Report)**.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| XML ISO 20022 literal | Estándar real, interoperable | Verboso, parsing complejo, overhead para PoC |
| JSON schema propio sin ISO | Simple, libre | Sin fundamento estándar, difícil de justificar |
| **JSON alineado a pacs.008** | Balance entre estándar y pragmatismo | No interoperable con sistemas ISO reales |
| Protocol Buffers | Eficiente, tipado | Overhead de tooling, menos legible |

## Razones

- pacs.008 encaja naturalmente con "transferencia de crédito entre rieles"
- JSON es más ergonómico que XML para el PoC y la UI
- La alineación semántica permite documentar el mapeo ISO 20022
- pacs.002-like permite representar ACCEPTED/REJECTED del riel

## Consecuencias

- No se valida contra XSD ISO 20022 real (solo subset)
- El modelo canónico es propio del middleware (no interoperable con sistemas ISO reales)
- Se documenta como limitación aceptada del PoC
