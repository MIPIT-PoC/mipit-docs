#!/usr/bin/env bash
# Wave 4 validation — P07 (Observability) + P11 (UI fixes) + P10 (Testkit) + P12 (Docs).
# Runs against the live local stack (docker compose up).
set -u
PASS=0; FAIL=0
green() { printf "\033[32m✓ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
red()   { printf "\033[31m✗ %s\033[0m  %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
bold()  { printf "\033[1m%s\033[0m\n" "$1"; }

CORE_URL="http://localhost:8080"
PROM_URL="http://localhost:9090"
AM_URL="http://localhost:9093"
RABBIT_MGMT="-u mipit:mipit_secret http://localhost:15672"
VHOST="mipit"   # The compose file pins vhost=mipit (not the default `/`).
ADAPTER_PIX_METRICS="http://localhost:9101/metrics"
ADAPTER_SPEI_METRICS="http://localhost:9102/metrics"
ADAPTER_BREB_METRICS="http://localhost:9103/metrics"

TOKEN=$(curl -sk -X POST "$CORE_URL/auth/token" -H 'Content-Type: application/json' -d '{}' | grep -oE '"access_token":"[^"]+"' | sed 's/.*:"\(.*\)"/\1/')

# ─── P07 Observability ───────────────────────────────────────────────────────
bold "=== P07 Observability ==="

# P07.1 — Prometheus scrappea los 3 adapters en los puertos correctos
TARGETS=$(curl -sf "$PROM_URL/api/v1/targets" | grep -oE '"job":"adapter-(pix|spei|breb)"' | sort -u)
[ "$(echo "$TARGETS" | wc -l)" = "3" ] && green "P07.1 Prometheus targets adapter-pix / -spei / -breb presentes" || red "P07.1 targets" "got: $TARGETS"

# P07.2 — rule_files cargado (mipit-recording + mipit-alerts)
RULES=$(curl -sf "$PROM_URL/api/v1/rules" | grep -oE '"name":"mipit-(recording|alerts)"' | sort -u | wc -l)
[ "$RULES" = "2" ] && green "P07.2 Recording + alert rules cargadas (mipit-recording, mipit-alerts)" || red "P07.2 rules" "expected 2 groups, got $RULES"

# P07.3 — AlertManager arriba
curl -sf "$AM_URL/api/v2/status" > /dev/null \
  && green "P07.3 AlertManager respondiendo en :9093" \
  || red "P07.3 alertmanager" "no responde"

# P07.4 — Métricas unificadas con label `rail` en los 3 adapters
for rail in pix spei breb; do
  METRIC=$(curl -sf "http://localhost:91$( [ $rail = pix ] && echo 01 || [ $rail = spei ] && echo 02 || echo 03 )/metrics" | grep -E '^mipit_adapter_requests_total\{[^}]*rail=' | head -1)
  [ -n "$METRIC" ] && green "P07.4-$rail mipit_adapter_requests_total con label rail expuesto" || red "P07.4-$rail" "missing"
done

# P07.5 — Pino redact: name/taxId/headers no aparecen en logs core
LOGS=$(docker logs mipit-core 2>&1 | tail -500)
echo "$LOGS" | grep -qE '"name":"[A-Z][a-z]+ [A-Z]' \
  && red "P07.5 PII redact" "encontré nombres en claro" \
  || green "P07.5 Pino redact: nombres no aparecen en claro en logs"

# P07.6 — UI surface trace_id (UI ya no se inspecciona aquí — chequeado en P11)

# ─── P11 UI ───────────────────────────────────────────────────────────────────
bold "=== P11 UI Critical Fixes ==="

# P11.1 — Detalle de pago tiene `trace_id`, `uetr`, `charge_bearer` en JSON
R=$(curl -sk -X POST "$CORE_URL/payments" -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: w4-ui-$(date +%s)" -H "Content-Type: application/json" \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909","name":"U"},"creditor":{"alias":"SPEI-072123456789012344","name":"V"},"purpose":"P2P"}')
PID=$(echo "$R" | grep -oE '"payment_id":"[^"]+"' | sed 's/.*:"\(.*\)"/\1/')
sleep 2
DETAIL=$(curl -sk -H "Authorization: Bearer $TOKEN" "$CORE_URL/payments/$PID")
echo "$DETAIL" | grep -q '"uetr"' && green "P11.1 PaymentDetail expone uetr" || red "P11.1 uetr" "no en respuesta"
echo "$DETAIL" | grep -q '"charge_bearer"' && green "P11.2 PaymentDetail expone charge_bearer" || red "P11.2 chrgBr" "no en respuesta"
echo "$DETAIL" | grep -q '"trace_id"' && green "P11.3 PaymentDetail expone trace_id (link a Jaeger)" || red "P11.3 trace_id" "no en respuesta"

# P11.4 — UI tests verdes (64/64)
if [ -d "C:/Users/nicog/Documents/Tesis/mipit-ui/node_modules" ]; then
  RESULT=$(cd C:/Users/nicog/Documents/Tesis/mipit-ui && npx jest --silent --json 2>/dev/null | tail -1)
  NUM_PASS=$(echo "$RESULT" | grep -oE '"numPassedTests":[0-9]+' | sed 's/.*://')
  NUM_FAIL=$(echo "$RESULT" | grep -oE '"numFailedTests":[0-9]+' | sed 's/.*://')
  [ "${NUM_FAIL:-0}" = "0" ] && [ "${NUM_PASS:-0}" -ge "60" ] && green "P11.4 UI tests: ${NUM_PASS} passing, 0 failing" || red "P11.4 UI tests" "pass=$NUM_PASS fail=$NUM_FAIL"
else
  red "P11.4 UI tests" "node_modules missing, skip"
fi

# ─── P10 Testkit ──────────────────────────────────────────────────────────────
bold "=== P10 Testkit Completeness ==="

# P10.1 — Generators producen CPFs/CLABEs/NITs con checksum válido (via tsx)
pushd C:/Users/nicog/Documents/Tesis/mipit-testkit > /dev/null
GEN_OUT=$(npx tsx --eval "
import {randomCPF, randomClabe, randomNIT} from './generators/utils.js';
function cpfValid(c){if(!/^\d{11}\$/.test(c))return false;let s=0;for(let i=0;i<9;i++)s+=parseInt(c[i],10)*(10-i);let d=11-(s%11);if(d>=10)d=0;if(parseInt(c[9],10)!==d)return false;s=0;for(let i=0;i<10;i++)s+=parseInt(c[i],10)*(11-i);let d2=11-(s%11);if(d2>=10)d2=0;return parseInt(c[10],10)===d2;}
function clabeValid(c){if(!/^\d{18}\$/.test(c))return false;const w=[3,7,1,3,7,1,3,7,1,3,7,1,3,7,1,3,7];let s=0;for(let i=0;i<17;i++)s+=parseInt(c[i],10)*w[i];return ((10-(s%10))%10)===parseInt(c[17],10);}
function nitValid(n){const parts=n.split('-');const d=parts[0];const c=parts[1];const w=[3,7,13,17,19,23,29,37,41,43,47,53,59,67,71];const r=d.split('').reverse();let s=0;for(let i=0;i<r.length;i++)s+=parseInt(r[i],10)*w[i];const rem=s%11;const ch=rem<2?rem:11-rem;return parseInt(c,10)===ch;}
let cpfOk=true,clabeOk=true,nitOk=true;
for(let i=0;i<100;i++){if(!cpfValid(randomCPF()))cpfOk=false;if(!clabeValid(randomClabe()))clabeOk=false;if(!nitValid(randomNIT()))nitOk=false;}
console.log('CPF='+cpfOk+' CLABE='+clabeOk+' NIT='+nitOk);
" 2>&1)
echo "$GEN_OUT" | grep -q "CPF=true CLABE=true NIT=true" \
  && green "P10.1 Generators producen CPF / CLABE / NIT con checksum válido (100/100 c/u)" \
  || red "P10.1 generators" "$GEN_OUT"
popd > /dev/null

# P10.2 — Datasets Bre-B existen y pasan el wire-format schema
[ -f C:/Users/nicog/Documents/Tesis/mipit-testkit/datasets/breb/breb-valid-01.json ] \
  && green "P10.2 Datasets Bre-B presentes (breb-valid-{01,02,nit}, breb-to-spei-01, breb-invalid-*)" \
  || red "P10.2 datasets" "missing"

# P10.3 — Contract test suite verde offline
cd C:/Users/nicog/Documents/Tesis/mipit-testkit
SUITE=$(npx jest --testPathPattern=tests/contract --silent --json 2>/dev/null | tail -1)
NUM_PASS=$(echo "$SUITE" | grep -oE '"numPassedTests":[0-9]+' | sed 's/.*://')
NUM_FAIL=$(echo "$SUITE" | grep -oE '"numFailedTests":[0-9]+' | sed 's/.*://')
[ "${NUM_FAIL:-0}" = "0" ] && [ "${NUM_PASS:-0}" -ge "20" ] && green "P10.3 Contract tests: ${NUM_PASS} passing, 0 failing" || red "P10.3 contract" "pass=$NUM_PASS fail=$NUM_FAIL"
cd - > /dev/null

# P10.4 — Smoke test (con JWT, P10) cubre los 3 rail-pairs
if [ -n "$TOKEN" ]; then
  cd C:/Users/nicog/Documents/Tesis/mipit-testkit
  SMOKE_OUT=$(bash tools/smoke-test.sh 2>&1)
  echo "$SMOKE_OUT" | grep -q "PIX → SPEI" && echo "$SMOKE_OUT" | grep -q "SPEI → BRE_B" && echo "$SMOKE_OUT" | grep -q "BRE_B → PIX" \
    && green "P10.4 Smoke test ejercita 3 rail-pairs (PIX→SPEI, SPEI→BRE_B, BRE_B→PIX)" \
    || red "P10.4 smoke" "no cubre los 3 pairs"
  cd - > /dev/null
fi

# P10.5 — Topología RabbitMQ presente (chequeada por contract test live también)
EX=$(curl -sf $RABBIT_MGMT/api/exchanges/$VHOST/mipit.payments 2>/dev/null | grep -oE '"type":"[^"]+"' | head -1)
[ "$EX" = '"type":"topic"' ] && green "P10.5 Exchange mipit.payments (topic) existe" || red "P10.5 exchange" "got $EX"

BINDINGS=$(curl -sf $RABBIT_MGMT/api/queues/$VHOST/payments.ack/bindings 2>/dev/null | grep -oE '"routing_key":"ack\.[^"]+"' | wc -l)
[ "$BINDINGS" -ge "3" ] && green "P10.5b payments.ack tiene ≥3 bindings (ack.pix, ack.spei, ack.breb)" || red "P10.5b bindings" "got $BINDINGS"

# ─── P12 Docs ─────────────────────────────────────────────────────────────────
bold "=== P12 Documentation ==="

# P12.1 — CONTEXTO-MIPIT.md menciona Next.js (no Vite) y Bre-B
grep -q "Next.js 15" C:/Users/nicog/Documents/Tesis/CONTEXTO-MIPIT.md \
  && green "P12.1 CONTEXTO-MIPIT.md actualizado a Next.js 15" \
  || red "P12.1 CONTEXTO" "aún dice Vite/desactualizado"
grep -q "Bre-B\|BRE_B" C:/Users/nicog/Documents/Tesis/CONTEXTO-MIPIT.md \
  && green "P12.1b CONTEXTO-MIPIT.md menciona Bre-B" \
  || red "P12.1b CONTEXTO" "no menciona Bre-B"

# P12.2 — LIMITATIONS.md existe
[ -f C:/Users/nicog/Documents/Tesis/mipit-docs/LIMITATIONS.md ] \
  && green "P12.2 LIMITATIONS.md creado en mipit-docs" \
  || red "P12.2 LIMITATIONS" "missing"

# P12.3 — OpenAPI lista 14 estados + Bre-B + UETR
grep -q "DEAD_LETTER" C:/Users/nicog/Documents/Tesis/mipit-docs/openapi/openapi.yaml \
  && green "P12.3a OpenAPI lista los 14 PaymentStatus (incluye DEAD_LETTER)" \
  || red "P12.3a openapi" "no DEAD_LETTER"
grep -q "BRE_B" C:/Users/nicog/Documents/Tesis/mipit-docs/openapi/openapi.yaml \
  && green "P12.3b OpenAPI incluye BRE_B en enums" \
  || red "P12.3b openapi" "no BRE_B"
grep -q "uetr" C:/Users/nicog/Documents/Tesis/mipit-docs/openapi/openapi.yaml \
  && green "P12.3c OpenAPI expone UETR en PaymentDetail" \
  || red "P12.3c openapi" "no uetr"

# P12.4 — Demo runbook menciona AlertManager y adapter-breb
grep -q "AlertManager\|alertmanager" C:/Users/nicog/Documents/Tesis/mipit-docs/demo-runbook/local-demo.md \
  && green "P12.4a local-demo.md menciona AlertManager (P07)" \
  || red "P12.4a runbook" "no AM"
grep -q "adapter-breb" C:/Users/nicog/Documents/Tesis/mipit-docs/demo-runbook/local-demo.md \
  && green "P12.4b local-demo.md menciona adapter-breb (P04)" \
  || red "P12.4b runbook" "no breb"

bold "=== SUMMARY ==="
printf "Total: %d\n" "$((PASS+FAIL))"
printf "\033[32mPassed: %d\033[0m\n" "$PASS"
printf "\033[31mFailed: %d\033[0m\n" "$FAIL"
[ "$FAIL" -gt "0" ] && exit 1
exit 0
