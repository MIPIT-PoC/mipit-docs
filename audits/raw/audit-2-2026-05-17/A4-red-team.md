# A4 — Red Team Pre-Sustentación (Audit 2)

**Fecha:** 2026-05-17 · **Branch:** `Auditoria-Claude` · **Scope:** análisis adversarial — preguntas hostiles del panel + demos en riesgo.

## 1. Preguntas hostiles del panel (top 30)

Semáforo: 🟢 sólida · 🟡 defendible · 🔴 alto riesgo.

### Arquitectura

1. 🟡 **"¿Por qué RabbitMQ y no Kafka?"** — Justificación razonable (routing topic, DLQ, confirm-channels) pero no enunciada. Responder: "instant payments no requieren retención de eventos para reprocesamiento".
2. 🟡 **"¿Cómo escalan a 1000 TPS?"** — Rate-limiter en `constants.ts:149` = 20 PIX/s, 10 SPEI/s, 8 BRE_B/s. PIX real maneja ~30k TPS.
3. 🟢 **"¿Canónico propio vs UETR/SWIFT GPI?"** — ADR-002 documenta. UETR mandatorio en pipeline.
4. 🔴 **"Muéstreme cómo `mapping_table` dirige la traducción."** — DECORATIVO. `applyTransformation` (`pix-to-canonical.ts:11-30`) solo conoce `identity/uppercase/lowercase/strip_pix_prefix/strip_clabe_prefix/numeric/string`. Las 13 transformaciones del SQL seed (`prefix_PIX/strip_prefix/convert_to_MXN/truncate_140/cop_integer/regenerate_if_invalid/map_status/parse_decimal`) **no están implementadas**. Si el panel hace ALTER y prueba un cambio data-driven, **no pasa nada**. **MAYOR RIESGO DEL POC**.
5. 🟡 **"¿Sin sharding = SPOF?"** — Idempotency-key in-memory por instance, no compartida.
6. 🟡 **"RouteEngine cache TTL 5min — y si meten regla en caliente?"** — Sin endpoint de invalidación manual.

### Negocio

7. 🟢 **"¿Pago duplicado en riel destino?"** — Idempotency-Key + endToEndId PIX + idTransaccion BREB.
8. 🔴 **"SPEI cae en mitad de batch — ¿50 pagos en vuelo?"** — `QUEUED` stuck hasta que adapter regrese o 1h TTL (`x-message-ttl:3600000`). Reconciliation reporta "stuck" tras 15 min pero **NO compensa automáticamente**.
9. 🔴 **"Muéstreme compensación real (pacs.004)."** — `compensation-service.ts:73` admite "log the intent". Solo cambio de estado DB. Sin envío a mocks.
10. 🟡 **"¿FX con proveedor caído?"** — `fx-service.ts:48` FALLBACK_RATES hardcoded: `BRL:5.02, MXN:17.43, COP:4180.0`. Sin `OPEN_EXCHANGE_RATES_APP_ID`, demo BRL→MXN = exactly `17.43/5.02 ≈ 3.4721`. "Sospechosamente redondos".

### Seguridad

11. 🔴 **"JWT secret en .env?"** — `mipit-infra/env/core.env:5`: `JWT_SECRET=mipit-poc-jwt-secret-change-in-production`. **Committeado al repo.** `postgres.env:2`: `mipit_secret`. `git log -p env/` sería doloroso.
12. 🟡 **"SQL injection en `name`?"** — Queries parametrizadas (`payment.repository.ts:30`).
13. 🟢 **"XSS con `<script>`?"** — `sanitize.ts:19-23` bloquea.
14. 🟡 **"Idempotency replay valida firma payload?"** — Sí, SHA256 (`payments.ts:27-30`).
15. 🔴 **"`/auth/token` debe ser 404 en prod."** — `NODE_ENV=development` en core.env → **habilitado** y emite tokens sin credenciales.

### ISO 20022

