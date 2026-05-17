I have enough to assemble the audit. I'll skip the remaining adapter/infra paths and produce the deliverable.

---

# UI + Testkit + Docs + Originals â€” Forensic Audit

**Date:** 2026-05-16
**Scope:** `mipit-ui`, `mipit-testkit`, `mipit-docs`, `plans/`, root PDFs, `CONTEXTO-MIPIT.md`, `fix_testkit.py`
**Severity tags:** [BLOCKER] [HIGH] [MEDIUM] [LOW] [INFO]

---

## 1. Executive Summary

The four artifact families audited are **internally well-built but mutually drifted**. Strongest layer is the running UI: typed, accessible-enough, and aligned with mipit-core endpoints actually shipped (auth/token, /analytics, /mocks, /events SSE). Weakest layer is the **testkit's `tests/` Jest suite**: a large fraction of those files are placeholder tests with `expect(true).toBe(true)` masquerading as coverage. The "11/11 green" headline is real â€” but it counts three "historical" entries with `durationMs: 0` that were not re-executed, and it counts five repo Jest suites without auditing the quality of the assertions underneath.

Documentation drift is severe in three places: (1) **OpenAPI** still describes a 2-rail world (PIX/SPEI only, 11 statuses, 202 on create); the running API supports 7 rails, 14 statuses, returns 201/200, and exposes routes that are not in the spec (`/translate/preview`, `/translate/rails`, `/analytics/*`, `/compensate/*`, `/events/payments`, `/mocks/{rail}/admin/*`, `/auth/token`). (2) **mappings/** CSVs and `canonical-fields.md` describe a flat snake_case canonical (`amount`, `currency`, `debtor.alias_type`); the real canonical is **nested camelCase** (`grpHdr.msgId`, `amount.value`, `amount.currency`, `origin.rail`) per `mipit-docs/design/translation-layer.md` and the UI's translator page. (3) **route-rules/rules.yaml** uses a different vocabulary (alias_type enum CLABE/CPF/PHONE/EMAIL/EVP/PHONE_MX) than the implementation, which routes by alias **prefix** (PIX-/SPEI-/BREB-) per `mipit-testkit/e2e-routing-correctness.mjs:22-44` and the UI placeholders in `mipit-ui/src/app/simulate/page.tsx:34-42`.

Original-proposal drift: the Propuesta promised **PIX + SPEI + FedNow + bre-b** as the four rails for the prototype evaluation. Delivery covers **PIX, SPEI, BRE_B as full Option B adapters** and **SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW as Option A translators only** â€” a net win on breadth but a subtle change in framing (the proposal counted 4 rails; the demo now has 7 names with 3 actually wired to mocks). SRS RF01â€“RF20 are nearly all covered functionally; RF19 (CSV/JSON export) is **not implemented in the UI**.

There is one dead file at the repo root (`fix_testkit.py`) â€” a one-shot Linux migration script from a prior session whose hardcoded `/home/estudiante/tesis/...` paths make it inert on Windows. It should be moved to `scripts/migrations/` or deleted.

---

## 2. UI audit (page-by-page, component-by-component)

### 2.1 Root and configuration

- `mipit-ui/package.json:1-54` â€” Next 15.1, React 19, Tailwind 4 alpha, Radix bits, zod 3.24, react-hook-form 7.54. Jest 29 / ts-jest. Versions are coherent and recent.
- `mipit-ui/next.config.ts:1-10` â€” Standalone output for Docker, server-actions body 2mb. Minimal but correct.
- `mipit-ui/tsconfig.json:1-23` â€” `strict: true`, path alias `@/*`. No bundler-resolved JSON, no `noUncheckedIndexedAccess`. [LOW] Consider enabling `noUncheckedIndexedAccess` â€” the codebase uses many `someMap[key]?.field` accesses (e.g., `payment-status-badge.tsx:9`) that would benefit.
- `mipit-ui/jest.config.ts:1-21` â€” Uses `next/jest`, jsdom env, `**/__tests__/**` plus `**/*.test.{ts,tsx}`. Coverage configured but `--passWithNoTests` in `npm test` means CI never fails for empty suites. [MEDIUM]
- `mipit-ui/jest.setup.ts:1` â€” One line: `@testing-library/jest-dom`. Fine.
- `mipit-ui/Dockerfile:1-16` â€” Multi-stage Node 22 alpine, standalone output. Correct.
- `mipit-ui/AGENTS.md:114-120` â€” Claims tests in `test/components/`. Reality: most tests live in `src/__tests__/`. The standalone `test/components/payment-form.test.tsx` is a **vitest** placeholder (`import {describe,it,expect} from 'vitest'`) running only `it.todo()` stubs (see `mipit-ui/test/components/payment-form.test.tsx:1-12`). [MEDIUM]
- `mipit-ui/README.md:14-16` â€” Tells the user to `npx shadcn@latest init`, but `src/components/ui/` is empty (`.gitkeep` only). Document either drops shadcn or actually adds primitives. [LOW]
- `mipit-ui/src/app/globals.css:1-7` â€” Tailwind 4 `@theme` block defines only `--color-card`; everything else (foreground/background/border/primary) is referenced throughout components but **never defined**. The app renders correctly in dev because Tailwind 4 has default tokens, but **`--color-foreground`, `--color-background`, `--color-border`, `--color-primary` are not declared anywhere**. [HIGH] This will surface as missing colors on a strict build or when the design system rotates.

### 2.2 Pages

#### `src/app/layout.tsx:1-29` [INFO]
Server component, `lang="es"`, Inter font, Navbar+Footer chrome. No error boundary, no `<head>` viewport meta, no `<noscript>`. Acceptable for PoC. The Inter import correctness is fine; no theme provider or i18n context â€” locale is hardcoded "es".

#### `src/app/page.tsx:1-23` (Dashboard)
Three composed widgets: `<StatsCards/>`, `<RecentPayments/>`, `<ServiceHealth/>`. Clean. No drift.

#### `src/app/analytics/page.tsx:1-599`
Large client component. Polls 4 analytics endpoints every 10s plus reconciliation on-demand. Strong points:
- Defensive parsing (`parseSummary`, `parseLatency`, `parseBreakers`, `parseRateLimits`) â€” none of them trust the API shape.
- Handles `success_rate` as either 0â€“1 or 0â€“100 (line 71-76). Pragmatic.
- Reconciliation panel renders generic key/value tables when shapes are unknown (lines 539-572).

[MEDIUM] **Performance**: `loadAnalytics` recreated on every render with no `useRef` for in-flight cancellation. Two slow tabs left open will pile up overlapping `Promise.all`s. Also `setInterval` keeps running while tab is hidden â€” should use `document.visibilityState`.

[LOW] Accessibility: error banner has `role="alert"` (good), but stat cards use `<dd>` without `aria-live="polite"` so screen readers don't announce updates.

#### `src/app/history/page.tsx:1-32`
Thin orchestrator. State for `statusFilter` and `railFilter`, hands to `<Filters/>` and `<PaymentTable/>`. Correct.

#### `src/app/live/page.tsx:1-252`
SSE-driven live feed with sidebar counts. Real-time, reconnect logic in the hook, animation on insert. The `<style>{ "@keyframes liveEventIn â€¦" }</style>` injection (lines 130-141) is fine for Next 15 but inline `<style>` in a client component creates an extra render node â€” preferable to add to `globals.css`. [LOW]

#### `src/app/payments/[id]/page.tsx:1-126`
Loads payment on mount, manual refresh button, **no polling**. The user's stated concern â€” "Does the timeline page render trace_id with a Jaeger link?" â€” **answer: NO**. There is no `trace_id` displayed anywhere on this page; `PaymentDetail` type in `src/lib/types.ts:26-51` does not even include `trace_id`. The OpenAPI spec also omits `trace_id` from the `PaymentDetail` schema (`openapi.yaml:302-374`). [HIGH] Trace-id surfacing was promised by ADR-008 ("propagaciÃ³n W3C Trace Contextâ€¦ correlaciÃ³n con trace_id en mensajes RabbitMQ") and the SRS section 2.1.5 mentions `X-Trace-ID`, but never reaches the UI. The Jaeger link is also absent â€” yet `next-steps.md:172-178` says "Jaeger trace de una transacciÃ³n completa" is part of the evidence.

#### `src/app/simulate/page.tsx:1-301`
The user asked: "Does the UI form display origin/destination rail and actually USE them in the request?" â€” **partial answer**:
- The form displays origin & destination rail pickers (`RailPicker` lines 44-79) and refines with `.refine(d => d.originRail !== d.destRail â€¦)` (line 27).
- The submit handler at lines 127-144 sends ONLY `amount`, `currency`, `debtor`, `creditor`, `purpose`, `reference` â€” `originRail` and `destRail` are **NOT in the request body**. They are used only for placeholder text and for the visual rail header.
- This is *intentional* per `CONTEXTO-MIPIT.md:177` and `plans/PLAN-DE-DESARROLLO.md:24-26`: the core's RouteEngine infers rail from the alias prefix. So the user can pick "PIX origin, BRE_B destination" but submit `PIX-â€¦@email.com` / `SPEI-012â€¦` aliases and the back end will route to SPEI regardless of the picker. **The picker is a lie.** [HIGH]
  - Fix options: (a) validate that the chosen aliases match the picker via `RAIL_CONFIG[...].aliasPattern` before submit; (b) explicitly send `origin_rail` / `destination_rail` hint to the API; (c) remove the pickers and have the form derive them from alias prefix in real time.

[MEDIUM] Validation: `formSchema` enforces `originRail !== destRail`, but the alias patterns in `src/lib/constants.ts:21-27` are not applied to `debtorAlias`/`creditorAlias`. A user can submit `debtor.alias = "garbage"` and the form will accept it; only the API rejects.

#### `src/app/simulator/page.tsx:1-567`
The mock control panel. Tabs PIX/SPEI/BRE_B. Excellent feature â€” the operator can change rejection rate, latency band, force reject/timeout next. Stats refresh every 5s. The whole thing is a custom Radix Tabs + sliders + toggle, no shadcn. Solid code. [INFO]

[LOW] The reset button uses `window.confirm` (line 545) â€” works but not stylistically consistent with the rest of the app's `toast` style. Consider a Radix Dialog confirm.

#### `src/app/translator/page.tsx:1-334`
Source rail picker, JSON textarea with live JSON validation, "translate to all" button. The user asked: "Does the translator page output canonical that matches mipit-core/src/canonical/?" â€” needs verification against core, but the **display** matches `mipit-docs/design/translation-layer.md:39-88` which describes the nested camelCase model (`grpHdr.msgId`, `amount.value`, etc.). The `SAMPLE_PAYLOADS` (lines 12-92) are realistic per-rail samples:
- PIX (lines 13-21): valid `endToEndId` 32-char format `E26264220...` per BACEN SPI v2.
- SPEI (lines 22-37): realistic `claveRastreo`, `cuentaBeneficiario` 18-digit CLABE, all CECOBAN fields present.
- SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW, BRE_B all reasonable.

[LOW] The "Modelo CanÃ³nico (pacs.008)" toggle label (line 303) implies a specific schema but the displayed JSON is whatever the back end returns â€” there's no UI-side schema validation that what came back actually matches pacs.008 fields.

### 2.3 Components

- `components/dashboard/recent-payments.tsx:1-101` â€” Polls every 15s, lists last 10. Defensive (`.catch(() => setPayments([]))`). Empty/loading states present.
- `components/dashboard/service-health.tsx:1-125` â€” Polls every 10s. Calls `/health` plus `/services/{rail}/health` for PIX/SPEI/BRE_B. Footer claims "7 rails soportados" (line 120) but only health-checks 3 â€” slight inconsistency. [LOW]
- `components/dashboard/stats-cards.tsx:1-104` â€” Computes stats **client-side** from a `listPayments({limit:200})` call. As payment history grows past 200, the dashboard becomes a lie. [MEDIUM] Should use `/analytics/summary`.
- `components/history/filters.tsx:1-77` â€” Status + rail selects, clear button, chip display. Clean.
- `components/history/payment-table.tsx:1-188` â€” Client-side sort + paginate over `listPayments({limit:100})`. Same scaling caveat as stats-cards. [MEDIUM]
- `components/layout/footer.tsx:1-8` â€” Trivial.
- `components/layout/navbar.tsx:1-98` â€” 7-link nav, mobile drawer, active-route highlight, accessible (`aria-label="Toggle menu"`). Good.
- `components/payments/flow-timeline.tsx:1-58` â€” 8-step timeline mapping to `STATUS_CONFIG[].step`. Renders compensation/dead-letter as terminal but doesn't visualize them as branches â€” `step: -2` and `-3` collapse to "isFailed". [LOW]
- `components/payments/message-inspector.tsx:1-39` â€” Three columns side-by-side `<pre>` blocks. No syntax highlighting. Functional.
- `components/payments/payment-card.tsx:1-17` â€” **DEAD CODE / TODO STUB**: `// TODO: Card summary for a single payment (used in lists/grids)` and renders `TODO: Payment card`. Not referenced anywhere. [MEDIUM] Delete or implement.
- `components/payments/payment-status-badge.tsx:1-17` â€” `// TODO: Style with proper badge component from shadcn/ui` â€” works but lingering TODO.
- `components/payments/rail-ack-panel.tsx:1-103` â€” Maps PIX/SPEI codes to human descriptions. Only covers AM04/RR04/DS04 (PIX) and R01/R03/LIM (SPEI). Missing BRE_B codes despite Bre-B being a full Option-B rail. [MEDIUM] The `mipit-ui/src/app/simulator/page.tsx:30-43` lists BREB001-BREB005 codes but `rail-ack-panel.tsx:31-43` doesn't translate them.
- `components/simulate/payment-form.tsx:1-20` â€” **DEAD CODE STUB**: renders `TODO: Formulario unificado`. Not used (`simulate/page.tsx` has its own inline form). [MEDIUM] Delete.
- `components/simulate/pix-form.tsx:1-13` â€” **DEAD CODE STUB**. Delete.
- `components/simulate/rail-selector.tsx:1-37` â€” Reusable but not used by `simulate/page.tsx` which inlines its own `RailPicker`. [MEDIUM] Delete one.
- `components/simulate/spei-form.tsx:1-13` â€” **DEAD CODE STUB**. Delete.

