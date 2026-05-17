# P09 — DB Schema Hardening

**Wave**: 1 (foundation — bloquea P01/P02/P03/P04/P05/P06)
**Repos afectados**: `mipit-infra`
**Branch**: `Auditoria-Claude`
**Estimación**: 1-2 días
**Riesgo**: Medio (cambios SQL pueden romper datos existentes; PoC tolera reset)

---

## 1. Objetivo

Llevar el schema PostgreSQL del nivel "TEXT libre everywhere" al nivel "ISO 20022 enforced at the DB layer". Concretamente:

1. **CHECK constraints** en `status`, `origin_rail`, `destination_rail`, `currency`, `country`, `amount > 0`.
2. **Agregar columnas ISO 20022**: `uetr UUID UNIQUE`, `end_to_end_id VARCHAR(35)`, `charge_bearer CHAR(4)`, `instructed_amount NUMERIC(18,5)`, `settlement_amount NUMERIC(18,5)`, `instructed_currency CHAR(3)`, `settlement_currency CHAR(3)`, `exchange_rate NUMERIC(18,8)`, `interbank_settlement_date DATE`.
3. **Aplicar `005_resilience.sql`** que actualmente solo está en `migrations/` (nunca corre).
4. **Migration runner**: agregar mechanism que aplique `migrations/*.sql` (no solo `init/`).
5. **`updated_at` trigger** para auto-update.
6. **Quorum queues** en RabbitMQ (config `definitions.json`).
7. **TTL/max-length** en queues.
8. **DLX en `payments.ack`**.
9. **Sweeper** para `idempotency_keys` expirados.

---

## 2. Findings que cierra

| ID | Severidad | Resumen |
|---|---|---|
| E8 | H | Sin CHECK constraints en payments |
| E9 | H | Sin columnas ISO 20022 (`end_to_end_id`, `uetr`, etc.) |
| E10 | H | `amount > 0` no validado |
| E11 | M | `currency DEFAULT 'USD'` en PoC LATAM |
| E12 | M | `reference DEFAULT 'MIPIT-POC'` sentinel |
| E13 | M | `updated_at` sin trigger |
| E14 | M | `payment_id TEXT` sin VARCHAR(64) |
| E15 | L | Audit FK sin ON DELETE clause |
| E16 | M | `event_type TEXT` sin CHECK enum |
| E17 | M | `004_webhooks.sql` duplicado en init + migrations |
| E18 | H | `005_resilience.sql` solo en migrations (no aplicado en fresh boot) |
| E20 | L | `route_rules.fallback_unavailable` overloads destination_rail |
| E22 | L | Sin CHECK sobre `rail` en mapping_table |
| E23 | H | RabbitMQ secrets en config (cubierto por P08) |
| E24 | H | `payments.ack` queue sin DLX (también en P06) |
| E25 | M | Todas queues classic, no quorum |
| E26 | M | Sin TTL/max-length |
| E27 | M | Sin alternate exchange (typo silencioso) |

---

## 3. Out of scope

- **NO** se cambia engine PostgreSQL.
- **NO** se introduce ORM (sigue pg raw + queries/index.ts).
- **NO** se hace event-sourcing total.

---

## 4. Dependencias

- **Bloquea**: P01 (canónico necesita columnas ISO), P05 (FX needs instructed/settlement columns), P06 (outbox table).
- **Depende de**: ninguna; primer plan en Wave 1.

---

## 5. Tareas detalladas

### 5.1 Schema hardening — payments

`mipit-infra/db/migrations/008_payments_constraints_and_iso.sql` (nuevo):

