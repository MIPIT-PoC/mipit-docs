# Auditoría MiPIT — 2026-05-16

> Code review exhaustivo + comparación contra specs oficiales (BCB, Banxico, BanRep, ISO 20022) de los 9 repos.
> Tres agentes auditaron en paralelo: `mipit-core` (ISO 20022), adaptadores (PIX/SPEI/Bre-B vs specs oficiales) y supporting repos (UI/testkit/infra/observability + drift en docs).

---

## TL;DR

El proyecto **demuestra interoperabilidad técnica entre 2 rieles (PIX↔SPEI) con honestidad académica si se documentan las brechas**. Lo que hoy NO sostiene la tesis sin retoques:

1. **Bre-B no está al nivel de los otros dos rieles** — sin tests E2E, sin filas en `mapping_table`, fuera del OpenAPI, llaves con formato inventado.
2. **El canónico es "inspirado en pacs.008", no pacs.008 real** — faltan `UETR`, `ChrgBr`, `IntrBkSttlmDt`, `InitgPty`, `SttlmInf.ClrSys`, BICFI bajo `DbtrAgt/CdtrAgt`. ADR-002 lo admite, pero OpenAPI y dashboards lo venden más fuerte de lo que la implementación banca.
3. **EndToEndId de PIX está mal generado**: usa `E2E-${ulid()}` o `Math.random` en UTC, no `E + ISPB(8) + YYYYMMDDHHmm(BRT) + 11 alnum = 32`.
4. **FX se calcula pero los adaptadores lo ignoran** (excepto FedNow). Una transferencia BRL→MXN llega a SPEI con `monto = valor BRL`, `moneda = 'BRL'`. La interoperabilidad cross-currency está rota estructuralmente.
5. **Códigos de institución SPEI son de 3 dígitos** (`'072'`, `'002'`); el catálogo Banxico real usa **5 dígitos** (`40072`, `40002`, `90646`).
6. **El observability claim está roto en producción**: Prometheus scrapea `:9100` cuando los adapters publican en `:9101/9102/9103`, el OTel collector está configurado pero no desplegado, AlertManager no existe, nginx mata SSE por buffering.

Severidad agregada: **18 Críticos, 27 Altos, 38 Medios, 17 Bajos**.

---

## Parte I — Code Review consolidado

### `mipit-core` (Fastify + pipeline + canonical + routing)

**Críticos**
- **Idempotencia sin TTL**: `expires_at` se lee pero nunca se escribe (`persistence/queries/index.ts:64-70`, `idempotency.repository.ts:41-53`). Cada réplica re-entra al pipeline y choca el PK de `payments`.
- **Pipeline sin transacción**: publica al broker antes de marcar `QUEUED`. Si la DB falla post-publish, el pago queda `FAILED` en BD pero ya viajó al adapter (`pipeline/payment-pipeline.ts:127-141`). Requiere outbox.
- **Channel.publish sin confirms**: `messaging/publisher.ts:19` no usa `confirmChannel`, así que `persistent: true` es teatro — un blip del broker = mensaje perdido.
- **El reconnect de RabbitMQ no re-attach a consumers**: `resilience/reconnect.ts:79-129` reabre conexión pero `AckConsumer`/`DlqHandler` quedan ligados al canal viejo (`index.ts:104,109`). Tras un blip los ACK se acumulan invisibles.
- **Routing rules sin tie-breaker estable**: `routing/route-engine.ts:23` ordena por `priority` sin `ORDER BY id` en SQL — orden no determinista entre prioridades iguales.

