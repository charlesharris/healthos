# Human Observability Platform
## Statistical Contract — v0.1
### Rules for Trustworthy Difference Detection and Evidence Ranking

**Status:** Pre-implementation statistical design  
**Scope:** Provider-facing longitudinal health observability  
**Primary consumers:** Comparison Engine, Finding Generator, Ops Queue, Investigation Workbench  
**Reference implementation:** Rails + PostgreSQL  
**Reference domain for examples:** Hypertension remote monitoring  
**Important:** This is a product/statistical engineering contract, not a validated clinical algorithm or regulatory statistical analysis plan.

---

# 1. Purpose

The Human Observability Platform exists to help provider teams answer:

> **When something changed, what was different, and what evidence supports that conclusion?**

That promise is easy to violate.

Longitudinal health data is:

- sparse,
- irregular,
- autocorrelated,
- nonstationary,
- behaviorally missing,
- instrument-dependent,
- high-dimensional,
- and frequently small-n at the individual-patient level.

A naive "compare everything and rank the biggest percentage differences" engine will reliably produce convincing nonsense.

This document defines the statistical contract that prevents that.

The platform must prefer:

> **No reliable distinguishing pattern found.**

over a statistically impressive but poorly supported explanation.

---

# 2. What This Contract Covers

This contract governs:

```text
Baseline eligibility
Comparison eligibility
Unit of analysis
Missingness
Measurement behavior
Data completeness
Small-n handling
Autocorrelation
Effect estimation
Multiple comparisons
Difference eligibility
Difference ranking
Finding clustering
Evidence-strength labels
Sensitivity checks
Cohort comparisons
Saved-investigation reproducibility
```

It does not define:

```text
clinical treatment thresholds
clinical risk scores
causal inference
diagnostic algorithms
treatment recommendations
validated outcome prediction
```

Those require separate domain, clinical, validation, and regulatory work.

---

# 3. Foundational Statistical Principles

## 3.1 Difference is not cause

The system may conclude:

> "Sleep duration was lower during the affected period."

It may not infer:

> "Reduced sleep caused the trajectory change."

unless a separately validated causal model explicitly supports that claim.

---

## 3.2 Absence of measurement is not measurement of absence

If nutrition entries disappear:

```text
nutrition observations = missing
```

does **not** mean:

```text
nutrition intake = zero
```

Missing data must never be silently converted into a biological or behavioral value.

---

## 3.3 Measurement behavior is itself data

The platform must model:

```text
measurement frequency
logging frequency
device reporting
source changes
manual/automatic collection
data gaps
```

as first-class dimensions.

---

## 3.4 Repeated observations are not automatically independent

Twenty-eight daily measurements do not imply:

```text
n = 28 independent observations
```

The Comparison Engine must operate on an explicitly declared analytical unit and must not use naive independence assumptions to inflate confidence.

---

## 3.5 The system must know when not to rank

A Difference may be mathematically computable but statistically unfit for provider-facing ranking.

Calculation and eligibility are separate concepts.

---

## 3.6 Denominators are mandatory

Never display:

```text
18% vs 4%
```

without the underlying evidence:

```text
3 of 17 observed units
vs
1 of 25 observed units
```

---

## 3.7 Clinical importance and statistical evidence are separate

A tiny but well-supported difference may have strong statistical evidence and low clinical relevance.

A medically important threshold event may require immediate review despite weak longitudinal evidence.

Therefore:

```text
Review Priority != Evidence Strength
```

The statistical engine does not assign clinical urgency.

---

# 4. Analysis Modes

Every Comparison declares one analysis mode.

The modes have different rules.

## 4.1 Within-subject window comparison

Example:

```text
A. Smith
Aug 1–Aug 14
vs
Jul 1–Jul 28
```

Used for:

```text
trajectory changes
symptom periods
measurement changes
recovery deviations
```

---

## 4.2 Within-subject episode comparison

Example:

```text
current treatment cycle
vs
previous treatment cycles
```

or:

```text
current post-op phase
vs
previous comparable recovery intervals
```

---

## 4.3 Single-episode contextual deviation

Example:

```text
this one treatment cycle
vs
distribution of prior cycles
```

The affected set contains only one episode.

This mode is descriptive.

It does not support ordinary hypothesis testing.

---

## 4.4 Cohort comparison

Example:

```text
patients with changed BP trajectory
vs
patients without changed BP trajectory
```

The unit of analysis is normally the subject, not individual measurements.

---

## 4.5 Matched-cohort comparison

Example:

```text
post-op patients with delayed recovery
vs
phase/procedure-matched patients without delay
```

Matching rules must be explicit and versioned.

---

# 5. Unit of Analysis

Every Comparison must store:

```text
analysis_mode
unit_of_analysis
```

Possible units:

```text
subject
day
week
episode
treatment_cycle
encounter
hospitalization
```

The domain pack defines valid units for each Context and ComparisonDefinition.

---

# 6. Raw Sample Count vs Analytical Unit Count

The UI and stored result must distinguish:

```text
raw observations
usable observations
analytical units
```

Example:

```text
42 BP readings
→
12 valid measurement days
→
12 analytical units
```

