I have enough material. Now writing the forensic audit. Given the user wants a 7000-10000 word report, I'll write it directly as my final answer (per instructions: do NOT write .md report files).

# Adapters â€” Forensic Audit per Rail

## 1. Executive Summary

This forensic audit dissects the three rail adapters (`mipit-adapter-pix`, `mipit-adapter-spei`, `mipit-adapter-breb`) line by line. The three adapters were clearly written from a shared template â€” file layout, worker loop, OAuth2 mock, admin routes and retry helper are near-identical. That symmetry is a strength for maintainability and a weakness for fidelity: every wrong choice in the template (UTC timestamps, `Math.random` ID suffixes, hard-coded OAuth2 secrets, `nack(msg, false, false)` on any error, no W3C TraceContext propagation, no in-flight idempotency cache) is multiplied by three.

Aggregate severity: **6 Critical, 17 High, 30 Medium, 14 Low** new findings beyond what the prior audit captured. The most consequential new findings:

- **(Critical) BREB has no retry helper** â€” `mipit-adapter-breb/src/breb/client.ts` inlines its own exponential backoff (`sleep(200*attempt)`, lines 112â€“114) while PIX and SPEI use `src/<rail>/retry.ts`. There is no `mipit-adapter-breb/src/breb/retry.ts` at all. The metrics counter `brebRetryCount` is declared in `observability/metrics.ts:21-25` but never incremented anywhere. So *retries on Bre-B happen but are invisible to Prometheus*.
- **(Critical) BREB has a broken test import** â€” `mipit-adapter-breb/test/unit/breb-translation.test.ts:6` imports `brebToCanonical` from `../../src/breb/types`. That symbol is not exported (`src/breb/types.ts` only exports `BREB_ENTITY_CODES` and `generateBrebTransactionId`). The test cannot have ever run green; either Jest silently skips it or it errors at module load and is suppressed.
- **(Critical) BREB has zero contract test** â€” no `test/contract/` directory exists. PIX and SPEI both have `test/contract/<rail>-mock.test.ts`. So the OAuth flow, idempotency, llave-format validation and rejection rates of the BanRep mock are exercised by *zero* assertions outside the unit-level mapper.
- **(Critical) PIX worker assigns `source_rail: 'PIX'` to every ack** â€” `mipit-adapter-pix/src/worker.ts:68` (and `mipit-adapter-spei/src/worker.ts:68`, `mipit-adapter-breb/src/worker.ts:71`). This is correct *for the rail this adapter serves* but the prior audit flagged that core deduces `destination_rail` by `source_rail === 'PIX' ? 'SPEI' : 'PIX'` â€” so the BREB adapter writes `source_rail: 'BRE_B'` (constant `RAIL = 'BRE_B'` in `mipit-adapter-breb/src/config/constants.ts:2`) and core's binary swap mis-labels it. This is a *core* bug, not an adapter bug, but the adapter could mitigate by emitting the explicit `destination_rail` it knows from the route message â€” it doesn't.
- **(High) PIX-`source_rail` value mismatch** â€” PIX/SPEI emit `'PIX'`/`'SPEI'` but BREB emits `'BRE_B'` with underscore. Any downstream consumer that splits on `_` or pattern-matches `^[A-Z]+$` will lose Bre-B.
- **(High) SPEI mock has a dead-code branch** â€” `src/spei/mock-server.ts:288-312`. The `settlementDelayMs` async-settlement branch is reachable only inside the `setTimeout` callback for the success path, but it *first* sets the response to `'EN_PROCESO'` and *then* sets it to `'LIQUIDADA'` after another `setTimeout`. The cached idempotency response is `'EN_PROCESO'` for the entire `settlementDelayMs` window. The adapter is then sent `'EN_PROCESO'` which `response-mapper.ts:51-60` maps to **`status: 'ERROR'`** â€” so any caller that uses async settlement guarantees a FAILED ack even though the payment will eventually liquidate. This is a fully wired bug.

