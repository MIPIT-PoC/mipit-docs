# P08 — Security Hardening

**Wave**: 1 (foundation — paralelo)
**Repos afectados**: `mipit-core`, `mipit-infra`, `mipit-adapter-{pix,spei,breb}`, `mipit-ui`
**Branch**: `Auditoria-Claude`
**Estimación**: 2-3 días
**Riesgo**: Medio (cambios bien acotados; mostly subtractive)

---

## 1. Objetivo

Cerrar el delta entre "demo-grade" y "minimum security baseline defensible en una sustentación académica". No buscamos enterprise-grade — buscamos que un panel que vea el código no encuentre **vulnerabilidades obvias** ni **secrets comiteados**.

Highlights:
- JWT con algorithm pinning, iss/aud.
- `/auth/token` gated tras `NODE_ENV !== production`.
- CORS hard-coded origins (no `origin: true`).
- Eliminar middleware regex anti-SQL (es teatro + falsos positivos).
- `trustProxy` en Fastify para rate limiter correcto.
- Nginx security headers (HSTS, CSP, XCTO, X-Frame-Options, Referrer-Policy).
- nginx rate limit.
- nginx SSE-friendly location.
- Mover secrets fuera de `.env.example` (placeholders sin valor real).
- Auth en endpoints `/admin/*` de los mocks.
- npm audit fix vulnerabilities críticas.
- SSE auth via token-in-URL.
- ui-proxy admin endpoints gated.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| C38 | H | `/auth/token` sin auth → admin token disponible para cualquiera |
| C39 | H | JWT sin `algorithms: ['HS256']`, sin iss/aud |
| C40 | H | CORS `origin: true` |
| C41 | H | Middleware regex anti-SQL crea más problemas que resuelve |
| C42 | H | Rate limiter trust `x-forwarded-for` sin `trustProxy` |
| C44 | M | error-handler sin RFC 7807 (mejora opcional) |
| C46 | H | `/health` no probe DB/MQ |
| C47 | H | SSE `/events/payments` sin auth → PII leak |
| C48 | **C** | `ui-proxy.ts` expone admin endpoints adapter via token admin |
| C60 | **C** | 13 npm vulnerabilities (4 critical, 7 high) |
| D15 | H | Admin endpoints `/admin/*` mocks sin auth |
| E23 | H | RabbitMQ `default_pass=mipit_secret` plain text |
| E29 | H | Nginx sin security headers |
| E30 | H | Nginx sin rate limit |
| E31 | **C** | Nginx `proxy_buffering on` mata SSE en 60s |
| E36 | H | `JWT_SECRET` committed en core.env.example |
| E37 | H | `mipit_secret` reutilizado en 6 servicios |
| E38 | H | Grafana admin password en docker-compose |
| F3 | H | UI SSE no recibe JWT |

---

## 3. Out of scope

- **NO** se implementa mTLS internal (overkill PoC).
- **NO** se implementa HSM / KMS.
- **NO** se implementa rotation automática de secrets.
- **NO** se implementa RBAC fine-grained (mantiene single `admin` role).

---

## 4. Dependencias

- **Bloquea**: P11 (UI SSE auth).
- **Depende de**: ninguna; puede correr en paralelo desde Wave 1.

---

## 5. Tareas detalladas

### 5.1 JWT hardening

`mipit-core/src/api/server.ts:58`:

```ts
// ANTES
app.register(fastifyJwt, { secret: env.JWT_SECRET });

// DESPUÉS
app.register(fastifyJwt, {
  secret: env.JWT_SECRET,
  sign: {
    algorithm: 'HS256',
    iss: 'mipit-core',
    aud: 'mipit-ui',
    expiresIn: '1h', // shorter for prod-like
  },
  verify: {
    algorithms: ['HS256'],
    allowedIss: 'mipit-core',
    allowedAud: 'mipit-ui',
    maxAge: '24h',
  },
});
```

- [ ] Implement
- [ ] Update token-generation script (`scripts/generate-token.ts`) for tests

### 5.2 Gate `/auth/token` for non-production

`mipit-core/src/api/server.ts:85-91`:

```ts
if (env.NODE_ENV !== 'production') {
  app.get('/auth/token', async (_, reply) => {
    const token = app.jwt.sign({ sub: 'mipit-ui', role: 'admin' });
    return { token, expires_in: 3600 };
  });
} else {
  app.get('/auth/token', async (_, reply) => {
    reply.code(404);
    return { error: 'endpoint not available in production' };
  });
}
```