The system must never present `42` as the sample size of a daily comparison.

---

# 7. Within-Unit Aggregation

When several observations occur within one analytical unit, the domain pack defines the aggregation.

Examples:

```text
blood pressure/day:
domain-defined valid daily summary

steps/day:
daily total

sleep/day:
primary sleep interval

weight/day:
latest valid device measurement or domain rule

glucose/day:
domain-specific summary metrics
```

Aggregation rules are versioned.

The statistical engine does not invent aggregation semantics.

---

# 8. Comparison Eligibility Pipeline

A candidate Comparison passes through gates in this order:

```text
1. semantic compatibility
2. source/instrument compatibility
3. baseline eligibility
4. usable-unit minimums
5. calendar-coverage minimums
6. completeness checks
7. missingness-difference checks
8. variance/information checks
9. analysis-mode checks
10. effect calculation
11. sensitivity checks
12. Difference eligibility
13. Finding generation
```

Failure at an early gate may prevent downstream ranking.

---

# 9. Semantic Compatibility

Affected and baseline sets must represent comparable concepts.

Examples of invalid comparisons:

```text
systolic BP vs diastolic BP
device-measured weight vs self-reported weight
unless explicitly allowed

different measurement protocols
without protocol-aware transformation

incompatible units
without defined conversion
```

The Semantic Registry determines compatibility.

---

# 10. Source and Instrument Compatibility

Source changes are never silently normalized away.

Before interpreting a health-value shift, the engine checks:

```text
source provider
device
device model
recording method
measurement protocol
integration version
```

If one changed materially, the engine may:

1. create a Measurement/Instrumentation Difference,
2. downgrade biological Difference evidence,
3. suppress the biological Difference entirely,
4. or permit comparison if the domain pack declares the sources equivalent.

---

# 11. Default Source-Change Rule

If:

```text
>30% of affected analytical units
come from a materially different source/method
than the baseline set
```

and equivalence is not declared:

```text
biological Difference evidence cannot exceed WEAK
```

If:

```text
>50% of affected units
come from a materially different source/method
```

then:

```text
biological Difference ranking is suppressed
```

and the instrumentation change itself becomes eligible as a Finding.

These percentages are configurable contract defaults, not clinical constants.

---

# 12. Missingness Taxonomy

For statistical purposes, the platform distinguishes:

```text
not_expected
observed
expected_but_missing
source_unavailable
device_not_reporting
manual_entry_absent
invalid_measurement
excluded_by_rule
late_not_yet_arrived
unknown
```

Do not collapse all missingness into `NULL`.

---

# 13. Expected Measurement Opportunity

Completeness requires an expected denominator.

Examples:

```text
BP protocol expects:
5 measurement days/week

CGM:
near-continuous expected coverage

lab:
not expected daily

patient-reported symptom:
event-driven, no daily completeness denominator unless protocol says otherwise
```

Every dimension participating in completeness-sensitive analysis declares an expectation model.

---

# 14. Completeness

For a defined window:

```text
completeness =
usable expected opportunities /
total expected opportunities
```

Example:

```text
expected BP days: 10
usable BP days:    7

completeness = 70%
```

The UI should expose both the ratio and denominator.

---

# 15. Default Completeness Gates

Unless overridden by a domain definition:

```text
< 40% completeness
→ Difference suppressed

40–59%
→ eligible only for WEAK evidence

60–79%
→ evidence can reach MODERATE

>= 80%
→ evidence can reach STRONG
```

These gates apply independently to affected and baseline sets.

The weaker side controls the maximum evidence level.

---

# 16. Differential Missingness

Even when both windows have usable data, a large change in measurement behavior may invalidate interpretation.

Define:

```text
completeness_delta =
affected completeness - baseline completeness
```

Default rule:

```text
absolute completeness delta >= 25 percentage points
```

creates an eligible:

```text
Measurement Behavior Changed
```

Difference.

For a manually entered or behavior-dependent signal, the corresponding biological/behavioral value Difference is capped at WEAK unless a domain pack explicitly defines a missingness-aware method.

---

# 17. Missingness Is Never Zero-Imputed

Forbidden:

```text
no meal entry
→ 0 calories

no exercise event
→ 0 exercise

no symptom report
→ symptom severity 0
```

Allowed only where the data contract itself guarantees that absence semantically means zero.

Example:

```text
connected step counter reports complete daily total = 0
```

is a recorded zero, not missingness.

---

# 18. Measurement-Behavior Dimensions

The Context Engine should make at least these dimensions available:

```text
measurement.frequency
measurement.frequency_delta
measurement.days_since_last
measurement.completeness
measurement.completeness_delta
measurement.manual_entry_frequency
measurement.device_reporting_frequency
measurement.source_changed
measurement.recording_method_changed
```

These can become Findings independently of health-value Differences.

---

# 19. Baseline Requirements

Every Comparison must reference a versioned BaselineDefinition.

A BaselineDefinition states:

```text
baseline type
eligible time range
phase/cycle alignment
exclusion rules
source compatibility rules
required units
target units
aggregation
expected trajectory logic if any
```

---

# 20. Baseline Types