```sql
-- Enforce status enum
ALTER TABLE payments
  ADD CONSTRAINT payments_status_check
  CHECK (status IN (
    'RECEIVED', 'VALIDATED', 'CANONICALIZED', 'NORMALIZED', 'ROUTED',
    'QUEUED', 'SENT_TO_DESTINATION', 'ACKED_BY_RAIL', 'COMPLETED',
    'FAILED', 'REJECTED', 'DUPLICATE', 'COMPENSATING', 'COMPENSATED',
    'DEAD_LETTER'
  ));

-- Enforce rail enum
ALTER TABLE payments
  ADD CONSTRAINT payments_origin_rail_check
  CHECK (origin_rail IN ('PIX', 'SPEI', 'BRE_B', 'SWIFT_MT103', 'ISO20022_MX', 'ACH_NACHA', 'FEDNOW'));

ALTER TABLE payments
  ADD CONSTRAINT payments_destination_rail_check
  CHECK (destination_rail IS NULL OR destination_rail IN ('PIX', 'SPEI', 'BRE_B', 'SWIFT_MT103', 'ISO20022_MX', 'ACH_NACHA', 'FEDNOW'));

-- Enforce currency ISO 4217 form
ALTER TABLE payments
  ADD CONSTRAINT payments_currency_iso4217
  CHECK (currency ~ '^[A-Z]{3}$');

-- Enforce amount > 0
ALTER TABLE payments
  ADD CONSTRAINT payments_amount_positive
  CHECK (amount > 0);

-- Enforce country ISO 3166 alpha-2 if set
ALTER TABLE payments
  ADD CONSTRAINT payments_debtor_country_iso
  CHECK (debtor_country IS NULL OR debtor_country ~ '^[A-Z]{2}$');

ALTER TABLE payments
  ADD CONSTRAINT payments_creditor_country_iso
  CHECK (creditor_country IS NULL OR creditor_country ~ '^[A-Z]{2}$');

-- Change defaults — remove sentinel values
ALTER TABLE payments
  ALTER COLUMN currency DROP DEFAULT,
  ALTER COLUMN reference DROP DEFAULT;

-- Tighten payment_id
ALTER TABLE payments
  ALTER COLUMN payment_id TYPE VARCHAR(64);

ALTER TABLE payments
  ADD CONSTRAINT payments_payment_id_format
  CHECK (payment_id ~ '^PMT-[A-Z0-9]{10,40}$');

-- ISO 20022 columns (P01 + P05)
ALTER TABLE payments
  ADD COLUMN uetr UUID UNIQUE,
  ADD COLUMN end_to_end_id VARCHAR(35),
  ADD COLUMN instr_id VARCHAR(35),
  ADD COLUMN tx_id VARCHAR(35),
  ADD COLUMN charge_bearer CHAR(4)
    CHECK (charge_bearer IS NULL OR charge_bearer IN ('DEBT','CRED','SHAR','SLEV')),
  ADD COLUMN interbank_settlement_date DATE,
  ADD COLUMN instructed_amount NUMERIC(18,5),
  ADD COLUMN instructed_currency CHAR(3)
    CHECK (instructed_currency IS NULL OR instructed_currency ~ '^[A-Z]{3}$'),
  ADD COLUMN settlement_amount NUMERIC(18,5),
  ADD COLUMN settlement_currency CHAR(3)
    CHECK (settlement_currency IS NULL OR settlement_currency ~ '^[A-Z]{3}$'),
  ADD COLUMN exchange_rate NUMERIC(18,8),
  ADD COLUMN exchange_rate_source VARCHAR(50),
  ADD COLUMN origin_ispb VARCHAR(8),
  ADD COLUMN origin_institution_code VARCHAR(8),
  ADD COLUMN destination_institution_code VARCHAR(8);

CREATE INDEX idx_payments_uetr ON payments(uetr) WHERE uetr IS NOT NULL;
CREATE INDEX idx_payments_end_to_end_id ON payments(end_to_end_id) WHERE end_to_end_id IS NOT NULL;
CREATE INDEX idx_payments_status_created ON payments(status, created_at);
```

- [ ] Crear archivo
- [ ] Aplicar a fresh DB; verificar todas las constraints
- [ ] Para DB existente: P09 corre `truncate` o `DROP TABLE payments CASCADE` y recrear (PoC tolerable)

