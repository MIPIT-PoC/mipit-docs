# Auditoría 2 — Listado completo de hallazgos + plan de Waves 5–8

> Documento síntesis preparado por el equipo: lista densa de los 88 hallazgos
> de la segunda auditoría y la organización en Waves 5–8. Versión de referencia
> rápida; el detalle vive en `audits/AUDITORIA-2-2026-05-17.md` (maestro) +
> `audits/raw/audit-2-2026-05-17/A{1,3,4,5}-*.md` (raw por agente) +
> `evidence/AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` (A2).

---

## Parte I — Listado completo de hallazgos (88)

### A1 — Spec compliance ISO 20022 (35)

#### pacs.008.001.10 modelado (16)

| ID | Sev | Hallazgo | File:line |
|---|---|---|---|
| N-001 | 🔴 CRÍT | adapters NO emiten `pacs002.txSts` enriquecido aunque el schema existe | `consumer.ts:76` + workers |
| N-002 | 🟠 ALTO | rejection codes BACEN/CECOBAN/BREB no mapeados a `ExternalStatusReason1Code` ISO | `response-mapper.ts:32-37` |
| N-003 | 🟠 ALTO | `CtgyPurp` ausente — PIX `tipo` y SPEI `tipoPago` se pierden | `canonical.ts:213`, `mapper.ts:99` |
| N-004 | 🟠 ALTO | `LclInstrm.Prtry` solo en FedNow, faltante en 5 emisores | `canonical-to-{pix,spei,breb,iso20022-mx,mt103,nacha}.ts` |
| N-005 | 🟠 ALTO | `nbOfTxs/ctrlSum/ttlIntrBkSttlmAmt` declarados pero no poblados | `payment-pipeline.ts:104-116` |
| N-006 | 🟠 ALTO | `XchgRate` como string plano, no objeto ISO con `RateTp/CtrctId` | `canonical-to-iso20022-mx.ts:75` |
| N-007 | 🟡 MED | `RgltryRptg` ausente + threshold USD 10k no flagged | — |
| N-008 | 🟡 MED | `IntrmyAgt1/2/3` ausentes — flujos corresponsales >2 hops | — |
| N-009 | 🟡 MED | `UltmtDbtr/UltmtCdtr` ausentes — PSPs fintech (Nequi/Daviplata) mal modelados | — |
| N-010 | 🟢 BAJO | `ChrgsInf` ausente | — |
| N-011 | 🟢 BAJO | `mappings/canonical-fields.md` stale | `mipit-docs/mappings/canonical-fields.md` |
| N-012 | 🟡 MED | BREB drift: core 8-dig legacy vs adapter 4-dig oficial | `breb-to-canonical.ts:99-109` |
| N-013 | 🟡 MED | Bre-B `ALIAS` regex mismatch core vs adapter (`@` prefix) | `breb-to-canonical.ts:129` vs `mapper.ts:75` |
| N-014 | 🟡 MED | `canonical-to-pix.ts:20` reusa `endToEndId` raw | `canonical-to-{pix,spei,breb}.ts` |
| N-015 | 🟢 BAJO | `status` enum mezcla 15 internos con ISO | `canonical.ts:15-32,219` |
| N-016 | 🟡 MED | `pacs002.schema.ts:55` solo acepta `.10/.08` (ISO publicó `.12`) | `pacs002.schema.ts:55` |

#### Mensajería complementaria (4)

| ID | Sev | Hallazgo | File:line |
|---|---|---|---|
| M-001 | 🟠 ALTO | pacs.002 nunca emitido al exterior (solo JSON propietario interno) | `consumer.ts:43-163` |
| M-002 | 🟠 ALTO | `/compensate` no emite pacs.004 — solo cambia estado DB | `compensation-service.ts:73-87` |
| M-003 | 🟡 MED | camt.054 (BankToCustomerDebitCreditNotification) ausente | — |
| M-004 | 🟢 BAJO | Reconciliation no consume camt.053 | `reconciliation-service.ts` |

#### Updates por riel 2024-2026 (15) — algunos [VERIFY]

