# Auditoría de Cumplimiento de Tesis — MiPIT PoC

**Fecha:** 2026-05-17
**Tipo:** Segunda auditoría — Cumplimiento de promesa vs entrega
**Estado del proyecto:** Wave 1–4 cerradas (verificación 2026-05-17 macOS, 591/591 unit tests, smoke 3/3 rail-pairs COMPLETED).
**Auditor:** Claude (subagent), branch `Auditoria-Claude` en los 9 repos.
**Referencia primer informe:** [`audits/AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md`](../audits/AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md).

> **Nota metodológica:** el sandbox de esta auditoría no pudo renderizar los PDF
> binarios directamente (`pdftoppm`/`pdftotext`/`pypdf` bloqueados por restricciones
> de ejecución). Los hallazgos referenciados al SRS / Memoria / Diseño se apoyan en
> las **citas literales extraídas y catalogadas en la auditoría profunda del
> 2026-05-16** (sección §11 de `AUDIT-RAW-ui-docs.md`, que sí leyó los PDFs página
> por página) y en los `mipit-docs/spmp/`, `mipit-docs/srs/`, `mipit-docs/design/`,
> `plans and context/PLAN-DE-DESARROLLO.md`. La trazabilidad PDF→requisito está
> garantizada porque la auditoría previa ya hizo el barrido textual de los 4 PDFs.

---

## 1. Objetivos de la tesis declarados

### 1.1 Objetivo general (Memoria / Propuesta)

Citado por la auditoría profunda en `AUDIT-RAW-ui-docs.md` §11.4 (lectura directa
de `Plantilla Propuesta Proyecto Middleware.pdf`):

> **Título oficial:** "Evaluación de una Arquitectura de Interoperabilidad Basada
> en ISO 20022 para Pagos Instantáneos Transfronterizos".
>
> **Objetivo general:** Evaluar un prototipo de middleware con **PIX, SPEI, FedNow
> y Bre-B** como los cuatro rieles objetivo del prototipo.

### 1.2 Objetivos específicos (Memoria / Propuesta)

1. Revisar el estado del arte en interoperabilidad de pasarelas instantáneas.
2. Desarrollar un **traductor semántico** bidireccional (formato nativo ↔ canónico ISO 20022).
3. Implementar un **enrutador inteligente** (semánticamente determina el rail destino).
4. Evaluar el sistema con sandboxes/mocks + métricas (latencia, correctitud, tasa de éxito).

### 1.3 Hitos formales del SPMP (`SPMP.pdf`, §11.5 de `AUDIT-RAW-ui-docs.md`)

| Hito | Promesa | Calendario |
|---|---|---|
| **H1** | Problema + criterios definidos | semana 4 |
| **H2** | Arquitectura validada | semana 8 |
| **H3** | Primer E2E con **2 rieles** | semana 12 |
| **H4** | **Evaluación con 4 rieles** | semana 14 |
| **H5** | Artículo académico + demo | semana 16 |

> El SPMP declara **16 semanas** totales bajo metodología DSR. El
> `PLAN-DE-DESARROLLO.md` posterior re-escaló a **17 semanas** incluyendo
> planeación formal (Fase 0 semanas 1–4 + Fase 1 semanas 5–14 + Fase 2 condensada
> semanas 15–17). La verificación macOS 2026-05-17 confirma que el desarrollo
> activo lleva **13+ semanas** (Wave 4 cerrada, contexto declara "13+ semanas").

### 1.4 Hallazgos sobre objetivos

- **OG-1:** El "marketing académico" del proyecto promete **interoperabilidad basada en ISO 20022**. La auditoría ADR-002 deja claro que el canónico es un **subset pragmático** de `pacs.008.001.10` (no XML, no XSD-validated, sin `RmtInf.Strd`, sin `RgltryRptg`, sin `IntrmyAgt`). Esto es honesto siempre que se nombre como "pacs.008-derived JSON" en sustentación y no como "ISO 20022 completo".
- **OG-2:** El alcance original prometía **4 rieles evaluables** (PIX, SPEI, FedNow, Bre-B). Lo entregado son **3 rieles productivos** (PIX, SPEI, Bre-B) **+ 4 rieles solo-traducción** (SWIFT_MT103, ISO20022_MX, ACH_NACHA, **FedNow degradado a translator-only**). Net positivo en breadth, pero "evaluación con FedNow" en sentido estricto (Option-B con mock + ack queue) **no se entrega**. Documentado en `LIMITATIONS.md §1`.
- **OG-3:** H4 ("evaluación con 4 rieles") en lectura estricta **no se cumple**. Se sustituyó FedNow por Bre-B en el slot de "rail evaluable" — eso es defendible si en sustentación se argumenta el re-framing.

