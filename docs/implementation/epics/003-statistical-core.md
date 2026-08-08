# Epic 003 — Statistical Core (Context → Baseline → Comparison)

> **ID:** 003-statistical-core
> **Status:** Blocked by 002 (measurement tasks 002-01..06 specifically)
> **Priority:** P0
> **Handover source:** §140–141 (Milestones 6–7), §181
> **Track:** B

⚠️ **Governance:** every threshold in this epic comes from the
Statistical Contract. Claude Code must not tune any gate, threshold,
or evidence rule to make a spec pass — that requires a version bump
and human review (STAT-044). Fixture effect thresholds are
NON-CLINICAL and labeled as such (§175).

## Goal

Reproducible analysis inputs (Context, Baseline) and the evidence-gated
comparison engine that turns them into Differences — including the
negative result as a first-class successful outcome.

## Exit Criteria (handover §140–141)

- A Context can be reproduced from canonical data; exact evidence
  inputs inspectable; version tuple + fingerprint persisted
- Baselines expose maturity (immature/partial/mature)
- Late data marks Case analysis stale and generates NEW artifacts;
  nothing historical mutates (STAT-041)
- No individual p-value ranking anywhere (STAT-019)
- Denominators always persisted (STAT-021); <40% completeness
  suppresses biology (STAT-012); source switch suppression works
  (STAT-008/009); small counts → insufficient_evidence
- "No reliable distinguishing pattern found" renders and is tested
  (STAT-036)
- **Gate:** synthetic statistical-contract scenarios pass (§100–101)

## Contract References

STAT-001, 004–009, 012–030, 036–042; S2C-018/019.

## Tasks

### Simulation harness FIRST
- [ ] 003-01 `spec/support/synthetic_health/`: SyntheticSubject,
      TimelineBuilder, MissingnessPattern, SourceSwitchScenario,
      TrajectoryScenario, CorrelatedDimensionsScenario — deterministic
      seeds (§100). Scenario families: null, level shift, trend,
      source-switch artifact, missingness artifact, sparse outliers,
      autocorrelation, phase drift, correlated families.
      _Build this before the engine; it is the engine's acceptance
      instrument._

### Context (Milestone 6)
- [ ] 003-02 ContextDefinition interface (§51) + versioning/digest
- [ ] 003-03 `contexts` + `context_values` (row-per-dimension typed,
      §52–53) with family metadata columns (semantic/source/derivation)
      (STAT-031)
- [ ] 003-04 Context materializer with input EvidenceSet + fingerprint;
      operational vs interactive modes (§54)
- [ ] 003-05 Hypertension `blood_pressure_change` ContextDefinition v1

### Baseline (Milestone 6)
- [ ] 003-06 BaselineDefinition config model (§56): eligibility,
      minimum/target units + span, exclusions, source compatibility
- [ ] 003-07 `baseline_instances` with maturity, completeness,
      source_summary, evidence set (§57)
- [ ] 003-08 `personal_recent` baseline v1 with generic minimums
      (10 usable days / 14-day span; targets 21/28) (STAT-016/017)
- [ ] 003-09 Version tuple + fingerprint capture on all artifacts (§80)
- [ ] 003-10 Late-data invalidation: overlap detection →
      analysis_status=stale → CaseEvent → coordinator re-run;
      over-invalidation acceptable (§55); saved artifacts untouched

### Comparison engine (Milestone 7)
- [ ] 003-11 `comparisons` with statuses completed_with_findings /
      completed_no_reliable_findings / insufficient_evidence / invalid
      / failed — never conflated (§59; S2C-019)
- [ ] 003-12 EvidenceGate (§61): "can we say anything?" separate from
      effect calculation; structured reason codes (§83, STAT-042)
- [ ] 003-13 Gate pipeline order per §60: semantic compat → source
      compat → baseline eligibility → unit minimums → span →
      completeness → differential missingness → variance → mode rules
- [ ] 003-14 Completeness gates (STAT-012) + differential-missingness
      ≥25pp Measurement Behavior Difference (STAT-013)
- [ ] 003-15 Source-change gates: >30% cap WEAK, >50% suppress +
      instrumentation surface (STAT-008/009)
- [ ] 003-16 Methods: RobustContinuousShift (median/MAD; omit
      standardized value when MAD unstable, §64),
      BinaryProportionShift (counts + denominators; no headline ratio
      when either side <3 positives, §65, STAT-021/022),
      TrajectoryDeviation, SingleEpisodeDeviation
- [ ] 003-17 Explicit unit-of-analysis on every Comparison; raw count
      vs usable units vs analytical units all distinguishable
      (§66, STAT-004/005)
- [ ] 003-18 Sensitivity/stability checks (alternate window, alternate
      baseline, leave-one-out); stable/mixed/unstable/not_testable;
      unstable cannot be STRONG (§71, STAT-026)
- [ ] 003-19 `differences` with effect, evidence_level,
      evidence_reasons, stability, families, rank (§68)
- [ ] 003-20 Evidence levels per §70 rules; lexicographic ranking, no
      magic score (§72, STAT-024/025)
- [ ] 003-21 Negative result: all-below-MODERATE → comparison status
      completed_no_reliable_findings → "No reliable distinguishing
      pattern found" (dedicated specs, §78, STAT-036)
- [ ] 003-22 Analysis coordinator `Analysis::BuildCaseAnalysis` with
      per-stage retry, side-built artifacts, transactional pointer
      publication + CaseEvent (§98–99)
- [ ] 003-23 Failure handling: failed analysis leaves Case visible with
      Retry (§97, S2C-019)

### Statistical acceptance (gate)
- [ ] 003-24 §101 behaviors as specs: null → no reliable Finding-level
      output; source switch → instrumentation outranks biology
      (assert at Difference level now, Finding level in 004);
      missingness collapse → measurement Difference surfaces + biology
      limited; small count → Case exists, insufficient_evidence; late
      data → live changes, saved pinned
- [ ] 003-25 §121 regression matrix: empty data, zero variance,
      extremes, duplicates, timezone boundaries, small denominators,
      sensitivity reversal
- [ ] 003-26 False-positive inspection run (§102): execute defaults
      against null scenarios, write results to
      `docs/reviews/` for human statistical review — do NOT self-tune

## Out of Scope

FindingDefinitions/aggregation (Epic 004), cohort methods + BH FDR
(deferred M12; schema fields may exist), Workbench UI, alternate
baseline types beyond personal_recent (phase/cycle/expected-trajectory
land when a domain needs them — keep BaselineDefinition general).

## Decision Log

_(append here)_
