# MiPIT PoC — Limitaciones Explícitas

> **P12 (Wave 4)** — Documento maestro de limitaciones del PoC, consolidando lo que cada repo declara
> en su propio README. Esto NO es una hoja de bugs: son **decisiones conscientes** del scope de un
> Proof of Concept de tesis, justificadas con la regulación o el costo de implementarlas a fondo.

Fecha de corte: 2026-05-17 (Wave 6 actualización — agregadas secciones 11 y 12 con
scope-outs adicionales identificados por la auditoría 2).

---

## 1. Rieles y conectividad real

| Tema | Limitación | Justificación |
|---|---|---|
| **PIX (BACEN/DICT)** | No conectado al DICT oficial. Usamos `mipit-adapter-pix` + mock server que respeta el contrato PIX (CPF/CNPJ/+55/email/EVP, estructuras de mensaje y códigos de rechazo). | Acceso a DICT requiere licencia bancaria brasileña y certificado ICP-Brasil; fuera del scope de tesis. |
| **SPEI (Banxico/STP)** | No conectado a STP/CECOBAN. Mock CLABE-18 con mod-10 weighted, ventana L-V 06:00-17:55 CT. | STP requiere intermediario bancario o "Institución Financiera Sustentable". |
| **Bre-B (BanRep)** | No conectado al directorio BanRep. Mock con TR-002 schema, llaves mobile-only, alias `@xxx`. | BanRep TR-002 GA fue 2025-10-06; el sandbox aún requiere ser EOP autorizada. |
| Otros rieles (SWIFT MT103, ACH NACHA, FedNow, ISO20022_MX) | Solo traducción (`POST /translate/*`), sin adaptador productivo ni mock. | El PoC se enfoca en las 3 LATAM productivas (PIX/SPEI/BRE_B). |

---

## 2. Canónico ISO 20022 — subset implementado

El canónico es un **subset documentado** de `pacs.008.001.10`, no una implementación completa.
Fuente de verdad: `mipit-docs/adrs/ADR-002-canonical-pacs008-json.md`.

**Implementado:**
- `GrpHdr` con `msgId`, `creDtTm`, `nbOfTxs`, `ctrlSum`, `ttlIntrBkSttlmAmt`, `initgPty`, `sttlmInf`
- `PmtId` con `instrId`, `endToEndId`, `txId`, **`uetr`** (UUIDv4, P11 lo surface en UI)
- `IntrBkSttlmAmt` (valor + currency ISO 4217)
- `IntrBkSttlmDt` (fecha de liquidación)
- `ChrgBr` (DEBT/CRED/SHAR/SLEV; default `SLEV` para rieles instantáneos)
- `Dbtr`, `Cdtr`, `DbtrAgt`, `CdtrAgt` (subset)

**NO implementado (limitaciones reconocidas):**
- `RmtInf.Strd` (structured remittance — solo se acepta `Ustrd` libre hasta 140 chars)
- `Purp` como código ISO 20022 ExternalPurpose1Code (acepta string libre con `purpose`)
- `RgltryRptg` (regulatory reporting tags)
- `Tax` block (Tx, Strd, etc.)
- `RltdRmt` (related remittance)
- Múltiples `CdtTrfTxInf` por mensaje (siempre `nbOfTxs=1`)
- `XchgRate` group completo con `UnitCcy`/`CtrctId` (P05 modela solo `value` + monedas instructed/settlement)
- Firma XMLDSig / SHA-256 / canonicalización (PoC usa JSON, no XML — ver ADR-002)

---

## 3. Seguridad