---

## 2. Requisitos funcionales (RF) — promesa vs implementación

Fuente: `SRS_MIPIT.pdf` RF01–RF20 (sección 3.4 según §11.1 de `AUDIT-RAW-ui-docs.md`).
Cruzado contra código actual en branch `Auditoria-Claude` (post-Wave 4).

| RF | Promesa SRS | Estado actual | Evidencia (file:line) |
|---|---|---|---|
| **RF01** | `POST /payments` para crear pago | Cumplido | `mipit-core/src/api/routes/payments.ts` (POST + GET + listing); declarado en `mipit-docs/openapi/openapi.yaml:65` aprox. |
| **RF02** | Generación + persistencia de `payment_id` único | Cumplido | Formato `PMT-${ulid()}`; columna PK en `payments` table (`mipit-infra/db/init/001_*.sql`); migración `008_payments_constraints_and_iso.sql` agrega `uetr UUID UNIQUE`. |
| **RF03** | Acuse inmediato (response síncrono) | Cumplido | `POST /payments` retorna `201 Created` con `{payment_id, status, destination_rail, ...}`. Antes era 202 — corregido en P06. |
| **RF04** | Traducción PIX/SPEI → canónico ISO 20022 | Cumplido con caveats | 16 traductores en `mipit-core/src/translation/` (PIX, SPEI, Bre-B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW bidireccional + `translator.ts` orquestador). Canónico vive en `src/domain/models/canonical.ts` y `src/canonical/pacs008.schema.ts`. **Caveat:** no XML ISO real, subset documentado en ADR-002. |
| **RF05** | Validación estructura + obligatoriedad | Cumplido | Zod schemas en `canonical.ts` con constraints ISO (max 35, 140, 4×70). Endpoint rechaza `amount <= 0`, alias inválido, `Idempotency-Key` malformado. |
| **RF06** | Catálogo `MappingTable` cargado en DB | Cumplido | `mipit-infra/db/init/003_seed_mapping_table.sql` (44 rows PIX+SPEI) + `db/migrations/013_seed_breb_mappings.sql` (23 rows BRE_B). `mapping-loader.ts` cachea con TTL 5 min. **Drift documental:** las CSVs en `mipit-docs/mappings/` siguen describiendo shape flat snake_case (legacy); el código usa nested camelCase. Tracked en plan P12. |
| **RF07** | `RouteRule` determina destino sin enviar `destination_rail` | Cumplido | `mipit-core/src/routing/route-engine.ts` carga reglas de `mipit-infra/db/init/002_seed_route_rules.sql` (8 reglas con prioridad alias > country > phone > fallback). Verificado en `tests/integration/routing.test.ts` (mejor archivo de testkit). |
| **RF08** | Despacho HTTP/cola al adapter | Cumplido | `messaging/publisher.ts` publica a exchange `mipit.payments` topic con routing key `route.{pix\|spei\|breb}`. Confirm channels habilitados (P06). |
| **RF09** | Procesamiento de respuesta del adapter | Cumplido | `messaging/consumer.ts` (`AckConsumer`) consume queue `payments.ack`. ACK con `OrgnlEndToEndId`, `OrgnlUETR`, `TxSts`. Audit trail per cambio de estado. |
| **RF10** | Conexión a sandbox real del riel | **Parcial (scope-out)** | 3 mock servers (`mipit-adapter-{pix,spei,breb}/src/.../mock-server.ts`) en lugar de DICT/STP/BanRep oficiales. Documentado en `LIMITATIONS.md §1`. **Justificación regulatoria, no falla.** |
| **RF11** | Mapeo `ACCEPTED` / `REJECTED` a estado final | Cumplido | Pipeline transita a `COMPLETED` / `REJECTED` / `FAILED` desde el ACK. Catálogo de error codes per-rail (BACEN, CECOBAN, BREB) en mocks. |
| **RF12** | Logging de latencia + errores | Cumplido | Pino structured JSON con `redact` de PII (P07), métricas `mipit_adapter_latency_ms{rail}` y `mipit_payments_*_total`. Wave 4 unificó shape de métricas adapters. |
| **RF13** | `AuditEvent` por pago (cadena inmutable) | Cumplido | `audit/audit-service.ts` + `audit_events` table. ~76 assertions de E2E verifications. **Caveat:** sin firma criptográfica de hashchain (documentado en `LIMITATIONS.md §3`). |
| **RF14** | Métricas Prometheus | Cumplido | `observability/metrics.ts` expone instruments en `:9090/metrics`. Recording rules (`mipit-recording`) + alert rules (`mipit-alerts`) en `mipit-observability/prometheus/`. |
| **RF15** | Dashboards Grafana | Cumplido con bug fix | 3 dashboards en `mipit-observability/grafana/`. **El primer audit detectó 8/19 paneles rotos**; Wave 4 P07 unificó nombres de métricas (`mipit_adapter_requests_total{rail,status}` etc.) — verificado funcional en `wave-1-4-verification-2026-05-17-macos.md`. |
| **RF16** | UI: timeline visual del flujo | Cumplido | `mipit-ui/src/components/payments/flow-timeline.tsx` (8 pasos con colores según status). UI muestra UETR, ChrgBr y `trace_id → Jaeger link` (P11). |
| **RF17** | UI: simulación + observación | Cumplido | `mipit-ui/src/app/simulate/page.tsx` + `simulator/page.tsx` (control panel de mocks). Dataset balanceado en `mipit-testkit/datasets/`. |
| **RF18** | UI: ver mensajes traducidos + sandbox response + métricas | Cumplido | `message-inspector.tsx` (3 columnas: original/canónico/traducido), `rail-ack-panel.tsx`, `analytics/page.tsx`. |
| **RF19** | **Exportación CSV/JSON** desde UI | **NO IMPLEMENTADO** | `mipit-ui/src/app/history/page.tsx` no tiene botón export; `analytics/page.tsx` tampoco. **Verificado:** ninguna referencia a `download`, `csv`, `Blob`, `URL.createObjectURL` en las páginas. **Brecha real, no scope-out documentado.** |
| **RF20** | Reinicio entre sesiones (estado limpio) | Cumplido | `docker compose down -v && up -d` + `/mocks/{rail}/admin/reset`. Idempotency sweeper background job (P06). |

