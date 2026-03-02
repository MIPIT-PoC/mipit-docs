# Runbook: Demo en 3 VMs

## Visión general

Despliegue distribuido en 3 máquinas virtuales para demostrar que los componentes
pueden ejecutarse en nodos separados, comunicándose vía red.

## Topología

```
┌─────────────────────────────────────┐
│            VM1: Core                │
│  - mipit-core                       │
│  - PostgreSQL                       │
│  - Nginx (reverse proxy)            │
│  - mipit-ui (static files)          │
│  IP: 192.168.1.10                   │
└─────────────────────────────────────┘
          │
          │ AMQP (5672) + HTTP (8080)
          │
┌─────────────────────────────────────┐
│       VM2: Messaging + Adapters     │
│  - RabbitMQ                         │
│  - mipit-adapter-pix                │
│  - mipit-adapter-spei               │
│  IP: 192.168.1.11                   │
└─────────────────────────────────────┘
          │
          │ OTLP (4317) + Prometheus scrape (9090)
          │
┌─────────────────────────────────────┐
│      VM3: Observability             │
│  - Prometheus                       │
│  - Grafana                          │
│  - Jaeger                           │
│  IP: 192.168.1.12                   │
└─────────────────────────────────────┘
```

## Pre-requisitos

- 3 VMs con Ubuntu 22.04+ o similar
- Docker Engine 26+ y Docker Compose en cada VM
- Red interna entre las 3 VMs (puertos abiertos: 5672, 15672, 8080, 443, 5432, 9090, 3000, 16686, 4317)
- Repos clonados en cada VM según su rol
- Certificados TLS generados (autofirmados para demo)

## VM1: Core

### Configuración

```bash
# Clonar repos necesarios
git clone https://github.com/MIPIT-PoC/mipit-infra.git
git clone https://github.com/MIPIT-PoC/mipit-core.git
git clone https://github.com/MIPIT-PoC/mipit-ui.git
```

### Variables de entorno

```bash
# .env para mipit-core
DATABASE_URL=postgres://mipit:mipit_secret@localhost:5432/mipit
RABBITMQ_URL=amqp://mipit:mipit_secret@192.168.1.11:5672
OTEL_EXPORTER_OTLP_ENDPOINT=http://192.168.1.12:4317
JWT_SECRET=mipit-poc-secret-2026
```

### Levantar servicios

```bash
# TODO: Ajustar docker-compose.vm1.yaml con override de IPs
docker compose -f docker-compose.vm1.yaml up -d
```

### Verificación

```bash
curl -k https://localhost/api/health
curl http://localhost:8080/health
```

## VM2: Messaging + Adapters

### Configuración

```bash
git clone https://github.com/MIPIT-PoC/mipit-infra.git
git clone https://github.com/MIPIT-PoC/mipit-adapter-pix.git
git clone https://github.com/MIPIT-PoC/mipit-adapter-spei.git
```

### Variables de entorno

```bash
# .env para adaptadores
RABBITMQ_URL=amqp://mipit:mipit_secret@localhost:5672
OTEL_EXPORTER_OTLP_ENDPOINT=http://192.168.1.12:4317
CORE_CALLBACK_URL=http://192.168.1.10:8080
```

### Levantar servicios

```bash
# TODO: Ajustar docker-compose.vm2.yaml
docker compose -f docker-compose.vm2.yaml up -d
```

### Verificación

```bash
curl http://localhost:15672/api/overview  # RabbitMQ management
# Verificar que las colas tienen consumers activos
```

## VM3: Observability

### Configuración

```bash
git clone https://github.com/MIPIT-PoC/mipit-observability.git
```

### Variables de entorno

```bash
# prometheus.yml: targets apuntando a VM1 y VM2
# - 192.168.1.10:8080 (core metrics)
# - 192.168.1.11:8081 (adapter-pix metrics)
# - 192.168.1.11:8082 (adapter-spei metrics)
```

### Levantar servicios

```bash
# TODO: Ajustar docker-compose.vm3.yaml
docker compose -f docker-compose.vm3.yaml up -d
```

### Verificación

```bash
curl http://localhost:9090/-/healthy   # Prometheus
curl http://localhost:3000/api/health  # Grafana
curl http://localhost:16686/           # Jaeger UI
```

## Ejecución de demo

Seguir los mismos pasos de [local-demo.md](local-demo.md), reemplazando `localhost` por las IPs correspondientes:

- **UI**: https://192.168.1.10
- **Grafana**: http://192.168.1.12:3000
- **RabbitMQ**: http://192.168.1.11:15672
- **Jaeger**: http://192.168.1.12:16686

## Troubleshooting

| Problema | Verificar |
|----------|-----------|
| Core no conecta a RabbitMQ | Firewall puerto 5672 entre VM1 y VM2 |
| Trazas no aparecen en Jaeger | Firewall puerto 4317 entre VM1/VM2 y VM3 |
| Prometheus sin targets | Verificar `prometheus.yml` con IPs correctas |
| UI no carga | Nginx corriendo en VM1, certificados TLS |
| Adaptadores sin consumer | RabbitMQ corriendo, colas creadas |
