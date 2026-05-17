# A5 — Inconsistencias Internas + Deuda No Documentada (Audit 2)

**Fecha:** 2026-05-17 · **Branch:** `Auditoria-Claude` · **Scope:** discrepancias docs ↔ código, tipos duplicados, tests placebo, deps huérfanas.

## 1. Top 10 hallazgos críticos

| # | ID | Severidad | Hallazgo | Ubicación |
|---|---|---|---|---|
| 1 | A1 | Inconsistencia (Crítica) | `mappings/canonical-fields.md` describe canónico FLAT (`canonical.msg_id`, `canonical.debtor.alias_type` con `CPF/CNPJ/PHONE/EMAIL/EVP/CLABE/PHONE_MX/CARD`) que **NO existe en código**. Canónico real es pacs.008-derived (`grpHdr.msgId`, `pmtId.endToEndId`, `alias.type` con `PIX_KEY/CLABE/IBAN/ACCOUNT/ABA_ROUTING/BIC/LLAVE_BREB`) | `mipit-docs/mappings/canonical-fields.md` vs `mipit-core/src/domain/models/canonical.ts:8,209` |
| 2 | A2 | Inconsistencia (Crítica) | 4 CSV mappings (`canonical-to-pix.csv`, `pix-to-canonical.csv`, etc.) referencian canónico FLAT antiguo (`canonical.instructing_agent`, `canonical.number_of_txs`, `canonical.settlement_method`). Campos no existen | `mipit-docs/mappings/*.csv` |
| 3 | B1 | Inconsistencia (Alta) | UI `constants.ts:STATUS_CONFIG` + `lib/types.ts:PaymentStatus` tienen **solo 13 estados** (falta `NORMALIZED`). DB CHECK + core + OpenAPI tienen 15. CONTEXTO dice "14 chips" pero UI muestra 13 | `mipit-ui/src/lib/constants.ts:3-18`, `lib/types.ts:3-17` vs `canonical.ts:15-31`, `008_*.sql:13-18`, `openapi.yaml:615-629` |
| 4 | E1 | Tests placebo (Crítica) | 5 tests con `expect(true).toBe(true)` + 4 archivos casi 100% TODOs (`pipeline.test.ts:54,59`, `translation.test.ts:101-103`, `idempotency-e2e.test.ts:56`, `openapi-validation.test.ts:185`) | `mipit-testkit/tests/integration/{pipeline,translation,idempotency,core-api}.test.ts`, `tests/e2e/{idempotency-e2e,error-scenarios}.test.ts` |
| 5 | E2 | Inconsistencia (Alta) | Test `translation.test.ts:81,82,93,94` afirma sobre `detail.canonical?.debtor?.rail` y `creditor?.rail` que **no existen** en schema real (que usa `origin.rail/destination.rail`). Test "verde" por skip silencioso | `mipit-testkit/tests/integration/translation.test.ts:73-94` |
| 6 | D1 | Inconsistencia (Alta) | AlertManager configurado POST a `http://core:8080/webhooks/alertmanager` — **endpoint no existe en core**. OpenAPI lo documenta (`openapi.yaml:361-371`) y CONTEXTO lo lista, pero `mipit-core/src/api/server.ts` no lo registra. `/webhooks/payment-completed` tampoco existe | `mipit-observability/alertmanager/alertmanager.yml:24`, `openapi.yaml:361-383` |
| 7 | C1 | Inconsistencia (Alta) | SPEI window: LIMITATIONS y CONTEXTO dicen `L-V 06:00-17:55 CT`, core (`constants.ts:143`) confirma `600-1755`, pero mock (`mock-server.ts:64-73, 195`) usa `07:00-17:30 CST`. Plan P03 explícitamente exige 06:00-17:55 | `mipit-adapter-spei/src/spei/mock-server.ts:64-73,195` vs `constants.ts:143` y `LIMITATIONS.md:16` |
| 8 | D2 | Deuda (Alta) | ADR-006 dice "Kysely o Knex como query builder". Código usa **`pg` raw** con `pool.query('SELECT…')` | `ADR-006-postgres-persistence.md:17-18` vs `mipit-core/src/persistence/db.ts:1,8` |
| 9 | G1 | Inconsistencia (Alta) | `mipit-core/src/messaging/rabbitmq.ts` es **dead code**. Define `connectRabbitMQ()` sin confirms; no importado en ningún sitio. Conexión real vía `RabbitMQReconnector` con `useConfirmChannel: true` | `mipit-core/src/messaging/rabbitmq.ts` (todo el archivo) |
| 10 | F1 | Tres-vías inconsistencia | rail_ack.status: core define `ACCEPTED/REJECTED/ERROR/PENDING` (4), UI tiene `ACCEPTED/REJECTED/ERROR` (3, sin PENDING), OpenAPI define `ACCEPTED/REJECTED/PENDING` (3, sin ERROR) | `canonical.ts:231`, `mipit-ui/src/lib/types.ts:49`, `openapi.yaml:495` |