- [ ] Implement
- [ ] Document in OpenAPI: "endpoint only in non-prod; production uses OIDC"

### 5.3 CORS hard-coded origins

`mipit-core/src/api/server.ts:56`:

```ts
// ANTES
app.register(cors, { origin: true });

// DESPUÉS
const allowedOrigins = env.CORS_ALLOWED_ORIGINS?.split(',').map(s => s.trim()) ?? ['http://localhost:3000', 'http://localhost:3001'];
app.register(cors, {
  origin: (origin, cb) => {
    if (!origin) return cb(null, true); // same-origin curl, server-to-server
    if (allowedOrigins.includes(origin)) return cb(null, true);
    cb(new Error('CORS: origin not allowed'), false);
  },
  credentials: false,
  methods: ['GET','POST','PUT','DELETE','OPTIONS'],
});
```

- [ ] Implement
- [ ] Add env var `CORS_ALLOWED_ORIGINS` to env.ts schema
- [ ] Default empty → fail-closed in prod

### 5.4 Remove regex anti-SQL middleware

`mipit-core/src/api/middleware/sanitize.ts` y `mipit-core/src/api/server.ts:72`:

- [ ] **Borrar** la regex anti-SQL (líneas 17-24)
- [ ] **Mantener** la regex anti-prototype-pollution (`__proto__`, `constructor`, `prototype`)
- [ ] **Mantener** el cap de 10KB y array length 1000
- [ ] Update test: `sanitize.test.ts` debe permitir cadenas como "Please update the form"

### 5.5 `trustProxy` en Fastify

`mipit-core/src/api/server.ts:50-54`:

```ts
const app = fastify({
  logger: false,
  trustProxy: true, // honors X-Forwarded-For from upstream proxy (nginx)
});
```

- [ ] Implement
- [ ] `rate-limit.ts` ya usa `req.ip` — ahora será el real remote IP

### 5.6 Nginx security headers + rate limit + SSE

`mipit-infra/nginx/nginx.conf`:

```nginx
worker_processes auto;
events { worker_connections 1024; }

http {
  # Rate limit zone — 10 req/s burst 20
  limit_req_zone $binary_remote_addr zone=mipit_api:10m rate=10r/s;

  upstream core_backend { server core:8080; }
  upstream ui_frontend  { server ui:3000; }

  # HTTP → HTTPS redirect
  server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl http2;
    ssl_certificate     /etc/nginx/certs/mipit.crt;
    ssl_certificate_key /etc/nginx/certs/mipit.key;
    ssl_protocols       TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache   shared:MozSSL:10m;
    ssl_session_tickets off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://10.43.101.28; frame-ancestors 'none';" always;

    client_max_body_size 1m;
    proxy_read_timeout 30s;
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;

    # SSE-friendly location (events streaming)
    location /api/events/ {
      proxy_pass http://core_backend/events/;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;

      # SSE essentials
      proxy_buffering off;
      proxy_cache off;
      proxy_set_header Connection '';
      chunked_transfer_encoding off;
      proxy_read_timeout 24h; # long-lived
    }

    # API
    location /api/ {
      limit_req zone=mipit_api burst=20 nodelay;
      proxy_pass http://core_backend/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    }

    # UI
    location / {
      proxy_pass http://ui_frontend;
      proxy_set_header Host $host;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
  }
}
```

- [ ] Apply
- [ ] Test: `curl -I https://10.43.101.28/` should return all security headers
- [ ] Test: SSE stream survives 60s (was killed before)

### 5.7 Move secrets out of committed env.example

Approach: `.env.example` tiene **placeholders** sin valor real. `.env` (gitignored, no committed) tiene los valores.

`mipit-infra/env/core.env.example`:

```bash
NODE_ENV=development
PORT=8080
DATABASE_URL=postgresql://USER:PASSWORD@postgres:5432/mipit
RABBITMQ_URL=amqp://USER:PASSWORD@rabbitmq:5672/mipit
JWT_SECRET=<generate-with-openssl-rand-base64-32>
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_SERVICE_NAME=mipit-core
LOG_LEVEL=info
HTTP_RATE_LIMIT_MAX=200
HTTP_RATE_LIMIT_WINDOW_MS=60000
CORS_ALLOWED_ORIGINS=http://localhost:3000,https://10.43.101.28
```

