# MiPIT Validation Suite Report

- Generated at: 2026-05-15T20:45:10.797Z
- Mode: deploy
- Base URL: http://localhost:8080
- API reachable: yes
- Docker available: yes
- Token issued: yes

## Summary

- Total scenarios: 11
- Passed: 11
- Failed: 0
- Skipped: 0

## Scenario Matrix

| ID | Category | Title | Status | Duration ms |
|---|---|---|---|---:|
| historical-load | historical | Carga histórica de 1000 pagos documentada | PASSED | 0 |
| historical-routing | historical | Correctitud histórica de routing de 999 pagos documentada | PASSED | 0 |
| historical-verifications | historical | 8 verificaciones E2E históricas documentadas | PASSED | 0 |
| core-validation | core-e2e | Core validation runner | PASSED | 3477 |
| core-e2e-carlos-simplified | core-e2e | Carlos - 12 pruebas simplificadas | PASSED | 16927 |
| core-e2e-carlos-full | core-e2e | Carlos - escenarios de error completos | PASSED | 31407 |
| core-e2e-routing | core-e2e | Core - routing e2e | PASSED | 16519 |
| e2e-verifications | e2e | 8 verificaciones E2E | PASSED | 61547 |
| e2e-routing-correctness | e2e | Routing correctness (999 pagos por defecto) | PASSED | 30873 |
| e2e-load | e2e | Load test | PASSED | 2761 |
| e2e-benchmark-latency | benchmark | Latency benchmark | PASSED | 20339 |

## Details

### historical-load - Carga histórica de 1000 pagos documentada

- Category: historical
- Status: PASSED
- Duration ms: 0
- Exit code: 0
- Note: Resultado histórico documentado, no re-ejecutado en esta corrida.

```json
{
  "source_document": "mipit-docs/testing/testing-completo.md",
  "script": "mipit-testkit/e2e-load.mjs",
  "total_sent": 1000,
  "succeeded": 1000,
  "failed": 0,
  "success_rate_pct": 100,
  "throughput_rps": 30,
  "latency_p50_ms": 45,
  "latency_p95_ms": 120,
  "latency_p99_ms": 250
}
```

### historical-routing - Correctitud histórica de routing de 999 pagos documentada

- Category: historical
- Status: PASSED
- Duration ms: 0
- Exit code: 0
- Note: Resultado histórico documentado, no re-ejecutado en esta corrida.

```json
{
  "source_document": "mipit-docs/testing/testing-completo.md",
  "script": "mipit-testkit/e2e-routing-correctness.mjs",
  "total_payments": 999,
  "correctly_routed": 999,
  "misrouted": 0,
  "lost": 0,
  "routing_accuracy_pct": 100
}
```

### historical-verifications - 8 verificaciones E2E históricas documentadas

- Category: historical
- Status: PASSED
- Duration ms: 0
- Exit code: 0
- Note: Resultado histórico documentado, no re-ejecutado en esta corrida.

```json
{
  "source_document": "mipit-testkit/E2E-VERIFICATION-RESULTS.md",
  "script": "mipit-testkit/e2e-verifications.mjs",
  "assertions_passed": 76,
  "assertions_failed": 0,
  "assertions_total": 76
}
```

### core-validation - Core validation runner

- Category: core-e2e
- Status: PASSED
- Duration ms: 3477
- Exit code: 0
- Command: `npm run validate:core`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/core-validation.log`

```json
{
  "total_checks": 8790,
  "passed": 28,
  "failed": 0,
  "warnings": 0,
  "skipped": 0
}
```

### core-e2e-carlos-simplified - Carlos - 12 pruebas simplificadas

- Category: core-e2e
- Status: PASSED
- Duration ms: 16927
- Exit code: 0
- Command: `npx jest test/e2e/error-scenarios-simplified.test.ts --forceExit --detectOpenHandles`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/core-e2e-carlos-simplified.log`

```json
{
  "suites_failed": 0,
  "suites_passed": 1,
  "suites_total": 1,
  "tests_failed": 0,
  "tests_passed": 12,
  "tests_total": 12
}
```

### core-e2e-carlos-full - Carlos - escenarios de error completos

- Category: core-e2e
- Status: PASSED
- Duration ms: 31407
- Exit code: 0
- Command: `npx jest test/e2e/error-scenarios.test.ts --forceExit --detectOpenHandles`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/core-e2e-carlos-full.log`

```json
{
  "suites_failed": 0,
  "suites_passed": 1,
  "suites_total": 1,
  "tests_failed": 0,
  "tests_passed": 11,
  "tests_total": 11
}
```

### core-e2e-routing - Core - routing e2e

- Category: core-e2e
- Status: PASSED
- Duration ms: 16519
- Exit code: 0
- Command: `npx jest test/e2e/routing.test.ts --forceExit --detectOpenHandles`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/core-e2e-routing.log`

```json
{
  "suites_failed": 0,
  "suites_passed": 1,
  "suites_total": 1,
  "tests_failed": 0,
  "tests_passed": 9,
  "tests_total": 9
}
```

### e2e-verifications - 8 verificaciones E2E

- Category: e2e
- Status: PASSED
- Duration ms: 61547
- Exit code: 0
- Command: `node e2e-verifications.mjs`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/e2e-verifications.log`

```json
{
  "assertions_passed": 76,
  "assertions_failed": 0,
  "assertions_total": 76
}
```

### e2e-routing-correctness - Routing correctness (999 pagos por defecto)

- Category: e2e
- Status: PASSED
- Duration ms: 30873
- Exit code: 0
- Command: `node e2e-routing-correctness.mjs`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/e2e-routing-correctness.log`

```json
{
  "verified": 999,
  "correctly_routed": 999,
  "misrouted": 0,
  "lost": 0,
  "routing_accuracy_pct": 100
}
```

### e2e-load - Load test

- Category: e2e
- Status: PASSED
- Duration ms: 2761
- Exit code: 0
- Command: `node e2e-load.mjs 200 20`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/e2e-load.log`

```json
{
  "succeeded": 200,
  "failed": 0,
  "success_rate_pct": 100,
  "throughput_rps": 75,
  "latency_p50_ms": 222,
  "latency_p95_ms": 360,
  "latency_p99_ms": 408
}
```

### e2e-benchmark-latency - Latency benchmark

- Category: benchmark
- Status: PASSED
- Duration ms: 20339
- Exit code: 0
- Command: `node e2e-benchmark-latency.mjs 5 20`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-15T20-42-05-163Z/e2e-benchmark-latency.log`

```json
{
  "POST /payments": {
    "requests": 100,
    "errors": 0,
    "avg_ms": 143,
    "p95_ms": 190,
    "p99_ms": 207
  },
  "POST /translate/preview": {
    "requests": 560,
    "errors": 0,
    "avg_ms": 25,
    "p95_ms": 40,
    "p99_ms": 45
  },
  "POST /translate": {
    "requests": 600,
    "errors": 0,
    "avg_ms": 21,
    "p95_ms": 34,
    "p99_ms": 42
  },
  "GET /payments/:id": {
    "requests": 620,
    "errors": 0,
    "avg_ms": 24,
    "p95_ms": 37,
    "p99_ms": 43
  }
}
```