| ID | Sev | Hallazgo |
|---|---|---|
| R-001 | 🟠 ALTO | [VERIFY] Pix Automático (BCB Res. 304/2023) + Pix Garantido no modelados |
| R-002 | 🟡 MED | MED (Mecanismo Especial Devolução) no modelado como flujo |
| R-003 | 🟢 BAJO | PIX límite BRL 1k PF / 20k PJ no chequeado |
| R-004 | 🟢 BAJO | PIX mock sin `/v2/dict/{key}` |
| R-005 | 🟠 ALTO | [VERIFY] DiMo (Banxico oct-2024) no modelado en SPEI |
| R-006 | 🟡 MED | [VERIFY] `isSpeiWindowOpen()` aún L-V 07:00-17:30 (SPEI migró 24/7) |
| R-007 | 🟢 BAJO | `SPEI_BANXICO_CODES.MIPIT_SIM='90999'` colisiona rango PSPs autorizados |
| R-008 | 🟡 MED | SPEI `tipoPago: 1` hardcoded |
| R-009 | 🟠 ALTO | `breb-to-canonical.ts:18-24` miente "(BanRep spec)" para códigos inventados |
| R-010 | 🟠 ALTO | [VERIFY] Bre-B debería emitir códigos ISO derivados |
| R-011 | 🟡 MED | Bre-B directorio (alias→PSP) no existe |
| R-012 | 🟢 BAJO | BREB límites COP inventados |
| R-013 | 🟡 MED | FedNow translator aplica FX pero FedNow es USD-domestic-only |
| R-014 | 🟡 MED | MT103 hardcodea `detailsOfCharges: 'SHA'` ignorando ChrgBr |
| R-015 | 🟡 MED | NACHA padding bugs persisten (9 vs 10 chars) |

### A2 — Cumplimiento de tesis (4)

| ID | Sev | Hallazgo |
|---|---|---|
| T-001 | 🟠 ALTO | **RF19** (export CSV/JSON) único requisito no cumplido sin scope-out |
| T-002 | 🟡 MED | **Drift alcance**: FedNow degradado a translator-only, sustituido por Bre-B sin sección "Cambios al alcance" en tesis formal |
| T-003 | 🟡 MED | **RNF no re-medidos** en Wave 4 (100 TPS / 99.9% / 15s validados solo en histórico 2026-05-15) |
| T-004 | 🟡 MED | Endpoints `/payments` vs `/transactions` del SRS — divergencia sin declarar |

### A3 — Code quality + architecture (25)

#### Críticos (5)

| ID | Sev | Hallazgo |
|---|---|---|
| F01 | 🔴 CRÍT | SSE expone PII sin autenticación (`/events/payments`) |
| F02 | 🟠 ALTO | Double-registered RabbitMQ consumers tras reconnect |
| F03 | 🟠 ALTO | `reconciliation.findSince` carga toda tabla en memoria (sin LIMIT) |
| F04 | 🟠 ALTO | DLQ requeue infinito sobre poison message |
| F05 | 🟡 MED | Race en idempotency 2nd lookup → respuesta sintética hardcoded |

#### Type safety (3)

| ID | Sev | Hallazgo |
|---|---|---|
| F25 | 🟡 MED | 20 `as any` ocultando model gaps (ISO 20022 fields nunca promovidos a `PaymentIntent`) |
| F26 | 🟢 BAJO | Type assertion `traceId` 4x sin module augmentation Fastify |
| F27 | 🟢 BAJO | 3 `eslint-disable any` en workers de adapters |

#### Arquitectura / duplicación (4)

| ID | Sev | Hallazgo |
|---|---|---|
| F08 | 🟠 ALTO | 3 adapters duplicados 95-97% (~300 LOC) |
| F28 | 🟡 MED | `BreBPermanentError` solo en BREB; PIX/SPEI sin distinción transient vs permanent |
| F29 | 🟡 MED | 4 singletons module-level (`db.ts:4`, `sse.ts:26`, `health.ts:21`, `circuit-breaker.ts:203`) bloquean tests paralelos |
| F30 | 🟢 BAJO | `TERMINAL_STATUSES` duplicado en `webhook.service.ts:22` y literal en `consumer.ts:149` |

#### Concurrency (2)

| ID | Sev | Hallazgo |
|---|---|---|
| F22 | 🟢 BAJO | Circuit breaker HALF_OPEN sin probe-mutex |
| F31 | 🟡 MED | Pipeline `catch` deja status intermedio si `updateStatus(FAILED)` falla |

#### Error handling (3)

| ID | Sev | Hallazgo |
|---|---|---|
| F12 | 🟡 MED | Consumer `nack(false, false)` sin distinción transient/permanent |
| F32 | 🟡 MED | Fastify validation errors → 500 silencioso |
| F33 | 🟡 MED | `FxService.getRates()` swallow errors + reintenta sin límite |

#### Performance / Observability (8)

| ID | Sev | Hallazgo |
|---|---|---|
| F06 | 🟡 MED | Timer leaks (rate-limit, reconciliation, SSE) sin `.unref()` |
| F10 | 🟡 MED | Recording rule `payment_latency:p95` mezcla todos los stages |
| F17 | 🟡 MED | Trace context no propagado en RabbitMQ envelope headers |
| F18 | 🟡 MED | Health adapters superficial (no chequea RMQ exchange) |
| F20 | 🟢 BAJO | `findPercentile` no interpola buckets |
| F23 | 🟢 BAJO | Pipeline emite >12 logs/request |
| F34 | 🟡 MED | Histogram buckets adapters mal escalados (cap 10s, latencias 80-450ms) |
| F35 | 🟡 MED | `HighLatency` alert threshold 10s para "instant payments" |
| F36 | 🟢 BAJO | `findRecent` sin índice composite `(status, created_at DESC)` |

