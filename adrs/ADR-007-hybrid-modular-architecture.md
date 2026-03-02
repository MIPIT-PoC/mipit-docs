# ADR-007: Arquitectura híbrida modular

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

Se necesita definir el estilo arquitectónico del middleware. El sistema tiene un componente
central (core) que orquesta validación, traducción, enrutamiento y gestión de estados,
y componentes periféricos (adaptadores) que se comunican con rieles de pago externos.
El core tiene un flujo secuencial (pipeline), mientras que la comunicación con adaptadores
debe ser asíncrona y desacoplada.

## Decisión

Adoptar una **arquitectura híbrida modular** que combina:

1. **Monolito modular** en el core — módulos internos (validator, translator, router,
   state-machine) se invocan secuencialmente dentro del mismo proceso
2. **Coreografía asíncrona** entre core y adaptadores — desacoplados vía RabbitMQ
3. **Despliegue independiente** — cada componente (core, adapter-pix, adapter-spei)
   es un contenedor Docker separado

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| Microservicios puros | Máximo desacoplamiento | Overhead de red, complejidad operativa excesiva para PoC |
| Monolito completo | Simple de desplegar | Adaptadores acoplados al core, difícil de escalar individualmente |
| Event sourcing completo | Auditoría perfecta, rebuild de estado | Complejidad de implementación excesiva para PoC |
| **Híbrido modular** | Balance entre simplicidad y desacoplamiento | No es un patrón "puro" (requiere documentar claramente) |
| Hexagonal estricta | Ports & adapters bien definidos | Overhead de abstracciones para un PoC de 2 personas |

## Razones

- El core tiene un flujo naturalmente secuencial → un monolito modular es más simple que microservicios
- Los adaptadores tienen ciclos de vida independientes → despliegue separado permite actualizarlos sin tocar el core
- RabbitMQ ya es una decisión tomada (ADR-003) → la coreografía asíncrona es natural
- Equipo de 2 personas → la simplicidad operativa es prioritaria
- El patrón permite evolucionar hacia microservicios si el proyecto crece

## Consecuencias

- Se documenta claramente qué es "modular interno" vs "distribuido externo"
- Los módulos del core comparten proceso y pueden compartir tipos (sin serialización interna)
- Los adaptadores solo se comunican con el core vía RabbitMQ (nunca HTTP directo)
- Se necesita orquestación de contenedores (Docker Compose) para desarrollo y demo
- El estilo no es puramente microservicios ni puramente monolítico, lo cual debe explicarse en la tesis