16. 🟢 **"Muéstreme UETR en `pacs.008`."** — `payment-pipeline.ts:41` `randomUUID()`. Persiste `uetr UUID UNIQUE`.
17. 🔴 **"`EndToEndId` en BD `E2E-01KRVQ...` no cumple formato PIX."** — Correcto. Canónico guarda `E2E-${ulid()}`. Adapter regenera válido en `mapper.ts:63`. **UI EndToEndId ≠ wire-format EndToEndId**. Tracing por ID no correlaciona.
18. 🟡 **"`pacs.002` para ACK?"** — Schema existe, adapters lo emiten opcionalmente. Consumer mapea a `txSts`.
19. 🟡 **"`pacs.004` para devoluciones?"** — `compensation-service.ts:83` admite "would be sent". Wave 2 P02.4 DEVOL falló en evidencia.
20. 🔴 **"`ChrgBr` defaults SLEV — auditable?"** — Sin registro de "cliente envió X, normalizamos a Y".

### Operación / Resiliencia

21. 🔴 **"Detengan adapter SPEI, envíen PIX→SPEI en vivo."** — Pago QUEUED indefinido. 15 min → reconciliation lo marca stuck. 1h → DLQ por TTL. Alert `AdapterUnreachable` con `for: 1m` dispara, pero el webhook va a `/webhooks/alertmanager` que **no existe**.
22. 🟡 **"Muéstrenme circuit breaker abriéndose."** — Implementación existe (`resilience/circuit-breaker.ts`) pero **único caller es `ui-proxy.ts:17`**. Pipeline NO usa CB. Demo CLOSED→OPEN→HALF_OPEN imposible.
23. 🟢 **"RabbitMQ caído?"** — Publisher confirms wired.
24. 🟡 **"DLQ con retry?"** — `dlq-handler.ts:75`: marca DEAD_LETTER y "requires manual review". Runbook miente diciendo "vuelve a publicarlo cuando adapter regrese".

### Observabilidad

25. 🔴 **"Grafana muestra 8 pagos, UI muestra 12. ¿Por qué?"** — Métrica solo incrementa en ACK consumer (`consumer.ts:134`). Pagos que fallan dentro del pipeline (FX/routing/validation) actualizan DB pero NO counter. Discrepancia reproducible.
26. 🔴 **"Provoquen alert, muéstrenme cadena al core."** — AlertManager → `http://core:8080/webhooks/alertmanager` (`alertmanager.yml:24`). **No existe route handler** en `mipit-core/src`. AlertManager hace 404. Cadena rota.
27. 🔴 **"Cliqueen 'Ver en Jaeger'."** — `trace_id` UI es **ULID** (`tracing.ts:6` `ulid()`). Jaeger espera hex 16/32 chars. Link `/trace/<ULID>` no encuentra trace. OTel span existe con otro ID. **VISIBLE EN VIVO**.

### Performance / Spec

28. 🟡 **"Cuántos TPS?"** — Sin test de carga. Histogram cap 2500ms.
29. 🔴 **"Alert `HighLatency` dispara cuando p95 > 10000ms, pero histogram cap 2500ms. ¿Cómo funciona?"** — Pregunta letal. Respuesta honesta: "no funciona, debe ajustar buckets".
30. 🟡 **"Muéstreme pago cross-currency: instructed/settlement/rate audit-trail."** — Bloque FX en UI (`payments/[id]/page.tsx:153-170`), pero `payment.exchange_rate` **no se devuelve en `GET /payments/:id`** (`payments.ts:124-148` omite columns). Columnas en DB pero response no surface. **Bloque FX nunca aparece**.

## 2. Demos en vivo con riesgo de fallar (10)