## 2. Hallazgos por categoría

### A. Coherencia del canónico

| ID | Severidad | Hallazgo |
|---|---|---|
| A1 | Crítica | `canonical-fields.md:9-46` describe campos inexistentes (msg_id, creation_date_time, number_of_txs, settlement_method, instructing_agent, debtor.alias flat, debtor.alias_type, purpose flat, remittance_info, source_rail) |
| A2 | Crítica | 4 CSVs usan modelo flat. Traductor real (`pix-to-canonical.ts:137-200`) emite `{grpHdr, pmtId, amount, origin, destination, debtor, creditor, alias}` |
| A3 | Alta | OpenAPI `CanonicalPacs008` (line 540-595) usa `intrBkSttlmAmt` y `rmtInf.ustrd` (array). Código (`canonical.ts:134-140`) usa `amount` y `remittanceInfo` (single string max 140). Híbrido |
| A4 | Media | OpenAPI no declara `fx/rail_ack/status/trace_id/reference/purpose` en CanonicalPacs008. Schema los tiene |
| A5 | Alta | `translation-layer.md:79` lista solo 6 valores de `alias.type`. Omite `LLAVE_BREB` que sí existe en `canonical.ts:8` |
| A6 | Media | `translation-layer.md:65` documenta `institutionCode?: string // BANXICO 3 dígitos`. `canonical.ts:163,175` usa `z.string().max(8)` |
| A7 | Media | OpenAPI `CanonicalParty` (line 597-606) tiene `{name, alias, alias_type, account, agent_id}`. Schema real (`canonical.ts:178-211`) modela `{name, country, account_id, taxId, accountType, agencia, email, phone, address}` con `alias` como objeto top-level. Total desalineación |

### B. Coherencia status enum

Comparativa de las 4 fuentes:

| Status | canonical.ts | 008_*.sql | OpenAPI | UI (constants + types) |
|---|---|---|---|---|
| RECEIVED | ✓ | ✓ | ✓ | ✓ |
| VALIDATED | ✓ | ✓ | ✓ | ✓ |
| CANONICALIZED | ✓ | ✓ | ✓ | ✓ |
| **NORMALIZED** | ✓ | ✓ | ✓ | **✗ FALTANTE** |
| ROUTED → DEAD_LETTER | ✓ | ✓ | ✓ | ✓ |

- **B1 (Alta):** Si payment llega a UI con `NORMALIZED`, `STATUS_CONFIG[NORMALIZED]` = undefined → **crash en render del badge**. Reproducible en cualquier query/SSE que muestre payment recién normalizado
- **B2 (Media):** CONTEXTO:121-125 dice "14 estados" pero enumera 15. Aclara más abajo "15 si se cuenta NORMALIZED; UI agrupa NORMALIZED dentro CANONICALIZED → 14 chips". El "agrupado" no está implementado — UI simplemente no maneja NORMALIZED. **Doc racionaliza un bug**

### C. Coherencia rail enum + alias prefixes

| Variante | Significado | Donde |
|---|---|---|
| `BRE_B` | Código interno (canonical, DB, prom labels, RMQ env_name) | `canonical.ts:4`, `008_*.sql:23`, `constants.ts:33` |
| `Bre-B` | Nombre humano con dash | `LIMITATIONS.md`, CONTEXTO, `RAIL_METADATA.BRE_B.name='Bre-B'` (constants.ts:108) |
| `BREB-` | Prefijo alias con dash | hardcoded en 8+ archivos: `payment-pipeline.ts:309`, `breb-to-canonical.ts:144`, `payment-request.ts:39`, `route-engine.ts:85`, `mipit-ui/lib/constants.ts:27`, `openapi.yaml:459` |
| `breb` | Lowercase routing key suffix | `ROUTING_KEYS.ROUTE_BREB='route.breb'` (constants.ts:124), `payments.route.breb` queue |

- **C1 (Alta):** Prefix NO debería estar hardcoded en 5+ archivos. Hay constante `RAIL_CONFIG.BRE_B.aliasPrefix='BREB-'` en UI pero core lo repite literal

### D. Coherencia ADRs vs código

