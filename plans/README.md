# Planes de remediación — Auditoría Claude

> **Update 2026-05-18**: agregada segunda generación de waves (Wave 5–8) tras la auditoría 2.
> Ver sección **"Waves 5–8 — Post-Auditoría 2"** abajo.

Esta carpeta contiene:
- **12 planes P01–P12** desacoplados de la primera auditoría (2026-05-16, ya implementados como Waves 1–4)
- **4 plans de wave** (Wave 5 entregada, Wave 6 entregada, Wave 7/8 prospectivos) derivados de la auditoría 2 (2026-05-17)

Cada plan es independiente, con `file:line` citations, tareas concretas, acceptance criteria y commits sugeridos.

**Reportes raw**:
- Auditoría 1: `../audits/AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md`
- Auditoría 2: `../audits/AUDITORIA-2-2026-05-17.md` (más raw files en `../audits/raw/audit-2-2026-05-17/`)

**Branch activa**: `Auditoria-Claude` en los 9 repos (desde `master`/`main`). Las branches efímeras `wave-N-*` no se usan — se commitea directo.

---

## Olas de ejecución (waves)

```
Wave 1 (foundation, paralelo)
├── P09 — DB Schema Hardening                    [mipit-infra]
├── P01 — Canonical & ISO 20022 Alignment        [mipit-core, mipit-docs, mipit-infra]
└── P08 — Security Hardening                     [mipit-core, mipit-infra, adapters, ui]

Wave 2 (rail-specific, paralelo, depende de P01+P09)
├── P02 — PIX Spec Compliance                    [mipit-adapter-pix, mipit-core]
├── P03 — SPEI Spec Compliance                   [mipit-adapter-spei, mipit-core]
└── P04 — Bre-B Completion                       [mipit-adapter-breb, mipit-core, mipit-infra, mipit-docs]

Wave 3 (cross-cutting, paralelo, depende de Wave 2)
├── P05 — FX Cross-Currency                      [mipit-core, all adapters]
└── P06 — Pipeline Reliability + Outbox          [mipit-core, mipit-infra]

Wave 4 (downstream)
├── P07 — Observability End-to-End               [mipit-observability + multi]
├── P11 — UI Critical Fixes                      [mipit-ui]
├── P10 — Testkit Completeness                   [mipit-testkit]
└── P12 — Documentation & Drift                  [mipit-docs + multi]
```

Tiempo total estimado **paralelo**: ~10 días con 2 devs.
Tiempo total **secuencial worst-case**: ~30 días con 1 dev.

---

## Planes (índice)

| ID | Título | Wave | Repos | Tiempo | Riesgo |
|---|---|---|---|---|---|
| [P01](P01-canonical-iso20022-alignment.plan.md) | Canonical Model & ISO 20022 Alignment | 1 | core, docs, infra | 3-4d | Alto |
| [P02](P02-pix-spec-compliance.plan.md) | PIX Spec Compliance | 2 | adapter-pix, core | 2-3d | Medio |
| [P03](P03-spei-spec-compliance.plan.md) | SPEI Spec Compliance | 2 | adapter-spei, core | 2-3d | Alto |
| [P04](P04-breb-completion.plan.md) | Bre-B Completion & Honest Documentation | 2 | adapter-breb, core, infra, docs | 3d | Alto |
| [P05](P05-fx-cross-currency.plan.md) | FX Cross-Currency Implementation | 3 | core, all adapters | 2-3d | Alto |
| [P06](P06-pipeline-reliability.plan.md) | Pipeline Reliability & Transactional Outbox | 3 | core, infra | 4-5d | Alto |
| [P07](P07-observability-end-to-end.plan.md) | Observability End-to-End | 4 | observability, infra, core, adapters, ui | 3-4d | Medio |
| [P08](P08-security-hardening.plan.md) | Security Hardening | 1 | core, infra, adapters, ui | 2-3d | Medio |
| [P09](P09-db-schema-hardening.plan.md) | DB Schema Hardening | 1 | infra | 1-2d | Medio |
| [P10](P10-testkit-completeness.plan.md) | Testkit Completeness | 4 | testkit | 3-4d | Bajo |
| [P11](P11-ui-critical-fixes.plan.md) | UI Critical Fixes | 4 | ui | 2-3d | Bajo |
| [P12](P12-documentation-drift.plan.md) | Documentation & Drift Reconciliation | 4 | docs, root, multi | 2-3d | Bajo |

