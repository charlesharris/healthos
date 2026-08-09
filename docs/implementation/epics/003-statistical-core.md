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
- [x] 003-02 ContextDefinition interface (§51) + versioning/digest
- [x] 003-03 `contexts` + `context_values` (row-per-dimension typed,
      §52–53) with family metadata columns (semantic/source/derivation)
      (STAT-031)
- [x] 003-04 Context materializer with input EvidenceSet + fingerprint;
      operational vs interactive modes (§54)
- [x] 003-05 Hypertension `blood_pressure_change` ContextDefinition v1

### Baseline (Milestone 6)
- [x] 003-06 BaselineDefinition config model (§56): eligibility,
      minimum/target units + span, exclusions, source compatibility
- [x] 003-07 `baseline_instances` with maturity, completeness,
      source_summary, evidence set (§57)
- [x] 003-08 `personal_recent` baseline v1 with generic minimums
      — materialization (`Baselines::Materialize`, `MaterializeCohort`, job)
      added 2026-08-10 for 002x-02; `baseline_instances` gained semantic_key,
      semantic_version, central_value, dispersion and unit, without which the
      table could not say what it was a baseline of
      (10 usable days / 14-day span; targets 21/28) (STAT-016/017)
- [x] 003-09 Version tuple + fingerprint capture on all artifacts (§80)
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

### 2026-08-09 — 003-06/003-08 BaselineDefinition and personal_recent

**SC §20's "there is no universal `normal`" is the whole reason this is a
class.** A baseline is a stated, defensible answer to "what counts as
this subject's usual", and different answers are legitimately different.
`Baselines::Definition` carries a key, version and digest so a Comparison
can say which question it asked; the eight baseline types SC §20 names
are all listed, so adding one is visibly joining a known set rather than
inventing a category.

**The definition reports, the gate decides.** `Definition::Result` gives
`maturity`, `completeness`, `usable_units`, `calendar_span_days`,
`missing_by_state` and `source_summary`, and reaches no conclusion about
whether any of it is good enough. Keeping the judgement out of the
materializer is what stops an evidence gate hiding somewhere nobody
reviews it (STAT-044).

**Thresholds are digested.** They are read from governed config, but they
also go into `parameters` and therefore into the digest — the numbers
decide what the baseline IS, and a definition that quietly started
accepting five days instead of ten would otherwise keep its identity.

**`Telemetry::Windows` promoted out of the hypertension pack.** The
day-aligned half-open window arithmetic was written for the monitors, but
nothing in it is disease-shaped and the baseline needs exactly the same
boundaries. Two copies would eventually disagree about a boundary reading,
and that disagreement surfaces as an unexplainable bias rather than as a
failure. `Hypertension::MonitorWindows` is now a shim so the monitors keep
reading the way they did.

**Two spec expectations were wrong, and the rule was right.** Twelve
CONSECUTIVE usable days looked like it should be `partial` and came out
`immature`: twelve days span twelve calendar days, short of STAT-016's
14-day minimum span. Twenty-five consecutive days came out `partial`
rather than `mature` for the same reason against the 28-day target. Both
fixtures were rewritten to spread the days out. This is precisely the
case CLAUDE.md rule 4 covers — the fix is the fixture, never the
threshold — and it is worth recording that the failure looked at first
like an off-by-one in `BaselineMaturity`.



### 2026-08-09 — 003-02/04/05/09 Context materialization

**The Context emits measurement behaviour beside biology, deliberately.**
A definition that produced only blood pressure would make STAT-007's
instrumentation-before-biology ordering impossible — the comparison
engine would have nothing to order against. Completeness and
source-change are materialized as first-class dimensions (STAT-003), not
attached as annotations.

**A dimension with nothing usable is EMITTED, not omitted**, carrying no
value. That is what lets a Comparison distinguish "we looked and found
nothing usable" from "we never looked" — omitting it would collapse the
two, and the second is not a gap while the first is.

**The CHECK constraint caught me putting metadata in a value column.**
`{"source_count" => 0}` on an `unknown` dimension tripped the
value-representation constraint. Relaxing the CHECK to admit `value_json`
would have been the easy fix and the wrong one: it would let a real value
be smuggled onto a missing dimension under a different column name.
Added a `details` jsonb column instead — always permitted, never a value
— so STAT-042's structured reason codes have a home and the invariant
stays absolute.

**A knowable zero is not an unknowable ratio.** A subject who was
expected to measure daily and measured nothing has a genuine 0%
completeness, recorded as `observed`. Only a dimension with no declared
expectation model is `unknown`. A gate that confused the two would read
"we could not tell" as "they barely measured" — my own first spec made
exactly that mistake, asserting nil where 0 was correct.

**Families are read from the semantic registry, never restated.** If a
definition declared its own, the two could drift and STAT-033's
correlated-family suppression would be reasoning about families that no
longer match the data.

**The definition computes but does not judge**, enforced by a spec that
greps it for `evidence_level|WEAK|MODERATE|STRONG|suppress`. A gate
hidden in a materializer is a governed threshold nobody reviews.

**The version tuple includes the statistical config digest** (HO §80),
so a threshold change is visible in the artifact rather than only in git
history — and stored ON the artifact rather than joined at read time,
since a join would resolve to today's versions and quietly rewrite what
the artifact meant.

### 2026-08-09 — 003-03/007 schema, and governed statistical config

**Every Statistical Contract threshold now lives in
`config/statistics/*.yml`**, read through `Analysis::StatisticalConfig`,
with the contract's own wording quoted beside each number so a reviewer
can check the transcription without opening SC. Nothing else in the
codebase may hard-code one, and a spec greps the maturity resolver to
prove it does not.

The specs assert the config against **the contract's numbers**, not
against whatever the file happens to contain. Editing a governed
threshold therefore breaks the suite — which is the intent. STAT-044
wants a version bump and human review, not a quiet edit that a green
suite would bless.

**A spec caught a shallow freeze.** `Hash#freeze` leaves nested hashes
mutable, so any caller could have reached in and changed a threshold at
runtime. A threshold mutable in-process is not governed, whatever the
file says. Now deep-frozen.

**Maturity takes the weaker of units and span** (SC §21). Ten readings
crammed into three days is not a fortnight's baseline, and SC §21 stores
both precisely so a burst of measurement cannot pass for sustained
history.

**An affected window has no maturity.** It either clears SC §23's
minimum or the comparison is refused for insufficient longitudinal
evidence (STAT-018) — giving it a maturity label would imply a spectrum
where the contract has a threshold. A spec asserts the method does not
exist.

**The value-representation CHECK is repeated on `context_values`.** A
dimension that could not be computed carries no value, so STAT-002 holds
at the analytical layer rather than being assumed to survive from the
telemetry layer.

**Difference-family metadata sits on every context value** (SC §49–50),
so STAT-033's correlated-family suppression is a filter rather than a
join, and adding a family later needs no schema change.

`config_digest` is exposed for inclusion in artifact version tuples
(HO §80), so an artifact records which governed configuration produced
it — a threshold change becomes visible in the artifact, not only in git
history.

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