#### Security (3, además de F01)

| ID | Sev | Hallazgo |
|---|---|---|
| F09 | 🟠 ALTO | SSRF risk: webhook URLs sin allowlist |
| F37 | 🟢 BAJO | SSE `Access-Control-Allow-Origin: *` choca con CORS allowlist global |
| F38 | 🟢 BAJO | Sin CSRF token (asume Authorization header, no cookies) |

#### Dependencies (3)

| ID | Sev | Hallazgo |
|---|---|---|
| F11 | 🟡 MED | OpenTelemetry version drift core vs adapters (6+ meses) |
| F13 | 🟢 BAJO | mipit-ui 7 deps unused (radix-ui x5 + CVA + ts-node) |
| F16 | 🟢 BAJO | `mipit-observability/alerting/rules.yaml` redundante (legacy de P07) |

#### Test coverage (3)

| ID | Sev | Hallazgo |
|---|---|---|
| F21 | 🟠 ALTO | Sin tests unit para reconnect/CB/webhook/FX/reconciliation/compensation/DLQ |
| F39 | 🟡 MED | mipit-adapter-breb tests (3) << pix/spei (8/9) |
| F40 | 🟢 BAJO | `--forceExit --detectOpenHandles` oculta timer leaks en jest |

#### Misc (4)

| ID | Sev | Hallazgo |
|---|---|---|
| F14 | 🟢 BAJO | 5 UI stub components con literal `TODO:` en JSX visible |
| F15 | 🟢 BAJO | Dead code ~150 LOC (`handleFailedMessage`, `shouldDeadLetter`, helpers audit unused, `recordIdempotencyHit` counter zombie) |
| F19 | 🟢 BAJO | XSS sanitizer regex demasiado agresivo (`sanitize.ts:19-23`) |
| F24 | 🟡 MED | `analytics/reconciliation` GET dispara DB scan sin cache |

### A4 — Red team / defensa (24)

#### 14 inconsistencias evidentes

| ID | Sev | Hallazgo |
|---|---|---|
| I1 | 🟠 ALTO | EndToEndId canónico `E2E-${ulid()}` vs adapter regenera otro → mismo pago 2 IDs |
| I2 | 🟡 MED | `RouteEngine.inferAliasType` retorna `IBAN/BIC` pero seed rules sin reglas |
| I3 | 🟡 MED | Regla `phone_co_to_breb` con `alias.value_prefix` no implementado en matcher (muerta) |
| I4 | 🟡 MED | Regla `fallback_unavailable` con `'DOWN'` no implementada (muerta) |
| I5 | 🔴 CRÍT | `mapping_table` decorativa — 7 de 14 transformaciones no implementadas en `applyTransformation` |
| I6 | 🟠 ALTO | `canonical-to-breb.ts:50` usa `.toFixed(2)` para COP que debe ser entero |
| I7 | 🟡 MED | UI `RAIL_CONFIG.BRE_B.aliasPattern` mezcla prefijo `BREB-` solo para phone |
| I8 | 🟡 MED | `payment.repository.ts:48-61` create() con 30+ params posicionales y `(payment as any)` |
| I9 | 🟢 BAJO | wave-1-4-verification doc afirma `mipit_payments_received_total` (nombre real: `mipit_payments_total`) |
| I10 | 🟢 BAJO | `local-demo.md:38-42` describe queue `q.adapter.pix` (real: `payments.route.pix`) |
| I11 | 🟡 MED | `tracing.ts:6` genera `traceId` como ULID; logs Pino tienen `trace_id` OTel hex — dos campos mismo nombre, dos valores |
| I12 | 🟠 ALTO | UI omite `NORMALIZED` del PaymentStatus (UI 13 vs DB+core 15) |
| I13 | 🟢 BAJO | Logger redact `idempotency-key` header — auditar replay imposible solo por logs |
| I14 | 🔴 CRÍT | AlertManager → `/webhooks/alertmanager` no implementado en core |

#### 10 demos en vivo con riesgo (D1-D10)

| ID | Sev | Demo con riesgo |
|---|---|---|
| D1 | 🔴 CRÍT | `GET /payments/:id` omite UETR/EndToEndId/ChrgBr/IntrBkSttlmDt — UI vacía |
| D2 | 🔴 CRÍT | Click "Ver en Jaeger" usa ULID → "Trace not found" |
| D3 | 🔴 CRÍT | Bloque FX en UI nunca aparece (response API omite `exchange_rate`) |
| D4 | 🔴 CRÍT | CLABE placeholder `012180000118359719` no pasa mod-10 |
| D5 | 🔴 CRÍT | Form `/simulate` permite SWIFT/NACHA/FedNow sin adapter activo |
| D6 | 🟡 MED | `docker stop adapter-spei` → pago QUEUED 1h sin retry |
| D7 | 🟡 MED | 5 componentes UI renderizan literal `TODO:` en JSX |
| D8 | 🔴 CRÍT | Grafana success rate inflado (counter no cuenta failures dentro pipeline) |
| D9 | 🟡 MED | Histogram cap 2500ms → p99 = NaN o `+Inf` |
| D10 | 🟢 OK | Idempotency con 409 — demo positiva |