Supported conceptual types:

```text
personal_recent
personal_historical
phase_matched
cycle_matched
expected_trajectory
cohort_prior
matched_cohort
pre_intervention
```

The domain pack declares the default.

There is no universal "normal."

---

# 21. Baseline Maturity

A baseline stores:

```text
usable_units
calendar_span
completeness
maturity
```

Generic maturity states:

```text
immature
partial
mature
```

Each BaselineDefinition defines:

```text
minimum_units
target_units
minimum_span
target_span
```

Rule:

```text
below minimum
→ immature

minimum <= units < target
→ partial

target met
→ mature
```

---

# 22. Generic v0.1 Default Baseline Thresholds

For day-based longitudinal comparisons, when a domain has not yet specified better values:

```text
minimum usable baseline days: 10
target usable baseline days: 21

minimum baseline calendar span: 14 days
target baseline calendar span: 28 days
```

These are engineering defaults only.

A domain pack should replace them as soon as a clinically meaningful cadence is known.

---

# 23. Affected-Window Minimums

Generic day-based default:

```text
minimum usable affected days: 5
minimum affected calendar span: 7 days
```

If the monitor fires faster for protocol reasons, the Case may still exist, but Difference Explorer may return:

> **Insufficient longitudinal evidence.**

This distinction is intentional.

---

# 24. Single-Episode Comparisons

A current episode can be compared to prior episodes even though:

```text
affected n = 1 episode
```

But this is treated as:

```text
contextual deviation
```

not a two-sample statistical test.

Generic requirement:

```text
minimum prior comparable episodes: 3
```

Evidence maximum:

```text
3–4 prior episodes → WEAK
5–7 prior episodes → MODERATE
8+ prior episodes  → potentially STRONG
```

Strong still requires quality and stability gates.

---

# 25. Cohort Minimums

For provider-facing Difference ranking:

```text
minimum affected subjects: 20
minimum baseline subjects: 20
```

Below this:

```text
descriptive aggregate display may be allowed
subject to privacy policy

Difference ranking:
suppressed
```

A domain pack or validated statistical plan may override this.

Do not reduce the threshold simply to make a demo produce results.

---

# 26. Small-n Philosophy

For individual-patient exploration, v0.1 is primarily:

```text
descriptive + robust + evidence-gated
```

not:

```text
frequentist significance testing
```

The UI should not show a p-value for:

```text
7 days vs 14 days
```

and imply a clinical discovery.

---

# 27. Autocorrelation Contract

Repeated measurements close in time are correlated.

v0.1 addresses this by:

1. aggregating raw measurements into domain-defined analytical units,
2. requiring minimum calendar span in addition to unit count,
3. avoiding naive p-values for single-subject comparisons,
4. using trajectory/episode summaries rather than treating every sample as independent,
5. applying stability checks across neighboring windows.

More sophisticated time-series models may be introduced later.

---

# 28. No P-Value Ranking for Individual Cases

For these modes:

```text
within-subject window
within-subject episode
single-episode contextual deviation
```

v0.1 MUST NOT rank Differences by p-value.

The provider-facing output centers on:

```text
effect magnitude
absolute values
denominators
data completeness
baseline maturity
source compatibility
stability
evidence strength
```

This is a deliberate product rule.

---

# 29. Continuous Difference Estimation

For general continuous dimensions, the default descriptive comparison is:

```text
affected median
baseline median
absolute difference
relative difference where meaningful
```

When a scale-normalized effect is useful:

```text
robust standardized difference =
(affected median - baseline median) /
baseline robust scale
```

Preferred robust scale:

```text
MAD
```

when enough baseline variation exists.

If scale is zero or too poorly estimated, omit the standardized value.

---

# 30. Mean-Based Domain Metrics

Some health metrics have domain-established summary semantics that use a mean.

The domain pack may define:

```text
mean
weighted mean
time-weighted mean
percentage in range
slope
variability metric
```

The statistical engine follows the domain's canonical derived signal.

It does not force medians universally.

---

# 31. Binary / Categorical Difference Estimation

For binary dimensions, always record:

```text
affected successes
affected denominator
baseline successes
baseline denominator

absolute proportion difference
```

Relative ratio may also be displayed when mathematically stable.

Never show a dramatic relative percentage without the absolute counts.

Example:

```text
3/17 vs 0/28
```

is preferred over:

```text
"1700% higher"
```

---

# 32. Rare Events

For very small counts:

```text
0
1
2
```

relative ratios are unstable.

Default UI rule:

```text
if either group has < 3 positive events,
do not headline a relative ratio
```

Show counts and absolute proportion difference instead.

---

# 33. Trajectory Differences

When a domain defines a trajectory signal, compare:

```text
slope
velocity
level
variability
or deviation from expected trajectory
```

using the domain's versioned DerivedSignal.

Do not fit arbitrary regression models ad hoc in the UI.

---

# 34. Effect Magnitude Classes

Every comparable dimension maps its effect into:

```text
small
moderate
large
```

The thresholds belong to the semantic/domain definition.

Example concept:

```yaml
dimension: blood_pressure.systolic_mean

effect_thresholds:
  moderate: DOMAIN_DEFINED
  large: DOMAIN_DEFINED
```

