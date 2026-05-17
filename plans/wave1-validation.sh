#!/usr/bin/env bash
# Wave 1 regression validation — Pass/fail per check.
# Goal: confirm Wave 1 changes (P01/P08/P09) don't break the system and
# their intended behavior is observable.

set -u
PASS=0
FAIL=0
SKIP=0
REPORT=()

CORE_URL="http://localhost:8080"
ADAPTER_PIX="http://localhost:9001"
ADAPTER_SPEI="http://localhost:9002"
ADAPTER_BREB="http://localhost:9003"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
green() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
red() { printf "\033[31m✗ %s\033[0m  %s\n" "$1" "$2"; }
yellow() { printf "\033[33m~ %s\033[0m  %s\n" "$1" "$2"; }

pass() { PASS=$((PASS+1)); green "$1"; REPORT+=("PASS: $1"); }
fail() { FAIL=$((FAIL+1)); red "$1" "$2"; REPORT+=("FAIL: $1 — $2"); }
skip() { SKIP=$((SKIP+1)); yellow "$1" "$2"; REPORT+=("SKIP: $1 — $2"); }

# Mute curl progress
CURL_OPTS="-sk --max-time 15"

# ─── Helper: get a JWT once ───────────────────────────────────────
TOKEN=$(curl $CURL_OPTS "$CORE_URL/auth/token" | grep -oE '"access_token":"[^"]+"' | sed 's/.*:"\(.*\)"/\1/')
if [ -z "$TOKEN" ]; then echo "FATAL: cannot get JWT"; exit 2; fi

bold "=== 1. STACK HEALTH ==="

# 1.1 /health/live always 200
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "$CORE_URL/health/live")
[ "$code" = "200" ] && pass "1.1 /health/live returns 200" || fail "1.1 /health/live" "got $code"

# 1.2 /health deep probe — should be 200 (db + mq up)
body=$(curl $CURL_OPTS "$CORE_URL/health")
echo "$body" | grep -q '"db":"ok"' && echo "$body" | grep -q '"rabbitmq":"ok"' \
  && pass "1.2 /health deep probe (db+mq ok)" \
  || fail "1.2 /health deep probe" "body=$body"

# 1.3 RabbitMQ Management
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" http://mipit:mipit_secret@localhost:15672/api/overview)
[ "$code" = "200" ] && pass "1.3 RabbitMQ management API reachable" || fail "1.3 RabbitMQ mgmt" "got $code"

# 1.4 Adapters health
for rail in pix spei breb; do
  port=$((9100 + ( $(echo "pix:1 spei:2 breb:3" | tr ' ' '\n' | grep "^$rail:" | cut -d: -f2) )))
  code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "http://localhost:${port}/health")
  [ "$code" = "200" ] && pass "1.4.$rail adapter $rail health" || fail "1.4.$rail adapter $rail" "port $port returned $code"
done

bold "=== 2. JWT / AUTH SECURITY (P08) ==="