**Resumen RF:** 19/20 cumplidos. **RF19 es el único NO-cumplido sin scope-out previo.**
Adicionales descubiertos durante implementación (no en SRS original): compensación
(`POST /compensate/:id`), reconciliación (job background), webhooks
(`POST /webhooks/{alertmanager,payment-completed}`), SSE
(`GET /stream/payments`), translate-only endpoints (`POST /translate/*`).

---

## 3. Requisitos no funcionales (RNF) — promesa vs implementación

Fuente: `SRS_MIPIT.pdf` §3.5 + Memoria + `Diseno_MIPIT.pdf` §3.4 (resumidos en
auditoría profunda §11.1).

| RNF | Promesa SRS | Estado actual | Evidencia |
|---|---|---|---|
| **Throughput** | ≥100 tx/sesión | **Validado en histórico, no re-medido en Wave 4** | `e2e-benchmark-latency.mjs` + `e2e-load.mjs` en testkit. Reportes en `mipit-testkit/evidence/suite/`. La validación-suite cuenta "historical-load" con `durationMs: 0` (sin re-ejecución reciente). **Flag para sustentación.** |
| **Latencia máxima respuesta** | ≤15 s | Sub-segundo en histórico (p99 ≈ 250 ms) | Mismo dataset histórico. No hay SLO enforcement automático que falle CI si regresiona; los E2E aceptan timeout de 30 s. |
| **Tasa de éxito** | ≥99.9 % | Aprox. validado (e2e-routing-correctness 999/999) | Reporte en `E2E-VERIFICATION-RESULTS.md`. **No re-medido en Wave 4** (histórico). |
| **Disponibilidad rails** | Conformidad reglamentaria | Cumplido | PIX 24/7 (BACEN Res. 1/2020 — P02 fix); SPEI L-V 06:00–17:55 CT (Banxico Circular 14/2017 — P03 fix); Bre-B 24/7 (BanRep TR-002 — P04). Verificado en `wave-1-4-verification-2026-05-17-macos.md` Wave 2 19/20 ✓. |
| **Seguridad — auth** | API Key o equivalente | Cumplido como JWT HS256 | ADR-005. `mipit-core/src/api/middleware/auth.ts`. Endpoint `/auth/token` dev-only. **Sin OIDC ni rotación**, documentado en `LIMITATIONS.md §3`. |
| **Seguridad — TLS** | TLS 1.3 | Cumplido en nginx | nginx TLSv1.3-only, self-signed certs. **Sin security headers (HSTS, CSP, X-Frame-Options)** — flagueado en primer audit, no en LIMITATIONS. |
| **Seguridad — PII** | Redacción / cuidado | Cumplido (P07) | Pino `redact` para `debtor/creditor.name/taxId/email/phone`, `headers.authorization`. Verificado en logs en Wave 4. |
| **Idempotencia** | `Idempotency-Key` header con dedupe | Cumplido | `mipit-core/src/api/routes/payments.ts`. TTL 24h con sweeper (P06 corrige el bug de `expires_at NULL`). Middleware dead code eliminado en P06. |
| **Mantenibilidad / observabilidad** | OpenTelemetry + Prometheus + Grafana | Cumplido | ADR-008. OTel SDK por servicio, Jaeger backend, Prometheus + AlertManager (P07). trace_id propagado a UI con link Jaeger (P11). **Caveat:** OTel collector configurado pero no desplegado (apps van directo a Jaeger). |
| **Escalabilidad** | Implícita (PoC, no carga real) | No medido | Sin pruebas de carga formal (k6/Gatling). Rate limiter implementado y wired en pipeline (P06). |