| # | Escenario | Qué se ve | Riesgo |
|---|---|---|---|
| D1 | Open payment detail "Trazabilidad ISO 20022" | Solo `trace_id`. NO UETR, EndToEndId, ChrgBr, IntrBkSttlmDt (response API no surface) | 🔴 |
| D2 | Click "Ver en Jaeger ↗" | Jaeger devuelve "Trace not found" (ULID ≠ hex) | 🔴 |
| D3 | Demo BRL→MXN, bloque "Conversión FX" | NO aparece (response API omite `exchange_rate`) | 🔴 |
| D4 | `/simulate` con placeholder `SPEI-012180000118359719` | CLABE no pasa mod-10. Click → `400 invalid CLABE` | 🔴 |
| D5 | `/simulate` destino SWIFT/NACHA/FEDNOW | Forms aceptan pero rieles sin adapter activo. Routing falla genérico | 🔴 |
| D6 | `docker stop mipit-adapter-spei` + PIX→SPEI | Pago QUEUED indefinido. UI spinner. 1h DLQ por TTL, no retry | 🟡 |
| D7 | Componentes UI con TODO: en JSX | 5 componentes (`payment-form.tsx:14`, `pix-form.tsx:9`, `spei-form.tsx:9`, `payment-card.tsx:13`, `payment-status-badge.tsx:11`) renderizan literal "TODO: ..." | 🟡 |
| D8 | Grafana panel "Tasa de Éxito (%)" | Counter no cuenta failures dentro pipeline → 100% éxito aunque hubo 3 FAILED | 🔴 |
| D9 | Grafana panel latencia P95/P99 | Histogram cap 2500ms → pagos >3s en bucket +Inf → `p99 = +Inf` o NaN | 🟡 |
| D10 | Idempotency con misma key + body distinto | `409 IDEMPOTENCY_CONFLICT`. Demo POSITIVA perfecta | 🟢 |

### Comandos exactos para reproducir pre-demo

```bash
# D1
TOKEN=$(curl -sf -X POST http://localhost:8080/auth/token -d '{}' -H 'Content-Type: application/json' | jq -r .access_token)
PMT=$(curl -sf -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -X POST http://localhost:8080/payments \
  -d '{"amount":150,"currency":"USD","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-002180000118359716"}}' \
  | jq -r .payment_id)
sleep 2
curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:8080/payments/$PMT | jq 'keys'
# NO incluye uetr, end_to_end_id, charge_bearer, exchange_rate

# D3
curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:8080/payments/$PMT | jq '.exchange_rate'
# null o ausente

# D4 — Validar CLABE placeholder
node -e "
const c='012180000118359719';
const w=[3,7,1,3,7,1,3,7,1,3,7,1,3,7,1,3,7];
const s=w.reduce((a,x,i)=>a+parseInt(c[i],10)*x,0);
console.log('expected check:', (10-(s%10))%10, 'got:', c[17]);
"
# expected: 3, got: 9 — INVÁLIDO

# D8 — Discrepancia counter vs DB
docker exec mipit-postgres psql -U mipit -d mipit -c \
  "SELECT status, COUNT(*) FROM payments GROUP BY status;"
curl -sf 'http://localhost:9090/api/v1/query?query=sum(mipit_payments_total)' | jq '.data.result'
```

## 3. Inconsistencias evidentes (14)

