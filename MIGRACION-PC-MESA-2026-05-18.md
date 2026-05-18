# Migración a PC de mesa — Sesiones 2026-05-17 + 2026-05-18

> **Para Nicolás (y cualquier dev migrando):** este documento te dice qué pasó en las sesiones del 17–18 mayo, qué commits hay nuevos, y los comandos exactos para alinearte en tu PC de mesa.

**Fecha de corte:** 2026-05-18
**Branch activa en los 9 repos:** `Auditoria-Claude`
**Stack live verificado:** 12/12 containers UP en macOS local (último rebuild 2026-05-17 noche)

---

## 0. TL;DR

```bash
# En tu PC de mesa
cd ~/Documents/Tesis  # ajusta a tu path

# 1. Pull en los 9 repos (todos en Auditoria-Claude)
for r in mipit-core mipit-ui mipit-adapter-pix mipit-adapter-spei mipit-adapter-breb \
         mipit-testkit mipit-observability mipit-infra mipit-docs; do
  cd "$r"
  git fetch origin
  git checkout Auditoria-Claude
  git pull --ff-only origin Auditoria-Claude
  cd -
done

# 2. Limpiar branches locales obsoletas (wave-5-hardening ya merged + borrada en remoto)
for r in mipit-core mipit-ui mipit-adapter-pix mipit-adapter-spei mipit-adapter-breb mipit-infra; do
  cd "$r" && git branch -D wave-5-hardening 2>/dev/null; cd -
done

# 3. Leer docs nuevos (orden recomendado)
cat mipit-docs/audits/AUDITORIA-2-2026-05-17.md          # auditoría 2 maestro
cat mipit-docs/plans/Wave-5-Hardening-Pre-Sustentacion.plan.md   # lo que se entregó
cat mipit-docs/plans/Wave-6-ISO20022-Spec-Compliance.plan.md     # lo que se entregó
cat mipit-docs/plans/Wave-7-Single-Source-of-Truth-y-Limpieza.plan.md   # próximo
cat mipit-docs/plans/Wave-8-Production-Ready.plan.md     # roadmap post-tesis
```

---

## 1. Lo que pasó (cronología)

### Sesión 2026-05-17 (mañana)
1. Pull de 9 repos a `Auditoria-Claude` (estado Wave 1–4).
2. Rebuild stack docker en macOS, verificación 591/591 unit tests + smoke 3/3 rail-pairs.
3. Doc generado: [evidence/wave-1-4-verification-2026-05-17-macos.md](evidence/wave-1-4-verification-2026-05-17-macos.md).

### Sesión 2026-05-17 (mediodía)
**Auditoría 2** — 5 agentes paralelos descubrieron **88 hallazgos NUEVOS** no cubiertos por la primera. Documentos generados:
- [audits/AUDITORIA-2-2026-05-17.md](audits/AUDITORIA-2-2026-05-17.md) (maestro consolidado)
- [audits/raw/audit-2-2026-05-17/A1-spec-compliance.md](audits/raw/audit-2-2026-05-17/A1-spec-compliance.md) (ISO 20022 deep)
- [audits/raw/audit-2-2026-05-17/A3-code-quality.md](audits/raw/audit-2-2026-05-17/A3-code-quality.md)
- [audits/raw/audit-2-2026-05-17/A4-red-team.md](audits/raw/audit-2-2026-05-17/A4-red-team.md)
- [audits/raw/audit-2-2026-05-17/A5-inconsistencies.md](audits/raw/audit-2-2026-05-17/A5-inconsistencies.md)
- [evidence/AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md](evidence/AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md) (A2)

### Sesión 2026-05-17 (tarde) — Wave 5 entregada
**Hardening pre-sustentación** — 14 tickets cerrados:
- Plan: [plans/Wave-5-Hardening-Pre-Sustentacion.plan.md](plans/Wave-5-Hardening-Pre-Sustentacion.plan.md)
- Evidencia: [evidence/wave-5-verification-2026-05-17.md](evidence/wave-5-verification-2026-05-17.md)
- Inicialmente usé branches `wave-5-hardening`; después merged a `Auditoria-Claude` y borradas.