**Resumen RNF:** **Las afirmaciones cuantitativas (100 TPS, 99.9%, latencia ≤15s)
no se han re-medido en Wave 4** — solo en la corrida histórica del 2026-05-15. Si
el panel pregunta "muéstrame el benchmark hoy", la respuesta seria es "re-ejecutar
`e2e-benchmark-latency.mjs` y `e2e-load.mjs` contra el stack live actual".

---

## 4. Alcance declarado vs alcance entregado

### 4.1 Lo prometido y NO entregado

| # | Prometido (origen) | Estado |
|---|---|---|
| 1 | **FedNow como rail evaluable Option-B** (Memoria, Propuesta) | Degradado a translator-only. Bre-B sustituye en el slot práctico. |
| 2 | **Export CSV/JSON en UI** (SRS RF19) | No implementado. **Brecha real**. |
| 3 | **API Key** (SRS §2.1.5) | Sustituido por JWT (semánticamente equivalente, drift documentado). |
| 4 | **Endpoints `/transactions` + `/transactions/{id}`** (Diseno PDF) | Renombrados a `/payments` y `/payments/{id}`. **Documentado** en plan; drift formal con Diseno_PDF. |
| 5 | **Schema request `sourceAccount/destinationAccount/destinationRail/metadata`** (Diseno PDF) | Renombrado a `debtor/creditor/purpose/reference`. Sin re-edición del Diseño_PDF. |
| 6 | **Status enum 4 estados** (Diseno PDF: `RECEIVED, PROCESSING, SUCCESS, FAILED`) | Implementado con 14 estados (`PAYMENT_STATUS_ENUM`). Diseño nunca actualizado. |
| 7 | **Spring Boot** (Diseno_PDF §3.1.2) | Reemplazado por Node.js + Fastify (ADR-001 supersede). |
| 8 | **`pacs.008.001.10` byte-fidelity** (implícito por "ISO 20022") | Subset pragmático JSON sin XML/XSD. Documentado explícitamente en `LIMITATIONS.md §2` y ADR-002 — **scope-out consciente, no falla**. |
| 9 | **Diagramas formales 4+1 / secuencia / despliegue** (Diseno_PDF §4) | Solo `architecture-overview.md` y `translation-layer.md` actualizados; diagramas detallados de Diseño no re-renderizados con Bre-B. |

### 4.2 Lo entregado y NO prometido (sobre-entrega)

| # | Entregado | Origen del crecimiento |
|---|---|---|
| 1 | **3 rieles productivos + 4 translator-only** (7 totales) | El plan original eran 4. La estructura hub-and-spoke escaló natural. |
| 2 | **`/compensate/{id}` + `/compensate/batch`** | Reverse flow saga-style. No en SRS original. **Caveat:** el primer audit muestra que la compensación no emite pacs.004 real (logged-only). |
| 3 | **Job de reconciliación periódica** | No en SRS. Compara status interno contra "expected ledger" local. Sin camt.054/camt.053 real. |
| 4 | **`POST /webhooks/{alertmanager,payment-completed}`** | Webhooks salientes con HMAC-SHA256. No en SRS. |
| 5 | **SSE `/stream/payments`** | Streaming en vivo para UI. No en SRS. |
| 6 | **`POST /translate/{canonical-to,from}/:rail`** | Endpoints debug/UI. No en SRS. |
| 7 | **`/analytics/{throughput,success-rate,rate-limits,reconciliation}`** | UI Analytics page. No en SRS. |
| 8 | **Generadores con checksum válido CPF/CLABE/NIT** (mod-11, mod-10) | Testkit P10. No en SRS — buena adicón académica. |
| 9 | **Circuit breakers + rate limiter wired en pipeline** | Resiliencia que no estaba prometida. |
| 10 | **AlertManager + webhook a `/webhooks/alertmanager`** | Observabilidad operacional, no en SRS. |
| 11 | **14 estados en `PAYMENT_STATUS_ENUM`** vs 4 del Diseño | Modelado más completo del ciclo de vida. |
| 12 | **OpenAPI con 25+ endpoints** vs los 5 originales del Diseño | Cobertura formal de la API real. |

