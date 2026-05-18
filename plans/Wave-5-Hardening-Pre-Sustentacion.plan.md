# Wave 5 — Hardening Pre-Sustentación

**Fecha:** 2026-05-17
**Branch:** `Auditoria-Claude`
**Origen:** Bloque A del documento maestro [AUDITORIA-2-2026-05-17.md](../audits/AUDITORIA-2-2026-05-17.md) — cierre de las 14 brechas visibles que un panel descubriría en demo
**Estado:** ✅ Cerrada — 14/14 tickets entregados, verificados live, committeados a `Auditoria-Claude`
**Evidencia:** [evidence/wave-5-verification-2026-05-17.md](../evidence/wave-5-verification-2026-05-17.md)

---

## Objetivo

Cerrar las brechas que un panel técnico descubriría en una demo en vivo, en ≈3 horas de trabajo concentrado, sin agregar features y sin desviarnos del alcance declarado en la propuesta. La regla guía: **toda Wave 5 es remedial** (bug fixes + completar lo declarado), no introduce funcionalidad nueva.

## Aclaración crítica de rieles aplicada en esta Wave

Durante la planeación de W5.8 surgió una clarificación que reorienta toda la lectura de las Waves 6–8:

- **3 rieles PRODUCTIVOS** (adapter + mock + pipeline E2E): PIX (Brasil), SPEI (México), Bre-B (Colombia)
- **4 rieles CASE-STUDY** (translator-only via `POST /translate/*`): SWIFT MT103, ISO 20022 MX, ACH NACHA, FedNow

Los 4 case-study NO son una limitación encubierta sino el **diferenciador de extensibilidad** del PoC: muestran que agregar un riel nuevo al hub-and-spoke requiere sólo escribir un par `*-to-canonical.ts` / `canonical-to-*.ts`. Esto vive ahora explícito en LIMITATIONS.md §1 + Amendment en AUDITORIA-2.

## Tickets entregados (14)

| ID | Cambio | Repo(s) | Audit findings cerrados |
|---|---|---|---|
| **W5.1 HARD-001** | `GET /payments/:id` ahora surface `uetr`, `end_to_end_id`, `charge_bearer`, `interbank_settlement_date`, `instructed_amount`, `instructed_currency`, `settlement_amount`, `settlement_currency`, `exchange_rate`, `exchange_rate_source` + timestamps terminales (`failed_at`, `compensated_at`, `dead_letter_at`). Las columnas ya existían en DB; el handler simplemente no las devolvía. | core | C5, D1, D3, Q30, I8 |
| **W5.2 HARD-002** | Implementar `POST /webhooks/alertmanager` como ruta pública (machine-to-machine, sin JWT). Acepta payload AlertManager v4, loguea firing/resolved con severidad apropiada. AlertManager estaba configurado para llamarlo pero antes devolvía 404 forever. | core | C4, B1, Q26, I14, A5-D1 |
| **W5.3 HARD-003** | UI Jaeger link cambia de `/trace/<ULID>` a `/search?service=mipit-core&tags={mipit.trace_id:...}`. El trace_id de MIPIT es ULID, no hex OTel; el path `/trace/<id>` no encontraba traza. | ui | C7, D2, Q27, I11 |
| **W5.4 HARD-004** | Pipeline catch block ahora llama `recordPayment(FAILED, originRail, 'UNKNOWN')`. Antes sólo el ACK consumer incrementaba `mipit_payments_total`, ocultando failures que crasheaban antes del routing. Grafana ahora matchea DB. | core | D8, Q25 |
| **W5.5 HARD-005** | Histogram buckets `[10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000]` ms (era cap 2500ms). p99 ya no satura a +Inf cuando un stage es lento, y `HighLatency` alert (>10s) ahora puede dispararse. Aplicado en core + 3 adapters. | core + 3 adapters | D9, F34, F35, Q29 |
| **W5.6 HARD-006** | UI `PaymentStatus` + `STATUS_CONFIG` agregan `NORMALIZED` (mismo step/color que CANONICALIZED). `payment-status-badge` con fallback neutral para status futuros desconocidos. Antes, un pago en NORMALIZED crasheaba el badge. | ui | C8, B1, I12 |
| **W5.7 HARD-007** | CLABE placeholders válidos mod-10 (`012180000118359713`, `002180012345678906`). Los anteriores fallaban el check digit al presionar "Iniciar Transacción". | ui | D4 |
| **W5.8 HARD-008** | `/simulate` ahora sólo expone los 3 rieles productivos (PIX, SPEI, BRE_B). Banner explícito dirige a `/translator` para los 4 case-study. Aclara visualmente la separación productivo vs extensibilidad. | ui | D5 |
| **W5.9 HARD-009** | SSE handlers validan `?token=<jwt>` antes de abrir el stream. Sin token → 401. PII (debtor/creditor alias, amounts) ya no leakea a clientes de red sin autenticar. | core | C1, F01 |
| **W5.10 HARD-010** | `canonical-to-breb.ts` usa `formatAmount(value, 'COP')` (entero, no `.toFixed(2)`). Si hay FX cross-currency, prefiere `fx.local_amount`. El mock toleraba `.00` pero BanRep TR-002 §5 lo rechazaría. | core | I6 |
| **W5.11 HARD-011** | Regex BRE_B mobile-only `^\+573\d{9}$` en el inferRail del pipeline + en el validator de `payment-request.ts`. El core era más laxo que el mock; ahora el core rechaza lo mismo que rechaza BanRep TR-002. | core | A5-F6, B6 |
| **W5.12 HARD-012** | Borrar 4 UI stubs zombie (`payment-card`, `payment-form`, `pix-form`, `spei-form`). Ninguno se importaba. Limpiar TODO comment de `payment-status-badge.tsx`. | ui | F14, D7 |
| **W5.13 HARD-013** | Corregir comentario engañoso en `breb-to-canonical.ts:18-24` que declaraba "(BanRep spec)" para códigos `BREB001-005` que son **MIPIT-invented**, no BanRep-published. Honestidad académica explícita. | core | R-009, A5-F3 |
| **W5.14 HARD-014** | Documentar `seed_mapping_table.sql` con cabecera "mapping-as-documentation, not policy engine". 7/13 de las transformaciones declaradas en el SQL no tienen case en `applyTransformation`; la lógica real vive en TypeScript tipado. Decisión de diseño, no vaporware. | infra | C3, I5, Q4 |

