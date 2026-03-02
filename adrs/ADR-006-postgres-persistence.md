# ADR-006: PostgreSQL como capa de persistencia

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

El core necesita persistir el estado de las transacciones (payload original, modelo canónico,
traducción, estado, timestamps) y las keys de idempotencia. Se requiere una base de datos
que soporte transacciones ACID, consultas flexibles y sea fácil de operar en Docker.

## Decisión

Usar **PostgreSQL 16** como base de datos relacional para el core. Se usa el tipo `jsonb`
para almacenar los payloads (original, canónico, traducido, rail_ack) y columnas tipadas
para campos indexados (payment_id, status, created_at). Se accede mediante un query builder
ligero (Kysely o Knex) en lugar de un ORM pesado.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| MongoDB | Flexible con documentos JSON | Sin ACID multi-documento nativo, menos consistente |
| SQLite | Zero-config, embebido | Sin concurrencia real, no apto para multi-contenedor |
| MySQL | Conocido, estable | Menos soporte nativo de JSONB, menos extensiones |
| **PostgreSQL** | ACID, JSONB nativo, extensiones, maduro | Más pesado que SQLite (pero trivial en Docker) |
| In-memory only | Ultra simple | Se pierde al reiniciar, no apto ni para demo |

## Razones

- ACID garantiza consistencia de la máquina de estados (una transacción no puede estar en dos estados)
- `jsonb` permite almacenar payloads variables sin schema rígido por columna
- Índices GIN sobre jsonb habilitan queries sobre campos internos si se necesita
- Imagen Docker oficial liviana y estable
- Ecosistema de drivers Node.js maduro (pg, Kysely)
- Volumen del PoC (~100 tx/sesión) no requiere tuning de performance

## Consecuencias

- Se agrega un contenedor PostgreSQL a la infraestructura
- Se necesitan migraciones de schema (manejadas por el core al iniciar)
- Los payloads JSON en jsonb no tienen schema enforcement en DB (se valida en aplicación con Zod)
- Si el PoC evoluciona, PostgreSQL escala bien horizontalmente con read replicas
