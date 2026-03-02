# ADR-001: Stack tecnológico — TypeScript + Node.js

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

Se necesita elegir el lenguaje y runtime para el backend del PoC (core + adaptadores).
El equipo tiene experiencia en TypeScript/JavaScript y el proyecto requiere prototipado rápido.

## Decisión

Usar **TypeScript sobre Node.js 22** con **Fastify** como framework HTTP para el core
y workers nativos de Node.js para los adaptadores.

## Alternativas consideradas

| Alternativa       | Pros                              | Contras                          |
|-------------------|-----------------------------------|----------------------------------|
| Java + Spring Boot| Ecosistema enterprise, tipado     | Verbose, setup pesado para PoC   |
| Go                | Performance, binarios ligeros     | Menos ecosistema ISO/financiero  |
| Python + FastAPI  | Rápido de prototipar              | Tipado dinámico, menos robusto   |
| **TypeScript + Node** | Fullstack unificado, tipado, rápido | Single-threaded (no aplica en PoC) |

## Razones

- Stack unificado (backend + frontend ambos TypeScript)
- Ecosistema npm rico para HTTP, messaging, observabilidad
- Tipado estricto con Zod para validación runtime
- Fastify ofrece buen rendimiento y plugin ecosystem
- Suficiente para el volumen del PoC (100 tx por sesión)

## Consecuencias

- Todo el equipo debe manejar TypeScript
- Se limitan opciones de concurrencia real (pero no es requerimiento del PoC)
- Las dependencias deben mantenerse actualizadas
