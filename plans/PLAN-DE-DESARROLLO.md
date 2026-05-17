# Plan de Desarrollo - MiPIT PoC

## Información General

| Campo | Valor |
|---|---|
| **Proyecto** | MiPIT - Middleware de Integración de Pagos Internacionales en Tiempo Real |
| **Tipo** | Proof of Concept (PoC) para Tesis |
| **Desarrolladores** | Carlos, Nicolas |
| **Duración total** | 17 semanas |
| **Semanas 1-4** | Planeación, investigación y diseño (ya realizadas) |
| **Semanas 5-6** | Completadas ✓ (infra, persistencia, traducción, normalización, routing, 57 unit tests) |
| **Fase 1 (Desarrollo)** | Semanas 5-10 |
| **Fase 2 (Testing)** | Semanas 11 en adelante |
| **Fase 3 (Deploy / Polish)** | Semanas 13-17 |

---

## Notas de implementación

### Naming: `/payments` vs `/transactions`
El documento de diseño (Diseno_MIPIT.pdf) usa `POST /transactions` y `GET /transactions/{id}`. La implementación usa `POST /payments` y `GET /payments/:paymentId` para mayor claridad semántica (el recurso es un pago, no una transacción genérica). Ambos son equivalentes; la documentación final debe reflejar los endpoints reales implementados.

### Inferencia de `destinationRail`
El diseño original contempla `destinationRail` como campo del request. La implementación es más sofisticada: el `RouteEngine` infiere automáticamente el rail destino analizando el alias del creditor, país y reglas en DB. Esto elimina la necesidad de que el cliente conozca los rieles disponibles y permite routing dinámico sin cambios en la API.

### Sandboxes PIX y SPEI
Los sandboxes oficiales del BCB (PIX) y Banxico (SPEI) requieren certificación como institución financiera, lo cual está fuera del alcance de un PoC académico. La implementación usa mock servers propios que replican la estructura y comportamiento documentado de cada riel (validación de CLABE 18 dígitos para SPEI, tipos de chave para PIX, tasas de error simuladas). Esto es coherente con las secciones 4.6.1 y 4.6.2 del diseño, que contemplan explícitamente "simulación o endpoints mock".

---

## Convenciones de Trabajo

### Branching
- Branch principal: `main`
- Branches de desarrollo: `Carlos_XX` y `Nicolas_XX` donde `XX` es el número de semana (ej: `Carlos_05`, `Nicolas_05`)
- Al finalizar cada semana, ambas branches se mergean a `main` via Pull Request
- La semana siguiente se crea branch nueva desde `main` actualizado

### Workflow Semanal
1. Lunes: ambos crean su branch desde `main` (`git checkout -b Carlos_XX main`)
2. Durante la semana: cada uno trabaja en sus tickets asignados
3. Viernes/Sábado: PR de cada branch a `main`, code review cruzado
4. Domingo: merge a `main`, verificación de que el build pasa

### Prioridades
- **P0 - Crítica**: Bloquea todo el flujo. Debe completarse sí o sí en la semana asignada.
- **P1 - Alta**: Desbloquea tickets de la siguiente semana. Prioritaria.
- **P2 - Media**: Importante pero no bloqueante para la semana siguiente.
- **P3 - Baja**: Nice-to-have, puede posponerse si hay deuda técnica.

---

## Semanas 1-4 — Planeación e investigación (realizadas)

Durante las primeras cuatro semanas se realizó la planeación del proyecto, investigación de dominio, diseño de arquitectura, definición de requisitos (SRS), plan de gestión (SPMP), diseño de la base de datos, contratos de mensajería y scaffolding de los 8 repositorios. No hay tickets de desarrollo asociados a este periodo.

---

## FASE 1: Desarrollo (Semanas 5-10)

---

### Semana 5 — Infraestructura + Capa de Persistencia ✅ COMPLETADA

> **Objetivo**: Levantar el stack Docker, verificar datos seed, e implementar fundamentos del core (config, logging, telemetría, DB) y todos los repositorios (payments, audit, idempotency, route rules, mappings).
>
> **Estado**: Completada. 13 tickets implementados y mergeados a `master`. Unit tests pasando.

#### Branch `Carlos_05`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| INFRA-001 | Verificar Docker Compose stack completo | P0 | Ejecutar `scripts/up.sh`, verificar que los 12 servicios levanten correctamente (postgres, rabbitmq, core placeholder, adapters placeholder, nginx, prometheus, grafana, jaeger). Documentar puertos y health checks. | Confirmar que la infraestructura base funciona antes de escribir código. | Afecta TODO el flujo — sin infra no hay desarrollo posible. | INFRA-002, CORE-004 |
| INFRA-002 | Ejecutar seeds SQL y verificar tablas | P0 | Conectarse a PostgreSQL, verificar que las 5 tablas existen (`payments`, `audit_events`, `route_rules`, `mapping_table`, `idempotency_keys`), que los seeds de `route_rules` (5 reglas) y `mapping_table` (44 mappings) se cargaron. | Garantizar que la capa de datos está lista. | Persistencia — base de todo el procesamiento. | CORE-006, CORE-009 |
| CORE-001 | Implementar `src/config/env.ts` con validación real | P1 | Completar la validación Zod de las 8 variables de entorno (NODE_ENV, PORT, DATABASE_URL, RABBITMQ_URL, JWT_SECRET, OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME, LOG_LEVEL). Lanzar error descriptivo si falta alguna. | Fail-fast al arrancar si la configuración es inválida. | Bootstrap del servicio — primer paso de `index.ts`. | CORE-002, CORE-003, CORE-004 |
| CORE-006 | Implementar `payment.repository.ts` | P0 | Implementar métodos: `create(payment)` → INSERT con ULID, `findById(id)` → SELECT, `updateStatus(id, status)` → UPDATE + timestamp, `updateRailAck(id, railAck)` → UPDATE con JSON rail_ack. Usar pool.query con parámetros $1, $2. | CRUD completo de pagos en PostgreSQL. | Centro del flujo — cada pago pasa por create → updateStatus (varias veces) → updateRailAck. | CORE-028 (pipeline) |
| CORE-007 | Implementar `audit.repository.ts` | P0 | Implementar `insert(event)` → INSERT con ULID, campos: payment_id, event_type, actor, detail (JSONB), trace_id, created_at. Implementar `findByPaymentId(paymentId)` → SELECT ORDER BY created_at. | Registro inmutable de cada cambio de estado para auditoría y debugging. | Auditoría — se inserta en cada paso del pipeline (RECEIVED, VALIDATED, ROUTED, etc). | CORE-027 (audit service) |
| CORE-008 | Implementar `persistence/queries/index.ts` | P1 | Definir todas las queries SQL como constantes con nombre descriptivo: INSERT_PAYMENT, FIND_PAYMENT_BY_ID, UPDATE_PAYMENT_STATUS, UPDATE_RAIL_ACK, INSERT_AUDIT, FIND_AUDITS_BY_PAYMENT, FIND_IDEMPOTENCY_KEY, INSERT_IDEMPOTENCY, UPDATE_IDEMPOTENCY_RESPONSE, FIND_ACTIVE_RULES, FIND_MAPPINGS_BY_RAIL. | Centralizar SQL en un solo archivo, evitar SQL inline en repositorios. | Transversal — usado por todos los repositorios. | Todos los repos |