### Sesión 2026-05-17 (noche) — Wave 6 entregada
**ISO 20022 spec compliance** — 13 tickets cerrados directo en `Auditoria-Claude`:
- Plan: [plans/Wave-6-ISO20022-Spec-Compliance.plan.md](plans/Wave-6-ISO20022-Spec-Compliance.plan.md)
- Evidencia: [evidence/wave-6-verification-2026-05-17.md](evidence/wave-6-verification-2026-05-17.md)
- 310/310 unit tests core post-Wave 6
- pacs.002 enriquecido emitiéndose live; pacs.004 emitido en compensation; BREB 4-dig + COP integer; FedNow USD-only guard; NACHA byte-exact layout; LIMITATIONS.md con §11 y §12 documentando scope-outs.

### Sesión 2026-05-18
**Housekeeping + planes prospectivos** — esta sesión:
- Borradas branches `wave-5-hardening` en local y remoto (6 repos)
- Limpieza de testkit dirty (datasets efímeros)
- Plans Wave 7 + Wave 8 escritos como `.plan.md` formales
- plans/README.md actualizado con índice de Waves 5–8
- Este documento MIGRACION-PC-MESA-2026-05-18.md creado

---

## 2. Aclaración crítica de rieles (importante para la defensa)

Durante Wave 5 emergió una clarificación que reorienta cómo se lee toda la auditoría 2:

**3 rieles PRODUCTIVOS** (adapter + mock + pipeline E2E):
- **PIX** (Brasil, BACEN SPI)
- **SPEI** (México, Banxico CECOBAN)
- **Bre-B** (Colombia, BanRep TR-002)

**4 rieles CASE-STUDY / extensibilidad** (translator-only via `POST /translate/*`):
- **SWIFT MT103**
- **ISO 20022 MX**
- **ACH NACHA**
- **FedNow**

Los 4 case-study **no son una limitación encubierta** — son el **diferenciador del PoC**: demuestran que agregar un riel al hub-and-spoke requiere sólo escribir `*-to-canonical.ts` + `canonical-to-*.ts`. Esto está explícito en:
- `mipit-docs/LIMITATIONS.md` §1 + §12
- `mipit-docs/audits/AUDITORIA-2-2026-05-17.md` (Amendment al inicio)
- `mipit-docs/evidence/AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` (gap declarativo: FedNow degradado a translator-only sustituido por Bre-B)

**Por qué importa para el panel:** si te preguntan "¿por qué no demostraron FedNow productivo?" — la respuesta es "FedNow es nuestro case study de extensibilidad ISO 20022 vía traductor; los 3 productivos son los LATAM con mock real". Esa narrativa convierte una potencial vulnerabilidad en un punto fuerte.

---

## 3. Commits clave (HEADs a 2026-05-18)

```
mipit-core            d09e556 Wave 6 — ISO 20022 spec compliance (mipit-core)
mipit-ui              2c63746 Merge wave-5-hardening — pre-sustentacion hardening (14 tickets)
mipit-adapter-pix     a398357 Wave 6 — W6.1: PIX adapter emite bloque pacs.002 enriquecido
mipit-adapter-spei    53043c0 Wave 6 — W6.1 + W6.3: SPEI emite pacs.002 + propaga ctgyPurp
mipit-adapter-breb    c9a4e77 Wave 6 — W6.1 + W6.7: BREB emite pacs.002 + 4-dig codigoEntidad
mipit-testkit         8af5268 Wave 4 — P10 (sin cambios en W5/W6)
mipit-observability   d01bd76 Wave 4 — P07 (sin cambios en W5/W6)
mipit-infra           60c8164 Merge wave-5-hardening — pre-sustentacion (puertos 9101/02/03 + SQL doc)
mipit-docs            (último) Wave 6 — W6.12 + W6.13 + evidence + plans Wave 7/8
```