The mock-fidelity scores (1 = no fidelity, 5 = swap-base-URL ready): **PIX = 2.5, SPEI = 1.5, Bre-B = 1.0**. None of them is ready for a real-network swap; the gap is largest for SPEI (real STP is RSA-signed SOAP, not OAuth2 JSON) and biggest in honesty terms for Bre-B (the code asserts fidelity to a "BanRep specification v1.0 (2023)" that does not exist â€” BanRep's first technical document is dated February 2026).

The rest of this report walks each adapter file by file, builds endpoint-by-endpoint contract tables, audits every validator, and catalogs cross-adapter duplication.

---

## 2. PIX adapter â€” full walkthrough

### 2.1 File-by-file walkthrough

#### `src/index.ts` (38 lines)

- Calls `initTelemetry()` *first* at module load (lines 1â€“2) â€” correct pattern for OTel auto-instrumentation. **Low**.
- Starts the mock server in-process when `PIX_MODE === 'mock'` (lines 12â€“15). Means the adapter cannot be horizontally scaled in mock mode without two replicas binding the same `PIX_MOCK_PORT` â€” fine for the PoC.
- Shutdown handler (lines 23â€“28) closes the channel but **does not drain in-flight messages**. Since `prefetch(1)` plus `ack` on success, any message currently being sent to the rail will be lost on SIGTERM. **Medium** (`mipit-adapter-pix/src/index.ts:23-28`).
- No SIGHUP handler; no readiness/liveness distinction. **Low**.

#### `src/worker.ts` (117 lines)

- `prefetch(1)` (line 38) â€” appropriate for sequential settlement against a mock with idempotency, but also means a *single slow rail* response blocks the queue. For real production you'd want `prefetch(N)` with concurrent-safe handler. **Low** for PoC.
- `consume` handler is async but `channel.consume` does not await it (line 42). Standard amqplib pattern but the implementation *uses* `await` inside (`startWorker` is async) â€” fine.
- Line 49: `JSON.parse(msg.content.toString())` with `catch` â†’ `channel.nack(msg, false, false)` on invalid JSON. `nack(msg, allUpTo=false, requeue=false)` is correct (sends to DLX). **OK**.
- Line 60: `routeMsg.canonical as any` â€” the canonical type is `Record<string, unknown>` and gets force-cast. The cost: the mapper's `CanonicalPacs008` interface is purely documentary, no runtime Zod schema. A malformed canonical will throw inside `canonicalToPixPayload` and be caught by the outer `catch` â†’ FAILED ack. **Medium** â€” no input validation distinct from rail validation.
- Line 71: `status: railAck.status === 'ACCEPTED' ? 'ACKED_BY_RAIL' : 'REJECTED'`. This loses the distinction between `REJECTED` and `ERROR` from `RailAck`. A status of `'ERROR'` (e.g. `EM_PROCESSAMENTO`) ends up as `'REJECTED'` in the ack, while the inner `rail_ack.status: 'ERROR'` is preserved. The two are inconsistent; consumers reading the outer `status` will treat a timeout as a hard rejection. **High** (`mipit-adapter-pix/src/worker.ts:71`).
- Lines 77 vs 108: `publishAck` happens *before* `channel.ack(msg)` on success and *before* `channel.nack` on failure. Order is correct (ack-after-publish), but neither path waits for a publisher confirm â€” the publisher channel is not a `confirmChannel`. If the broker dies between publish and ack, the ack to ourselves is lost and the message is re-delivered on reconnect, re-publishing the duplicate ack. **High** (and shared across all 3 adapters).
- Lines 79â€“80 record metrics with `status: 'success'` even on `'rejected'` (the label flips between `success`/`rejected`/`error`); but the latency histogram observation always uses `status: 'success'` on the happy path (line 80) â€” even for rejected, it's labeled `'success'`. **Medium** (label mismatch).
- Line 90/104: `latencyMs` recomputed inside the catch. OK.
- Line 102: error code is hardcoded `'ADAPTER_ERROR'` and `message: String(err)` â€” `String(err)` on an Error gives `'Error: <message>'`. The Error stack is dropped. **Low**.
- Line 113: `channel.nack(msg, false, false)` on any caught error â€” even on transient OAuth network failures the message goes to DLQ without retry at the AMQP layer. The retry inside `client.ts` does cover most cases (3 attempts Ã— exponential) but if all retries fail the message is *not requeued*. **High** (`mipit-adapter-pix/src/worker.ts:113`).

#### `src/health-server.ts` (28 lines)

- CORS wildcard (`Access-Control-Allow-Origin: *`, line 9). Acceptable for PoC; not for production. **Low**.
- `/health` (line 14) returns `{status: 'ok', adapter: 'pix'}` unconditionally â€” does not probe RabbitMQ channel state or upstream mock readiness. **Medium** â€” the adapter could be disconnected from RabbitMQ and still respond OK.
- `/metrics` registers `prom-client` registry. Listens on `HEALTH_PORT` default `9101` (matches `prometheus.yml` once the prior audit's prometheus port fix is applied). **OK**.

#### `src/messaging/rabbitmq.ts` (50 lines)

- Module-level mutable `connection`/`channel` (lines 6â€“7) â†’ singleton pattern. Reconnect is **not implemented**. The `'error'` handler logs and the `'close'` handler warns (lines 31â€“37) but neither schedules a reconnect. If RabbitMQ blips the adapter sits dead until restarted. **High** (`mipit-adapter-pix/src/messaging/rabbitmq.ts:31-37`).
- DLX setup (lines 21â€“25): `x-dead-letter-exchange: 'mipit.dlx'`, `x-dead-letter-routing-key: 'dlq.pix'`. The mipit-infra side must declare `mipit.dlx` â€” the adapter does not assert it, so if infra forgets, all DLQ messages are dropped silently by RabbitMQ. **Medium**.
- `'route.pix'` binding (line 27). Hardcoded â€” should ideally be env-driven for multi-env. **Low**.
- Queue is `durable: true` but classic (not quorum). **Low** (prior audit captured).

#### `src/messaging/publisher.ts` (18 lines)

- `channel.publish(exchange, routingKey, payload, { persistent: true, contentType: 'application/json' })`. No `mandatory: true`, no publisher confirms. **High** â€” silent message loss possible.
- No headers, so **no W3C TraceContext (traceparent) propagation**. The OTel SDK started in `index.ts` cannot stitch the trace across the AMQP hop. **High** (matches prior audit) â€” applies identically to SPEI/BREB publishers.
- Logs at `debug` level â€” invisible in production unless `LOG_LEVEL=debug`. **Low**.

#### `src/observability/otel.ts` (22 lines)

- OTLP/HTTP exporter pointing at `${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`. If env var unset, exporter is `undefined` â†’ spans go nowhere but no error. **Low**.
- No metrics SDK, no logs SDK â€” only traces. The `prom-client` metrics live in a parallel registry. So the `/metrics` Prometheus scrape and the OTel traces are *disjoint*; you cannot exemplar-link them. **Medium**.
- `getNodeAutoInstrumentations()` enables all auto-instrumentations including amqplib â€” good. But there's no manual span around `sendPixPayment`. The traces will show generic `fetch` spans without the business context (paymentId/E2E ID as attributes). **Medium**.

#### `src/observability/metrics.ts` (26 lines)

- 3 metrics: `mipit_adapter_pix_payments_total`, `mipit_adapter_pix_payment_latency_ms`, `mipit_adapter_pix_retries_total`. Label cardinality is bounded (`status` âˆˆ {success, rejected, error}). **OK**.
- No metric for OAuth2 token refresh count, no metric for mock-vs-real, no metric for amount distribution. **Low** â€” out of scope for a PoC.

#### `src/observability/logger.ts` (12 lines)

- Pino with ISO timestamps. **No redaction** â€” `info({ payment_id, trace_id }, ...)` is fine, but the mapper logs `endToEndId` and the client logs `endToEndId` (`client.ts:46`). Combined with broader traces, `chave`/`taxId` may leak. **Medium** â€” prior audit captured for core; same gap here.

#### `src/config/env.ts` (40 lines)

- Solid Zod schema. `OTEL_EXPORTER_OTLP_ENDPOINT` is **required** (no default) â€” if you forget it, the adapter exits at boot. Compose probably sets it. **Low**.
- `PIX_TIMEOUT_MS = 10000` default â€” fine. But the timeout is enforced via `AbortController` in `client.ts:42` and reused across the 401-refresh retry â€” same `signal` (lines 55, 69). If the first request consumes 9s of the 10s budget, the refresh request gets <1s, often failing as well. **High** (`mipit-adapter-pix/src/pix/client.ts:55,69` â€” prior audit captured this as a cross-adapter pattern).
- `INSTANCE_ID` defaults to `pix-${process.pid}` â€” PID changes on container restart; ack messages have non-stable identity. **Low**.

#### `src/config/constants.ts` (3 lines)

- `RAIL = 'PIX' as const`, `ADAPTER_ID = 'adapter-pix'`. **OK**.

#### `src/pix/client.ts` (90 lines)

- Module-level mutable `cachedToken` (line 6) â€” singleton OAuth cache. Thread-safe only because Node is single-threaded; under concurrent workers it could refresh redundantly but never racily. **OK**.
- Lines 7â€“36: `getOAuthToken()`. **Hard-coded `client_id: 'mipit-core'` and `client_secret: 'mipit-secret-pix-2024'`** (lines 18â€“19). Per prior audit â€” **High**. Should be env-loaded.
- Line 20: `scope: 'spi.pagamentos'` â€” *invented*. Real BCB scopes are `cob.write cob.read cobv.write cobv.read pix.read pix.write` (per the BCB OpenAPI fetched). The mock OAuth (`oauth-mock.ts:64`) defaults to `'spi.pagamentos'` so the scopes match between adapter and mock â€” but neither matches BCB. **High** (`mipit-adapter-pix/src/pix/client.ts:20`).
- Lines 38â€“88: `sendPixPayment` wrapped in `withRetry`. Issues:
  - Single `AbortController` shared across the original request *and* the 401-refresh retry (lines 41, 55, 69). After a 401, the controller still counts from the original `setTimeout` (line 42). **High** (`mipit-adapter-pix/src/pix/client.ts:55-70`).
  - On 401, the code force-refreshes once but **does not classify 401 as a retry candidate** â€” a *second* 401 throws and burns a `withRetry` attempt. Acceptable but undocumented.
  - On `!res.ok`, `await res.text()` then throws. The retry will fire on *any* non-2xx â€” including `400 ParÃ¢metro invÃ¡lido`. That's a permanent error, but `withRetry` retries 3 times. **High** â€” no 4xx/5xx differentiation. Wastes 7s per dud message (500ms + 1s + 2s = 3.5s of backoff plus 3Ã— the latency).
- Endpoint URL `${PIX_SANDBOX_URL}/spi/v2/pagamentos` (line 40). **Invented**. The real BCB public PIX API exposes `/cob/{txid}`, `/cobv/{txid}`, `/pix/{e2eid}`, etc. There is no public `POST /spi/v2/pagamentos`. SPI is the *back-end* settlement message bus, not an HTTP API; the PSP-facing API is the `/cob` family above. The mock is a fictitious endpoint plausible in shape but not in URL. **High** â€” flag in tesis limitations. (`mipit-adapter-pix/src/pix/client.ts:40`).

#### `src/pix/mapper.ts` (135 lines)

- Round-trip identity is partial. Inbound canonical â†’ PIX payload:
  - Loses: `purpose` (unless reused as `campoLivre`), `reference` (unless `remittanceInfo` absent), `trace_id` (not in PIX wire), creditor `agencia` is included but `creditor.account_id` is dropped (the PIX flow resolves account via DICT from `chave`), `origin.rail/destination.rail` (rail metadata).
  - Adds: `tipo: 'TRANSF'` (hard-coded â€” `tipo` is `'TRANSF' | 'COBR' | 'DBOL'`. `COBR` for QR-code-issued charges and `DBOL` for boletos are never emitted). **Medium** (`mipit-adapter-pix/src/pix/mapper.ts:85`).
  - Adds: `dataHora: new Date().toISOString()` (line 93) â€” **always UTC**. Prior audit captured the EndToEndId fix; same bug here for the wire `dataHora`. **High**.
- FX: `localAmount = canonical.amount.value * fxRate` (lines 38â€“39). The canonical's `fx.rate` is treated as `source_currency â†’ BRL`. But the canonical schema has *no field* for the target currency the adapter should send. **It's assumed that `fxRate` is canonicalâ†’BRL.** If the core ever sends `fxRate` in the wrong direction (USDâ†’MXN for example) the value is garbage. **Medium** â€” passive contract.
- Line 50: `ispb.padStart(8, '0')` â€” defensive padding. Good.
- Lines 43â€“44: strips `PIX-` prefix from `debtor.account_id` and `alias.value || creditor.account_id`. The triple-strip pattern the prior audit called out is alive here.
- `inferPixKeyType` (lines 107â€“113): regexes match BCB DICT spec for CPF/CNPJ/PHONE/EMAIL/EVP. But:
  - The EVP branch is the default fallback for *anything* not matching. So a malformed key like `"foo bar"` is labeled `EVP` and sent to the rail. **Medium** (`mipit-adapter-pix/src/pix/mapper.ts:112`).
  - PHONE regex is `^\+55\d{10,11}$` â€” Brazilian fixed numbers are 10 digits, mobile 11. Both pass. OK.
  - EMAIL regex permits Unicode in localpart. OK.
  - EVP must be UUIDv4 per DICT â€” the adapter does not validate, just labels. **Medium**.
- `buildPixIdentity` (lines 116â€“122): strips non-digits, distinguishes CPF (11) vs CNPJ (14) by length. **No checksum.** Prior audit captured. **High**.
- `extractAccountNumber` (lines 129â€“134): regex `/^\d{5,12}-?\d?$/` for account-like strings, otherwise placeholder `'000001-0'`. The placeholder is the same for every payment if the chave isn't a CPF â€” so the *pagador's* account number is constant. PIX SPI rejects ambiguous accounts; in real life the PSP knows the pagador's account (the customer is the PSP's user). The placeholder is a tell that the adapter doesn't really know the pagador. **Medium** â€” defensible PoC limitation.

#### `src/pix/response-mapper.ts` (74 lines)

- Four-branch switch on `response.status`. All four statuses match the spec (`CONCLUIDA`/`NAO_REALIZADA`/`DEVOLVIDA`/`EM_PROCESSAMENTO`). **OK**.
- `EM_PROCESSAMENTO â†’ status: 'ERROR'` (line 54). The semantics are weird: if the SPI is *still processing*, the correct response is to *poll* (the mock supports `GET /spi/v2/pagamentos/:endToEndId`, line 308). Currently the adapter treats pending as an adapter timeout, ack-FAILED, message acked, and abandons the rail-side state. The payment may eventually settle and the core never finds out. **High** (`mipit-adapter-pix/src/pix/response-mapper.ts:51-60`).
- `rail_tx_id` fallback to `endToEndId` (line 19) â€” sensible.
- `raw_response` is cast through `as unknown` then `as Record<string, unknown>` â€” fine, but the type assertion is repeated 4Ã— verbatim. **Low**.

#### `src/pix/types.ts` (188 lines)

- Comprehensive interface definitions. The EndToEndId comment (line 5) says `E + ISPB(8) + AAAAMMDD + HHmm + 11 chars`. Matches BCB *form*.
- `generatePixEndToEndId` (lines 182â€“188):
  - Line 183: `new Date()`.
  - Line 184: `slice(0, 10).replace(/-/g, '')` over `toISOString()` â†’ **UTC date**.
  - Line 185: `slice(11, 16).replace(':', '')` over `toISOString()` â†’ **UTC time**.
  - Line 186: `Math.random().toString(36).substring(2, 13).toUpperCase().padEnd(11, '0')` â€” `toString(36)` gives `[a-z0-9]`, after `toUpperCase()` becomes `[A-Z0-9]`, but the suffix can be shorter than 11 chars when the random number happens to be small (`0.0001.toString(36) = '0.00ds3o2'`). Then `padEnd(11, '0')` pads to 11. The padding can *degrade* the entropy to a few leading chars + `0`s. Birthday collision on 11 chars of `[A-Z0-9]` is ~36^5.5 â‰ˆ 1B; padded down to 8 effective chars it's 36^4 â‰ˆ 1.7M. For 10k tx/day, a collision day every ~170 days. **Medium** (`mipit-adapter-pix/src/pix/types.ts:186`).
- ISPB table (lines 167â€“176): real values (BB, Bradesco, ItaÃº, etc.) plus `MIPIT_SIMULATED: '26264220'`. Nubank and Inter included â€” fine. The simulated ISPB is not in BACEN's directory; OK for PoC if documented.

#### `src/pix/retry.ts` (29 lines)

- `for (let attempt = 1; attempt <= maxRetries; attempt++)` â€” attempt count off-by-one **semantics**. With `maxRetries=3`, the loop runs 3Ã— total (not 1 + 3 retries). The variable name says "max retries" but it's "max attempts". **Medium** â€” confusing but consistent across files.
- `baseDelayMs = 500`, exponential `delay = base * 2^(attempt-1)`. Schedule: 500, 1000, 2000ms before attempts 2/3/4. **No jitter.** **Medium** â€” thundering-herd risk under broker failover.
- No retry classification by error type â€” every throw retries. Mirrors the `client.ts` issue.

#### `src/pix/mock-server.ts` (394 lines)

Validators per field (line numbers):
- `endToEndId` regex `^E\d{8}\d{8}\d{4}[A-Z0-9]{11}$` (line 110). Accepts uppercase only â€” would reject the BCB-allowed mixed case. The mapper happens to also emit uppercase. **Medium**.
- `valor.original` regex `^\d+\.\d{2}$` (line 120). Strict 2-decimal. Good.
- `amountValue > 0` and `â‰¤ 999_999_999.99` (lines 131, 138). Spec doesn't define a max but this is plausible.
- `chave` non-empty (line 145).
- `chave` format per `tipoChave` (line 154) via `CHAVE_VALIDATORS` (lines 57â€“63): CPF `\d{11}`, CNPJ `\d{14}`, PHONE `\+55\d{10,11}`, EMAIL, EVP UUIDv4. **No checksums on CPF/CNPJ.** **High** (prior audit).
- `tipo` enum `['TRANSF', 'COBR', 'DBOL']` (line 164).
- SPI window (lines 72â€“82). `ENFORCE_HOURS` default `'false'` so it never trips in PoC.
- PIX Noturno limit (lines 88â€“92). Same gate.
- Idempotency map keyed by `endToEndId` (line 51); duplicate returns cached response with HTTP 200. Real SPI returns 200 for both first and replay; OK.
- Admin force-reject / force-timeout (lines 201â€“219). Force-timeout sleeps 30s then 504. Pointless because `PIX_TIMEOUT_MS = 10000` aborts at 10s â€” but the `setTimeout` keeps running server-side. **Low**.
- Random rejection ladder (lines 222â€“258): five buckets at `rate*0.4`, `*0.6`, `*0.8`, `*0.9`, `*1.0`. Codes AM04/AC01/RR04/BE01/DS04. The *first* bucket (`rate*0.4`) **doesn't increment `mockStats.totalRejected`** (line 226 has no `mockStats.totalRejected++`) â€” the other four do. **Low** (`mipit-adapter-pix/src/pix/mock-server.ts:222-230`).
- Success path: latency = `mockConfig.minLatencyMs + Math.random() * (max - min)` (line 261). Builds `PixSpiPaymentResponse` with `txid: body.idConciliacao` (line 269) â€” the *request's* `idConciliacao` is echoed back as `txid`. Real DICT `txid` is a separate identifier. **Medium** (semantic re-use).
- Legacy endpoint `POST /pix/payments` (lines 334â€“359). Used by the contract test. Lower-quality validator and accepts numeric `valor`. Considered backward-compat shim.

#### `src/pix/oauth-mock.ts` (110 lines)

- Real BCB requires OAuth2 client_credentials **plus mTLS with ICP-Brasil cert**. Mock skips mTLS entirely. The code comment (lines 5â€“10) is honest about this.
- `VALID_CLIENTS` (lines 24â€“27) hard-coded; `mipit-core` and `mipit-test`. **Medium** â€” secrets in source.
- Token TTL 3600s; in-memory `activeTokens` map never cleans expired entries (line 31). Memory grows monotonically. **Low** for PoC.
- Default scope on issue: `'spi.pagamentos'` (line 64) â€” matches the client's invented scope. **High** (prior audit).
- Middleware skips `/health`, `/oauth`, `/admin` (line 81). `/admin` being unauth means the UI dashboard can flip the kill-switch without creds. **High** (`mipit-adapter-pix/src/pix/oauth-mock.ts:81`).
- Token entropy: 32 bytes hex from `crypto.randomBytes`. Strong.

#### `src/pix/admin-routes.ts` (109 lines)

- 6 endpoints: GET config, POST config, POST reject-next, POST timeout-next, POST reset, GET stats.
- `MOCK_REJECTION_RATE` env var read (line 31) with sensible default 0.10. Clamping (lines 39â€“44) is defensive. **OK**.
- `forceRejectCode` mutable via POST `/admin/config` â€” any string. The mock doesn't validate it against the BACEN code set. **Low**.
- `mockConfig` is module-singleton; multi-instance deployment would have inconsistent admin state across replicas. **Medium**.

#### Tests

- `test/unit/mapper.test.ts` (218 lines): 9 cases. Verifies E2E ID matches BCB regex, FX conversion math, key-type inference for CPF/CNPJ/PHONE/EMAIL, prefix-strip, `campoLivre` truncation, default names, taxId mapping, emailâ†’`infoAdicional`, decimal rounding. *Does not test* the UTC-vs-BRT timezone bug, EVP key generation, CNPJ checksum, or `dataHora` field. **Medium** â€” coverage holes match the bug list.
- `test/unit/response-mapper.test.ts` (139 lines): 7 cases. All four statuses + fallback. Good coverage of the function as written; doesn't notice that EM_PROCESSAMENTO â†’ ERROR is semantically wrong.
- `test/unit/retry.test.ts` (54 lines): 5 cases. Tests success-first, retry-then-succeed, exhaust-retries, metric inc, default baseDelay. **Does not test** that retries fire on 4xx (which would catch the "retry on permanent error" bug if asserted).
- `test/unit/worker.test.ts` (145 lines): 6 cases. Mocks every dependency; tests prefetch=1, consume from queue, happy-path ack, invalid-JSON nack, null msg, error-path nack+FAILED ack. **Doesn't assert TraceContext header propagation** (which is missing), or that `source_rail` is `'PIX'` (just verifies `status: 'success'` metric). The mock returns a *string* `status: 'ACCEPTED'` from `pixResponseToAck`, then the assertion is `expect(pixPaymentsTotal.inc).toHaveBeenCalledWith({ status: 'success' })` â€” passes for the wrong reason.
- `test/unit/publisher.test.ts` (111 lines): 3 cases. Verifies exchange/routing key/persistent. Doesn't assert *absence* of confirms, doesn't assert headers â€” placeholder coverage.
- `test/unit/health-server.test.ts` (43 lines): 2 cases. GET /health returns ok, GET /metrics returns prom text. **Doesn't probe that the adapter is actually healthy** (because the endpoint doesn't either).
- `test/unit/spi-mapper.test.ts` (197 lines): 16 cases. Extensive cover of `generatePixEndToEndId` shape, but never compares the embedded date to local-time-BRT vs UTC â€” the bug skates through.
- `test/contract/pix-mock.test.ts` (210 lines): 6 cases. Tests health, OAuth happy-path, payment with token, simulated failures, idempotency by EndToEndId echo, numeric valor backward-compat. Uses `endToEndId: 'E1234567820260413120501234567890'` â€” note the year `2026` and the trailing `01234567890` (digits not alphanumeric). The legacy endpoint isn't strict about the suffix, so it passes; the strict endpoint would fail.

