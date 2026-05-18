# Auditoría 3 — B5: Defense Readiness (Demo + Entregables)

**Fecha:** 2026-05-18
**Scope:** Reproducibilidad de la demo, entregables tangibles para el panel, coherencia narrativa, honestidad académica visible, risk register de sustentación.
**Out of scope:** preguntas verbales hostiles (A4 Audit-2), spec compliance interna (A1), perf/DB (B2), tests funcionales (A3), UI styling.
**Branch:** `Auditoria-Claude` (Wave 1-6 cerradas, Wave 7-8 abiertas)
**Asumido:** sustentación en <2 semanas (≤2026-06-01).

---

## Resumen Ejecutivo

**El proyecto está técnicamente listo, pero los entregables visibles al panel están en estado frágil.** Wave 5-6 corrigió los hallazgos de Audit-2 a nivel código (UETR/ChrgBr/FX surface, recording rules, pacs.002/.004 schemas, ChargeBearer, simulator placeholders), pero quedan **tres bloques de riesgo de defensa**:

1. **El runbook de demo está envenenado con valores que fallan validación.** La tabla "6 rail-pairs" en `local-demo.md` lista `PIX-12345678901` (CPF mod-11 inválido — el algoritmo correcto da `-9`, no `-1`) y `BREB-900123456-1` (DIAN mod-11 inválido — la check digit correcta es `-8`, no `-1` ni `-7`). El **dataset** `breb-valid-nit.json` también usa el NIT inválido `-7`. **Si Nicolás copia-pega del runbook en vivo, el pago rail-pair #4 (BRE_B→PIX) y #5 (SPEI→BRE_B con NIT) van a REJECTED.** Esto es reproducible.

2. **No existe ningún entregable de presentación.** No hay `.pptx`, `.key`, `slides/`, `presentation/`, ni video demo de backup. Si el día de sustentación falla la red, falla docker o hay un cuelgue, no hay plan B visual — solo terminal + PDFs estáticos. Las carpetas `mipit-docs/evidence/{logs,traces,test-results,dashboards}/` están **vacías**: no hay screenshots de Grafana, no hay JSON exports de Jaeger, no hay XML/JSON de tests. La única evidencia "visible" son los 3 reports `wave-N-verification-*.md` (texto plano markdown).

3. **Hay tres mentiras o ambigüedades pendientes en el código vs. lo documentado:**
   - `mipit-adapter-breb/src/breb/response-mapper.ts:19` aún dice "Error codes (BanRep spec):" para BREB001-005 — Wave 5 W5.13 sólo corrigió `breb-to-canonical.ts`, dejó este archivo intacto.
   - El navbar de la UI exhibe **dos rutas de simulador**: `/simulate` (form productivo limitado a PIX/SPEI/BRE_B per W5.8) y `/simulator` (panel de mocks). Si el panel cliquea "Simulador" esperando un form de pago, ve un control de mocks — confunde.
   - El smoke test sólo cubre 3 de los 6 rail-pairs direccionales (PIX→SPEI, SPEI→BRE_B, BRE_B→PIX); las direcciones inversas (SPEI→PIX, PIX→BRE_B, BRE_B→SPEI) no tienen evidencia automatizada. La tabla del runbook promete 6, el testkit ejercita 3.

**Veredicto B5: defendible con 7 días de trabajo focalizado.** El núcleo técnico está; falta envolver. Las acciones críticas son (en orden de impacto):
1. Generar/corregir el dataset de demo con checksums verificados y commitearlo a `mipit-testkit/datasets/defense/`.
2. Producir un slide deck de 15-20 láminas y un video screencast de 5 min como respaldo "internet caído".
3. Cerrar los gaps de honestidad: el comentario "BanRep spec" en response-mapper, y la duplicidad `/simulate` vs `/simulator`.
4. Documentar explícitamente en una "defense narrative" el re-framing FedNow→Bre-B (OG-2/H4) y por qué eso no rompe el objetivo de tesis.

---

## Tabla maestra de hallazgos B5