# 2.1 JWT claims have iss/aud
claims=$(echo "$TOKEN" | awk -F. '{print $2}' | tr '_-' '/+' | { read s; pad=$(( (4 - ${#s} % 4) % 4 )); echo "$s$(printf '=%.0s' $(seq 1 $pad))"; } | base64 -d 2>/dev/null)
echo "$claims" | grep -q '"iss":"mipit-core"' && echo "$claims" | grep -q '"aud":"mipit-ui"' \
  && pass "2.1 JWT has iss=mipit-core + aud=mipit-ui" \
  || fail "2.1 JWT claims" "claims=$claims"

# 2.2 No-auth request rejected on /payments
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" -H "Content-Type: application/json" -d '{}')
[ "$code" = "401" ] && pass "2.2 POST /payments without JWT → 401" || fail "2.2 unauthed POST" "got $code"

# 2.3 JWT with alg=none rejected
none_token="eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJtaXBpdC11aSIsInJvbGUiOiJhZG1pbiIsImlzcyI6Im1pcGl0LWNvcmUiLCJhdWQiOiJtaXBpdC11aSJ9."
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" -H "Authorization: Bearer $none_token" -H "Content-Type: application/json" -d '{}')
[ "$code" = "401" ] && pass "2.3 JWT alg=none rejected (algorithm pinning)" || fail "2.3 alg=none" "got $code"

# 2.4 /auth/token enabled in non-prod (current env is development)
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "$CORE_URL/auth/token")
[ "$code" = "200" ] && pass "2.4 /auth/token works in non-production" || fail "2.4 /auth/token" "got $code"

bold "=== 3. PAYMENT HAPPY PATH (P01) ==="

# 3.1 POST /payments returns 201 + UETR + ChrgBr + IntrBkSttlmDt
idk="wave1-happy-$(date +%s)"
resp=$(curl $CURL_OPTS -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $idk" \
  -H "Content-Type: application/json" \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909","name":"Validador"},"creditor":{"alias":"SPEI-072123456789012344","name":"Receiver"},"purpose":"P2P"}')
pid=$(echo "$resp" | grep -oE '"payment_id":"[^"]+"' | sed 's/.*:"\(.*\)"/\1/')
[ -n "$pid" ] && pass "3.1 POST /payments → 201 returns payment_id ($pid)" || fail "3.1 POST /payments" "resp=$resp"

# 3.2 Response contains origin/destination/trace_id
echo "$resp" | grep -q '"origin_rail":"PIX"' \
  && echo "$resp" | grep -q '"destination_rail":"SPEI"' \
  && echo "$resp" | grep -q '"trace_id":"' \
  && pass "3.2 Response has origin/destination/trace_id" \
  || fail "3.2 Response shape" "resp=$resp"

# Wait briefly for DB consistency
sleep 2

# 3.3 GET /payments/:id returns persisted ISO 20022 fields
detail=$(curl $CURL_OPTS "$CORE_URL/payments/$pid" -H "Authorization: Bearer $TOKEN")
uetr=$(echo "$detail" | grep -oE '"uetr":"[^"]*"' | head -1 | sed 's/.*:"\(.*\)"/\1/')
echo "$uetr" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' \
  && pass "3.3 Payment has valid UUIDv4 UETR ($uetr)" \
  || fail "3.3 UETR format" "got=$uetr"

# 3.4 Idempotency replay returns cached
resp2=$(curl $CURL_OPTS -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $idk" \
  -H "Content-Type: application/json" \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909","name":"Validador"},"creditor":{"alias":"SPEI-072123456789012344","name":"Receiver"},"purpose":"P2P"}')
pid2=$(echo "$resp2" | grep -oE '"payment_id":"[^"]+"' | sed 's/.*:"\(.*\)"/\1/')
[ "$pid" = "$pid2" ] && pass "3.4 Idempotency replay returns same payment_id" || fail "3.4 idempotency replay" "first=$pid second=$pid2"

# 3.5 Idempotency conflict (same key, different body) → 409
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $idk" \
  -H "Content-Type: application/json" \
  -d '{"amount":999,"currency":"BRL","debtor":{"alias":"PIX-12345678909","name":"X"},"creditor":{"alias":"SPEI-072123456789012344","name":"Y"},"purpose":"P2P"}')
[ "$code" = "409" ] && pass "3.5 Idempotency conflict → 409" || fail "3.5 idempotency conflict" "got $code"

bold "=== 4. DB CHECK CONSTRAINTS (P09) ==="

# 4.1 status enum rejected
err=$(docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,debtor_alias,creditor_alias,uetr) VALUES ('PMT-W1CHECKSTAT0000','GIBBERISH','PIX',1,'BRL','a','b',gen_random_uuid())" 2>&1)
echo "$err" | grep -q "payments_status_check" \
  && pass "4.1 CHECK: invalid status rejected" \
  || fail "4.1 status CHECK" "err=$err"

# 4.2 amount > 0 enforced
err=$(docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,debtor_alias,creditor_alias,uetr) VALUES ('PMT-W1CHECKAMT00000','RECEIVED','PIX',-1,'BRL','a','b',gen_random_uuid())" 2>&1)
echo "$err" | grep -q "payments_amount_positive" \
  && pass "4.2 CHECK: negative amount rejected" \
  || fail "4.2 amount CHECK" "err=$err"

# 4.3 currency ISO 4217 form
err=$(docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,debtor_alias,creditor_alias,uetr) VALUES ('PMT-W1CHECKCCY00000','RECEIVED','PIX',1,'usd','a','b',gen_random_uuid())" 2>&1)
echo "$err" | grep -q "payments_currency_iso4217" \
  && pass "4.3 CHECK: non-ISO currency rejected (lowercase)" \
  || fail "4.3 currency CHECK" "err=$err"

# 4.4 charge_bearer enum
err=$(docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,charge_bearer,debtor_alias,creditor_alias,uetr) VALUES ('PMT-W1CHECKCHB00000','RECEIVED','PIX',1,'BRL','XXXX','a','b',gen_random_uuid())" 2>&1)
echo "$err" | grep -q "payments_charge_bearer_check" \
  && pass "4.4 CHECK: invalid charge_bearer rejected" \
  || fail "4.4 charge_bearer CHECK" "err=$err"

# 4.5 UETR uniqueness
fixed_uuid="11111111-1111-4111-8111-111111111111"
docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,debtor_alias,creditor_alias,uetr) VALUES ('PMT-W1UETR0000000000','RECEIVED','PIX',1,'BRL','a','b','$fixed_uuid')" >/dev/null 2>&1
err=$(docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,debtor_alias,creditor_alias,uetr) VALUES ('PMT-W1UETRDUP0000000','RECEIVED','PIX',1,'BRL','a','b','$fixed_uuid')" 2>&1)
echo "$err" | grep -qiE "duplicate|unique" \
  && pass "4.5 UETR UNIQUE constraint enforced" \
  || fail "4.5 UETR uniqueness" "err=$err"

# Clean up
docker exec mipit-postgres psql -U mipit -d mipit -c \
  "DELETE FROM audit_events WHERE payment_id LIKE 'PMT-W1%'; DELETE FROM payments WHERE payment_id LIKE 'PMT-W1%';" >/dev/null 2>&1

bold "=== 5. DB MIGRATIONS APPLIED (P09) ==="

# 5.1 schema_migrations tracks applied
count=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc "SELECT count(*) FROM schema_migrations" 2>&1 | tr -d '\r ')
[ "$count" -ge "6" ] && pass "5.1 schema_migrations has $count rows (≥6 expected)" || fail "5.1 schema_migrations" "got $count"

# 5.2 Re-running migrate.sh is idempotent
cd "C:/Users/nicog/Documents/Tesis/mipit-infra" && out=$(bash scripts/migrate.sh 2>&1 | tail -5) ; cd - >/dev/null
echo "$out" | grep -q "Migrations up to date" \
  && pass "5.2 migrate.sh idempotent (re-run is no-op)" \
  || fail "5.2 migrate.sh idempotent" "out=$out"

# 5.3 updated_at trigger fires
docker exec mipit-postgres psql -U mipit -d mipit -c \
  "INSERT INTO payments (payment_id,status,origin_rail,amount,currency,debtor_alias,creditor_alias,uetr,updated_at) VALUES ('PMT-W1TRIG00000000','RECEIVED','PIX',1,'BRL','a','b',gen_random_uuid(),'2020-01-01'::timestamptz);" >/dev/null 2>&1
# Update and check the updated_at was bumped
docker exec mipit-postgres psql -U mipit -d mipit -c "UPDATE payments SET status='VALIDATED' WHERE payment_id='PMT-W1TRIG00000000'" >/dev/null 2>&1
upd=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc "SELECT updated_at > '2025-01-01' FROM payments WHERE payment_id='PMT-W1TRIG00000000'" 2>&1 | tr -d '\r ')
[ "$upd" = "t" ] && pass "5.3 updated_at trigger bumps on UPDATE" || fail "5.3 updated_at trigger" "got $upd"
docker exec mipit-postgres psql -U mipit -d mipit -c "DELETE FROM audit_events WHERE payment_id='PMT-W1TRIG00000000'; DELETE FROM payments WHERE payment_id='PMT-W1TRIG00000000'" >/dev/null 2>&1