| Área | Implementado | Limitación |
|---|---|---|
| Auth | JWT HS256 dev (`/auth/token`) | Sin OIDC/OAuth2 real, sin rotación de keys, secreto en variable de entorno. Producción requeriría KMS + JWKS. |
| Rate-limit | Por IP, sliding window | Sin política por cliente/tenant; sin distribución (in-memory por instancia). |
| Idempotency | `Idempotency-Key` header, TTL 24 h, sweeper background | Sin firma del payload (un MITM podría modificar el body si no hay TLS). |
| Sanitization | Input zod + helmet + size cap 1 MB | Sin WAF; sin allow-list por endpoint. |
| TLS | Asumido en el reverse-proxy (nginx) | El PoC NO termina TLS dentro de Node. |
| Audit log | Eventos a `audit` table + opcional WAL | Sin firma criptográfica de la cadena (sería append-only signed hashchain). |
| PII redaction | Pino `redact` en `debtor/creditor name/taxId/email/phone`, `headers.authorization`, JWTs/secrets, alias nativos por riel | Sin tokenización ni cifrado en reposo a nivel DB. La DB asume cifrado de disco. |

---

## 4. Resiliencia

- **Circuit breaker** por riel — implementado, pero con thresholds estáticos (no ajuste adaptativo).
- **DLQ** con max 3 retries — sin replay automático; requiere intervención manual.
- **Compensación** (`/compensate/:id`) — best-effort en mocks; rieles reales raramente permiten reversa instantánea.
- **Reconciliación** — job periódico contra una "expected ledger" local; en producción habría que reconciliar contra el ledger del operador del riel.

---

## 5. Observabilidad

- **Métricas:** unificadas en `mipit_adapter_{requests,latency,retries,errors}_total` con label `rail`. Recording rules en Prometheus para p50/p95/p99 y success rate (P07).
- **Tracing:** OpenTelemetry → Jaeger. El `trace_id` viaja en headers RabbitMQ y en respuestas HTTP, y la UI lo enlaza a Jaeger (P11).
- **Alertas:** AlertManager con webhook a `/webhooks/alertmanager` (P07).
- **Limitación:** Sin SLO formal con error-budget; las alertas son "raw" sin burn-rate.

---

## 6. UI

- **Stack:** Next.js 15 App Router, React 19, TypeScript, Tailwind, sonner.
- **Pruebas UI:** 64/64 tests (Jest + Testing Library + jsdom). Polyfill de `crypto.randomUUID` (P11).
- **No incluye:** SSR/SSG real (todas las páginas son client-rendered), i18n (solo español), accesibilidad WCAG AA completa, modo dark sin parpadeo.

---

## 7. Testing y datasets

- **Generators** (`mipit-testkit/generators/`): producen CPFs, CLABEs y NITs con checksum válido (P10). Datasets para los 6 rail-pairs direccionales.
- **Smoke test** (`tools/smoke-test.sh`): adquiere JWT, cubre PIX→SPEI, SPEI→BRE_B, BRE_B→PIX (P10).
- **Contract tests** (`tests/contract/`): zod-based offline + live API/RabbitMQ Management si la stack está arriba (P10).
- **No incluye:** chaos engineering (sin fault injection automatizado), pruebas de carga formales (k6/Gatling), pruebas de seguridad ofensivas (DAST/SAST).

---

## 8. Compliance regulatorio

El PoC **no busca certificación** PCI-DSS, ISO 27001, ni cumplir directamente con la regulación de cada banco central. Documentamos los puntos de contacto:

- **BACEN (PIX):** Resolución 1/2020 — cumplimos disponibilidad 24/7 y formato DICT. NO somos PISP autorizado.
- **Banxico (SPEI):** Circular 14/2017 — respetamos ventana operativa y formato CLABE. NO somos Institución Financiera Sustentable.
- **BanRep (Bre-B):** TR-002 — respetamos catálogo de llaves y currency COP. NO somos Entidad Operadora Pagadora autorizada.
- **GDPR/LFPDPPP/Habeas Data:** PII redaction implementada en logs (P07). NO hay flujo formal de derechos ARCO ni data-subject requests.

---

## 9. Despliegue