**Altos**
- JWT sin algoritmo pineado (`api/server.ts:58`), sin `iss/aud`. Un token con `alg: none` o `alg: RS256` podría colar.
- Endpoint `/auth/token` no autenticado entrega JWT de admin a cualquiera con red. Es PoC, pero hay que gatearlo con `NODE_ENV !== 'production'`.
- CORS `origin: true` reflejando cualquier origin.
- Middleware "anti-SQL" por regex (`api/middleware/sanitize.ts:17-24`) rechaza cualquier texto con palabras como `select/update/drop` — bloquea remittance legítimos y es bypaseable. Eliminarlo (las queries ya son parametrizadas).
- Rate limiter in-memory que confía en `x-forwarded-for` sin `trustProxy`.
- PII en logs (Pino sin `redact`): debtor/creditor names, taxId, alias aparecen en plaintext.
- DLQ handler hace `ack()` en mensajes malformados (`messaging/dlq-handler.ts:50-53`) — los pierde sin huella.
- SSE endpoint `GET /events/payments` está fuera de la zona JWT-protegida (`api/routes/sse.ts`) → cualquiera en la LAN escucha todos los pagos (leak PII).
- Race en idempotencia: dos requests simultáneos con la misma key reciben respuestas inconsistentes (no se hace polling/409).
- Reconciliation job en `setInterval` sin guard de overlap.

**Medios** (selección)
- Funciones `applyTransformation/getNestedValue/setNestedValue` duplicadas byte-a-byte entre `pix-to-canonical.ts:11-84` y `spei-to-canonical.ts:11-84`.
- `Math.random()` para UUIDs/UETRs (`canonical-to-fednow.ts:177`, `breb-to-canonical.ts:121`) — usar `crypto.randomUUID()`.
- `consumer.ts:88` deduce `destination_rail` con `source_rail === 'PIX' ? 'SPEI' : 'PIX'` → todos los acks Bre-B se etiquetan como `PIX`, ensucia Grafana.
- W3C TraceContext NO se inyecta en headers AMQP — la traza se corta entre publisher y adapter.
- `Pool.on('error', ...)` solo loguea; pool muerto sigue tragando queries.
- `/health` devuelve `ok` incondicional sin probar DB/MQ.

### Adapters (PIX, SPEI, Bre-B)

**Patrones cross-rail que se repiten en los 3**:
1. `Math.random().toString(36).padEnd(N, '0')` para suffix único — colisionable y degenera a ceros.
2. `toISOString()` para construir IDs con timestamp → **siempre UTC**, no la zona horaria del riel (BRT para PIX, COT para Bre-B). En PIX cerca de medianoche el `EndToEndId` queda con la fecha del día siguiente.
3. OAuth2 client secret hard-codeado en `client.ts:19/20/21`.
4. Retry de 401 reusa el mismo `AbortController` cuyo timeout ya consumió 9s.
5. Mapper hace `strip(BREB-|PIX-|SPEI-)` defensivamente → indica que el prefijo de routing se está colando al canónico.

### `mipit-ui`

**Críticos**
- **`<Toaster />` nunca se monta** (`app/layout.tsx:14-27`) → `sonner.toast.success/error` se llama desde 4 páginas y todos los mensajes se pierden silenciosamente.
- **Origin/destination rail no se transmiten al backend** (`app/simulate/page.tsx:127-138`). El selector de riel es decorativo: la routing engine infiere todo del alias. El usuario puede elegir "PIX→Bre-B" y el sistema mandar a SPEI sin advertir → colapsa el demo de interop.
- **SSE no recibe el JWT**: `use-sse.ts:41` usa `EventSource` que no soporta `Authorization` header; ni token en URL ni cookie configurados.

**Altos**
- Componentes `pix-form.tsx/spei-form.tsx/rail-selector.tsx` son stubs TODO no importados — borrar o cablear.
- Sin validación client-side de chave/CLABE/llave (las regex existen en `lib/constants.ts:21-27` pero la validación Zod solo exige `min(3)`).
- `dashboard/service-health.tsx:119` dice "7 rails soportados" — la tesis es de 3.
- `traceId` está en el tipo pero **nunca se muestra en UI** → la promesa "observable end-to-end" es invisible para el usuario.
- Locale `es-MX` hard-coded para fechas; `en-US` para montos. BRL/MXN/COP se renderizan sin símbolo.

