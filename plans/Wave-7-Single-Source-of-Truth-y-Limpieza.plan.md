# Wave 7 — Single Source of Truth + Limpieza

**Fecha planeada:** post-sustentación o cuando haya 1.5 días disponibles
**Branch sugerida:** `Auditoria-Claude` (directo, mismo patrón que W5/W6)
**Origen:** Bloque D del documento maestro [AUDITORIA-2-2026-05-17.md](../audits/AUDITORIA-2-2026-05-17.md) + remediación de hallazgos A5 (inconsistencias internas) y A3 (code quality quick wins)
**Estado:** ⏳ Planeada (no iniciada)
**Estimado:** ~1.5 días concentrados

---

## Objetivo

Eliminar la deuda de "fuentes de verdad múltiples" (mismo concepto modelado en N lugares que divergen silenciosamente) y la deuda visible de housekeeping (dead code, deps huérfanas, tests placebo, configs hardcoded). Ningún cambio funcional — sólo limpieza estructural que reduce el riesgo de regresión futura.

**No es pre-requisito de sustentación** — pero un panel que revisa el código apreciará explícitamente el orden.

## Tickets propuestos (16)

### Single Source of Truth (5)

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W7.1 SOT-001** | Crear paquete `@mipit/shared-types` (monorepo workspace o paquete npm interno) con `RAILS`, `PAYMENT_STATUS_ENUM`, `ALIAS_TYPE_ENUM`, `rail_ack.status` enum unificado. Importar en core + UI + 3 adapters. Resuelve los 3-way mismatches detectados (rail_ack.status: core 4 / UI 3 / OpenAPI 3 son distintos hoy). | core + ui + 3 adapters | A5-F1, B1/C8, F30 |
| **W7.2 SOT-002** | Helper `parseRailAlias(alias)` → `{rail, value}`. Refactor 8+ sites del core que hacen `.startsWith('PIX-')` / `.startsWith('SPEI-')` / `.startsWith('BREB-')` literal. Test único cubre todos los rieles. | core | A5-H1, C1 |
| **W7.3 SOT-003** | Borrar `mappings/canonical-fields.md` y los 4 CSVs ya borrados en Wave 6 W6.13. **Generar OpenAPI desde Zod** vía `zod-to-openapi` para que el contrato HTTP esté sincronizado byte-a-byte con el schema runtime. Reemplaza `openapi/openapi.yaml` manual con build step `npm run build:openapi`. | docs + core | A5-A1/A2/A3/A4/A7 |
| **W7.4 SOT-004** | OAuth secrets actualmente hardcoded en 6 archivos (`mipit-secret-{pix,spei,breb}-2024` en `client.ts` + `oauth-mock.ts` de cada adapter) → mover a env vars `{PIX,SPEI,BREB}_OAUTH_CLIENT_SECRET`. Validar con Zod `.min(16)`. Documentar en LIMITATIONS que en PoC vienen en `.env` plano. | 3 adapters | A5-F5, A5-H2 |
| **W7.5 SOT-005** | TTL 5min duplicado en `mapping-loader.ts:10` y `fx-service.ts:56` → extraer a `config/constants.ts:MAPPING_TTL_MS`. Idem otras constantes mágicas. | core | A5-H3 |

### Limpieza dead code y deuda (6)

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W7.6 CLEAN-001** | Borrar `mipit-core/src/messaging/rabbitmq.ts` (no importado en ningún sitio; conexión real vía `RabbitMQReconnector`). Borrar también `dlq-handler.ts:94-146` (`handleFailedMessage`, `shouldDeadLetter` — funciones huérfanas que confunden al lector). | core | A5-G1, F15 |
| **W7.7 CLEAN-002** | Borrar `mipit-observability/alerting/rules.yaml` legacy (P07 migró a `prometheus/rules/mipit-alerts.yaml`; el viejo nunca se borró). | observability | F16 |
| **W7.8 CLEAN-003** | `npm uninstall` deps huérfanas: en `mipit-ui` borrar `@radix-ui/react-{dialog,label,select,slot,toast}` + `class-variance-authority` (UI usa `sonner`, no toast de radix); en core borrar `@opentelemetry/exporter-prometheus` (no importado); `ts-node` en 5 repos que usan tsx (4 adapters + testkit + ui). | core + ui + 4 adapters + testkit | F13, A5-I3/I4 |
| **W7.9 CLEAN-004** | Agregar `@opentelemetry/api` a `package.json` de core (actualmente usado vía transitive abuse). | core | A5-I2 |
| **W7.10 CLEAN-005** | Borrar 2 reglas muertas en `seed_route_rules.sql` (`phone_co_to_breb` con `condition_field='alias.value_prefix'` que el matcher no entiende; `fallback_unavailable` con `'DOWN'` que el matcher no entiende). O implementar el matcher correspondiente. | infra | I3, I4 |
| **W7.11 CLEAN-006** | Borrar archivos `test_8.md`, `test_7.md` del root de `mipit-core/src/` (notas del developer, no código). | core | A5-G4 |