### 2.2 PIX endpoint contract audit

| Endpoint | Real spec | Our mock | Match? | Notes |
|---|---|---|---|---|
| `POST /spi/v2/pagamentos` | **Does not exist as public API.** BCB exposes `POST /cob` and `PUT /cob/{txid}` for PSP-side. SPI itself is XML over RSFN, not HTTP. | `POST /spi/v2/pagamentos` returning `PixSpiPaymentResponse` | âŒ | The URL is plausible-sounding but invented. **Critical** for fidelity. |
| `GET /spi/v2/pagamentos/:endToEndId` | Maps to `GET /pix/{e2eid}` on real PIX API. | `GET /spi/v2/pagamentos/:endToEndId` returns cached response | âš ï¸ | Path differs from real `/pix/{e2eid}`. **High**. |
| `POST /oauth/token` | BCB uses certificate-bound OAuth2 with mTLS. Token endpoint URL varies per PSP. | Standard client_credentials w/o mTLS | âš ï¸ | Auth pattern simplified. **High** (prior). |
| `POST /pix/payments` (legacy) | N/A â€” internal shim | Legacy testkit endpoint | N/A | Should be deleted. **Low**. |
| `GET /health` | N/A | OK | N/A | Mock-only. |
| `GET/POST /admin/*` | N/A | Mock controls | N/A | Should be auth-gated. **High**. |

Real BCB endpoints absent from our mock: `/cob/{txid}`, `/cob`, `/cobv/{txid}`, `/loc`, `/loc/{id}`, `/pix/{e2eid}`, `/pix/{e2eid}/devolucao/{id}`, `/webhook/{chave}`, `/lotecobv/{id}`. Not having these is defensible (PoC scope is SPI settlement, not QR-code charge management), but the docs should make this explicit.

### 2.3 PIX field-by-field validation audit

| Field | Mock validator | BCB spec | Strict enough? |
|---|---|---|---|
| `endToEndId` | `^E\d{8}\d{8}\d{4}[A-Z0-9]{11}$` | `E + ISPB + AAAAMMDD + HHmm + 11 alnum (case-insensitive)` | Too strict (rejects lowercase). **Medium**. |
| `valor.original` | `^\d+\.\d{2}$` | 2-decimal monetary string | **Match**. |
| amount range | `0 < x â‰¤ 999_999_999.99` | Spec floor 0.01, no explicit max | Reasonable. |
| `chave` (CPF) | `\d{11}` | `\d{11}` + mod-11 checksum | Too lax (no checksum). **High**. |
| `chave` (CNPJ) | `\d{14}` | `\d{14}` + mod-11 dual checksum | Too lax. **High**. |
| `chave` (PHONE) | `^\+55\d{10,11}$` | `+55` + DDD + 8-9 digits | OK. |
| `chave` (EMAIL) | RFC-light | RFC 5321 | OK. |
| `chave` (EVP) | UUIDv4 | UUIDv4 | OK. |
| `tipo` | `['TRANSF', 'COBR', 'DBOL']` | Same enum | OK. |
| `pagador.ispb` | not validated in mock | 8-digit BACEN ISPB code | Missing. **Medium**. |
| `idConciliacao` | not validated | 26â€“35 alnum, mandatory for COBR | Missing. **Medium**. |
| `dataHora` | not validated | ISO 8601 | Missing. **Low**. |
| `infoAdicional[].nome/valor` | not validated | max 50/200 chars, max 50 entries | Missing. **Low**. |

### 2.4 PIX OAuth2 audit

Real BCB: OAuth2 **client_credentials** + **mTLS** with ICP-Brasil cert. Scopes are per-resource: `cob.read cob.write cobv.read cobv.write pix.read pix.write lotecobv.read lotecobv.write webhook.read webhook.write payloadlocation.read payloadlocation.write`. Tokens are *certificate-bound*: the cert used in mTLS must match the cert that was presented at token issuance.