### `mipit-testkit`

**Críticos**
- **Cero cobertura E2E para Bre-B**: solo existen `pix-to-spei.test.ts` y `spei-to-pix.test.ts`. De los 6 pares posibles (PIX↔SPEI, PIX↔Bre-B, SPEI↔Bre-B) solo hay 2.
- **Contract tests son placebos**: `tests/contract/*.test.ts` tienen 13 `expect(true).toBe(true)` con TODO. La suite reporta verde sin verificar nada.

**Altos**
- Todos los fixtures usan `currency: 'USD'` (PIX es BRL-only, SPEI es MXN-only) → cualquier aserción FX queda inválida.
- Los CLABE generados (`generators/utils.ts:13-15`) son 18 dígitos al azar sin checksum. Los "PIX keys" generados son random base64 (no CPF/CNPJ/email/phone/EVP).
- `e2e-resilience.mjs` solo mata PIX adapter (no broker, no DB, no SPEI/Bre-B, no DLQ requeue).
- Aserciones tautológicas: `assert(queueDepth >= 0)`, `assert(status === 201 || 200 || 400)`.
- E2E poll hasta 30s sin SLO de latencia → la tesis dice "instant" pero la suite acepta 29s.

### `mipit-infra`

**Críticos**
- Secretos comiteados (`env/core.env:5` JWT, `env/postgres.env:2`, `rabbitmq/rabbitmq.conf:4`, `compose/docker-compose.yml:182` Grafana admin).
- RabbitMQ con `loopback_users.guest = false` expuesto en `:5672` + permisos `.*` para el user `mipit` → sin segmentación.
- **No hay filas Bre-B en `mapping_table`** (`db/init/003_seed_mapping_table.sql`). El adapter Bre-B traduce con código hard-codeado, anulando el diseño table-driven.
- **nginx rompe SSE**: `nginx.conf:32-38` con `proxy_buffering on` y sin `proxy_read_timeout` override → la página "Pagos en vivo" muere a los 60s en producción.

**Altos**
- DDL sin CHECK constraints (`status TEXT`, `origin_rail TEXT`, `currency DEFAULT 'USD'`). No hay columnas para `EndToEndId` ni `UETR`.
- `payments.amount > 0` no validado a nivel DB.
- Migraciones split entre `db/init/` (auto al primer boot) y `db/migrations/` (manual). `005_resilience.sql` solo está en `migrations/` — VM nueva no la tendría.
- Puerto Postgres `5432` publicado al host pese a que la suite usa `5433` por el override.
- Todas las colas son clásicas (no quorum), sin `x-max-length`, sin TTL.
- Adapters dependen solo de `rabbitmq` en compose, no de Postgres.
- Sin healthchecks salvo en postgres y rabbitmq.

### `mipit-observability`

**Críticos**
- **Prometheus scrapea puertos que no existen**: `prometheus.yml:16,23` apunta a `adapter-pix:9100` y `adapter-spei:9100`. Los adapters publican métricas en `:9101/:9102/:9103`. **Las métricas de PIX y SPEI no se están recolectando** — los paneles enseñan ceros/datos viejos.
- `postgres-exporter:9187` se scrapea pero no existe en compose.
- `prometheus.yml` no carga `alerting/rules.yaml` (`rule_files:` ausente) → todas las alertas están muertas.
- AlertManager no está desplegado.
- **El OTel collector está en archivos pero no en compose**. Apps apuntan directo a `jaeger:4318`, así que no hay batching, sampling, ni el pipeline de métricas OTel.

**Altos**
- Sin datasource de logs en Grafana → correlación trace→log es manual.
- Dashboards consultan métricas que las scrapes rotas no producen.

### `mipit-docs` — drift contra implementación