# 5.4 sweep_expired_idempotency_keys() function exists
exists=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT count(*) FROM pg_proc WHERE proname='sweep_expired_idempotency_keys'" 2>&1 | tr -d '\r ')
[ "$exists" = "1" ] && pass "5.4 sweep_expired_idempotency_keys() function present" || fail "5.4 sweeper fn" "count=$exists"

# 5.5 Idempotency expires_at is being written
docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT count(*) FROM idempotency_keys WHERE expires_at > NOW()" >/dev/null 2>&1
ne=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT count(*) FROM idempotency_keys WHERE expires_at IS NULL" 2>&1 | tr -d '\r ')
[ "$ne" = "0" ] && pass "5.5 All idempotency_keys have expires_at set (TTL bug fix)" || fail "5.5 expires_at TTL bug" "null rows=$ne"

bold "=== 6. RABBITMQ TOPOLOGY ==="

# 6.1 Exchanges exist
for ex in mipit.payments mipit.dlx; do
  code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "http://mipit:mipit_secret@localhost:15672/api/exchanges/mipit/${ex}")
  [ "$code" = "200" ] && pass "6.1.$ex exchange exists" || fail "6.1.$ex" "got $code"
done

# 6.2 All queues exist
for q in payments.route.pix payments.route.spei payments.route.breb payments.ack dlq.pix dlq.spei dlq.breb; do
  code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "http://mipit:mipit_secret@localhost:15672/api/queues/mipit/${q}")
  [ "$code" = "200" ] && pass "6.2.$q queue exists" || fail "6.2.$q" "got $code"