| ID | Severidad | ADR claim | Realidad |
|---|---|---|---|
| D1 | Alta | ADR-008 + LIMITATIONS implican `/webhooks/alertmanager`. AM lo llama | **Endpoint no existe**. AlertManager 404 forever |
| D2 | Alta | ADR-006: "Kysely o Knex" | Código `pg` directo `pool.query('SELECT…')`. Sin builder |
| D3 | Media | ADR-006: "migraciones manejadas por core al iniciar" | Migraciones SQL en `mipit-infra/db/migrations/`. Ejecutadas por `scripts/migrate.sh` externo, NO por core |
| D4 | Media | ADR-006 no menciona rollbacks | No hay scripts `*-down.sql`. Numbers gap: 004, 005, 008, 009, 010, 011, 013 (faltan 006, 007, 012) |
| D5 | Baja | ADR-002 lista `RmtInf.Ustrd` implementado | `canonical.ts:217` lo modela como single string max 140, no array. OpenAPI sí usa array. Inconsistente |
| D6 | Alta | ADR-003 + ADR-007: RabbitMQ topic + confirms | OK en core. **Pero adapters** (pix/spei/breb) usan `createChannel()` plain (sin confirms en publicación ACK). Asimétrico |
| D7 | Alta | ADR-007: "hybrid modular" con módulos validator/translator/router/state-machine | Módulo "state-machine" NO existe. Hay `payment-pipeline.ts` con transiciones implícitas |
| D8 | Baja | ADR-008: "logs JSON estructurados a stdout, recolectados por Docker" | OK pero sin agente shipping (Loki/Promtail/fluentd) |
| D9 | Media | `architecture-overview.md:43`: "reglas YAML" para route engine | NO hay YAML. Reglas en Postgres vía `RuleLoader` (`mipit-core/src/routing/rule-loader.ts`) |

### E. Tests placebo y rotos

| ID | Test | Problema |
|---|---|---|
| E1.1 | `pipeline.test.ts:51-60` | Dos `it()` con `expect(true).toBe(true)` + TODOs en comentarios |
| E1.2 | `pipeline.test.ts:27` | Tests "reales" sin auth header (darán 401). Referencian `'TRANSLATED'` que **no es estado válido** |
| E1.3 | `translation.test.ts:101-103` | `it('inverse direction covered…', () => expect(true).toBe(true))` |
| E1.4 | `translation.test.ts:71-94` | Asserts sobre `detail.canonical?.debtor?.rail` que **no existe**. Skip silencioso |
| E1.5 | `tests/integration/idempotency.test.ts` | TODO comments exclusivos, sin un solo `expect` |
| E1.6 | `tests/integration/core-api.test.ts` | TODO comments exclusivos |
| E1.7 | `tests/e2e/idempotency-e2e.test.ts:56` | `expect(true).toBe(true)` |
| E1.8 | `tests/e2e/error-scenarios.test.ts:24-35` | TODOs sin asserts |
| E1.9 | `tests/contract/openapi-validation.test.ts:178-187` | "Skips live-stack tests when API unreachable" → `expect(true).toBe(true)` |
| E2.1 | `mipit-core/test/e2e/error-scenarios.test.ts` y `error-scenarios-simplified.test.ts` | **Duplicación**. 2 archivos similares, ~16+ tests duplicados |
| E3 | `pix-valid-01.json` y otros datasets | `"currency": "USD"` en PIX-payload — debería ser BRL. También en `pix-invalid-amount.json`, `pix-to-canonical-01.json`, expected files |

### F. Mock fidelity gaps NO documentadas en LIMITATIONS

| ID | Severidad | Hallazgo |
|---|---|---|
| F1 | Alta | rail_ack.status 3-way: core 4 valores, UI 3 sin PENDING, OpenAPI 3 sin ERROR. TS rechaza interop |
| F2 | Alta | PIX mock comenta línea 1-30: "Endpoint POST /spi/v2/pagamentos es **invented**. Real BCB expone /v2/cob…, /v2/cobv/…, /v2/pix/{e2eid}. SPI itself is XML over RSFN, no public REST". LIMITATIONS solo dice "no conectado al DICT oficial" — NO menciona endpoint REST inventado |
| F3 | Alta | BREB mock comenta línea 1-25: error codes BREB001-005 **inventados**, no del catálogo BanRep. LIMITATIONS dice "TR-002 schema", insinuando fidelity |
| F4 | Media | SPEI mock implementa OAuth2 client_credentials. SPEI/CECOBAN real **no usa OAuth** — TCP/SSL con backbone vía firmware bancario propietario. OAuth en mock es totally ficcional, no flagged |
| F5 | Media | OAuth secrets hardcoded en 6 archivos (3 adapters × 2: client.ts + oauth-mock.ts) |
| F6 | Media | LIMITATIONS dice "Bre-B mobile-only +57 prefijo 3". OK en mock (`mock-server.ts:69` `^\+573\d{9}$`). PERO `payment-request.ts` core acepta `^\+57\d{10}$` (sin restricción móvil). Core laxo, mock estricto |
| F7 | Baja | PIX mock declara "Endpoint legacy /pix/payments" (`mock-server.ts:352-`) que el adapter no usa. Code arqueológico |