- OpenAPI dice "los rieles PIX (Brasil) y SPEI (México)" — Bre-B omitido pese a estar en routing.
- `canonical-fields.md:45` enum `source_rail: PIX, SPEI` — sin Bre-B. Y usa `source_rail`, mientras la implementación usa `origin.rail`.
- Runbook menciona colas `q.adapter.pix/spei` cuando las reales son `payments.route.{pix,spei,breb}`.
- Mapping CSVs solo PIX↔canonical y SPEI↔canonical (no hay `breb-to-canonical.csv`).
- ADR-002 sí reconoce honestamente que el canónico "no es interoperable con ISO real". Eso es positivo, pero la copy en otros docs y dashboards lo vende más fuerte.

---

## Parte II — Inconsistencias contra specs oficiales

### A) ISO 20022 pacs.008 real vs canónico MiPIT

| Campo real pacs.008.001.10 | MiPIT canonical | Estado |
|---|---|---|
| `GrpHdr.MsgId` | `grpHdr.msgId` | ✅ |
| `GrpHdr.CreDtTm` | `grpHdr.creDtTm` | ✅ |
| `GrpHdr.NbOfTxs` | `grpHdr.nbOfTxs` | ✅ pero como `number`, el wire es `string`. |
| `GrpHdr.CtrlSum` | — | ❌ |
| `GrpHdr.SttlmInf.SttlmMtd` | opcional | ⚠️ real es mandatorio |
| `GrpHdr.SttlmInf.ClrSys.Cd` | — | ❌ |
| `GrpHdr.InitgPty` | — | ❌ mandatorio en CBPR+ |
| `CdtTrfTxInf.PmtId.EndToEndId` | `pmtId.endToEndId` | ✅ |
| `CdtTrfTxInf.PmtId.UETR` | — | ❌ **CRÍTICO** mandatorio en .001.10 y CBPR+ (UUIDv4) |
| `CdtTrfTxInf.PmtTpInf` | — | ❌ |
| `CdtTrfTxInf.IntrBkSttlmAmt{Ccy,value}` | `amount.{currency,value}` separados | ⚠️ shape divergente |
| `CdtTrfTxInf.IntrBkSttlmDt` | — | ❌ |
| `CdtTrfTxInf.ChrgBr` (DEBT/CRED/SHAR/SLEV) | — | ❌ mandatorio |
| `DbtrAgt.FinInstnId.BICFI` | `origin.bic` opcional | ⚠️ |
| `CdtrAgt.FinInstnId.BICFI` | `destination.bic` opcional | ⚠️ |
| `Purp.Cd` (catálogo ISO) | `purpose: string` libre | ⚠️ |
| `RmtInf.Ustrd` | `remittanceInfo` | ✅ |

**Veredicto**: lo que se llama "pacs.008" es un JSON plano inspirado. Hay dos rutas honestas:
- **Renombrar** a "MiPIT Internal Canonical Model (pacs.008-derived)" en OpenAPI/ADR/UI/dashboards y dejar una tabla de deltas explícita.
- **Alinear** agregando UETR (UUIDv4 mandatorio), ChrgBr, IntrBkSttlmDt, InitgPty, SttlmInf.ClrSys, modelando amount como `{Ccy, value}`, y separando DbtrAgt/CdtrAgt de origin/destination.

Otra evidencia de la incoherencia: `canonical-to-iso20022-mx.ts:33` accede al settlement method con `(canonical.grpHdr as Record<string,unknown>)?.sttlmInf as Record<string,unknown>?.['sttlmMtd']` — un cast atroz que delata que schema y emitter no concuerdan.

### B) PIX — qué dice BCB vs qué hace MiPIT