The platform core must not hard-code medical thresholds.

For generic nonclinical dimensions such as measurement completeness, platform defaults are allowed.

---

# 35. Statistical Ranking Philosophy

v0.1 does not generate one opaque numerical "importance score."

Differences are ordered lexicographically by:

```text
1. eligibility
2. evidence strength
3. effect magnitude class
4. stability
5. data quality
6. domain-defined relevance
```

This keeps ranking explainable.

---

# 36. Internal Rank Metadata

An internal ordinal representation is acceptable:

```text
evidence:
insufficient < weak < moderate < strong

effect:
small < moderate < large

stability:
unstable < mixed < stable
```

But the application must not expose a pseudo-scientific:

```text
Finding Score: 92.7
```

unless such a score is separately validated.

---

# 37. Evidence Strength

Evidence strength describes:

> **How strongly the available data supports that this dimension differs between the affected and baseline sets under the declared comparison.**

It does not describe:

```text
clinical severity
causality
treatment importance
```

Levels:

```text
INSUFFICIENT
WEAK
MODERATE
STRONG
```

---

# 38. INSUFFICIENT Evidence

Any hard failure yields INSUFFICIENT.

Examples:

```text
baseline below minimum
affected set below minimum
completeness < 40%
semantic incompatibility
material source change prevents interpretation
no variation/information
privacy/statistical cohort minimum not met
comparison cannot be reproduced
```

INSUFFICIENT Differences are not ranked as biological findings.

They may still produce a Measurement/Data Quality Finding.

---

# 39. WEAK Evidence

Eligible but limited.

Typical reasons:

```text
partial baseline
40–59% completeness
small usable sample
effect unstable across sensitivity windows
important missingness difference
source compatibility uncertainty
single episode with only 3–4 prior episodes
```

Weak findings can be shown inside an Investigation.

If all candidate Findings are WEAK:

the Ops Queue should generally display:

> **No reliable distinguishing pattern found.**

rather than promoting one weak finding as "Top Finding."

---

# 40. MODERATE Evidence

Default requirements:

```text
comparison eligibility passes
affected and baseline minimums pass
>=60% completeness on both sides
baseline at least partial
effect magnitude >= domain moderate threshold
no disqualifying source change
sensitivity check does not reverse direction
```

For single-episode comparison:

```text
>=5 prior comparable episodes
```

---

# 41. STRONG Evidence

Strong evidence is intentionally difficult to reach.

Generic requirements:

```text
all MODERATE requirements
>=80% completeness on both sides
mature baseline
effect magnitude >= domain moderate threshold
stable direction under sensitivity analysis
no material unresolved instrumentation change
no major differential missingness
adequate domain-defined observation count
```

A domain can require additional conditions.

Strong does **not** mean causal.

---

# 42. Sensitivity Check

Every MODERATE-or-higher within-subject Difference should run a simple predefined sensitivity check when data permits.

Examples:

```text
alternate nearby window
alternate reasonable baseline window
leave-one-unit-out check
alternate robust aggregation
```

The sensitivity method belongs to the ComparisonDefinition.

---

# 43. Stability Labels

Possible result:

```text
stable
mixed
unstable
not_testable
```

Generic rule:

```text
direction preserved and effect remains meaningful
→ stable

direction preserved but effect attenuates materially
→ mixed

direction reverses
→ unstable
```

An unstable Difference cannot receive STRONG evidence.

---

# 44. Multiple Comparisons: Core Rule

The Difference Explorer may examine dozens or hundreds of dimensions.

v0.1 therefore makes a crucial distinction:

## Individual-provider investigation

Exploratory ranking without formal p-value claims.

## Cohort statistical analysis

May use formal hypothesis testing and false-discovery control when defined by the ComparisonMethod.

---

# 45. Individual Investigations and Multiplicity

For individual Cases, multiplicity is controlled operationally through:

```text
minimum evidence gates
effect magnitude thresholds
data-quality gates
missingness gates
domain-defined candidate dimensions
sensitivity checks
Difference Clustering
suppression of redundant derived dimensions
```

The system does not imply:

> "This is statistically significant at p < .05."

---

# 46. Cohort FDR

If cohort mode performs a family of formal hypothesis tests, the family must be declared.

Example:

```text
Comparison:
hypertension trajectory-changed cohort

Test family:
42 eligible Context dimensions
```

Default formal multiplicity correction:

```text
Benjamini-Hochberg false discovery rate
```

unless a validated domain method specifies otherwise.

Store:

```text
raw p-value
adjusted q-value
family identifier
number of tests
method/version
```

---

# 47. Cohort Significance Is Not Enough

Even in cohort mode, a dimension is not surfaced merely because:

```text
q < threshold
```

It must also pass:

```text
minimum effect magnitude
minimum denominators
data-quality requirements
```

Large cohorts can make trivial effects statistically significant.

---

# 48. Default Cohort FDR Threshold

For exploratory provider analytics:

```text
q <= 0.10
```

may be used as an **internal eligibility default**, paired with minimum effect size.

This threshold must be:

- configurable by ComparisonDefinition,
- shown in analysis metadata,
- and not marketed as a clinical decision threshold.

For validated clinical algorithms, a separate statistical plan is required.

---

# 49. Correlated Dimensions

Dimensions are often redundant.

Example:

```text
steps ↓
active minutes ↓
exercise sessions ↓
```

may represent one activity pattern.

Likewise:

```text
systolic mean ↑
high-BP day count ↑
7-day systolic trend ↑
```

may be multiple summaries derived from the same BP records.

Presenting them as three discoveries exaggerates evidence.

---

# 50. Difference Families

Every dimension should optionally declare:

```text
semantic_family
source_family
derivation_family
```

Example:

```text
dimension:
activity.steps_delta

semantic_family:
activity

source_family:
wearable_activity

derivation_family:
daily_activity_summary
```

This metadata supports clustering and redundancy handling.

---

# 51. Finding / Difference Cluster Contract

A Finding is:

> **A provider-facing group of one or more related Differences that describes one coherent pattern.**

Examples:

```text
Measurement behavior changed
Activity/recovery pattern changed
Instrumentation changed
Treatment-event pattern changed
Sleep pattern changed
```

---

# 52. v0.1 Finding Generation

Use **domain-authored semantic grouping first**.

Do not begin with machine-learned clustering.

Process:

```text
eligible Differences
   ↓
group by FindingDefinition
   ↓
remove redundant derivatives
   ↓
evaluate support
   ↓
assign Finding evidence
   ↓
rank Findings
```

This is reproducible and understandable.

---

# 53. FindingDefinition

Conceptual structure:

```yaml
key: activity_recovery_changed

candidate_dimensions:
  - activity.steps_delta
  - activity.active_minutes_delta
  - activity.exercise_frequency_delta
  - sleep.duration_delta

minimum_support:
  moderate_differences: 2

independent_source_bonus: true
```

Domain packs own health-domain FindingDefinitions.

The platform owns generic Findings such as:

```text
measurement behavior changed
instrumentation changed
data quality degraded
```

---

# 54. Redundant Differences

Two Differences derived from substantially the same raw evidence cannot independently boost Finding strength.

Example:

```text
systolic_mean_delta
systolic_7d_average_delta
```

derived from the same readings are not two independent confirmations.

Use `derivation_family` and input lineage to identify redundancy.

---

# 55. Finding Evidence Aggregation

Default v0.1 rule:

1. Start with the strongest eligible component Difference.
2. Supporting Differences from the same derivation/source family do not increase evidence.
3. A second supportive Difference from a meaningfully different evidence family may increase the Finding by **at most one evidence level**.
4. A Finding can never exceed STRONG.
5. Contradictory component Differences may reduce evidence or mark the Finding `mixed`.
6. No cluster can transform several WEAK correlated Differences into STRONG evidence.

---

# 56. Example

Suppose:

```text
steps ↓               MODERATE
active minutes ↓      MODERATE
exercise sessions ↓   MODERATE
```

all from the same wearable/activity data.

Finding:

```text
Activity pattern changed
Evidence: MODERATE
```

not STRONG.

If additionally:

```text
physical therapy attendance ↓
MODERATE
```

from a separate care-workflow source:

```text
Activity/rehab pattern changed
Evidence may become STRONG
```

subject to other gates.

---

# 57. Measurement Findings Precede Biological Findings

When a material instrumentation or measurement-behavior Finding exists, it is evaluated before biological Findings.

Possible output:

```text
1. Measurement source changed       STRONG
2. Blood-pressure pattern changed   WEAK
```

The user should immediately see that the apparent biological pattern may be confounded by observation changes.

---

# 58. "Evidence Against" Findings

The engine may also establish that an obvious confounder did **not** change.

Example:

```text
Instrumentation:
No material change detected

Device:
same

Recording method:
same

Completeness:
stable
```

This is valuable supporting evidence.

It should not be phrased as proof that instrumentation had no effect—only that no material recorded change was detected.

---

# 59. Negative Results

If no candidate Difference reaches MODERATE evidence:

provider-facing summary:

> **No reliable distinguishing pattern found.**

The investigation may still show WEAK exploratory Differences in a secondary section.

This is a defining product behavior.

---

# 60. Comparison Outcome States

A Comparison has one of:

```text
completed_with_findings
completed_no_reliable_findings
insufficient_evidence
invalid
failed
```

These must not be conflated.

---

# 61. Data Quality vs Statistical Evidence

Store separately:

```text
data_quality_state
evidence_level
```

Example:

```text
Data quality: GOOD
Evidence: WEAK
```

because clean data can still be too sparse to distinguish a pattern.

Or:

```text
Data quality: POOR
Evidence: INSUFFICIENT
```

---

# 62. Baseline Drift / Nonstationarity

A domain may mark a process as nonstationary.

Examples:

```text
post-operative recovery
pregnancy
medication titration
chemotherapy cycle
physical rehabilitation
```

For these, simple trailing baselines should not be the default.

Use:

```text
phase-matched
cycle-matched
expected-trajectory
```

where available.

---

# 63. Detrended / Expected-Trajectory Comparison

