# Tareas Semana 8 — Nicolas

## Objetivo de la semana

Implementar los middlewares de autenticación JWT y tracing, el bootstrap completo del servidor (`server.ts` + `index.ts`), y el integration test HTTP → pipeline → DB. Al finalizar, `mipit-core` es un servicio HTTP funcional que:

- Rechaza requests sin JWT válido (401)
- Propaga `X-Trace-ID` en toda la cadena
- Arranca conectando OTel → DB → RabbitMQ → Fastify → AckConsumer
- Se apaga con graceful shutdown (SIGTERM/SIGINT)
- Responde al integration test con Fastify inject

## Dependencias

- Semana 7 completada: `PaymentPipeline`, `AckConsumer`, `Publisher`, `AuditService` — todo en master.
- Skeletons existentes: `auth.ts`, `tracing.ts`, `server.ts`, `index.ts`, `payments.ts`, `idempotency.ts`, `error-handler.ts` — todos con TODOs o placeholders.
- `@fastify/jwt` ya en `package.json`.

## Estado actual del skeleton

| Archivo | Estado | Qué falta |
|---|---|---|
| `api/middleware/auth.ts` | Stub que solo verifica presencia del header `Bearer` | Verificar JWT real con `@fastify/jwt`, decodificar claims, decorar request |
| `api/middleware/tracing.ts` | Básico: extrae `X-Trace-ID` o genera ULID | Agregar response header `X-Trace-ID`, propagar a OTel span context |
| `api/server.ts` | Registra cors, helmet, routes, error handler | Registrar JWT plugin, aplicar hooks (tracing → auth → idempotency), inyectar dependencias a las rutas |
| `api/routes/payments.ts` | Placeholders que retornan datos hardcoded | Conectar `PaymentPipeline` real, implementar `POST` y `GET` con lógica real, manejo de errores |
| `src/index.ts` | Bootstrap básico con `TODO` para AckConsumer | Wireup completo de repos, servicios, pipeline, registrar AckConsumer |

---

## Tickets de Nicolas — Semana 8

### CORE-034: Middleware JWT Auth

**Archivo**: `src/api/middleware/auth.ts`

**Qué hacer**:
1. Registrar `@fastify/jwt` como plugin de Fastify en `server.ts` con `secret: env.JWT_SECRET`
2. En `auth.ts`, usar `request.jwtVerify()` para validar el token
3. Si falla verificación → `401 Unauthorized` con `{ code: 'UNAUTHORIZED', message }`
4. Decorar `request.user` con los claims decodificados (sub, iat, exp)
5. Crear un script/util para generar tokens de prueba (JWT firmado con JWT_SECRET para testing)

**Cómo hacerlo**:
- `@fastify/jwt` ya está en `package.json`. Al registrarlo, Fastify añade `request.jwtVerify()` y `app.jwt.sign()`
- El middleware debe ser un hook `onRequest` en el server que se aplique SOLO a `/payments` (no a `/health` ni `/metrics`)
- Para el PoC, los claims mínimos son `{ sub: 'mipit-client', role: 'admin' }`

**Errores esperados**:
- Token expirado → 401
- Token con firma inválida → 401
- Header ausente → 401
- Token válido → pasa al siguiente middleware

---

### CORE-035: Middleware de Tracing

**Archivo**: `src/api/middleware/tracing.ts`

**Qué hacer**:
1. Extraer `X-Trace-ID` del header de request, o generar ULID si no viene
2. Inyectar `traceId` en el contexto del request (ya hace esto el skeleton)
3. **Nuevo**: Agregar `X-Trace-ID` como response header para que el cliente lo reciba
4. **Nuevo**: Propagar el traceId al contexto de OpenTelemetry (`trace.getActiveSpan()?.setAttribute`)
5. Aplicar como primer hook `onRequest` (antes de auth e idempotency)

**Cómo hacerlo**:
- Usar `reply.header('X-Trace-ID', traceId)` en el middleware
- Importar `trace` de `@opentelemetry/api` para propagar al span activo
- El tracing se aplica a TODAS las rutas (incluye `/health` y `/metrics`)

---

