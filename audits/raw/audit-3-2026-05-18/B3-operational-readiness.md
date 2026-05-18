# Auditoría 3 — Frente B3: Operational Readiness y Observabilidad Efectiva

**Fecha:** 2026-05-18
**Agente:** B3
**Scope:** Logs, métricas, alertas, runbook, troubleshooting/DR
**Stack auditado:** `Auditoria-Claude` branch, post Wave 6 (P07 mounted rules, AlertManager, métricas unificadas)

---

## Resumen ejecutivo (5 líneas)

El setup observability existe pero **la operabilidad real es frágil**. La topología RabbitMQ documentada en `definitions.json` **NO se carga** (falta `management.load_definitions` en `rabbitmq.conf`), y el core/adapters declaran queues con args diferentes — divergencia silenciosa entre lo prometido y lo deployado. El runbook tiene 2 aliases con checksum inválido que el mock va a rechazar en una demo en vivo, y referencias a queues que no existen (`q.adapter.pix`, `payments.dlq`). Las alertas son rudimentarias (3 de 4 sin `description`, ninguna con `runbook_url`), un dashboard Grafana queda permanentemente vacío por desalineación de stage labels, y BRE_B tiene un counter declarado-pero-nunca-incrementado. No hay troubleshooting doc, ni scripts de backup/restore, ni rollback de migrations. **Un nuevo dev no puede levantar el stack siguiendo solo los docs sin ayuda**.

---

## Tabla maestra de hallazgos

| ID | Sev | Área | Título | Esfuerzo fix |
|---|---|---|---|---|
| B3-001 | 🔴 CRÍT | DR/Topology | `definitions.json` declarado pero NO cargado — toda la topología canónica fantasma | 1 línea de config |
| B3-002 | 🔴 CRÍT | DR/Topology | `core` crea `payments.dlq` pero `definitions.json` declara `dlq.{pix,spei,breb,ack}` — DLQs divergentes | 1 sprint de unificación |
| B3-003 | 🔴 CRÍT | Runbook | NIT `900123456-1` (row 5) tiene checksum inválido — el mock BRE_B lo rechaza | Cambiar a NIT válido |
| B3-004 | 🔴 CRÍT | Runbook | CPF `12345678901` (row 4) tiene checksum inválido — el mock PIX lo rechaza | Cambiar a CPF válido |
| B3-005 | 🟠 ALTO | Runbook | `health-check.sh` no verifica AlertManager, ni los 3 adapters, ni los mocks, pero el runbook promete la salida | Agregar 7 checks |
| B3-006 | 🟠 ALTO | Runbook | `health-check.sh` hace `curl localhost:5432` (Postgres NO responde HTTP) — siempre marca PG como down | Cambiar a `pg_isready` |
| B3-007 | 🟠 ALTO | Runbook | Runbook menciona queues `q.adapter.pix/spei/breb` y `payments.dlq` — no existen en el código | Sync con `payments.route.*` |
| B3-008 | 🟠 ALTO | Métricas | BRE_B declara `adapterRetriesTotal` pero nunca lo incrementa — dashboard `Reintentos por Adaptador` siempre 0 para BRE_B | Agregar `recordAdapterRetry()` en retry.ts |
| B3-009 | 🟠 ALTO | Métricas | Dashboard `mipit-latency.json` panel 5 queries `stage="route_decision"`; el código usa `pipeline_routing`/`routing` — panel siempre vacío | Renombrar query a `pipeline_routing` |
| B3-010 | 🟠 ALTO | Alertas | 3 de 4 alertas sin `description`, ninguna con `runbook_url` — operador en pager no sabe qué hacer | Completar annotations |
| B3-011 | 🟠 ALTO | Logs | PII leak: `pix-to-canonical.ts:217` + `spei-to-canonical.ts:145` loguean `value: transformedValue` con CPF/CLABE/alias en texto plano | Cambiar key o agregar `*.value` a redact |
| B3-012 | 🟠 ALTO | Logs | Pino logger sin `serializers: { err: pino.stdSerializers.err }` explícito — riesgo de stack truncado en algunas rutas | Agregar serializer |
| B3-013 | 🟠 ALTO | DR | Sin doc de troubleshooting / DR / disaster recovery — escenarios típicos (DB lleno, JWT rotation, queue backup, adapter caído permanente) sin procedimiento | Crear `mipit-docs/troubleshooting.md` |
| B3-014 | 🟠 ALTO | DR | Sin scripts `backup.sh` / `restore.sh` — DR es manual | Agregar scripts pg_dump |
| B3-015 | 🟠 ALTO | DR | `rollback.sh` no incluye `adapter-breb` en `SERVICES` — rollback parcial post-P04 | Agregar a array |
| B3-016 | 🟠 ALTO | DR | Migrations sin transacción (004, 005, 013) ni script `.down.sql` — fallo a mitad deja DB inconsistente | Wrap en `BEGIN;…COMMIT;` + crear backups |
| B3-017 | 🟡 MED | Logs | `consumer.ts:62` loguea `raw: msg.content.toString().slice(0,200)` antes de parsear — puede incluir PII | Cambiar a hash o longitud solamente |
| B3-018 | 🟡 MED | Logs | Pipeline emite 8 `log.info` por payment exitoso (Steps 1-7 + completion) — verbose para producción | Bajar Step 2/3 a `debug` o consolidar |
| B3-019 | 🟡 MED | Topology | Adapters llaman `assertQueue(payments.route.pix)` con args diferentes a `definitions.json` (sin TTL/max-length/quorum) — PRECONDITION_FAILED si se carga definitions | Igualar args en adapter |
| B3-020 | 🟡 MED | Alertas | `AdapterUnreachable` con `for: 1m` puede dispararse por scrape blip de 15-30s — falso positivo | Subir a `for: 2m` |
| B3-021 | 🟡 MED | Topology | `payments.dlq` (crash del core) sin `x-max-length` ni TTL — eventual disco lleno si DLQ crece | Agregar `x-max-length: 100000` |
| B3-022 | 🟡 MED | Métricas | Bre-B usa `brebRetryCount` con label `outcome` mientras PIX/SPEI no tienen ese label — desalineación de cardinalidad | Documentar o unificar |
| B3-023 | 🟡 MED | Runbook | Pre-demo checklist line 11 "Topología canónica creada — exchange `mipit.payments`, DLX `mipit.dlx`, queue `payments.ack` (bound a `ack.pix`, `ack.spei`, `ack.breb`), queue `payments.dlq`" — `payments.dlq` no aparece en definitions; ack queue real usa `ack.#` binding (no listado por riel) | Sync con realidad |
| B3-024 | 🟡 MED | Runbook | vm-demo.md línea 183 dice `mipit:mipit_pwd` en AlertManager curl, pero en otros lados es `mipit:mipit_secret` — inconsistencia de credenciales | Unificar |
| B3-025 | 🟡 MED | Métricas | Dashboard `mipit-overview.json` panel 6 query `sum by (origin_rail, destination_rail)(mipit_payments_total)` — cardinalidad puede ser combinatoria (4 origin × 4 dest × 7 status = 112 series) | OK por ahora, watch |
| B3-026 | 🟢 BAJO | Métricas | `payment_id` no se usa como label en ningún Counter/Histogram — bien, sin cardinality explosion | (sin acción, mención positiva) |
| B3-027 | 🟢 BAJO | Runbook | `local-demo.md` § 9 reset.sh borra todo + relevanta, no preserva dashboards Grafana como dice ("Mantiene dashboards Grafana") — confuso | Aclarar texto |