| Spec BCB | MiPIT | Severidad |
|---|---|---|
| EndToEndId = `E + ISPB(8) + UTC-3 YYYYMMDDHHmm + 11 alnum` (32 chars) | `E2E-${ulid()}` (30 chars, empieza con `E2E-`) en `pix-to-canonical.ts:173`. El adapter `mapper.ts:184-185` arma con `toISOString()` → **UTC en lugar de BRT** → fecha errada cerca de medianoche. | **CRÍTICO** |
| Suffix `[A-Za-z0-9]{11}` | Mock acepta solo `[A-Z0-9]{11}` (`mock-server.ts:110`); rechazaría EndToEndIds reales con minúsculas. | Alto |
| `valor` debe ser string `"110.00"` | Adapter manda número/string sin garantía. | Medio |
| `horario` (timestamp del PIX completado) | Se **descarta** en `pix-to-canonical.ts:117-148`; el normalizer (`date-rules.ts:19`) sobreescribe con `new Date().toISOString()`. La marca temporal original se pierde. | **CRÍTICO** |
| Validación checksum CPF mod-11 (pesos 10..2 + 11..2) | Mock solo valida con regex `\d{11}` → `00000000000` pasa. | Alto |
| Validación checksum CNPJ mod-11 (pesos 5,4,3,2,9,8,7,6,5,4,3,2 + segunda pasada) | No se valida. | Alto |
| DICT consultation `GET /v2/dict/{key}` antes de transferir | No existe en el adapter ni en el mock. | Alto |
| SPI 24/7/365 (Resolução BCB 1/2020 art. 24) | Mock implementa "M-F 07:00-23:59, Sáb 07:00-17:59, Dom cerrado" (`mock-server.ts:71-82`). El core (`config/constants.ts:140`) tiene `start=0700 end=2359` → bloquea PIX entre 00:00-07:00. | Alto |
| Endpoint público real es `/v2/cob` (PSP-side); SPI es XML sobre RSFN | Nuestro mock expone `POST /spi/v2/pagamentos` — endpoint inventado. Una swap-base-URL contra el mundo real no tendría un endpoint compatible al otro lado. | Medio (limitación PoC) |
| OAuth2 + mTLS con certificados ICP-Brasil, scopes `cob.write cob.read pix.read pix.write` | OAuth2 Bearer mock con scope inventado `'spi.pagamentos'`, sin mTLS. | Medio |
| ISPB es 8 dígitos asignado por BACEN | Hard-coded `'26264220'` (`types.ts:175`) sin nota de "simulado". | Alto |

### C) SPEI — qué dice Banxico vs qué hace MiPIT