#### Branch `Nicolas_05`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-002 | Implementar `src/observability/otel.ts` | P1 | Configurar NodeSDK con Resource, OTLPTraceExporter apuntando a Jaeger (env.OTEL_EXPORTER_OTLP_ENDPOINT), y auto-instrumentations para http, fastify, pg, amqplib. Exportar `initTelemetry()` y `sdk` para shutdown. | Tener trazabilidad distribuida desde el día 1. | Observabilidad — genera `trace_id` para cada request, propagado a adapters via RabbitMQ headers. | CORE-036 |
| CORE-003 | Implementar `src/observability/logger.ts` | P1 | Configurar Pino con nivel desde `env.LOG_LEVEL`, timestamp ISO, campo base `service: env.OTEL_SERVICE_NAME`. Exportar instancia `logger`. | Logging estructurado JSON para debugging y auditoría. | Transversal — usado por todos los módulos del core. | Todos los módulos |
| CORE-004 | Implementar `src/persistence/db.ts` | P0 | Crear PG Pool con `env.DATABASE_URL`, configurar `max: 20`, `idleTimeoutMillis: 30000`, `connectionTimeoutMillis: 5000`. Exportar `connectDb()` que verifica conexión con `SELECT 1`, y `pool` para queries. | Conexión a PostgreSQL funcional. | Persistencia — sin DB no hay pagos, auditoría, ni idempotencia. | CORE-006 a CORE-011 |
| CORE-005 | Implementar `src/observability/metrics.ts` | P2 | Crear las 5 métricas Prometheus: `mipit_payments_total` (Counter), `mipit_payment_latency_ms` (Histogram con 9 buckets), `mipit_translation_errors_total` (Counter), `mipit_routing_decisions_total` (Counter), `mipit_idempotency_hits_total` (Counter). | Métricas listas para instrumentar el pipeline. | Observabilidad — alimenta dashboards de Grafana. | CORE-025, CORE-028 |
| CORE-009 | Implementar `idempotency.repository.ts` | P0 | Implementar `findByKey(hashedKey)` → SELECT, `insert(key, method, path)` → INSERT, `updateResponse(hashedKey, statusCode, responseBody)` → UPDATE. Hash SHA-256 del Idempotency-Key header. | Prevenir pagos duplicados — requerimiento crítico del SRS. | Middleware de idempotencia — ejecuta ANTES del pipeline en cada POST /payments. | CORE-033 (idempotency middleware) |
| CORE-010 | Implementar `route-rule.repository.ts` | P1 | Implementar `findActive()` → SELECT WHERE is_active = true ORDER BY priority ASC, `findById(id)` → SELECT. Retornar tipado como `RouteRule[]`. | Cargar reglas de ruteo desde DB en vez de hardcodear. | Routing — paso 5 del pipeline, decide si va a PIX o SPEI. | CORE-022 (rule loader) |
| CORE-011 | Implementar `mapping.repository.ts` | P1 | Implementar `findByRail(rail, direction)` → SELECT WHERE rail=$1 AND direction=$2, `findAll()` → SELECT. Retornar tipado como `MappingEntry[]`. | Cargar tabla de mapeo de campos para traducción bidireccional. | Traducción — pasos 3 y 6 del pipeline (canonicalizar y traducir a destino). | CORE-012 (mapping loader) |

#### Criterio de merge Semana 5 ✅
- [x] `docker compose up` levanta los 12 servicios sin errores
- [x] Las 5 tablas SQL existen con datos seed
- [x] `env.ts` lanza error si falta `DATABASE_URL`
- [x] `db.ts` conecta exitosamente a PostgreSQL
- [x] `otel.ts` envía al menos un span a Jaeger
- [x] `logger.ts` produce JSON estructurado
- [x] Las 5 métricas Prometheus se registran sin error
- [x] `paymentRepo.create()` inserta un pago y `findById()` lo recupera
- [x] `auditRepo.insert()` registra un evento y `findByPaymentId()` lo lista
- [x] `idempotencyRepo.insert()` + `findByKey()` detecta duplicado correctamente
- [x] `routeRuleRepo.findActive()` retorna las 5 reglas seed ordenadas por prioridad
- [x] `mappingRepo.findByRail('PIX', 'TO_CANONICAL')` retorna 13 mappings

---

### Semana 6 — Traducción + Normalización y Routing ✅ COMPLETADA

> **Objetivo**: Implementar las 4 funciones de traducción bidireccional (PIX ↔ Canonical, SPEI ↔ Canonical), el orquestador Translator, las reglas de normalización, el rule loader y el motor de enrutamiento. Al finalizar, un payload se puede canonicalizar, normalizar y rutear a PIX o SPEI.
>
> **Estado**: Completada. 13 tickets implementados (Nicolas cubrió los de Carlos). 57 unit tests pasando. Cache TTL 5min en MappingLoader y RuleLoader. Logging y métricas en Translator, Normalizer y RouteEngine. FX cross-currency detection implementada.

#### Branch `Carlos_06`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-012 | Implementar `translation/mapping-loader.ts` | P0 | Cargar mappings desde DB via `mappingRepo.findByRail()`. Cachear en memoria con TTL de 5 min. Exportar `loadMappings(rail, direction)` que retorna `Map<sourceField, {targetField, transformation, validation}>`. | Cache de mappings para no consultar DB en cada traducción. | Traducción — prerequisito de los 4 mappers. | CORE-013 a CORE-016 |
| CORE-013 | Implementar `translation/pix-to-canonical.ts` | P0 | Recibir payload PIX (chave, valor, tipo_chave, etc), aplicar mappings TO_CANONICAL, generar objeto `CanonicalPacs008` con campos correctos: alias → `debtor.alias` con prefijo `PIX-`, valor → `amount.value`, etc. Validar resultado con Zod schema. | Traducir entrada PIX al modelo canónico pacs.008. | Paso 3 del pipeline (canonicalización) cuando el origen es PIX. | CORE-028 (pipeline) |
| CORE-014 | Implementar `translation/canonical-to-pix.ts` | P1 | Recibir `CanonicalPacs008`, aplicar mappings FROM_CANONICAL para PIX, generar payload PIX nativo: `amount.value` → `valor`, `debtor.alias` → strip `PIX-` prefix → `chave`, `currency` → ignorar (PIX siempre BRL). | Traducir canónico a formato PIX para enviar al adaptador. | Paso 6 del pipeline (traducción a destino) cuando destino es PIX. | PIX-002 (adapter mapper) |
| CORE-019 | Implementar reglas de normalización | P1 | Implementar los 4 archivos de reglas: `date-rules.ts` (convertir fechas a UTC ISO-8601), `currency-rules.ts` (uppercase currency code), `id-rules.ts` (generar msgId y endToEndId si faltan, usando ULID), `fallback-rules.ts` (purpose default 'P2P', reference default 'MIPIT-POC'). | Garantizar consistencia de datos canónicos independiente del formato de origen. | Paso 4 del pipeline (normalización) — se ejecuta después de canonicalización. | CORE-020 |
| CORE-020 | Implementar `normalization/normalizer.ts` | P0 | Clase `Normalizer` con método `normalize(canonical: CanonicalPacs008)` que aplica las 4 reglas en orden: dates → currency → ids → fallbacks. Retorna canonical modificado. Loggea cada normalización aplicada. | Pipeline de normalización encadenado. | Paso 4 del pipeline — transforma el canónico antes de rutear. | CORE-028 (pipeline) |
| CORE-021 | Unit tests de normalización | P2 | Tests: fecha no-UTC se convierte a UTC, currency 'usd' → 'USD', msgId vacío se genera con ULID, purpose vacío → 'P2P'. Mínimo 8 tests cubriendo edge cases. | Confianza en la normalización. | Testing. | — |