### 2.4 Hooks

- `hooks/use-payment.ts:1-32`, `use-payments.ts:1-38` â€” Fetch + loading + error, cancellation flag. Solid but **no polling** â€” page-level component does manual refresh. None of the pages actually use these hooks; `payments/[id]/page.tsx` and `dashboard/recent-payments.tsx` re-implement the fetch inline. [LOW] Either centralize on the hooks or remove them.
- `hooks/use-simulate.ts:1-30` â€” Generates UUID idempotency key per call via `crypto.randomUUID()`. Correct.
- `hooks/use-sse.ts:1-83` â€” EventSource with `connected` event + `payment_update` event handlers, 3s reconnect. The `useCallback(connect)` depends on `paymentId, maxEvents` â€” every change of `maxEvents` re-creates the source. Acceptable.

### 2.5 Lib

- `lib/api.ts:1-143` â€” Centralized client with token cache + refresh, bearer auth, idempotency-key support. Calls `${BASE_URL}/auth/token` to acquire JWT (lines 17-26). All endpoints used by the app are listed here. Token is stored in **module memory** â€” refresh page, refresh token. No localStorage leak. [INFO]
- `lib/constants.ts:1-31` â€” `STATUS_CONFIG` has 14 entries (`RECEIVED`, `VALIDATED`, `CANONICALIZED`, `ROUTED`, `QUEUED`, `SENT_TO_DESTINATION`, `ACKED_BY_RAIL`, `COMPLETED`, `FAILED`, `REJECTED`, `DUPLICATE`, `COMPENSATING`, `COMPENSATED`, `DEAD_LETTER`). [HIGH] **Drift with constants tests**: `src/__tests__/lib/constants.test.ts:11` asserts `Object.keys(STATUS_CONFIG).length` === 11 â€” this test must be currently failing (there are actually 14 entries). The user reports "11/11 green" but if `mipit-ui` Jest is included in the suite this assertion is red. Verified by reading both files: constants.ts has the 14 keys, the test expects 11. **The test is broken.**
- `lib/types.ts:1-98` â€” 14 PaymentStatus values (matches constants.ts). `Rail` is 7 values. `PaymentDetail` mirrors the API. No `trace_id`. No `audit_events`.
- `lib/utils.ts:1-7` â€” `cn()` helper. Standard.