---

## Detalle de hallazgos

### B3-001 🔴 CRÍT — `definitions.json` se monta pero NO se carga

**Archivo:** `mipit-infra/rabbitmq/rabbitmq.conf`
**Observado:** El archivo `definitions.json` (87 líneas que declaran exchange `mipit.payments`, DLX `mipit.dlx`, queues `payments.route.{pix,spei,breb}`, queues `dlq.{pix,spei,breb,ack}`, queue `payments.ack`, alternate-exchange `mipit.unrouted`, bindings con DLX) se monta como volumen en `docker-compose.yml:46`. Sin embargo, `rabbitmq.conf` (las 11 líneas reales) **no contiene** la directiva `management.load_definitions = /etc/rabbitmq/definitions.json` ni equivalente. El management plugin necesita esa línea explícita para cargar el JSON al startup.

**Por qué es problema:** Las queues, dead-letter exchanges, alternate-exchange (`mipit.unrouted` para mensajes no ruteables), y los args (`x-message-ttl=1h`, `x-max-length=100k`, `x-queue-type=quorum`) **no existen** en runtime. RabbitMQ acepta lo que sea que cada cliente declare con `assertQueue`. Resultado: las queues se crean classic (no quorum), sin TTL, sin max-length. El `mipit.unrouted` no existe y los `mandatory:true` en publicaciones que no rutean SE PIERDEN. La promesa de "topología canónica P10 contract-test la valida" del runbook es falsa: lo que se testea es lo que los servicios crean, no lo del archivo.

**Fix:** Agregar a `rabbitmq.conf`:
```
management.load_definitions = /etc/rabbitmq/definitions.json
```

---

### B3-002 🔴 CRÍT — DLQ topology divergente entre `definitions.json` y código

**Archivos:** `mipit-core/src/config/constants.ts:132`, `mipit-core/src/messaging/rabbitmq.ts:26-27`, `mipit-infra/rabbitmq/definitions.json:65-68`
**Observado:**
- `definitions.json` declara 4 DLQs: `dlq.pix`, `dlq.spei`, `dlq.breb`, `dlq.ack` (con bindings `dlq.pix` / `dlq.spei` / `dlq.breb` / `dlq.ack` al exchange `mipit.dlx`).
- `core/src/messaging/rabbitmq.ts` hace `assertQueue('payments.dlq')` + `bindQueue('payments.dlq', 'mipit.dlx', 'dlq.#')` — una sola DLQ catch-all.
- `core/src/messaging/dlq-handler.ts:14` doc-comment dice `Queue: payments.dlq`.
- `handleFailedMessage` publica a DLX con routing key **`dlq.failed`** (línea 123), que no matchea `dlq.pix/spei/breb/ack`.

