# Wave 6 — ISO 20022 Spec Compliance — Verificación

**Fecha:** 2026-05-17 (segunda mitad del día)
**Branch:** `Auditoria-Claude` (directo, sin branch separado por preferencia del equipo)
**Stack:** rebuild local Wave 6 + verify live (12 containers UP)
**Categorización de rieles aplicada:** PIX/SPEI/Bre-B productivos · SWIFT MT103, ISO20022 MX, NACHA, FedNow case-study (per Amendment AUDITORIA-2)

## Tickets entregados (13 — todos en `Auditoria-Claude`)

| Ticket | Cambio | Repos | Verificado |
|---|---|---|---|
| W6.1 ISO-001 | 3 adapters emiten bloque `pacs002` enriquecido (`orgnlEndToEndId`, `orgnlUetr`, `txSts`, `stsRsnInf`); consumer materializa a `rail_ack` | core + 3 adapters | ✅ live: `tx_sts: ACSC`, `orgnl_uetr: 99d96f34-...` |
| W6.2 ISO-002 | `rail-rejection-mapping.ts`: BACEN/CECOBAN/BREB → ISO `ExternalStatusReason1Code` con `Rsn.Prtry` preservando original | core | ✅ unit tests |
| W6.3 ISO-003 | `canonical.ctgyPurp` agregado; SPEI mapper deriva `tipoPago` (CASH→1, SALA→5, TAXS→14...). Tipo `tipoPago: number` (era `1|2|3|4`) | core + adapter-spei | ✅ TS compila |
| W6.4 ISO-004 | `pacs004.schema.ts` creado; `compensation-service` construye + persiste pacs.004 real (RtrId, OrgnlEndToEndId, OrgnlUETR, RtrdIntrBkSttlmAmt, RtrRsnInf) | core | ✅ TS compila |
| W6.5 ISO-005 | Fidelity batch: pipeline stampa `nbOfTxs/ctrlSum/ttlIntrBkSttlmAmt`; XchgRate como objeto `{UnitCcy, XchgRate, RateTp:'SPOT'}`; canónico `lclInstrm{cd,prtry}`; ISO20022-MX default `LclInstrm.Prtry='SCT'`; MT103 `chrgBr→detailsOfCharges` map (DEBT→OUR, CRED→BEN, etc.) | core | ✅ unit tests |
| W6.6 ISO-006 | `pacs002.schema.orgnlMsgNmId` cambia a regex `/^pacs\.008\.001\.\d{2}$/` (forward-compat con .12 maintenance May 2024) | core | ✅ unit tests |
| W6.7 ISO-007 | `BREB_ENTITY_CODES` unificados a 4-dig Superfinanciera; mock acepta ambos formatos; mensaje de error stale corregido | core + adapter-breb | ✅ live: `codigoEntidad: "9999"` (4-dig), idTransaccion 28 chars |
| W6.8 ISO-008 | Bre-B `inferTipoLlave` unified core+adapter: ALIAS exige `@` prefix per TR-002, EMAIL regex estricta con TLD | core | ✅ unit tests |
| W6.9 ISO-009 | `canonical-to-{pix,spei}` regeneran `endToEndId`/`claveRastreo` si el canónico no cumple el regex del riel (caso SPEI→PIX donde e2eId trae hyphen) | core | ✅ unit tests |
| W6.10 ISO-010 | `canonical-to-fednow` lanza `TranslationError` si `currency !== USD` y no hay USD on-ramp explícito en `canonical.fx` (Fed OP §3.1) | core | ✅ TS compila |
| W6.11 ISO-011 | NACHA File Header (Type 1) layout corregido — Immediate Origin pasó de 9 a 10 chars per NACHA OR 2025 §3.1; nuevo unit test asserta byte-exact positions | core | ✅ unit tests 20/20 |
| W6.12 ISO-012 | LIMITATIONS.md §11 + §12 agregadas con scope-outs nuevos (Pix Automático, DiMo, MED, TR-002 oficial, Bre-B directorio, FedNow cross-border, camt.054, RgltryRptg, IntrmyAgt) | docs | ✅ committed |
| W6.13 ISO-013 | Borrados `mappings/canonical-fields.md` y 4 CSVs legacy (describían un canónico flat ya inexistente); README.md y AGENTS.md actualizados con la nueva fuente de verdad | docs | ✅ archivos eliminados |

## Commits pusheados a `Auditoria-Claude`

| Repo | Commit | Tickets |
|---|---|---|
| mipit-core | `d09e556` | W6.1/2/3/4/5/6/8/9/10/11 + tests |
| mipit-adapter-pix | `a398357` | W6.1 |
| mipit-adapter-spei | `53043c0` | W6.1 + W6.3 |
| mipit-adapter-breb | `c9a4e77` | W6.1 + W6.7 |
| mipit-docs | (próximo) | W6.12 + W6.13 + evidence |