#### Branch `Nicolas_06`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-015 | Implementar `translation/spei-to-canonical.ts` | P0 | Recibir payload SPEI (clabe_origen, clabe_destino, monto, moneda, etc), aplicar mappings, generar `CanonicalPacs008`. Mapear: clabe_origen → `debtor.alias` con prefijo `SPEI-`, monto → `amount.value`, moneda → `amount.currency`. | Traducir entrada SPEI al modelo canónico pacs.008. | Paso 3 del pipeline cuando origen es SPEI. | CORE-028 (pipeline) |
| CORE-016 | Implementar `translation/canonical-to-spei.ts` | P1 | Recibir `CanonicalPacs008`, generar payload SPEI: `amount.value` → `monto`, `creditor.alias` → strip `SPEI-` → `clabe_destino`, tipo_cuenta='CLABE', moneda='MXN'. | Traducir canónico a formato SPEI. | Paso 6 del pipeline cuando destino es SPEI. | SPEI-002 (adapter mapper) |
| CORE-017 | Implementar `translation/translator.ts` (orquestador) | P0 | Clase `Translator` con métodos `toCanonical(rail, payload)` y `fromCanonical(rail, canonical)`. Usa mapping-loader + el mapper correcto según rail. Maneja errores con `TranslationError`. | Punto de entrada único para toda traducción — el pipeline solo llama al Translator. | Pasos 3 y 6 del pipeline — orquesta qué mapper usar. | CORE-028 (pipeline) |
| CORE-018 | Unit tests de traducción | P2 | Escribir tests para las 4 funciones: PIX→Canonical (verifica campos, prefijo PIX-, Zod validation), Canonical→PIX (strip prefix, BRL default), SPEI→Canonical, Canonical→SPEI. Mínimo 3 tests por función. | Confianza en la correctitud de las traducciones. | Testing — valida que el corazón del middleware funciona. | — |
| CORE-022 | Implementar `routing/rule-loader.ts` | P1 | Cargar reglas activas desde DB via `routeRuleRepo.findActive()`. Cachear con TTL 5 min. Exportar `loadRules()` → `RouteRule[]` ordenadas por prioridad (menor número = mayor prioridad). | Reglas de ruteo dinámicas cargadas desde DB. | Routing — alimenta al route engine. | CORE-023 |
| CORE-023 | Implementar `routing/route-engine.ts` | P0 | Clase `RouteEngine` con método `route(canonical: CanonicalPacs008)` → `{rail: 'PIX'|'SPEI', rule: RouteRule}`. Evalúa reglas en orden de prioridad: match por alias pattern (regex), match por country code, match por credential type. Primera regla que matchea gana. Si ninguna matchea → throw `RoutingError('NO_ROUTE_FOUND')`. | Decidir automáticamente el rail destino basado en datos del pago. | Paso 5 del pipeline — después de normalizar, antes de traducir a destino. | CORE-028 (pipeline) |
| CORE-024 | Unit tests de routing | P2 | Tests: alias CLABE 18 dígitos → SPEI, alias PIX key → PIX, country BR → PIX, country MX → SPEI, alias desconocido → error NO_ROUTE_FOUND. Mínimo 6 tests. | Confianza en decisiones de ruteo. | Testing. | — |

#### Criterio de merge Semana 6 ✅
- [x] `translator.toCanonical('PIX', pixPayload)` retorna CanonicalPacs008 válido
- [x] `translator.toCanonical('SPEI', speiPayload)` retorna CanonicalPacs008 válido
- [x] `translator.fromCanonical('PIX', canonical)` retorna payload PIX nativo
- [x] `translator.fromCanonical('SPEI', canonical)` retorna payload SPEI nativo
- [x] `normalizer.normalize()` convierte fechas a UTC, uppercase currency, genera IDs faltantes
- [x] `routeEngine.route()` retorna PIX para alias con formato de chave PIX
- [x] `routeEngine.route()` retorna SPEI para CLABE de 18 dígitos
- [x] `routeEngine.route()` lanza error para alias sin regla matching
- [x] 57 unit tests pasan (traducción + normalización + routing) — supera los 14 mínimos

---

### Semana 7 — Mensajería RabbitMQ y Pipeline ✅ COMPLETADA

> **Objetivo**: Conectar a RabbitMQ, implementar publisher/consumer, y orquestar el pipeline completo de 7 pasos. Al finalizar, un pago puede fluir desde la recepción hasta la publicación en la cola del adaptador correcto.
>
> **Estado**: Completada. Nicolas implementó CORE-028 (pipeline), CORE-029 (consumer), CORE-030 (integration tests). Carlos implementó carga dinámica de mappings en traducciones (S6 tardío). 40 nuevos tests (11 unit pipeline + 11 unit consumer + 9 integration pipeline + 9 integration messaging). Corrección de esquema SQL (audit_events, payments.failed_at). Todas las branches mergeadas y eliminadas.
>
> **Depende de**: Semana 6 (translator, normalizer, route engine)

#### Branch `Carlos_09`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-025 | Implementar `messaging/rabbitmq.ts` | P0 | Conectar a RabbitMQ usando `env.RABBITMQ_URL`. Crear channel, assert exchange `mipit.payments` (topic), assert queues (`payments.route.pix`, `payments.route.spei`, `payments.ack`), crear bindings con routing keys (`route.pix`, `route.spei`, `ack.pix`, `ack.spei`). Exportar `connectRabbitMQ()` → `{connection, channel}`. | Conexión y topología RabbitMQ lista para publish/consume. | Mensajería — conecta core con adaptadores de forma asíncrona. | CORE-026, CORE-029 |
| CORE-026 | Implementar `messaging/publisher.ts` | P0 | Clase `Publisher` con método `publish(rail: string, canonical: CanonicalPacs008)`. Determinar routing key (`route.pix` o `route.spei`). Publicar en exchange `mipit.payments` con `persistent: true`, headers con `trace_id` y `payment_id`. JSON.stringify del canonical como buffer. | Enviar mensajes canónicos al adaptador correcto via RabbitMQ. | Paso 7 del pipeline — último paso antes de que el adaptador tome control. | CORE-028 (pipeline), PIX-001, SPEI-001 |
| CORE-027 | Implementar `audit/audit-service.ts` | P1 | Clase `AuditService` con método `log(paymentId, eventType, actor, detail, traceId)`. Genera ULID para audit_event_id, inserta via auditRepo. Event types: RECEIVED, VALIDATED, CANONICALIZED, NORMALIZED, ROUTED, TRANSLATED, QUEUED, SENT, ACKED, COMPLETED, FAILED. | Registro de auditoría en cada cambio de estado. | Auditoría — se llama en cada paso del pipeline para traza completa. | CORE-028 |

#### Branch `Nicolas_07`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-028 | Implementar `pipeline/payment-pipeline.ts` | P0 | Clase `PaymentPipeline` con método `process(request: CreatePaymentRequest)` que ejecuta 7 pasos: (1) Inferir rail origen del alias, (2) Persistir pago con status RECEIVED, (3) Traducir a canónico via Translator, (4) Normalizar via Normalizer, (5) Rutear via RouteEngine → determinar rail destino, (6) Traducir a formato destino via Translator, (7) Publicar a RabbitMQ via Publisher. En cada paso: actualizar status en DB + log audit event. Si error en cualquier paso: catch, status FAILED, audit log, re-throw. Instrumentar con `mipit_payment_latency_ms` histogram por stage. | Orquestación completa del flujo de pago — el corazón del middleware. | ES el flujo completo del core — desde la recepción del request HTTP hasta la entrega al adaptador. | CORE-031 (POST route) |
| CORE-029 | Implementar `messaging/consumer.ts` (ACK) | P0 | Clase `AckConsumer` con `start()`. Consume de queue `payments.ack`. Parsear mensaje como `PaymentAckMessage` (payment_id, trace_id, source_rail, adapter_id, status, rail_ack, latency_ms). Mapear status: ACCEPTED→COMPLETED, REJECTED→REJECTED, otro→FAILED. Actualizar pago en DB: `updateStatus()` + `updateRailAck()`. Log audit event. channel.ack(msg). | Cerrar el ciclo: recibir confirmación del adaptador y actualizar estado final del pago. | Paso final del flujo — el pago cambia de QUEUED/SENT a COMPLETED/REJECTED/FAILED. | TEST-004 (E2E) |
| CORE-030 | Integration test: pipeline → DB | P2 | Test que crea un `PaymentPipeline` con mocks de RabbitMQ, ejecuta `process()` con un payload PIX válido, verifica: pago existe en DB con status QUEUED, audit events registrados (RECEIVED, VALIDATED, CANONICALIZED, NORMALIZED, ROUTED, TRANSLATED, QUEUED). | Verificar que el pipeline completo funciona end-to-end dentro del core (sin adaptadores). | Testing — primer test de integración real. | — |

