# Arquitectura: Visión general

## Estilo arquitectónico

MiPIT emplea una **arquitectura híbrida modular** que combina:

- **Orquestación centralizada** en el core (pipeline secuencial de procesamiento)
- **Coreografía asíncrona** entre core y adaptadores (vía RabbitMQ)
- **Despliegue independiente** de cada componente como contenedor Docker

Este enfoque permite mantener la simplicidad de un monolito modular en el core mientras desacopla los adaptadores de rieles específicos mediante mensajería asíncrona.

## Componentes principales

```
┌──────────────┐     HTTPS/REST      ┌──────────────────────────────────────────────────┐
│   mipit-ui   │ ◄──────────────────► │                  mipit-core                      │
│   (React)    │                      │                                                  │
└──────────────┘                      │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
                                      │  │ Validator │→│Translator│→│ Routing Engine   │  │
                                      │  └──────────┘ └──────────┘ └──────────────────┘  │
                                      │        ↓             ↓              ↓             │
                                      │  ┌───────────────────────────────────────────┐   │
                                      │  │          State Machine + Postgres         │   │
                                      │  └───────────────────────────────────────────┘   │
                                      └────────────────────┬───────────────────────────┘
                                                           │ RabbitMQ (topic exchange)
                                              ┌────────────┴────────────┐
                                              ▼                         ▼
                                    ┌──────────────────┐     ┌──────────────────┐
                                    │ mipit-adapter-pix │     │ mipit-adapter-spei│
                                    │   (Worker Node)   │     │   (Worker Node)   │
                                    └────────┬─────────┘     └────────┬──────────┘
                                             ▼                        ▼
                                      PIX Sandbox/Mock         SPEI Sandbox/Mock
```

## Flujo de una transacción (PIX → SPEI)

1. **UI** envía `POST /payments` al core vía Nginx reverse proxy
2. **Core** valida el payload y verifica idempotencia (`Idempotency-Key`)
3. **Translator** convierte el payload original al modelo canónico (pacs.008 JSON)
4. **Routing Engine** evalúa reglas YAML y determina el riel destino (SPEI)
5. **Core** publica mensaje canónico en RabbitMQ (`route.spei`)
6. **Adapter-SPEI** consume el mensaje, traduce a formato SPEI, y envía al sandbox/mock
7. **Adapter-SPEI** publica ack en RabbitMQ (`ack.spei`) con resultado del riel
8. **Core** consume el ack, actualiza estado a `COMPLETED` o `REJECTED`
9. **UI** consulta `GET /payments/{id}` y muestra el timeline completo

## Observabilidad

Cada componente exporta:

- **Trazas** vía OpenTelemetry SDK → Jaeger (propagación W3C Trace Context)
- **Métricas** vía endpoint `/metrics` → Prometheus → Grafana
- **Logs** JSON estructurados a stdout → recolección Docker

## Decisiones clave

Las decisiones arquitectónicas están documentadas como ADRs en [`adrs/`](../adrs/README.md).

## Diagramas

Los diagramas detallados (secuencia, componentes, despliegue) se encuentran en [`diagrams/`](diagrams/).