Our mock: plain client_credentials, no mTLS, scope `'spi.pagamentos'` (invented), no cert-binding.

Severity: **High**, but acknowledged in the source comments (`oauth-mock.ts:5-10`). Defensible for PoC but document explicitly in the thesis.

### 2.5 PIX worker reliability audit

| Aspect | State | Severity |
|---|---|---|
| Prefetch | `1` | OK |
| Ack on success | After publishAck (no confirm) | High |
| Nack on parse error | `nack(false, false)` â†’ DLQ | OK |
| Nack on processing error | `nack(false, false)` â†’ DLQ (no retry) | High |
| DLQ routing | `dlq.pix` via `mipit.dlx` | OK |
| Idempotency on retry | None at adapter; mock has E2E-ID map | High (adapter side) |
| Channel reconnection | **None** â€” connection events only log | High |
| Graceful shutdown | Closes channel, no drain | Medium |
| TraceContext propagation | None | High |

### 2.6 PIX mapper round-trip

Inbound canonical â†’ PIX request â†’ mock response â†’ ack:
- **Lost going out:** `purpose` (if `remittanceInfo` set), `reference` (same), `trace_id`, `payment_id` past 35-char truncation, `origin.rail`/`destination.rail`, `fx.source_currency`, accountType beyond `'CACC'`.
- **Added going out:** `tipo: 'TRANSF'`, `tipoCuentaBeneficiario` always `CACC`, `dataHora` synthesized as UTC ISO, EndToEndId generated, `idConciliacao` from payment_id.
- **Coming back:** `id`, `txid` (echoed from `idConciliacao`), `horario` (UTC ISO), `status`, mirrored `pagador`/`recebedor`. None of `motivo`, `codigoErro`, `mensagemErro` exists on success.
- **Lost in ack:** the entire `pagador`/`recebedor` block (only the raw_response carries it), `horario` (replaced by `processed_at = new Date().toISOString()` adapter-side).

The "settlement time" the user sees is the *adapter's* `Date.now()`, not the rail's `horario`. **Medium** drift â€” same as for SPEI/BREB.

### 2.7 PIX retry/backoff

| Aspect | Value | Severity |
|---|---|---|
| Base delay | 500ms | OK |
| Max delay | 2s (3 attempts Ã— 2^(n-1)) | OK |
| Jitter | None | Medium |
| Max attempts | 3 (var named `maxRetries`) | OK semantically; naming Low |
| Per-error-class differentiation | None â€” 4xx retried | High |
| Idempotency-key-safe? | Yes (EndToEndId reused) | OK |

### 2.8 PIX mock fidelity score

**2.5/5**. Strong: idempotency, full BACEN code set, validates by tipoChave, configurable rejection & latency, admin controls. Gaps: invented endpoint URL, no mTLS, invented scope, no CPF/CNPJ checksums, UTC-instead-of-BRT in generated IDs, EVP not validated as UUIDv4 in mapper, `dataHora` UTC, `txid` semantically wrong.

---

## 3. SPEI adapter â€” full walkthrough

### 3.1 File-by-file walkthrough

#### `src/index.ts` (38 lines)

Mirror image of PIX. Same gaps (no graceful drain, in-process mock). **Same Medium**.

#### `src/worker.ts` (117 lines)

Identical structure to PIX. Same High findings:
- `status: 'ACCEPTED' ? 'ACKED_BY_RAIL' : 'REJECTED'` collapses ERROR into REJECTED (line 71).
- `nack(false, false)` on error (line 113) â€” no retry on transient.
- No publisher confirms.
- The `publishAck(channel, failAck )` has a quirky space before `)` (lines 77, 108) â€” stylistic noise. **Low**.

#### `src/health-server.ts` (28 lines)

Identical to PIX (`adapter: 'spei'`). Same Medium re. health-probe shallowness.

#### `src/messaging/rabbitmq.ts` and `publisher.ts`

Identical to PIX modulo routing key strings. Same High findings.

#### `src/observability/*`

Identical structure, `mipit_adapter_spei_*` metric names. **OK**.

#### `src/config/env.ts` (40 lines)

- `HEALTH_PORT` default `9102` (vs PIX `9101`). Matches the prior audit's port-fix recommendation.
- `SPEI_TIMEOUT_MS` default 10s.
- `QUEUE_NAME` default `payments.route.spei`, `ACK_ROUTING_KEY` default `ack.spei`.

#### `src/spei/client.ts` (89 lines)

- Same OAuth pattern. Hard-coded `client_id: 'mipit-core'`, `client_secret: 'mipit-secret-spei-2024'`, `scope: 'spei.transferencias'` (invented; STP doesn't use OAuth at all â€” it's RSA-signed SOAP).
- Same shared `AbortController` bug across 401 refresh (lines 41, 55, 68).
- Same retry-on-4xx bug.
- Endpoint URL `${SPEI_SANDBOX_URL}/spei/v3/transferencias` (line 40) â€” invented; real STP uses SOAP at `https://demo.stpmex.com:7024/speiws/rest/...`.
- **(High) STP authentication is RSA-PKCS#1 v1.5 + SHA-256 on a pipe-joined canonical string of selected fields** (`empresa|claveRastreo|conceptoPago|cuentaBeneficiario|cuentaOrdenante|institucionContraparte|institucionOperante|monto|nombreBeneficiario|nombreOrdenante|referenciaNumerica|rfcCurpBeneficiario|tipoCuentaBeneficiario|tipoCuentaOrdenante|tipoPago`). Our client signs **nothing**. Same as prior audit; flagged here for completeness â€” Critical for swap-fidelity.

#### `src/spei/mapper.ts` (112 lines)

- Lines 36â€“38: FX same shape as PIX. Same passive contract.
- Line 41: strip `SPEI-` prefix from `alias.value`/`creditor.account_id`. Triple-strip pattern.
- Line 45: `validateClabeDetailed(clabeDestino)` â†’ throws on invalid. Good â€” CLABE checksum runs at the adapter, before the rail.
- Lines 53â€“55: Institution code is `canonical.destination.institutionCode ?? clabeBankCode` where `clabeBankCode = clabeDestino.substring(0, 3)`. **3-digit code derived from CLABE bank prefix.** Real Banxico SPEI participant codes are **5 digits** (e.g. `40072` Banorte, `40012` BBVA, `90646` STP). The 3-digit code is the CLABE bank prefix, which *maps to* a 5-digit Banxico code via a published table â€” but the adapter sends the 3-digit form verbatim. Real STP rejects. Prior audit captured. **Critical** (`mipit-adapter-spei/src/spei/mapper.ts:53-55`).
- Line 65: `generateSpeiClaveRastreo('MIPIT')`. Looking at `types.ts:171-175`:
  ```
  generateSpeiClaveRastreo(prefix='MIPIT'):
    date = YYYYMMDD (UTC slice)
    seq = Math.floor(Math.random()*99999999).padStart(8, '0')
    return `${prefix}${date}${seq}`.substring(0, 30)
  ```
  Length is `5 + 8 + 8 = 21` â‰¤ 30. Chars: `M,I,P,T,0-9`. **No hyphen** here, so unlike the prior audit's claim about core's `E2E-${ulid()}`, the *adapter* generates a clean clave. But the *core* sends `endToEndId = E2E-${ulid()}` as `claveRastreo` per the prior audit. The adapter generates its own and discards core's â€” so the trace ID continuity is broken. **High** (`mipit-adapter-spei/src/spei/mapper.ts:65`). The `payment_id` linkage survives via `folioOrigen` (line 71).
- Line 68: `fechaOperacion = new Date().toISOString().slice(0, 10).replace(/-/g, '')` â†’ **UTC date**. Same TZ bug as PIX. Banxico expects Mexico City time (UTC-6/UTC-5 DST). **High**.
- Line 82: `tipoPago: 1` hard-coded. The full Banxico catalog has 31 values. **High** (prior).
- Line 83: `tipoCuentaBeneficiario: 40` hard-coded â€” CLABE. The adapter never sends `3` (debit card), `10` (phone) or `99` (free). **Medium**.
- Lines 91â€“95: optional creditor email and `rfcCurpBeneficiario` truncation to 18 chars. RFC max is 13, CURP max is 18 â€” truncating an RFC to 18 is harmless but truncating a CURP at 18 also truncates the check digit (18-th char). **Medium** (`mipit-adapter-spei/src/spei/mapper.ts:95`).
- Lines 102â€“105: ordering party only included when `clabeOrigen` is exactly 18 digits. If the debtor account is anything else, the adapter silently drops the ordering party. STP requires `cuentaOrdenante` for traceable transfers. **Medium**.

#### `src/spei/response-mapper.ts` (74 lines)

- Same 4-branch switch, mirror of PIX. `LIQUIDADA`/`RECHAZADA`/`DEVUELTA`/`EN_PROCESO`. `EN_PROCESO â†’ status: 'ERROR'` same semantic bug.
- `rail_tx_id = response.folioControl ?? response.claveRastreo` (line 19). Reasonable.
- No special handling for the `settlementDelayMs` async-settle return â€” see the dead-code interaction below.

#### `src/spei/types.ts` (181 lines)

- `SPEI_BANXICO_CODES` (lines 156â€“168): **3-digit codes** (`'002'`, `'006'`, `'012'`, etc.) labeled `BANXICO codes`. They are CLABE bank prefixes, not Banxico SPEI participant codes. The constant is *named wrong*. **High** (`mipit-adapter-spei/src/spei/types.ts:156-168`).
- `'MIPIT_SIM': '999'` â€” `999` is in the CLABE bank-code reserved range (typically 600â€“999 are non-bank PSPs/CECOBAN test codes). Plausible PoC choice.
- `generateSpeiReferencia` (lines 178â€“180): `Math.floor(Math.random() * 9999999)` â†’ returns 0â€¦9_999_998 (off-by-one â€” `Math.random()` is `[0,1)`, `*9999999` is `[0, 9999999)`, floor is `[0, 9999998]`). The mock validator accepts `0`. **Low**.
- `generateSpeiClaveRastreo` (lines 171â€“175): see above.

#### `src/spei/clabe-validator.ts` (126 lines)

**This file is the gem of the adapter.** Properly implements:
- Mod-10 weighted (3,7,1) algorithm (lines 16, 31â€“38).
- Component extractors (`getClabeBankCode`, `getClabeCity`, `getClabeAccount`).
- Detailed error classification (`INVALID_FORMAT`/`INVALID_LENGTH`/`INVALID_CHECK_DIGIT`).
- Test-CLABE builder (`buildTestClabe`) used heavily by tests.