| Spec Banxico/STP | MiPIT | Severidad |
|---|---|---|
| **`institucionContraparte` = 5 dígitos** del catálogo Banxico (`40072` Banorte, `40012` BBVA Bancomer, `90646` STP) | El adapter declara códigos de **3 dígitos** (`'072'`, `'002'`) en `types.ts:157-168`, derivándolos del prefijo CLABE. **STP los rechazaría inmediatamente**. | **CRÍTICO** |
| `claveRastreo` 1-30 alfanumérico **únicamente** (sin guiones/underscores), único por originador/día | Mock acepta `[A-Z0-9a-z\-_]{1,30}` (`mock-server.ts:109`). Core manda el `endToEndId = E2E-${ulid()}` con guion como `claveRastreo` (`canonical-to-spei.ts:20`). STP también rechazaría. | **CRÍTICO** |
| **`firma`**: RSA-PKCS#1 v1.5 + SHA-256 sobre canonical pipe-joined `empresa\|claveRastreo\|...` | El mock implementa OAuth2 Bearer (no usado por STP). **STP no usa OAuth2**, usa firma RSA con certificado. Una swap-base-URL contra STP demo falla en el primer request. | **CRÍTICO** |
| CLABE 18 dígitos con mod-10 ponderado (3,7,1...) | ✅ El validator (`clabe-validator.ts:23`) es **correcto**. El check digit se calcula bien. | OK |
| `tipoCuentaBeneficiario` 40=CLABE / 3=tarjeta / 10=celular | Hard-coded `40`, no se valida formato si fuera 3 o 10. | Medio |
| `tipoPago` catálogo de 31 valores (1, 3, 4, 5, 8, 11-17, ...) | Adapter declara `1\|2\|3\|4` (`types.ts:63`), hard-coded `1` en `mapper.ts:81`. | Alto |
| `referenciaNumerica` numérico 1-9999999 | Mock acepta `[0, 9_999_999]` → cero (reservado/sentinela en muchos sistemas) pasa. | Medio |
| `conceptoPago` ASCII-printable, sin diacríticos (CECOBAN XML-encoded) | Mapper trunca a 39 chars pero no strip-diacritics. "Pago de café" pasa, STP rechazaría. | Medio |
| Operativa M-F 06:00-17:55 CT + ventana settlement hasta 18:00 (Circular 14/2017) | Mock M-F 07:00-17:30 (`mock-server.ts:64-73`). Hora errada. | Alto |
| RFC con dígito verificador (mod-11 base-37) | Mock solo regex de forma (`[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}`). | Medio |
| CURP con dígito verificador | Solo regex de forma. | Medio |
| FX: monto debe ser MXN, no la divisa original | `canonical-to-spei.ts:23` manda `monto: canonical.amount.value, moneda: canonical.amount.currency` ignorando `canonical.fx.local_amount`. **Una transferencia 100 BRL → SPEI llega como `monto: 100, moneda: 'BRL'` ≈ 5× el valor real**. | **CRÍTICO** |

### D) Bre-B — qué dice BanRep vs qué hace MiPIT

BanRep lanzó Bre-B en 2025 pero **no hay spec de wire-format público**. Eso es defendible para PoC; lo que NO es defendible es que el código y los comentarios afirmen fidelidad a una "BanRep specification v1.0 (2023)" que no existe (`mock-server.ts:8`).

| Spec BanRep | MiPIT | Severidad |
|---|---|---|
| Llaves: **CC (cédula), CE (extranjería), NIT, Pasaporte, celular `+57 3XX XXXXXXX`, email, alfanumérica con `@` y opcional `.`/`_`** | Adapter declara `TELEFONO\|NIT\|EMAIL\|ALIAS` (`types.ts:12`). **Faltan CC, CE, Pasaporte**. La regex de alfanumérica `^[A-Za-z0-9]{4,20}$` rechaza el prefijo `@` que BanRep especifica. | **CRÍTICO** |
| Celular: `+57` + 10 dígitos empezando en **`3`** (móvil) | Mapper acepta `^\+57\d{10}$` — entran fijos `+57 1 xxx xxxx`. | Alto |
| Códigos de entidad: 4 dígitos de Superfinanciera (Bancolombia=`007`, Davivienda=`051`, Banco de Bogotá=`001`) | `pagador.codigoEntidad` declarado como **8 dígitos** (`types.ts:81`, `mock-server.ts:109`). `BREB_ENTITY_CODES` zero-paddea a 8 e incluso duplica BBVA_COLOMBIA y BANCO_DE_BOGOTA al mismo `'00000013'`. | Alto |
| Límites: BanRep inició con ~COP 10M; algunos analistas citan COP 4M para natural retail | Mock `LIMIT_NATURAL_COP = 20_000_000` y `LIMIT_JURIDICA_COP = 200_000_000` — un orden de magnitud arriba. | Alto |
| Bre-B es 24/7/365 | ✅ Mock no bloquea por horario. ⚠️ Core `config/constants.ts:142` define `06:00-22:00 weekdays` → contradice. | Alto |
| Directorio Bre-B (análogo a DICT) consultado pre-transferencia | No existe. Error `BREB004 receptor no registrado` se dispara al azar. | Medio |
| `idTransaccion` — formato no publicado | Inventado: `BR + entidad(8) + YYYYMMDD + HHmm + 10 alnum`; mismo bug de UTC en lugar de COT (UTC-5). | Medio |