- [ ] Replace literal `mipit_secret`, `mipit-poc-jwt-secret-change-in-production` with placeholders
- [ ] Add `README.md` setup section: "Copy .env.example to .env; replace placeholders. Generate JWT_SECRET with `openssl rand -base64 32`."
- [ ] Equivalent for `postgres.env.example`, `rabbitmq.env.example`, `ui.env.example`, `*.env.example` per rail
- [ ] `scripts/up.sh` ya copia example→env si missing; ahora también valida que no haya placeholders en `.env`

`mipit-infra/scripts/setup-secrets.sh` (nuevo):

```bash
#!/bin/bash
set -e

ENV_DIR="env"
EXAMPLES=$(ls $ENV_DIR/*.env.example)

for example in $EXAMPLES; do
  env_file="${example%.example}"
  if [ ! -f "$env_file" ]; then
    cp "$example" "$env_file"
  fi
  # Replace placeholders with random secrets
  if grep -q '<generate-with-openssl' "$env_file"; then
    JWT_SECRET=$(openssl rand -base64 32)
    sed -i "s|<generate-with-openssl-rand-base64-32>|$JWT_SECRET|g" "$env_file"
  fi
done

echo "Secrets generated. Verify with: grep -r '<' env/*.env"
```

- [ ] Crear script
- [ ] `up.sh` lo invoca primero

### 5.8 Grafana admin password from env

`mipit-infra/compose/docker-compose.yml:182`:

```yaml
# ANTES
GF_SECURITY_ADMIN_PASSWORD=mipit2026

# DESPUÉS
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD env required}
```

- [ ] Implement
- [ ] Add `GRAFANA_ADMIN_PASSWORD=` to `.env` template
- [ ] Document in README

### 5.9 RabbitMQ password from env

`mipit-infra/rabbitmq/rabbitmq.conf`:

```
loopback_users.guest = false
default_vhost = mipit
default_user = mipit
# default_pass = mipit_secret  # REMOVED
```

`mipit-infra/compose/docker-compose.yml`:

```yaml
rabbitmq:
  image: rabbitmq:3.13-management-alpine
  environment:
    RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER:?required}
    RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD:?required}
    RABBITMQ_DEFAULT_VHOST: mipit
```

- [ ] Update both files
- [ ] Set env vars from env files

### 5.10 Auth in mock admin endpoints

The 3 adapters expose `POST /admin/{reject-next,timeout-next,config,reset}` sin auth.

`mipit-adapter-pix/src/pix/admin-routes.ts`:

```ts
function requireAdminToken(req, res, next) {
  const token = req.headers['x-admin-token'];
  if (token !== process.env.MOCK_ADMIN_TOKEN) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  next();
}

router.use(requireAdminToken);

router.post('/admin/reject-next', /* ... */);
// etc.
```

- [ ] Implement in all 3 adapters
- [ ] Env var `MOCK_ADMIN_TOKEN` (different per rail OR same for simplicity)
- [ ] UI Simulator page sends `X-Admin-Token` header (coord P11)
- [ ] `ui-proxy.ts` en core injects the header from server-side env (not exposed to browser)

### 5.11 SSE auth

Multiple approaches:
- **Option A**: token in query string `GET /events/payments?token=...` (simple, works with EventSource)
- **Option B**: SSE behind cookie auth (more secure but requires CORS rework)

Recomendación PoC: **Opción A** con caveats documentados.

`mipit-core/src/api/routes/sse.ts`:

```ts
app.get('/events/payments', async (req, reply) => {
  const token = req.query.token as string | undefined;
  if (!token) {
    reply.code(401).send({ error: 'token required' });
    return;
  }
  try {
    await app.jwt.verify(token);
  } catch (err) {
    reply.code(401).send({ error: 'invalid token' });
    return;
  }
  // ... existing SSE logic ...
});
```

UI side:
```ts
// mipit-ui/src/hooks/use-sse.ts
const token = await getToken();
const sse = new EventSource(`/api/events/payments?token=${encodeURIComponent(token)}`);
```

- [ ] Implement
- [ ] Document: "Token-in-URL is acceptable for PoC SSE. For prod consider cookie-based auth."