### CORE-036: Server build + index.ts bootstrap

**Archivo**: `src/api/server.ts` y `src/index.ts`

**Qué hacer en `server.ts`**:
1. Registrar plugin `@fastify/jwt` con `{ secret: env.JWT_SECRET }`
2. Agregar hook `onRequest` global para tracing (todas las rutas)
3. Agregar hook `onRequest` para auth SOLO en rutas `/payments*`
4. Pasar `deps` expandido a las rutas: incluir `db`, `channel`, y las instancias de repositorios y servicios

**Qué hacer en `index.ts`**:
1. Instanciar repos: `PaymentRepository`, `AuditRepository`, `IdempotencyRepository`
2. Instanciar servicios: `AuditService`, `Translator`, `Normalizer`, `RouteEngine`, `Publisher`
3. Instanciar `PaymentPipeline` con todas sus dependencias
4. Instanciar `AckConsumer` y llamar `.start()`
5. Pasar todo al `buildServer()` via `deps` extendido
6. Verificar que `shutdown` cierre: app, channel, connection, pool, sdk

**Cómo hacerlo**:
- Ampliar la interfaz `ServerDeps` para incluir `pipeline`, `paymentRepo`, `auditRepo`, `idempotencyRepo`, `auditService`
- En `index.ts`, seguir el orden: OTel → DB → RabbitMQ → instanciar repos → instanciar servicios → instanciar pipeline → buildServer → start AckConsumer → listen
- Guardar `connection` de RabbitMQ además de `channel` para cerrar ambos en shutdown

---

### CORE-037: Integration test HTTP → pipeline → DB

**Archivo**: `test/integration/http-pipeline.test.ts`

**Qué hacer**:
1. Crear el test file con mocks de DB (Pool) y RabbitMQ (Channel)
2. Construir un `buildServer()` con los deps mockeados
3. Test `POST /payments` con payload válido + Idempotency-Key + JWT → esperar 201
4. Verificar que `paymentRepo.create()` fue llamado
5. Verificar que `publisher.publishToAdapter()` fue llamado
6. Test `POST /payments` sin JWT → esperar 401
7. Test `POST /payments` con body inválido → esperar 400
8. Test `GET /payments/:id` → esperar datos del pago
9. Test `POST /payments` con Idempotency-Key repetida → esperar response cacheada
10. Verificar que response incluye header `X-Trace-ID`

**Cómo hacerlo**:
- Usar `app.inject()` de Fastify para simular HTTP sin levantar el server
- Generar JWT válido con `app.jwt.sign({ sub: 'test' })`
- Mockear `Pool` con `jest.fn()` para los queries
- Mockear `Channel` con `jest.fn()` para publish/consume

---

## Orden de ejecución recomendado

1. **CORE-035** (tracing) — independiente, rápido, base para los demás
2. **CORE-034** (auth JWT) — necesita que server registre el plugin
3. **CORE-036** (server.ts + index.ts) — integra todo: tracing, auth, pipeline, consumer
4. **CORE-037** (integration test) — verifica todo funcionando junto

## Unit tests por ticket

| Ticket | Tests esperados |
|---|---|
| CORE-034 | Auth: request sin header → 401, token inválido → 401, token expirado → 401, token válido → pasa, claims decorados en request |
| CORE-035 | Tracing: genera ULID si no viene header, usa header si viene, response incluye X-Trace-ID, propaga a span |
| CORE-036 | Server: build retorna Fastify instance, registra rutas /health /metrics /payments, hooks aplicados. Index: no tests unitarios (es bootstrap) |
| CORE-037 | Integration test (ya es test en sí) |

## Criterios de merge

- [ ] Request sin JWT → 401
- [ ] Request con JWT válido + payload válido → 201 con payment_id
- [ ] Response incluye header `X-Trace-ID`
- [ ] `GET /payments/:id` retorna detalle con audit trail
- [ ] Idempotency-Key duplicada → response cacheada
- [ ] `POST /payments` con body inválido → 400 con detalles de validación
- [ ] Integration test pasa con Fastify inject
- [ ] `npx tsc --noEmit` compila sin errores