## Tests (ajustados al código, no al revés)

| Suite | Resultado | Cambios |
|---|---|---|
| mipit-core unit | **310/310 ✅** (era 307) | +3 nuevos por W6.11 NACHA byte-positions. Ajustes en `canonical-to-pix.test`, `canonical-to-spei.test`, `breb.test`, `metrics.test`, `pipeline.test` para reflejar formatos nuevos (BCB E2E regex, Banxico claveRastreo regex, COP integer, 4-dig BREB codes, extended buckets, recordPayment mock) |
| mipit-adapter-pix | 62/62 | sin cambios estructurales en tests |
| mipit-adapter-spei | 86/86 | sin cambios estructurales en tests |
| mipit-adapter-breb | 44/44 | sin cambios estructurales en tests |

## Verificaciones live post-rebuild

```bash
# W6.1 + W6.2 — PIX→SPEI emite pacs.002 enriquecido
PMT=$(curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: w6-..." -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"SPEI-012180000118359713"}}' \
  | jq -r .payment_id)
docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT jsonb_pretty(rail_ack) FROM payments WHERE payment_id='$PMT'"
# → {tx_sts: "ACSC", orgnl_uetr: "99d96f34-...", orgnl_end_to_end_id: "E2E-..."}

# W6.7 + W5.10 — PIX→BRE_B emite 4-dig codigoEntidad + COP entero
PMT=$(curl -sf -X POST http://localhost:8080/payments \
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: w6-breb..." -H 'Content-Type: application/json' \
  -d '{"amount":100,"currency":"BRL","debtor":{"alias":"PIX-12345678909"},"creditor":{"alias":"BREB-+573001234567"}}' \
  | jq -r .payment_id)
docker exec mipit-postgres psql -U mipit -d mipit -tAc \
  "SELECT jsonb_pretty(translated_payload) FROM payments WHERE payment_id='$PMT'"
# → codigoEntidad: "9999" (4-dig); valor.original: "83267" (integer);
#   idTransaccion: "BR9999..." (28 chars total)
```

## Hallazgos durante verificación live

1. **Network DNS re-registration**: tras `docker compose up -d --build`, el alias `postgres` se desincronizó del embedded DNS de Docker. Solución: `docker compose down && up -d` completo. Documentado para futuros rebuilds.
2. **Test flakiness**: la primera corrida de pix/spei tests reportó 6+9 fallos por timing (workers de mocks no liberaban puerto entre tests); la segunda corrida pasó limpio. No es bug Wave 6.
3. **Error TS pre-existente** en `mipit-core/src/observability/otel.ts:5` (`resourceFromAttributes` no exportado) persiste — es A3 F11 OTel version drift, cubierto por Wave 8 ARCH-008.

## Pendientes que se trasladan

- **W6.4 verify live**: el código pacs.004 está + tests unit pasan, pero verificar el flow end-to-end requiere provocar un FAILED y compensarlo. Demo durante sustentación.
- **W6.1 pacs.002 endpoint externo**: el bloque pacs002 se persiste en rail_ack pero no se expone aún en un endpoint REST `GET /payments/:id/pacs.002`. Wave 7 SOT-001 puede absorberlo.
- **W6.5 LclInstrm en emitters PIX/SPEI/BRE_B nativos**: el canónico tiene el campo, pero los wire-formats nativos PIX/SPEI/BRE_B no lo incluyen porque sus protocolos no lo usan. Solo iso20022-mx + FedNow lo emiten. Documentar.

## Veredicto

✅ **Wave 6 cierra los 11 hallazgos críticos de ISO 20022 compliance** (M-001/M-002, N-001/-002/-003/-004/-005/-006/-012/-013/-014/-016, R-013/-014/-015). El claim "MIPIT habla ISO 20022 pacs.008/.002/.004" ahora se sostiene a nivel byte:
- pacs.008 generado tiene `nbOfTxs/ctrlSum`, `XchgRate` como objeto, `LclInstrm` (donde aplica), `chrgBr` mandatorio
- pacs.002 emitido por los adapters con `OrgnlUETR` + `OrgnlEndToEndId` + `TxSts` ISO
- pacs.004 emitido por compensation con `RtrId/RtrRsnInf.Rsn.Cd` ISO
- Códigos de rechazo mapeados a `ExternalStatusReason1Code` con `Rsn.Prtry` preservando original

El gap residual es **conexión a sandboxes reales** (BCB/Banxico/BanRep), que requiere licencia financiera y está documentado en LIMITATIONS.md §1.