### 5.2 Audit table

`mipit-infra/db/migrations/009_audit_events_constraints.sql`:

```sql
ALTER TABLE audit_events
  ADD CONSTRAINT audit_events_event_type_check
  CHECK (event_type IN (
    'PAYMENT_RECEIVED', 'PAYMENT_VALIDATED', 'CANONICAL_UPDATED',
    'ROUTE_DECISION', 'TRANSLATED', 'PUBLISHED_TO_QUEUE',
    'ACK_RECEIVED', 'PIPELINE_ERROR', 'STATUS_CHANGE',
    'COMPENSATION_STARTED', 'COMPENSATION_COMPLETED', 'COMPENSATION_REVERSAL_REQUIRED',
    'WEBHOOK_DELIVERED', 'WEBHOOK_FAILED',
    'RECONCILIATION_REPORT',
    'DEAD_LETTER'
  ));

-- Make FK explicit
ALTER TABLE audit_events
  DROP CONSTRAINT audit_events_payment_id_fkey;
ALTER TABLE audit_events
  ADD CONSTRAINT audit_events_payment_id_fkey
  FOREIGN KEY (payment_id) REFERENCES payments(payment_id)
  ON DELETE RESTRICT; -- prevent payment deletion if audit exists
```

### 5.3 mapping_table constraints

```sql
ALTER TABLE mapping_table
  ADD CONSTRAINT mapping_table_rail_check
  CHECK (rail IN ('PIX', 'SPEI', 'BRE_B', 'SWIFT_MT103', 'ISO20022_MX', 'ACH_NACHA', 'FEDNOW'));

ALTER TABLE mapping_table
  ADD CONSTRAINT mapping_table_transformation_check
  CHECK (transformation IN (
    'copy', 'parse_decimal', 'truncate_35', 'truncate_140',
    'prefix_PIX', 'prefix_SPEI', 'prefix_BREB',
    'strip_prefix', 'convert_to_BRL', 'convert_to_MXN', 'convert_to_COP',
    'set_BRL', 'set_MXN', 'set_COP', 'map_status', 'ignore',
    'regenerate_if_invalid', 'force_COP', 'cop_integer_or_2dec',
    'route_by_format'
  ));
```

### 5.4 route_rules cleanup

```sql
-- Add a 'action' column instead of overloading destination_rail
ALTER TABLE route_rules
  ADD COLUMN action VARCHAR(20) NOT NULL DEFAULT 'ROUTE'
  CHECK (action IN ('ROUTE', 'REJECT', 'COMPENSATE'));

-- Migrate existing fallback_unavailable
UPDATE route_rules
  SET action = 'REJECT', destination_rail = NULL
  WHERE rule_name = 'fallback_unavailable' AND destination_rail = 'FAILED';

-- Tighten destination_rail
ALTER TABLE route_rules
  ADD CONSTRAINT route_rules_dest_rail
  CHECK (
    (action = 'ROUTE' AND destination_rail IN ('PIX','SPEI','BRE_B','SWIFT_MT103','ISO20022_MX','ACH_NACHA','FEDNOW'))
    OR (action != 'ROUTE')
  );

-- Updated_at on rules
ALTER TABLE route_rules
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
```

### 5.5 `updated_at` trigger

`mipit-infra/db/migrations/010_updated_at_trigger.sql`:

```sql
CREATE OR REPLACE FUNCTION update_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS payments_updated_at ON payments;
CREATE TRIGGER payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS route_rules_updated_at ON route_rules;
CREATE TRIGGER route_rules_updated_at
  BEFORE UPDATE ON route_rules
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
```

### 5.6 Idempotency sweeper

`mipit-infra/db/migrations/011_idempotency_sweeper.sql`:

```sql
-- Function to delete expired keys
CREATE OR REPLACE FUNCTION sweep_expired_idempotency_keys() RETURNS INTEGER AS $$
DECLARE
  deleted INT;
BEGIN
  DELETE FROM idempotency_keys WHERE expires_at < NOW();
  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$ LANGUAGE plpgsql;
```