### A5 — Inconsistencias internas (14)

#### Canónico (7)

| ID | Sev | Hallazgo |
|---|---|---|
| A5-A1 | 🔴 CRÍT | `canonical-fields.md` describe canónico FLAT (`msg_id/alias_type CPF/CNPJ/...`) que no existe |
| A5-A2 | 🔴 CRÍT | 4 CSV mappings (`canonical-to-pix.csv` etc.) usan modelo flat antiguo |
| A5-A3 | 🟠 ALTO | OpenAPI `CanonicalPacs008` usa `intrBkSttlmAmt + rmtInf.ustrd[]`; código usa `amount + remittanceInfo` string |
| A5-A4 | 🟡 MED | OpenAPI omite `fx/rail_ack/status/trace_id/reference/purpose` |
| A5-A5 | 🟠 ALTO | `translation-layer.md:79` omite `LLAVE_BREB` del `alias.type` enum |
| A5-A6 | 🟡 MED | `translation-layer.md:65`: `institutionCode 3 dígitos` vs código `max(8)` |
| A5-A7 | 🟡 MED | OpenAPI `CanonicalParty` totalmente desalineado del schema real |

#### Coherencia ADRs (9)

| ID | Sev | Hallazgo |
|---|---|---|
| A5-D1 | 🔴 CRÍT | AlertManager → endpoint no existe (= F14, I14) |
| A5-D2 | 🟠 ALTO | ADR-006: Kysely/Knex; código usa `pg` raw |
| A5-D3 | 🟡 MED | ADR-006: migraciones por core; real: `scripts/migrate.sh` externo |
| A5-D4 | 🟡 MED | Sin scripts rollback `*-down.sql` |
| A5-D5 | 🟢 BAJO | ADR-002 `RmtInf.Ustrd[]`; código single string |
| A5-D6 | 🟠 ALTO | Adapters usan `createChannel()` plain (sin confirms), core usa ConfirmChannel — asimétrico |
| A5-D7 | 🟠 ALTO | ADR-007 lista módulo "state-machine" que no existe |
| A5-D8 | 🟢 BAJO | ADR-008: "logs recolectados por Docker" — sin Loki/Promtail real |
| A5-D9 | 🟡 MED | `architecture-overview.md`: "reglas YAML"; real: en Postgres |

#### Tests placebo (3 grupos)

| ID | Sev | Hallazgo |
|---|---|---|
| A5-E1 | 🔴 CRÍT | 5 tests con `expect(true).toBe(true)` + 4 archivos TODO-only en `mipit-testkit/tests/{integration,e2e}` |
| A5-E2 | 🟠 ALTO | `translation.test.ts:71-94` asserts sobre `detail.canonical?.debtor?.rail` campo inexistente |
| A5-E3 | 🟡 MED | Datasets PIX con `"currency": "USD"` (debería BRL) en `pix-valid-01.json`, etc. |

#### Mock fidelity gaps NO en LIMITATIONS (7)

| ID | Sev | Hallazgo |
|---|---|---|
| A5-F1 | 🟠 ALTO | `rail_ack.status` 3-way: core 4 valores / UI 3 sin PENDING / OpenAPI 3 sin ERROR |
| A5-F2 | 🟠 ALTO | PIX mock endpoint `/spi/v2/pagamentos` inventado (real BCB es XML over RSFN) — no en LIMITATIONS |
| A5-F3 | 🟠 ALTO | BREB error codes BREB001-005 inventados — no en LIMITATIONS |
| A5-F4 | 🟡 MED | SPEI OAuth2 ficcional (real es TCP/SSL con CECOBAN) |
| A5-F5 | 🟡 MED | OAuth secrets hardcoded en 6 archivos (3 adapters × {client.ts, oauth-mock.ts}) |
| A5-F6 | 🟡 MED | Bre-B mobile-only en mock pero core `payment-request.ts` acepta `+57\d{10}` (sin restricción `3`) |
| A5-F7 | 🟢 BAJO | PIX mock endpoint legacy `/pix/payments` (`mock-server.ts:352-`) |

#### Deuda variada