### 4.3 Veredicto de alcance

**Saldo neto positivo en breadth, neutro-negativo en compromiso documental.**
El proyecto entrega más superficie técnica de la prometida, pero arrastra
**inconsistencias formales con los PDFs originales** (endpoints, schemas, status
enum, stack Spring Boot vs Node, RF19, FedNow). El primer audit ya enumeró estos
drifts; lo que falta es **acta explícita** en la tesis que reconozca cada cambio.

---

## 5. Evidencia para la sustentación

### 5.1 Claims sólidos (tests + evidencia ejecutada reciente)

| Claim | Evidencia |
|---|---|
| **Interoperabilidad técnica 3 rieles** | `wave-1-4-verification-2026-05-17-macos.md` smoke test 3/3: PIX→SPEI, SPEI→BRE_B, BRE_B→PIX **COMPLETED** end-to-end. |
| **Pipeline 8 pasos funcional con FX cross-currency** | Wave 3 P05 17/17 ✓; ejemplo BRL→MXN convierte vía rate openexchangerates a `fx.local_amount`. |
| **Idempotencia E2E** | `tests/integration/idempotency.test.ts` + `e2e-verifications.mjs` (100 concurrentes, 1 create + 99 cached). Sweeper background activo. |
| **JWT auth + redact PII** | Wave 1 P01 4/4 ✓ JWT/AUTH; Wave 4 P07 verificó Pino redact en logs live. |
| **Métricas adapters unificadas** | Wave 4 P07 verificado: `mipit_adapter_requests_total{rail,status}` expuesta en PIX/SPEI/BRE_B; 3 dashboards Grafana renderizan. |
| **trace_id propagado a UI con link Jaeger** | `mipit-ui/src/app/payments/[id]/page.tsx:104-150` (P11). |
| **Validación checksum real** | Generators con mod-11 (CPF, NIT), mod-10 (CLABE). Datasets P10 corregidos. |
| **591/591 unit tests** | Verificación macOS: core 307 + ui 64 + pix 62 + spei 86 + breb 44 + testkit 28. |
| **Bre-B end-to-end** | 23 mapping_table rows, 6 fixtures, 44 tests, smoke COMPLETED. |
| **DLQ + reintentos** | Wave 1 P06: `payments.dlq` unificada (decisión arquitectónica, no 3 separadas como esperaba el script). |

### 5.2 Claims débiles (afirmado sin evidencia reciente)

| Claim | Por qué es débil | Cómo reforzar |
|---|---|---|
| "**100 TPS sostenidos**" | No re-medido en Wave 4. Histórico del 2026-05-15. | Re-ejecutar `e2e-load.mjs` + `e2e-benchmark-latency.mjs` contra stack live actual, capturar histograma p50/p95/p99 en evidence/. |
| "**99.9% delivery success**" | Histórico, no actual. | Mismo: corrida controlada con N=1000, reportar JSON. |
| "**Latencia ≤15s p99**" | Ningún test FALLA si regresiona. Solo timeout 30s. | Agregar SLO assertion explícito en `tests/e2e/*.test.ts` y en `e2e-benchmark-latency.mjs` que falle si `p99 > 15000`. |
| "**Compensation saga"** | El primer audit demuestra que `compensation-service.ts` solo cambia status, no emite pacs.004 ni llama adapter. | Cambiar lenguaje en sustentación: "compensación lógica/contable, no pacs.004 wire" (consistente con `LIMITATIONS.md §4`). |
| "**Reconciliación**" | Job corre pero no persiste reportes ni dispara webhook (primer audit). | Cambiar lenguaje a "monitor periódico que detecta anomalías a logs". O implementar tabla `reconciliation_reports` en próxima iteración. |

### 5.3 Claims overstated (afirmamos más de lo entregado)