### 2.6 Tests in UI

| File | Real assertions | Placebos |
|---|---|---|
| `__tests__/components/payment-status-badge.test.tsx` | 11 real status renders + 2 color-class checks | none |
| `__tests__/components/rail-ack-panel.test.tsx` | 8 real assertions (ACCEPTED, REJECTED, error codes, JSON expand) | none |
| `__tests__/hooks/use-payment.test.ts` | 4 real assertions w/ mocked api | mock shape uses old `origin`/`destination` field names not the current `origin_rail`/`destination_rail` â€” see line 11 |
| `__tests__/hooks/use-simulate.test.ts` | 5 real assertions including unique idempotency key | none |
| `__tests__/lib/constants.test.ts` | 11+ assertions BUT **expects 11 statuses** (constants has 14) and expects only `PIX,SPEI,SWIFT_MT103,ISO20022_MX,ACH_NACHA,FEDNOW,BRE_B` rails â€” that part matches | **drift in count: must be failing** [HIGH] |
| `test/components/payment-form.test.tsx` | 0 â€” all `it.todo()` | 8 todos |

Overall UI tests are honest but **stale**: `use-payment.test.ts:11-20` mocks a payment with `origin`/`destination` fields that the real `PaymentDetail` type calls `origin_rail`/`destination_rail`. The mock therefore tests the hook against a type the production code doesn't return.

---

## 3. Testkit audit + coverage matrices

### 3.1 Inventory

| File | Purpose | Real or placebo? |
|---|---|---|
| `e2e-verifications.mjs` (lines 1-100+ read) | 8 verification suites, 76 assertions | **REAL** â€” performs concurrent POSTs, idempotency stress, alias validation, FX, round-trip, error code coverage, webhooks, pipeline + audit |
| `e2e-load.mjs` (159 lines) | Async load test, configurable TOTAL/CONCURRENCY | **REAL** â€” sends N pagos w/ realistic CLABE/llave/CPF aliases, measures p50/p90/p95/p99 |
| `e2e-resilience.mjs` (222 lines) | Kills adapter container, verifies redelivery | **REAL but Docker-dependent** â€” uses `docker stop ${ADAPTER_CONTAINER}` and RabbitMQ Management API |
| `e2e-retry-timeout.mjs` (80 lines read) | Retry/timeout verification | **REAL with caveat** â€” admits it can't inject 503 cleanly and falls back to "log inspection + metrics counting" (see lines 14-21) |
| `e2e-schema-evolution.mjs` (80 lines read) | Backward-compat with minimal/full payloads | **REAL** â€” sends minimal & full PIX payloads, checks canonical preservation |
| `e2e-routing-correctness.mjs` (80 lines read) | Sends N per rail, verifies destination | **REAL** â€” distinct destination alias pools per rail, 333 default |
| `e2e-benchmark-latency.mjs` (60 lines read) | k6-style sustained load on 4 endpoints | **REAL** â€” DURATION_S Ã— RPS_TARGET, percentile computation |
| `e2e-roundtrip.sh`, `e2e-load.sh` | Wrappers | **REAL** |
| `logging.mjs` (164 lines) | Trace logger w/ redaction | **REAL** â€” redacts Authorization/token/secret keys (lines 5-48) |
| `tools/run-validation-suite.ts` (694 lines) | Master orchestrator | **REAL but counts 3 historical entries as passed without execution** (lines 487-509) [HIGH] |
| `tools/smoke-test.sh` (53 lines) | Curl-based health + create + poll | **REAL** but **does NOT send Authorization header** (lines 19-29) â€” will fail against current core which requires JWT [MEDIUM] |
| `tools/run-e2e.sh` | Wraps Jest E2E | **REAL** |
| `tools/generate-evidence.sh` | Collects /health + Prom metrics into folder | **REAL** |
| `tools/report.ts` | Summarizes batch-load JSON | **REAL** |

### 3.2 Jest `tests/` directory â€” the honesty problem

| File | Lines that actually assert real behavior | Placebos (`expect(true).toBe(true)`) | Verdict |
|---|---|---|---|
| `tests/contract/canonical-schema.test.ts` | reads fixture, checks `amount === 150.25` and `alias.startsWith('PIX-')` | 2Ã— `expect(true).toBe(true)` (lines 18, 35) | **placebo-heavy** [HIGH] |
| `tests/contract/openapi-validation.test.ts` | 0 real | **6Ã— `expect(true).toBe(true)`** (all `it()` bodies) | **100% placebo** [BLOCKER] |
| `tests/contract/rabbitmq-messages.test.ts` | 0 real | **5Ã— `expect(true).toBe(true)`** | **100% placebo** [BLOCKER] |
| `tests/e2e/batch-load.test.ts` | real fetch loop, real percentiles, asserts `successRate >= 0.9` | none | **REAL** |
| `tests/e2e/error-scenarios.test.ts` | real 400-on-zero-amount, real malformed-JSON | mid-scenario "if status==202â€¦ else" leniency at lines 43-64 means rejection path may be skipped | **partial** |
| `tests/e2e/idempotency-e2e.test.ts` | real same-key/same-id assertion + 5 concurrent | 1Ã— `expect(true).toBe(true)` at line 56 | **mostly real** |
| `tests/e2e/pix-to-spei.test.ts` | full E2E w/ poll; **expects 202** | None | **HIGH drift** â€” core returns 201 (see `fix_testkit.py:81` which fixes this; the test file shown to the auditor has `.toBe(202)` not `.toBe(201)`) |
| `tests/e2e/spei-to-pix.test.ts` | same shape as pix-to-spei | None | **HIGH drift** â€” same 202/201 issue |
| `tests/integration/core-api.test.ts` | real POST + GET, expects 202 | None | **drift** â€” should be 201 |
| `tests/integration/idempotency.test.ts` | real, no placeholders | None | **REAL** |
| `tests/integration/pipeline.test.ts` | real polling + canonical inspection | 2Ã— `expect(true).toBe(true)` lines 54, 60 | **partial** |
| `tests/integration/routing.test.ts` (329 lines) | dense, real, multi-rail, concurrent | None | **REAL** â€” and uses `expect(status).toBe(201)` (line 73 & elsewhere), so this one is *already adapted* to the new status code. The PIX/SPEI/BRE_B routing matrix here is the strongest contract test in the repo. |
| `tests/integration/translation.test.ts` | partial real (canonical.amount, canonical.debtor.rail) | 3Ã— `expect(true).toBe(true)` lines 33, 67, 75 | **partial** + uses outdated nested shape `detail.canonical.debtor.rail` which contradicts the new nested model (`canonical.debtor.account_id`, no `.rail` field per `translation-layer.md:68-77`) |