### G. TODOs / FIXMEs / dead code

#### TODOs activos (36 total, sin tracking issue)

| File:line | Texto |
|---|---|
| `mipit-ui/src/components/payments/payment-card.tsx:8,13` | `TODO: Card summary` (stub) |
| `mipit-ui/src/components/payments/payment-status-badge.tsx:11` | `TODO: Style with shadcn/ui` |
| `mipit-ui/src/components/simulate/{payment,pix,spei}-form.tsx:4-16` | TODOs (stubs) |
| `mipit-testkit/tests/integration/pipeline.test.ts` | 6 TODOs |
| `mipit-testkit/tests/integration/idempotency.test.ts` | 6 TODOs |
| `mipit-testkit/tests/integration/core-api.test.ts` | 7 TODOs |
| `mipit-testkit/tests/e2e/error-scenarios.test.ts` | 2 TODOs |
| `mipit-testkit/tests/e2e/idempotency-e2e.test.ts` | 6 TODOs |

#### Dead code / unused

| File | Estado |
|---|---|
| `mipit-core/src/messaging/rabbitmq.ts` | **No importado** en ningún sitio. Conexión real vía `RabbitMQReconnector` |
| `mipit-core/src/persistence/repositories/payment.repository.ts:274` | `@deprecated Use updateRailAck()` sin tracking |
| `mipit-adapter-breb/src/breb/types.ts:125` | `@deprecated Use SUPERFIN_ENTITY_CODES` sin issue |
| `mipit-adapter-pix/src/pix/mock-server.ts:352-` | Legacy `/pix/payments` endpoint |
| `mipit-ui/src/components/{payments,simulate}/*.tsx` | 5 componentes solo con `TODO:` strings |
| `mipit-core/test_8.md`, `test_7.md` | Archivos de notas en `src` root |

### H. Strings hardcoded duplicados

```
prefijo_rail (PIX-, SPEI-, BREB-)
├── mipit-core/src/pipeline/payment-pipeline.ts:307-309 (inferRail)
├── mipit-core/src/api/schemas/payment-request.ts:33-39 (validator)
├── mipit-core/src/routing/route-engine.ts:83-85 (inferAliasType)
├── mipit-core/src/translation/pix-to-canonical.ts:20 (strip prefix)
├── mipit-core/src/translation/spei-to-canonical.ts:20 (strip prefix)
├── mipit-core/src/translation/breb-to-canonical.ts:144 (strip prefix)
├── mipit-ui/src/lib/constants.ts:21-27 (aliasPrefix)
├── mipit-docs/openapi/openapi.yaml:111,121,129,457-459 (examples + schema)
└── mipit-docs/mappings/*.csv (legacy refs)

OAuth secrets (mipit-secret-{rail}-2024)
├── mipit-adapter-pix/src/pix/client.ts:19
├── mipit-adapter-pix/src/pix/oauth-mock.ts:25
├── mipit-adapter-spei/src/spei/client.ts:19
├── mipit-adapter-spei/src/spei/oauth-mock.ts:25
├── mipit-adapter-breb/src/breb/client.ts:21
└── mipit-adapter-breb/src/breb/oauth-mock.ts:25

TTL 5 minutos
├── mipit-core/src/translation/mapping-loader.ts:10 (TTL_MS = 5*60*1000)
└── mipit-core/src/fx/fx-service.ts:56 (CACHE_TTL_MS = 5*60*1000)

Error codes inventados sin enum
├── BREB001-005 hardcoded en mipit-adapter-breb/src/breb/mock-server.ts
├── AM01-AC03-AB03-AM04-BE01-DS04-RR04 hardcoded en mipit-adapter-pix/src/pix/mock-server.ts
└── R01-R04, R08, LIM en mipit-adapter-spei/src/spei/mock-server.ts
```

### I. Dependencias huérfanas/faltantes