Code is clean, validator is correct (I verified against `032180000118359719` in head). **Low** issue: the `INVALID_FORMAT` branch (line 107) checks `!/^\d+$/.test(clabe)` *before* checking length, so a 17-digit string returns `INVALID_LENGTH` while a 17-digit string + a letter returns `INVALID_FORMAT`. Consistent for our purposes.

#### `src/spei/retry.ts` (29 lines)

Identical to PIX retry. Same off-by-one naming, no jitter, no error classification.

#### `src/spei/mock-server.ts` (427 lines)

- `ENFORCE_HOURS` env (line 45) â€” default false. Window 07:00â€“17:30 CST (line 72). Banxico's real window is **06:00 to 17:55 CT** with a final settlement cut-off ~18:00 per Circular 14/2017. Mock is 1h tighter at the start and 25min tighter at the end. **Medium**.
- `RFC_REGEX` (line 53): `[A-ZÃ‘&]{3,4}\d{6}[A-Z0-9]{3}` â€” RFC form, no checksum.
- `CURP_REGEX` (line 56): standard 18-char layout with gender H/M, no checksum.
- `claveRastreo` validator: `^[A-Z0-9a-z\-_]{1,30}$` (line 109). **Accepts hyphen and underscore**, which real CECOBAN does NOT (alphanumeric only). Prior audit captured. **Critical** (`mipit-adapter-spei/src/spei/mock-server.ts:109`).
- `monto` validations (lines 118â€“132). OK.
- `referenciaNumerica` accepts 0 (line 136). Real CECOBAN treats 0 as sentinel. **Medium**.
- `conceptoPago` length 39 (line 146). Per spec. OK.
- RFC/CURP regex check (lines 155â€“168). Either pattern accepted. No checksum.
- `institucionContraparte` regex `^\d{3,5}$` (line 171) â€” accepts both 3-digit (wrong) and 5-digit (right) formats. So a properly-configured 5-digit code would also pass â€” but the *mapper* doesn't emit 5-digit. **High**.
- CLABE validation when `tipoCuentaBeneficiario === 40` (lines 180â€“188). Good.
- SPEI window (lines 191â€“196). Conditional on `ENFORCE_HOURS`.
- Admin: enabled / reject-next / timeout-next (lines 203â€“229). Same pattern as PIX.
- **The dead-code/bug**: `settlementDelayMs` (lines 288â€“312). When `settlementDelayMs > 0` (configurable via admin):
  - First `setTimeout` (lines 262, 272) fires after `latency` ms; inside it, if `settlementDelayMs > 0`, the mock writes a `pending` (EN_PROCESO) response into `processedTransfers`, returns HTTP 202 with the pending body, then schedules another `setTimeout` to *update* `processedTransfers` with `LIQUIDADA` after `settlementDelayMs` ms.
  - **The adapter receives 202 with body `estatus: 'EN_PROCESO'`. `response-mapper.ts` maps that to `status: 'ERROR'`. The worker emits a FAILED ack and `nack`s the message.**
  - Meanwhile, the mock will eventually flip to `LIQUIDADA` but the adapter has already given up and abandoned the trace.
  - **Critical** (`mipit-adapter-spei/src/spei/mock-server.ts:288-312`). The async-settlement feature is broken end-to-end.
