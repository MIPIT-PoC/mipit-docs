# ADR-005: Seguridad del PoC — JWT + HTTPS

**Estado**: Aceptado
**Fecha**: 2026-03-01
**Autores**: Nicolás Calderón, Carlos Mejía

## Contexto

El PoC necesita un mecanismo de autenticación y transporte seguro que sea representativo
de un sistema real pero sin la complejidad de un identity provider completo (OAuth2/OIDC).
El alcance es demostrar que el middleware contempla seguridad, no implementar un sistema
de autenticación production-grade.

## Decisión

Usar **JWT (JSON Web Tokens)** con firma simétrica (HS256) para autenticación de la API,
y **HTTPS vía Nginx** con certificados autofirmados para cifrado en tránsito.
Se genera un token estático de demo que la UI incluye automáticamente.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| Sin autenticación | Simple, rápido | No demuestra consideración de seguridad |
| API Key estática | Muy simple | No estándar, sin claims ni expiración |
| OAuth2 + OIDC completo | Production-grade | Excesivo para PoC, requiere identity provider |
| **JWT + HTTPS** | Estándar, claims, expiración, demuestra intención | No es production-grade (firma simétrica, token estático) |
| mTLS | Autenticación mutua fuerte | Complejidad de certificados excesiva para PoC |

## Razones

- JWT es estándar de la industria para APIs REST
- Los claims permiten documentar roles/permisos aunque no se apliquen granularmente
- HTTPS demuestra cifrado en tránsito (requisito básico de cualquier sistema de pagos)
- El token estático de demo simplifica la experiencia de demostración
- Se documenta explícitamente como limitación del PoC vs. un sistema real

## Consecuencias

- La seguridad es **demostrativa, no production-grade** (se documenta como limitación)
- El secret del JWT se incluye en configuración (no en vault)
- Los certificados HTTPS son autofirmados (el navegador mostrará advertencia)
- Si el PoC evoluciona, se debería migrar a OAuth2/OIDC con firma asimétrica (RS256)