---

## 4. Cambios en código que vas a ver

### `mipit-core`
- `src/api/routes/payments.ts`: `GET /payments/:id` ahora surface `uetr`, `end_to_end_id`, `charge_bearer`, FX completo, terminal timestamps
- `src/api/routes/webhooks.ts` (NUEVO): endpoint `/webhooks/alertmanager` público
- `src/api/routes/sse.ts`: handlers exigen `?token=<jwt>` (W5.9)
- `src/canonical/pacs002.schema.ts`: forward-compat `.NN`
- `src/canonical/pacs004.schema.ts` (NUEVO): PaymentReturn ISO 20022
- `src/translation/rail-rejection-mapping.ts` (NUEVO): BACEN/CECOBAN/BREB → ISO ExternalStatusReason1Code
- `src/translation/breb-to-canonical.ts`: BREB codes a 4-dig + ALIAS regex unificada + comentario sobre fidelidad
- `src/translation/canonical-to-{pix,spei}.ts`: regeneran IDs cuando el canónico tiene formato no-rail
- `src/translation/canonical-to-fednow.ts`: throw si currency !== USD
- `src/translation/canonical-to-ach-nacha.ts`: File Header (Type 1) layout corregido byte-exact
- `src/translation/canonical-to-swift-mt103.ts`: detailsOfCharges mapeado de ChrgBr
- `src/translation/canonical-to-iso20022-mx.ts`: XchgRate como objeto + LclInstrm
- `src/domain/models/canonical.ts`: agrega `ctgyPurp` + `lclInstrm`
- `src/pipeline/payment-pipeline.ts`: stampa `nbOfTxs/ctrlSum/ttlIntrBkSttlmAmt` + recordPayment(FAILED) en catch
- `src/observability/metrics.ts`: buckets `[10..30000]`
- `src/messaging/consumer.ts`: enriquece rail_ack con `tx_sts/orgnl_uetr/orgnl_end_to_end_id/sts_rsn_inf`
- `src/compensation/compensation-service.ts`: emite pacs.004 real cuando wasAcked

### `mipit-ui`
- `src/lib/types.ts` + `lib/constants.ts`: agregan `NORMALIZED` + RailPicker limita a productivos
- `src/app/payments/[id]/page.tsx`: Jaeger link via search-by-attribute (no `/trace/<id>`)
- `src/app/simulate/page.tsx`: sólo 3 rieles productivos + banner a `/translator`
- `src/components/payments/payment-status-badge.tsx`: fallback neutral para status desconocidos
- 4 stubs zombie eliminados (payment-card.tsx, payment-form.tsx, pix-form.tsx, spei-form.tsx)

### `mipit-adapter-{pix,spei,breb}`
- `src/worker.ts`: emite bloque `pacs002` enriquecido + helper `railStatusToTxSts`
- `src/observability/metrics.ts`: buckets `[10..30000]`
- SPEI: `mapper.ts` deriva `tipoPago` de `ctgyPurp` (CASH/SALA/TAXS/...); `types.ts` widens `tipoPago: number`
- BREB: mensajes de error stale corregidos ("4 u 8 dígitos")

### `mipit-infra`
- `db/init/003_seed_mapping_table.sql`: cabecera "mapping-as-documentation, not policy engine"