**The "76 assertions PASS" claim** in `E2E-VERIFICATION-RESULTS.md` is for `e2e-verifications.mjs` (which is real). It does NOT apply to `tests/contract/*` which are placeholders. The validation-suite report's "passed: 11" headline counts: 3 historical (paper), 5 repo Jest suites that include the UI's broken constants test if invoked, 8 verifications (real), routing correctness (real), load (real), benchmark (real). If `tests/contract/*` were properly executed the suite count would expose those placeholders â€” they only "pass" because `expect(true).toBe(true)` always passes.

### 3.3 Datasets reality check

- `datasets/pix/pix-valid-01.json:1-15` â€” `amount: 150.25`, `debtor.alias: "PIX-alice.silva.2026"`, `creditor.alias: "SPEI-012345678901234567"`. **CLABE 012345678901234567** has check digit **7**; BANXICO algorithm `(10 - sum%10)%10` with weights `[3,7,1,3,7,1...]` on `01234567890123456` (17 digits) gives sum=0Â·3+1Â·7+2Â·1+3Â·3+4Â·7+5Â·1+6Â·3+7Â·7+8Â·1+9Â·3+0Â·7+1Â·1+2Â·3+3Â·7+4Â·1+5Â·3+6Â·7 = 0+7+2+9+28+5+18+49+8+27+0+1+6+21+4+15+42 = 242. 242%10=2. (10-2)%10 = 8. **Expected check digit: 8, not 7.** [HIGH] The dataset CLABE is mathematically invalid. (This is exactly what `fix_testkit.py:17-30` was written to fix; presumably ran on the VM but the local Windows working copy still has the bad digit.)
- `datasets/pix/pix-valid-02.json` â€” same pattern likely; same fix script.
- `datasets/pix/pix-invalid-alias.json:1-15` â€” `"INVALID!!@@##$$"` â€” clearly invalid, fine.
- `datasets/pix/pix-invalid-amount.json` â€” `amount: 0` â€” fine.
- `datasets/spei/spei-invalid-clabe.json` â€” `"SPEI-12345"` (5 digits) â€” fine.
- `datasets/spei/spei-valid-01.json` â€” `cuentaBeneficiario: "SPEI-987654321098765432"` â€” check digit similar issue, again probably patched only on VM.
- `datasets/expected/canonical-to-pix-01.json:1-19` â€” flat fields (`amount`, `currency`, `rail_format`, `pix_metadata.key_type`). This shape **does not match** the nested camelCase canonical (`grpHdr.msgId`, `amount.value`, `pmtId.endToEndId`) that the real core uses per `translation-layer.md:39-88`. The expected output describes a different/older translation layer. [HIGH]
- `datasets/expected/pix-to-canonical-01.json:1-25` â€” flat `canonical.amount`, `canonical.debtor.rail`. **Same drift.**

**No `datasets/breb/*` directory exists.** Bre-B has no fixture coverage at the dataset layer despite being a full Option-B rail. [HIGH] No `breb` generator under `generators/`. The generators directory only has `generate-pix.ts`, `generate-spei.ts`, `generate-batch.ts`, `utils.ts`. The batch generator only mixes PIX+SPEI (line 4: `type Rail = 'PIX' | 'SPEI'`).

### 3.4 Coverage matrices

#### Rail-pair E2E coverage (does the testkit prove that pair actually works end-to-end?)

| Fromâ†“ / Toâ†’ | PIX | SPEI | Bre-B |
|---|---|---|---|
| PIX | n/a | YES (`tests/e2e/pix-to-spei.test.ts`, `integration/routing.test.ts:64-91`, `e2e-routing-correctness.mjs` lines 22-44, `e2e-verifications.mjs` round-trip) | YES (`integration/routing.test.ts:94-136`, `e2e-routing-correctness.mjs`) |
| SPEI | YES (`tests/e2e/spei-to-pix.test.ts`, `integration/routing.test.ts:264-281`) | n/a | YES (`integration/routing.test.ts:138-152`) |
| Bre-B | YES (`integration/routing.test.ts:154-167`) | NO direct test (covered only by smoke implicit) | n/a |

`tests/integration/routing.test.ts` is the most complete rail-pair matrix file in the repo.

#### Resilience scenarios

| Scenario | Covered where | Strength |
|---|---|---|
| Broker down at publish | NOT explicit | gap |
| Broker down mid-consume | NOT explicit | gap |
| Adapter dies after pulling msg | `e2e-resilience.mjs` Phase 3-6 | REAL (Docker) |
| Adapter responds 500 | `e2e-retry-timeout.mjs` (indirect, via logs+metrics) | partial â€” can't inject 503 cleanly |
| Adapter responds 4xx | `e2e-verifications.mjs` test 6 (rejection codes per rail) | REAL |
| Adapter times out | `e2e-retry-timeout.mjs` + `simulator` force-timeout endpoint | REAL |
| DB primary down | NOT covered | gap |
| DLQ requeue | `e2e-resilience.mjs` Phase 4 (depth check + final drain) | partial â€” doesn't verify DLQ-specific routing |
| Reconnect | `use-sse.ts:64-68` (client-side); `amqplib` auto in core (untested) | partial |
| Duplicate publish (idempotency) | `e2e-verifications.mjs` test 1 (100 concurrent same key) | STRONG |
| Out-of-order ACK | NOT covered | gap |
| Compensation flow | `lib/api.ts:103-110` and `/compensate/batch` exists but no E2E test | gap |
| Webhook delivery failure | `e2e-verifications.mjs` test 7 (success only) | partial â€” happy path only |

[HIGH] Resilience gaps are documented as "the work the testkit did" but several plausible failures (broker outage, DB primary down, DLQ requeue contents, out-of-order ack, compensation E2E) have **zero coverage**.

### 3.5 Evidence pipeline

- 12 evidence/suite/ runs between 2026-05-08 and 2026-05-15. Most recent: `2026-05-15T15-38-43-765Z/validation-suite-report.md`.
- All recent ones report **passed: 11, failed: 0, skipped: 0**.
- The headline is defensible *only if* you treat "historical-load / historical-routing / historical-verifications" as passed-by-declaration. They have `durationMs: 0` and the report note literally says: `"Resultado histÃ³rico documentado, no re-ejecutado en esta corrida."` [HIGH for the headline; INFO for the orchestrator design]

The orchestrator does this **on purpose** â€” see `tools/run-validation-suite.ts:487-509`: scenarios are constructed with `summary: summarizeHistoricalLoad()` and **no command**, so `executeScenario` short-circuits at lines 371-383 to "PASSED (documented/historical scenario)". This is not fraud â€” it is openly labeled â€” but a busy reader will see "11/11" and miss the asterisk.

---

## 4. ADR-by-ADR drift analysis

### ADR-001: TypeScript + Node 22 + Fastify
**Decision:** Backend in TS/Node, Fastify for the core.
**Implementation:** Confirmed in package.json files across mipit-core and adapters (not audited here but referenced by `mipit-testkit/tools/run-validation-suite.ts:511-531` running `npm test` in each).
**Drift:** None visible. [INFO]
**Note:** SRS Table 2.1 (line 380+ of SRS) listed "Spring Boot" alongside Node/Next.js. ADR-001 supersedes that. The Diseno PDF at section 3.1.2 (`/tmp/dis.txt:740-780`) and 3.1.3 (lines 1380-1400 of SRS) **still mention Spring Boot** â€” drift between the original design docs and the ADR. [MEDIUM]