| # | Lugar | Inconsistencia |
|---|---|---|
| I1 | `pix-to-canonical.ts:125` vs adapter `mapper.ts:63` | `pmtId.endToEndId` canónico = `E2E-01KRVQ...`. Adapter regenera otro EndToEndId conforme BCB. **Mismo pago, dos IDs distintos** |
| I2 | `canonical.ts:208` ALIAS_TYPE_ENUM tiene `LLAVE_BREB/IBAN/BIC` | RouteEngine retorna `LLAVE_BREB/IBAN/BIC` pero seed rules sin reglas para IBAN/BIC → routing default impredecible |
| I3 | `002_seed_route_rules.sql:9` `phone_co_to_breb` con `condition_field='alias.value_prefix'` | El matcher (`route-engine.ts:51-75`) NO maneja `alias.value_prefix`. Regla **muerta** |
| I4 | `002_seed_route_rules.sql:10` `fallback_unavailable` con `availability='DOWN'` | Matcher solo acepta `'always'`/`'true'` para availability. Regla **muerta** |
| I5 | `003_seed_mapping_table.sql` + `013_seed_breb_mappings.sql` declaran 14 transformaciones | Solo 7 en `applyTransformation` switch. 7 (`prefix_PIX/strip_prefix/parse_decimal/convert_to_BRL/convert_to_MXN/truncate_140/cop_integer/map_status/regenerate_if_invalid/route_by_format`) fallan al default y no transforman nada. **Traducción "data-driven" no existe** |
| I6 | `canonical-to-breb.ts:50` `canonical.amount.value.toFixed(2)` | COP debe ser entero (`fx/currency-metadata.ts:18`). Manda `420000.00` en lugar de `420000`. Mock acepta solo 2 decimales — bug enmascarado. Real BanRep rechazaría |
| I7 | UI `RAIL_CONFIG['BRE_B']` aliasPattern | `/^(BREB-\+57\d{10}|\d{9,10}-\d|email)$/` mezcla prefijo BREB- solo para phone. Core (`payment-request.ts:39-43`) exige prefijo siempre |
| I8 | `payment.repository.ts:48-61` create() acepta 30+ params posicionales con `(payment as any).end_to_end_id ?? null` | Cualquier rename rompe en silencio. Sin type-safety |
| I9 | `wave-1-4-verification` doc afirma "mipit_payments_received_total" | Nombre real `mipit_payments_total`. Doc desincronizado |
| I10 | `local-demo.md:38-42` topología | Dice exchange `mipit.payments` + queue `q.adapter.pix`. Real: queue `payments.route.pix`. Runbook incorrecto |
| I11 | `tracing.ts:6` `traceId = ulid()` | Logs Pino tienen `trace_id` OTel hex. Request-scoped `traceId` es ULID. **Dos campos mismo nombre, dos valores** |
| I12 | UI `lib/types.ts:4-17` PaymentStatus omite `NORMALIZED` | Backend persiste 15 estados, UI conoce 14. Pago en NORMALIZED → "Recibido" default o crash en `STATUS_CONFIG[currentStatus]?.step` |
| I13 | Logger redact `req.headers["idempotency-key"]` | Auditar replay con logs imposible. Solo por payment_id |
| I14 | `alertmanager.yml:24` apunta a `/webhooks/alertmanager` no implementado | AlertManager hace 404 |

## 4. Datos seed problemáticos

### `seed_route_rules.sql`
```sql
('phone_co_to_breb',      'alias.value_prefix',   '+57',         'BRE_B',  3, ...)
('fallback_unavailable',  'availability',         'DOWN',        'FAILED', 9, ...)
```
Inertes (I3/I4). Si panel hace `SELECT * FROM route_rules` y prueba alias `+573001234567` esperando regla 3, se activa accidentally por `inferAliasType` → `LLAVE_BREB` → matchea `llave_breb_to_breb`. Funciona por accidente.

### `seed_mapping_table.sql`
13 rows con transformaciones inexistentes en `applyTransformation`:
- `PIX TO_CANONICAL chaveOrigem → debtor.account_id` con `prefix_PIX` ❌
- `PIX FROM_CANONICAL amount.value → valor` con `convert_to_BRL` ❌
- `SPEI TO_CANONICAL monto → amount.value` con `parse_decimal` ❌
- `SPEI FROM_CANONICAL debtor.account_id → clabe_origen` con `strip_prefix` ❌

### `seed_breb_mappings.sql`
```sql
('BRE_B','FROM_CANONICAL','amount.value','valor.original','cop_integer',NULL,'COP no centavos')
```
Nota dice "COP no centavos" pero código manda `.toFixed(2)` siempre (`canonical-to-breb.ts:50`). **Regla y código se contradicen explícitamente** en el repo.

### `001_schema.sql:25,75-76`
`reference TEXT DEFAULT 'MIPIT-POC'` → "test data en producción". Migración 008 lo elimina.