#### Criterio de merge Semana 7 ✅
- [x] `connectRabbitMQ()` establece conexión y crea topología
- [x] `publisher.publish('PIX', canonical)` publica mensaje en `payments.route.pix`
- [x] `pipeline.process(pixRequest)` ejecuta 7 pasos y el pago queda en status QUEUED
- [x] ACK consumer procesa mensaje y actualiza pago a COMPLETED
- [x] Audit events registrados para cada paso del pipeline
- [x] Integration test pasa (9 pipeline + 9 messaging)

---

### Semana 8 — API HTTP y Middleware del Core

> **Objetivo**: Implementar los endpoints REST, middlewares de seguridad/idempotencia/tracing, y el bootstrap completo de `index.ts`. Al finalizar, el core es un servicio HTTP funcional que recibe pagos y responde.
>
> **Depende de**: Semana 7 (CORE-028 pipeline, CORE-029 consumer)

#### Branch `Carlos_08`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-031 | Implementar `POST /payments` completo | P0 | En `api/routes/payments.ts`: recibir body, validar con `createPaymentSchema` (Zod), extraer `Idempotency-Key` header (requerido), llamar `pipeline.process(request)`, retornar 201 con `{payment_id, status, created_at, destination_rail}`. Manejar errores: 400 (validation), 409 (duplicate), 422 (routing error), 500. | Endpoint principal del middleware — punto de entrada de todo pago. | ENTRADA del flujo — es donde todo comienza. Sin este endpoint no hay pagos. | UI-005, TEST-001 |
| CORE-032 | Implementar `GET /payments/:paymentId` completo | P1 | En `api/routes/payments.ts`: buscar pago por ID via `paymentRepo.findById()`, si no existe → 404, si existe → retornar `PaymentDetail` con: datos del pago, status actual, timestamps (received_at, completed_at), audit trail via `auditRepo.findByPaymentId()`, original/canonical/translated payloads, rail_ack. | Consultar estado y detalle completo de un pago — usado por UI y testing. | CONSULTA del flujo — permite ver el estado y la traza completa. | UI-006, TEST-004 |
| CORE-033 | Implementar middleware de idempotencia | P0 | En `api/middleware/idempotency.ts`: extraer `Idempotency-Key` header, hashear SHA-256, buscar en `idempotencyRepo`. Si existe y tiene response → retornar response cacheada (incrementar `mipit_idempotency_hits_total`). Si existe sin response → 409 Conflict (request in progress). Si no existe → insertar key, continuar al handler, al terminar guardar response via `updateResponse()`. | Prevenir procesamiento duplicado de pagos — requerimiento crítico ISO 20022. | PRE-PIPELINE — se ejecuta antes del pipeline en cada POST. Bloquea duplicados. | TEST-008 (E2E idempotency) |

#### Branch `Nicolas_08`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| CORE-034 | Implementar middleware JWT auth | P1 | En `api/middleware/auth.ts`: extraer `Authorization: Bearer <token>` header, verificar JWT con `env.JWT_SECRET` usando `@fastify/jwt`. Si inválido → 401. Decorar request con payload decodificado. Para PoC: generar token de prueba en seed o script. | Seguridad básica del API — requerimiento del SRS. | PRE-PIPELINE — antes de idempotencia. Sin token válido, request rechazado. | — |
| CORE-035 | Implementar middleware de tracing | P1 | En `api/middleware/tracing.ts`: extraer `X-Trace-ID` header o generar ULID nuevo. Inyectar en request context. Agregar como response header `X-Trace-ID`. Propagar a OpenTelemetry span. | Correlacionar requests a través de todo el sistema (core → adapter → response). | TRANSVERSAL — el trace_id viaja por todo el flujo hasta el adapter y vuelta. | — |
| CORE-036 | Implementar `api/server.ts` + `index.ts` bootstrap | P0 | `server.ts`: crear Fastify app, registrar cors, helmet, JWT plugin, error handler. Registrar rutas: `/health`, `/metrics`, `/payments`. Aplicar middleware hooks (tracing → auth → idempotency). `index.ts`: bootstrap en orden: (1) initTelemetry, (2) connectDb, (3) connectRabbitMQ, (4) buildServer, (5) start AckConsumer, (6) listen en PORT. Graceful shutdown (SIGTERM/SIGINT): close app, channel, pool, sdk. | Servicio core completamente funcional y desplegable. | ES el servicio — sin bootstrap no hay nada. | PIX-001, SPEI-001, UI-001 |
| CORE-037 | Integration test: HTTP → pipeline → DB | P2 | Test con Fastify inject: POST /payments con payload PIX válido + Idempotency-Key + JWT, verificar 201, verificar pago en DB, verificar audit events. Segundo POST con misma key → verificar response cacheada. | Validar el flujo completo del core como servicio HTTP. | Testing — primer test que prueba el core como servicio. | — |

#### Criterio de merge Semana 8
- [ ] `POST /payments` con payload válido retorna 201 con payment_id
- [ ] `GET /payments/:id` retorna detalle completo con audit trail
- [ ] Segundo POST con mismo Idempotency-Key retorna response cacheada (no procesa de nuevo)
- [ ] Request sin JWT → 401
- [ ] Response incluye header `X-Trace-ID`
- [ ] `node dist/index.js` arranca el servicio completo sin errores
- [ ] Graceful shutdown funciona (SIGTERM cierra DB + RabbitMQ + OTel)

---

### Semana 9 — Adaptadores PIX y SPEI

> **Objetivo**: Implementar ambos adaptadores como workers RabbitMQ independientes. Cada uno consume de su cola, traduce a formato nativo, llama al mock sandbox, y publica ACK de vuelta al core.
>
> **Depende de**: Semana 6 (CORE-036 core funcional, CORE-026 publisher)

#### Branch `Carlos_09`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| PIX-001 | Implementar `adapter-pix/src/worker.ts` | P0 | Consume de `payments.route.pix` via channel.consume(). Parsear mensaje JSON como `CanonicalPacs008`. Llamar `canonicalToPixPayload()` → payload PIX. Llamar `sendPixPayment()` → response. Llamar `pixResponseToAck()` → ACK message. Publicar ACK a exchange `mipit.payments` con routing key `ack.pix`. Channel.ack(msg). Si error → channel.nack(msg, false, false) para enviar a DLQ. | Worker completo que procesa pagos PIX de forma autónoma. | ADAPTADOR PIX — recibe canonical del core, llama al sandbox, devuelve ACK. Es la mitad del flujo E2E. | TEST-004 |
| PIX-002 | Implementar `mapper.ts` + `response-mapper.ts` con lógica real | P0 | `mapper.ts`: `canonicalToPixPayload(canonical)` → `PixPaymentRequest` con campos: valor (amount con FX si aplica), chave (strip PIX- prefix del alias), tipo_chave, pagador (debtor.name), cpf_pagador. `response-mapper.ts`: `pixResponseToAck(response, canonical)` → `PaymentAckMessage` mapeando e2e_id→ACCEPTED, error→REJECTED, con latency_ms. | Traducción correcta entre canónico y formato PIX nativo. | Traducción en el adaptador — complementa la traducción del core. | PIX-001 |
| PIX-003 | Implementar `client.ts` con retry real | P1 | `sendPixPayment(payload)`: HTTP POST a `env.PIX_SANDBOX_URL/pix/payments`, timeout via AbortController (`env.PIX_TIMEOUT_MS`), wrapped en `withRetry(fn, {maxRetries: 3, baseDelay: 1000})`. Loggear intentos y resultados. | Comunicación resiliente con el sandbox PIX. | Llamada al rail — si falla, el pago queda en FAILED. Retry protege contra errores transitorios. | PIX-001 |
| PIX-004 | Verificar mock server + bootstrap completo | P1 | Verificar que `mock-server.ts` responde en puerto 9001: POST /pix/payments (10% random fail, latencia 100-500ms), GET /health. Verificar `index.ts`: bootstrap OTel → mock (si PIX_MODE=mock) → RabbitMQ → worker. Test manual: publicar mensaje en cola, verificar que el worker lo procesa. | Adaptador PIX completamente funcional y autónomo. | VERIFICACIÓN — confirma que el adaptador funciona de punta a punta. | TEST-004 (E2E) |