- **Local:** `docker compose up -d` levanta ~16 contenedores (postgres, rabbitmq, jaeger, prometheus, grafana, alertmanager, core, 3 adapters, 3 mocks, ui).
- **VM:** VM1 (infra) + VM2 (services). IPs y credenciales documentadas en `mipit-docs/demo-runbook/vm-demo.md`.
- **Cloud:** No hay despliegue managed. Sin Helm/Kustomize, sin Terraform.

---

## 11. ISO 20022 — scope-outs identificados en Auditoría 2 (Wave 6)

| Tema | Scope-out | Razón |
|---|---|---|
| **Pix Automático** (BCB Res. 304/2023, GA jun-2024) | Sin `RecurrentPaymentInformation` / `Frequency` / `PaymentMandate` en el canónico. | El PoC modela transferencias one-shot; recurring requiere mandate signing y un schema de schedule que multiplica el alcance. |
| **Pix Garantido** | No modelado. | Es flujo crédito-comprador→garantizar-vendedor; comportamiento financiero específico, no técnico. |
| **MED estructurado** (Mec. Especial de Devolução, BCB Res. 103/2021+215/2022) | Solo el enum `DEVOL` en el mock, sin SLA 80 días ni motivos FRAU/FAIL/REFD. | La devolución por compensación queda cubierta vía pacs.004 (W6.4); MED real requeriría un workflow regulado adicional. |
| **DiMo** (Banxico oct-2024, SPEI por celular) | El adapter SPEI sólo emite `tipoCuentaBeneficiario=40` (CLABE); `=10` (Phone-linked) queda fuera. | El catálogo nacional DiMo y su API de resolución no son accesibles sin licencia bancaria. |
| **TR-002 oficial Bre-B** | Los códigos `BREB001-005`, el formato exacto de `idTransaccion` y el OAuth flow son convenciones MIPIT-inventadas. W5.13/W6.7 corrigieron la documentación de esto; un sandbox real BanRep aceptaría formatos diferentes. | TR-002 v1.1 (oct-2025) aún no expone una spec REST pública. |
| **Bre-B directorio (alias→PSP)** | Sin endpoint `GET /breb/v1/directorio/{llave}`. El core asume que `destination.ispb` ya está resuelto. | Análogo a `/v2/dict/{key}` PIX — requiere acceso al directorio central BanRep. |
| **FedNow cross-border** | El traductor `canonical-to-fednow` lanza `TranslationError` si la currency no es USD (W6.10). | FedNow es USD-domestic-only per Federal Reserve OP §3.1; un on-ramp BRL→USD se debe completar antes (SPEI/SWIFT corresponsal). |
| **camt.054 / camt.053** (DebitCreditNotification + Statement) | No emitidos. La reconciliación interna no consume extractos del operador. | En producción reemplazaría comparación interna con `camt.053`; fuera de scope académico. |
| **`RgltryRptg` + threshold USD 10k** | Sin middleware que detecte y flagee transferencias regulatorias (BACEN Carta-Circular 3.598/2022, Banxico Circular 100/2019, SARLAFT CO). | Threshold detection sin sistema regulatorio downstream no agrega valor demostrable; documentado para que un panel financiero sepa que es escope futuro. |
| **`IntrmyAgt1-3` / `UltmtDbtr` / `UltmtCdtr`** | No modelados. | Necesarios para correspondent banking ≥2 hops (BRL→USD→COP via corresponsal) y para PSPs SEDPE que actúan on-behalf-of usuarios finales (Nequi/Daviplata). El PoC cubre el caso ≤2-hops directo. |
| **`ChrgsInf`** | Solo `ChrgBr` (quién paga), sin lista de cargos por agente. | PoC LATAM instantáneo defaulta a `SLEV`, donde el cargo es cero. |

## 12. NACHA / SWIFT MT103 / ISO 20022 MX (rieles case-study)

Estos rieles existen para **demostrar la extensibilidad** del canónico ISO 20022. NO tienen adaptador productivo
ni mock, sólo el par `<rail>-to-canonical.ts` ↔ `canonical-to-<rail>.ts`. Wave 6 mejoró su fidelidad
(LclInstrm, NACHA layout de 94 chars, MT103 chrgBr→detailsOfCharges) pero quedan como demostración.