**Por qué es problema:** Tres realidades incompatibles:
1. Documentación dice que hay 4 DLQs por riel.
2. Código del core asume 1 DLQ unificada con catch-all.
3. Si `definitions.json` se carga (B3-001 fix), las 4 DLQs SÍ existen pero el core las ignora.

En producción este split deja mensajes huérfanos: si una migración a quorum queues sucede, el core sigue creando classic con nombre divergente y el operador no encuentra los failed messages donde el plan dice.

**Fix:** Decidir un único modelo: ya sea 1 DLQ unificada (eliminar las 4 en definitions.json) o 4 DLQs por riel (cambiar core a publicar a `dlq.<rail>` específico). Mi recomendación: 4 por riel — permite filtrar por riel sin parsear el contenido y aislar fallas.

---

### B3-003 🔴 CRÍT — Runbook usa NIT con checksum inválido

**Archivo:** `mipit-docs/demo-runbook/local-demo.md` row 5
**Observado:** Tabla rail-pairs línea 61 muestra `BREB-900123456-1` como creditor para SPEI→BRE_B. Verificación DIAN mod-11:
```
weights = [3, 7, 13, 17, 19, 23, 29, 37, 41]
digits revertidos: 6,5,4,3,2,1,0,0,9 (de "900123456")
sum = 6×3 + 5×7 + 4×13 + 3×17 + 2×19 + 1×23 + 0 + 0 + 9×41 = 596
596 % 11 = 2 → expected = 11 - 2 = 9
Dado en runbook: 1
```
**El check digit correcto es 9, no 1**. La doc nota explícitamente "todos los alias arriba usan checksums **válidos** (CPF mod-11, CLABE mod-10, NIT mod-11)". Falso.

**Por qué es problema:** El mock BRE_B (`mipit-adapter-breb/src/breb/mock-server.ts:166-170`) valida NIT con `isValidNIT` y rechaza con código BREB002. La demo en vivo fallará en ese row. Si el reviewer pregunta "¿por qué falla esa transacción?", el equipo improvisa.

**Fix:** Reemplazar por `BREB-900123456-9` (check correcto) o regenerar con `mipit-testkit/generators/utils.ts:randomNIT()`.

---

### B3-004 🔴 CRÍT — Runbook usa CPF con checksum inválido

**Archivo:** `mipit-docs/demo-runbook/local-demo.md` row 4
**Observado:** Tabla rail-pairs línea 60 muestra `PIX-12345678901` como creditor para BRE_B→PIX. Validación CPF mod-11:
```
d1 esperado: sum(c[i]*(10-i) for i in 0..8) → 11-(s%11), if d1>=10 then 0
Para "123456789", d1 = 0 (correcto en runbook)
d2 esperado: sum(c[i]*(11-i) for i in 0..9) → 11-(s%11), if d2>=10 then 0
Para "1234567890" → d2 = 9 (no 1)
```
El CPF `12345678901` es uno de los típicos "fake" usados para tests que no pasa el checksum real. La nota dice "checksums válidos". Falso.

**Por qué es problema:** El mock PIX (`mipit-adapter-pix/src/pix/mock-server.ts:166-170`) ahora valida CPF con `isValidCPF()` (P02 fix). Rechaza con AC03. Demo en vivo fallará. Mismo problema que B3-003 — agravado porque ese flujo es BRE_B→PIX, que es uno de los smoke tests críticos.

**Fix:** Reemplazar por un CPF válido (e.g., `52998224725` que tiene checksum válido) o ejecutar `randomCPF()` y poner uno generado.

---

### B3-005 🟠 ALTO — `health-check.sh` no verifica ~50% de los servicios del runbook

**Archivo:** `mipit-infra/scripts/health-check.sh`
**Observado:** El script chequea solo 7 servicios:
- PostgreSQL, RabbitMQ, Core API, UI, Prometheus, Grafana, Jaeger.

El runbook (línea 22-36 de `local-demo.md`) promete que la salida muestra **además**: AlertManager, adapter-pix, adapter-spei, adapter-breb, Nginx, y bindings de queues. **Ninguno** de estos se verifica.

**Por qué es problema:** El comando de "verificar servicios" mentiría — el script imprime "✓" para 7 servicios y termina, pero el operador asume que también verificó adapter-breb (que es el nuevo riel P04). Si breb está caído, no se entera hasta intentar una transacción.

**Fix:** Agregar 7+ checks:
```bash
check_service "AlertManager" "http://localhost:9093/api/v2/status"
check_service "adapter-pix"  "http://localhost:9101/metrics"
check_service "adapter-spei" "http://localhost:9102/metrics"
check_service "adapter-breb" "http://localhost:9103/metrics"
check_service "pix-mock"     "http://localhost:7001/health"
check_service "spei-mock"    "http://localhost:7002/health"
check_service "breb-mock"    "http://localhost:7003/health"
```