- Random rejection ladder (lines 232â€“267): R01/R03/R02/LIM/R05. Same `totalRejected++` missing in the first bucket pattern as PIX. **Low**.
- Success: builds `LIQUIDADA` response with `folioControl: CECOBAN${ulid().substring(0,10)}` (line 276) â€” fine. `horaLiquidacion: now.toTimeString().slice(0, 8)` (line 275) â†’ uses **server local time** (host's timezone). On a Docker container running UTC this is UTC; on a Mac in CST this is CST. Non-deterministic. **Medium**.
- Legacy `POST /spei/payments` (lines 343â€“383): backward-compat. Returns `estatus: 'ACEPTADO'|'RECHAZADO'`. Used by contract test.

#### `src/spei/oauth-mock.ts` (110 lines)

Identical pattern to PIX. Default scope `'spei.transferencias'`. Same issues:
- Admin endpoints unauth'd (line 81).
- Hard-coded `mipit-core` / `mipit-secret-spei-2024`.
- Token map never expires.

#### `src/spei/admin-routes.ts` (115 lines)

Identical pattern to PIX plus `settlementDelayMs` knob (lines 22, 74â€“76). The dead-code interaction means setting this via admin produces broken FAILED acks â€” **the UI dashboard exposes a footgun** if the user toggles it.

#### Tests

- `test/unit/mapper.test.ts` (152 lines) and `test/unit/cecoban-mapper.test.ts` (164 lines): heavy overlap â€” both test the same mapper. `cecoban-mapper.test.ts` is the more thorough one (uses `buildTestClabe` for valid CLABEs). Asserts CLABE check-digit validation works, FX, prefix-strip, etc. **Does not test** the institutionCode 3-vs-5 digit issue, the UTC date bug, or the `claveRastreo` hyphen issue.
- `test/unit/clabe-validator.test.ts` (191 lines): excellent coverage of the validator. Includes edge cases (all-zeros valid because check=0, wrong-check-digit, non-digit chars, multiple bank CLABEs).
- `test/unit/response-mapper.test.ts`, `worker.test.ts`, `publisher.test.ts`, `retry.test.ts`, `health-server.test.ts`: mirror PIX.
- `test/contract/spei-mock.test.ts` (174 lines): tests OAuth, payment-with-token, CLABE format, error code on rejection, simulated failures. **Does not test** the `settlementDelayMs` async settlement (would catch the bug), the strict `/spei/v3/transferencias` endpoint (only tests `/spei/payments` legacy), or any field-level rejection except CLABE.

### 3.2 SPEI endpoint contract audit

| Endpoint | Real spec | Our mock | Match? | Notes |
|---|---|---|---|---|
| `POST /spei/v3/transferencias` | STP exposes SOAP `registraOrden` over WSDL at `:7024/speiws`. No REST `/spei/v3/transferencias`. | Returns `SpeiCecobanResponse` JSON | âŒ | URL invented; protocol differs (REST vs SOAP). **Critical**. |
| `GET /spei/v3/transferencias/:claveRastreo` | STP `consultaOrden`/`consultaOrdenes` | Returns cached response | âš ï¸ | Path differs. |
| `POST /oauth/token` | **STP doesn't use OAuth** â€” RSA-signed SOAP | client_credentials | âŒ | **Critical** authentication mismatch. |
| `POST /spei/payments` (legacy) | N/A | Compatibility shim | N/A | Remove. |
| `GET /health` | N/A | OK | N/A | |
| Admin endpoints | N/A | Unauth | High | Unauth admin. |

### 3.3 SPEI field-by-field validation audit

| Field | Mock validator | Banxico/STP spec | Match? |
|---|---|---|---|
| `claveRastreo` | `^[A-Z0-9a-z\-_]{1,30}$` | `^[A-Za-z0-9]{1,30}$` (no `-`, no `_`) | Too lax. **Critical**. |
| `monto` | `0 < x â‰¤ 999_999_999.99` | `> 0`, max varies per session | OK. |
| `referenciaNumerica` | `0 â‰¤ x â‰¤ 9_999_999` | `1 â‰¤ x â‰¤ 9_999_999` (some sources) | Allows 0. **Medium**. |
| `conceptoPago` | `length â‰¤ 39` ASCII-tolerant | 39 char, ASCII-printable, no diacritics | Lax. **Medium**. |
| `tipoPago` | not validated by mock | enum of 31 values | Missing. **High**. |
| `tipoCuentaBeneficiario` | not validated | 3/10/40/99 | Missing. **Medium**. |
| `institucionContraparte` | `\d{3,5}` | CatÃ¡logo Banxico 5-digit | Lax. **Critical**. |
| `rfcCurpBeneficiario` | RFC or CURP regex | + checksum | No checksum. **Medium**. |
| `cuentaBeneficiario` (CLABE) | mod-10 check via validator | Same | OK. |
| `nombreBeneficiario` | not length-validated in mock | â‰¤ 39 chars per CECOBAN | The mapper truncates; mock doesn't enforce. **Low**. |
| `empresa` | not validated | â‰¤ 6 chars Banxico-registered | Missing. **Low**. |
| `fechaOperacion` | not validated | YYYYMMDD = current operating day | Missing. **Low**. |

### 3.4 SPEI OAuth2 audit

Real STP uses **RSA-PKCS#1 v1.5 + SHA-256** signatures on a pipe-joined canonical string of order fields. The signature is sent as a `firma` field alongside the order. There is **no OAuth, no Bearer token, no token endpoint**. The connection is also SOAP over TLS, with no certificate-binding requirement.

Our mock implements OAuth2 client_credentials. **Critical mismatch.** This is the single biggest hole in any of the three rails â€” for PIX the auth is wrong-ish (no mTLS) but the *shape* matches; for SPEI the entire auth paradigm is wrong.

### 3.5 SPEI worker reliability audit

Same matrix as PIX. **Additional finding**: the settlementDelayMs mode (admin-controllable) breaks the worker flow â€” see Â§3.1 mock-server.

### 3.6 SPEI mapper round-trip

- **Lost going out:** `purpose` (unless used for `concepto`), `reference`, `trace_id`, `created_at`, `origin.rail/destination.rail`, `fx.source_currency`.
- **Discarded by adapter from canonical:** `payment_id` past 19-char `folioOrigen` truncation, alias.type beyond CLABE.
- **Added:** `claveRastreo` (new, no link to `endToEndId`), `tipoPago = 1`, `tipoCuentaBeneficiario = 40`, `iva = 0`, `empresa = 'MIPIT'`.
- **Coming back:** `estatus`, `monto`, `fechaOperacion`, optional `horaLiquidacion`, `folioControl`.
- **Lost in ack:** `monto`, `iva`, `folioControl` survives as `rail_tx_id`. The horaLiquidacion never reaches core.

### 3.7 SPEI retry/backoff

Identical to PIX. Same Highs.

### 3.8 SPEI mock fidelity score

**1.5/5**. Strong CLABE validator is the only real-spec adherence. Weak: invented endpoint URL, invented protocol (REST vs SOAP), invented auth (OAuth vs RSA-signed), 3-digit institution codes, async-settle bug, no checksums on RFC/CURP, claveRastreo permits forbidden chars.

---

## 4. Bre-B adapter â€” full walkthrough

### 4.1 File-by-file walkthrough

#### `src/index.ts` (38 lines)

Mirror image of PIX/SPEI. Same Medium re. graceful shutdown.

#### `src/worker.ts` (119 lines)

Functional mirror, with two diffs:
- Line 83: `brebPaymentLatency.observe({ status: railAck.status === 'ACCEPTED' ? 'success' : 'rejected' }, latencyMs)`. **Correct labeling** â€” unlike PIX/SPEI which always use `'success'` on the happy path. **Low** (BREB is the only one right here).
- `RAIL = 'BRE_B'` (constants.ts:2) â€” with underscore. PIX/SPEI use `'PIX'`/`'SPEI'`. Cross-rail inconsistency. **High** (`mipit-adapter-breb/src/config/constants.ts:2`).

#### `src/health-server.ts` (28 lines)

Mirror of others with `adapter: 'breb'`.

#### `src/messaging/rabbitmq.ts` and `publisher.ts`

Mirror of others with `'route.breb'`/`'dlq.breb'`. Same High findings.

#### `src/config/env.ts` (37 lines)

- `HEALTH_PORT` default `9103` â€” matches port-fix recommendation.
- `BREB_SANDBOX_URL` default `http://localhost:9003`.
- `RABBITMQ_URL` has a **default** (`amqp://mipit:mipit@localhost:5672`) unlike PIX/SPEI which require it. So Bre-B can boot with default creds; PIX/SPEI cannot. Mild inconsistency. **Low**.
- `OTEL_EXPORTER_OTLP_ENDPOINT` defaults to `http://localhost:4318` unlike PIX/SPEI (which require it). **Low**.

#### `src/observability/*`

Mirror of others.

#### `src/breb/client.ts` (124 lines)

**Diverges significantly** from PIX/SPEI client:
- Inlines retry loop (lines 48â€“116) instead of using a `retry.ts` helper. There is **no `mipit-adapter-breb/src/breb/retry.ts`**. **Critical** divergence in template.
- Inline retry never calls `brebRetryCount.inc()` â€” the metric is *declared* (`observability/metrics.ts:21-25`) but **never used**. **Critical** (`mipit-adapter-breb/src/breb/client.ts:48-116`, `mipit-adapter-breb/src/observability/metrics.ts:21-25`).
- Different retry math: `sleep(200 * attempt)` (linear, not exponential) â†’ 200ms, 400ms, 600ms. PIX/SPEI use 500ms Ã— 2^(n-1) â†’ 500/1000/2000ms. **Cross-rail inconsistency**. **High**.
- Lines 89â€“93: **does handle 4xx separately** â€” returns the body without retry. PIX/SPEI lack this. So Bre-B is actually *better* on retry semantics than PIX/SPEI.
- Line 64: extra `X-Adapter` header â€” not present in PIX/SPEI. **Low**.
- Endpoint `${BREB_SANDBOX_URL}/breb/v1/pagos` (line 45) â€” invented; BanRep has no public spec.

#### `src/breb/mapper.ts` (97 lines)

- Lines 44â€“52: strips entity prefix via `/`-split (`'26264220/900123456-1'` â†’ `'900123456-1'`). Different convention from PIX (prefix `PIX-`) and SPEI (prefix `SPEI-`). **Cross-rail inconsistency**. **Medium**.
- Line 58: `llave.replace(/^BREB-/, '')` â€” still strips `BREB-` prefix on the *llave* even though the account uses `/` split. So both conventions exist in the same file. **Medium**.
- Lines 60â€“64: tipoLlave inference:
  - `^\+57\d{10}$` â†’ `TELEFONO`. Accepts fixed-line `+57 1` prefix; real Bre-B accepts only mobile (`+57 3`). **High**.
  - `^\d{9,10}-\d$` â†’ `NIT`.
  - `includes('@')` â†’ `EMAIL`.
  - else â†’ `ALIAS`.
  - **Missing:** `CC` (cÃ©dula), `CE` (cÃ©dula extranjerÃ­a), `PASAPORTE`. The canonical type system declares `BreBKeyType = 'TELEFONO' | 'NIT' | 'EMAIL' | 'ALIAS'` (`types.ts:12`) â€” so the schema itself omits CC/CE/Pasaporte. **Critical** for spec fidelity.
- Lines 73, 74, 75â€“77: NIT/CC dispatch by `taxId?.includes('-')`. A NIT in Colombia is `9-10 digits + check digit`, sometimes written with hyphen, sometimes without. The heuristic is wrong: `123456789` (no hyphen) is a NIT with a missing check digit, classified as CC. **High**.
- Line 73: `name ?? 'REMITENTE'`, line 83: `name ?? 'BENEFICIARIO'`. PIX uses Portuguese defaults; SPEI uses Spanish ("Beneficiario MIPIT"); BREB uses Spanish too. Consistent.
- Line 94: `fechaHora: canonical.created_at`. **Uses the canonical's `created_at`, not `new Date().toISOString()`** like PIX (line 93 of mapper.ts) and SPEI (line 68 fechaOperacion). This is the *correct* behavior â€” preserves the original timestamp. **Low** finding: PIX/SPEI should do the same.

#### `src/breb/response-mapper.ts` (82 lines)

Mirror of PIX/SPEI. Same `EN_PROCESO â†’ status: 'ERROR'` semantic.

#### `src/breb/types.ts` (97 lines)

- `BreBKeyType = 'TELEFONO' | 'NIT' | 'EMAIL' | 'ALIAS'` â€” missing CC/CE/Pasaporte. **Critical** (`mipit-adapter-breb/src/breb/types.ts:12`).
- `BREB_ENTITY_CODES` (lines 75â€“82):
  ```
  BANCOLOMBIA:       '00000007',
  BANCO_DE_BOGOTA:   '00000013',
  DAVIVIENDA:        '00000051',
  NEQUI:             '10007550',
  DAVIPLATA:         '00005141',
  FINTECH_SIMULATED: '26264220',
  ```
  All **8 digits**. Real Superfinanciera entity codes are 4 digits (e.g. Bancolombia = `0007`, Banco de BogotÃ¡ = `0001`). Zero-padding to 8 is the adapter's invention. **High** (`mipit-adapter-breb/src/breb/types.ts:75-82`).
  - **Critical sub-finding from prior audit:** the prior audit claimed BBVA_COLOMBIA and BANCO_DE_BOGOTA collide at `'00000013'`. Looking here, BBVA_COLOMBIA is **not present** at all. So either the prior audit was reading a different file, or BBVA was removed. Today the table has no collision. **Tracked**.
- `generateBrebTransactionId` (lines 88â€“96):
  - Same UTC-vs-local bug as PIX. **High**.
  - Same `Math.random().padEnd(10, '0')` entropy degradation. **Medium**.
  - 10-char suffix vs PIX's 11 â€” inconsistent.
- `created_at` not in the canonical interface in the mapper but referenced in the mapper (line 94 reads `canonical.created_at` â€” but mapper interface line 26 defines it). **OK**.

#### `src/breb/mock-server.ts` (321 lines)

- Header comment (line 8) claims fidelity to "BanRep specification v1.0 (2023)". **There is no such 2023 spec.** BanRep's first technical document is February 2026. **Critical** (`mipit-adapter-breb/src/breb/mock-server.ts:8`) â€” academic integrity flag.
- `LIMIT_NATURAL_COP = 20_000_000`, `LIMIT_JURIDICA_COP = 200_000_000` (lines 55â€“56). Real Bre-B started with COP 10M for naturals, ~4M for retail per analyst commentary. **High** (prior audit).
- `LLAVE_VALIDATORS` (lines 59â€“64):
  - `TELEFONO: /^\+57\d{10}$/` â€” accepts fixed-line. **High**.
  - `NIT: /^\d{9,10}-\d$/` â€” requires hyphen + check digit. OK.
  - `EMAIL` â€” OK.
  - `ALIAS: /^[A-Za-z0-9]{4,20}$/` â€” **excludes `@` prefix** that BanRep specifies for alphanumeric aliases (per prior audit). **High**.
  - Missing: CC, CE, PASAPORTE.
- `idTransaccion` regex `^BR\d{8}\d{8}\d{4}[A-Z0-9]{10}$` (line 82) â€” accepts only uppercase suffix. Same fragility as PIX.
- Validation: amount format (line 92), non-zero (line 102), entity 8-digit (line 109), `pagador.nombre` required (line 118), `beneficiario.codigoEntidad` 8-digit if present (line 127), `llave` non-empty (line 136), `llave` format by `tipoLlave` (line 145), `concepto` â‰¤ 140 (line 156), COP limit by isLegalEntity heuristic (lines 166â€“175). The `isLegalEntity` flag is just `Boolean(pagador?.nit)` â€” any payment with a NIT-bearing payer gets the 200M limit, including individuals who happen to send their NIT as taxId. **Medium**.
- Admin disabled / force-reject / force-timeout (lines 180â€“207).
- Rejection ladder (lines 213â€“251): BREB001 / BREB004 / BREB002 / BREB005. **Different bucket boundaries** than PIX/SPEI: 0.4 / 0.7 / 0.9 / 1.0 (PIX uses 0.4/0.6/0.8/0.9/1.0). **Low** inconsistency.
- Line 253: `idConfirmacion = BRE${Date.now()}${ulid().substring(0,6)}` â€” uses `Date.now()` not ULID alone. The first 13 chars are predictable (ms timestamp). **Low**.
- No `GET /admin/stats` returns inside admin-routes.ts but there is no SPI window enforcement at all. Bre-B is supposed to be 24/7, so this is actually *correct* â€” but inconsistent with PIX/SPEI which have window logic.
- No `settlementDelayMs` knob â€” Bre-B's admin-routes.ts is *simpler* than SPEI's. So it avoids the SPEI bug. **Low**.

#### `src/breb/oauth-mock.ts` (109 lines)

Identical pattern. Default scope `'breb.pagos'`. Real BanRep auth model is undocumented (the Feb 2026 technical doc may specify; we couldn't extract the PDF text). **High** â€” invented auth, but at least it's honest about not having a real spec.

#### `src/breb/admin-routes.ts` (109 lines)

Identical pattern, minus `settlementDelayMs`.

#### Tests

- `test/unit/mapper.test.ts` (174 lines): 17 cases. Tests idTransaccion format, FX, entity mapping, default fallback, prefix strip, aliasâ†’llave, tipoLlave inference, NIT vs CC mapping, name truncation, concepto, fechaHora preservation. **Does not test** the `+57 1` fixed-line acceptance bug or the missing CC/CE key types.
- `test/unit/response-mapper.test.ts` (117 lines): 9 cases. Covers all 4 states and rail_tx_id fallback.
- `test/unit/breb-translation.test.ts` (89 lines): **Has a broken import** â€” line 6 imports `brebToCanonical` which is not exported from `types.ts`. **Critical**. The test file is dead.
- **No `test/contract/`** â€” no HTTP-level integration test exists for the Bre-B mock. **Critical**.
- **No `test/unit/worker.test.ts`** â€” unlike PIX/SPEI which have one. **High**.
- **No `test/unit/publisher.test.ts`** â€” same. **High**.
- **No `test/unit/health-server.test.ts`** â€” same. **High**.
- **No `test/unit/retry.test.ts`** â€” there's nothing to test (no retry.ts file). But the inline retry in client.ts is *also* not tested. **High**.

### 4.2 Bre-B endpoint contract audit

No public BanRep wire-format spec exists for Bre-B as of audit date. So every "Match?" is by definition unverifiable.

| Endpoint | Real spec | Our mock | Match? | Notes |
|---|---|---|---|---|
| `POST /breb/v1/pagos` | Unknown / unpublished | Returns `BreBPaymentResponse` | â“ | Defensible PoC if labeled. |
| `GET /breb/v1/pagos/:idTransaccion` | Unknown | Returns cached | â“ | |
| `POST /oauth/token` | Unknown | client_credentials | â“ | |
| `GET /health` | N/A | OK | N/A | |
| Admin endpoints | N/A | Unauth | High | |

### 4.3 Bre-B field validation audit

| Field | Mock validator | BanRep (per Feb 2026 doc, partially recovered) | Match? |
|---|---|---|---|
| `idTransaccion` | `^BR\d{8}\d{8}\d{4}[A-Z0-9]{10}$` | Format unpublished | â“ Plausible. |
| `valor.original` | `^\d+\.\d{2}$` | COP, 0 decimals? COP is integer-only in practice. | âš ï¸ Wrong â€” COP has no centavos. **Medium**. |
| `pagador.codigoEntidad` | `\d{8}` | Superfinanciera 4-digit | Wrong digit count. **High**. |
| `llave` (TELEFONO) | `^\+57\d{10}$` | Mobile only (`+57 3xx`) | Too lax. **High**. |
| `llave` (NIT) | `\d{9,10}-\d` | NIT 9-10 digits + check digit | Match. |
| `llave` (EMAIL) | RFC-light | RFC | OK. |
| `llave` (ALIAS) | `[A-Za-z0-9]{4,20}` | `@`-prefixed alphanumeric per BanRep | Wrong (no `@`). **High**. |
| Missing: `CC`, `CE`, `PASAPORTE` | â€” | Required per BanRep llave catalog | Missing. **Critical**. |
| `concepto` length | â‰¤ 140 | Unpublished | Plausible. |
| Amount limit | 20M COP natural / 200M juridica | ~10M COP natural at launch | Too lax. **High**. |
| `fechaHora` | not validated by mock | ISO 8601 | Missing. **Low**. |

### 4.4 Bre-B OAuth2 audit

Auth pattern in real Bre-B is unpublished. Our mock implements client_credentials with scope `'breb.pagos'`. Defensible *iff* explicitly framed as "PoC inventing auth because BanRep hasn't published". **High** â€” flag in thesis.

### 4.5 Bre-B worker reliability audit

Same matrix as PIX/SPEI. Plus:
- `brebRetryCount` metric unused. **Critical**.
- Inline retry uses linear backoff (200ms Ã— attempt). **High** divergence.
- 4xx not retried (better than PIX/SPEI). **OK**.

### 4.6 Bre-B mapper round-trip

- **Lost:** `purpose`, `reference` (unless used for concepto), `trace_id`, `payment_id` entirely (no folio equivalent), `origin.rail/destination.rail`.
- **Added:** `tipoLlave` inferred, `tipoCuenta: 'CACC'` default, fixed `valor.original` 2-decimal formatting.
- **Coming back:** `idConfirmacion`, `estado`, `fechaLiquidacion`, optional error fields.
- **Lost in ack:** `fechaLiquidacion` (replaced by `processed_at` adapter-side).

### 4.7 Bre-B retry/backoff

| Aspect | Value | Severity |
|---|---|---|
| Base delay | 200ms | Differs from PIX/SPEI (500). High inconsistency. |
| Max delay | 600ms (3 attempts linear) | Lower ceiling. Medium. |
| Jitter | None | Medium. |
| Max attempts | 3 | OK. |
| Error class | 4xx returned, 5xx retried | **Better than PIX/SPEI**. Low (good). |
| Metric tracked | `brebRetryCount.inc()` **never called** | **Critical**. |

### 4.8 Bre-B mock fidelity score

**1.0/5**. Wire format is invented; some plausible structure but missing core llave types, wrong entity-code width, wrong COP decimals, wrong celular validator. The honest framing has to be "reference implementation for a future spec," not "Bre-B mock."

---

## 5. Cross-adapter patterns

### 5.1 Duplicate code

The following symbols appear ~verbatim in all three adapters:

| File | Diff |
|---|---|
| `src/worker.ts` | ~98% identical; differs in rail constant, mapper function name, metric names. Could be a shared `@mipit/adapter-worker` package. |
| `src/messaging/rabbitmq.ts` | 100% identical except `'dlq.<rail>'` and `'route.<rail>'` strings. |
| `src/messaging/publisher.ts` | 100% identical except for log payload key (`'Published ack message'`). |
| `src/observability/otel.ts` | 100% identical. |
| `src/observability/logger.ts` | 100% identical. |
| `src/observability/metrics.ts` | 100% structurally identical; only metric names differ. |
| `src/health-server.ts` | 100% identical except `adapter: '<name>'`. |
| `src/<rail>/oauth-mock.ts` | 99% identical except scope, secret, token prefix. |
| `src/<rail>/admin-routes.ts` | 99% identical except rail label and default `forceRejectCode`. SPEI adds `settlementDelayMs`. |
| `src/<rail>/retry.ts` | 100% identical between PIX/SPEI. **Absent in BREB**. |

This is ~1500 lines of duplication. Severity: **Medium** (maintainability), **High** (because divergent fixes need three commits).

### 5.2 Divergent patterns

| Pattern | PIX | SPEI | BREB |
|---|---|---|---|
| Account prefix strip | `^PIX-` | `^SPEI-` | `'/'`-split + `^BREB-` (on llave) |
| ID generation suffix length | 11 | 8 | 10 |
| ID generation char set | `[A-Z0-9]` post-`toUpperCase()` | `[0-9]` (numeric `seq`) | `[A-Z0-9]` |
| Date in ID | UTC slice | UTC slice | UTC slice |
| Retry backoff | 500 Ã— 2^n | 500 Ã— 2^n | 200 Ã— n (linear) |
| 4xx behavior | Retried | Retried | Returned without retry |
| OAuth client_secret | `mipit-secret-pix-2024` | `mipit-secret-spei-2024` | `mipit-secret-breb-2024` |
| OAuth scope | `'spi.pagamentos'` | `'spei.transferencias'` | `'breb.pagos'` |
| Mock latency range | 80â€“450 | 80â€“450 | 80â€“400 |
| Default `rejectionRate` | 0.10 | 0.095 | 0.10 |
| Force-reject code | `'AM04'` | `'R01'` | `'BREB001'` |
| `RAIL` constant value | `'PIX'` | `'SPEI'` | `'BRE_B'` (underscore!) |
| `dataHora` field | `new Date().toISOString()` | `new Date().toISOString()` slice | **`canonical.created_at`** |
| Latency metric labeling | `'success'` regardless | `'success'` regardless | Correct `success`/`rejected` |

The `created_at` preservation in BREB is the *correct* behavior; PIX and SPEI should follow.

The `RAIL = 'BRE_B'` underscore is a cross-system landmine.

### 5.3 Common cross-rail bugs (all three)

- **UTC dates in ID generation** (`<rail>/types.ts`). **High**.
- **Hard-coded OAuth client_secret in source** (`<rail>/client.ts`). **High**.
- **Shared AbortController across 401-refresh retry** (`<rail>/client.ts`). **High**.
- **No publisher confirms** (`messaging/publisher.ts`). **High**.
- **No W3C TraceContext injection** in AMQP message headers. **High**.
- **No channel reconnection** (`messaging/rabbitmq.ts`). **High**.
- **`nack(false, false)` on any error** â†’ straight to DLQ, no requeue (`worker.ts`). **High**.
- **Outer `status` collapses ERROR â†’ REJECTED** (`worker.ts:71`). **High**.
- **EN_PROCESO / EM_PROCESSAMENTO mapped to `status: 'ERROR'`** (`<rail>/response-mapper.ts`). **High**.
- **No CPF/CNPJ/RFC/CURP checksum validation** in mocks. **High** (per rail).
- **Admin endpoints unauth'd** in mocks. **High**.
- **`/admin/<rail>/*` endpoints return ostensibly-correct rail label but the BREB one uses `'BRE_B'` with underscore** â€” UI tooling has to special-case. **Medium**.
- **`infoAdicional`/email truncation defensively done by mapper but mock doesn't enforce** â€” adapter rules differ from mock rules. **Medium**.
- **No `idempotency` at the adapter level** â€” the mock keeps an in-memory map, but the *adapter* will retry on transient errors and re-send the same payload (which mock dedupes by ID â€” good). If a different adapter instance retries (multi-replica), the ID will be different because it's generated fresh each `canonicalToXPayload` call. So the mock's dedupe is bypassed. **High**.

### 5.4 Routing/prefix concern leaking into canonical

All three mappers strip a rail-specific prefix from `debtor.account_id` / `creditor.account_id` / `alias.value`. This is a sure sign the routing engine in core is *adding* the prefix and the mapper is *removing* it â€” the canonical layer briefly carries routing metadata. The prior audit captured this. From the audit perspective, the symptom is that all three mappers have prefix-stripping code in the same place.

### 5.5 Time-zone handling

| File | Code | Effect |
|---|---|---|
| `pix/types.ts:184-185` | `toISOString().slice` | UTC; expected BRT |
| `spei/mapper.ts:68` | `toISOString().slice` | UTC; expected CT |
| `breb/types.ts:92-93` | `toISOString().slice` | UTC; expected COT |
| `breb/mapper.ts:94` | `canonical.created_at` | **Honored** |
| All mock response `horario` / `fechaLiquidacion` | `new Date().toISOString()` | UTC |
| `spei/mock-server.ts:275` | `now.toTimeString().slice(0,8)` | **Server-local** (host TZ) |

Three different time-zone strategies coexist in one repo. **High**.

### 5.6 Error-mapping convention

PIX: BACEN code (`AB03`, `AC01`, `AM01`, â€¦) â†’ `error.code` direct.
SPEI: CECOBAN code (`R01`, â€¦, `LIM`) â†’ `error.code` direct.
BREB: BanRep code (`BREB001`, â€¦) â†’ `error.code` direct.

Three different error-code namespaces in the same `RailAck` shape with no namespace prefix. A downstream consumer that wants "which rail rejected" must look at `source_rail`. **Medium**.

The `*_DEVUELTA`/`*_EN_PROCESO`/`*_UNKNOWN_STATUS` synthetic codes are made up by the response-mapper. They are **not** in the rail's spec. So a Grafana panel showing "Top error codes" will mix real rail codes with our synthetic ones. **Medium**.

### 5.7 OAuth2 mock duplication

The three `oauth-mock.ts` files are byte-equivalent modulo VALID_CLIENTS / scope / token prefix. A shared `@mipit/oauth-mock` package would eliminate ~300 lines of duplication.

### 5.8 Endpoint URL pattern

| Rail | URL | Real spec |
|---|---|---|
| PIX | `/spi/v2/pagamentos` | Real PIX-PSP uses `/cob/{txid}` etc., real SPI is XML/RSFN |
| SPEI | `/spei/v3/transferencias` | Real STP is SOAP `/speiws/rest/...` |
| Bre-B | `/breb/v1/pagos` | Unpublished |

All three invent a REST POST endpoint at a plausible-sounding URL. **High** for fidelity. The version numbers (`v2`/`v3`/`v1`) are also invented and don't track real API generations.

---

## 6. What was DONE WELL

To be fair, the codebase has real strengths. Calling them out concretely:

### 6.1 CLABE validator (`mipit-adapter-spei/src/spei/clabe-validator.ts`)

A correctly-implemented mod-10 weighted check-digit algorithm against the published Banxico CLABE specification (`CLABE_WEIGHTS = [3, 7, 1, 3, 7, 1, â€¦]`, 17-digit weighted sum mod-10). Plus error-detail classification (`INVALID_FORMAT`/`INVALID_LENGTH`/`INVALID_CHECK_DIGIT`) and a `buildTestClabe()` helper that makes the unit tests readable. This is the highest-quality piece of rail-spec adherence in the entire project. **Score: 5/5**.

### 6.2 OAuth2 token caching in clients (`<rail>/client.ts:6-36`)

Cache-with-margin pattern (`Date.now() < cachedToken.expiresAt - 60_000`) is the textbook approach. The 60-second buffer prevents 401s due to clock skew. The 401 force-refresh flow is well-thought-out (even if marred by the shared AbortController bug). **Score: 4/5**.

### 6.3 Mock idempotency by canonical ID

All three mocks key idempotency on the rail's canonical transaction ID (`endToEndId` / `claveRastreo` / `idTransaccion`), which is the right approach â€” real rails do exactly this. Returning the cached response on replay with HTTP 200 matches real behavior. **Score: 4/5**.

### 6.4 Rejection-code coverage

The mocks emit a rich set of rejection codes per rail:
- PIX: AM01, AM02, AM04, AC01, AC03, AB03, BE01, DS04, RR04 + admin codes. Maps to BACEN Appendix III faithfully in terms of *codes used* (semantics).
- SPEI: R01, R02, R03, R04, R05, R08, LIM (Banxico/CECOBAN code set partial but well-known codes covered).
- Bre-B: BREB001, BREB002, BREB003, BREB004, BREB005 + BREB_AM01 synthetic. The codes are made up but consistent.

This is much better than a binary success/failure mock. **Score: 4/5**.

### 6.5 Admin-control API design

`GET /admin/config`, `POST /admin/config`, `POST /admin/reject-next`, `POST /admin/timeout-next`, `POST /admin/reset`, `GET /admin/stats` is a clean, dashboard-friendly contract. The UI dashboard can flip a rail into a degraded mode for resilience testing without restarting. **Score: 4/5**.

### 6.6 SPEI `cecoban-mapper.test.ts`

Uses `buildTestClabe` to generate valid CLABEs at test-fixture build time. The tests are *self-validating* in that the CLABE inputs are demonstrably valid by the validator's own algorithm. Cases include CLABE-invalid throws (3 variants â€” bad checksum, wrong length, non-digit). **Score: 4/5**.

### 6.7 Health endpoints expose Prometheus metrics

`/metrics` endpoint per adapter exposes the prom-client registry. Default node metrics + the rail counters are correct format and live behind the standard `:9101/9102/9103` ports (post-prior-fix). **Score: 4/5**.

### 6.8 BREB mapper preserves `canonical.created_at`

Line 94: `fechaHora: canonical.created_at`. This is the *one* place across the three adapters where the original creation timestamp is honored. PIX and SPEI clobber it with `new Date().toISOString()` instead. **Score: 5/5** â€” be more like BREB here.

### 6.9 BREB client classifies 4xx correctly

`if (!res.ok && res.status < 500) return body;` (lines 89â€“93). 4xx errors are surfaced to the response-mapper without burning retry attempts. PIX and SPEI both blindly retry 4xx. **Score: 5/5** â€” be more like BREB here.

### 6.10 Per-rail Zod env validation

All three adapters validate `process.env` on boot with Zod and exit 1 on failure with a readable error. This is solid configuration hygiene; many comparable PoCs read env strings at lazy time and crash mid-request. **Score: 5/5**.

### 6.11 Latency labeling â€” BREB

`mipit-adapter-breb/src/worker.ts:83` is the only adapter that labels the latency histogram by actual outcome (`success`/`rejected`/`error`). PIX/SPEI always tag the success path as `'success'` even on rejection. **Score: 5/5** â€” be more like BREB here.

### 6.12 DLQ scaffolding

All three adapters declare DLX (`x-dead-letter-exchange: 'mipit.dlx'`) and a dedicated dead-letter routing key. The pattern is correct; the missing pieces (auto-reconnect, requeue on transient) live elsewhere. **Score: 3.5/5**.

### 6.13 Mock-server CORS

All three mocks set CORS headers to allow any origin (the simulator dashboard is on a different origin). Pragmatic for a PoC. **Score: 4/5**.

### 6.14 Consistent file layout

The mirror-image file structure across PIX/SPEI/BREB makes onboarding trivial â€” find a file in PIX, you find the analog in SPEI in seconds. The cost is the duplication (Â§5.1) but the navigability is real. **Score: 4/5**.

### 6.15 Strict EndToEndId regex in PIX mock

`^E\d{8}\d{8}\d{4}[A-Z0-9]{11}$` (line 110). Matches the BACEN spec shape almost exactly; would reject malformed E2E IDs. Strictness of the mock here is actively defensive of the spec. **Score: 4/5** â€” only loss is case-sensitivity (BACEN allows mixed).

---

## Sources

- Prior audit: `C:\Users\nicog\Documents\Tesis\AUDITORIA-MIPIT-2026-05-16.md`
- BCB PIX API OpenAPI: https://raw.githubusercontent.com/bacen/pix-api/master/openapi.yaml
- BCB PIX docs portal: https://bacen.github.io/pix-api/index.html
- Banxico SPEI participants: https://www.banxico.org.mx/servicios/participantes-spei-banco-me.html
- Banxico CEP-SCL institution list: https://www.banxico.org.mx/cep-scl/listaInstituciones.do
- Banxico Monitor SPEI: https://www.banxico.org.mx/monspei/
- STP/cuenca-mx Python client (referenced; private API): https://github.com/cuenca-mx/speid and https://pypi.org/project/stpmex/
- BanRep Bre-B portal: https://www.banrep.gov.co/es/bre-b/que-es
- BanRep Bre-B technical document (Feb 2026): https://d1b4gd4m8561gs.cloudfront.net/sites/default/files/publicaciones/archivos/documento-tecnico-bre-b-febrero-2026.pdf
- Bancolombia Bre-B explainer: https://blog.bancolombia.com/educacion-financiera/que-es-bre-b/
- CatÃ¡logo bancos SAT MÃ©xico: https://www.gob.mx/cms/uploads/attachment/file/151413/catalogo_bancos.pdf

---

## Final notes on what changed vs. prior audit

The prior audit captured the headline findings (EndToEndId UTC bug, SPEI institution-code 3-vs-5 digits, FX ignored, Bre-B llave gaps, OAuth2 mismatches). This forensic pass added the long tail:

1. BREB has **no retry.ts and never increments brebRetryCount** â€” invisible retries.
2. BREB **test file with broken import** (`brebToCanonical` not exported).
3. BREB has **no contract test, no worker test, no publisher test, no health-server test**.
4. SPEI **`settlementDelayMs` async-settle is wired to fail** â€” produces FAILED acks for what will eventually liquidate.
5. **Worker outer `status` collapses ERROR â†’ REJECTED** in all three adapters.
6. **Shared `AbortController` across 401 refresh** in all three.
7. **Retry on 4xx** in PIX/SPEI (but not BREB â€” better there).
8. **`RAIL` constant value inconsistent** â€” `'PIX'`, `'SPEI'`, `'BRE_B'` (underscore).
9. **Latency metric mislabeling** â€” PIX/SPEI tag `'success'` regardless of outcome.
10. **Admin endpoints unauth'd** even though the OAuth middleware exists.
11. **PIX mock first-rejection-bucket doesn't increment `totalRejected`** counter.
12. **PIX mock `txid` reuses request's `idConciliacao`** â€” semantic re-use.
13. **PIX EVP keys not validated as UUIDv4 by mapper** â€” anything-not-matching falls through to EVP.
14. **CURP truncation to 18 chars cuts the check digit** in SPEI mapper.
15. **SPEI ordering party silently dropped** if `cuentaOrdenante` not 18-digit CLABE.
16. **BREB `+57` regex accepts fixed-line** numbers (mobile-only per BanRep).
17. **BREB ALIAS regex missing `@` prefix** required by BanRep.
18. **BREB COP amount uses 2-decimal format** â€” COP is integer-only in practice.
19. **BREB `isLegalEntity = Boolean(nit)` heuristic** wrongly elevates individuals.
20. **Mock-server fidelity claims to "2023 BanRep spec" that doesn't exist** â€” academic integrity hit.

The codebase is solid for a PoC and the test scaffolding for PIX/SPEI is genuine; Bre-B is half-finished and several patterns (TraceContext, publisher confirms, reconnect, time-zone handling) would benefit from a small shared library.