**No bloquea sustentación** que estos rieles no tengan adapter productivo — su valor académico es mostrar que
agregar un nuevo riel al hub-and-spoke requiere sólo escribir dos funciones puras de traducción.

---

## 13. Audit 3 (2026-05-18) — claim-drift cerrado declarativamente

Wave 6 declaró cerrados estos dos tickets, pero la Auditoría 3 (B1-003, B1-004) detectó que el código
real no implementa todo lo declarado. Sin código nuevo, documentamos honestamente el estado verdadero:

| Ticket | Lo que dijo Wave 6 | Estado real (Audit 3) | Por qué no se completa ahora |
|---|---|---|---|
| **W6.3 `ctgyPurp` end-to-end** | "agrega `canonical.ctgyPurp`; SPEI mapper deriva `tipoPago` (CASH→1, SALA→5, TAXS→14...)". | El schema + tabla de mapping existen y el SPEI mapper sí lee `canonical.ctgyPurp`. Pero **ningún translator emite el campo** (`pix-to-canonical`, `spei-to-canonical`, `breb-to-canonical`, `iso20022-mx-to-canonical` no escriben `ctgyPurp`) y la API request schema no lo acepta. Resultado: SPEI siempre cae al fallback `tipoPago=1` (CASH). Las filas SALA→5 / TAXS→14 son scaffolding muerto. | Emitirlo end-to-end requiere extender los 4 traductores + extender `createPaymentSchema` + ampliar tests; estimado 2h. Queda en Wave 7 backlog. La defensa académica es: la **arquitectura** está lista (el tipo, el mapping, el consumer) y un riel cualquiera puede empezar a emitirlo sin cambios estructurales. |
| **W6.4 pacs.004 persistido** | "compensation-service construye + persiste pacs.004 real (RtrId, OrgnlEndToEndId, OrgnlUETR, RtrdIntrBkSttlmAmt, RtrRsnInf)". | El código construye el pacs.004 correctamente (schema en `canonical/pacs004.schema.ts`, helper en `compensation-service.ts`). Pero la "persistencia" es **sub-objeto JSON dentro de `audit_events.detail`**, no una tabla/columna dedicada. No hay endpoint `GET /payments/:id/pacs004` ni columna `payments.pacs004_envelope`. | Una migration nueva pre-sustentación introduce riesgo de regresión sin valor demostrable; el envelope es **observable** via `GET /payments/:id/audit-events` y eso es lo que un panel revisaría. Si se necesitara persistencia dedicada, agregar columna JSONB + GIN index es trabajo de 30 min en Wave 7. |

Esto es **honestidad académica**: cerrar el claim sin reescribir el código, documentando exactamente qué está
en `Auditoria-Claude` y qué requeriría trabajo adicional. Las dos limitaciones son detectables en revisión de
código y se reconocen explícitamente.

---

## 10. Qué *sí* demuestra el PoC

A pesar de las limitaciones, el PoC entrega evidencia funcional de:

1. **Interoperabilidad técnica** entre 3 rieles instantáneos LATAM (PIX, SPEI, Bre-B).
2. **Canónico pacs.008-derivado** con UETR + ChrgBr + IntrBkSttlmDt + EndToEndId + FX cross-currency.
3. **Pipeline end-to-end** con 8 pasos, idempotencia, rate-limit, circuit-breaker, DLQ.
4. **Observabilidad full-stack** con trace_id propagado de UI a Jaeger pasando por core + adapter.
5. **Validación de checksums** real para CPF / CLABE / NIT (no payloads garbage).
6. **6 rail-pairs direccionales** ejercitados por testkit + smoke.
7. **Compensación + reconciliación** modeladas (aunque sean best-effort en mocks).

Las limitaciones documentadas aquí son el **plan natural de continuación** para una eventual versión productiva.