### ADR-002: Canonical pacs.008 (JSON, not XML)
**Decision:** JSON canonical aligned to ISO 20022 pacs.008.
**Implementation:** Per `translation-layer.md:39-88`, the canonical is nested camelCase (`grpHdr.msgId`, `amount.value`, `pmtId.endToEndId`, `origin.rail`, `destination.rail`).
**Drift:** Massive between this and `mipit-docs/mappings/canonical-fields.md`, which describes a flat snake_case schema (`msg_id`, `creation_date_time`, `debtor.alias_type`). Same drift in CSVs. The CSV/`canonical-fields.md` shape is **also** what `tests/integration/translation.test.ts:27-28` expects (`detail.canonical.debtor.rail`). The translator page sample and ADR-002's design intent use the nested camelCase. **Two contradictory canonical specs exist in the repo.** [HIGH]

### ADR-003: RabbitMQ with topic exchanges + DLQ
**Decision:** `mipit.payments` topic exchange, `route.{pix|spei}` keys, `mipit.dlx` DLQ.
**Implementation:** Per `E2E-VERIFICATION-RESULTS.md:303-313`, exchanges and queues exist; resilience test (`e2e-resilience.mjs`) talks to `payments.route.pix` and RabbitMQ Management API.
**Drift:** ADR-003 says `route.pix / route.spei` (no Bre-B). Implementation per `E2E-VERIFICATION-RESULTS.md:305-307` includes `route.breb` plus `dlq.breb`. **ADR-003 was never updated when Bre-B was added.** [MEDIUM] Also: ADR-003 says queue name `q.adapter.pix`; actual queue name is `payments.route.pix`. [LOW] `contracts/rabbitmq-messages.md:6-15` matches ADR-003's older names â€” **two queue-naming schemes documented in the repo**. [MEDIUM]

### ADR-004: Idempotency-Key header
**Decision:** UUID, hash+payload stored, 409 on conflict.
**Implementation:** `e2e-verifications.mjs` test 1 (100 concurrent â†’ 1 create + 99 cached, 409 on different payload). `tests/integration/idempotency.test.ts` matches. `mipit-ui/src/hooks/use-simulate.ts:16` generates `crypto.randomUUID()`. **No drift.** [INFO]

### ADR-005: JWT (HS256) + HTTPS
**Decision:** Static demo JWT, HS256, self-signed certs via Nginx.
**Implementation:** UI fetches `/auth/token` (`lib/api.ts:20`), caches it (lines 14-25). The smoke-test.sh **does NOT add Authorization header** (lines 19-29) â€” this script will fail on a JWT-protected core. [MEDIUM] The OpenAPI spec at line 21 declares `security: [bearerAuth]` globally and exempts `/health` and `/metrics` (lines 203, 224), but **does NOT declare `/auth/token`** as an endpoint at all. [HIGH]

### ADR-006: PostgreSQL with jsonb
**Decision:** Postgres 16 + jsonb payload columns.
**Implementation:** Per SRS section 3.6 and matches the seed/migration path documented in `plans/PLAN-DE-DESARROLLO.md` Semana 5 (CORE-008+). Not directly verifiable from the four repos audited but cross-references are consistent. [INFO]

### ADR-007: Hybrid modular architecture
**Decision:** Modular monolith in core, choreography via RabbitMQ to adapters, independent Docker deployment per component.
**Implementation:** Confirmed by the `architecture-overview.md:14-36` diagram. Aligns with what UI sees and what testkit attacks. [INFO]

### ADR-008: OpenTelemetry + Prometheus + Grafana
**Decision:** Three pillars; W3C Trace Context propagation; `trace_id` in messages.
**Implementation:** RabbitMQ contracts (`contracts/rabbitmq-messages.md:33-67`) include `trace_id`; testkit's `logging.mjs` redacts auth headers; benchmark and load tests stream traces. **BUT**: `mipit-ui/src/lib/types.ts:26-51` `PaymentDetail` has no `trace_id` field, the OpenAPI `PaymentDetail` schema has no `trace_id`, the UI payment-detail page never shows it. Jaeger link never surfaces. **ADR-008's "evidence for the thesis" promise is partially unmet at the UI layer.** [HIGH]

---

## 5. OpenAPI spec vs implementation

`mipit-docs/openapi/openapi.yaml:1-491` is **out of date in many places**:

| Spec says | Reality |
|---|---|
| `POST /payments` returns **202** | Returns **201/200** per `tests/integration/routing.test.ts:73` and `fix_testkit.py:80` |
| `destination` enum `[PIX, SPEI]` (line 173, 300) | Real `Rail` is 7 values |
| `PaymentStatus` enum has 11 entries (line 428-441) | Code (`src/lib/types.ts:3-17`) has **14** entries â€” missing `COMPENSATING`, `COMPENSATED`, `DEAD_LETTER` |
| `Idempotency-Key` is **required** (line 44) | Reality: API treats it as optional / generates one if missing |
| Endpoint `/translate` â€” NOT in spec | UI uses it (`lib/api.ts:71-75`) |
| Endpoint `/translate/preview` â€” NOT in spec | UI uses it heavily |
| Endpoint `/translate/rails` â€” NOT in spec | UI uses it |
| Endpoint `/analytics/summary`, `/analytics/latency`, `/analytics/circuit-breakers`, `/analytics/rate-limits`, `/analytics/reconciliation` â€” NOT in spec | UI uses all five |
| Endpoint `/services/{rail}/health` â€” NOT in spec | UI uses it on dashboard |
| Endpoint `/events/payments`, `/events/payments/{id}` (SSE) â€” NOT in spec | UI uses it for `/live` |
| Endpoint `/compensate/{paymentId}`, `/compensate/batch` â€” NOT in spec | UI exposes API stubs (`lib/api.ts:103-110`) |
| Endpoint `/mocks/{rail}/admin/{stats|config|reject-next|timeout-next|reset}`, `/mocks/{rail}/health` â€” NOT in spec | UI Simulator page uses all of them |
| Endpoint `/auth/token` â€” NOT in spec | UI requires it |
| `Party.alias` description (line 277) â€” "Clave PIX, CLABE, nÃºmero de cuenta" | Implementation uses prefixed aliases `PIX-â€¦`, `SPEI-â€¦`, `BREB-â€¦` (per testkit and UI placeholders); spec doesn't mention the prefix convention |
| `PaymentDetail.timestamps.received_at` (line 350) | Code uses `created_at` (per `src/lib/types.ts:43`); spec field name doesn't exist in actual API response |

[BLOCKER] The OpenAPI spec is a 2-rail starter document; the real API is a multi-rail platform with 20+ additional routes.

---

## 6. Mapping CSVs vs translators

The four CSVs (`pix-to-canonical.csv`, `canonical-to-pix.csv`, `spei-to-canonical.csv`, `canonical-to-spei.csv`) describe a **flat snake_case canonical** with fields like `canonical.msg_id`, `canonical.amount`, `canonical.debtor.alias_type`. The implementation per `translation-layer.md:39-88` uses **nested camelCase** (`grpHdr.msgId`, `amount.value`, `amount.currency`, `pmtId.endToEndId`, `origin.rail`, `destination.rail`, `alias.type`).

**Drift examples:**
- CSV says `canonical.creation_date_time`; code uses `grpHdr.creDtTm`.
- CSV says `canonical.debtor.alias_type` enum `CPF/CNPJ/PHONE/EMAIL/EVP/CLABE/PHONE_MX/CARD`; code uses `alias.type` enum `PIX_KEY/CLABE/IBAN/ACCOUNT/ABA_ROUTING/BIC`.
- CSV says `canonical.source_rail` enum `[PIX, SPEI]`; code uses `origin.rail` enum of 7 rails.

[HIGH] **None of the four CSVs reflect the current translator.** They were authored against an earlier (flat) canonical and never re-issued. The `canonical-fields.md` likewise. There are **no CSVs for BRE_B, SWIFT_MT103, ISO20022_MX, ACH_NACHA, FEDNOW** â€” 5 rails undocumented at the mapping layer. [HIGH]