| ID | Sev | Tipo | Título | Bloquea panel? |
|---|---|---|---|---|
| B5-001 | 🔴 CRÍT | demo-risk | `local-demo.md` lista `PIX-12345678901` con CPF mod-11 inválido (correcto: `-9`) — rail-pair #4 falla en vivo | Sí |
| B5-002 | 🔴 CRÍT | demo-risk | `local-demo.md` lista `BREB-900123456-1` con DIAN mod-11 inválido (correcto: `-8`); `breb-valid-nit.json` usa `-7` también inválido | Sí |
| B5-003 | 🔴 CRÍT | entregable-falta | No existe slide deck (`.pptx`/`.key`/`slides/`/`presentation/`/`defense/`) en todo el workspace | Sí |
| B5-004 | 🔴 CRÍT | entregable-falta | No existe video demo backup (`.mp4`/`.mov`/`.webm`) — si el día falla docker, no hay plan B visual | Sí |
| B5-005 | 🔴 CRÍT | entregable-falta | `mipit-docs/evidence/{logs,traces,test-results,dashboards}/` están **vacías** post-Wave 6 — los placeholders prometen pero no entregan | Sí |
| B5-006 | 🟠 ALTO | honestidad | `mipit-adapter-breb/src/breb/response-mapper.ts:19` aún dice "Error codes (BanRep spec):" para BREB001-005 inventados | Si lo abren |
| B5-007 | 🟠 ALTO | narrativa-incoherente | UI navbar muestra `/simulate` (form) y `/simulator` (mock panel) — confusión navegacional | Si lo cliquean |
| B5-008 | 🟠 ALTO | demo-risk | `smoke-test.sh` sólo cubre 3 de 6 rail-pairs direccionales — la tabla del runbook (6) sobrevende lo testeado (3) | Sí |
| B5-009 | 🟠 ALTO | demo-risk | `vm-demo.md` referencia `docker-compose.vm1.yml` y `docker-compose.vm2.yml` que **no existen** (sólo `docker-compose.yml`+`override`) | Si demo VM |
| B5-010 | 🟠 ALTO | demo-risk | `vm-demo.md` referencia puerto 4317 (OTLP gRPC) pero `docker-compose.yml` sólo expone 4318 (OTLP HTTP) en Jaeger | Si demo VM |
| B5-011 | 🟠 ALTO | narrativa-incoherente | Re-framing FedNow→Bre-B no está explícitamente justificado en una "carta de cambio de scope" — el panel puede leer SPMP §H4 y preguntar | Probable |
| B5-012 | 🟠 ALTO | entregable-falta | RF19 (Exportación CSV/JSON desde UI) declarado en SRS, no implementado, no scope-out en `LIMITATIONS.md` | Si revisan SRS literal |
| B5-013 | 🟡 MED | honestidad | Varios comentarios `per BACEN spec` / `per CECOBAN spec` en mappers son referencias a documentos reales pero el código sólo implementa subset — riesgo si panel pide cita textual | Si profundizan |
| B5-014 | 🟡 MED | demo-risk | El stack docker requiere ~16 contenedores + ≥6GB RAM — en una laptop común con Slack/Zoom abiertos, el OOM kill es probable | Si demo local en proyector |
| B5-015 | 🟡 MED | demo-risk | `bash scripts/up.sh` asume `docker compose` (v2) Y `jq`, `curl`, `uuidgen`; cuelgues si el laptop no los tiene preinstalados | Si demo en máquina nueva |
| B5-016 | 🟡 MED | demo-risk | El FX hardcoded da `BRL:5.02 / MXN:17.43`, ratio BRL→MXN = exactamente `3.4721` — "demasiado redondo", olor a hardcoded en pantalla | Si lo notan |
| B5-017 | 🟡 MED | narrativa-incoherente | No hay "killer feature" único — el PoC es competente pero el diferenciador vs literatura no está cristalizado en una frase memorable | Si comparan vs estado del arte |
| B5-018 | 🟡 MED | entregable-falta | No hay screenshots/diagramas en la `evidence/` ni en la memoria — el PDF `Diseno_MIPIT.pdf` no se verificó coherencia con código post-Wave 6 | Si comparan PDFs vs código |
| B5-019 | 🟢 BAJO | demo-risk | Currencies en los datasets `*-valid-*.json` son `USD` (placeholder) mientras el runbook narra `BRL/MXN/COP` — funcionará pero no narra | Si lo notan en UI |
| B5-020 | 🟢 BAJO | honestidad | "Compensación end-to-end" no está verificada live post-Wave 6 (W6.4 unit tests sí pero la entrega de pacs.004 al mock no) — declarado pendiente en wave-6-verification | Si piden demo en vivo |

---

## Detalle por hallazgo

### B5-001 🔴 CRÍT — `PIX-12345678901` en runbook tiene CPF mod-11 inválido