Schedule via core code (setInterval cada 1h) — coord P06.

### 5.7 Outbox table (coord P06)

Cubierto en P06. Aquí solo confirmamos que P09 incluye la migration `007_outbox.sql`.

### 5.8 Reconciliation reports table (coord P06)

`mipit-infra/db/migrations/012_reconciliation_reports.sql`:

```sql
CREATE TABLE reconciliation_reports (
  id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  run_started_at  TIMESTAMPTZ NOT NULL,
  run_ended_at    TIMESTAMPTZ NOT NULL,
  payments_scanned INT NOT NULL,
  anomalies_found INT NOT NULL,
  report          JSONB NOT NULL,
  webhook_fired   BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_recon_started ON reconciliation_reports(run_started_at DESC);
```

### 5.9 Migration runner

**Decisión**: usar [`node-pg-migrate`](https://github.com/salsita/node-pg-migrate) OR un script custom.

**Approach simple (custom)**: `mipit-infra/scripts/migrate.sh`:

```bash
#!/bin/bash
set -e

DB_URL=${DATABASE_URL:-postgresql://mipit:mipit_secret@localhost:5433/mipit}
MIGRATIONS_DIR="$(dirname "$0")/../db/migrations"

# Ensure schema_migrations table
docker exec mipit-postgres psql -U mipit -d mipit -c "
CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"

for file in $(ls $MIGRATIONS_DIR/*.sql | sort); do
  version=$(basename $file .sql)
  applied=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc "SELECT 1 FROM schema_migrations WHERE version='$version'")
  if [ -z "$applied" ]; then
    echo "Applying $version..."
    docker exec -i mipit-postgres psql -U mipit -d mipit < $file
    docker exec mipit-postgres psql -U mipit -d mipit -c "INSERT INTO schema_migrations(version) VALUES ('$version')"
  fi
done

echo "Migrations up to date."
```

- [ ] Crear script
- [ ] `scripts/up.sh` lo invoca DESPUÉS de levantar postgres healthy
- [ ] Verify: aplicar a fresh VM aplica TODO (`004` + `005` + `006` + `007` + ...)

### 5.10 RabbitMQ — quorum queues + DLX en ack + TTL + alt-exchange

`mipit-infra/rabbitmq/definitions.json`:

```json
{
  "rabbit_version": "3.13.0",
  "vhosts": [{"name": "mipit"}],
  "exchanges": [
    {"name": "mipit.payments", "vhost": "mipit", "type": "topic", "durable": true, "auto_delete": false, "arguments": {"alternate-exchange": "mipit.unrouted"}},
    {"name": "mipit.dlx", "vhost": "mipit", "type": "topic", "durable": true, "auto_delete": false},
    {"name": "mipit.unrouted", "vhost": "mipit", "type": "fanout", "durable": true, "auto_delete": false}
  ],
  "queues": [
    {
      "name": "payments.route.pix", "vhost": "mipit", "durable": true,
      "arguments": {
        "x-queue-type": "quorum",
        "x-dead-letter-exchange": "mipit.dlx",
        "x-dead-letter-routing-key": "dlq.pix",
        "x-message-ttl": 3600000,
        "x-max-length": 100000
      }
    },
    {
      "name": "payments.route.spei", "vhost": "mipit", "durable": true,
      "arguments": {
        "x-queue-type": "quorum",
        "x-dead-letter-exchange": "mipit.dlx",
        "x-dead-letter-routing-key": "dlq.spei",
        "x-message-ttl": 3600000,
        "x-max-length": 100000
      }
    },
    {
      "name": "payments.route.breb", "vhost": "mipit", "durable": true,
      "arguments": {
        "x-queue-type": "quorum",
        "x-dead-letter-exchange": "mipit.dlx",
        "x-dead-letter-routing-key": "dlq.breb",
        "x-message-ttl": 3600000,
        "x-max-length": 100000
      }
    },
    {
      "name": "payments.ack", "vhost": "mipit", "durable": true,
      "arguments": {
        "x-queue-type": "quorum",
        "x-dead-letter-exchange": "mipit.dlx",
        "x-dead-letter-routing-key": "dlq.ack",
        "x-message-ttl": 3600000
      }
    },
    {"name": "dlq.pix", "vhost": "mipit", "durable": true, "arguments": {"x-queue-type": "quorum"}},
    {"name": "dlq.spei", "vhost": "mipit", "durable": true, "arguments": {"x-queue-type": "quorum"}},
    {"name": "dlq.breb", "vhost": "mipit", "durable": true, "arguments": {"x-queue-type": "quorum"}},
    {"name": "dlq.ack", "vhost": "mipit", "durable": true, "arguments": {"x-queue-type": "quorum"}},
    {"name": "unrouted", "vhost": "mipit", "durable": true, "arguments": {"x-queue-type": "quorum"}}
  ],
  "bindings": [
    {"source": "mipit.payments", "vhost": "mipit", "destination": "payments.route.pix", "destination_type": "queue", "routing_key": "route.pix"},
    {"source": "mipit.payments", "vhost": "mipit", "destination": "payments.route.spei", "destination_type": "queue", "routing_key": "route.spei"},
    {"source": "mipit.payments", "vhost": "mipit", "destination": "payments.route.breb", "destination_type": "queue", "routing_key": "route.breb"},
    {"source": "mipit.payments", "vhost": "mipit", "destination": "payments.ack", "destination_type": "queue", "routing_key": "ack.#"},
    {"source": "mipit.dlx", "vhost": "mipit", "destination": "dlq.pix", "destination_type": "queue", "routing_key": "dlq.pix"},
    {"source": "mipit.dlx", "vhost": "mipit", "destination": "dlq.spei", "destination_type": "queue", "routing_key": "dlq.spei"},
    {"source": "mipit.dlx", "vhost": "mipit", "destination": "dlq.breb", "destination_type": "queue", "routing_key": "dlq.breb"},
    {"source": "mipit.dlx", "vhost": "mipit", "destination": "dlq.ack", "destination_type": "queue", "routing_key": "dlq.ack"},
    {"source": "mipit.unrouted", "vhost": "mipit", "destination": "unrouted", "destination_type": "queue", "routing_key": ""}
  ]
}
```

- [ ] Apply
- [ ] Apply requires queue recreation — drop existing queues first (PoC)
- [ ] Test: poner mensaje en queue, verify quorum semantics (multi-broker no aplica en single node, pero `x-queue-type` queda set)
- [ ] Test: publish a routing key inexistente → mensaje cae a `unrouted`

### 5.11 RabbitMQ — vm_memory_high_watermark

`mipit-infra/rabbitmq/rabbitmq.conf`:

```
loopback_users.guest = false
default_vhost = mipit
default_user = mipit
# default_pass removed (P08 — comes from env)
vm_memory_high_watermark.relative = 0.6
disk_free_limit.absolute = 1GB
```

### 5.12 Eliminar duplicate `004_webhooks.sql`

- [ ] Delete `mipit-infra/db/init/004_webhooks.sql` (canónico es `migrations/004_webhooks.sql`)
- [ ] El migration runner aplicará `004` desde `migrations/`

---

## 6. Acceptance criteria

- [ ] `payments` table tiene CHECK constraints en status, rails, currency, country, amount
- [ ] `payments` tiene columnas: uetr, end_to_end_id, instr_id, tx_id, charge_bearer, interbank_settlement_date, instructed_amount/currency, settlement_amount/currency, exchange_rate, origin_ispb, *_institution_code
- [ ] `audit_events.event_type` CHECK constraint
- [ ] `mapping_table.{rail, transformation}` CHECK constraints
- [ ] `route_rules` action column con CHECK
- [ ] `updated_at` trigger funciona en payments y route_rules
- [ ] Sweeper function `sweep_expired_idempotency_keys()` existe
- [ ] Migration runner script aplica TODAS las migraciones; fresh DB en VM nueva tiene TODO
- [ ] `schema_migrations` table tracks aplicados
- [ ] RabbitMQ queues son `x-queue-type=quorum`
- [ ] `payments.ack` tiene DLX
- [ ] Alternate exchange `mipit.unrouted` recibe mensajes con routing key sin binding
- [ ] TTL 1h en route queues
- [ ] Max length 100k en route queues
- [ ] `init/004_webhooks.sql` borrado
- [ ] Tests integration: insert con `status='GIBBERISH'` → rejected
- [ ] Tests integration: insert con `amount=-1` → rejected
- [ ] Tests integration: insert con `currency='USDX'` → rejected
- [ ] Tests integration: UPDATE en payments dispara `updated_at`

---

## 7. Testing plan

### Migration test
- `mipit-infra/scripts/test-migration.sh`: levanta postgres clean container, corre migrate.sh, verifica todas las tablas presentes
- Drop database, recreate, run all migrations, verify schema

### Constraint tests
- `mipit-testkit/tests/integration/db-constraints.test.ts`:
  - POST con status inválido → 500 (CHECK violation)
  - POST con currency `xyz` → 500
  - INSERT directo amount=0 → fails
  - INSERT audit_event con event_type random → fails

### RabbitMQ
- Manual verify: `rabbitmqadmin -V mipit declare queue name=test arguments='{}'` y comparar
- Test: stop+start container, verify quorum queues sobreviven

---

## 8. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| CHECK constraints rechazan datos existentes | PoC: TRUNCATE before migrate; document |
| Migration runner agrega complejidad | Simple bash script con tracking de versions; no introduce dep |
| Quorum queues no soportan ciertas features | Quorum es default-recommend; classic features lost: priorities, per-message TTL (we use queue-level TTL) |
| TTL 1h en route queues purga mensajes lentos | Acceptable for instant payments; lengthen if needed |
| Alternate exchange unbinds nothing previously | Routing key typos antes silenciosamente perdidos; ahora caen en `unrouted` queue inspeccionable |

---

## 9. Commits sugeridos

1. `feat(db): CHECK constraints on payments (status, rails, currency, country, amount)`
2. `feat(db): ISO 20022 columns (uetr, end_to_end_id, charge_bearer, instructed/settlement amounts, exchange_rate)`
3. `feat(db): audit_events event_type CHECK and FK ON DELETE RESTRICT`
4. `feat(db): mapping_table rail and transformation CHECKs`
5. `refactor(db): route_rules action column (REJECT/ROUTE/COMPENSATE)`
6. `feat(db): updated_at trigger on payments and route_rules`
7. `feat(db): sweep_expired_idempotency_keys function`
8. `feat(db): reconciliation_reports table`
9. `feat(infra): migration runner script (scripts/migrate.sh)`
10. `feat(rabbitmq): quorum queues + TTL + max-length on route queues`
11. `feat(rabbitmq): DLX on payments.ack queue`
12. `feat(rabbitmq): alternate exchange mipit.unrouted for unrouted messages`
13. `chore(db): remove duplicate init/004_webhooks.sql (canonical in migrations/)`

---

## 10. Notas para el dev

- **PoC tolera reset**: el approach es "drop everything, recreate clean". En producción real, cada ALTER TABLE necesitaría migration plan cuidadoso. Para tesis: documentar como "fresh deploy migration path".
- **Quorum queues** requieren ≥3 broker nodes para tolerance real; en single-node, son **funcionales** pero sin replicación. PoC OK; cite como "quorum-ready, single-broker by deployment choice".
- **`pgcrypto`** para `gen_random_uuid()` ya está enabled (`001_schema.sql`).
- **Migration runner**: si querés algo más maduro, swap `migrate.sh` por `node-pg-migrate` (mantiene compatibility con files SQL puros).