| ID | Sev | Hallazgo |
|---|---|---|
| A5-G1 | 🟠 ALTO | `mipit-core/src/messaging/rabbitmq.ts` dead code (no importado) |
| A5-G2 | 🟢 BAJO | 36 TODOs activos sin tracking |
| A5-G3 | 🟡 MED | 3 `@deprecated` sin tracking issue |
| A5-G4 | 🟢 BAJO | `test_8.md`, `test_7.md` files in `mipit-core/src/` root |
| A5-H1 | 🟡 MED | Rail prefijos `PIX-/SPEI-/BREB-` repetidos en 8+ archivos |
| A5-H2 | 🟠 ALTO | OAuth secrets hardcoded x6 |
| A5-H3 | 🟢 BAJO | TTL 5min duplicado (`mapping-loader.ts:10`, `fx-service.ts:56`) |
| A5-H4 | 🟡 MED | Error codes hardcoded sin enum (BREB001-005, AM01/AC01/AB03..., R01-R04/LIM) |
| A5-I1 | 🟡 MED | `@opentelemetry/exporter-prometheus` orfan en core |
| A5-I2 | 🟡 MED | `@opentelemetry/api` faltante en core (transitive abuse) |
| A5-I3 | 🟢 BAJO | 7 deps orfan en mipit-ui (radix-ui×5 + CVA + ts-node) |
| A5-I4 | 🟢 BAJO | ts-node orfan en 4 repos más (adapters+testkit) — todos usan tsx |
| A5-C1 | 🟠 ALTO | SPEI window 3-way: docs+core `06:00-17:55` vs mock `07:00-17:30` |

---

## Parte II — Plan de Waves 5–8

### 🌊 Wave 5 — Hardening pre-demo

**Tiempo:** ≈3 horas · **Foco:** las 14 brechas visibles que un panel descubriría en demo · **Estado:** ✅ Cerrada (entregada 2026-05-17)

| Orden | Ticket | Cambio | Tiempo | Resuelve |
|---|---|---|---|---|
| W5.1 | HARD-001 | `GET /payments/:id` surface UETR / EndToEndId / ChrgBr / IntrBkSttlmDt / FX block / terminal timestamps | 20 min | C5, D1, D3, Q30, I8 |
| W5.2 | HARD-002 | Implementar `POST /webhooks/alertmanager` (público, AlertManager v4) | 30 min | C4, B1, Q26, I14, A5-D1 |
| W5.3 | HARD-003 | UI Jaeger link via search-by-attribute (no `/trace/<id>`) | 15 min | C7, D2, Q27, I11 |
| W5.4 | HARD-004 | Pipeline: `recordPayment(FAILED, originRail, 'UNKNOWN')` en catch | 20 min | D8, Q25 |
| W5.5 | HARD-005 | Histogram buckets `[10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000]` | 5 min | D9, F34, F35, Q29 |
| W5.6 | HARD-006 | UI agrega `NORMALIZED` + STATUS_CONFIG fallback neutral | 10 min | C8, B1, I12 |
| W5.7 | HARD-007 | CLABE placeholders válidos mod-10 (`012180000118359713`, `002180012345678906`) | 5 min | D4 |
| W5.8 | HARD-008 | `/simulate` restringe a productivos + banner a `/translator` para case-study | 20 min | D5 |
| W5.9 | HARD-009 | SSE handlers exigen `?token=<jwt>` (401 sin token) | 20 min | C1, F01 |
| W5.10 | HARD-010 | `canonical-to-breb` usa `formatAmount('COP')` (entero, no `.toFixed(2)`) | 10 min | I6 |
| W5.11 | HARD-011 | Pipeline + payment-request regex BRE_B mobile-only `+573` | 5 min | A5-F6, B6 |
| W5.12 | HARD-012 | Borrar 4 UI stubs zombie + limpiar TODO de `payment-status-badge` | 30 min | F14, D7 |
| W5.13 | HARD-013 | Corregir header `breb-to-canonical.ts` (`BREB001-005` son MIPIT-invented, no BanRep) | 5 min | R-009, A5-F3 |
| W5.14 | HARD-014 | Documentar `seed_mapping_table.sql` como "mapping-as-documentation, not policy engine" | 20 min | C3, I5, Q4 |

**Criterios de éxito Wave 5 (todos cumplidos):**

- ✅ Smoke 3/3 sigue COMPLETED
- ✅ Demo de payment detail muestra UETR + ChrgBr + FX
- ✅ Link Jaeger abre traza correcta
- ✅ AlertManager → core sin 404 en logs
- ✅ Grafana success rate matchea DB COUNT
- ✅ SSE 401 sin token, 200 con token
- ✅ UI tests 65/65

---

### 🌊 Wave 6 — ISO 20022 Spec Compliance

**Tiempo:** ≈3.5 días (entregada en una sesión por densidad de fixes pequeños) · **Foco:** robustecer claim "MIPIT habla ISO 20022 pacs.008/.002/.004" a nivel byte · **Estado:** ✅ Cerrada (entregada 2026-05-17 noche)