---

## Convenciones

- **Branch**: `Auditoria-Claude` en cada repo (creada desde principal el 2026-05-16).
- **Commits**: cada plan tiene una lista numerada de commits sugeridos. Usar prefijos `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`.
- **Acceptance criteria**: cada plan tiene checklist concreta — cerrar el plan solo cuando todas marcadas.
- **Coordination**: planes con scope cross-repo coordinarse via PR comments o weekly sync.
- **Testing**: cada plan tiene su `Testing plan` section. Suite `validate:suite` debe estar verde post-plan.

---

## Hallazgos cerrados por cada plan

Cada plan referencia los `ID` específicos de la auditoría que cierra (ver tablas en sección "Findings que cierra" dentro de cada `.plan.md`).

Total agregado: **~195 hallazgos** distribuidos:
- **~25 Críticos**: bloquean defensa de tesis con integridad
- **~50 Altos**: visibles en demo, cazables por panel técnico
- **~80 Medios**: quality / polish
- **~40 Bajos**: nits

Distribución por plan (no exclusivo — algunos hallazgos cierran en múltiples planes):

| Plan | C | H | M | L |
|---|---|---|---|---|
| P01 Canonical | 5 | 6 | 1 | 0 |
| P02 PIX | 5 | 6 | 4 | 0 |
| P03 SPEI | 6 | 5 | 5 | 0 |
| P04 Bre-B | 6 | 5 | 3 | 0 |
| P05 FX | 2 | 1 | 4 | 0 |
| P06 Pipeline | 6 | 7 | 1 | 0 |
| P07 Observability | 6 | 5 | 1 | 0 |
| P08 Security | 2 | 14 | 1 | 0 |
| P09 DB Schema | 0 | 8 | 7 | 2 |
| P10 Testkit | 3 | 8 | 4 | 0 |
| P11 UI | 1 | 8 | 5 | 1 |
| P12 Docs | 1 | 13 | 11 | 3 |

---

## Cómo trabajar con estos planes

### Workflow recomendado por plan

```bash
# 1. Asegurar branch correcta
cd C:/Users/nicog/Documents/Tesis/<repo>
git checkout Auditoria-Claude

# 2. Leer plan completo
cat ../plans/P0X-*.plan.md

# 3. Trabajar por tarea, commits incrementales
git commit -m "feat(scope): description"

# 4. Validar Acceptance Criteria checklist
# 5. Run testing plan
npm test
# o cd ../mipit-testkit && npm run validate:suite

# 6. Push branch
git push -u origin Auditoria-Claude

# 7. Abrir PR contra master/main
gh pr create --title "P0X: <plan title>" --body "Closes findings: ..."
```

### Dependencias entre planes

Si un plan dependía de otro (ej. P02 depende de P01), **mergear el plan upstream primero** o trabajar en branch derivada `Auditoria-Claude-P02-on-P01`.

### Coordinación cross-repo

P04 (Bre-B) toca 4 repos. P07 (Observability) toca 5+. Para estos:
- Crear PR por repo
- Hacer merge en orden topológico (DB primero, code después, docs último)
- Verificar suite verde después de cada merge

---

## Estado actual (snapshot 2026-05-18)

