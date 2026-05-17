# Checklist Pre-Demo

Verificar todos los puntos antes de iniciar una demostración.

## Infraestructura

- [ ] Docker Engine corriendo con ≥6 GB libres (16 contenedores en local: postgres, rabbitmq, jaeger, prometheus, **alertmanager**, grafana, core, 3 adapters, 3 mocks, ui, optional postgres-exporter)
- [ ] Todos los contenedores `Up (healthy)` (`docker compose ps`)
- [ ] PostgreSQL 16 aceptando conexiones (`scripts/health-check.sh`)
- [ ] RabbitMQ 3.13 operativo — Mgmt UI en `:15672` (user `mipit` / pwd from `.env`)
- [ ] Topología canónica creada — exchange `mipit.payments`, DLX `mipit.dlx`, queue `payments.ack` (bound a `ack.pix`, `ack.spei`, **`ack.breb`**), queue `payments.dlq` (P10 contract-test la valida)

## Servicios de aplicación

- [ ] `mipit-core` → `GET /health` con `status=ok` y dependencias `postgres`/`rabbitmq` `ok`
- [ ] `POST /auth/token` devuelve un JWT (solo dev/staging; en prod responde 404 — esperado)
- [ ] `mipit-adapter-pix` consumiendo `q.adapter.pix` (logs: "ready, consuming…")
- [ ] `mipit-adapter-spei` consumiendo `q.adapter.spei`
- [ ] **`mipit-adapter-breb`** (P04) consumiendo `q.adapter.breb`
- [ ] Cada adapter expone métricas con label `rail` (P07): `mipit_adapter_requests_total{rail="PIX"}`, etc.
- [ ] `mipit-ui` (Next.js 15) accesible vía HTTPS y muestra el `<Toaster />` en errores (P11)

## Observabilidad (P07)

- [ ] Prometheus scrappea TODOS los targets — http://localhost:9090/targets — incluye core + 3 adapters (`:9101/:9102/:9103`) + rabbitmq exporter
- [ ] `rule_files` cargado — `curl http://localhost:9090/api/v1/rules | jq '.data.groups[].name'` muestra `mipit-recording` y `mipit-alerts`
- [ ] AlertManager arriba en `:9093` y configurado con receiver `webhook → /webhooks/alertmanager`
- [ ] Grafana dashboard "MiPIT Overview" carga con datos: latencia p50/p95/p99 (recording rules), success rate, throughput por rail
- [ ] Jaeger recibe trazas; `mipit-core`, `mipit-adapter-*` aparecen en el dropdown
- [ ] UI muestra `trace_id` clicable que abre Jaeger en la vista de detalle de pago (P11)

## Datos y estado

- [ ] DB limpia o con seed de prueba controlado (`scripts/reset.sh` si hay dudas)
- [ ] Colas RabbitMQ vacías
- [ ] No hay pagos previos en estados intermedios (`COMPENSATING`, `DEAD_LETTER`) que confundan la demo
- [ ] **Generators con checksums válidos** (P10) — usar `mipit-testkit/generators/` o las muestras de `datasets/{pix,spei,breb}/*-valid-*.json`

## Red y acceso

- [ ] Navegador en modo incógnito (para evitar caché de certificado autofirmado o JWT viejo)
- [ ] Si es demo en VMs: firewall abierto entre VM1↔VM2 (ver `vm-demo.md`)
- [ ] Si demo remota: compartir pantalla testeado, resolución ≥1080p

## Preparación de demo

- [ ] Conocer el flujo: 3 rail-pairs base (PIX→SPEI, BRE_B→PIX, SPEI→BRE_B) + idempotencia + fallo + compensación
- [ ] Tener abiertos en tabs: UI, Grafana ("MiPIT Overview"), Jaeger, RabbitMQ Mgmt, AlertManager
- [ ] Tabla de aliases válidos a la mano (ver `local-demo.md` § 4) — los CPF/CLABE/NIT incluidos pasan los checksums
- [ ] Dataset de respaldo: `mipit-testkit/datasets/breb/breb-valid-{01,02,nit}.json` y equivalentes PIX/SPEI
- [ ] Smoke test pre-warm: `cd mipit-testkit && npm run smoke` (debería terminar verde, P10 cubre PIX→SPEI, SPEI→BRE_B, BRE_B→PIX)