| Orden | Ticket | Cambio | Tiempo | Resuelve |
|---|---|---|---|---|
| W6.1 | ISO-001 | Adapters emiten `pacs002` enriquecido (`orgnlEndToEndId`, `orgnlUetr`, `txSts`, `stsRsnInf`) | 1 día | N-001, M-001, C6 |
| W6.2 | ISO-002 | `rail-rejection-mapping.ts`: BACEN/CECOBAN/BREB → ISO `ExternalStatusReason1Code` (preserva `Rsn.Prtry`) | medio día | N-002, R-010 |
| W6.3 | ISO-003 | `canonical.ctgyPurp` propagado canónico → SPEI `tipoPago` (CASH/SALA/TAXS/...) | medio día | N-003, R-008 |
| W6.4 | ISO-004 | `pacs004.schema.ts` + `compensation-service` emite pacs.004 real (RtrId, OrgnlUETR, RtrRsnInf) | 1 día | M-002, C2 |
| W6.5 | ISO-005 | Fidelity batch: pipeline `nbOfTxs/ctrlSum` + `XchgRate` objeto + `LclInstrm` + MT103 `chrgBr→detailsOfCharges` | medio día | N-004/5/6, R-014 |
| W6.6 | ISO-006 | `pacs002.schema.orgnlMsgNmId` regex `/^pacs\.008\.001\.\d{2}$/` (forward-compat `.12`) | 5 min | N-016 |
| W6.7 | ISO-007 | Unificar BREB entity codes a 4-dig Superfinanciera + mensajes mock | 30 min | N-012 |
| W6.8 | ISO-008 | Bre-B ALIAS regex unified core+adapter (`@`-prefix per TR-002) | 30 min | N-013 |
| W6.9 | ISO-009 | `canonical-to-{pix,spei}` regenera `endToEndId`/`claveRastreo` si formato no-rail | 30 min | N-014 |
| W6.10 | ISO-010 | FedNow translator throw si `currency !== USD` (Fed OP §3.1) | 10 min | R-013 |
| W6.11 | ISO-011 | NACHA File Header layout correcto byte-exact + fixture test | medio día | R-015 |
| W6.12 | ISO-012 | LIMITATIONS.md §11 (scope-outs ISO) + §12 (case-study rails) | medio día | N-007/8/9/10, R-001/2/5/11, M-003 |
| W6.13 | ISO-013 | Borrar `mappings/canonical-fields.md` + 4 CSVs legacy | medio día | A5-A1/A2, N-011 |

**Criterios de éxito Wave 6 (todos cumplidos):**

- ✅ ACK trae `pacs002` con `txSts` ISO real
- ✅ Compensate genera pacs.004 visible
- ✅ ctgyPurp propaga (PIX SALA → SPEI tipoPago=5)
- ✅ pacs.008 generado tiene `nbOfTxs/ctrlSum/XchgRate-objeto/LclInstrm`
- ✅ Core 310/310 unit tests
- ✅ LIMITATIONS.md actualizado

---

### 🌊 Wave 7 — Limpieza y Single Source of Truth (Días 6-7, ~1.5 días)

**Objetivo:** eliminar deuda visible, normalizar nombres, reducir confusión.
**Branch sugerido:** `Auditoria-Claude` (directo, mismo patrón W5/W6).
**Estado:** ⏳ Planeada.

