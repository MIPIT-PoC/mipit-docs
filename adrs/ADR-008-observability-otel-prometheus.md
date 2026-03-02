# ADR-008: Observabilidad — OpenTelemetry + Prometheus + Grafana

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

Un middleware de pagos necesita observabilidad para demostrar que las transacciones fluyen
correctamente, diagnosticar fallos y medir latencias. Para la tesis, la observabilidad
también sirve como evidencia de que el sistema funciona end-to-end. Se necesitan tres
pilares: trazas distribuidas, métricas y logs estructurados.

## Decisión

Implementar los tres pilares de observabilidad usando:

1. **OpenTelemetry SDK** en cada servicio para instrumentación de trazas y métricas
2. **Jaeger** como backend de trazas distribuidas (recibe spans vía OTLP)
3. **Prometheus** para scraping de métricas (cada servicio expone `/metrics`)
4. **Grafana** para dashboards de métricas y exploración de trazas
5. **Logs JSON estructurados** a stdout, recolectados por Docker

Propagación de contexto vía **W3C Trace Context** (`traceparent` header) entre HTTP
y correlación con `trace_id` en mensajes RabbitMQ.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| Sin observabilidad | Cero overhead | No hay forma de demostrar el flujo ni diagnosticar |
| Solo logs | Simple | Sin trazas distribuidas, sin métricas |
| Datadog/New Relic | Todo-en-uno, SaaS | Costo, dependencia externa, no auto-hospedable |
| ELK Stack | Logs avanzados, búsqueda | Pesado para PoC, Elasticsearch consume mucha RAM |
| **OTel + Prometheus + Jaeger + Grafana** | Estándar abierto, tres pilares, auto-hospedable | Más componentes de infraestructura |

## Razones

- OpenTelemetry es el estándar de la industria para instrumentación (vendor-neutral)
- Jaeger visualiza trazas end-to-end (UI → core → adapter → riel) con waterfall view
- Prometheus es el estándar de facto para métricas en contenedores
- Grafana unifica métricas (Prometheus) y trazas (Jaeger) en una sola UI
- W3C Trace Context permite correlación automática entre servicios
- Todos los componentes son open source y corren en Docker
- Las capturas de dashboards y trazas sirven como evidencia para la tesis

## Consecuencias

- Se agregan 3 contenedores de infraestructura (Jaeger, Prometheus, Grafana)
- Cada servicio necesita inicializar el SDK de OpenTelemetry al arrancar
- El overhead de instrumentación es negligible para el volumen del PoC
- Se necesitan dashboards pre-configurados en Grafana (provisioning)
- Los logs deben ser JSON con campos consistentes (trace_id, service, level, msg)
