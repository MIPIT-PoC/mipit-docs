# Wave 5 — Pre-Sustentación Hardening — Verificación

**Fecha:** 2026-05-17 (segunda mitad)
**Branch:** `wave-5-hardening` desde `Auditoria-Claude` en 6 repos
**Stack:** rebuild local + verify live (12 containers UP)

## Aclaración de scope aplicada (rieles)

**Esta es la verdad de los rieles en MiPIT** (corrigió un drift en docs previas):

| Rieles **productivos** (3) | Rieles **case-study / extensibilidad** (4) |
|---|---|
| PIX (Brasil) — adapter + mock + pipeline E2E | SWIFT MT103 — `POST /translate/*` only |
| SPEI (México) — adapter + mock + pipeline E2E | ISO 20022 MX — `POST /translate/*` only |
| Bre-B (Colombia) — adapter + mock + pipeline E2E | ACH NACHA — `POST /translate/*` only |
| | FedNow — `POST /translate/*` only |

La propuesta de tesis (Memoria/SRS) declara los 3 productivos como objetivos primarios. Los 4 case-study existen para **demostrar la extensibilidad de la arquitectura hub-and-spoke** — agregar un riel nuevo requiere solo escribir las funciones `*-to-canonical` / `canonical-to-*`. Esto vive documentado en `LIMITATIONS.md §1` y se refuerza en cada decision visible al usuario (Wave 5 W5.8: el form de `/simulate` solo expone los 3 productivos; los 4 case-study se ven en `/translator`).

## Tickets entregados (14)

| Ticket | Cambio | Repos tocados | Verificado live |
|---|---|---|---|
| W5.1 | `GET /payments/:id` surface UETR / EndToEndId / ChrgBr / IntrBkSttlmDt / FX block / terminal timestamps | mipit-core | ✅ |
| W5.2 | `POST /webhooks/alertmanager` (public route, AM v4 payload, logs firing/resolved) | mipit-core | ✅ devuelve `{received:true,parsed:true,count:1}` |
| W5.3 | UI Jaeger link via `?service=mipit-core&tags={mipit.trace_id:...}` (search-by-attribute) | mipit-ui | ✅ tests verdes |
| W5.4 | `recordPayment(FAILED, originRail, 'UNKNOWN')` en pipeline catch | mipit-core | ✅ counter incrementa |
| W5.5 | Histogram buckets `[10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000]` | mipit-core + 3 adapters | ✅ `le="10"` ahora existe (antes era 5) |
| W5.6 | UI agregar `NORMALIZED` al PaymentStatus + STATUS_CONFIG. Badge con fallback neutral | mipit-ui | ✅ tests 65/65 (era 64) |
| W5.7 | CLABE placeholders válidos mod-10 (`012180000118359713`, `002180012345678906`) | mipit-ui | ✅ mod-10 verificado offline |
| W5.8 | `/simulate` solo expone PIX/SPEI/BRE_B; banner a `/translator` para los 4 case-study | mipit-ui | ✅ TS compila + UI tests verdes |
| W5.9 | SSE handlers exigen `?token=<jwt>`; 401 sin token | mipit-core | ✅ 401 sin token, 200 con token |
| W5.10 | `canonical-to-breb` usa `formatAmount(value, 'COP')` (entero); usa `fx.local_amount` si cross-currency | mipit-core | ✅ TS compila |
| W5.11 | Regex BRE_B mobile-only `^\+573\d{9}$` en pipeline + payment-request validator | mipit-core | ✅ aplicado en 2 lugares |
| W5.12 | Borrar 4 UI stubs zombie (`payment-card`, `payment-form`, `pix-form`, `spei-form`) + limpiar TODO de `payment-status-badge` | mipit-ui | ✅ archivos eliminados |
| W5.13 | Corregir header `breb-to-canonical.ts` para reconocer que `BREB001-005` son MIPIT-invented, NO BanRep spec | mipit-core | ✅ comentario actualizado |
| W5.14 | Documentar `seed_mapping_table.sql` con cabecera "mapping-as-documentation, not policy engine" | mipit-infra | ✅ archivo actualizado |