When a domain provides an expected trajectory:

```text
observed value
-
expected value at same phase
```

becomes the comparison quantity.

Example:

```text
actual recovery slope
vs
expected post-op-day-21 recovery slope
```

The expected model must have:

```text
model version
training/reference population description
applicability rules
uncertainty metadata
```

A cohort-derived expected trajectory must never masquerade as an individual biological certainty.

---

# 64. Cohort Priors and Cold Start

When personal baseline is immature, a domain may use a cohort prior.

UI must say so.

Example:

```text
Baseline:
Program population prior

Personal history:
8 usable days

Baseline maturity:
IMMATURE
```

Evidence based primarily on a cohort prior cannot receive STRONG individual-level evidence in v0.1.

---

# 65. Historical Backfill

Historical imports can mature a baseline.

But imported data must retain:

```text
source
collection method
historical import time
original observed time
source-version metadata
```

A baseline containing multiple incompatible historical measurement methods may still be partial despite a large record count.

---

# 66. Cohort Comparison Contract

Default cohort analysis unit:

```text
subject
```

not individual observations.

Subject-level features are computed first.

Example:

```text
subject A:
28d BP variability = X

subject B:
28d BP variability = Y
```

Then cohort groups are compared.

This prevents patients with dense telemetry from dominating the sample.

---

# 67. Cohort Matching

v0.1 supports:

```text
unmatched descriptive cohort comparison
```

and optionally:

```text
explicit rule-based matching / stratification
```

Examples:

```text
age band
treatment phase
procedure type
program duration
```

Do not introduce propensity-score causal inference in MVP.

If cohort groups differ materially on known matching dimensions, the UI must disclose that.

---

# 68. Cohort Causal Language

Forbidden:

> "Patients who slept less had worse outcomes because of sleep."

Allowed:

> "Lower sleep duration was more common in the affected cohort."

Even after FDR adjustment.

Association remains association.

---

# 69. Evidence Strength and Sample Size

Evidence labels must not depend only on sample count.

They incorporate:

```text
minimum evidence gates
completeness
baseline maturity
source compatibility
effect magnitude
stability
missingness behavior
analysis mode
```

A giant sample with a source transition can still produce poor evidence.

---

# 70. Provider-Facing Difference Display

Every displayed Difference should be capable of expanding to:

```text
Affected:
value / distribution
count
usable denominator
calendar span
completeness

Baseline:
value / distribution
count
usable denominator
calendar span
completeness

Effect:
absolute difference
relative/standardized difference if appropriate

Evidence:
level
reasons

Source:
source mix
recording method

Stability:
result

Method:
comparison method/version
```

---

# 71. Provider-Facing Evidence Explanation

Example:

```text
Evidence: MODERATE

Why:
✓ 7 of 9 expected affected days observed
✓ 23 of 28 baseline days observed
✓ same connected cuff and recording method
✓ direction stable using alternate 10-day window

Limits:
• baseline is partial, not mature
```

Evidence labels must be explainable in ordinary language.

---

# 72. Internal Evidence Reason Codes

Store structured reason codes.

Examples:

```text
affected_minimum_met
baseline_minimum_met
high_completeness
partial_baseline
mature_baseline
stable_sensitivity
unstable_sensitivity
source_changed
missingness_shift
low_count
cohort_prior_used
independent_support
```

The UI explanation is generated from these codes.

Do not generate evidence explanations from an LLM.

---

# 73. AI Boundary

AI may summarize:

```text
Comparison
Differences
Findings
Evidence reasons
```

AI may not:

```text
upgrade evidence
invent uncomputed associations
silently choose a different baseline
reinterpret missing values as observations
declare causality
```

---

# 74. Reproducibility

Every Comparison result stores or references:

```text
affected-set definition
baseline instance
unit of analysis
context-definition version
semantic-convention version
normalizer versions
derived-signal versions
aggregation versions
comparison-method version
Finding-definition versions
source data as-of timestamp
```

---

# 75. Saved Investigations

A saved Investigation pins:

```text
data snapshot / evidence IDs
Comparison result
Finding set
versions
```

New data does not rewrite the historical Investigation.

If results change:

```text
New data available since this analysis.
```

The user may explicitly create a new Comparison.

---

# 76. Late-Arriving Data

Live Case analysis is recomputed when relevant late data arrives.

Possible consequences:

```text
INSUFFICIENT → MODERATE
STRONG → MODERATE
Finding rank changes
Finding disappears
new Measurement Finding appears
```

This is normal.

The Case timeline should record that analysis changed.

---

# 77. Version Changes

Changing:

```text
comparison algorithm
baseline rule
effect threshold
Finding grouping
```

does not rewrite old saved analyses.

Live cases may be reprocessed under the new version according to an explicit migration/recompute policy.

---

# 78. Rails Statistical API Shape

The statistical layer should be expressed as explicit Ruby objects.

Conceptual:

```ruby
Comparisons::Run.call(
  affected_set:,
  baseline:,
  definition:,
  as_of:
)
```

Returns:

```ruby
ComparisonResult.new(
  status:,
  differences:,
  evidence_metadata:,
  method_version:
)
```