### 5.12 ui-proxy admin endpoints behind admin role

`mipit-core/src/api/routes/ui-proxy.ts`. Cada admin endpoint debe verificar que `request.user.role === 'admin'`:

```ts
function requireAdmin(req, reply, done) {
  if (req.user?.role !== 'admin') {
    reply.code(403).send({ error: 'forbidden' });
    return done(new Error('forbidden'));
  }
  done();
}

app.post('/mocks/:rail/admin/reject-next', { preHandler: requireAdmin }, async (req, reply) => {
  // proxy to adapter with X-Admin-Token header
});
```

- [ ] Implement
- [ ] All `/mocks/*/admin/*` routes have `preHandler: requireAdmin`

### 5.13 Health endpoint deep probe

`mipit-core/src/api/routes/health.ts`:

```ts
app.get('/health', async (_, reply) => {
  const checks = {
    db: await checkDb(),
    rabbitmq: await checkRabbitMQ(),
    timestamp: new Date().toISOString(),
  };

  const ok = Object.values(checks).every(v => v === 'ok' || typeof v === 'string');
  reply.code(ok ? 200 : 503);
  return { status: ok ? 'ok' : 'degraded', checks };
});

async function checkDb(): Promise<'ok' | string> {
  try {
    await db.query('SELECT 1');
    return 'ok';
  } catch (err) {
    return `error: ${String(err)}`;
  }
}

async function checkRabbitMQ(): Promise<'ok' | string> {
  try {
    if (!channel) return 'no_channel';
    await channel.checkExchange('mipit.payments');
    return 'ok';
  } catch (err) {
    return `error: ${String(err)}`;
  }
}
```

- [ ] Implement
- [ ] K8s readiness: separate `/health/live` (always 200 if process up) and `/health/ready` (200 only when DB + MQ verde)

### 5.14 npm audit fix

`mipit-core`:

```bash
npm audit
npm audit fix
# For semver-major upgrades:
npm install @fastify/jwt@latest
npm install @opentelemetry/auto-instrumentations-node@latest
npm install @opentelemetry/sdk-node@latest
npm install @opentelemetry/exporter-prometheus@latest
```

- [ ] Run en mipit-core, mipit-testkit, mipit-ui, los 3 adapters, mipit-observability if any
- [ ] Verify tests still pass
- [ ] Commit `package-lock.json` updates

Remove unused dependencies:
- `mipit-core`: `jsonwebtoken` (no usado; `@fastify/jwt` ya incluye `fast-jwt`)
- `mipit-core`: `@opentelemetry/exporter-metrics-otlp-http` (no import)

```bash
npm uninstall jsonwebtoken @opentelemetry/exporter-metrics-otlp-http
```

### 5.15 Adapter health endpoint deep probe (similar)

`mipit-adapter-pix/src/health-server.ts`:

```ts
app.get('/health', async (req, res) => {
  const checks = {
    rabbitmq: channel?.connection?.connection?.stream?.writable ? 'ok' : 'down',
    mock_server: mockServerReady ? 'ok' : 'starting',
    timestamp: new Date().toISOString(),
  };
  const ok = checks.rabbitmq === 'ok';
  res.status(ok ? 200 : 503).json({ status: ok ? 'ok' : 'degraded', adapter: 'pix', checks });
});
```

- [ ] Implement in 3 adapters
- [ ] Update Prometheus uptime alert to use real status

---

## 6. Acceptance criteria

- [ ] JWT pinned to HS256 with iss/aud verified
- [ ] `/auth/token` 404 en production
- [ ] CORS hard-coded; `*` origins rejected
- [ ] Sanitize regex anti-SQL eliminada; tests no rechazan strings legítimos
- [ ] `trustProxy: true`; rate limiter usa real client IP
- [ ] Nginx security headers presentes (verify via `curl -I`)
- [ ] Nginx rate limit 10r/s con burst 20
- [ ] SSE stream `/api/events/*` no muere por buffering
- [ ] `.env.example` con placeholders no valores reales
- [ ] `setup-secrets.sh` genera secretos random
- [ ] RabbitMQ creds del env vars (no hard-coded en conf)
- [ ] Grafana admin password del env
- [ ] Admin endpoints adapter requieren X-Admin-Token
- [ ] SSE endpoint requiere token (query string)
- [ ] ui-proxy admin endpoints requieren role admin
- [ ] `/health` probe real (DB + MQ); fail con 503 si degraded
- [ ] `npm audit`: 0 critical, 0 high (sólo low/info acceptable)
- [ ] `jsonwebtoken` y `@opentelemetry/exporter-metrics-otlp-http` removidos