---

## 7. Route rules YAML vs DB seed

`mipit-docs/route-rules/rules.yaml:1-67` defines 5 rules: `clabe_to_spei`, `cpf_to_pix`, `phone_br_to_pix`, `phone_mx_to_spei`, `email_to_pix`. They evaluate `canonical.creditor.alias_type` and `canonical.creditor.alias` (snake_case, flat).

The actual routing implementation is **alias-prefix-based** per:
- `mipit-ui/src/app/simulate/page.tsx:34-42` placeholders (PIX-..., SPEI-..., BREB-...).
- `e2e-routing-correctness.mjs:22-44` destination alias pools.
- `tests/integration/routing.test.ts:64-167` uses `PIX-joao@email.com â†’ SPEI-012180000118359719 â†’ routes to SPEI`. **The destination is decided by `SPEI-` prefix, not by `CLABE` alias_type detection.**
- `plans/CONTEXTO-MIPIT.md:91` describes "Inferir rail origen del alias del debtor (PIX- o SPEI-)".

[HIGH] `rules.yaml` and `route-rules/examples.md` describe a *semantic* (alias_type-based) routing engine that **doesn't reflect the implemented prefix-based router**. The YAML is aspirational design, not current. There's also no rule for `breb_to_...` despite Bre-B being live.

---

## 8. Design docs vs implementation

- `design/architecture-overview.md:14-36` â€” Diagram shows PIX/SPEI only. **Bre-B missing.** [MEDIUM]
- `design/translation-layer.md:22-32` â€” Lists 6 rails (PIX, SPEI, SWIFT, ISO20022_MX, ACH, FedNow) but **omits BRE_B**. The actual UI supports 7 (BRE_B included). [HIGH]
- `design/adding-a-new-rail.md` â€” Uses Bizum (EspaÃ±a) as the hypothetical example. Steps are reasonable; checklist matches the implementation pattern. No drift, but it doesn't mention that this is what was actually done for BRE_B. [LOW]
- `design/next-steps.md` â€” Date-of-writing references "this week" but no date stamp; references SEPA CT as the recommended 5th rail; documents k6 / wrk benchmarks. Practical but stale around what's already done (BRE_B + 4 translator-only rails). [LOW]
- `contracts/payment-status-machine.md:1-99` â€” Documents 11 states. Code has 14 (compensation + dead-letter). [HIGH] No transitions for `COMPENSATING â†’ COMPENSATED â†’ COMPLETED` documented.
- `contracts/error-codes.md:1-68` â€” Catalog uses generic `PIX_INSUFFICIENT_FUNDS`, `SPEI_INVALID_CLABE`. Actual mock servers per `E2E-VERIFICATION-RESULTS.md:135-175` use **BACEN/CECOBAN/BREB-real codes** (AM04, RR04, R01, R03, BREB001-BREB005). The doc names don't appear anywhere in code. [HIGH] The doc has **no Bre-B section**.
- `contracts/rabbitmq-messages.md:1-167` â€” `route.pix / route.spei`, `q.adapter.pix / q.adapter.spei`. Reality uses `payments.route.pix / .spei / .breb`. [MEDIUM] Bre-B contracts missing.

---

## 9. Demo runbook walkthrough

`demo-runbook/local-demo.md:11-95`:
- Step 1: `cd mipit-infra && bash scripts/up.sh` â€” relies on a script not audited but referenced consistently.
- Step 2 health-check expected output mentions `mipit-ui â†’ localhost:443 (via Nginx)`. UI port-3000 also exposed (Dockerfile EXPOSE 3000). [LOW]
- Step 3 URLs: Grafana on 3000 (collides with Next.js dev on 3000 if both run). [LOW]
- Step 4 PIX â†’ SPEI form: tells user to put `+5511999887766` in the debtor alias field. **Reality**: the UI's form validates that aliases follow `PIX-â€¦` prefix per `RAIL_CONFIG[].aliasPattern` *intent* (though not enforced at submit â€” see UI audit Â§2.2). Runbook example would fail validation in some setups and silently succeed in others. [MEDIUM]
- Step 7 idempotency: says "El estado debe mostrar `DUPLICATE`". The actual state machine and impl makes the *second* call return cached response; the payment itself does not become DUPLICATE â€” it stays in whatever state it was. [MEDIUM]

`demo-runbook/vm-demo.md:1-167`: Three-VM topology. Says VM IPs `192.168.1.10/.11/.12`. **CONTEXTO-MIPIT.md** says current VMs are at `10.43.101.29` (per `fix_testkit.py:156-161`). [HIGH] VM IPs are placeholders.

`demo-runbook/checklist-pre-demo.md:1-42`: Checklist mentions `q.adapter.pix / q.adapter.spei / q.core.ack`. Reality (per E2E doc) uses `payments.route.pix / .spei / .breb`. [MEDIUM]

---

## 10. Plans audit + ticket completion tally

`plans/PLAN-DE-DESARROLLO.md` defines **96 tickets across 17 weeks**. Weeks 5-7 are marked completed in CONTEXTO-MIPIT.md.

| Week | Status per plan | Cross-check vs CONTEXTO-MIPIT.md / repo evidence |
|---|---|---|
| 1-4 | Planning | Out of scope for ticket count |
| 5 | âœ… 13 tickets (INFRA-001/002, CORE-001 to CORE-011) | CONTEXTO-MIPIT.md:124 confirms; ~57 unit tests claimed |
| 6 | âœ… 13 tickets (CORE-012 to CORE-024) | CONTEXTO-MIPIT.md:125 confirms; ~110 tests claimed; FX cross-currency mentioned |
| 7 | âœ… Pipeline + ack consumer + SQL fix + 150 tests | CONTEXTO-MIPIT.md:126; matches mipit-testkit assertions |
| 8 | â³ Per CONTEXTO-MIPIT.md, but `tests/integration/core-api.test.ts` already exercises POST/GET â†’ API is **clearly implemented**; CONTEXTO-MIPIT is stale | [HIGH] CONTEXTO-MIPIT-2026-05-16 still says "Semana 8 prÃ³xima" â€” but tests prove the API exists and the validation suite ran successfully on 2026-05-15 |
| 9 | â³ adapters | Adapters exist (audited as full mock + worker + publisher per `e2e-resilience.mjs` referencing them) |
| 10 | â³ UI | UI exists and is rich (this audit) |
| 11-17 | â³ Test E2E, deploy, etc. | Validation suite + evidence/ folder + `mipit-docs/testing/local/2026-05-15...` runs all confirm execution |

**Plans drift summary**: At least 8 weeks of work have been completed past the CONTEXTO-MIPIT snapshot. The repo is at week 13-14 by deliverable, not week 8. [HIGH] CONTEXTO-MIPIT.md needs an update before sharing with another Cursor session.

Other plan files:
- `FIX-SQL-QUERIES.plan.md`, `CORE-028/029/030.plan.md` â€” task-specific plans, presumably completed (CORE-028 is "pipeline" referenced as done).
- `mipit-*.plan.md` â€” repo-level plans, not audited line-by-line.
- `REFERENCIAS-PASARELAS.md:1-60+` â€” Citations to BACEN PIX OpenAPI, BCB DICT, PIX Tester, manual de padrones. All URLs are real-world authoritative; cannot verify without web fetch but `bacen/pix-api` GitHub is correct. [INFO]
- `TAREAS-SEMANA-7.md`, `TAREAS-SEMANA-8.md`, `TAREAS-SEMANALES-NICOLAS.md` â€” Per-week ticket detail; consistent with main plan.

---

## 11. PDF audit

### 11.1 `SRS_MIPIT.pdf` (65 pages)