---

# 79. Difference Result Object

Conceptual:

```ruby
DifferenceResult = Data.define(
  :dimension_key,
  :status,

  :affected_summary,
  :baseline_summary,

  :effect,
  :effect_magnitude,

  :evidence_level,
  :evidence_reasons,

  :stability,

  :source_compatibility,
  :completeness,

  :method_version
)
```

Prefer immutable value objects for statistical outputs.

Persistence happens at the application boundary.

---

# 80. Evidence Gate Object

Conceptual:

```ruby
class Comparisons::EvidenceGate
  Result = Data.define(
    :eligible,
    :maximum_evidence,
    :reasons
  )

  def evaluate(affected:, baseline:, definition:)
    # deterministic rules
  end
end
```

This keeps "can we say anything?" separate from effect calculation.

---

# 81. Comparison Method Interface

Conceptual:

```ruby
module Comparisons
  class Method
    def run(affected:, baseline:, definition:)
      raise NotImplementedError
    end
  end
end
```

Potential v0.1 methods:

```text
RobustContinuousShift
BinaryProportionShift
TrajectoryDeviation
SingleEpisodeDeviation
CohortContinuousDifference
CohortBinaryDifference
```

---

# 82. No General Statistics DSL in v0.1

Do not build an arbitrary statistics language.

ComparisonDefinitions are code/config owned by the platform/domain pack.

Provider users can choose:

```text
time range
allowed baseline
filters
```

but cannot construct unvalidated arbitrary formulas in MVP.

---

# 83. Reference Hypertension Example A

Affected:

```text
7-day window
5 usable BP days
71% completeness
same device
```

Baseline:

```text
28-day window
23 usable BP days
82% completeness
same device
partial/mature per domain definition
```

Result:

```text
systolic summary shifted materially
direction stable
no source change
```

Possible evidence:

```text
MODERATE
```

If domain-defined effect and baseline requirements pass.

---

# 84. Reference Hypertension Example B — Source Change

Affected:

```text
5 manual BP entry days
```

Baseline:

```text
21 connected-cuff days
```

Result:

```text
Measurement method changed: STRONG
BP pattern changed: suppressed or WEAK
```

The product does not headline the biological interpretation.

---

# 85. Reference Hypertension Example C — Missingness

Affected:

```text
3 of 10 expected measurement days
30% completeness
```

Baseline:

```text
22 of 28 expected days
79% completeness
```

Result:

```text
BP pattern Difference:
INSUFFICIENT

Measurement behavior changed:
STRONG
```

This is a successful analysis, not a failure.

---

# 86. Reference Hypertension Example D — Small Count

Affected:

```text
3 measurement days
```

Baseline:

```text
6 measurement days
```

Even if:

```text
affected mean BP appears dramatically higher
```

the longitudinal Difference result is:

```text
INSUFFICIENT
```

The threshold Monitor may still assign:

```text
Review Priority: NOW/TODAY
```

according to customer clinical policy.

Again:

```text
urgency != statistical evidence
```

---

# 87. Reference Cohort Example

Affected:

```text
47 subjects with trajectory change
```

Baseline:

```text
126 subjects without trajectory change
```

Candidate dimensions:

```text
42
```

Formal cohort method may compute:

```text
effect estimate
raw p-value
BH-adjusted q-value
```

Surface only dimensions that meet:

```text
minimum group size
minimum effect magnitude
q threshold
data-quality requirements
```

Then cluster eligible Differences into provider-facing Findings.

---

# 88. Statistical Method Versioning

Every method has a stable identifier:

```text
robust_continuous_shift.v1
binary_proportion_shift.v1
cohort_fdr_bh.v1
finding_evidence_aggregation.v1
```

A method version is immutable.

Behavior changes require a new version.

---

# 89. Auditability

For every provider-visible Finding, the system must be able to answer:

```text
Why did this appear?
Why is it ranked here?
Why is the evidence MODERATE?
What was excluded?
What baseline was used?
What changed in measurement behavior?
Which records contributed?
Which method version ran?
```

If those questions cannot be answered, the Finding should not exist.

---

# 90. Statistical Testing Requirements

Every statistical method needs tests for:

```text
empty data
minimum thresholds
missingness
source changes
zero variance
extreme values
duplicate observations
late data
timezone boundaries
small denominators
retries/reproducibility
```

---

# 91. Simulation Tests

Before pilot use, build synthetic datasets representing:

```text
true stable trajectory
true level shift
true gradual trend
source-switch artifact
missingness artifact
random sparse outliers
high autocorrelation
seasonal/phase drift
correlated Difference families
```

Expected product behavior should be asserted.

Example:

```text
source-switch artifact
→ instrumentation Finding outranks biological Finding
```

---

# 92. False-Positive Budget

Before pilot deployment, every default domain monitor/comparison combination should be exercised against synthetic null data.

The purpose is not to claim formal clinical validation.

The purpose is to catch:

```text
engines that always find something
rankings dominated by low-n dimensions
artifact amplification
unstable Finding clusters
```

The desired behavior on null data is frequently:

```text
No reliable distinguishing pattern found.
```

---

# 93. Pilot Feedback