## 5. Brechas claim vs realidad (10)

| # | Claim | Realidad |
|---|---|---|
| B1 | CONTEXTO:140 "Webhooks: POST /webhooks/alertmanager" | Endpoint NO existe. AlertManager 404 |
| B2 | LIMITATIONS:62 "Circuit breaker por riel — implementado" | Wired solo en `ui-proxy` (`ui-proxy.ts:15`). Pipeline NO lo invoca |
| B3 | LIMITATIONS:64 "Compensación — best-effort en mocks" | No llama a mocks. Solo cambio de estado DB + audit (`compensation-service.ts:73-89`) |
| B4 | local-demo:80 "DLQ handler vuelve a publicar cuando adapter regrese" | `dlq-handler.ts:75-78` solo marca DEAD_LETTER + "manual review". Sin re-publicación |
| B5 | LIMITATIONS:72 "métricas unificadas `mipit_adapter_*`" | Cierto pero conviven con métricas LEGACY per-rail (`mipit_adapter_pix_payments_total`). Double registry → cardinalidad inflada |
| B6 | CONTEXTO:73 "Inferir rail origen del alias" | Regex BRE_B (`payment-pipeline.ts:326`) acepta `+57\d{10}` SIN `3` mobile-only. Validación mobile-only solo en mock |
| B7 | LIMITATIONS:53 "Idempotency-Key TTL 24h, sweeper background" | OK, pero sweeper depende del job. Si core reinicia, claims pendientes sin INSERT viven hasta TTL |
| B8 | wave-1-4-verification:127 "smoke 3/3 prueba más relevante" | Smoke usa alias prefijados (fast-path). Formatos reales (CPF puro, CLABE 18, NIT `xxx-x`) NO cubiertos por smoke diario |
| B9 | CONTEXTO:101 "Tracing OTel→Jaeger; trace_id propagado" | UI usa ULID, no OTel hex. Propagación a Jaeger via SDK auto-instrumenting, pero ID visible al user ≠ ID en Jaeger |
| B10 | local-demo:31 "Grafana admin/mipit2026" vs task prompt "admin/admin" | docker-compose.yml:205 = `mipit2026`. Demo asumiendo admin/admin se queda bloqueada |

## 6. Hardening top 15 pre-demo (≤2h cada uno)

| # | Cambio | Esfuerzo | Por qué |
|---|---|---|---|
| H1 | `payments.ts`: añadir al GET response los campos `uetr/end_to_end_id/charge_bearer/interbank_settlement_date/instructed_amount/instructed_currency/settlement_amount/settlement_currency/exchange_rate` | 20 min | **Arregla D1+D3+I8**. Bug visible de mayor impacto |
| H2 | `payments/[id]/page.tsx:140`: cambiar Jaeger link a `?service=mipit-core&tags=%7B%22mipit.trace_id%22%3A%22${trace_id}%22%7D` | 15 min | Arregla D2 |
| H3 | Corregir CLABE placeholder a `012180000118359716` en `simulate/page.tsx:36` | 5 min | Arregla D4 |
| H4 | Disabled `SWIFT_MT103/ISO20022_MX/ACH_NACHA/FEDNOW` en RailPicker | 20 min | Arregla D5 |
| H5 | Implementar `POST /webhooks/alertmanager` en core | 30 min | Arregla B1 |
| H6 | Borrar UI stubs con TODO visible (`pix-form.tsx`, `spei-form.tsx`, etc.) o quitar el texto TODO del JSX | 30 min | Arregla D7 |
| H7 | Histogram buckets a `[10,50,100,250,500,1000,2500,5000,10000,30000]` | 5 min | Arregla D9+Q29 |
| H8 | Borrar reglas muertas en `seed_route_rules.sql` o implementar matcher | 20 min | Arregla I3+I4 |
| H9 | `NODE_ENV=production` + token issuer out-of-band; rotar JWT_SECRET fuera del repo | 30 min | Arregla Q15 |
| H10 | `recordPayment(status, originRail, '-')` después de cada `updateStatus(FAILED)` en pipeline | 20 min | Arregla D8+Q25 |
| H11 | `canonical-to-breb.ts:50` → `formatAmount(amount, 'COP')` | 10 min | Arregla I6 |
| H12 | UI `types.ts` + `constants.ts`: agregar NORMALIZED | 10 min | Arregla I12 |
| H13 | Documentar `seed_mapping_table.sql` como descriptivo, no policy engine | 20 min | Mitiga Q4+I5 |
| H14 | Pipeline regex BRE_B → `/^\+573\d{9}$/` | 5 min | Arregla B6 |
| H15 | `simulate/page.tsx:104`: default `currency` a moneda nativa del riel origen | 15 min | Evita demos con USD→PIX accidental |

