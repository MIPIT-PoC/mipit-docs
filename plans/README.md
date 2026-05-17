# Planes de remediación — Auditoría Claude 2026-05-16

Esta carpeta contiene 12 planes desacoplados para remediar los ~195 hallazgos de la auditoría profunda ejecutada el 2026-05-16. Cada plan es independiente, con `file:line` citations, tareas concretas, acceptance criteria y commits sugeridos.

**Reportes raw**: ver `../AUDITORIA-PROFUNDA-MIPIT-2026-05-16.md` (índice) y `../AUDIT-RAW-{translation,adapters,ui-docs}.md` (detalle).

**Branch**: `Auditoria-Claude` creada en los 9 repos desde `master` (8 repos) y `main` (`mipit-adapter-breb`).

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

## Estado actual (snapshot 2026-05-16)

- ✅ Branches creadas en los 9 repos
- ✅ 12 planes escritos
- ⏳ Implementación pendiente (decisión del usuario qué wave atacar primero)

---

## Notas finales

1. **Wave 1 (P01+P08+P09) puede empezar inmediatamente**. Son foundation sin dependencias.
2. **P02/P03/P04 paralelizables** una vez P01/P09 mergeados.
3. **P07 puede correr en paralelo a P02-P06** mostly — solo depende de adapter metric naming (P02/P03/P04) para los dashboards.
4. **P10/P11/P12 son last** — testean / muestran / documentan lo que P01-P09 construyó.

Si tiempo limitado, **prioridad sustentación**: P01 + P02 + P03 + P04 + P05 + P12. Eso cierra los hallazgos críticos visibles para un panel técnico.