| Orden | Ticket | Cambio | Tiempo | Resuelve |
|---|---|---|---|---|
| W7.1 | SOT-001 | Crear paquete `@mipit/shared-types` con `RAILS`, `PAYMENT_STATUS_ENUM`, `ALIAS_TYPE_ENUM`, `rail_ack.status` enum unificado. Importar en core + UI + adapters | medio día | A5-F1, B1/C8, F30 |
| W7.2 | SOT-002 | `parseRailAlias(alias)` helper → `{rail, value}`. Refactor 8+ sites de `.startsWith('PIX-')` | medio día | A5-H1, C1 enums |
| W7.3 | CLEAN-001 | Borrar dead code: `mipit-core/src/messaging/rabbitmq.ts`, `handleFailedMessage/shouldDeadLetter` (`dlq-handler.ts:94-146`), helpers audit unused, `recordIdempotencyHit/idempotencyHits` métrica zombie | 30 min | A5-G1, F15 |
| W7.4 | CLEAN-002 | Borrar `mipit-observability/alerting/rules.yaml` legacy | 5 min | F16 |
| W7.5 | CLEAN-003 | `npm uninstall` deps orfanas: `@radix-ui/react-{dialog,label,select,slot,toast} class-variance-authority` en UI; `ts-node` en 5 repos que usan tsx; `@opentelemetry/exporter-prometheus` en core | 30 min | F13, A5-I3, A5-I4, A5-I1 |
| W7.6 | CLEAN-004 | Agregar `@opentelemetry/api` a `package.json` de core (eliminar transitive abuse) | 5 min | A5-I2 |
| W7.7 | CLEAN-005 | OAuth secrets en env vars: `PIX_OAUTH_CLIENT_SECRET`, `SPEI_*`, `BREB_*`. Validar con Zod `.min(16)`. Documentar en LIMITATIONS | 30 min | A5-F5, A5-H2 |
| W7.8 | CLEAN-006 | Borrar reglas muertas `phone_co_to_breb` y `fallback_unavailable` de `seed_route_rules.sql` (o implementar matcher) | 20 min | I3, I4 |
| W7.9 | CLEAN-007 | Borrar files `test_8.md`, `test_7.md` de `mipit-core/src/` root | 5 min | A5-G4 |
| W7.10 | TEST-001 | Eliminar 5 tests `expect(true).toBe(true)`. Convertir 4 archivos TODO-only en `it.todo('...')`. Borrar `translation.test.ts:71-94` (asserts campos inexistentes) | 30 min | A5-E1, A5-E2, F40 |
| W7.11 | TEST-002 | ESLint rule `jest/no-truthy-only-assertions` en CI | 10 min | A5-E1 prevent regression |
| W7.12 | TEST-003 | Fix datasets PIX con `"currency": "USD"` → `"BRL"` (`pix-valid-01.json` + expected files) | 20 min | A5-E3 |
| W7.13 | DOC-001 | Update `architecture-overview.md` línea 43: "reglas en Postgres vía RuleLoader" (no YAML); `translation-layer.md:65,79`: agregar `LLAVE_BREB`, corregir `institutionCode max(8)` | 20 min | A5-D9, A5-A5, A5-A6 |
| W7.14 | DOC-002 | Update `local-demo.md`: queue real `payments.route.pix` (no `q.adapter.pix`); credenciales Grafana correctas (`admin/mipit2026`) | 15 min | I10, B10 |
| W7.15 | DOC-003 | ADR-006 amend: declarar honesto "pg raw, no Kysely". O implementar Kysely (depende decisión equipo) | 30 min decisión + 1 día si implementan | A5-D2 |
| W7.16 | CLEAN-008 | UI Toast clean: si se borró radix-toast vs sonner, asegurar consistencia | 10 min | F13 follow-up |

**Criterios de éxito Wave 7:**

- ✅ `npm ls` en UI sin warnings de orfan deps
- ✅ Tests count baja pero todos los que quedan son reales (sin placebos)
- ✅ Grep `expect(true)` en `mipit-testkit/tests` = 0
- ✅ Imports de `RAILS/STATUS` apuntan a `@mipit/shared-types`
- ✅ Doc `canonical-fields.md` y CSVs no existen; OpenAPI generado desde Zod

---

### 🌊 Wave 8 — Architecture para Producción (Días 8-15, ~7-10 días)

**Objetivo:** llevar MiPIT a un estado defendible ante revisores ISO 20022 / SWIFT CBPR+. **NO bloquea sustentación** — es el roadmap post-tesis.
**Branch sugerido:** `Auditoria-Claude` o branch nueva `production-ready`.
**Estado:** ⏳ Planeada.