## 7. Demos "winning" (5 escenarios bullet-proof)

### W1. Idempotency end-to-end con replay seguro
SHA256 + 409 conflict. Demo positiva, código bien hecho visible.

```bash
TOKEN=$(curl -sf -X POST http://localhost:8080/auth/token -d '{}' -H 'Content-Type: application/json' | jq -r .access_token)
KEY="DEMO-IDEMP-$(date +%s)"
# 1ª: 201 Created
# 2ª (mismo key+body): 201 con mismo payment_id (replay)
# 3ª (mismo key, body distinto): 409 IDEMPOTENCY_CONFLICT
```
**Mostrar:** tabla `idempotency_keys` con `request_hash` SHA-256 distinto entre pruebas.

### W2. Smoke 3-rail-pairs (PIX→SPEI, SPEI→BRE_B, BRE_B→PIX)
Prueba más limpia de interoperabilidad. Validado en `wave-1-4-verification`.

### W3. Inspector ISO 20022 (Original/Canónico/Traducido side-by-side)
`MessageInspector` muestra los 3 payloads JSON pretty-printed. Hub-and-spoke entendible en 5s.

**Preparación:** verificar (post H1) que `pmtId.uetr`, `chrgBr`, `amount.currency=MXN`, `fx.local_amount` aparezcan en el "Canónico".

### W4. Validación checksums reales (CPF mod-11, CLABE mod-10, NIT mod-11)
Generators producen muestras válidas; CPF inválido es rechazado con código `AC03`.

### W5. FX cross-currency BRL→COP con audit-trail completo
**Requiere H1 aplicado primero**. Mostrar DB row con `instructed_amount=1000 BRL`, `settlement_amount=4180000 COP`, audit_events ms-a-ms.

**Cuidado:** mencionar proactivamente "usamos FALLBACK rate hardcodeado; producción usaría Open Exchange Rates real (`fx-service.ts:48`)".

## Cierre

**Sólido y mostrar primero:**
- Pipeline 8-pasos persistente con audit
- Idempotency criptográfica
- UETR + ChrgBr + IntrBkSttlmDt persistidos (post H1 visibles en API)
- Smoke 3/3 rail-pairs COMPLETED
- Generators con checksums reales
- PII redaction logs
- Publisher confirms wired

**NO demostrar sin parchar:**
- Click Jaeger (link roto, H2)
- Bloque ISO 20022/FX en UI (response API no surface, H1)
- Compensación real (no-op, B3)
- Alert → core flow (endpoint no existe, H5)
- Grafana success rate si hubo failures pipeline (H10)
- Carga >20 TPS PIX (429)
- `/simulate` con placeholders tal cual (H3)

**Las 4 horas más rentables pre-demo:** H1+H2+H3+H4+H5+H7+H10 (≈2h sumadas).

**Recomendación final:** anticipar el matiz "mapping_table decorativo" como "decisión de diseño: BD documenta catálogo de transformaciones para auditoría humana; implementación en TypeScript tipado para performance e invariantes. **Mapping-as-documentation**, no mapping-as-engine". Mejor que dejar que el panel lo descubra y lo etiquete como "vaporware".