Sobre el prefijo `BREB-`: se inyecta en el API público (`payment-request.ts:38`), se strip-ea en `canonical-to-breb.ts:43`, y el adapter vuelve a strip-earlo defensivamente en `mapper.ts:58`. **Triple manipulación del mismo string** — síntoma de que el routing concern está leak-eando al canónico. Igual patrón con `PIX-` y `SPEI-` en los otros dos.

---

## Parte III — ¿La tesis cumple? (claim-by-claim)

| Claim de la tesis | Veredicto | Justificación |
|---|---|---|
| "3 rieles instantáneos funcionan" | ⚠️ **Parcial** | PIX↔SPEI sí (con caveats de formato). Bre-B está cableado en compose, routing y dashboards pero: 0 tests E2E, 0 filas en `mapping_table`, ausente en OpenAPI/runbook/CSVs, llaves con formato inventado. Mejor caracterizarlo como "desplegado pero no verificado" o limitar la tesis a 2 rieles + 1 placeholder. |
| "ISO 20022 pacs.008 como modelo canónico" | ⚠️ **Débil** | ADR-002 admite que es "JSON alineado, no interoperable con ISO real". OpenAPI/dashboards lo venden más. Faltan UETR, ChrgBr, IntrBkSttlmDt, InitgPty, SttlmInf.ClrSys, BICFI. Tres artefactos internos (canonical-fields.md / mapping_table / shape en testkit) discrepan entre sí. |
| "Pagos en tiempo real" | ⚠️ **No validado** | E2E acepta hasta 30s; sin SLO `<10s` enforced. Latencia de mocks es sub-segundo, así que la demo se ve rápida, pero la suite no falla si regresiona a 25s. |
| "Cross-border / cross-currency" | ❌ **Roto** | FX se calcula en `currency-rules.ts` pero los adapters (excepto FedNow) ignoran `canonical.fx.local_amount`. BRL→MXN llega a SPEI como `100 BRL`. La interoperabilidad cross-currency está estructuralmente mal. |
| "Observabilidad end-to-end" | ⚠️ **Parcial** | Jaeger/Prom/Grafana desplegados pero: scrapes de adapter PIX/SPEI rotos (puerto 9100 vs 9101/9102), OTel collector no desplegado, AlertManager ausente, alert rules no cargadas, sin datasource de logs, sin TraceContext en headers AMQP (la traza se corta entre publisher y adapter), UI nunca muestra `traceId`. |
| "Mensajería async con resiliencia" | ⚠️ **Parcial** | RabbitMQ + DLQ + reconnect existen, pero: publisher sin confirms, reconnect no re-attach consumers, DLQ handler `ack` mensajes malformados, colas clásicas (no quorum), sin TTL ni max-length, sin transactional outbox. |
| "Mock-fidelity → swap base URL = producción" | ❌ **No** | PIX usa endpoint inventado `/spi/v2/pagamentos` (real PSP es `/v2/cob` + RSFN XML). SPEI usa OAuth2 + códigos 3-dig (STP usa firma RSA + códigos 5-dig). Bre-B inventa todo. Ninguno aguanta una swap real. |

---

## Parte IV — Plan de remediación priorizado (para defender la tesis con integridad)