---

### B3-006 🟠 ALTO — `health-check.sh` chequea PG con HTTP

**Archivo:** `mipit-infra/scripts/health-check.sh:14`
**Observado:** `check_service "PostgreSQL" "localhost:5432"` — `curl` contra puerto 5432 falla porque PG no habla HTTP. El script **siempre** reporta PG como down (o no responde correctamente).

**Por qué es problema:** Falsos negativos hacen que los operadores ignoren el script — "siempre dice que PG está abajo y todo funciona". Cuando PG realmente falle, no se detecta.

**Fix:** Usar `pg_isready` adentro del container:
```bash
if docker exec mipit-postgres pg_isready -U mipit -d mipit >/dev/null 2>&1; then echo "  ✓ PostgreSQL"; ...
```

---

### B3-007 🟠 ALTO — Runbook menciona queues inexistentes

**Archivo:** `mipit-docs/demo-runbook/local-demo.md:32-34, 40-41`
**Observado:** El runbook lista:
```
✓ adapter-pix   → metrics :9101 / bound q.adapter.pix
✓ adapter-spei  → metrics :9102 / bound q.adapter.spei
✓ adapter-breb  → metrics :9103 / bound q.adapter.breb     (P04)
```
y "Queue `payments.dlq` (TTL 1 día, max-length 100k)".

**Realidad:**
- Las queues reales se llaman `payments.route.pix/spei/breb` (validado en `mipit-adapter-pix/src/messaging/rabbitmq.ts:19` con env `QUEUE_NAME=payments.route.pix`).
- `payments.dlq` no tiene TTL ni max-length (`core/src/messaging/rabbitmq.ts:26`).
- En `definitions.json` (no cargado, B3-001) las queues `payments.route.*` SÍ tienen `x-message-ttl: 3600000` (1 hora, no 1 día) y `x-max-length: 100000`.

**Por qué es problema:** Si el operador entra a RabbitMQ Mgmt UI buscando `q.adapter.pix`, no lo encuentra. Si filtra por `payments.dlq` ve 1 queue sin args. Pierde tiempo, asume corrupción, hace `purge` accidental.

**Fix:** Actualizar texto del runbook para reflejar nombres reales y TTLs reales.

---

### B3-008 🟠 ALTO — BRE_B `adapterRetriesTotal` declarado pero nunca incrementado

**Archivos:**
- `mipit-adapter-breb/src/observability/metrics.ts:47` declara `adapterRetriesTotal` con label `rail`.
- `mipit-adapter-breb/src/breb/retry.ts:47, 50` incrementa **solo** `brebRetryCount` con label `outcome`.
- `mipit-observability/grafana/dashboards/mipit-rails.json:115` query `sum(rate(mipit_adapter_retries_total[5m])) by (rail)`.

**Observado:** El dashboard "Reintentos por Adaptador" en `mipit-rails.json` queries `mipit_adapter_retries_total`. PIX y SPEI lo incrementan via `recordAdapterRetry()`. BRE_B no — solo incrementa el legacy `brebRetryCount`. Resultado: el panel muestra PIX y SPEI con datos, BRE_B siempre en 0.

**Por qué es problema:** Cuando un operador investigue "¿BRE_B está retryeando mucho?", el dashboard miente. La métrica con label `outcome` (legacy) no se muestra en el dashboard unificado P07.

**Fix:** En `mipit-adapter-breb/src/breb/retry.ts`, agregar `adapterRetriesTotal.inc({ rail: 'BRE_B' })` cada vez que se incrementa `brebRetryCount` (al menos en el path `transient_retry`).

---

### B3-009 🟠 ALTO — Dashboard `mipit-latency.json` panel "Routing Decision Latency" siempre vacío

**Archivo:** `mipit-observability/grafana/dashboards/mipit-latency.json:178`
**Observado:** Query: `histogram_quantile(0.95, sum(rate(mipit_payment_latency_ms_bucket{stage="route_decision"}[5m])) by (le))`.

Los stages reales emitidos por el código (`mipit-core/src/pipeline/payment-pipeline.ts` + `route-engine.ts` + `translator.ts`) son:
- `pipeline_total`, `pipeline_to_canonical`, `pipeline_normalization`, `pipeline_routing`, `pipeline_from_canonical`
- `routing`, `normalization`, `translation_to_canonical`, `translation_from_canonical`

**Ninguno se llama `route_decision`.** Panel siempre N/A.

**Por qué es problema:** El reviewer mira el dashboard de latencia "Routing Decision Latency (p95)" pensando que es donde se mide el routing, y ve un stat vacío. Pierde confianza en el resto del dashboard. El panel también tiene thresholds explícitos (50ms yellow, 200ms red) — sugiere que sí debería tener datos.

**Fix:** Cambiar query a `stage="pipeline_routing"` (preferido) o `stage="routing"`.

---

### B3-010 🟠 ALTO — Alertas sin annotations completas ni `runbook_url`

