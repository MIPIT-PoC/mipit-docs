# Runbook: Demo Local Completa

## Pre-requisitos
- Docker Engine 26+ y Docker Compose instalados
- Repos clonados: mipit-infra, mipit-core, mipit-adapter-pix, mipit-adapter-spei, mipit-ui, mipit-observability
- Todos al mismo nivel de directorio

## Pasos

### 1. Levantar infraestructura
```bash
cd mipit-infra
bash scripts/up.sh
```

### 2. Verificar servicios
```bash
bash scripts/health-check.sh
```

Salida esperada:
```
✓ PostgreSQL    → localhost:5432
✓ RabbitMQ      → localhost:5672 (AMQP) / localhost:15672 (Management)
✓ Prometheus    → localhost:9090
✓ Grafana       → localhost:3000
✓ Jaeger        → localhost:16686
✓ Nginx         → localhost:443
✓ mipit-core    → localhost:8080
✓ adapter-pix   → connected to q.adapter.pix
✓ adapter-spei  → connected to q.adapter.spei
✓ mipit-ui      → localhost:443 (via Nginx)
```

### 3. Abrir UIs
- **MiPIT UI**: https://localhost
- **Grafana**: http://localhost:3000 (admin/mipit2026)
- **RabbitMQ**: http://localhost:15672 (mipit/mipit_secret)
- **Jaeger**: http://localhost:16686

### 4. Ejecutar transacción PIX → SPEI
1. Ir a UI → Simulación
2. Origen: PIX, Destino: SPEI
3. Llenar formulario con datos sintéticos
4. Click "Iniciar Transacción"
5. Observar timeline de estados

Datos sugeridos:
| Campo | Valor |
|-------|-------|
| Monto | 1500.00 |
| Moneda | BRL |
| Deudor alias | +5511999887766 |
| Deudor nombre | Maria Silva |
| Acreedor alias | 012180012345678901 |
| Acreedor nombre | Carlos Mejía |

### 5. Inspeccionar
- **Inspector**: Ver original / canónico / traducido (3 tabs en la UI)
- **Grafana**: Ver métricas en dashboard "MiPIT Overview"
  - Transacciones por estado
  - Latencia P50/P95/P99
  - Tasa de éxito/fallo
- **Jaeger**: Buscar por trace_id la traza completa
  - Verificar spans: API → validator → translator → router → publisher → adapter → ack

### 6. Ejecutar transacción inversa SPEI → PIX
- Repetir con origen SPEI, destino PIX

Datos sugeridos:
| Campo | Valor |
|-------|-------|
| Monto | 5000.00 |
| Moneda | MXN |
| Deudor alias | 012180098765432101 |
| Deudor nombre | Juan López |
| Acreedor alias | 12345678901 |
| Acreedor nombre | Ana Costa |

### 7. Probar idempotencia
- Repetir misma transacción con mismo Idempotency-Key
- Verificar que devuelve misma respuesta sin procesar de nuevo
- El estado debe mostrar `DUPLICATE` si la key ya existía con mismo payload

### 8. Probar fallo
- Esperar a que el mock rechace (~10% de las veces, configurable)
- Verificar estado `REJECTED` y `rail_ack` con error
- O detener un adaptador (`docker stop mipit-adapter-spei`) y enviar transacción para ver `FAILED`

### 9. Reset
```bash
bash scripts/reset.sh
```

Esto limpia: base de datos, colas RabbitMQ, métricas de Prometheus. Los dashboards de Grafana se mantienen.