#### Branch `Nicolas_09`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| SPEI-001 | Implementar `adapter-spei/src/worker.ts` | P0 | Igual estructura que PIX: consume `payments.route.spei`, parsea canonical, llama `canonicalToSpeiPayload()`, llama `sendSpeiPayment()`, genera ACK con `speiResponseToAck()`, publica con routing key `ack.spei`. Nack a DLQ en caso de error. | Worker completo para pagos SPEI. | ADAPTADOR SPEI — espejo de PIX pero para rail mexicano. | TEST-005 |
| SPEI-002 | Implementar `mapper.ts` + `response-mapper.ts` SPEI | P0 | `mapper.ts`: `canonicalToSpeiPayload(canonical)` → `SpeiPaymentRequest` con: clabe_destino (strip SPEI- prefix, 18 dígitos), clabe_origen, monto, moneda='MXN', tipo_cuenta='CLABE', concepto. `response-mapper.ts`: `speiResponseToAck()` → mapea estatus ACEPTADO→ACCEPTED, RECHAZADO→REJECTED. | Traducción canónico → SPEI con validación de CLABE. | Traducción SPEI — campos específicos del sistema SPEI mexicano. | SPEI-001 |
| SPEI-003 | Implementar `client.ts` con retry real | P1 | `sendSpeiPayment(payload)`: POST a `env.SPEI_SANDBOX_URL/spei/payments`, timeout, retry con backoff. Misma estructura que PIX client pero apuntando a SPEI sandbox. | Comunicación resiliente con sandbox SPEI. | Llamada al rail SPEI. | SPEI-001 |
| SPEI-004 | Verificar mock server SPEI + bootstrap | P1 | Mock en puerto 9002: POST /spei/payments con validación CLABE (18 dígitos), 10% random fail. Bootstrap: OTel → mock → RabbitMQ → worker. Test manual igual que PIX. | Adaptador SPEI completamente funcional. | VERIFICACIÓN del adaptador SPEI. | TEST-005 |

#### Criterio de merge Semana 9
- [ ] Adapter PIX consume mensaje de cola, llama mock, publica ACK
- [ ] Adapter SPEI consume mensaje de cola, llama mock, publica ACK
- [ ] Core recibe ACK y actualiza pago a COMPLETED
- [ ] Flujo E2E manual: POST /payments → core → RabbitMQ → adapter → mock → ACK → core → COMPLETED
- [ ] DLQ recibe mensajes cuando el mock falla y se agotan retries
- [ ] Ambos mock servers responden en health check

---

### Semana 10 — Interfaz de Usuario

> **Objetivo**: Implementar la UI completa en Next.js con shadcn/ui. Al finalizar, un usuario puede simular pagos, ver el detalle con timeline y message inspector, y consultar historial.
>
> **Depende de**: Semana 8 (CORE-031, CORE-032 — API endpoints del core)

#### Branch `Carlos_10`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| UI-001 | Instalar shadcn components y configurar layout | P0 | Ejecutar `npx shadcn@latest add button card input badge select table tabs toast`. Implementar `layout.tsx` (root con providers), `navbar.tsx` (logo MiPIT, links: Dashboard, Simular, Historial), `footer.tsx` (versión PoC + link GitHub). Verificar que Tailwind 4 compila correctamente. | Base visual del frontend — todos los componentes UI dependen de esto. | UI — no afecta el flujo de pagos, es la capa de presentación. | UI-002 a UI-008 |
| UI-002 | Implementar Dashboard page | P1 | `app/page.tsx`: 3 componentes — `stats-cards.tsx` (total pagos, tasa éxito, latencia p95), `recent-payments.tsx` (últimos 5 pagos con status badge), `service-health.tsx` (status de core, adapters, RabbitMQ). Datos via API polling cada 10s. | Vista general del estado del sistema para el demo. | Dashboard — lectura, no modifica el flujo. | — |
| UI-003 | Implementar hooks reutilizables | P1 | `use-payment.ts` (fetch single payment con polling para status updates), `use-payments.ts` (fetch lista con filtros), `use-simulate.ts` (submit payment + loading state). Todos usan `api.ts` client. Manejar loading, error, data states. | Lógica de datos reutilizable entre páginas. | Data fetching — conecta UI con API del core. | UI-005, UI-006, UI-007 |

#### Branch `Nicolas_10`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| UI-005 | Implementar Simulation page completa | P0 | `app/simulate/page.tsx`: `rail-selector.tsx` (botones PIX/SPEI con banderas para origen y destino), `payment-form.tsx` (formulario dinámico según rail: PIX muestra chave + CPF, SPEI muestra CLABE), campos comunes (amount, currency, purpose). Submit via `api.createPayment()`, redirect a `/payments/:id` al completar. Validación con Zod + react-hook-form. | Página principal del demo — donde se inician pagos simulados. | ENTRADA UI — equivale a hacer POST /payments desde la interfaz. | TEST-004 |
| UI-006 | Implementar Payment Detail page | P0 | `app/payments/[id]/page.tsx`: `flow-timeline.tsx` (8 pasos visuales: Received→Validated→Canonicalized→Normalized→Routed→Translated→Queued→Completed, con colores verde/amarillo/gris según status actual), `message-inspector.tsx` (3 columnas: Original / Canónico / Traducido con JSON pretty-print), `rail-ack-panel.tsx` (respuesta del rail destino), `payment-status-badge.tsx`. Polling cada 2s hasta status terminal. | Visualización completa del ciclo de vida de un pago — diferenciador del PoC. | VISUALIZACIÓN — muestra cada paso del pipeline en la UI. | — |
| UI-007 | Implementar History page | P2 | `app/history/page.tsx`: `payment-table.tsx` (tabla con columns: ID, Origin Rail, Dest Rail, Amount, Status, Created), `filters.tsx` (filtros por status, rail, fecha). Paginación client-side. Click en fila → navega a detalle. | Consulta de pagos históricos para el demo. | CONSULTA — lista todos los pagos procesados. | — |
| UI-008 | Implementar payment-card y status-badge | P2 | `payment-card.tsx` (card reutilizable con resumen de pago para dashboard y history), `payment-status-badge.tsx` (badge con color según status: verde=COMPLETED, rojo=FAILED/REJECTED, amarillo=en progreso, gris=DUPLICATE). Usar STATUS_CONFIG de constants.ts. | Componentes reutilizables para consistencia visual. | UI components — usados en Dashboard y History. | — |

#### Criterio de merge Semana 10
- [ ] UI arranca con `npm run dev` sin errores
- [ ] Dashboard muestra stats (aunque sean 0 si no hay pagos)
- [ ] Simulation page permite seleccionar rail, llenar formulario, y submit
- [ ] Submit crea pago real via API y redirige a detalle
- [ ] Payment detail muestra timeline con pasos coloreados según status
- [ ] Message inspector muestra 3 columnas con JSON
- [ ] History page lista pagos con filtros funcionales

---

### Semana 11 — Testing y Primera Integración E2E

> **Objetivo**: Implementar tests de contrato, integración y E2E. Ejecutar el primer flujo completo con todos los servicios levantados. Corregir bugs encontrados.
>
> **Depende de**: Semana 9 (adaptadores completos), Semana 10 (UI funcional)