**Summary**: SRS IEEE-830 styled. Defines PoC scope: API unificada, traductor canÃ³nico bidireccional, normalizador, enrutador inteligente, adaptadores PIX/SPEI, persistencia, observabilidad, UI. Functional requirements RF01-RF20 (page 36-37). Section 2.1.3 promises 3 VMs. Section 2.1.4 lists software stack including PostgreSQL 16, Next.js 14, OpenTelemetry. Section 3.4 imposes architecture as "API Gateway + microservices". Section 3.5.5 requires throughput >=100 tx/session and >=99.9% delivery success rate.

| Requirement | Implementation status | Evidence |
|---|---|---|
| RF01 POST /payments | âœ… | `tests/integration/core-api.test.ts`, `lib/api.ts:48-53` |
| RF02 payment_id generation + persistence | âœ… | `PMT-{ulid}` format per `tests/e2e/pix-to-spei.test.ts:23` |
| RF03 immediate acknowledgement | âœ… | Returns 201/200 with payment_id |
| RF04 PIX/SPEI â†’ ISO 20022 canonical | âœ… but drift | Real impl is nested camelCase; CSVs say flat |
| RF05 structure + obligatoriness validation | âœ… | Zod schemas, 400 on invalid amount |
| RF06 MappingTable rules | partial | DB-backed (per PLAN week 5), but YAML+CSV docs drifted [MEDIUM] |
| RF07 RouteRule destination resolution | âœ… but **drift in rule shape**: code uses prefix, docs use alias_type | [HIGH] |
| RF08 HTTP to adapter | âœ… via RabbitMQ |
| RF09 adapter response processing | âœ… via ack queue |
| RF10 sandbox connection | âœ… but mocks, not real BACEN/Banxico (acknowledged in plan) |
| RF11 ACCEPTED/REJECTED | âœ… |
| RF12 latency + error logging | âœ… (Prometheus + Jaeger) |
| RF13 AuditEvent | âœ… (`E2E-VERIFICATION-RESULTS.md:222-235` shows 6 audit events) |
| RF14 Prometheus metrics | âœ… |
| RF15 Grafana dashboards | âœ… (`mipit-observability` repo, not audited) |
| RF16 UI flow visualization | âœ… FlowTimeline component |
| RF17 simulation start + observe | âœ… Simulate page |
| RF18 translated messages, sandbox responses, metrics | âœ… MessageInspector + RailAckPanel + Analytics |
| **RF19 export CSV/JSON** | âŒ **NOT IMPLEMENTED** | No export feature in UI. [HIGH] |
| RF20 restart between sessions | âœ… via `docker-compose down -v && up -d` and `/mocks/{rail}/admin/reset` |

**Non-functional gaps**:
- 99.9% delivery rate (SRS 3.5.5) â€” claimed validated by `999/999 100% routing accuracy` (E2E-VERIFICATION-RESULTS.md). [OK]
- 15s max response (SRS 3.5.5) â€” load test p99 = 250ms historical, well under. [OK]
- TLS 1.3 (SRS 3.5.2) â€” Self-signed cert per ADR-005. [OK for PoC]
- API Key (SRS 2.1.5, 3.1.4) â€” Implementation uses JWT, not API Key. Slight semantic drift but functionally equivalent. [LOW]
- mTLS for production â€” Documented as future work, not implemented. [Documented as OK]

### 11.2 `Diseno_MIPIT.pdf` (multi-section design spec, 64 pages)

**Summary**: v0.2 design spec. Restates SRS, adds 4+1 architecture views, defines API endpoints `POST /transactions` + `GET /transactions/{transactionId}`, message contracts, idempotency, error codes, ISO 20022 subset structures, mapping table format, routing engine semantics, observability dashboards, traceability matrix RF/RNF â†’ component â†’ evidence, risks & mitigations.

**Gaps with implementation**:
- Endpoints: **Diseno uses `/transactions`; implementation uses `/payments`**. Acknowledged in `plans/PLAN-DE-DESARROLLO.md:22-23` as deliberate naming change. [INFO]
- Diseno request fields: `sourceAccount`, `destinationAccount`, `destinationRail`, `metadata`. Implementation uses `debtor`, `creditor`, `purpose`, `reference` (no destinationRail â€” inferred). Schema rename. [MEDIUM]
- Status enums per Diseno: `RECEIVED, PROCESSING, SUCCESS, FAILED`. Code uses 14 statuses. [HIGH] Doc never updated.
- Section 4.5.1 RouteRule schema in Diseno aligns with current implementation **better** than the YAML rules.yaml does.
- Section 3.1.2 talks about Spring Boot â€” drift with ADR-001. [MEDIUM]

### 11.3 `Informacion del diseno.pdf` (insumos para diseno, ~10 pages)

**Summary**: Pre-design inputs/notes. Lists what's IN/OUT of the PoC. Endpoints listed: `POST /payments`, `GET /payments/{id}`, optional `/health`, `/metrics`. JWT auth, Idempotency-Key, X-Trace-ID. Mentions RabbitMQ confirmed, Nginx/API Gateway as "yes (may change)".

This document is **closest to what was actually built**. It's the practical pre-design that superseded the more formal Diseno_MIPIT.pdf endpoints. [INFO]

### 11.4 `Plantilla Propuesta Proyecto Middleware.pdf` (~20 pages)

**Summary**: The thesis proposal. Title: "EvaluaciÃ³n de una Arquitectura de Interoperabilidad Basada en ISO 20022 para Pagos InstantÃ¡neos Transfronterizos". General objective evaluates a prototype with **PIX, SPEI, FedNow, bre-b** as the four target rails. Specific objectives: review state of art, develop semantic translator, implement intelligent router, evaluate with sandbox + metrics. Deliverables: arch document, translator PoC, router PoC, demo of cross-border payment.

**Drift with delivery**:
- Promised: 4 rails (PIX, SPEI, FedNow, bre-b) **as evaluable rails**. Delivered: PIX, SPEI, BRE_B with full mock + adapter; **FedNow as translator-only (Option A)**, plus 3 bonus translators (SWIFT_MT103, ISO20022_MX, ACH_NACHA). Net win on breadth, **but FedNow lacks an Option-B adapter** which arguably matters for "evaluation" per the proposal. [MEDIUM]
- Phase 3 deliverable: "Medir mÃ©tricas de latencia, correctitud en las transformaciones, tasa de Ã©xito" â€” fulfilled via `e2e-benchmark-latency.mjs`, `e2e-load.mjs`, `e2e-verifications.mjs`. [OK]
- "Mocks de bancos origen y destino" â€” fulfilled per `/mocks/{rail}/admin/*` admin API. [OK]
- "Reintento" scenarios â€” fulfilled by `e2e-retry-timeout.mjs` (partially). [OK]

### 11.5 `SPMP.pdf` (Software Project Management Plan, large)

**Summary**: DSR-based methodology, 16-week schedule (S1-S16), 5 milestones H1-H5: H1 (problem + criteria), H2 (architecture validated), H3 (first E2E with 2 rails), H4 (evaluation with 4 rails), H5 (article + demo). Deliverables include "documento de arquitectura, mapeos, PoC operativo, plan de pruebas, reporte de mÃ©tricas, anÃ¡lisis comparativo, artÃ­culo acadÃ©mico".

**Drift with execution**:
- Schedule: SPMP says **16 weeks** total. CONTEXTO-MIPIT says **17 weeks**. PLAN-DE-DESARROLLO says 17 weeks. [LOW] minor off-by-one â€” likely from including week 0 as planning.
- H3 promised "first E2E with 2 rails". Delivered: full E2E with 3 rails (PIX, SPEI, BRE_B). [OVER-DELIVERED]
- H4 "evaluation with 4 rails". Delivered: 3 fully-evaluable + 4 translator-only. Strict reading of "evaluation" with 4 rails is **not met** since only 3 are end-to-end. [MEDIUM] â€” Defendable as "7 rails covered at translator level, 3 at full pipeline level".
- H5 academic article: Not in this audit's scope.