Provider dispositions should be linked back to statistical outputs.

Useful aggregates:

```text
Finding judged useful
Finding judged irrelevant
instrumentation issue confirmed
measurement issue confirmed
no actionable distinction
provider disagreed
```

This is product-quality feedback.

It must not automatically retrain statistical models in v0.1.

---

# 94. Changes Requiring Statistical Review

The following cannot be changed casually by product engineering:

```text
minimum evidence thresholds
evidence label rules
effect-size definitions
FDR thresholds
baseline requirements
source-change suppression rules
Finding evidence aggregation
cohort minimum sizes
```

Changes require:

1. written rationale,
2. version bump,
3. simulation/regression tests,
4. statistical/clinical review appropriate to the domain.

---

# 95. What v0.1 Explicitly Does Not Attempt

Not included:

```text
causal inference
Bayesian patient digital twins
propensity scoring
automated treatment-effect estimation
generalized mixed models for every signal
hidden Markov disease-state inference
learned Finding clustering
ML feature importance presented as explanation
cross-customer population inference
formal clinical prediction models
```

Those may become useful later.

They should not contaminate the trustworthy descriptive core.

---

# 96. v0.1 Contract Summary

The Comparison Engine must obey:

1. **Declare the unit of analysis.**
2. **Never treat raw repeated samples as independent merely because they exist.**
3. **Model missingness and measurement behavior explicitly.**
4. **Never zero-impute absence unless the semantic contract guarantees zero.**
5. **Check instrumentation changes before biological interpretation.**
6. **Require explicit versioned baselines.**
7. **Expose baseline maturity.**
8. **Require minimum affected and baseline evidence.**
9. **Use robust descriptive effects for individual investigations.**
10. **Do not rank individual-patient Differences by p-value.**
11. **Show denominators everywhere.**
12. **Run sensitivity/stability checks before strong evidence.**
13. **Control formal multiplicity in cohort hypothesis-testing mode.**
14. **Require effect magnitude in addition to statistical significance.**
15. **Cluster correlated Differences into Findings.**
16. **Do not double-count derivatives from the same underlying evidence.**
17. **Keep Review Priority separate from Evidence Strength.**
18. **Permit "No reliable distinguishing pattern found."**
19. **Pin every saved Investigation to reproducible inputs and method versions.**
20. **Make every provider-facing conclusion independently inspectable.**

---

# 97. Founding Statistical Principle

> **The system does not owe the user an explanation.**

It owes the user an honest representation of the available evidence.

Sometimes that is:

> **This period is meaningfully different, and these dimensions distinguish it.**

Sometimes:

> **The way this patient was measured changed.**

And sometimes:

> **We do not have enough evidence to know yet.**

All three are successful outputs.

---

# 98. Implementation Handoff

With this contract fixed, the implementation plan can safely define:

```text
BaselineDefinition schema
BaselineInstance schema

ComparisonDefinition schema
Comparison persistence

EvidenceGate pipeline

Comparison Method objects

Difference persistence

FindingDefinition / Finding generation

analysis-status transitions

late-data invalidation

Ops Queue evidence summaries

Investigation evidence inspector
```

The implementation should preserve the statistical boundaries in this document rather than embedding statistical behavior directly into controllers, ActiveRecord callbacks, or UI code.

---

# 99. References and Methodological Influences

These sources informed the conservative direction of this contract. They do not constitute product validation.

## FDA — Digital Health Technologies for Remote Data Acquisition in Clinical Investigations

FDA emphasizes prespecifying endpoints/source data, accounting for technology changes that can affect collection or interpretation, and planning for missing data and data-quality issues in remotely acquired digital-health data.

https://www.fda.gov/regulatory-information/search-fda-guidance-documents/digital-health-technologies-remote-data-acquisition-clinical-investigations

## European Medicines Agency — Missing Data in Confirmatory Clinical Trials

The EMA guideline discusses missing-data mechanisms including MCAR, MAR, and MNAR and the importance of explicitly addressing missing data rather than assuming it is innocuous.

https://www.ema.europa.eu/en/missing-data-confirmatory-clinical-trials-scientific-guideline

## Benjamini & Hochberg (1995)

"Controlling the False Discovery Rate: A Practical and Powerful Approach to Multiple Testing."

Journal of the Royal Statistical Society: Series B, 57(1), 289–300.

https://doi.org/10.1111/j.2517-6161.1995.tb02031.x

## Tang & Landes (2020)

"Some t-tests for N-of-1 trials with serial correlation."

The work demonstrates that serial correlation can materially alter inference in repeated single-person measurements and reinforces the decision not to use naive independent-sample testing for individual health timelines.

https://pmc.ncbi.nlm.nih.gov/articles/PMC6999905/

---

# 100. Next Step

The remaining pre-implementation design task is no longer statistical.

The next step should be:

# **Implementation Plan v0.1 — Rails**

That plan can now map the product into:

```text
Rails models
PostgreSQL schema
domain namespaces
jobs
service objects
domain-pack interfaces
Hotwire screens
vertical slices
test strategy
and pilot milestones
```

without leaving the core epistemic and statistical behavior undefined.
