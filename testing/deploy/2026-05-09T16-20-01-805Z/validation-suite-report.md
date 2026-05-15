# MiPIT Validation Suite Report

- Generated at: 2026-05-09T16:22:55.834Z
- Mode: deployment
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
| historical-verifications | historical | 8 verificaciones E2E históricas documentadas | PASSED | 1 |
| core-validation | core-e2e | Core validation runner | PASSED | 3491 |
| core-e2e-carlos-simplified | core-e2e | Carlos - 12 pruebas simplificadas | PASSED | 11851 |
| core-e2e-carlos-full | core-e2e | Carlos - escenarios de error completos | PASSED | 7411 |
| core-e2e-routing | core-e2e | Core - routing e2e | PASSED | 15205 |
| e2e-verifications | e2e | 8 verificaciones E2E | PASSED | 60220 |
| e2e-routing-correctness | e2e | Routing correctness (999 pagos por defecto) | PASSED | 29385 |
| e2e-load | e2e | Load test | PASSED | 5890 |
| e2e-benchmark-latency | benchmark | Latency benchmark | PASSED | 40379 |

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
- Duration ms: 1
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
- Duration ms: 3491
- Exit code: 0
- Command: `npm run validate:core`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/core-validation.log`

```json
{
  "total_checks": 28,
  "passed": 28,
  "failed": 0,
  "warnings": 0,
  "skipped": 0
}
```

### core-e2e-carlos-simplified - Carlos - 12 pruebas simplificadas

- Category: core-e2e
- Status: PASSED
- Duration ms: 11851
- Exit code: 0
- Command: `npx jest test/e2e/error-scenarios-simplified.test.ts --forceExit --detectOpenHandles`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/core-e2e-carlos-simplified.log`

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
- Duration ms: 7411
- Exit code: 0
- Command: `npx jest test/e2e/error-scenarios.test.ts --forceExit --detectOpenHandles`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/core-e2e-carlos-full.log`

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
- Duration ms: 15205
- Exit code: 0
- Command: `npx jest test/e2e/routing.test.ts --forceExit --detectOpenHandles`
- Workdir: `/home/estudiante/tesis/mipit-core`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/core-e2e-routing.log`

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
- Duration ms: 60220
- Exit code: 0
- Command: `node e2e-verifications.mjs`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/e2e-verifications.log`

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
- Duration ms: 29385
- Exit code: 0
- Command: `node e2e-routing-correctness.mjs`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/e2e-routing-correctness.log`

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
- Duration ms: 5890
- Exit code: 0
- Command: `node e2e-load.mjs 500 25`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/e2e-load.log`

```json
{
  "succeeded": 500,
  "failed": 0,
  "success_rate_pct": 100,
  "throughput_rps": 86,
  "latency_p50_ms": 251,
  "latency_p95_ms": 327,
  "latency_p99_ms": 417
}
```

### e2e-benchmark-latency - Latency benchmark

- Category: benchmark
- Status: PASSED
- Duration ms: 40379
- Exit code: 0
- Command: `node e2e-benchmark-latency.mjs 10 30`
- Workdir: `/home/estudiante/tesis/mipit-testkit`
- Log: `/home/estudiante/tesis/mipit-testkit/evidence/suite/2026-05-09T16-20-01-805Z/e2e-benchmark-latency.log`

```json
{
  "POST /payments": {
    "requests": 297,
    "errors": 0,
    "avg_ms": 119,
    "p95_ms": 158,
    "p99_ms": 179
  },
  "POST /translate/preview": {
    "requests": 1120,
    "errors": 0,
    "avg_ms": 25,
    "p95_ms": 39,
    "p99_ms": 45
  },
  "POST /translate": {
    "requests": 1210,
    "errors": 0,
    "avg_ms": 21,
    "p95_ms": 32,
    "p99_ms": 38
  },
  "GET /payments/:id": {
    "requests": 1320,
    "errors": 447,
    "avg_ms": 20,
    "p95_ms": 35,
    "p99_ms": 42
  }
}
```