| Wave | Origen | Estado | Evidencia |
|---|---|---|---|
| 1 (P01+P06+P08+P09) | Auditoría 1 | ✅ Cerrada | `../evidence/wave-1-4-verification-2026-05-17-macos.md` |
| 2 (P02+P03+P04) | Auditoría 1 | ✅ Cerrada | idem |
| 3 (P05) | Auditoría 1 | ✅ Cerrada | idem |
| 4 (P07+P10+P11+P12) | Auditoría 1 | ✅ Cerrada | idem |
| **5** (Hardening pre-sustentación, 14 tickets) | Auditoría 2 Bloque A | ✅ Cerrada 2026-05-17 | `../evidence/wave-5-verification-2026-05-17.md` |
| **6** (ISO 20022 spec compliance, 13 tickets) | Auditoría 2 Bloque B | ✅ Cerrada 2026-05-17 | `../evidence/wave-6-verification-2026-05-17.md` |
| **7** (SoT + limpieza, 16 tickets) | Auditoría 2 Bloque D | ⏳ Planeada | [Wave-7-Single-Source-of-Truth-y-Limpieza.plan.md](Wave-7-Single-Source-of-Truth-y-Limpieza.plan.md) |
| **8** (Production ready, 28 tickets) | Auditoría 2 Bloque C | ⏳ Planeada | [Wave-8-Production-Ready.plan.md](Wave-8-Production-Ready.plan.md) |

---

## Waves 5–8 — Post-Auditoría 2

Después de cerrar las Waves 1–4 ejecutamos la segunda auditoría (5 agentes paralelos, 88 hallazgos NUEVOS). El plan maestro de remediación está en [../audits/AUDITORIA-2-2026-05-17.md](../audits/AUDITORIA-2-2026-05-17.md) organizado en 4 bloques (A/B/C/D) que mapean a Waves 5/6/8/7 respectivamente.

### Plans index

| Wave | Plan | Estado | Tickets | Tiempo |
|---|---|---|---|---|
| 5 | [Wave-5 — Hardening Pre-Sustentación](Wave-5-Hardening-Pre-Sustentacion.plan.md) | ✅ Cerrada | 14 | ~3h |
| 6 | [Wave-6 — ISO 20022 Spec Compliance](Wave-6-ISO20022-Spec-Compliance.plan.md) | ✅ Cerrada | 13 | ~3.5d entregado en 1 sesión |
| 7 | [Wave-7 — SoT + Limpieza](Wave-7-Single-Source-of-Truth-y-Limpieza.plan.md) | ⏳ Planeada | 16 | ~1.5d |
| 8 | [Wave-8 — Production Ready](Wave-8-Production-Ready.plan.md) | ⏳ Planeada | 28 | ~7-10d |

### Orden recomendado de ejecución

```
Wave 5  (3h, pre-sustentación, prioridad MÁXIMA si demo está cerca)
   ↓
Wave 6  (3.5d, ISO compliance, prioridad ALTA — refuerza claim académico)
   ↓
Wave 7  (1.5d, limpieza, prioridad MEDIA — no bloquea sustentación)
   ↓
Wave 8  (7-10d, producción, prioridad BAJA — sólo si MIPIT continúa post-tesis)
```

### Notas de implementación Waves 5–6

- Se commiteó directo a `Auditoria-Claude` (no se usaron branches separadas tipo `wave-5-hardening` — la primera versión las usó pero se decidió consolidar)
- Tests ajustados al código, no al revés (regla del equipo)
- Verificación live contra `docker compose` rebuilt: smoke 3/3 + curl assertions + DB queries
- Cada Wave dejó un doc `evidence/wave-N-verification-2026-05-DD.md` con comandos exactos para reproducir

---

## Notas finales (Waves 1–4)

1. **Wave 1 (P01+P08+P09) puede empezar inmediatamente**. Son foundation sin dependencias.
2. **P02/P03/P04 paralelizables** una vez P01/P09 mergeados.
3. **P07 puede correr en paralelo a P02-P06** mostly — solo depende de adapter metric naming (P02/P03/P04) para los dashboards.
4. **P10/P11/P12 son last** — testean / muestran / documentan lo que P01-P09 construyó.

Si tiempo limitado, **prioridad sustentación**: P01 + P02 + P03 + P04 + P05 + P12. Eso cierra los hallazgos críticos visibles para un panel técnico.
