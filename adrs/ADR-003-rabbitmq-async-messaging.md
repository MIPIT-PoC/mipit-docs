# ADR-003: RabbitMQ como broker de mensajería asíncrona

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

El core necesita comunicarse con los adaptadores de rieles (PIX, SPEI) de forma desacoplada.
La comunicación debe ser asíncrona para que el core no bloquee esperando la respuesta del riel,
y debe soportar reintentos, dead-letter queues y enrutamiento por tipo de riel.

## Decisión

Usar **RabbitMQ 3.13** como broker de mensajería con **topic exchanges** para enrutar mensajes
del core a los adaptadores (`route.{pix|spei}`) y de los adaptadores al core (`ack.{pix|spei}`).
Se configura un dead-letter exchange (`mipit.dlx`) para mensajes que agotan reintentos.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| Kafka | Alta throughput, persistencia de log | Overhead para PoC, complejidad operativa |
| Redis Streams | Simple, ya disponible si se usa Redis | Menos features de messaging (DLQ, routing) |
| HTTP directo (sync) | Simple, sin broker | Acoplamiento temporal, sin reintentos nativos |
| **RabbitMQ** | Topic routing, DLQ, management UI, maduro | Componente adicional de infraestructura |
| NATS | Ligero, rápido | Menos maduro en DLQ y management UI |

## Razones

- Topic exchanges permiten enrutar `route.pix` y `route.spei` a colas específicas
- Dead-letter queues para manejar fallos sin perder mensajes
- Management UI (puerto 15672) facilita debugging durante desarrollo
- Librería `amqplib` bien soportada en Node.js
- Desacopla temporalmente core y adaptadores (el core no espera respuesta síncrona)
- Volumen del PoC (~100 tx/sesión) es cómodo para RabbitMQ sin tuning especial

## Consecuencias

- Se agrega un componente de infraestructura (contenedor RabbitMQ)
- Se necesita manejar serialización/deserialización de mensajes JSON
- Los adaptadores deben implementar consumer + publisher
- Se debe monitorear la salud de las colas (profundidad, consumers activos)