| Claim | Realidad |
|---|---|
| "**ISO 20022 pacs.008.001.10**" sin matización | Es subset JSON (sin XML, XSD, RmtInf.Strd, IntrmyAgt). El nombre técnico correcto es **"pacs.008-derived"** (ADR-002 lo dice). Mantener este término en slides. |
| "**Conexión real a sandbox PIX/SPEI/Bre-B**" | Mocks propios; los oficiales requieren licencia financiera. Documentado en `LIMITATIONS.md §1`. |
| "**Cross-border / cross-currency end-to-end**" | FX se calcula en core y se persiste, pero el primer audit reportó que adapters PIX/SPEI/Bre-B **ignoraban** `canonical.fx.local_amount` (solo FedNow lo usaba). **Verificar** que P05 corrigió esto en los 3 adapters productivos antes de demostrar BRL→MXN frente al panel. |
| "**Mocks byte-fidelity con APIs reales**" | Endpoints inventados (PIX `/spi/v2/pagamentos` no existe; SPEI usa OAuth cuando STP real es SOAP RSA-firmada). El primer audit lo demuestra con citas a BCB/Banxico/BanRep oficiales. |

---

## 6. Brechas críticas pre-sustentación

Si el panel pide demos puntuales, esto es lo que **no podemos mostrar bien hoy**:

### 6.1 Top 5 brechas (orden de visibilidad)

1. **"Muéstrenme RF19 — exportar el historial en CSV/JSON desde la UI."**
   → No hay botón. Implementable en 1 día (`Blob` + `URL.createObjectURL` en
   `history/page.tsx`, columnas ya disponibles vía `listPayments()`).

2. **"Muéstrenme la reconciliación detectando una discrepancia."**
   → El job corre cada 30 min y solo loggea. No persiste a tabla, no
   dispara alerta. Posibles respuestas: (a) implementar tabla
   `reconciliation_reports` con 2 columnas (job_id, anomalies_jsonb), o (b)
   re-encuadrar como "monitor de salud" en el discurso académico y citar
   `LIMITATIONS.md §4`.

3. **"Muéstrenme un pago en `COMPENSATED` con su pacs.004 saliente."**
   → Hoy no se emite pacs.004 (logged-only). Plan honesto: defender como
   "compensación lógica" (rollback de estado interno) y mostrar la transición
   `COMPENSATING → COMPENSATED` con el audit_event. Documentado en
   `LIMITATIONS.md §4`. **Esto es defendible**, pero hay que ensayar el
   discurso para no decir "saga compensation" sin contexto.

4. **"Muéstrenme cross-currency BRL→MXN llegando al mock SPEI con el monto
   convertido."** → P05 cerró Wave 3 con BRL→SPEI COMPLETED, pero el primer
   audit dejó duda sobre si los **adapters** consumen `fx.local_amount` (vs
   ignorarlo). **Acción:** ejecutar trace manual completo (insertar pago
   BRL→SPEI, hacer `GET /payments/:id`, verificar que `canonical_payload.fx`
   y `translated_payload.monto` cuadran). Capturar screenshot.

5. **"¿Qué pasa si el adapter SPEI se cae mid-flight?"** → 8 tests E2E en
   `error-scenarios*.test.ts` están **rojos** en la verificación macOS (24/32
   pasan). Aunque la corrida histórica los pasaba, hoy fallan por assertions
   de transiciones `DEAD_LETTER` vs `FAILED/REJECTED/COMPLETED`. **Acción:**
   reparar los 8 tests o documentar explícitamente como "resilience deuda
   técnica con DLQ verificada manualmente" en sustentación.

### 6.2 Brechas secundarias (improbables que un panel técnico cace, pero útil cerrar)

6. **Auth en SSE `/events/payments`** — el endpoint no enforces token; cualquier
   cliente con red puede ver pagos. Sin PII por `redact`, pero igual es
   superficie. (Pequeña: agregar `preHandler: app.authenticate` o token via
   query param como dice CONTEXTO).
7. **Health endpoint hardcoded `{status:'ok'}`** — Kubernetes readiness siempre
   verde aun con Postgres caído. Bug del primer audit no se ha confirmado si
   Wave 4 lo arregló.
8. **`/auth/token` sin auth** en dev/staging — cualquier red interna obtiene
   token admin. Si el demo es en VM y la VM tiene red lateral, esto es vector.
9. **OpenAPI vs realidad** — Wave 4 sincronizó las cosas críticas (UETR,
   ChrgBr, DEAD_LETTER, BRE_B); aún faltan `/mocks/{rail}/admin/*` y schemas
   por riel. Cosmético; no crítico para sustentación.
10. **Test count placebos:** `tests/contract/openapi-validation.test.ts` y
    `rabbitmq-messages.test.ts` siguen con 2+1 `expect(true).toBe(true)` que
    inflan los pass counts. Riesgo: si un revisor abre el código, lo nota.
    Renombrar a `.skip.ts` o implementar assertions reales.