#### Branch `Carlos_11`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| TEST-001 | Contract tests (OpenAPI, Zod, RabbitMQ) | P1 | En mipit-testkit: `openapi-validation.test.ts` (validar que responses del core matchean OpenAPI spec), `canonical-schema.test.ts` (validar payloads contra Zod CanonicalPacs008 schema), `rabbitmq-messages.test.ts` (validar estructura de mensajes en colas). | Garantizar que los contratos entre componentes se respetan. | CONTRATOS — si un contrato falla, la integración entre componentes se rompe. | — |
| TEST-002 | Integration tests (core API, translation, routing) | P1 | `core-api.test.ts` (POST + GET contra core real), `translation.test.ts` (round-trip PIX→Canonical→PIX verifica no-loss), `routing.test.ts` (verifica 5 reglas seed contra payloads reales), `idempotency.test.ts` (doble POST misma key), `pipeline.test.ts` (pipeline completo con DB real). | Validar que cada módulo del core funciona correctamente con dependencias reales. | INTEGRACIÓN — prueba módulos reales, no mocks. | TEST-004 |
| TEST-003 | Smoke test script funcional | P1 | En `tools/smoke-test.sh`: health check todos los servicios, crear pago PIX→SPEI, poll hasta COMPLETED (max 30s), verificar campos response con jq. Exit code 0 si todo OK, 1 si falla. | Script rápido para verificar que el sistema funciona — útil post-deploy. | SMOKE — primera línea de defensa antes de correr suite completa. | — |

#### Branch `Nicolas_11`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| TEST-004 | E2E test PIX → SPEI flujo completo | P0 | En `tests/e2e/pix-to-spei.test.ts`: crear pago con debtor PIX + creditor SPEI, poll GET /payments/:id hasta status COMPLETED (timeout 35s), verificar: payment_id formato PMT-ULID, status=COMPLETED, origin_rail=PIX, destination_rail=SPEI, original_payload existe, canonical_payload tiene pacs.008 fields, translated_payload tiene formato SPEI, rail_ack contiene response del mock, timestamps (received_at < completed_at). | Validar el flujo más importante del PoC: pago cross-border PIX→SPEI. | FLUJO COMPLETO — prueba todos los componentes: Core→RabbitMQ→Adapter SPEI→Mock→ACK→Core. | STAB-001 |
| TEST-005 | E2E test SPEI → PIX flujo completo | P0 | Mismo que TEST-004 pero inverso: debtor SPEI + creditor PIX, verificar destination_rail=PIX, translated_payload tiene formato PIX. | Validar flujo inverso SPEI→PIX. | FLUJO INVERSO — confirma bidireccionalidad. | — |
| TEST-006 | Bug fixes encontrados durante E2E | P1 | Reservar tiempo para corregir bugs encontrados al ejecutar E2E. Típicos: serialización JSON incorrecta, mappings faltantes, timing issues con RabbitMQ, status race conditions. | Estabilizar el flujo E2E. | BUG FIXES — crítico para que el sistema funcione. | — |
| TEST-007 | Verificar observabilidad completa | P2 | Con el flujo E2E corriendo: verificar traces en Jaeger (span del POST → pipeline → RabbitMQ → adapter → ACK), verificar métricas en Prometheus (`mipit_payments_total`, latencies), verificar dashboard Grafana muestra datos reales. | Confirmar que la observabilidad funciona con datos reales — diferenciador del PoC para la tesis. | OBSERVABILIDAD — no afecta el flujo pero es requerimiento del SRS. | — |

#### Criterio de merge Semana 11
- [ ] E2E PIX → SPEI completa en < 10s con status COMPLETED
- [ ] E2E SPEI → PIX completa en < 10s con status COMPLETED
- [ ] Contract tests pasan (OpenAPI + Zod + RabbitMQ)
- [ ] Integration tests pasan
- [ ] Smoke test script retorna exit code 0
- [ ] Jaeger muestra trace completo del flujo
- [ ] Grafana dashboard muestra métricas reales

---

### Semana 12 — Estabilización y Cierre de Desarrollo

> **Objetivo**: Performance testing, idempotency E2E, generación de evidencia, y documentación actualizada. Al finalizar, el sistema está estable y listo para la fase de deploy y polish.
>
> **Depende de**: Semana 11 (E2E funcionando)

#### Branch `Carlos_12`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| TEST-008 | E2E idempotency tests | P1 | `idempotency-e2e.test.ts`: (1) Enviar pago, reenviar con mismo Idempotency-Key → recibir misma response sin reprocesar, (2) Enviar con mismo key pero diferente body → 409 Conflict, (3) Enviar con key diferente → nuevo pago creado. Verificar counter `mipit_idempotency_hits_total` incrementa. | Validar idempotencia E2E — requerimiento crítico del SRS para evitar pagos duplicados. | IDEMPOTENCIA — protección contra duplicados a nivel de todo el sistema. | — |
| TEST-009 | Batch load test (50 transacciones) | P1 | `batch-load.test.ts`: cargar `pix-batch-50.json`, enviar 50 pagos en paralelo (Promise.all), esperar 15s, poll todos, calcular: p50/p95/p99 latency, success rate (>= 90%), write `evidence/batch-load-results.json`. Timeout 90s. | Validar que el sistema maneja carga concurrente sin degradarse. | PERFORMANCE — 50 txns simultáneas estresan pipeline + RabbitMQ + adapters. | — |
| STAB-001 | Fix performance issues | P1 | Analizar resultados de batch test: si p95 > 5s → optimizar (connection pooling, batch DB writes, prefetch count RabbitMQ). Si success rate < 90% → investigar failures (timeouts, DLQ messages). | Sistema estable bajo carga moderada. | ESTABILIDAD — el PoC debe funcionar de forma confiable para el demo. | — |

#### Branch `Nicolas_12`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| STAB-002 | Evidence generation scripts funcionales | P1 | Ejecutar `tools/generate-evidence.sh`: capturar health de todos los servicios, queries Prometheus (total_payments, success_rate, avg_latency), screenshots Grafana, export traces Jaeger. Todo guardado en `evidence/` con timestamp. | Generar evidencia reproducible para la tesis. | EVIDENCIA — artefactos requeridos para el documento de tesis. | — |
| STAB-003 | Actualizar READMEs de todos los repos | P2 | Revisar y actualizar README.md de los 8 repos: verificar que las instrucciones de setup funcionan, agregar sección "Estado actual", documentar environment variables reales, agregar badges (build status placeholder). | Documentación actualizada para evaluadores de la tesis. | DOCUMENTACIÓN — no afecta flujo técnico. | — |
| STAB-004 | Demo runbook verificado end-to-end | P1 | Seguir `mipit-docs/demo-runbook/local-demo.md` paso a paso: desde `docker compose up` hasta demo completo (crear pago, ver en UI, mostrar Grafana, mostrar Jaeger). Corregir cualquier paso que no funcione. Agregar screenshots esperados. | Runbook confiable para presentar el PoC — si falla el demo, falla la tesis. | DEMO — el runbook guía toda la presentación. | — |

#### Criterio de merge Semana 12
- [ ] Idempotency E2E: duplicados detectados correctamente
- [ ] Batch 50 txns: success rate >= 90%, p95 < 5s
- [ ] Evidence generada en `evidence/` con datos reales
- [ ] READMEs actualizados y verificados
- [ ] Demo runbook ejecutado exitosamente de punta a punta
- [ ] **HITO: SISTEMA FUNCIONAL COMPLETO**

---
---

## FASE 2: Testing (Semanas 11-12)

Las semanas 11 y 12 corresponden a testing e integración E2E (ver arriba: Semana 11 — Testing, Semana 12 — Estabilización). Al cierre de la semana 12 el sistema debe estar funcional y estable.

---

## FASE 3: Deploy, Adiciones y Polish (Semanas 13-17)

> A partir de aquí el código esencial está completo y testeado. El foco es: despliegue en VMs, hardening de seguridad, optimizaciones, documentación final, y preparación de la presentación.

---

### Semana 13 — Deploy a VMs y CI/CD

> **Objetivo**: Desplegar el sistema en las 3 VMs con Docker Compose y configurar pipeline CI básico.