---

## 12. CONTEXTO-MIPIT.md drift

The file dated **today (2026-05-16)** says "Semanas 5, 6 y 7 completadas. PrÃ³xima: Semana 8." (line 13).

This is **clearly stale**. Evidence:
- `evidence/suite/2026-05-15T15-38-43-765Z/validation-suite-report.md` proves the full stack ran end-to-end with all 11 scenarios green on 2026-05-15 â€” that requires API (week 8), adapters (week 9), UI (week 10) and testing (week 11+) all done.
- `mipit-ui/src/app/` has 8 working pages with real backend integration.
- `tests/integration/routing.test.ts` exercises Bre-B routing â€” that's well past Week 9.
- The plan's Week 11-17 deliverables (E2E test suite, deploy, observability dashboards, demo runbook) all exist in the repos audited.

Other drift in CONTEXTO-MIPIT.md:
- Line 27 says "mipit-ui: React, TypeScript, Vite". Reality: **Next.js 15** (no Vite). [HIGH] â€” same on line 113.
- Line 56: branches `Nicolas_05, Nicolas_06, Nicolas_07, carlos_05` â€” current branch nomenclature is unclear but the timestamp suggests work is well past these.
- Line 108: "RabbitMQ 3.12+". Reality per `E2E-VERIFICATION-RESULTS.md:5`: **3.13**.
- Line 89-97 describes a "7-step pipeline". Implementation flows through ~8 states ACKED_BY_RAIL â†’ COMPLETED.

**Recommendation**: Rewrite CONTEXTO-MIPIT.md to reflect 2026-05-15 reality before next context-transfer. [HIGH]

---

## 13. Dead code in repo root

### `fix_testkit.py` (188 lines)

A one-shot Python migration script written for a Linux VM session:
- Hardcoded paths: `BASE = '/home/estudiante/tesis/mipit-testkit'` (line 12), `INFRA_ENV = '/home/estudiante/tesis/mipit-infra/env/ui.env'` (line 13). Will not run on Windows.
- 5 fix categories: (1) corrects CLABE check digits in test/dataset files via BANXICO algorithm, (2) injects an `authedFetch` wrapper + `beforeAll(/auth/token)` block into Jest tests, (3) rewrites `expect().toBe(202)` to `.toBe(201)` for the new core status code, (4) removes a broken `helpers/auth.js` import from `routing.test.ts`, (5) updates `ui.env` to point at the VM IPs (`10.43.101.29:9001/9002/9003`).
- Useful evidence of what *should* have been applied to the tests/datasets, but **on the local Windows workspace the changes appear NOT to have been committed** â€” verified by checking `tests/integration/core-api.test.ts:21` still says `.toBe(202)` and `datasets/pix/pix-valid-01.json:9` still has CLABE `012345678901234567` (wrong check digit, see Â§3.3).

**Recommendation**:
- [HIGH] Move to `scripts/migrations/2026-05-fix-testkit-for-vm.py` for archival.
- [HIGH] Re-run a Windows-portable version that does the same patches locally, then commit. Alternatively, accept the divergence as "VM-only" and document.

No other dead `.py` or `.sh` at root other than what's already audited.

---

## 14. What was DONE WELL

1. **`tests/integration/routing.test.ts` (329 lines)** â€” Best file in the testkit. Real PIXâ†”SPEI, PIXâ†”BRE_B, SPEIâ†’BRE_B, BRE_Bâ†’PIX coverage with concurrency + idempotency.
2. **`e2e-verifications.mjs` + `E2E-VERIFICATION-RESULTS.md`** â€” 76 honest assertions across 8 dimensions (idempotency, alias validation, FX, round-trip, limits, error codes, webhooks, audit). Documented per rail with real per-code occurrence counts (AM04: 39, R01: 40, BREB001: 86, etc.).
3. **`tools/run-validation-suite.ts`** â€” Cross-platform (Windows `.cmd` handling at lines 47-49), env-file loading, scenario abstraction, per-tool result parsers, JSON+Markdown report. Architecturally clean.
4. **`mipit-ui/src/app/simulator/page.tsx`** â€” Production-quality control panel with debounced sliders, optimistic config push with rollback on error, snapshot caching per rail, and 5-second stat refresh decoupled from full reload.
5. **`mipit-ui/src/app/analytics/page.tsx`** â€” Defensive parsing throughout. Handles `success_rate` as either 0â€“1 or 0â€“100. Graceful empty/error/loading states.
6. **`mipit-ui/src/lib/api.ts` token cache** â€” Module-scoped cache with 60-second pre-expiry refresh window (line 24). Stops both leaking JWT to localStorage AND hammering `/auth/token`.
7. **`mipit-ui/src/hooks/use-sse.ts`** â€” Auto-reconnect, named events (`connected`, `payment_update`), `maxEvents` ring-buffer, cleanup on unmount.
8. **ADR-001 through ADR-008** â€” Each ADR has Status / Date / Context / Decision / Alternatives table / Reasons / Consequences. Solid template adherence. Even where the ADR drifted from implementation, the **structure** is exemplary.
9. **`mipit-docs/design/translation-layer.md`** â€” Most accurate document in the repo. Describes Option A (translator only) vs Option B (full adapter), hub-and-spoke pattern, file layout, per-rail format details with real protocol references (BACEN ISPB, BANXICO CLABE algorithm with the actual weights, NACHA 94-char record types, FedNow UETR + USABA).
10. **`mipit-docs/design/adding-a-new-rail.md`** â€” Excellent extensibility doc. Step-by-step with code skeletons, checklist for Option A and Option B, time estimates (2-4h vs 1-2 days). The Bizum example is concrete enough to actually follow.
11. **`mipit-testkit/logging.mjs`** â€” Centralized trace logger with sensitive-key redaction (`SENSITIVE_KEY = /(authorization|token|secret|password|jwt)/i`) â€” proper hygiene rare in PoC tooling.
12. **Validation-suite reports under `evidence/suite/`** â€” 12 timestamped runs with full JSON + Markdown + per-scenario .log files. Excellent audit trail.

---

## Sources

PDF pages consulted (all under `C:\Users\nicog\Documents\Tesis\`):
- `SRS_MIPIT.pdf` pages 1-46 (sections 1, 2, 3.1-3.6, 4)
- `Diseno_MIPIT.pdf` pages 1-30 (TOC, section 4.1 endpoints, section 4.5 routing)
- `Plantilla Propuesta Proyecto  Middleware.pdf` pages 1-12 (objectives, deliverables, phases)
- `SPMP.pdf` pages 1-25 (TOC, milestones, DSR phases)
- `Informacion del diseno.pdf` page 1 (scope inputs)

Repo files cited above with line numbers â€” full path always under `C:\Users\nicog\Documents\Tesis\{repo}\â€¦`. Key files:
- `mipit-ui/src/{app,components,hooks,lib,__tests__,test}/**` â€” all source files enumerated in Â§1, every page/component/hook/lib read in full.
- `mipit-testkit/{e2e-*.mjs,tests/**,datasets/**,generators/**,tools/**,*.md,package.json,evidence/suite/2026-05-15T15-38-43-765Z/**}`.
- `mipit-docs/{adrs/ADR-*.md,openapi/openapi.yaml,mappings/*.csv,mappings/canonical-fields.md,route-rules/{rules.yaml,examples.md},design/*.md,contracts/*.md,demo-runbook/*.md,README.md}`.
- `plans/{PLAN-DE-DESARROLLO.md,TAREAS-SEMANALES-NICOLAS.md,REFERENCIAS-PASARELAS.md}`.
- `CONTEXTO-MIPIT.md`, `fix_testkit.py`.

No web URLs fetched.
