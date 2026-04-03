# Siguientes Pasos — Hoja de Ruta Post-PoC

Este documento describe las tareas recomendadas ordenadas por prioridad, organizadas en tres horizontes: inmediato (validación del PoC), corto plazo (extensión académica) y largo plazo (producción).

---

## Horizonte 1 — Validación del PoC (esta semana)

### 1. Ejecutar el stack completo localmente

```bash
cd mipit-infra
bash scripts/up.sh
```

Verificar que todos los servicios respondan:

```bash
bash scripts/health-check.sh

# Verificar traducciones
curl http://localhost:8080/translate/rails

# Ejecutar smoke tests completos
bash scripts/smoke-test.sh
```

### 2. Ejecutar todos los tests unitarios

```bash
# Backend core — incluye traductores SWIFT, ISO20022, ACH, FedNow
cd mipit-core && npm test

# Adapter PIX — incluye mapper SPI y formato EndToEndId
cd mipit-adapter-pix && npm test

# Adapter SPEI — incluye validador CLABE y mapper CECOBAN
cd mipit-adapter-spei && npm test

# UI — hooks y componentes
cd mipit-ui && npm test
```

Cobertura esperada: >80% en módulos de traducción.

### 3. Verificar el flujo E2E PIX → SPEI

```bash
# Con el stack arriba, simular una transacción real
curl -X POST http://localhost:8080/payments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(bash scripts/get-token.sh)" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "amount": 1500,
    "currency": "USD",
    "debtor":   { "alias": "PIX-joao@email.com",      "name": "João Silva" },
    "creditor": { "alias": "SPEI-012180000118359719", "name": "María García" }
  }'

# Verificar estado completo
curl http://localhost:8080/payments/{payment_id}
```

---

## Horizonte 2 — Extensión Académica (próximas semanas)

### 4. Tests de integración (mipit-testkit)

El repo `mipit-testkit` contiene la base para tests E2E. Los tests de integración más valiosos para la tesis son:

**4a. Test de traducción bidireccional (round-trip)**
```
PIX → canonical → SPEI → canonical' → PIX'
Verificar: amount, debtor.name, creditor.name se preservan sin pérdida
```

**4b. Test de idempotencia**
```
Enviar mismo pago dos veces con mismo Idempotency-Key
Verificar: segundo request devuelve status 200 con payment_id existente (no duplicado)
```

**4c. Test de timeout del riel**
```
Configurar mock PIX para responder en >5s
Verificar: adapter maneja timeout, publica ACK con status ERROR
Core actualiza payment a FAILED
```

### 5. Agregar un 5to riel (Option A → Option B)

**Candidato recomendado: SEPA CT (Single Euro Payments Area - Credit Transfer)**

- Relevante geográficamente (zona euro, 36 países)
- Usa ISO 20022 XML (diferente a FedNow que usa JSON del mismo estándar — contraste interesante para la tesis)
- Los tipos ya son parcialmente compatibles con `iso20022-mx-to-canonical.ts`

Pasos: ver [adding-a-new-rail.md](./adding-a-new-rail.md).

### 6. Benchmark de latencia de traducción

Medir el overhead de la capa de traducción bajo carga:

```bash
# Instalar k6 (https://k6.io)
brew install k6

# Script de benchmark
cat > /tmp/bench-translate.js << 'EOF'
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    translate_preview: {
      executor: 'constant-rps',
      rate: 50,          // 50 req/s
      duration: '30s',
    },
  },
};

const PAYLOAD = JSON.stringify({
  sourceRail: 'PIX',
  payload: {
    endToEndId: 'E6074694820230601120012345678901',
    valor: { original: '1500.00' },
    pagador: { ispb: '60746948', nome: 'João', contaTransacional: { numero: '123-4', tipoConta: 'CACC' } },
    recebedor: { ispb: '00000000', nome: 'María' },
    chave: '+5521999887766',
    tipo: 'TRANSF',
  },
});

export default function () {
  const res = http.post('http://localhost:8080/translate/preview', PAYLOAD, {
    headers: { 'Content-Type': 'application/json' },
  });
  check(res, { 'status 200': r => r.status === 200 });
}
EOF

k6 run /tmp/bench-translate.js
```

**Métricas esperadas para documentar en la tesis:**
- P50 latencia de traducción a 5 rieles simultáneos
- P99 latencia bajo 50 req/s
- Throughput máximo (req/s) antes de degradación

### 7. Benchmark con wrk (alternativo, más simple)

```bash
brew install wrk

# Traducción simple PIX → SPEI
wrk -t4 -c100 -d30s \
  -s /tmp/post-translate.lua \
  http://localhost:8080/translate
```

### 8. Capturar evidencia para la tesis

```bash
# Screenshots que capturar:
# 1. Dashboard UI con pagos reales
# 2. Payment detail con FlowTimeline completo y RailAckPanel
# 3. Translator page mostrando 5 formatos simultáneos
# 4. Grafana dashboard con métricas de throughput
# 5. Jaeger trace de una transacción completa (end-to-end)

# Jaeger: http://localhost:16686
# Grafana: http://localhost:3000

# Exportar trace como JSON para el apéndice
curl "http://localhost:16686/api/traces/{traceId}" > trace-pix-spei-ejemplo.json
```

---

## Horizonte 3 — Preparación para Producción (largo plazo)

Estos pasos no son necesarios para el PoC académico, pero documentan el camino a producción.

### 9. Autenticación real

Reemplazar el JWT estático del PoC por un proveedor OAuth2:
- Auth0 o AWS Cognito para clientes del middleware
- Scopes: `payments:write`, `translate:read`, `admin:*`
- Certificados mTLS para comunicación inter-adapter

### 10. Compliance y datos sensibles

- **PCI DSS**: Los números de cuenta no deberían almacenarse en texto plano en PostgreSQL
- **LGPD (Brasil)**: CPF/CNPJ son datos personales — encriptar en reposo
- **LFPDPPP (México)**: RFC/CURP igualmente sensibles
- Implementar field-level encryption con AWS KMS o Vault

### 11. Alta disponibilidad

```yaml
# docker-compose.yml en producción
core:
  deploy:
    replicas: 3              # mínimo para HA
    update_config:
      parallelism: 1
      delay: 10s
      failure_action: rollback
    rollback_config:
      parallelism: 1
```

### 12. Conectividad con rieles reales

| Riel | Entorno sandbox | Documentación |
|------|----------------|---------------|
| PIX | BACEN SPI Homologação | BCB Resolution nº 1/2020 |
| SPEI | BANXICO SPEI+ sandbox | spei.banxico.org.mx/docs |
| SWIFT MT103 | SWIFT Alliance Lite2 sandbox | swift.com/our-solutions/banking |
| ISO 20022 | SWIFT MX sandbox (mismo) | iso20022.org |
| ACH NACHA | Plaid Sandbox o Stripe Treasury | nacha.org |
| FedNow | Federal Reserve FedNow Explorer | frbservices.org/financial-services/fednow |

---

## Resumen ejecutivo de prioridades

```
Semana actual:
  ✓ Ejecutar stack local + smoke tests
  ✓ Verificar cobertura de tests (npm test)
  ✓ Capturar evidencia: UI, Grafana, Jaeger

Próximas 2 semanas:
  □ Tests de integración (round-trip, idempotencia, timeout)
  □ Agregar SEPA CT como Option B (nuevo adapter completo)
  □ Benchmark de latencia con k6

Para la defensa de tesis:
  □ Documentar métricas de benchmark
  □ Comparativa de formatos (tabla de equivalencia de campos)
  □ Diagrama de secuencia del flujo completo
```