**Archivo:** `mipit-observability/prometheus/rules/mipit-alerts.yaml`
**Observado:**
| Alerta | summary | description | runbook_url |
|---|---|---|---|
| HighErrorRate | ✓ | ✓ | ✗ |
| HighLatency | ✓ | ✗ | ✗ |
| AdapterUnreachable | ✓ | ✗ | ✗ |
| RabbitMQQueueBacklog | ✓ | ✗ | ✗ |

**Por qué es problema:** Cuando una alerta dispara a las 3am, el on-call abre AlertManager y ve "Cola payments.route.pix con más de 100 mensajes pendientes" sin contexto: ¿qué hacer? ¿purgar? ¿reiniciar adapter? ¿escalar? Sin `description` ni `runbook_url` no hay procedimiento. Esta es la diferencia entre observability "presente" y "operacional".

**Fix:** Para cada alerta:
```yaml
annotations:
  summary: "..."
  description: "El adapter {{ $labels.job }} no responde a scrapes Prometheus desde hace ≥1m. Validar logs con `docker logs mipit-adapter-pix`; si OOM, escalar memoria; si crash loop, ver código en mipit-adapter-pix/."
  runbook_url: "https://github.com/MIPIT-PoC/mipit-docs/blob/main/troubleshooting.md#adapter-unreachable"
```

---

### B3-011 🟠 ALTO — PII leak en logs de translation

**Archivos:**
- `mipit-core/src/translation/pix-to-canonical.ts:217` — `log.warn({ field: sourceField, validation: mapping.validation, value: transformedValue }, 'Dynamic validation failed');`
- `mipit-core/src/translation/spei-to-canonical.ts:145` — Mismo patrón.

**Observado:** Cuando un mapping dinámico falla validación, se loguea el `value` crudo bajo el key literal `value`. El `value` puede ser CPF, CNPJ, CLABE, email o phone — todos PII. Los redact paths en `mipit-core/src/observability/logger.ts:22-64` cubren `*.debtor.taxId`, `*.creditor.taxId`, `*.pagador.cpf`, etc., pero **no** `*.value` ni el patrón `{ field, value }`.

**Por qué es problema:** En producción, una mala configuración de mapping ejecuta `log.warn` con CPF/CLABE en plain text. Esto va a archivos de log, agregadores (Loki/ELK), y queda sin redact. GDPR/LFPDPPP exigen no loguear PII sin justificación.

**Fix:** Agregar a `redact.paths`: `'*.value'` y `'*.fields.value'`. O cambiar la línea a `value: '[REDACTED]'` cuando el `field` es uno conocido como PII (mejor: solo loguear `field` y `validation` sin el valor).

---

### B3-012 🟠 ALTO — Pino sin serializer `err` explícito

**Archivo:** `mipit-core/src/observability/logger.ts`
**Observado:** El logger no especifica `serializers: { err: pino.stdSerializers.err }`. En pino v9+ el serializer de errores se activa automáticamente cuando la key es exactamente `err`, pero hay edge cases (custom Error classes, errors wrapping otros errors via `cause`) donde sin serializer explícito el stack no se serializa correctamente.

**Por qué es problema:** En 16 sitios el código loguea `{ err }` (ver `log\.error\(\{\s*err\s*\}` grep). Si el stack se pierde, debugging es mucho más difícil. P.ej. `payment-pipeline.ts:310` log "Pipeline failed" — sin stack ya no se sabe en qué translator/normalizer/route-engine ocurrió.

**Fix:** Agregar al logger:
```ts
serializers: pino.stdSerializers,  // o explícito: { err: pino.stdSerializers.err, req, res }
```

---

### B3-013 🟠 ALTO — Sin documento de troubleshooting / DR

**Observado:** En `mipit-docs/` no existe ningún archivo con `troubleshoot`, `DR`, `disaster`, `recovery` en el nombre. `LIMITATIONS.md` lista lo que el PoC NO hace, pero no responde "si X falla en demo, ¿qué hago?".

Escenarios típicos sin procedimiento documentado:
1. **DB sin disco** — ¿cómo detectarlo antes de morir? (no hay alerta de `disk_free`). Procedimiento de cleanup.
2. **RabbitMQ queue backs up** — Alerta dispara, pero ¿purgar? ¿drain manual? ¿escalar consumers?
3. **Adapter caído permanente** — `RabbitMQQueueBacklog` dispara, ¿purge queue?
4. **JWT secret rotation** — Cambiar `JWT_SECRET` invalidaría todos los tokens en flight; ¿procedimiento blue-green?
5. **Migration falla a mitad** — `migrate.sh` usa `ON_ERROR_STOP=1` pero migrations 004, 005, 013 no tienen BEGIN/COMMIT — DB en estado intermedio sin entry en schema_migrations. ¿Cómo recuperar?
6. **Postgres data loss** — Sin backup, ¿cómo restaurar?

**Por qué es problema:** Operacionalmente, el stack es una bomba: funciona hasta que algo falla y nadie sabe qué hacer.

**Fix:** Crear `mipit-docs/troubleshooting.md` con sección por escenario. Vinculo desde alertas (B3-010).