### Bloque 1 — Antes de la sustentación (1 semana)
1. **Renombrar** el canónico de "pacs.008" a "MiPIT Internal Canonical (pacs.008-derived)" en OpenAPI, dashboards, UI, ADR-002 ya lo dice — propagar coherentemente.
2. **Agregar UETR (UUIDv4) y ChrgBr al canónico**, persistirlos en `payments`, y reusarlos en toda la cadena de mensajes (un solo UETR por pago).
3. **Fix PIX EndToEndId**: implementar `generatePixE2EId(ispb, brtTimestamp)` con formato exacto BCB, marcar `MIPIT_FAKE_ISPB` como "simulado" en el código y la tesis.
4. **Fix FX**: los 3 outbound translators (`canonical-to-pix`, `canonical-to-spei`, `canonical-to-breb`) deben leer `canonical.fx.local_amount/target_currency` si existe.
5. **Fix SPEI institutionCode**: usar catálogo 5-dígitos Banxico y mapear correctamente. Agregar `claveRastreo` generation que cumpla `^[A-Za-z0-9]{1,30}$` (sin guion).
6. **Documentar Bre-B como "implementación de referencia, formato wire inventado"** porque BanRep no ha publicado el formato. Agregar al menos 1 test E2E y filas en `mapping_table`.
7. **Fix observability scrapes**: cambiar `prometheus.yml` a `:9101/:9102/:9103`. Quitar `postgres-exporter` o agregarlo a compose. Cargar `rule_files`.
8. **Mostrar `traceId` en la UI** de detalle de pago, con link a Jaeger.
9. **Montar `<Toaster />`** en `layout.tsx`. Sin esto el demo se ve roto.

### Bloque 2 — Hardening (2 semanas opcionales)
10. Outbox transaccional para publicación a RabbitMQ.
11. `confirmChannel` + `waitForConfirms` en publisher.
12. Reconnect handler que re-registre consumers.
13. CHECK constraints en DDL para `status`, `origin_rail`, `destination_rail`, `amount > 0`, `currency IN (...)`.
14. Validación checksum CPF/CNPJ/CURP/RFC en mocks (algoritmos publicados, ~50 líneas cada uno).
15. Pino `redact` para PII; CORS hard-coded; JWT con `algorithms: ['HS256']` y `iss/aud`.
16. Llaves Bre-B completas (CC, CE, Pasaporte) con regex correctas, prefijo `@` para alfanumérica.
17. Borrar el middleware regex anti-SQL; las queries ya son parametrizadas.
18. Eliminar el componente "service-health soporta 7 rails" — la tesis es 3.
19. Tests E2E para los 6 pares de rieles (PIX↔SPEI, PIX↔Bre-B, SPEI↔Bre-B).
20. SLO de latencia en E2E (`<10s` por riel).

### Bloque 3 — Honestidad académica (siempre)
- Agregar a la tesis una **sección de limitaciones** explícita que enumere:
  - Canónico es subset de pacs.008, sin UETR/ChrgBr/IntrBkSttlmDt/InitgPty hasta que se implemente.
  - Mocks no son fiel-byte de la API real; específicamente PIX usa endpoint inventado, SPEI no implementa firma RSA, Bre-B no tiene spec pública que mockear.
  - Sin certificados ICP-Brasil/HSM/mTLS — fuera de scope académico.
  - No hay verificación de checksums CPF/CNPJ/RFC/CURP/CLABE-D-extra.
  - FX es estática con tabla in-memory, no consume API real.

Hacer esto explícito convierte una "incosistencia oculta" en una "limitación documentada", que es lo que un panel académico valora.

---

## Fuentes consultadas

- ISO 20022 pacs.008.001.10 (Clearstream usage guideline; SWIFT/CBPR+ reference)
- BCB API Pix v2.9.0 OpenAPI: https://bacen.github.io/pix-api/index.html
- BCB Manual de Padrões para Iniciação do Pix
- BCB Resolução nº 1/2020 (SPI 24/7)
- BCB API DICT v2.X
- Banxico Circular 14/2017
- Banxico Catálogo de Participantes SPEI (códigos 5-dígitos)
- STP WADL + cuenca-mx/stpmex-python (firma RSA-SHA256)
- Banco de la República — Documento técnico Bre-B (feb-2026)
- Decreto 1297/2022 (Colombia, pagos inmediatos interoperables)
- SWIFT — ISO 20022 Programme materials
- Fedwire ISO 20022 FAQs