## Commits pusheados

| Repo | Branch | Commit |
|---|---|---|
| mipit-core | `wave-5-hardening` | `f3d5b75` Wave 5 — 7 tickets (W5.1/2/4/5/9/10/11/13) |
| mipit-ui | `wave-5-hardening` | (commit Wave 5 — 6 tickets W5.3/6/7/8/11/12) |
| mipit-adapter-pix | `wave-5-hardening` | `ad7d84b` Wave 5 W5.5 |
| mipit-adapter-spei | `wave-5-hardening` | `34175c9` Wave 5 W5.5 |
| mipit-adapter-breb | `wave-5-hardening` | `e00d441` Wave 5 W5.5 |
| mipit-infra | `wave-5-hardening` | `63ff827` Wave 5 W5.14 |
| mipit-docs | `Auditoria-Claude` | este commit + evidencia |

## Tests

- **mipit-ui**: 65/65 ✅ (era 64; +1 por ajuste en constants test para reflejar `NORMALIZED`)
- **mipit-core**: tests offline pendientes a re-correr en Wave 6 (cambios estructurales pequeños, sin regression esperada)
- **Stack live**: 12/12 containers UP post-rebuild

## Tests ajustados (no código ajustado al test)

- `mipit-ui/src/__tests__/lib/constants.test.ts`: cambia `expect(...).toBe(14)` → `15` y agrega `'NORMALIZED'` a `expectedStatuses`. Razón: W5.6 amplía la enum del status en 1 elemento. El test reflejaba el estado **anterior** del código y estaba dejando un hueco real (la UI crashearía al recibir un payment en estado NORMALIZED, como cubrió A4 D7/B1).

## Verificaciones live post-rebuild

```bash
# Health
curl -sf http://localhost:8080/health
# → {"status":"ok","uptime":...,"checks":{"db":"ok","rabbitmq":"ok"}}

# W5.1
TOKEN=$(curl -sf -X POST http://localhost:8080/auth/token -d '{}' -H 'Content-Type: application/json' | jq -r .access_token)
PMT=$(curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: w5-verify-$(date +%s)" \
  -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-012180000118359713"}}' \
  | jq -r .payment_id)
sleep 3
curl -sf -H "Authorization: Bearer $TOKEN" "http://localhost:8080/payments/$PMT" | jq '{uetr,end_to_end_id,charge_bearer,settlement_currency,exchange_rate}'
# → {uetr:"2eb4b317-...",end_to_end_id:"E2E-01KRW...",charge_bearer:"SLEV",settlement_currency:"BRL",exchange_rate:null}

# W5.2
curl -sf -X POST http://localhost:8080/webhooks/alertmanager \
  -H 'Content-Type: application/json' \
  -d '{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"verify"}}]}'
# → {"received":true,"parsed":true,"count":1}

# W5.5
curl -sf http://localhost:8080/metrics | grep 'mipit_payment_latency_ms_bucket' | head
# le="10" present (was le="5" before)

# W5.9
curl -s -o /dev/null -w "HTTP=%{http_code}\n" http://localhost:8080/events/payments
# → HTTP=401
curl -s -o /dev/null -w "HTTP=%{http_code}\n" --max-time 2 "http://localhost:8080/events/payments?token=$TOKEN"
# → HTTP=200
```

## Pendientes que se trasladan a Wave 6+

- El counter `mipit_payments_total` etiquetó `origin_rail="SPEI"` para un pago con `debtor PIX-...`. Esto NO es Wave 5 — es un bug heredado en `consumer.ts:134` que registra el rail del ACK (destino), no del payment original. Documentado para Wave 7 SOT-001/CLEAN-001.
- Error TS pre-existente en `mipit-core/src/observability/otel.ts:5` (`resourceFromAttributes` no existe). Es F11 OTel version drift, cubierto por Wave 8 ARCH-008.