## Criterios de éxito (todos cumplidos)

- ✅ Smoke 3/3 rail-pairs (PIX↔SPEI↔BRE_B↔PIX) sigue llegando a COMPLETED end-to-end
- ✅ Demo de payment detail muestra UETR + ChrgBr + FX
- ✅ Link Jaeger abre la traza correcta (via search-by-attribute)
- ✅ AlertManager → core sin 404 en logs (devuelve `{received:true,parsed:true,count:N}`)
- ✅ Grafana `mipit_payments_total` matchea `SELECT COUNT(*) FROM payments`
- ✅ SSE responde 401 sin token + 200 con token válido
- ✅ UI tests 65/65 (era 64; +1 por ajuste en `constants.test.ts` para reflejar `NORMALIZED`)

## Commits y push

Todos los cambios viven en `Auditoria-Claude` (la branch `wave-5-hardening` se borró tras merge):

| Repo | Commit | Tickets |
|---|---|---|
| `mipit-core` | `f3d5b75` → merged en `Auditoria-Claude` `788afd7` | W5.1, W5.2, W5.4, W5.5, W5.9, W5.10, W5.11, W5.13 |
| `mipit-ui` | `0d3da86` → merged en `Auditoria-Claude` `2c63746` | W5.3, W5.6, W5.7, W5.8, W5.11, W5.12 |
| `mipit-adapter-pix` | `ad7d84b` → merged en `Auditoria-Claude` `c9a7f83` | W5.5 |
| `mipit-adapter-spei` | `34175c9` → merged en `Auditoria-Claude` `e2b6c86` | W5.5 |
| `mipit-adapter-breb` | `e00d441` → merged en `Auditoria-Claude` `1aee4dc` | W5.5 |
| `mipit-infra` | `63ff827` → merged en `Auditoria-Claude` `60c8164` | W5.14 |

## Tests ajustados al código (no al revés)

- `mipit-ui/src/__tests__/lib/constants.test.ts`: `expect(...).toBe(14)` → `15` + agregué `'NORMALIZED'` a `expectedStatuses`. Razón: W5.6 corrige un hueco real — la UI crasheaba al recibir un payment en `NORMALIZED`.

## Lecciones aprendidas

1. **El mayor unblock visible** fue W5.1 (surface UETR/FX en API). La UI ya tenía los bloques visuales; el API simplemente no los devolvía.
2. **W5.13 (corregir comentario mentiroso)** es el cambio de menor LOC pero alto impacto académico — un panel siempre celebra honestidad sobre claims overstated.
3. **W5.8 (rieles productivos vs case-study)** convirtió un posible cuestionamiento ("¿por qué falla cuando elijo FedNow?") en un punto fuerte de demo ("vamos al traductor para ver la extensibilidad").
4. **Network DNS race en `docker compose up --build`** parcial: requiere `compose down + up` completo para refrescar aliases del embedded DNS. Documentado en evidence.

## Pendientes trasladados

- Bug menor en `consumer.ts:134`: `recordPayment` etiqueta `origin_rail` con el rail del ACK destino, no del payment original → Wave 7 SOT-001/CLEAN-001
- Error TS pre-existente en `otel.ts:5` (`resourceFromAttributes` no exportado) → Wave 8 ARCH-008 (OTel version drift)