---

## 7. Verdaderos diferenciadores académicos

Lo que hace MiPIT **distinto a un middleware genérico** y por qué tiene peso para
una tesis:

1. **Hub-and-spoke con canónico pacs.008-derived implementado end-to-end** entre
   3 rieles instantáneos LATAM heterogéneos (BACEN/PIX, Banxico/SPEI, BanRep/Bre-B).
   La tesis demuestra que la abstracción `N×2 traductores + 1 canónico` es viable
   y minimiza la combinatoria `N×(N-1)` de mapeos directos. Evidencia: el smoke
   test del 2026-05-17 (3 rail-pairs COMPLETED).

2. **Trazabilidad ISO 20022 visible en UI**: UETR + ChrgBr + EndToEndId +
   trace_id con link a Jaeger renderizados en `payments/[id]/page.tsx`. Esto es
   raro incluso en sistemas productivos (P11). Cita: `mipit-ui/src/app/payments/[id]/page.tsx:104-150`.

3. **Validación de checksums por riel** (CPF mod-11, CLABE mod-10 weighted, NIT
   mod-11). Los datasets de testkit no son "garbage strings" — usan números
   matemáticamente correctos. Cita: `mipit-testkit/generators/`.

4. **6 rail-pairs direccionales ejercitados** vs los 2 mínimos prometidos. La
   tabla en `tests/integration/routing.test.ts` cubre PIX↔SPEI, PIX↔BRE_B,
   SPEI→BRE_B, BRE_B→PIX con `expect(status).toBe(201)` directo.

5. **Observabilidad full-stack con AlertManager**: alertas Prometheus →
   webhook MiPIT → dashboard. Recording rules p50/p95/p99 + success rate por
   riel. Cita: `mipit-observability/prometheus/recording-rules.yaml` y
   `alerting/`.

6. **Bre-B como caso de extensión "fresh"**: BanRep TR-002 entró en GA el
   2025-10-06 (real, no inventado). MiPIT lo adoptó dentro del PoC con 23
   mapping rows, fixtures dedicados, 44 tests unitarios. Esto demuestra que la
   arquitectura permite añadir un riel nuevo en semanas — atributo evaluable
   académicamente. Cita: `mipit-docs/design/adding-a-new-rail.md` + ADR-002
   sección "extensibilidad".

7. **Limitaciones documentadas con honestidad** (`LIMITATIONS.md` consolidado
   en P12). El propio acto de catalogar qué NO está implementado es un
   diferenciador frente a PoCs que "afirman todo y muestran demos rosas".
   Citar literalmente las 10 secciones de `LIMITATIONS.md` en la presentación.

---

## 8. Recomendaciones para defensa de tesis (orden de impacto)

### 8.1 Top 5 cambios pre-sustentación (alto impacto, costo bajo)

1. **Implementar RF19 (export CSV/JSON en `history/page.tsx`)** — ~3 h.
   Es el único requisito funcional NO-cumplido en lectura literal del SRS. Un
   panel que tenga el SRS al lado preguntará. Implementación trivial: botón
   "Exportar CSV" que itere `listPayments({limit: all})` y genere `Blob`.

2. **Re-ejecutar benchmark de carga y archivar evidence/<fecha>.json** — ~30 min.
   Sin esto, los claims de "100 TPS / 99.9%" descansan en una corrida
   histórica del 2026-05-15. Plan: `npm run test:e2e -- --testPathPattern=batch-load`
   y `node e2e-benchmark-latency.mjs DURATION_S=60 RPS_TARGET=20`. Guardar
   en `mipit-docs/evidence/benchmark-2026-05-17/`.

3. **Reparar los 8 tests E2E de `error-scenarios`** — ~4 h. La verificación
   macOS los marca rojos. Para sustentación es vital que `npm test` corra
   verde de extremo a extremo. Si la decisión es "marcar como `@flaky` y
   priorizar siguiente iteración", al menos documentar la razón en
   `LIMITATIONS.md §4` (resiliencia).