- **Where:** `mipit-docs/demo-runbook/local-demo.md:60` (rail-pair #4: `BRE_B → PIX`, creditor `PIX-12345678901`).
- **Qué:** El CPF `12345678901` falla la check digit por mod-11. Computado a mano contra `mipit-adapter-pix/src/pix/cpf-cnpj-validator.ts:12-28`:
  - d1: weights [10..2] sobre primeros 9 → sum=210; 11-(210%11)=11-1=10; d1>=10 ⇒ d1=0 ✓ (matchea digit[9]=0)
  - d2: weights [11..2] sobre primeros 10 → sum=255; 11-(255%11)=11-2=9; **d2=9 ≠ digit[10]=1** ✗
  - **Por lo tanto:** valid only is `12345678909`, no `12345678901`.
- **Impacto en sustentación:** Si Nicolás demuestra el rail-pair #4 copiando del runbook, el core acepta (porque `payment-request.ts:38` no valida CPF), enruta a PIX adapter, el mock-server.ts:166 hace `isValidCPF(chave)` → `false` → respuesta `REJECTED` con código de error. El panel ve "rail-pair feliz" terminando en `REJECTED`. Catastrófico.
- **Mitigación:** corregir el runbook a `PIX-12345678909` (el valor real usado en `plans/wave3-validation.sh:17` y demás validators). Adicionalmente, crear `mipit-testkit/datasets/defense/` con dataset 100% verified.
- **Acción recomendada:** corregir hoy mismo, antes del próximo `git push` a `Auditoria-Claude`.

### B5-002 🔴 CRÍT — `BREB-900123456-1` (runbook) y `breb-valid-nit.json` (-7) tienen DIAN mod-11 inválidos

- **Where:** `mipit-docs/demo-runbook/local-demo.md:61` (rail-pair #5 creditor `BREB-900123456-1`); `mipit-testkit/datasets/breb/breb-valid-nit.json:5` (`BREB-900123456-7`).
- **Qué:** Computado contra `mipit-adapter-breb/src/breb/types.ts:176-187 isValidNIT`:
  - Reversed: [6,5,4,3,2,1,0,0,9]; weights [3,7,13,17,19,23,29,37,41]
  - sum = 18+35+52+51+38+23+0+0+369 = 586; 586%11=3; rem≥2 ⇒ expected=11-3=**8**
  - **Por lo tanto:** la única check digit válida para `900123456` es `-8`. Ni `-1` ni `-7` pasa.
- **Impacto:** rail-pair #5 (SPEI→BRE_B con NIT) según runbook falla en mock breb. Adicionalmente, cualquier persona que ejecute el dataset preparado (`breb-valid-nit.json`) también obtiene REJECTED. La narrativa "tenemos validación real de checksums" se invalida si los propios assets del PoC fallan.
- **Mitigación:** corregir AMBOS archivos a `900123456-8`. Verificar el resto de la tabla del runbook ejecutando `npm run smoke` extendido a los 6 rail-pairs.

### B5-003 🔴 CRÍT — No existe slide deck

- **Where:** búsqueda exhaustiva en todo el workspace: `**/*.pptx`, `**/*.key`, `**/slides/**`, `**/presentation/**`, `**/defense/**` — **cero resultados**. El único `.key` es la cert TLS de nginx (`mipit-infra/nginx/certs/mipit.key`).
- **Qué:** un panel de sustentación tradicional espera 15-25 láminas: portada, problema, estado del arte, arquitectura, demo screenshot, evidencia, conclusiones, q&a. No tenemos ninguna lámina.
- **Impacto:** Nicolás llega con 4 PDFs (`Diseno_MIPIT.pdf`, `SRS_MIPIT.pdf`, `SPMP.pdf`, `Plantilla Propuesta...pdf`) que no son slides — son documentos densos. Presentarlos como slides es leerlos en voz alta = peor formato posible. El panel pierde atención en los primeros 3 min.
- **Mitigación:** crear `presentation/defense.pptx` (o google-slides exportable) con:
  - 1 portada
  - 2 problema (interop LATAM)
  - 2 estado del arte (PIX, SPEI, Bre-B + ISO 20022)
  - 3 arquitectura (hub-and-spoke + canónico)
  - 4 implementación (3 productivos + 4 case-study)
  - 3 demo screenshots (UI + Grafana + Jaeger)
  - 2 evidencia (591/591 tests, 11/11 validation suite, 76/76 E2E assertions)
  - 2 limitaciones y trabajo futuro
  - 1 conclusiones
- **Tiempo estimado:** 2-3 días con material existente.
- **Acción:** comenzar HOY. Es el gap más visible.

### B5-004 🔴 CRÍT — No existe video demo backup

- **Where:** `**/*.mp4`, `**/*.mov`, `**/*.webm`, `**/*.gif` — cero resultados aparte de node_modules.
- **Qué:** si el día de defensa falla el internet (FX service externo), o Docker no arranca por hyper-v collision, o el laptop OOM-kills, no hay plan B. Sólo terminal + slides.
- **Impacto:** un cuelgue de 90 segundos en vivo destroza la confianza del panel. Si el adapter falla mid-demo, no hay forma de mostrar "esto funciona normalmente, hoy hubo un transient".
- **Mitigación:** grabar 1 screencast de 5 min con `OBS Studio` o `loom.com` mostrando:
  1. `bash scripts/up.sh` levantando todo healthy
  2. UI loading → simulate PIX→SPEI
  3. Detalle del payment con UETR/ChrgBr/FX/Jaeger link
  4. Jaeger trace con cadena completa
  5. Grafana dashboard con counters incrementando
  6. Idempotency replay
  7. Adapter shutdown → DLQ message
- Embebido en slide 14 (demo) como fallback. Si la live demo falla, "vamos a verlo grabado, este es el mismo flujo que reproducimos en CI cada commit".
- **Tiempo estimado:** 1 día (incluye reintentos).

### B5-005 🔴 CRÍT — `mipit-docs/evidence/` está vacía

- **Where:** `mipit-docs/evidence/{logs,traces,test-results,dashboards}/` — directorios existen pero **0 archivos** en cada uno.
- **Qué:** la sección 4.5 del SRS y la checklist de "evidence" prometen artefactos exportados. No hay PNG de dashboards, no hay JSON de Jaeger traces, no hay XML de junit, no hay logs sanitized de un run real.
- **Impacto:** si el panel dice "muéstreme el resultado de los 76 assertions", se enseña un MD escrito a mano que **enumera** los resultados pero no muestra el output crudo. Si pide "muéstreme un trace completo de un pago en producción", no existe un export.
- **Mitigación:** ejecutar y commitear:
  - `mipit-testkit/tools/generate-evidence.sh` para producir logs en `evidence/logs/`
  - Manual: 4-6 screenshots de Grafana dashboard "MiPIT Overview" en `evidence/dashboards/*.png`
  - Manual: 2 traces de Jaeger exportados JSON en `evidence/traces/*.json`
  - `npm run test:contract -- --reporter=junit > evidence/test-results/contract.junit.xml`
  - `npm run validate:suite > evidence/test-results/validation-suite-2026-05-18.log`
- **Tiempo:** 0.5 día. Es trabajo mecánico.

### B5-006 🟠 ALTO — `breb/response-mapper.ts:19` aún dice "BanRep spec"

- **Where:** `mipit-adapter-breb/src/breb/response-mapper.ts:19-25`. Comentario textual:
  ```
  Error codes (BanRep spec):
    BREB001 — Fondos insuficientes
    BREB002 — Cuenta/entidad no encontrada
    BREB003 — Límite de transacción excedido
    BREB004 — Receptor no registrado en Bre-B
    BREB005 — Timeout del sistema BanRep
  ```
- **Qué:** Wave 5 W5.13 corrigió la línea análoga en `mipit-core/src/translation/breb-to-canonical.ts` pero dejó este archivo (en otro repo) intacto. El comentario miente — los códigos son MIPIT-invented per `LIMITATIONS.md §11`.
- **Impacto:** si un panelista hace `grep "BanRep spec" mipit-adapter-breb/`, encuentra esta línea. Audit-2 R-009 (A1 spec-compliance) ya identificó el mismo issue en otro archivo; aquí queda residual. Es exactamente la clase de inconsistencia que **lee mal** en una sustentación.
- **Mitigación:** un Edit de 3 líneas. Cambiar a:
  ```
  Error codes (MIPIT-invented per LIMITATIONS.md §11, NOT BanRep-published —
  pending mapping to ISO 20022 ExternalStatusReason1Code):
  ```

### B5-007 🟠 ALTO — UI navbar tiene `/simulate` y `/simulator` co-existiendo

- **Where:** `mipit-ui/src/components/layout/navbar.tsx:20-26`. Ambos en NAV_LINKS:
  - `/simulate` con label "Simular" e icono `SendHorizontal` → form de pago real (W5.8 limitado a 3 productivos)
  - `/simulator` con label "Simulador" e icono `Server` → panel de control de mocks (rejection rate, latencia)
- **Qué:** semánticamente diferentes. UX problema: "Simular" vs "Simulador" → suena igual en español. Un panelista que cliquea esperando un form de pago ve un panel de configuración de mocks → "¿qué es esto, dónde envío el pago?".
- **Impacto:** baja prob, alto impacto: pérdida de fluidez en la demo. Si Nicolás navega vía teclado, fácil escoger el equivocado.
- **Mitigación:** renombrar el primero a "Crear pago" o "Enviar pago", y el segundo a "Control de mocks" / "Panel de mocks". Cambio de 4 strings.

### B5-008 🟠 ALTO — Smoke test sólo cubre 3 de 6 rail-pairs direccionales

- **Where:** `mipit-testkit/tools/smoke-test.sh` cubre:
  1. PIX → SPEI
  2. SPEI → BRE_B
  3. BRE_B → PIX
- **Qué:** la tabla del runbook promete 6 rail-pairs direccionales pero los 3 **inversos** (SPEI→PIX, PIX→BRE_B, BRE_B→SPEI) no están en smoke. No tienen evidencia automatizada de happy path.
- **Impacto:** si el panel pide "muéstreme PIX→BRE_B" (rail-pair #3 según runbook), depende de que Nicolás escriba el payload a mano en cURL o navegue a la UI con un alias válido en memoria. Audit-2 D4/D5 fueron este tipo de problema.
- **Mitigación:** extender `smoke-test.sh` con 3 calls más, o crear `smoke-test-full.sh` que cubra los 6. Aprovechar para verificar que **los 6 valores del runbook table pasan**.

### B5-009 🟠 ALTO — `vm-demo.md` referencia compose files inexistentes

- **Where:** `vm-demo.md:88` (`docker-compose.vm1.yml`) y `:133` (`docker-compose.vm2.yml`).
- **Qué:** En `mipit-infra/compose/` sólo existen `docker-compose.yml` y `docker-compose.override.yml`. No hay split por VM.
- **Impacto:** si el demo se hace en VMs (no local), `docker compose -f compose/docker-compose.vm1.yml up -d` falla con "no such file". Memory file `project_vm_deployment.md` declara las VMs deployadas pero el runbook no es ejecutable. Posiblemente las VMs reales corren con `docker-compose.yml` plain y env vars diferentes; runbook no lo dice.
- **Mitigación:**
  - opción A: crear realmente los compose files split (1 día de trabajo)
  - opción B: corregir el runbook para indicar el comando real (más rápido, ~30 min)
  - Verificar SI la sustentación es local o en VMs. Si es local, ignorar este hallazgo. Si es VM, urgente.

### B5-010 🟠 ALTO — `vm-demo.md` referencia puerto 4317 (gRPC) pero compose expone 4318 (HTTP)

- **Where:** `vm-demo.md:48,71,113` mencionan OTLP `4317`; `mipit-infra/compose/docker-compose.yml:220` Jaeger sólo expone `4318:4318`.
- **Qué:** OTLP tiene dos transportes: gRPC en 4317, HTTP en 4318. El compose actual sólo abre HTTP. Si los adapters están configurados a `OTEL_EXPORTER_OTLP_ENDPOINT=http://...:4317`, las trazas no llegan.
- **Impacto:** si se intenta demo VM siguiendo el runbook literal, las trazas no fluyen → Jaeger vacío → la demo de "trazabilidad full-stack" falla. Si se hace local, depende de qué cliente OTLP usen los adapters (gRPC vs HTTP).
- **Mitigación:** verificar qué puerto usan en realidad los adapters (env var en `mipit-infra/env/*.env`) y alinear runbook + compose.

### B5-011 🟠 ALTO — Re-framing FedNow→Bre-B no documentado explícitamente

- **Where:** SPMP `H4: Evaluación con 4 rieles` (PIX, SPEI, FedNow, Bre-B). Realidad post-Wave 6: 3 productivos (PIX, SPEI, **Bre-B reemplaza FedNow**) + 4 case-study donde FedNow queda como translator-only.
- **Qué:** Audit `AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` §1.4 OG-2/OG-3 lo reconoce; pero la "carta de cambio de scope" no existe como documento standalone. Tampoco se menciona en la sección Conclusiones de la Memoria PDF (no verificado pero presumido si Wave 6 no tocó PDFs).
- **Impacto:** un panelista que lea SPMP literal pregunta "¿dónde está la evaluación con FedNow?". Respuesta defendible existe (en `LIMITATIONS.md §1` + audit), pero requiere que Nicolás la articule fluido. Sin slide o respuesta preparada, suena improvisado.
- **Mitigación:** crear `mipit-docs/defense-narrative/scope-pivot-fednow-to-breb.md` (1 página) con la justificación: "FedNow se reframea como case-study translator-only porque (a) BCB Res 304/2023 puso a Bre-B en GA 2025-10-06, abriendo un riel LATAM más relevante para integración cross-border BRL/MXN/COP que un riel US-domestic, (b) Bre-B encaja con el objetivo cross-border LATAM que da nombre a la tesis, (c) FedNow queda demostrado como traducible vía `canonical-to-fednow.ts`". Llevar impresa.

### B5-012 🟠 ALTO — RF19 (Export CSV/JSON) declarado en SRS, no implementado, no scope-out

- **Where:** SRS_MIPIT.pdf RF19; `AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` §2 línea RF19.
- **Qué:** "Exportación CSV/JSON desde UI" promesa, no implementado en `history/page.tsx` ni `analytics/page.tsx`. No declarado en LIMITATIONS.md.
- **Impacto:** el único RF de 20 NO-cumplido sin scope-out documentado. Si el panel lee SRS literal, esta es la pregunta letal "¿implementaron todos los RF?". Respuesta honesta: "19 de 20".
- **Mitigación:**
  - Opción A (técnica): implementar export — `history/page.tsx` agrega botón "Exportar JSON/CSV" usando `Blob` + `URL.createObjectURL`. ~2 horas.
  - Opción B (docs): agregar a `LIMITATIONS.md` sección 13 "RF19 deferred — el listing JSON via API (`GET /payments`) sirve como export programático; un botón UI es trivial pero no se priorizó frente a Wave 5/6". 30 min.
  - **Recomendado A**: el código es trivial y elimina la pregunta.

### B5-013 🟡 MED — Comentarios "per X spec" en mappers sin cita versionada

- **Where:** múltiples archivos:
  - `mipit-adapter-pix/src/pix/mapper.ts:40` "per BACEN spec"
  - `mipit-adapter-spei/src/spei/mapper.ts:76` "per CECOBAN spec"
  - `mipit-adapter-spei/src/spei/types.ts:3` "Based on: BANXICO CECOBAN specification"
  - `mipit-adapter-breb/src/breb/response-mapper.ts:19` "BanRep spec" (ya hallazgo B5-006)
- **Qué:** los comments aluden a specs reales sin citar versión/sección. "per BACEN spec" es vago; BACEN tiene "Manual de Padrões para Mensageria PIX" y "Resolução 1/2020" y otros. Para una tesis, idealmente cada referencia tiene `(v2.3 §3.4)` o similar.
- **Impacto:** medio — los specs existen y son verificables externamente; pero si un panelista de finanzas pide "muéstreme la página exacta del manual", no hay link directo.
- **Mitigación:** dejarlo como está si tiempo es escaso; alternativamente reemplazar por `per BACEN Manual de Padrões §X.Y` cuando sea verificable. Para el response-mapper Bre-B sí es crítico (B5-006).

### B5-014 🟡 MED — Stack docker requiere ≥6GB RAM + 16 contenedores

- **Where:** `checklist-pre-demo.md:7` "≥6 GB libres". 16 contenedores: postgres, rabbitmq, jaeger, prometheus, alertmanager, grafana, core, 3 adapters, 3 mocks, nginx, ui.
- **Qué:** un laptop común con 16 GB RAM + Slack + Zoom + Chrome (40 tabs) + IDE = fácilmente <6GB libres. OOM-killer mata contenedores random.
- **Impacto:** demo en proyector con laptop personal — alta prob de cuelgue inesperado mid-demo.
- **Mitigación:**
  - Pre-demo: cerrar Slack/Zoom/IDE/extra browser tabs.
  - Hacer un `docker compose down` y `up -d` limpio antes de cada demo.
  - Si el laptop es <16GB total, demo desde una VM o desktop dedicado.

### B5-015 🟡 MED — `scripts/up.sh` asume binarios disponibles

- **Where:** `mipit-infra/scripts/up.sh:5,17,27`; `health-check.sh:7` usa `curl`; smoke usa `jq`, `uuidgen`.
- **Qué:** bash script en Windows — Nicolás está en Windows (per `env` info `Platform: win32`). Bash existe en WSL/git-bash, pero `docker compose` requiere Docker Desktop Y los binarios `jq`, `uuidgen` no son default en git-bash.
- **Impacto:** si presenta desde Windows nativo: `bash scripts/up.sh` falla por `jq: command not found` o similar. Si presenta desde WSL2: ok pero `docker compose` debe estar en PATH.
- **Mitigación:** previo a sustentación, hacer un dry-run completo en la máquina exacta que se usará. Documentar como pre-req: WSL2 + Docker Desktop + `apt install jq uuid-runtime`.

### B5-016 🟡 MED — FX hardcoded da ratio "sospechosamente redondo"

- **Where:** `mipit-core/src/fx/fx-service.ts:48` `FALLBACK_RATES: BRL:5.02, MXN:17.43, COP:4180.0`.
- **Qué:** sin `OPEN_EXCHANGE_RATES_APP_ID` (no setteado por default), BRL→MXN = 17.43/5.02 = exactly **3.47211...** que aparece en UI/DB. El "exacto" 3.4721 huele a hardcoded.
- **Impacto:** un panelista financiero detecta y pregunta "¿de dónde vienen esas tasas?". Respuesta honesta: "fallback hardcoded del 2026-Q1, sin connection a un provider real porque no se setteó la API key". Audit-2 A4-Q10 ya lo identificó.
- **Mitigación:** poner `OPEN_EXCHANGE_RATES_APP_ID` real (free tier OK) en `.env` antes del demo. Tasa fluctuará pero al menos no es hardcoded visible. O documentar en slide "FX fallback hardcoded — entorno PoC".

### B5-017 🟡 MED — Falta "killer feature" diferenciado

- **Where:** narrativa global del PoC.
- **Qué:** los componentes técnicos están bien (canónico ISO 20022, hub-and-spoke, 6 rail-pairs, pacs.002/004, observabilidad full-stack). Pero la frase "¿qué hace MIPIT que ningún paper anterior haga?" no tiene respuesta cristalizada en una lámina.
- Posibles killer features:
  - **"Bre-B (Colombia) como primer prototipo público académico"** — TR-002 GA fue oct-2025, MIPIT lo modeló en 2026-05; ningún paper anterior lo cubre.
  - **"6 rail-pairs direccionales LATAM canónicos"** — la matriz PIX×SPEI×BRE_B es novedosa.
  - **"Traducción byte-exact a pacs.008/.002/.004"** — Wave 6 deja byte-fidelity verificable.
- **Impacto:** si el panel pregunta "¿qué contribuyen al estado del arte?", respuesta improvisada vs respuesta preparada cambia la nota.
- **Mitigación:** lámina 1 de slide deck — un statement como: *"MIPIT es el primer middleware académico que canoniza los tres rieles instantáneos LATAM (PIX, SPEI, Bre-B) a un subset de pacs.008 byte-exact, demostrando hub-and-spoke a través de 6 rail-pairs direccionales con observabilidad full-stack."*

### B5-018 🟡 MED — PDFs de tesis no verificados coherentes con código post-Wave 6

- **Where:** `Diseno_MIPIT.pdf`, `SRS_MIPIT.pdf`, `SPMP.pdf` en raíz.
- **Qué:** Wave 5/6 cambió comportamiento (chargeBearer default SLEV, validaciones de checksums, /simulate restringido a 3 productivos, pacs.002/.004 enriquecido). Los PDFs son artefactos congelados de fase Diseño/SRS. Si dicen "RF02: validar formato de CLABE" y código además valida mod-10, OK. Si dicen "Pago a 4 rieles incluyendo FedNow" y código sólo tiene 3 productivos + FedNow case-study, hay drift documentado en `AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` pero no en los PDFs.
- **Impacto:** el panel **lee los PDFs**. Si el PDF dice X y el código hace Y, ya hay una pregunta. Audit Cumplimiento §1.4 lo señala para OG-2/H4.
- **Mitigación:** no se pueden re-emitir los PDFs (asumo) pero sí preparar una "fe de erratas" de 1 página: "Sección X del SRS dice 'FedNow productivo'; entrega final es 'FedNow case-study'. Justificación: ver §1 LIMITATIONS y `defense-narrative/scope-pivot-fednow-to-breb.md`".

### B5-019 🟢 BAJO — Datasets con currency USD mientras runbook narra BRL/MXN/COP

- **Where:** `mipit-testkit/datasets/pix/pix-valid-01.json:2` `currency: USD`; idem en SPEI. local-demo.md tabla dice "BRL→MXN".
- **Qué:** los datasets pre-armados usan USD como placeholder. El smoke test (`smoke-test.sh`) usa BRL/MXN/COP. La UI form acepta cualquier currency con length=3 (`payment-request.ts:54`).
- **Impacto:** mínimo. La narrativa "cross-border LATAM" implica monedas locales, no USD. Si Nicolás copia-pega `pix-valid-01.json` en un form, el detail page va a mostrar "USD 150.25", inconsistente con la frase "PIX→SPEI BRL→MXN".
- **Mitigación:** corregir los datasets a las monedas reales del rail. 5 min de trabajo.

### B5-020 🟢 BAJO — Compensación end-to-end no verificada live post-Wave 6

- **Where:** `wave-6-verification-2026-05-17.md:75-78` ("W6.4 verify live: el código pacs.004 está + tests unit pasan, pero verificar el flow end-to-end requiere provocar un FAILED y compensarlo. Demo durante sustentación").
- **Qué:** Wave 6 deja la verificación live como pendiente; el código compila y tests unit pasan, pero la cadena adapter→DLQ→reconciliation→compensate→pacs.004→mock no se probó como flow continuo. Audit-2 A4-Q9 (`compensation-service.ts` "log the intent") sigue parcialmente abierto.
- **Impacto:** si el panel pide "muéstrenme compensación", Nicolás depende de que ese flow funcione live por primera vez en sustentación. Riesgo medio-bajo.
- **Mitigación:** ejecutar el flow al menos 1 vez completo antes de sustentación. Si falla, documentar en `LIMITATIONS.md` y demonstrar el componente (DB transition + audit row) en vez del flow completo.

---

## Inventario de entregables — estado post-Wave 6

| Item | Existe? | Actualizado? | Presentable? | Notas |
|---|---|---|---|---|
| **PDFs** Diseño/SRS/SPMP/Propuesta | ✅ | ⚠️ pre-Wave 5 | ⚠️ | drift contra código actual (RF19, FedNow); fe-de-erratas necesaria |
| **Código 9 repos** | ✅ | ✅ Auditoria-Claude | ✅ | 591/591 unit tests, 11/11 validation suite |
| **Demo stack docker** | ✅ | ✅ | ⚠️ | requiere ≥6GB RAM; runbook tiene 2 valores con checksums inválidos (B5-001/002) |
| **Slides defensa** | ❌ | — | ❌ | **gap CRÍTICO** — no existe |
| **Video demo backup** | ❌ | — | ❌ | **gap CRÍTICO** — no existe |
| **Evidence/ folders** | ⚠️ vacías | ❌ | ❌ | logs/traces/test-results/dashboards todos vacíos |
| **Smoke + contract + validation suite** | ✅ | ✅ | ✅ | sólo cubre 3/6 rail-pairs en smoke |
| **Audit trail Auditoria-2** | ✅ | ✅ | ✅ | 88 hallazgos documentados, 41 cerrados Wave 5+6 |
| **LIMITATIONS.md** | ✅ | ✅ | ✅ | bien actualizado, sec 11+12 |
| **demo-runbook (local + vm + checklist)** | ✅ | ⚠️ | ❌ | runbook envenenado con checksums inválidos + referencias a compose files inexistentes |
| **Auto-memory (MEMORY.md)** | ✅ | ✅ 2026-05-18 | n/a | uso interno del agente |

**Score global de entregables: 7/11 listos.** Los 4 gaps (slides, video, evidence, runbook fix) son todos abordables en ≤7 días.

---

## Defense narrative coherence — auditoría

### ¿La narrativa "interop ISO 20022 cross-border LATAM" se sostiene?

| Pregunta | Verificación en código | Estado |
|---|---|---|
| ¿Existe translation bidireccional para los 3 productivos? | `mipit-core/src/translation/{pix,spei,breb}-to-canonical.ts` y `canonical-to-{pix,spei,breb}.ts` | ✅ |
| ¿Existe pacs.008/.002/.004? | `src/canonical/pacs00{8,2,4}.schema.ts` | ✅ |
| ¿UI muestra original→canónico→traducido? | `mipit-ui/src/components/payments/message-inspector.tsx` 3 columnas | ✅ |
| ¿Los 6 rail-pairs son demostrables hoy? | smoke cubre 3; runbook lista 6; los 3 inversos no automatizados | ⚠️ |
| ¿UETR / EndToEndId / ChrgBr / IntrBkSttlmDt en UI? | `payments/[id]/page.tsx:107-156` (P11) | ✅ |
| ¿FX cross-currency surface? | `payments/[id]/page.tsx:160-178` + `payments.ts:142-147` | ✅ |
| ¿Jaeger link funcional? | `payments/[id]/page.tsx:146-152` via `mipit.trace_id` attribute search (W5.3) | ✅ |
| ¿Killer feature único? | No cristalizado en una frase | ❌ |

**Net:** la narrativa técnica se sostiene bien post-Wave 6. El gap es **presentacional** (no hay slide deck) y **el wow factor** (no hay killer feature articulada).

---

## Honestidad académica — auditoría

| Claim ambiguo | Donde aparece | Estado |
|---|---|---|
| "BanRep spec" para BREB001-005 | `breb/response-mapper.ts:19` | ❌ NO FIXED (B5-006) |
| "BanRep spec" para BREB001-005 | `breb-to-canonical.ts:28-34` | ✅ FIXED W5.13 |
| "BanRep spec v1.0 (2023)" inventada | `breb/mock-server.ts:8` | ✅ FIXED P04 |
| "per BACEN spec" sin cita | `pix/mapper.ts:40` | 🟡 ACEPTABLE (BACEN spec es real y pública) |
| "per CECOBAN spec" sin cita | `spei/mapper.ts:76` | 🟡 ACEPTABLE (idem) |
| "ISO 20022 compliant" sin subset | `LIMITATIONS.md §2` explícitamente nombra "subset documentado" | ✅ |
| "Mocks vs oficiales" | `LIMITATIONS.md §1` etiqueta clara cada riel | ✅ |
| RF19 (export CSV/JSON) no entregado, no scope-out | `LIMITATIONS.md` faltante | ❌ NO DOCUMENTADO (B5-012) |
| FedNow → Bre-B re-framing | `LIMITATIONS.md §1` y `AUDITORIA-CUMPLIMIENTO §1.4` | ⚠️ documentado pero no en una "defense narrative" lista para citar |

**Net:** 6 de 9 fixed, 1 acceptable, **2 gaps abiertos** (B5-006, B5-012) y 1 needs polishing (defense narrative scope pivot).

---

## Risk Register Final — Los 10 escenarios concretos de sustentación

> Cada escenario incluye probabilidad (baja/media/alta), impacto (baja/medio/alto/crítico), causa raíz, mitigación pre-defensa y respuesta in-the-moment si ocurre.

### Risk 1 — Demo PIX→SPEI termina en REJECTED por CPF inválido
- **Prob:** 🔴 alta (si Nicolás copia del runbook)
- **Impacto:** 🔴 crítico (rompe la primera demo)
- **Causa:** B5-001 — runbook tiene `PIX-12345678901` (CPF inválido).
- **Pre-defensa:** corregir runbook y datasets a valores con checksum válido. Pre-cargar 5 valores correctos memorizados o en un cheat-sheet impreso.
- **In-the-moment:** "Disculpen, ese alias tiene un typo. Déjenme usar este otro de mi notas." Mostrar cheat-sheet impreso.

### Risk 2 — Demo BRE_B→PIX o SPEI→BRE_B termina en REJECTED por NIT inválido
- **Prob:** 🔴 alta (B5-002)
- **Impacto:** 🔴 crítico
- **Causa:** runbook + breb-valid-nit.json tienen `-1` / `-7` cuando lo válido es `-8`.
- **Pre-defensa:** corregir ambos archivos. Validar con `npm run smoke -- --rail-pair BRE_B-SPEI`.
- **In-the-moment:** idem Risk 1.

### Risk 3 — Docker OOM-killea contenedores mid-demo
- **Prob:** 🟡 media (B5-014, depende de la máquina)
- **Impacto:** 🔴 crítico (uno o más adapters caen, demo congela)
- **Causa:** ≥6GB RAM + 16 contenedores + apps adicionales abiertas.
- **Pre-defensa:** cerrar Slack/Zoom/Chrome; reset stack 30 min antes; correr en máquina dedicada si posible.
- **In-the-moment:** cambiar a video screencast (B5-004 mitigation): "Vamos a verlo grabado, este es el mismo flujo de CI".

### Risk 4 — Internet cae, FX externo no responde, UI sin contenido
- **Prob:** 🟡 media (depende de venue WiFi)
- **Impacto:** 🟡 medio
- **Causa:** `OPEN_EXCHANGE_RATES_APP_ID` no setteado o API caída.
- **Pre-defensa:** verificar que `FALLBACK_RATES` se activa cuando no hay key (`fx-service.ts:110`). Demo no rompe.
- **In-the-moment:** "Tenemos un fallback hardcoded de tasas — verán que sigue funcionando. En producción habría un cache distribuido y múltiples providers".

### Risk 5 — El panel cliquea "Ver en Jaeger" y no encuentra el trace
- **Prob:** 🟡 media (Audit-2 A4-Q27)
- **Impacto:** 🟠 alto (rompe la narrativa "trazabilidad full-stack")
- **Causa:** W5.3 cambió el link a `?service=mipit-core&tags={mipit.trace_id:...}` (attribute search). Si Jaeger no tiene los spans, no encuentra. Eso pasa si OTel sampling es agresivo o el span no fue exportado.
- **Pre-defensa:** verificar `OTEL_TRACES_SAMPLER_ARG=1.0` (100% sampling) en `.env` antes de la demo. Hacer un pago de prueba 10 min antes y clicar el link — confirmar que aparece.
- **In-the-moment:** "Jaeger a veces tarda 10-15 segundos en aceptar el span. Vamos a recargar." Si no, abrir Jaeger directamente con search "service=mipit-core" y mostrar el trace más reciente.

### Risk 6 — El panel pide compensación pacs.004 end-to-end en vivo
- **Prob:** 🟢 baja (B5-020)
- **Impacto:** 🟠 alto
- **Causa:** flow live no verificado post-Wave 6.
- **Pre-defensa:** ejecutar el flow 1x antes de defensa. Si falla, documentar en LIMITATIONS.md.
- **In-the-moment:** mostrar el state transition en DB (`SELECT * FROM payments WHERE payment_id = 'PMT-...'` → COMPENSATED) y el audit row, en vez del XML pacs.004 enviado al mock. "El bloque pacs.004 se construye y persiste como evidencia; la entrega al mock depende del estado del adapter".

### Risk 7 — Pregunta "muéstreme el `mapping_table` data-driven" (Audit-2 A4-Q4)
- **Prob:** 🟡 media
- **Impacto:** 🔴 crítico (Audit-2 declara este el "mayor riesgo del PoC": `applyTransformation` sólo soporta 7 ops básicas, las 13 del seed SQL son decorativas).
- **Causa:** `pix-to-canonical.ts:11-30` no implementa las transformaciones de SQL.
- **Pre-defensa:** preparar respuesta honesta: "La mapping_table es referencia documental; las transformaciones avanzadas (FX, MED, RegEx regenerate) se compilan en TypeScript no en SQL. Es una decisión de tradeoff entre flexibilidad y type-safety". (Wave 5 W5.14 documentó esto en `seed_mapping_table.sql`).
- **In-the-moment:** abrir `seed_mapping_table.sql` y mostrar el header con la disclosure "mapping-as-documentation, not policy engine".

### Risk 8 — DB queda corrupta entre prep y demo (idempotency keys colisión, payments stuck)
- **Prob:** 🟢 baja
- **Impacto:** 🟡 medio
- **Causa:** runs previos dejan estado parcial.
- **Pre-defensa:** ejecutar `bash scripts/reset.sh` 15 min antes de defensa. Verificar `docker compose ps` → todos healthy.
- **In-the-moment:** si DB está rara, `docker compose down && up -d && bash scripts/migrate.sh` toma 90 segundos. Justificable como "limpiar entorno".

### Risk 9 — Pregunta "Throughput real medido?" (Audit-2 A4-Q28)
- **Prob:** 🟡 media
- **Impacto:** 🟡 medio
- **Causa:** sin load test formal (k6/Gatling). B2-001 (Auditoría 3) confirma cuello en AckConsumer sin prefetch → ~25-45 TPS sostenible.
- **Pre-defensa:** preparar slide o respuesta cualitativa: "El PoC está dimensionado para decenas de TPS (validado empíricamente con smoke + idempotency stress en 76 assertions). PIX real es ~30k TPS; el cuello del PoC es AckConsumer single-threaded — documentado en LIMITATIONS y B2 audit como roadmap".
- **In-the-moment:** mostrar el histogram en Grafana, latencias P50/P95 en milisegundos. "Las latencias bajo carga ligera son P95 ~80ms; sin medición formal de TPS sostenido."

### Risk 10 — Panel detecta inconsistencia entre PDF (SRS/Memoria) y código
- **Prob:** 🟡 media (probabilidad de que el panel lea el SRS con detalle)
- **Impacto:** 🟠 alto (RF19, FedNow re-framing, mapping_table behavior, BREB error codes)
- **Causa:** los PDFs son artefactos congelados; el código evolucionó Wave 5+6.
- **Pre-defensa:** llevar **impresa** una "fe de erratas" de 1 página listando los 3-4 deltas conocidos (RF19, FedNow, mapping_table, BREB nomenclatura). Apoyarse en `AUDITORIA-CUMPLIMIENTO-TESIS-2026-05-17.md` como evidencia de que se reconoce el drift.
- **In-the-moment:** "Reconocemos ese delta y lo documentamos en LIMITATIONS.md §X y en la auditoría de cumplimiento. La justificación es [X]. Lo dejamos como brecha visible en vez de re-emitir el SRS porque [Y]."

---

## Plan de mitigación priorizado (≤7 días)

Asumiendo sustentación en 7-14 días, asignación de esfuerzo en orden de impacto:

### Día 1 (urgente, 4 horas)
- [ ] B5-001: corregir `local-demo.md:60` a `PIX-12345678909`
- [ ] B5-002: corregir `local-demo.md:61` y `datasets/breb/breb-valid-nit.json` a `BREB-900123456-8`
- [ ] B5-006: actualizar `breb/response-mapper.ts:19` con disclaimer correcto
- [ ] B5-012: implementar export JSON en `history/page.tsx` (≤2h) o documentar en LIMITATIONS (30 min)
- [ ] B5-019: corregir currencies en datasets (USD → BRL/MXN/COP)
- [ ] Re-ejecutar smoke con valores corregidos para confirmar 6/6 happy paths

### Día 2-3 (slides, 1.5 días)
- [ ] B5-003: crear `presentation/defense.pptx` con la estructura propuesta (15-20 láminas)
- [ ] B5-017: cristalizar la frase killer feature en la primera lámina
- [ ] B5-011: redactar `defense-narrative/scope-pivot-fednow-to-breb.md` (1 página)
- [ ] B5-018: fe-de-erratas PDF→código (1 página impresa)

### Día 4 (video, 1 día)
- [ ] B5-004: grabar screencast de 5 min con OBS / Loom
- [ ] Embeber link/archivo en slide 14
- [ ] B5-014: probar la demo en máquina de presentación, medir uso de RAM

### Día 5 (evidence, 0.5 día)
- [ ] B5-005: poblar `evidence/dashboards/` con 4-6 screenshots de Grafana
- [ ] poblar `evidence/traces/` con 2 JSON exports de Jaeger
- [ ] poblar `evidence/test-results/` con outputs de smoke + contract + validation suite

### Día 6 (smoke completo, 0.5 día)
- [ ] B5-008: extender `smoke-test.sh` o crear `smoke-test-full.sh` con los 6 rail-pairs
- [ ] B5-007: renombrar nav items "Simular" → "Crear pago", "Simulador" → "Panel de mocks"
- [ ] B5-020: ejecutar flow de compensación end-to-end al menos 1x

### Día 7 (dry run completo)
- [ ] Demo completo seguido del runbook actualizado, cronometrar (~15 min)
- [ ] Validar B5-005/009/010 si aplica VM
- [ ] B5-016: settear `OPEN_EXCHANGE_RATES_APP_ID` si tienen key, o aceptar fallback
- [ ] Llevar cheat-sheet impreso con valores válidos memorizados

---

## Notas finales para Nicolás

### Lo que sí está sólido y se puede defender con confianza
- **Arquitectura hub-and-spoke** con canónico pacs.008-derivado, ADR-002 documenta tradeoffs.
- **3 rieles productivos LATAM** con adapter + mock + pipeline E2E ejercitados.
- **Validación de checksums real** (CPF mod-11, CNPJ mod-11, CLABE mod-10, NIT mod-11) — código verificable.
- **Observabilidad full-stack** con UETR + trace_id propagado UI→Core→Adapter→ACK.
- **76/76 E2E assertions + 591/591 unit tests** documentados.
- **2 auditorías + 7 plans (P01-P12) + 2 waves (5,6)** muestran rigor académico raro en PoC.
- **LIMITATIONS.md** brillantemente honesto, sección 11/12 reciente.

### Lo que duele admitir pero hay que tener listo
- FedNow degradado a translator-only (re-framed por Bre-B GA 2025-10-06).
- RF19 (export CSV) sin entregar (mitigable con 2h de código o 1 sección de LIMITATIONS).
- Compensación pacs.004 no probada live end-to-end.
- mapping_table SQL es referencial, no policy-engine ejecutable (decisión arquitectónica, documentada).
- Sin load testing formal — datos cualitativos (P95 < 100ms) en lugar de TPS.
- No corre TPS reales de PIX/SPEI/Bre-B; mocks con checksum-validation real.

### El elefante en la sala
**No hay slide deck ni video.** Es el gap más visible y el más fácil de cerrar. Cualquier panel espera ver láminas. Sin ellas, la sustentación es "Nicolás abriendo VSCode y navegando archivos" — un formato que para un proyecto técnico tan completo deja una impresión injustamente baja. **Día 2-4 son los más críticos del plan de mitigación.**

---

**Fin del informe B5.**