---

### B3-014 🟠 ALTO — Sin scripts `backup` / `restore`

**Archivo:** `mipit-infra/scripts/`
**Observado:** Scripts presentes: `deploy-vm.sh`, `down.sh`, `health-check.sh`, `logs.sh`, `migrate.sh`, `reset.sh`, `rollback.sh`, `seed.sh`, `smoke-test.sh`, `up.sh`. **Sin `backup.sh`** ni `restore.sh`.

**Por qué es problema:** Si la DB se corrompe o el operador hace `reset.sh` por error (que hace `docker compose down -v`, borra el volumen!), todos los pagos históricos se pierden. No hay procedimiento para snapshot pre-demo o pre-deploy.

**Fix:** Agregar:
```bash
# backup.sh
docker exec mipit-postgres pg_dump -U mipit -d mipit -Fc > backups/mipit-$(date +%F-%H%M).dump

# restore.sh
docker exec -i mipit-postgres pg_restore -U mipit -d mipit --clean < "$1"
```

---

### B3-015 🟠 ALTO — `rollback.sh` no incluye `adapter-breb`

**Archivo:** `mipit-infra/scripts/rollback.sh:23`
**Observado:** `SERVICES=(core adapter-pix adapter-spei ui)` — falta `adapter-breb` (P04, mandatory desde Wave 4).

**Por qué es problema:** Si ejecuto `rollback.sh sha-abc1234`, los servicios listados vuelven a esa SHA pero `adapter-breb` queda con la imagen actual. Estado inconsistente — el resto del stack es Wave N-1 y BRE_B es Wave N. Comportamiento impredecible.

**Fix:** `SERVICES=(core adapter-pix adapter-spei adapter-breb ui)`.

---

### B3-016 🟠 ALTO — Migrations sin transacción ni rollback

**Archivos:** `mipit-infra/db/migrations/004_webhooks.sql`, `005_resilience.sql`, `013_seed_breb_mappings.sql`
**Observado:** Tres de las siete migrations NO empiezan con `BEGIN;` ni terminan con `COMMIT;`. `migrate.sh` ejecuta cada archivo con `psql -v ON_ERROR_STOP=1`. Psql en autocommit aplica cada statement inmediatamente; al primer error, aborta — pero los statements anteriores ya están commiteados. No hay `schema_migrations.version` entry (ese se inserta al final), así que el operador vuelve a ejecutar `migrate.sh` y los DDLs ya aplicados causan errores ("relation already exists").

No hay `.down.sql` ni script de rollback para migrations.

**Por qué es problema:** En producción una migration que falla a mitad rompe el deploy completo y deja la DB inconsistente. El "rollback" se hace manualmente con `psql` — pero el stack productivo no tiene operador con suficiente expertise.

**Fix:**
1. Wrappear todas las migrations con `BEGIN;` ... `COMMIT;`.
2. Crear `.down.sql` para cada migration que tenga rollback no-trivial.
3. `migrate.sh` debe registrar `schema_migrations.version` **dentro** de la misma transacción del DDL (o no commitearlo si falla).

---

### B3-017 🟡 MED — Log raw payload puede contener PII

**Archivo:** `mipit-core/src/messaging/consumer.ts:62`
**Observado:** Cuando un ACK message es JSON inválido:
```ts
logger.error({ err: parseErr, raw: msg.content.toString().slice(0, 200) }, 'Failed to parse ACK message');
```
El `raw` con 200 chars puede contener PII (debtor name, taxId, alias). Antes del parse no aplicó redact (los redact paths funcionan sobre el structured object, no sobre strings raw).

**Por qué es problema:** Si un adapter emite un ACK malformado con un campo extra (e.g. debugging), el contenido llega al log sin redact.

**Fix:** Cambiar a:
```ts
logger.error({ err: parseErr, content_length: msg.content.length, content_hash: hash(msg.content) }, 'Failed to parse ACK message');
```

---

### B3-018 🟡 MED — Pipeline verbose: 8 `log.info` por payment exitoso

**Archivo:** `mipit-core/src/pipeline/payment-pipeline.ts:48-266`
**Observado:** Por cada payment exitoso, el pipeline emite:
1. Step 1 (rail inferred)
2. Step 2 (persisted)
3. Step 3 (validated)
4. Step 4 (canonical)
5. Step 5 (normalized)
6. Step 6 (routed)
7. Step 6b (translated)
8. Step 7 (published)
9. "Pipeline completed successfully"

A 100 TPS sostenidas: 900 log lines/seg. Costo de log shipping + storage no trivial.

**Por qué es problema:** Producción tendría log inflation. Pino formatea bien pero el volumen es real.

**Fix:** Bajar Steps 2/3/4 a `debug` (mantener Step 1 = rail inferred, Step 6 = routed, Step 7 = published como `info`). O consolidar en una línea final `{ steps_completed: [...], duration_ms }` al éxito y solo loguear pasos individuales en `debug`.

---

### B3-019 🟡 MED — `assertQueue` en adapters con args distintos a `definitions.json`