### `mipit-docs`
- **NUEVO** `audits/AUDITORIA-2-2026-05-17.md` + 4 raw files en `audits/raw/audit-2-2026-05-17/`
- **NUEVO** `evidence/AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md`
- **NUEVO** `evidence/wave-5-verification-2026-05-17.md`
- **NUEVO** `evidence/wave-6-verification-2026-05-17.md`
- **NUEVO** `plans/Wave-5-Hardening-Pre-Sustentacion.plan.md`
- **NUEVO** `plans/Wave-6-ISO20022-Spec-Compliance.plan.md`
- **NUEVO** `plans/Wave-7-Single-Source-of-Truth-y-Limpieza.plan.md`
- **NUEVO** `plans/Wave-8-Production-Ready.plan.md`
- `plans/README.md`: actualizado con índice Waves 5–8
- `LIMITATIONS.md`: §11 (scope-outs ISO 20022) + §12 (case-study rails clarificados)
- `README.md` + `AGENTS.md`: borrados refs a mappings legacy
- **BORRADOS** `mappings/canonical-fields.md` + 4 CSVs (W6.13)

---

## 5. Levantar el stack en tu PC

```bash
cd mipit-infra

# Down completo (evita network DNS race al rebuild)
docker compose -f compose/docker-compose.yml -f compose/docker-compose.override.yml down

# Up con rebuild
docker compose -f compose/docker-compose.yml -f compose/docker-compose.override.yml up -d --build

# Esperar ~30s a que se estabilice
sleep 30

# Health check
curl -sf http://localhost:8080/health
# Esperado: {"status":"ok","checks":{"db":"ok","rabbitmq":"ok"}}

# Smoke 3 rail-pairs
TOKEN=$(curl -sf -X POST http://localhost:8080/auth/token -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)

# PIX → SPEI (cross-currency BRL→MXN)
curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: smoke-$(date +%s)-1" \
  -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-012180000118359713"}}' | jq

# PIX → BRE_B (cross-currency BRL→COP)
curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: smoke-$(date +%s)-2" \
  -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"BREB-+573001234567"}}' | jq
```

---

## 6. Cómo verificar las mejoras Wave 5+6 contra tu stack

```bash
TOKEN=$(curl -sf -X POST http://localhost:8080/auth/token -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)

# W5.1 — API surface UETR + FX
PMT=$(curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: verify-$(date +%s)" \
  -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-012180000118359713"}}' \
  | jq -r .payment_id)
sleep 4
curl -sf -H "Authorization: Bearer $TOKEN" "http://localhost:8080/payments/$PMT" | \
  jq '{uetr, end_to_end_id, charge_bearer, settlement_currency, exchange_rate}'
# Esperado: campos no nulos

# W5.2 — Endpoint AlertManager existe
curl -sf -X POST http://localhost:8080/webhooks/alertmanager \
  -H 'Content-Type: application/json' \
  -d '{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"Test","severity":"warning"},"annotations":{"summary":"verify"}}]}'
# Esperado: {"received":true,"parsed":true,"count":1}

# W5.5 — Buckets nuevos (le="10" debe existir)
curl -sf http://localhost:8080/metrics | grep 'mipit_payment_latency_ms_bucket{stage="pipeline_total",le="10"'
# Esperado: una línea

# W5.9 — SSE requiere token
curl -s -o /dev/null -w "HTTP=%{http_code}\n" http://localhost:8080/events/payments
# Esperado: HTTP=401

curl -s -o /dev/null -w "HTTP=%{http_code}\n" --max-time 2 "http://localhost:8080/events/payments?token=$TOKEN"
# Esperado: HTTP=200

# W6.1 — pacs.002 enriquecido en rail_ack
docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT jsonb_pretty(rail_ack) FROM payments WHERE payment_id='$PMT'"
# Esperado: incluye tx_sts (ej "ACSC"), orgnl_uetr (UUID), orgnl_end_to_end_id

# W6.7 — BREB outbound 4-dig + COP integer
PMT2=$(curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: w67-$(date +%s)" \
  -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"BREB-+573001234567"}}' \
  | jq -r .payment_id)
sleep 4
docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT jsonb_pretty(translated_payload) FROM payments WHERE payment_id='$PMT2'"
# Esperado: codigoEntidad: "9999" (4-dig); valor.original: "83267" (sin decimales)
```