### Tests policy (3)

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W7.12 TEST-001** | Eliminar 5 tests con `expect(true).toBe(true)` + 4 archivos TODO-only de `mipit-testkit/tests/{integration,e2e}`: o borrar el archivo si nada vale, o convertir a `it.todo('...')` (Jest los reporta como `pending`, no inflados como `passed`). Reemplaza el "11/11 verde engañoso" por un conteo honesto. | testkit | A5-E1, F40 |
| **W7.13 TEST-002** | Lint rule `jest/no-truthy-only-assertions` en CI para detectar `expect(true).toBe(true)` automáticamente y bloquear nuevos placebos. | core + adapters + testkit + ui | (preventivo) |
| **W7.14 TEST-003** | Fix datasets PIX con `"currency": "USD"` → `"BRL"` (`pix-valid-01.json` + expected files). PIX trabaja BRL nativamente; USD es error de fixture. | testkit | A5-E3 |

### Bug menores heredados (2)

| ID | Cambio | Repos | Audit |
|---|---|---|---|
| **W7.15 BUG-001** | `consumer.ts:134`: `recordPayment(finalStatus, ack.source_rail, destRail ?? 'UNKNOWN')` etiqueta `origin_rail` con el rail del ACK (que es el destino del payment original). Fix: el consumer debe leer `payment.origin_rail` de DB y usar ese para el counter, manteniendo destination_rail del ACK. | core | (heredado Wave 5) |
| **W7.16 BUG-002** | Update `architecture-overview.md:43`: "reglas en Postgres vía RuleLoader" (no YAML). Update `translation-layer.md:65,79`: agregar `LLAVE_BREB` al `alias.type` enum, corregir `institutionCode max(8)` (era 3 dígitos). Update `local-demo.md` con credenciales Grafana correctas (`admin/mipit2026`) y queue name (`payments.route.pix` no `q.adapter.pix`). | docs | A5-D9, A5-A5, A5-A6, I10, B10 |

## Criterios de éxito

- ✅ `npm ls` en UI sin warnings de orfan deps
- ✅ `grep -rn "expect(true)" mipit-testkit/tests` = 0
- ✅ Imports de `RAILS` / `STATUS` / `ALIAS_TYPE` apuntan a `@mipit/shared-types`
- ✅ OpenAPI generado desde Zod en build step (no manual)
- ✅ Tests count total baja pero todos los que quedan son reales (sin placebos)
- ✅ OAuth secrets no aparecen en `git grep "mipit-secret"` (sólo en `.env.example`)

## Dependencias

- **No depende de Wave 8**: puede correrse antes
- **Recomendado antes** de cualquier nuevo desarrollo de feature para no propagar la deuda

## Riesgos

| Riesgo | Mitigación |
|---|---|
| **`@mipit/shared-types` rompe builds** durante el refactor | Hacer el cambio en una sesión single, con CI verde en cada commit |
| **Borrar dead code** que en realidad se usaba via `require()` dinámico | Grep agresivo (rg / ripgrep) antes de borrar; correr full test suite |
| **Lint rule** rechaza tests legítimos con assertion única | Configurar regla con allowlist por filename o usar `// eslint-disable-next-line` justificada |

## Estimación detallada

| Bloque | Días | Comentario |
|---|---|---|
| SoT (W7.1–7.5) | 0.5 día | El paquete shared-types es el más grande; resto son moves |
| Cleanup (W7.6–7.11) | 0.3 día | Mecánico: `git rm` + `npm uninstall` + tests |
| Tests policy (W7.12–7.14) | 0.3 día | Borrar placebos + lint rule + fixture currency |
| Bugs heredados (W7.15–7.16) | 0.4 día | El bug del consumer requiere lookup DB extra |
| **Total** | **~1.5 días** | |

## Cuando NO hacer Wave 7

- Si la sustentación está en menos de 1 semana y no hay tiempo dedicado: **saltar** y agendar post-defensa
- Si el equipo decide pasar directo a Wave 8 (arquitectura productiva): Wave 7 puede absorberse parcialmente dentro de Wave 8 R1 (shared types parte de `@mipit/contracts`) y R7 (DI container resuelve mucho del cleanup de singletons)
