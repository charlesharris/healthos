# Implementation Plan — Working Index

This directory operationalizes `implementation-plan-v0.1.md` into epics
that Claude Code can execute task-by-task. The handover plan remains
the authority for detail (schemas §10–§53, contracts §164–165,
milestones §133–147); these epic files are the working surface.

## Epic sequence

| Epic | File | Handover source | Milestones | Gate |
|------|------|-----------------|------------|------|
| 001 | `epics/001-foundation-vertical-slice.md` | §134–135, §179 | M0–M1 (+ slivers of M2–M5) | Synthetic BP JSON → Queue row, end to end |
| 002 | `epics/002-operational-spine.md` | §136–139, §180 | M2–M5 | Team can operate a synthetic hypertension population |
| 003 | `epics/003-statistical-core.md` | §140–141, §181 | M6–M7 | Every STAT requirement in scope passes simulation |
| 004 | `epics/004-findings-investigation.md` | §142–143, §182 | M8–M9 | Product becomes Human Observability, not alert management |
| 005 | `epics/005-pilot-integration.md` | §144–145, §183 | M10–M11 | Pilot-ready per handover §187 |

Deferred beyond 005: Cohort Explorer (M12), AI Narrator (M13). Their
schemas must not be blocked, but no code before 005 completes.

## Critical path

```
tenancy → canonical telemetry → measurement/provenance → derived
signals → monitors → Signals → Case correlation → Ops Queue →
Context/Baseline → Comparison → Findings → Quick Review → Investigation
```

Epic 001 deliberately cuts a *thin vertical slice through the whole
path* (one monitor, one case type, no Comparison yet) so the pipeline
shape is proven before breadth is added. Do not "complete the backend"
before the queue renders.

## Parallel tracks (within/across epics 002–004)

- **A — Operational spine:** Signal, Case, Queue, lifecycle, routing
- **B — Evidence/analysis:** Context, Baseline, Comparison, Finding
- **C — Domain pack:** hypertension semantics, monitors, rules, fixtures
- **D — Platform/security:** tenancy hardening, audit, credentials, deploy

Tracks converge at Epic 004 (Milestone 8). When running multiple Claude
Code sessions in parallel, keep each session inside one track to
minimize merge conflicts.

## Session workflow

1. Open the current epic file. Pick the first unchecked task whose
   dependencies are checked.
2. Read the task's Contract References in the governing docs.
3. Write failing specs named after the requirement IDs, implement,
   green, lint.
4. Check the box, append to the epic's Decision Log if anything
   deviated from the handover plan, commit with the task ID + contract
   IDs in the message (e.g. `001-08: normalization provenance [STAT-006]`).
5. One task per commit; small tasks may batch if they share a boundary.

## Rules that override momentum

- Statistical thresholds/gates/evidence rules are governed config:
  never adjust them to satisfy a test (STAT-044). Stop and flag.
- If a task appears to require mutating an append-only or immutable
  artifact, the task is wrong or the design needs review — stop.
- Do-not-build list (handover §152) applies to every epic. No
  microservices, Kafka, ClickHouse, React, patient app, LLM
  correlation, causal inference, workflow engine, risk scores.
- Do-not-ship list (handover §188) is checked at every epic gate.

## Open questions carried into implementation

Resolved-by-default (challenge in Decision Logs if evidence emerges):

- Solid Queue over Sidekiq (§170) — revisit only with measured job lag.
- Row-per-dimension typed ContextValue (§171) — revisit after cohort
  profiling, not before.
- Definitions in versioned code/config, optional read-only
  `definition_registry_entries` mirror later (§168).
- Generic EvidenceSet for drilldown; add explicit strong input tables
  per-artifact only if enforcement gaps appear (§169).
- RLS: schema-ready from first migration; implement + exercise before
  PHI (Epic 005) (§172).

Genuinely open (needs Charles / external review, not Claude Code):

- Numeric false-positive behavior sign-off (§174) — statistical
  reviewer + clinician on simulation output before pilot.
- Domain effect-size thresholds (§175) — fixtures marked NON-CLINICAL
  until reviewed.
- First commercial pilot domain (§173).
- Regulatory counsel review of claims/CDS posture (Epic 005 gate).
