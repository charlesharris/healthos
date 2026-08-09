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
- [x] 003-01 `spec/support/synthetic_health/`: SyntheticSubject,
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

### 2026-08-09 — 003-01 simulation harness

Built ahead of the engine, as the epic requires ("build this before the
engine; it is the engine's acceptance instrument"). 43 examples.
Delegated to a sub-agent; reviewed and verified before commit.

**Ground truth is structural, not asserted.** Generation is layered —
biology, then instrumentation, then missingness — and deterministic
components consume zero randomness. So at a given seed,
`latent(level_shift) - latent(null)` equals the injected magnitude
*exactly* at every index, with no tolerance, and the source-switch and
missingness families have `latent_series` byte-identical to null. "The
instrument changed, the subject did not" is a property of the generator
rather than a hope about it. That is what makes the harness usable as an
acceptance instrument: a failure means the engine is wrong, not that the
fixture drifted.

**Determinism is portable, not merely repeatable.** Stream seeds derive
via FNV-1a rather than `String#hash`, which is salted per process and
would have looked deterministic locally while breaking in CI. No Float
and no `Math.*` anywhere — noise is Irwin–Hall over integer draws and
the seasonal wave is a twelve-point BigDecimal table. Verified
byte-identical across separate processes.

**No thresholds encoded.** `Scenario` deliberately exposes no
`evidence_level` or `significant?`, and a spec asserts their absence.
Truth reports counts, denominators, completeness ratios and source mixes
descriptively; judging them is the engine's job. Six of the twelve
families inject no biological effect at all, since STAT-036 makes the
negative result the thing most worth testing.

**DST is deliberately not modelled.** Subjects carry a fixed integer UTC
offset so the harness stays Rails-free. Defaults are negative-offset so
the evening slot lands on the *next* UTC day — an engine that groups by
UTC date instead of subject-local date fails loudly (HO §121).

**Contract ambiguity — RESOLVED 2026-08-09 (Charles).**
SC §14 defines completeness over "expected opportunities" but does not
say where `invalid_measurement`, `excluded_by_rule` and `unknown` sit.
This is a *statistical* decision, not an implementation detail: it moves
comparisons across STAT-012's 40/60/80 bands and therefore decides
whether a Difference can reach MODERATE or STRONG.

Resolved as:

- `invalid_measurement` — **counts against** completeness. The protocol
  wanted a usable reading and did not get one; that an attempt happened
  does not make the day measured.
- `unknown` — **counts against**. Assuming the opportunity was met would
  inflate completeness on the strength of ignorance.
- `excluded_by_rule` — **removed from the denominator**. We chose to
  discard that reading, and charging the subject's completeness for our
  own exclusion double-counts it: once by dropping the value, again by
  making the day look missed.

Implemented as the single constant
`Measurement::Completeness::DENOMINATOR_EXEMPT_STATES`, with a spec
asserting its contents — changing it changes every completeness ratio in
the system, so STAT-044 requires it be one reviewable line rather than
logic scattered through a calculation. A day whose readings are *all*
excluded is exempt; a day that also produced a usable reading is not.
When every expected day is excluded the result is indeterminate rather
than zero, because a ratio over an empty denominator is not a low score
— it is no measurement at all.

The harness's own denominator note is now superseded by this.

**Process note:** a `git add -A` on the main thread swept 19 of these
files into commit `663235e` ("001-11: case correlation"), whose message
does not mention them. History was not rewritten, since that commit is
pushed and CI-green. Subsequent commits use targeted paths while a
sub-agent is writing.