---

## 7. Tests offline esperados

| Repo | Tests esperados |
|---|---|
| `mipit-core` unit | 310/310 |
| `mipit-ui` | 65/65 |
| `mipit-adapter-pix` | 62/62 |
| `mipit-adapter-spei` | 86/86 |
| `mipit-adapter-breb` | 44/44 |
| `mipit-testkit` contract offline | 28/28 + 11 skipped (live) |

```bash
# Correr todos en serial (o paralelo si tu cpu aguanta)
for r in mipit-core mipit-ui mipit-adapter-pix mipit-adapter-spei mipit-adapter-breb; do
  echo "=== $r ==="
  cd "$r" && npm test --silent | tail -5
  cd -
done
cd mipit-testkit && npm run test:contract --silent | tail -5
```

**Si en tu PC mac/arm los tests del UI fallan con "@next/swc-darwin-arm64 not installed"**:
```bash
cd mipit-ui && npm install @next/swc-darwin-arm64 @next/swc-darwin-x64 --no-save
```

---

## 8. Próximas waves (cuando decidas)

### Si la sustentación está en <1 semana:
- **NO** hacer Wave 7 ni Wave 8 — concentrarse en ensayar la demo y refinar slides
- Usar los docs `evidence/wave-5-verification` y `evidence/wave-6-verification` como respaldo de "lo que se logró"

### Si quedan 1-2 semanas:
- **Considerar Wave 7** (1.5 días, limpieza visible: deps, dead code, tests placebo). Eleva la percepción de calidad del código sin riesgo funcional.

### Post-sustentación (si MIPIT continúa):
- **Wave 8** (~7-10 días, refactors arquitecturales). Lleva a MVP productivo.

---

## 9. Decisiones del equipo capturadas

| Decisión | Razón | Documentado en |
|---|---|---|
| Commitear directo a `Auditoria-Claude`, no usar branches `wave-N` | Equipo prefiere historial lineal; las branches efímeras agregaban fricción | Este doc + plans Wave 7/8 |
| Tests se ajustan al código, no al revés | Si un test verde escondía un bug real (ej. UI sin NORMALIZED), el test estaba mal | Tickets W5.6, W6.5/9/10 |
| 3 productivos + 4 case-study es by-design, no scope-out | Diferenciador del PoC (demostrar extensibilidad arquitectónica) | LIMITATIONS.md §1+§12, AUDITORIA-2 Amendment |
| Borrar mappings/canonical-fields.md y CSVs legacy | Eran 4 representaciones del canónico que divergían silenciosamente; ahora ADR-002 + canonical.ts (Zod) son la única fuente | W6.13 |
| Cargo de `pacs.004` en compensation persiste en audit, sin enviar a queue de returns | Mock destino no consume return queue (scope-out PoC); pacs.004 sirve como evidencia de generación | W6.4 + LIMITATIONS §11 |

---

## 10. Si algo te confunde

1. **"¿Qué branch debo usar?"** → `Auditoria-Claude` en los 9 repos.
2. **"Veo `wave-5-hardening` localmente"** → `git branch -D wave-5-hardening` (ya merged + borrada en remoto).
3. **"`Auditoria-Claude` está adelantado en remoto"** → `git pull --ff-only origin Auditoria-Claude`.
4. **"El stack no levanta"** → `docker compose down` completo, luego `up -d --build`. El network DNS de Docker se confunde con rebuilds parciales.
5. **"Los tests fallan en mi PC pero pasan en macOS"** → revisa `@next/swc-*` binaries (UI) y que `mipit-core/.env` exista localmente (gitignored).
6. **"Hay docs que no entiendo"** → empezar por `audits/AUDITORIA-2-2026-05-17.md` (es el maestro de toda la auditoría 2), luego `plans/README.md`.

---

**Última actualización:** 2026-05-18 — sesión de housekeeping + plans Wave 7/8 + esta guía