---

## 7. Testing plan

### Manual / scripts
- `scripts/security-test.sh` (nuevo): curl tests para cada hardening point
  - `curl https://10.43.101.28/api/auth/token` con `NODE_ENV=production` → 404
  - `curl https://10.43.101.28/health` → JSON con checks
  - `curl -X POST https://10.43.101.28/api/mocks/pix/admin/reject-next` sin token → 401
  - `curl https://10.43.101.28/api/events/payments` sin `?token=` → 401
- `curl -I https://10.43.101.28/` → verify all security headers
- `npm audit --audit-level=high` → 0

### Unit
- `auth.test.ts` — JWT verify alg/iss/aud
- `cors.test.ts` — disallowed origin blocked
- `sanitize.test.ts` — legitimate strings allowed
- `rate-limit.test.ts` — uses real IP under trustProxy

### Integration
- `mipit-testkit/tests/security/security-headers.test.ts`
- `mipit-testkit/tests/security/auth-token-prod-gated.test.ts`

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Rate limit 10r/s rompe load test | E2E load test corre con `?adminBypass=...` o ENV `NGINX_RATE_LIMIT_DISABLE` |
| CSP demasiado estricto rompe UI | Testear en local con DevTools console; relax `unsafe-inline` si Next.js lo necesita |
| `trustProxy: true` mal config introduce IP spoofing | Solo confía X-Forwarded-* si viene de nginx (internal docker network) |
| `npm audit fix --force` puede romper | Hacer semver-major upgrades uno a la vez; correr tests entre cada uno |
| Removing `jsonwebtoken` rompe scripts custom | Buscar imports antes de borrar |

---

## 9. Commits sugeridos

1. `feat(security): JWT pinned to HS256 with iss/aud verification`
2. `feat(security): gate /auth/token behind NODE_ENV !== production`
3. `feat(security): CORS hard-coded allowed origins (env-driven)`
4. `refactor(security): remove regex anti-SQL middleware (false positives)`
5. `fix(security): Fastify trustProxy for real client IP`
6. `feat(nginx): security headers HSTS/CSP/XCTO/X-Frame-Options/Referrer-Policy`
7. `feat(nginx): rate limit 10r/s with burst; SSE-friendly location`
8. `chore(secrets): move literal secrets to .env.example placeholders`
9. `feat(secrets): setup-secrets.sh generates random JWT/passwords`
10. `feat(security): RabbitMQ creds from env (not hard-coded in conf)`
11. `feat(security): Grafana admin password from env`
12. `feat(security): admin endpoints in adapters require X-Admin-Token`
13. `feat(security): SSE endpoint requires JWT in query string`
14. `feat(security): ui-proxy admin endpoints behind role=admin`
15. `fix(health): deep probe DB and RabbitMQ; return 503 on degraded`
16. `feat(health): adapter deep probe with rabbitmq + mock_server checks`
17. `chore(deps): npm audit fix; upgrade @fastify/jwt, OTel SDK, exporters`
18. `chore(deps): remove unused jsonwebtoken and metrics-otlp-http`

---

## 10. Notas para el dev

- **JWT `algorithms: ['HS256']` pin** es la línea más importante. Sin ella, un atacante puede usar `alg: none` (algunas libs vulnerables) o downgrade.
- **CORS**: para PoC, `CORS_ALLOWED_ORIGINS=http://localhost:3000,https://10.43.101.28` cubre dev y VM.
- **Nginx CSP**: el `unsafe-inline` para scripts/styles es necesario por Next.js. Documented trade-off.
- **`MOCK_ADMIN_TOKEN`**: puede ser el mismo per los 3 adapters (simplicity) o diferentes (per-rail isolation). Decisión: mismo per simplicity; rotar manualmente.
- **SSE token-in-URL**: el token aparece en server logs (URL). Aceptable PoC pero document caveat.
- **`npm audit` 0 critical/high** es realista para deps modernos. Si algún OTel sub-dep tiene RFC, documentar como aceptado.