**Archivo:** `mipit-adapter-pix/src/messaging/rabbitmq.ts:19-25` (mismo patrón en spei + breb)
**Observado:** Adapter llama:
```ts
await channel.assertQueue(env.QUEUE_NAME, {
  durable: true,
  arguments: {
    'x-dead-letter-exchange': 'mipit.dlx',
    'x-dead-letter-routing-key': `dlq.pix`,
  },
});
```
`definitions.json` declara la misma queue con `x-queue-type: 'quorum'`, `x-message-ttl: 3600000`, `x-max-length: 100000`.

**Por qué es problema:** Si B3-001 se arregla (definitions.json se carga al startup), el adapter al arrancar va a llamar `assertQueue` con args distintos → **RabbitMQ retorna `PRECONDITION_FAILED` (406)** y el adapter crashea. Solo funciona hoy porque definitions no se carga.

**Fix:** Igualar args entre código y definitions.json. Mejor: que los adapters **NO** asserten las queues y dependan exclusivamente de `definitions.json` (más limpio, menos riesgo de divergencia).

---

### B3-020 🟡 MED — `AdapterUnreachable` con `for: 1m` puede ser falso positivo

**Archivo:** `mipit-observability/prometheus/rules/mipit-alerts.yaml:31`
**Observado:** Scrape interval Prometheus = 15s (`prometheus.yml:2`). Un solo scrape fallido + `for: 1m` puede disparar la alerta tras 2 scrapes fallidos (30s sin response + 30s para llegar al threshold). Network blip transient genera page innecesaria.

**Por qué es problema:** Falsos positivos erosionan trust del operador. "Adapter Unreachable" debe ser real, no scrape glitch.

**Fix:** `for: 2m` (o `3m`) — adapter realmente caído va a seguir abajo, blip se autocorrije.

---

### B3-021 🟡 MED — `payments.dlq` sin TTL ni max-length

**Archivo:** `mipit-core/src/messaging/rabbitmq.ts:26`
**Observado:** `await channel.assertQueue(QUEUES.DLQ, { durable: true });` — sin args.

**Por qué es problema:** Si los adapters fallan masivamente y los DLQ-handler no procesan (e.g. bug), la queue crece indefinidamente. Postgres llena disco, RabbitMQ llena disco, todo cae.

**Fix:** Agregar args:
```ts
arguments: { 'x-message-ttl': 86400000, 'x-max-length': 100000 }
```

---

### B3-022 🟡 MED — Métricas retries con cardinalidad desalineada entre rieles

**Archivos:** `mipit-adapter-{pix,spei}/src/observability/metrics.ts` vs `mipit-adapter-breb/src/observability/metrics.ts:25`
**Observado:**
- PIX/SPEI: `pixRetryCount` / `speiRetryCount` sin labels.
- BRE_B: `brebRetryCount` con label `outcome` (`transient_retry` / `permanent_error` / `exhausted`).

**Por qué es problema:** Las queries Prometheus que asumen schema uniforme (e.g. `sum by (rail)(rate(mipit_adapter_*retries_total[5m]))`) fallan o producen datos parciales. La incoherencia documental también: no se sabe si `outcome` es estándar futuro o BRE_B-only.

**Fix:** Documentar el label `outcome` como BRE_B-only o adoptarlo en los 3. Recomiendo adoptarlo — distinguir retry transient de permanent es útil para todos.

---

### B3-023 🟡 MED — Checklist-pre-demo lista topología que no coincide con código ni definitions

**Archivo:** `mipit-docs/demo-runbook/checklist-pre-demo.md:11`
**Observado:** "Topología canónica creada — exchange `mipit.payments`, DLX `mipit.dlx`, queue `payments.ack` (bound a `ack.pix`, `ack.spei`, `ack.breb`), queue `payments.dlq` (P10 contract-test la valida)".

Realidad:
- `mipit.payments` ✓
- `mipit.dlx` ✓
- `payments.ack` bound a `ack.pix`, `ack.spei`, `ack.breb` — **definitions.json bindea a `ack.#` (un solo binding catch-all)** — `mipit-core/src/messaging/rabbitmq.ts:21-23` bindea los 3 explícitamente. Si solo core arranca y crea la queue, son 3 bindings. Si definitions.json se cargara, sería 1.
- `payments.dlq` — solo si el core la creó; no está en definitions.

**Por qué es problema:** Operador va a `RabbitMQ Mgmt UI` con expectativa de ver 3 bindings + DLQ unificada. La realidad depende de qué arrancó primero. Tres bindings explícitos son seguros porque routing key `ack.pix` matchea tanto el binding específico como `ack.#`.

**Fix:** Sincronizar checklist con la realidad final (post-B3-002 fix).

---

### B3-024 🟡 MED — Credencial inconsistente en vm-demo.md

**Archivo:** `mipit-docs/demo-runbook/vm-demo.md:183`
**Observado:** `curl -u mipit:mipit_pwd http://<VM2_IP>:9093/api/v2/alerts` — el password real es `mipit_secret` (ver `rabbitmq.conf:7`). En `rabbitmq.env.example`, `mipit-core/.env` (línea 70), y resto del runbook, es `mipit_secret`.