| Orden | Ticket | Cambio | Tiempo | Resuelve |
|---|---|---|---|---|
| W8.1 | ARCH-001 | Crear `@mipit/adapter-runtime` package compartido. `runAdapterWorker(handler, metrics, rail)` genérico. Cada adapter queda ~30 LOC | 1-2 días | F08, F28, C10 master |
| W8.2 | ARCH-002 | `@mipit/contracts` versionado (Zod schemas + ts types + JSON Schema + OpenAPI export desde una SoT) | 1 día | A5-A3, A5-A4, A5-A7, F25, R2 |
| W8.3 | ARCH-003 | Idempotency middleware (separar de route handler). NOTIFY/LISTEN para resolver race F05 | medio día | F05, R3 |
| W8.4 | ARCH-004 | Outbox pattern para webhooks. Tabla `webhook_outbox` con worker dedicado y retry exponencial | 1 día | F33, R4 (B4 fix definitivo) |
| W8.5 | ARCH-005 | Circuit breaker integrado en publisher + 3 adapter HTTP clients (hoy solo en ui-proxy) | 1 día | F22, R5 (B2 master) |
| W8.6 | ARCH-006 | Property-based tests con fast-check. Invariantes: roundtrip translation, FX symmetry, pipeline always reaches terminal | 2 días | F21, F39, R6 |
| W8.7 | ARCH-007 | DI container — eliminar singletons module-level (`db.ts`, `health.ts`, `sse.ts`, `circuit-breaker.ts`). Constructor injection | 1 día | F29, R7 |
| W8.8 | ARCH-008 | pnpm workspace + alignment OTel/amqplib/prom-client entre core y adapters | medio día | F11, A5-I (drift OTel), R8 |
| W8.9 | PERF-001 | `reconciliation-service.findSince` con LIMIT + cursor pagination | 1 día | F03 master |
| W8.10 | PERF-002 | DLQ retry counter en headers (`x-mipit-dlq-attempts`); descartar tras max=3 a tabla `payments_dead` | medio día | F04 master |
| W8.11 | PERF-003 | Recording rules Prometheus separar por stage (`by (stage, le)`) | 30 min | F10 |
| W8.12 | PERF-004 | Trace context propagation: `publisher.ts` agrega `traceparent` header W3C; consumer lo lee y propaga al span | medio día | F17 |
| W8.13 | PERF-005 | Logger refactor: pasos intermedios → `log.debug`; mantener solo `info` en boundaries | 20 min | F23 |
| W8.14 | PERF-006 | DB índice composite `(status, created_at DESC)` para `findRecent` | 10 min | F36 |
| W8.15 | PERF-007 | Histogram bucket cap fix `findPercentile` con interpolación lineal | 30 min | F20 |
| W8.16 | PERF-008 | Health adapters check `channel.checkExchange(env.EXCHANGE_NAME)` antes de ok | 15 min | F18 |
| W8.17 | PERF-009 | Cachear `runReconciliation` 60s; servir cache salvo `?refresh=true` | 30 min | F24 |
| W8.18 | PERF-010 | Timer leaks: `.unref()` en `rate-limit.ts:39`, `index.ts:146`, `sse.ts:89,135`; remove `--forceExit` de jest | 30 min | F06, F40 |
| W8.19 | PERF-011 | Module augmentation Fastify `traceId` en `src/types/fastify.d.ts` | 10 min | F26 |
| W8.20 | PERF-012 | Borrar double-registered consumers en `mipit-core/src/index.ts:137-143` (confiar solo en bootstraps) | 20 min | F02, C9 master |
| W8.21 | SEC-001 | SSRF mitigation: validar webhook URL no resuelve a IP privada (10/8, 172.16/12, 192.168/16, 169.254/16, ::1) | 1 hora | F09 |
| W8.22 | SEC-002 | `/auth/token` 404 en producción (`NODE_ENV=production`). Token issuer out-of-band via `tools/issue-token.sh` | 30 min | Q15 |
| W8.23 | SEC-003 | JWT secret out of repo (`.env.local` gitignored o KMS para prod) | 30 min | Q11 |
| W8.24 | TEST-COV | Unit tests para Wave 2-4 components: reconnect, CB, webhook, FX, reconciliation, compensation, DLQ. Target: 70% coverage | 2 días | F21 |
| W8.25 | TEST-BREB | `mipit-adapter-breb` tests al nivel pix/spei: `worker.test.ts`, `retry.test.ts`, `publisher.test.ts`, `health-server.test.ts` | 1 día | F39 |
| W8.26 | REGUL-001 | Middleware `regulatory-threshold.ts`: detecta `amount >= USD-10k-equivalent` → stamp en audit + `regulatory_flagged: true` | medio día | N-007 |
| W8.27 | RF19 | Implementar export CSV/JSON en `/payments` y `/audit-events` (RF19 declarado en SRS pero no entregado) | 3 horas | T-001 |
| W8.28 | BENCH-001 | Re-medir RNF: throughput / latencia p95-p99 / disponibilidad. Documentar en `evidence/benchmark-2026-05-18.md`. K6 o autocannon | medio día | T-003 |

**Criterios de éxito Wave 8:**

- ✅ `npm test` corre sin `--forceExit`
- ✅ Cobertura unit >70% en Wave 2-4 components
- ✅ pacs.008 generado pasa XSD validator oficial
- ✅ Cross-service trace en Jaeger atraviesa core → publisher → adapter sin gaps
- ✅ Circuit breaker se observa abriéndose en analytics endpoint cuando se detiene un adapter
- ✅ DLQ retry counter visible; mensajes poison no rebotan más
- ✅ Reconciliation procesa 100k pagos sin memory issue

---

## Parte III — Recap visual

| Wave | Días | Foco | Hallazgos resueltos |
|---|---|---|---|
| **Wave 5** | 0.5 día | Hardening pre-demo | 14 issues visibles (D1-D10 críticos + 4 inconsistencias) |
| **Wave 6** | 3.5 días | ISO 20022 fidelity | 13 hallazgos A1 + LIMITATIONS update |
| **Wave 7** | 1.5 días | SoT + limpieza | ~30 hallazgos A3+A5 (deps, dead code, tests, docs) |
| **Wave 8** | 7-10 días | Production-ready | ~28 hallazgos resiliencia/perf/test/refactor |
| **Total** | ~13-15 días | — | 88 hallazgos cubiertos |

### Recomendación de orden

- Si tienes **2 semanas** hasta sustentación: Wave 5 + Wave 6 son obligatorias. Wave 7 es nice-to-have. Wave 8 es post-tesis.
- Si tienes **1 semana**: Wave 5 día 1, Wave 6 días 2-5. Skip 7 y 8.
- Si tienes **3 días**: solo Wave 5 + las 3 acciones más rentables de Wave 6 (W6.1 pacs.002, W6.4 pacs.004, W6.12 LIMITATIONS update).
