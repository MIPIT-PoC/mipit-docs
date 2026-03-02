# Checklist Pre-Demo

Verificar todos los puntos antes de iniciar una demostración.

## Infraestructura

- [ ] Docker Engine corriendo y con suficiente memoria (mínimo 4 GB libre)
- [ ] Todos los contenedores levantados (`docker ps` muestra todos los servicios)
- [ ] PostgreSQL aceptando conexiones (`scripts/health-check.sh` pasa)
- [ ] RabbitMQ operativo — Management UI accesible en puerto 15672
- [ ] Colas creadas y con consumers activos (`q.adapter.pix`, `q.adapter.spei`, `q.core.ack`)

## Servicios de aplicación

- [ ] `mipit-core` respondiendo a `/health` con status `ok` y dependencias `ok`
- [ ] `mipit-adapter-pix` conectado a su cola y procesando (verificar logs: `docker logs mipit-adapter-pix --tail 5`)
- [ ] `mipit-adapter-spei` conectado a su cola y procesando (verificar logs: `docker logs mipit-adapter-spei --tail 5`)
- [ ] `mipit-ui` accesible vía HTTPS (https://localhost o IP correspondiente)

## Observabilidad

- [ ] Prometheus scrapeando targets correctamente (http://localhost:9090/targets — todos UP)
- [ ] Grafana accesible y dashboards cargados (http://localhost:3000 — dashboard "MiPIT Overview" visible)
- [ ] Jaeger accesible y recibiendo trazas (http://localhost:16686 — servicio `mipit-core` aparece en dropdown)

## Datos y estado

- [ ] Base de datos limpia o con datos de prueba controlados (ejecutar `scripts/reset.sh` si es necesario)
- [ ] Colas RabbitMQ vacías (sin mensajes pendientes de demos anteriores)
- [ ] No hay transacciones previas que confundan la demostración

## Red y acceso

- [ ] Navegador abierto sin caché problemático (usar modo incógnito si hay dudas con certificados)
- [ ] Certificado autofirmado aceptado en el navegador (para HTTPS)
- [ ] Si es demo remota: compartir pantalla funcionando, resolución legible

## Preparación de demo

- [ ] Datos sintéticos preparados (nombres, alias, montos) — ver tablas en [local-demo.md](local-demo.md)
- [ ] Conocer el flujo de la demo: PIX→SPEI, SPEI→PIX, idempotencia, fallo
- [ ] Tener abierto en tabs: UI, Grafana, Jaeger, RabbitMQ Management