**Por qué es problema:** Comando documentado falla con 401. Operador improvisa.

**Fix:** Cambiar a `mipit:mipit_secret`. También, AlertManager no usa auth básica HTTP por default — ese curl no necesita `-u`. Verificar.

---

### B3-025 🟡 MED — Dashboard overview cardinalidad combinatoria

**Archivo:** `mipit-observability/grafana/dashboards/mipit-overview.json:214`
**Observado:** Query `sum by (origin_rail, destination_rail)(mipit_payments_total)`. Con 7 rieles (PIX, SPEI, BRE_B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW) × 7 × 8 statuses = potencialmente 392 series. En la práctica solo se usan 3 rieles productivos (PIX, SPEI, BRE_B) — 3×3×8 = 72 series.

**Por qué es problema:** Si el PoC se escala (P15+), o si alguien hace un test con todos los 7 rieles, las series explotan. Prometheus 1.x se queja con >10k series por métrica.

**Fix:** Marcar como observado, sin acción inmediata. Si crece, agregar `filter` en query: `mipit_payments_total{origin_rail=~"PIX|SPEI|BRE_B"}`.

---

### B3-026 🟢 BAJO — `payment_id` NO se usa como label (positive)

**Archivo:** `mipit-core/src/observability/metrics.ts` + adapter metrics.
**Observado:** Ninguna métrica usa `payment_id` (o `trace_id`, o `uetr`) como label. Estos van solo en logs.

**Por qué es positivo:** Las cardinalidades son seguras. Cada métrica tiene <100 series máx.

---

### B3-027 🟢 BAJO — `reset.sh` aclaración engañosa

**Archivo:** `mipit-infra/scripts/reset.sh:5` + `local-demo.md:94`
**Observado:** `reset.sh` hace `docker compose down -v` (borra todos los volúmenes, incluido Grafana). Pero `local-demo.md:94` dice "Limpia DB, queues, métricas. **Mantiene dashboards Grafana**".

**Por qué es problema:** Si Grafana usa el volumen `grafana-data`, ese se borra con `-v`. Los dashboards provisionados via `dashboards.yaml` se re-cargan, pero cualquier dashboard custom NO. Texto del runbook miente.

**Fix:** Aclarar: "Limpia DB, queues, métricas y dashboards Grafana custom; los provisionados se re-cargan automáticamente."

---

## Conclusión: ¿Podría un nuevo dev levantar el stack siguiendo solo los docs sin ayuda?

### **NO.**

### 3 razones principales:

1. **El runbook tiene comandos rotos.** `health-check.sh` chequea Postgres con HTTP (B3-006, falla silenciosamente), no verifica AlertManager ni los 3 adapters (B3-005), y promete una salida que el script no produce (B3-007). El nuevo dev ejecuta `bash scripts/health-check.sh`, ve "✗ PostgreSQL" siempre, asume que PG falló, ejecuta `reset.sh` (que borra volúmenes), y entra en loop.

2. **Los datos de demo están rotos.** Dos de los seis rail-pairs (B3-003 BRE_B con NIT inválido, B3-004 PIX con CPF `12345678901`) van a ser rechazados por los mocks. Sin diagnosticar la falla profundo en logs, el dev concluye "MIPIT no funciona". Y al no haber un troubleshooting doc (B3-013), no tiene cómo recuperar.

3. **La topología RabbitMQ es fantasma.** `definitions.json` se monta pero no se carga (B3-001) y `payments.dlq` vs `dlq.{pix,spei,breb,ack}` están en conflicto (B3-002). Si el dev entra a RabbitMQ Mgmt UI buscando lo que el runbook dice, no lo encuentra. Asume corrupción, hace purge accidental, pierde mensajes. Cuando intente arreglar definitions.json activando `management.load_definitions`, los adapters empiezan a crashear por `PRECONDITION_FAILED` (B3-019) — porque sus `assertQueue` no coinciden.

### Bonus razón (4): No hay forma de validar end-to-end que el setup esté correcto.
`smoke-test.sh` solo testea endpoints `/translate` y `/health` — no envía un `POST /payments` real ni verifica que el adapter ack vuelva. El "PASS" del smoke no garantiza que el stack opere.

### Lo que SÍ funciona (positivos)

- **Métricas unificadas (P07)** están bien diseñadas — labels cardinality-safe, recording rules razonables, buckets correctos.
- **AlertManager webhook receiver** (B3 verificó `webhooks.ts`) procesa JSON v4 correctamente con zod + soft-fail.
- **Logger Pino con redact** cubre la mayoría de PII paths (con 2 huecos identificados — B3-011, B3-017).
- **Topología en `definitions.json` declarativa** es la dirección correcta — solo falta que se cargue y que los adapters dejen de re-declarar.
- **`payment_id` NO se usa como label** — disciplina excelente en cardinalidad (B3-026).

---

**Fin del reporte B3.**