4. **Renombrar canónico a "pacs.008-derived" consistentemente** en slides,
   README de mipit-core, `architecture-overview.md`. ADR-002 ya lo usa; queda
   alinear el resto. Esto blinda contra la pregunta "¿es ISO 20022 real?" con
   la respuesta correcta ("subset pragmático JSON; las limitaciones están
   listadas en LIMITATIONS.md §2"). ~1 h grep+replace.

5. **Sustentar Bre-B como caso de éxito de la arquitectura** — material de
   slides. La adición de Bre-B durante el desarrollo (post-Wave 1) es la mejor
   evidencia empírica de que el hub-and-spoke escala. Tener listo:
   - Cuántas líneas de código nuevas para Bre-B (`adapter-breb` LOC + 23
     mapping rows + 6 fixtures).
   - Cuánto tiempo (Wave 2 P04, ~3-4 días).
   - Qué NO hubo que tocar (core pipeline, otros adapters, contract canónico).

### 8.2 Cambios secundarios (si queda tiempo)

6. **Endpoint `/health` real (probar DB + RabbitMQ)** — 30 min. El primer audit
   reportó que devuelve `{status:'ok'}` hardcoded. Trivial corregir con
   `pool.query('SELECT 1')` y `channel.checkExchange('mipit.payments')`.

7. **Auth en SSE** — token via query param como prometido en CONTEXTO. ~1 h.

8. **Marcar tests placebo** como `.skip.ts` o reemplazar con assertions reales —
   ~2 h. Reduce "11/11 green" a número honesto (sin placebos).

9. **Tabla `reconciliation_reports` y persistir anomalías** — 4 h. Convierte
   una capability "logged-only" en "demoable" para si el panel pregunta.

10. **Actualizar diagramas formales de `Diseno_MIPIT.pdf`** con Bre-B y
    `/payments` (no `/transactions`). Si se entrega versión re-publicada del
    PDF, evita drift visible. ~4 h con un diagrama tool.

### 8.3 Estrategia narrativa de defensa

- **Liderar con honestidad académica.** `LIMITATIONS.md` es un activo, no un
  pasivo. Una sección de "Limitaciones conocidas" en la sustentación neutraliza
  el 80 % de preguntas hostiles.
- **Citar `mipit-docs/evidence/wave-1-4-verification-2026-05-17-macos.md`** como
  prueba reproducible. Tener corrido el comando dos veces antes del demo.
- **Diferenciar "claim arquitectónico" de "implementación productiva":** el
  claim es "la arquitectura hub-and-spoke con canónico ISO 20022-derived es
  viable para interop LATAM"; la implementación es un PoC con mocks. Estos son
  separables y el PoC valida el primero sin pretender ser el segundo.

---

## Anexos

### A. Evidencia ejecutada (2026-05-17 macOS)

- `mipit-docs/evidence/wave-1-4-verification-2026-05-17-macos.md`: 591/591 unit
  tests, smoke 3/3 rail-pairs COMPLETED, 12 containers UP, 7 migraciones DB
  aplicadas.
- Falsos positivos del script (no del código): 4 Wave 1 + 4 Wave 4 (whitespace
  `wc -l`, subshell asociativo, paths `tsx --eval`).

### B. Referencias

- `mipit-docs/audits/AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md` — primer audit (5 agentes paralelos, 5 reports).
- `mipit-docs/audits/AUDIT-RAW-ui-docs.md` — escaneo PDF por PDF (SRS, Diseño, Memoria, SPMP) con citas página/sección.
- `mipit-docs/LIMITATIONS.md` — limitaciones explícitas del PoC (P12 Wave 4).
- `mipit-docs/CONTEXTO-MIPIT.md` — single source of truth del estado actual.
- `plans and context/PLAN-DE-DESARROLLO.md` — 96 tickets / 17 semanas.
- `plans and context/Memoria_MIPIT.pdf`, `SRS_MIPIT (1).pdf`, `Diseno_MIPIT.pdf` — PDFs originales (citas a través de auditoría profunda §11).

### C. Veredicto final

| Pregunta | Respuesta |
|---|---|
| ¿La tesis cumple lo prometido? | **Sí, con caveats documentados.** 19/20 RF, 7+ rieles vs 4 (sustitución FedNow→Bre-B), arquitectura validada con smoke E2E reciente. |
| ¿La tesis es defendible ante un panel técnico? | **Sí, si se ensayan los puntos de §6 (brechas) y §8 (recomendaciones).** El primer audit + Wave 1–4 cerraron la mayoría de defectos materiales. |
| ¿Qué quita más sueño? | El **gap entre "PDF formal" y "código actual"** (endpoints, schemas, status enum, FedNow→Bre-B, RF19). La solución no es re-codear; es **declarar los cambios formalmente** en una sección "Cambios al alcance" de la tesis. |
| ¿Mejor diferenciador para slides? | **Bre-B como case study de extensibilidad** + **trazabilidad UETR/ChrgBr/trace_id visible en UI** + **LIMITATIONS.md como honestidad académica explícita**. |