done

bold "=== 7. PIPELINE END-TO-END ==="

# 7.1 Wait + verify the smoke payment progressed through pipeline
sleep 4
detail=$(curl $CURL_OPTS "$CORE_URL/payments/$pid" -H "Authorization: Bearer $TOKEN")
status=$(echo "$detail" | grep -oE '"status":"[^"]+"' | head -1 | sed 's/.*:"\(.*\)"/\1/')
case "$status" in
  QUEUED|ACKED_BY_RAIL|COMPLETED|REJECTED|FAILED)
    pass "7.1 Pipeline reached terminal/transit state: $status"
    ;;
  *)
    fail "7.1 Pipeline status" "stuck in $status"
    ;;
esac

# 7.2 Audit trail has multiple events
audit_count=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT count(*) FROM audit_events WHERE payment_id='$pid'" 2>&1 | tr -d '\r ')
[ "$audit_count" -ge "4" ] && pass "7.2 Audit trail captures ≥4 events ($audit_count)" || fail "7.2 audit" "$audit_count events"

# 7.3 Audit event_types are within CHECK enum (no rejections)
bad_types=$(docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT count(*) FROM audit_events WHERE event_type NOT IN ('PAYMENT_RECEIVED','PAYMENT_VALIDATED','CANONICAL_UPDATED','NORMALIZATION_COMPLETE','ROUTE_DECISION','TRANSLATED','PUBLISHED_TO_QUEUE','ACK_RECEIVED','PIPELINE_ERROR','STATUS_CHANGE','COMPENSATION_STARTED','COMPENSATION_COMPLETED','COMPENSATION_REVERSAL_REQUIRED','WEBHOOK_DELIVERED','WEBHOOK_FAILED','RECONCILIATION_REPORT','DEAD_LETTER','AUDIT_TEST')" 2>&1 | tr -d '\r ')
[ "$bad_types" = "0" ] && pass "7.3 No audit_event with disallowed event_type" || fail "7.3 audit enum" "$bad_types invalid"

bold "=== 8. UI / SSE / METRICS ==="

# 8.1 /metrics endpoint exposes Prometheus
metrics=$(curl $CURL_OPTS "$CORE_URL/metrics" | head -50)
echo "$metrics" | grep -q "mipit_payments_total" \
  && pass "8.1 /metrics exposes mipit_payments_total" \
  || fail "8.1 metrics" "no mipit_payments_total"

# 8.2 SSE endpoint accessible (just verify it responds with 200 + content-type stream)
sse_code=$(curl $CURL_OPTS --max-time 3 -o /dev/null -w "%{http_code}" "$CORE_URL/events/payments")
# SSE either returns 200 (stream open) or 401 (if behind auth)
case "$sse_code" in
  200|401) pass "8.2 SSE endpoint responds ($sse_code)" ;;
  *) fail "8.2 SSE" "got $sse_code" ;;