#### Branch `Carlos_13`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| DEPLOY-001 | Configurar VM1 (DB + RabbitMQ) | P0 | Instalar Docker en VM1. Desplegar postgres + rabbitmq con volumes persistentes. Configurar firewall para puertos 5432, 5672, 15672. Verificar health checks remotos. | Infraestructura de datos en VM dedicada. | PERSISTENCIA — DB y colas en VM separada del compute. | DEPLOY-003 |
| DEPLOY-002 | Configurar VM2 (Core + Adapters) | P0 | Desplegar core, adapter-pix, adapter-spei en VM2. Configurar env vars apuntando a VM1 (DB + RabbitMQ). Verificar conexión entre VMs. | Servicios de compute aislados. | COMPUTE — pipeline + adapters. | DEPLOY-003 |

#### Branch `Nicolas_13`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| DEPLOY-003 | Configurar VM3 (UI + Nginx + Observabilidad) | P0 | Desplegar ui, nginx (HTTPS), prometheus, grafana, jaeger en VM3. Nginx reverse proxy apuntando a VM2 (core). Configurar certificados TLS. | Frontend y observabilidad en VM dedicada. | PRESENTACIÓN — la VM que se muestra en el demo. | DEPLOY-004 |
| DEPLOY-004 | Smoke test en entorno VM | P1 | Ejecutar smoke-test.sh contra el entorno desplegado en VMs. Verificar que flujo E2E funciona cross-VM. Documentar latencias VM vs local. | Confirmar que el deploy funciona en producción-like. | VALIDACIÓN — primer test en entorno real. | — |
| CI-001 | GitHub Actions: lint + build + test | P2 | Crear `.github/workflows/ci.yml` en cada repo: checkout → npm ci → npm run lint → npm run build → npm test. Trigger en push a main y PRs. | Proteger main de código roto. | CI — previene regresiones. | — |

#### Criterio de merge Semana 13
- [ ] 3 VMs levantadas con servicios corriendo
- [ ] Flujo E2E funciona cross-VM
- [ ] CI pipeline verde en GitHub Actions

---

### Semana 14 — Seguridad y Hardening

> **Objetivo**: Mejorar seguridad del PoC: TLS real, JWT con refresh, rate limiting, headers de seguridad.

#### Branch `Carlos_14`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| SEC-001 | Certificados TLS con Let's Encrypt o CA propia | P1 | Reemplazar self-signed por certificados de CA propia con cadena completa. Configurar Nginx con cert + key + chain. Verificar HTTPS sin warnings. | TLS real para el demo — muestra profesionalismo. | SEGURIDAD — protege tráfico HTTP. | — |
| SEC-002 | Rate limiting en API | P1 | Implementar rate limiter en Nginx o Fastify: 100 req/min por IP para POST /payments, 500 req/min para GET. Retornar 429 Too Many Requests con Retry-After header. | Proteger contra abuso — requerimiento no-funcional del SRS. | PRE-PIPELINE — bloquea antes de procesar. | — |

#### Branch `Nicolas_14`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| SEC-003 | JWT con expiración y script de generación | P1 | Configurar JWT con expiración (1h para PoC). Crear script `generate-jwt.sh` que genera token firmado con secret. Documentar en README cómo obtener token para testing. | Tokens con expiración — más realista que token eterno. | AUTH — tokens vencidos rechazan requests correctamente. | — |
| SEC-004 | Security headers y CORS estricto | P2 | Verificar que Helmet agrega: X-Content-Type-Options, X-Frame-Options, Strict-Transport-Security. Configurar CORS para solo permitir origen de UI (mipit.local). | Headers de seguridad estándar. | SEGURIDAD — hardening HTTP. | — |

---

### Semana 15 — Optimización de Performance

> **Objetivo**: Identificar y resolver cuellos de botella. Mejorar latencias y throughput.

#### Branch `Carlos_15`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| PERF-001 | Optimizar queries SQL (índices, explain) | P1 | Ejecutar EXPLAIN ANALYZE en las queries más frecuentes (findById, updateStatus). Agregar índices faltantes si necesario. Implementar connection pooling óptimo. | Reducir latencia de DB — componente más lento del pipeline. | PERSISTENCIA — afecta latencia de cada paso. | — |
| PERF-002 | Optimizar RabbitMQ (prefetch, persistent) | P1 | Tuning: prefetch count en consumers (10 por adapter), confirm mode en publisher, persistent messages, consumer timeout ajustado. Monitorear queue depths en RabbitMQ management. | Mejorar throughput de mensajería. | MENSAJERÍA — afecta latencia entre core y adapters. | — |

#### Branch `Nicolas_15`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| PERF-003 | Profiling y optimización de latencia end-to-end | P1 | El cache TTL de route rules y mappings ya fue implementado en Semana 6 (CORE-012 y CORE-022). En su lugar: ejecutar profiling del pipeline completo con `clinic.js` o flamegraphs. Identificar funciones con mayor latencia, optimizar serialización JSON, evaluar pre-compilación de Zod schemas. Documentar hallazgos en `evidence/profiling-s15.md`. | Reducir latencia del pipeline — encontrar cuellos de botella reales con datos. | PIPELINE — afecta latencia total de cada pago. | — |
| PERF-004 | Benchmark: 100 txns concurrentes | P2 | Generar batch de 100 txns, enviar en paralelo, medir: p50/p95/p99, throughput (txns/s), error rate. Comparar con resultados de Semana 12 (50 txns). Documentar en evidence/. | Benchmark real para la tesis — datos cuantitativos de performance. | PERFORMANCE — datos para el capítulo de resultados. | — |

---

### Semana 16 — Documentación Final

> **Objetivo**: Completar toda la documentación técnica, actualizar diagramas, y preparar artefactos para la tesis.

#### Branch `Carlos_16`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| DOC-001 | Diagramas de arquitectura (PNG) | P1 | Crear los 5 diagramas pendientes en mipit-docs: high-level-architecture.png, sequence-pix-to-spei.png, sequence-spei-to-pix.png, component-diagram.png, deployment-diagram.png. Usar draw.io o Mermaid → PNG. | Diagramas requeridos para el documento de tesis y la presentación. | DOCUMENTACIÓN — artefactos visuales. | — |
| DOC-002 | Actualizar OpenAPI spec con ejemplos reales | P1 | Agregar request/response examples reales basados en los E2E tests. Verificar que el spec matchea exactamente lo que el API retorna. Regenerar si hay cambios. | OpenAPI preciso y con ejemplos — evaluadores pueden probar con Swagger. | DOCUMENTACIÓN — contrato del API. | — |

#### Branch `Nicolas_16`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| DOC-003 | Copiar PDFs de tesis a mipit-docs | P1 | Copiar SRS_MIPIT.pdf, SPMP.pdf, propuesta.pdf a sus carpetas en mipit-docs. Actualizar índice en README. | Centralizar documentación del proyecto. | DOCUMENTACIÓN. | — |
| DOC-004 | Capítulo de resultados: evidencia técnica | P1 | Compilar evidence/: screenshots Grafana con métricas reales, traces Jaeger, resultados batch test (latencias, success rate), logs de E2E. Formato listo para insertar en documento de tesis. | Evidencia cuantitativa para la tesis. | DOCUMENTACIÓN — soporte del capítulo de resultados. | — |

---

### Semana 17 — Demo, buffer y presentación final

> **Objetivo**: Ensayar el demo completo, preparar slides, y verificar que todo funciona de forma reproducible.