| Repo | Dep | Estado |
|---|---|---|
| mipit-core | `@opentelemetry/exporter-prometheus` | ORFAN — no importado |
| mipit-core | `@opentelemetry/api` | FALTANTE — usado en `observability/{logger,otel}.ts` vía transitive abuse |
| mipit-ui | `@radix-ui/react-{dialog,label,select,slot,toast}` | ORFAN x5 |
| mipit-ui | `class-variance-authority` | ORFAN |
| mipit-adapter-{pix,spei,breb} | `ts-node` | ORFAN x3 — proyecto usa tsx |
| mipit-ui | `ts-node` | ORFAN — usa ts-jest |
| mipit-testkit | `ts-node` | ORFAN — usa tsx |
| mipit-adapter-* vs core | OTel versions | MISMATCH (`^0.57.0/^1.30.0` vs `^0.218.0/^2.7.1`) |

| Repo | Orfan count | Total deps | % grasa |
|---|---|---|---|
| mipit-ui | 6 + ts-node | 19 | ~37% |
| mipit-core | 1 + 1 faltante | 18 | ~10% |
| mipit-adapter-pix | 1 (ts-node) | 11 | ~10% |
| mipit-adapter-spei | 1 (ts-node) | 11 | ~10% |
| mipit-adapter-breb | 1 (ts-node) | 11 | ~10% |
| mipit-testkit | 1 (ts-node) | 7 | ~14% |

## 6. Recomendaciones — Single Source of Truth (5)

### R1. Canonical schema → fuente única
**Problema:** 4 representaciones del canónico (canonical-fields.md, mappings CSV, openapi.yaml, canonical.ts). Las primeras 2 mienten; la 3a es subset.
**Acción:** Generar OpenAPI desde Zod (`zod-to-openapi`). Borrar `canonical-fields.md` y mappings CSV legacy. Una sola fuente: `canonical.ts`.

### R2. Status enum + Rail enum compartidos
**Problema:** UI hardcodea 13 estados (falta NORMALIZED). Constants duplicados en 3+ archivos.
**Acción:** Paquete TS interno `@mipit/shared-types` (monorepo workspace) consumido por core + UI + adapters. Zod schemas + ts types + JSON Schema. PAYMENT_STATUS_ENUM y RAILS importados desde ahí.

### R3. Constantes rail prefix + parsers
**Problema:** `PIX-`, `SPEI-`, `BREB-` repetidos en 8+ archivos del core con lógica `startsWith` duplicada.
**Acción:** `RAIL_PREFIX` map + función `parseRailAlias(alias)` → `{rail, value}`. Test único, refactor all sites.

### R4. OAuth secrets + URLs en config
**Problema:** Secretos en 6 archivos × 3 adapters, URLs sandbox hardcoded.
**Acción:** Mover a env vars (`PIX_OAUTH_CLIENT_SECRET`, etc.). Validar con Zod `.min(16)`. Documentar en LIMITATIONS.md.

### R5. Test policy — eliminar placebos
**Problema:** 5 tests `expect(true).toBe(true)` + 9 archivos integration/e2e 90% TODOs. Skipping silencioso hace suite "11/11 verde" engañosa.
**Acción:**
- Borrar archivos TODO-only o convertir TODOs en `it.todo('…')` (Jest los reporta como pending, no como passed)
- Eliminar `expect(true).toBe(true)`; convertir a `it.skip(…)` con razón
- CI gate: detectar `expect(true)` con lint rule (eslint `jest/no-truthy-only-assertions`)

## 7. Cobertura vs auditoría 1

Auditoría 1 (2026-05-16) cubrió:
- Wave 1-4 fixes (P01-P12) ya remediados
- SPEI institution code 3 vs 5 dígitos
- PIX SPI vs REST API real
- BREB error codes inventados

Auditoría 2 (esta) enfoca en lo **NO cubierto previamente**:
- Drift docs ↔ código (mappings CSV, canonical-fields.md, ADR-006 Kysely, openapi alertmanager)
- Tests placebo (`expect(true).toBe(true)`)
- Duplicación status enum UI vs core/DB (NORMALIZED missing)
- Dead code (`mipit-core/src/messaging/rabbitmq.ts`)
- 3-way inconsistencias en rail_ack.status
- Mock fidelity gaps NO en LIMITATIONS (OAuth ficcional SPEI, error codes inventados PIX/BREB)
- Deps huérfanas (radix-ui, ts-node, exporter-prometheus)
- ts-node declarado pero no usado en 5 repos
- OAuth secrets hardcoded en 6 archivos
- SPEI hours mock vs core vs docs (3-way divergencia)
- TTL 5min duplicado