esac

# 8.3 UI reachable
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "http://localhost:3001/")
[ "$code" = "200" ] && pass "8.3 UI reachable on :3001" || fail "8.3 UI" "got $code"

bold "=== 9. SANITIZE MIDDLEWARE (P08) ==="

# 9.1 Legitimate string with "update" + "form" should NOT be rejected
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: wave1-sanitize-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d '{"amount":50,"currency":"BRL","debtor":{"alias":"PIX-12345678909","name":"Please update the form"},"creditor":{"alias":"SPEI-072123456789012344","name":"X"},"purpose":"P2P","reference":"Update the form please"}')
# Should be 201 (or 200 if idempotent), NOT 400
case "$code" in
  200|201) pass "9.1 Sanitize allows legitimate strings ('update'+'form')" ;;
  400) fail "9.1 Sanitize regression" "rejected legit string with code $code" ;;
  *) fail "9.1 Sanitize" "unexpected code $code" ;;
esac

# 9.2 XSS payload still rejected
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":50,"currency":"BRL","debtor":{"alias":"PIX-12345678909","name":"<script>alert(1)</script>"},"creditor":{"alias":"SPEI-072123456789012344","name":"X"}}')
[ "$code" = "400" ] && pass "9.2 Sanitize still blocks <script>" || fail "9.2 XSS guard" "got $code"

bold "=== 10. INVALID PAYLOADS REJECTED ==="

# 10.1 Invalid CLABE checksum → 400
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":50,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-072123456789012345"}}')
[ "$code" = "400" ] && pass "10.1 Invalid CLABE checksum rejected" || fail "10.1 CLABE validation" "got $code"

# 10.2 Negative amount → 400
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":-5,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-072123456789012344"}}')
[ "$code" = "400" ] && pass "10.2 Negative amount rejected" || fail "10.2 amount validation" "got $code"

# 10.3 Unknown alias prefix → 400
code=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" -X POST "$CORE_URL/payments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"amount":50,"currency":"BRL","debtor":{"alias":"FAKE-xyz"},"creditor":{"alias":"SPEI-072123456789012344"}}')
[ "$code" = "400" ] && pass "10.3 Unknown alias prefix rejected" || fail "10.3 alias validation" "got $code"

bold "=== SUMMARY ==="
printf "\033[1mTotal:\033[0m   $((PASS+FAIL+SKIP))\n"
printf "\033[32mPassed:\033[0m  $PASS\n"
printf "\033[31mFailed:\033[0m  $FAIL\n"
printf "\033[33mSkipped:\033[0m $SKIP\n"

if [ "$FAIL" -gt "0" ]; then
  echo ""
  bold "Failed checks:"
  for r in "${REPORT[@]}"; do
    echo "$r" | grep "^FAIL:" || true
  done
  exit 1
fi
exit 0