#### Branch `Carlos_17`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| DEMO-001 | Preparar datasets de demo atractivos | P2 | Crear 3-5 pagos predefinidos con datos realistas y nombres reales (no test data) para el demo. Incluir: pago PIX→SPEI exitoso, pago SPEI→PIX exitoso, pago duplicado (idempotencia), pago con error. | Demo con datos que cuenten una historia clara. | DEMO — narrativa del PoC. | — |
| DEMO-002 | Ensayo del demo (dry run #1) | P1 | Seguir runbook completo: levantar servicios, ejecutar pagos, mostrar UI, mostrar Grafana, mostrar Jaeger, mostrar código clave. Cronometrar: target 15-20 min. Anotar problemas. | Primer ensayo — identificar problemas de timing y flow. | DEMO — preparación. | DEMO-003 |
| EXTRA-001 | GET /payments (listado con filtros) | P3 | Si no existe: implementar endpoint GET /payments?status=X&rail=Y&page=1&limit=20 en el core. Paginación offset-based. | API más completa para la UI de historial. | API — mejora la UI de historial. | — |
| EXTRA-002 | Webhook/SSE para status updates real-time | P3 | Server-Sent Events en GET /payments/:id/stream. Enviar evento cada vez que el status cambia. UI puede escuchar en vez de polling. | Real-time updates — impresionante para el demo. | UI — elimina polling, mejora UX. | — |
| FINAL-001 | Dry run #2 completo | P0 | Ensayo final del demo completo desde cero (docker compose down -v → up → demo). Cronometrar y ajustar. | Demo perfecto y reproducible. | DEMO. | — |
| FINAL-002 | Freeze de código y tag v1.0.0 | P0 | Crear tag v1.0.0 en los 8 repos. No más cambios de código después de esto. | Versión estable para evaluación. | RELEASE. | — |

#### Branch `Nicolas_17`

| ID | Título | Prioridad | Descripción | Objetivo | Impacto en el flujo | Desbloquea |
|---|---|---|---|---|---|---|
| DEMO-003 | Fix issues del dry run #1 | P1 | Corregir cualquier problema encontrado en DEMO-002. Posibles: servicios lentos al levantar, UI no refresca, dashboards vacíos, scripts no funcionan en clean state. | Demo confiable y reproducible. | BUG FIX. | — |
| DEMO-004 | Preparar slides de presentación | P2 | Crear presentación: problema, solución propuesta, arquitectura, demo en vivo, resultados (métricas + evidencia), conclusiones, trabajo futuro. | Soporte visual para la defensa. | PRESENTACIÓN. | — |
| EXTRA-003 | Dark mode en UI | P3 | Toggle dark/light mode en navbar. Tailwind dark mode con class strategy. Persistir preferencia en localStorage. | UI más profesional para el demo. | UI — visual. | — |
| EXTRA-004 | Health dashboard mejorado | P3 | Página dedicada mostrando: status de cada servicio, queue depths RabbitMQ, connection pool DB, memoria/CPU (si hay métricas). | Vista operacional del sistema. | OBSERVABILIDAD — mejora el demo. | — |
| FINAL-003 | Documentación final README principal | P1 | Crear README principal en carpeta raíz que enlaza los 8 repos con descripción, links, y quick start global. | Punto de entrada para evaluadores. | DOCUMENTACIÓN. | — |
| FINAL-004 | Backup completo y entrega | P0 | Backup de VMs, export de dashboards Grafana, export de traces Jaeger, zip de evidence/. Entrega de repositorios a evaluadores. | Entregable completo de la tesis. | ENTREGA. | — |

---
---

## Resumen de Tickets por Semana

| Semana | Carlos | Nicolas | Total | Foco |
|---|---|---|---|---|
| 1-4 | — | — | 0 | Planeación e investigación (realizadas) |
| 5 ✅ | INFRA-001, INFRA-002, CORE-001, CORE-006, CORE-007, CORE-008 | CORE-002, CORE-003, CORE-004, CORE-005, CORE-009, CORE-010, CORE-011 | 13 | Infra + Persistencia |
| 6 ✅ | *(Nicolas cubrió ambas ramas)* | CORE-012 a CORE-024 (todos) | 13 | Traducción + Normalización + Routing |
| 7 ✅ | CORE-025, CORE-026, CORE-027 *(Carlos: mappings dinámicos S6)* | CORE-028, CORE-029, CORE-030 *(Nicolas cubrió S7 completa)* | 6 | Mensajería + Pipeline |
| 8 | CORE-031, CORE-032, CORE-033 | CORE-034, CORE-035, CORE-036, CORE-037 | 7 | API + Middleware |
| 9 | PIX-001 a PIX-004 | SPEI-001 a SPEI-004 | 8 | Adaptadores |
| 10 | UI-001, UI-002, UI-003 | UI-005, UI-006, UI-007, UI-008 | 7 | Interfaz de Usuario |
| 11 | TEST-001, TEST-002, TEST-003 | TEST-004, TEST-005, TEST-006, TEST-007 | 7 | Testing + E2E |
| 12 | TEST-008, TEST-009, STAB-001 | STAB-002, STAB-003, STAB-004 | 6 | Estabilización |
| 13 | DEPLOY-001, DEPLOY-002 | DEPLOY-003, DEPLOY-004, CI-001 | 5 | Deploy + CI |
| 14 | SEC-001, SEC-002 | SEC-003, SEC-004 | 4 | Seguridad |
| 15 | PERF-001, PERF-002 | PERF-003, PERF-004 | 4 | Performance |
| 16 | DOC-001, DOC-002 | DOC-003, DOC-004 | 4 | Documentación |
| 17 | DEMO-001, DEMO-002, EXTRA-001, EXTRA-002, FINAL-001, FINAL-002 | DEMO-003, DEMO-004, EXTRA-003, EXTRA-004, FINAL-003, FINAL-004 | 12 | Demo + Buffer + Release |
| **TOTAL** | **46 tickets** | **50 tickets** | **96** | |

---

## Diagrama de Dependencias Críticas

```
Semanas 1-4: Planeación (sin tickets de desarrollo)

Semana 5                    Semana 6                 Semana 7                  Semana 8
┌──────────────────┐       ┌──────────────────┐    ┌───────────┐             ┌───────────┐
│ INFRA + CORE-001 │       │ CORE-012..014    │    │ CORE-025  │             │ CORE-031  │
│ CORE-006,007,008 │──────▶│ CORE-019..021    │───▶│ CORE-026  │────────────▶│ CORE-032  │
└──────────────────┘       │ CORE-015..018   │    │ CORE-027  │             │ CORE-033  │
┌──────────────────┐       │ CORE-022..024   │    │ CORE-028  │             │ CORE-034  │
│ CORE-002..005    │──────▶└──────────────────┘    │ CORE-029  │             │ CORE-036  │
│ CORE-009,010,011 │              ▲                │ CORE-030  │             │ CORE-037  │
└──────────────────┘              │                └───────────┘             └───────────┘
                                                       │                          │
Semana 10             Semana 9                         │                          │
┌──────────┐         ┌──────────┐                      │                          │
│ UI-001..008│◀──────│ PIX-001..004│◀──────────────────┘                          │
└──────────┘         │ SPEI-001..004│◀─────────────────────────────────────────────┘
     │               └──────────┘
     ▼
Semana 11-12 (Testing)     Semana 13-17 (Deploy, Seguridad, Perf, Doc, Demo, Release)
┌───────────┐              ┌─────────────────────────────────────────────────────┐
│ TEST-001..009│           │ DEPLOY → SEC → PERF → DOC → DEMO+EXTRA+FINAL          │
│ STAB-001..004│           └─────────────────────────────────────────────────────┘
└───────────┘
```

---

## Push a GitHub

Para pushear los repos a la organización MIPIT-PoC:

```bash
# 1. Autenticarse (una sola vez)
gh auth login

# 2. Crear repos y pushear (ejecutar desde c:\Users\nicog\Documents\Tesis)
repos=("mipit-infra" "mipit-core" "mipit-adapter-pix" "mipit-adapter-spei" "mipit-ui" "mipit-observability" "mipit-docs" "mipit-testkit")

for repo in "${repos[@]}"; do
  cd "$repo"
  gh repo create "MIPIT-PoC/$repo" --public --source=. --remote=origin --push
  cd ..
done
```

Para PowerShell:

```powershell
# 1. Autenticarse
gh auth login

# 2. Crear y pushear
$repos = @("mipit-infra","mipit-core","mipit-adapter-pix","mipit-adapter-spei","mipit-ui","mipit-observability","mipit-docs","mipit-testkit")
foreach ($r in $repos) {
  Push-Location $r
  gh repo create "MIPIT-PoC/$r" --public --source=. --remote=origin --push
  Pop-Location
}
