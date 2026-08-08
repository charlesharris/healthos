# Human Observability Platform
## Product & Architecture Design — v0.3
### Provider Observability for Longitudinal Health

**Working category:** Provider Health Observability

**Internal product metaphor:** *Honeycomb for health providers.*

**External shorthand:** *Datadog/Honeycomb for longitudinal health.*

**Primary customer:** Healthcare providers, virtual-care organizations, population-health teams, clinical operations teams, specialty-care programs, remote-patient-monitoring programs, and other B2B care organizations.

**Primary users:** Clinical operations, care management, population health, nursing, medical directors, specialty clinicians, analysts, and other provider-side users responsible for understanding changing patient trajectories.

**Not a patient-facing product.**

**Core product loop:**

> **Signal → Context → Compare → Investigate → Evidence → Action**

**Founding product principle:**

> **When something changes, show me what was different. Then show me the evidence.**

---

# 1. Executive Summary

Healthcare organizations increasingly possess enormous quantities of longitudinal health data:

- EHR observations and encounters,
- laboratory results,
- medications,
- pharmacy and medication-access events,
- claims,
- remote patient monitoring,
- wearable data,
- smart scales,
- continuous glucose monitors,
- patient-reported outcomes captured through existing systems,
- scheduling and care-delivery events,
- care plans,
- device metadata,
- and specialty-specific telemetry.

What they usually lack is a coherent way to **investigate change across those systems**.

Most healthcare software answers questions such as:

```text
What is the latest weight?
What was the last A1c?
How many patients missed a measurement?
Which patients crossed a threshold?
```

The Human Observability Platform is designed to answer a different class of question:

```text
What changed?
What was different around that change?
Is the apparent change biological, behavioral, operational, or instrumentation-related?
How does this period compare with an appropriate baseline?
Which other patients show the same pattern?
What evidence supports this finding?
Is there enough evidence to say anything at all?
```

The product takes its deepest inspiration from Honeycomb rather than from conventional health dashboards.

It assumes:

> **We often do not know which dimension matters before the investigation begins.**

Therefore the system must preserve rich context and high-cardinality dimensions rather than reducing every patient to a fixed dashboard.

The daily provider workflow is not a patient dashboard.

It is an **operations queue**:

```text
Population
   ↓
Signals / trajectory changes
   ↓
Cases requiring review
   ↓
Top evidence-backed findings
   ↓
One-click investigation
   ↓
Provider action in existing workflow
```

The power-user workflow is an **Investigation Workbench**:

```text
Select anomaly
   ↓
Construct context
   ↓
Choose baseline
   ↓
Compare
   ↓
Rank Difference Clusters
   ↓
Inspect dimensions
   ↓
Drill into evidence
   ↓
Form / test hypothesis
```

The platform is deliberately general.

GLP-1 care may be one useful early domain pack, but nothing above the domain-pack layer should depend on GLP-1-specific concepts.

The same core platform should support:

- diabetes,
- hypertension,
- cardiology,
- oncology,
- post-operative recovery,
- physical therapy,
- sleep medicine,
- nephrology,
- behavioral health,
- fertility,
- pregnancy,
- remote monitoring,
- hospital-at-home,
- chronic disease management,
- and future specialty programs.

---

# 2. What Changed From v0.2

v0.3 makes five major corrections.

## 2.1 The product is provider-side only

The product no longer includes a patient-facing UX.

Patients may remain data subjects and may contribute data through upstream systems, but they are not product users.

This changes the product metaphor from:

> “Personal health dashboard”

to:

> **“Clinical/health operations observability console.”**

The closest organizational analogy is an SRE team investigating production systems.

---

## 2.2 GLP-1 is a domain pack, not the platform

GLP-1 concepts move below the platform boundary.

Core platform:

```text
Telemetry
Context
Baseline
Comparison
Difference
Finding
Investigation
Evidence
Monitor
Queue
Cohort
```

Domain pack:

```text
GLP-1
Diabetes
Cardiology
Sleep
Oncology
etc.
```

Every platform-level design decision should pass this test:

> **Would this still make sense if the first commercial specialty changed tomorrow?**

If not, it belongs in a domain pack.

---

## 2.3 The daily product is the Ops Queue

The Investigation Workbench remains the most distinctive demo surface.

But it is not necessarily where most users spend most of their day.

The daily workflow becomes:

```text
Which patients / cases need attention?
Why are they here?
What changed?
How strong is the evidence?
What should I inspect next?
```

The queue precomputes enough context that deep investigation is one click away.

---

## 2.4 Statistical trust becomes a first-class architecture problem

v0.2 handled provenance and epistemology well but under-specified:

- endogenous missingness,
- small sample sizes,
- multiple comparisons,
- autocorrelation,
- correlated dimensions,
- nonstationary baselines,
- and cold start.

v0.3 treats these as core product behavior.

The platform must be willing to say:

> **Not enough evidence to distinguish this period from baseline.**

Silence is better than a confident artifact.

---

## 2.5 Differences become Findings / Difference Clusters

A raw ranked list of dimensions is too naive.

Example:

```text
nausea ↑
protein ↓
hydration ↓
activity ↓
```

may be four measurements of one underlying phenomenon.

v0.3 adds:

## **Finding**

A Finding groups one or more related Differences into a coherent, inspectable story.

Example:

```text
Finding: GI-intolerance pattern

Evidence:
- nausea severity increased
- hydration declined
- meal logging declined
- activity declined

Confidence:
moderate

Important:
This is a descriptive cluster, not a diagnosis or causal conclusion.
```

---

# 3. Product Category

The platform should not be positioned as:

- remote patient monitoring,
- patient engagement,
- personal health tracking,
- another EHR,
- another wearable dashboard,
- disease-specific coaching,
- AI diagnosis,
- or a general business-intelligence tool.

The intended category is:

# **Provider Health Observability**

The customer buys a way to observe and investigate longitudinal health systems.

The “system” is not only the patient's body.

It includes:

```text
patient physiology
behavior
treatment
medication access
care delivery
instrumentation
data collection
environment
workflow
```

This distinction is critical.

An apparent health change may originate in any of them.

---

# 4. Primary Customer and User Model

## 4.1 Economic buyer

Likely buyers include:

- VP Clinical Operations,
- Chief Medical Officer,
- Chief Clinical Informatics Officer,
- Population Health leader,
- specialty-program leader,
- RPM leader,
- digital-health product leader,
- quality/outcomes leader.

The economic promise is operational:

> **Help your team detect, triage, and investigate meaningful changes across a patient population without reconstructing the story from five disconnected systems.**

---

## 4.2 Primary day-to-day user

Primary operational persona:

> **Provider-side care operations / clinical operations user**

Examples:

- care manager,
- nurse,
- population health specialist,
- specialty-program operator,
- clinical analyst.

Their job resembles Ops/SRE work:

```text
watch population
identify changes
triage queue
inspect evidence
escalate or act
document outcome
```

---

## 4.3 Secondary power user

Examples:

- physician,
- medical director,
- specialist,
- clinical informaticist,
- research/quality analyst.

They use the Investigation Workbench for deeper questions.

---

# 5. Product Surfaces

The B2B product has four primary surfaces.

## 5.1 Ops Queue

Daily operating surface.

```text
Cases needing attention
Signals
Top Findings
Evidence maturity
Data-quality warnings
Assignment
Status
```

---

## 5.2 Investigation Workbench

Honeycomb-inspired deep exploration.

```text
Timeline
Affected region
Baseline
Difference Clusters
Dimensions
Evidence
Provenance
```

---

## 5.3 Cohort Explorer

Population investigation.

```text
Define population
Select affected group
Choose comparison group
Find distinguishing clusters
Drill into patients
```

---

## 5.4 Observability Administration

Operational trust surface.

```text
data sources
integration health
data completeness
late-arriving data
schema versions
source changes
monitor definitions
domain packs
audit
```

The platform should be observable as a data system in its own right.

---

# 6. Core Product Loop

The revised loop is:

```text
SIGNAL
   ↓
CONTEXT
   ↓
COMPARE
   ↓
FINDINGS
   ↓
INVESTIGATE
   ↓
EVIDENCE
   ↓
ACTION
```

---

# 7. Signal

A Signal is an indication that something may deserve attention.

Signals can originate from:

- monitors,
- trajectory changes,
- missing expected data,
- source/instrumentation changes,
- care workflow events,
- clinician queries,
- cohort analysis,
- or external system events.

A signal is **not** a diagnosis.

Example:

```text
weight trajectory changed
blood pressure variability increased
device stopped reporting
medication refill delayed
lab pattern changed
sleep worsened
rehab adherence declined
post-op recovery deviated from expected trajectory
```

A Signal may create or update an Ops Queue item.

---

# 8. Canonical Telemetry Model

The canonical layer remains normalized and evidence-preserving.

Core canonical entities:

```text
Observation
Event
Interval
DerivedSignal
Source
Device
Provenance
Subject
Organization
```

---

## 8.1 Observation

A measured or reported value.

Examples:

```text
weight
blood pressure
heart rate
A1c
creatinine
temperature
pain score
oxygen saturation
steps
sleep duration
glucose
```

---

## 8.2 Event

A discrete occurrence.

Examples:

```text
medication administered
medication ordered
refill requested
visit completed
therapy session completed
fall reported
symptom reported
procedure performed
device connected
device changed
```

---

## 8.3 Interval

A bounded period.

Examples:

```text
sleep session
hospital admission
illness
travel
medication exposure
rehab episode
treatment cycle
symptom episode
```

---

## 8.4 DerivedSignal

A reproducible computed value.

Examples:

```text
7-day weight velocity
blood-pressure variability
adherence estimate
baseline deviation
recovery slope
symptom burden
data-completeness score
```

Every derived signal must retain exact lineage.

---

# 9. Context

A Context is a wide, queryable representation of what was happening around a meaningful moment or interval.

Examples:

```text
Lab Context
Visit Context
Medication Context
Hospitalization Context
Recovery Context
Symptom Context
Trajectory Context
Treatment-Cycle Context
Device-Change Context
```

A Context is constructed from canonical data.

It is not the source of truth.

---

# 10. Context Is Constructed, Not Canonical

Architecture:

```text
Raw data
   ↓
Canonical telemetry
   ↓
Derived signals
   ↓
Context Engine
   ↓
Wide analytical context
   ↓
Comparison / investigation
```

This preserves:

- replayability,
- provenance,
- source truth,
- algorithm versioning,
- and future extensibility.

---

# 11. The Context Engine

The Context Engine is a core platform capability.

Given an anchor such as:

```text
event
observation
time window
episode
queue item
patient cohort
```

it constructs the relevant dimensions around that anchor.

Example general Context:

```text
subject.id
age_band
care_program
treatment_phase

latest_measurements
measurement trends
recent medications
recent labs
recent visits

activity baseline delta
sleep baseline delta
symptom burden

care adherence
medication access

source changes
logging changes
data completeness

recent hospitalization
recent illness
recent travel

derived trajectory state
```

Different domain packs define different useful dimensions.

---

# 12. Multi-Timescale Context

Health must be analyzed across multiple overlapping windows.

A context may include:

```text
6 hours
24 hours
72 hours
7 days
28 days
90 days
treatment phase
historical baseline
```

The ContextDefinition determines which windows are valid per signal.

Example:

```yaml
dimension: health.sleep.duration_delta

window:
  primary: 7d

baseline:
  type: personal_phase_adjusted

minimum_evidence:
  observed_days: 4
```

---

# 13. Full Reproducibility Tuple

Reproducing a Context requires more than its ContextDefinition version.

The complete version tuple includes:

```text
context_definition_version
semantic_convention_version
normalizer_version(s)
derived_signal_algorithm_version(s)
baseline_definition_version
comparison_method_version
source snapshot / as-of time
```

Saved investigations pin this tuple.

---

# 14. Late Data and Context Recalculation

Late-arriving data is expected.

An already-materialized Context may become stale when:

- a wearable sync arrives late,
- a corrected lab appears,
- a source event is modified,
- duplicate resolution changes,
- or historical data is backfilled.

Policy:

1. Canonical telemetry updates.
2. Context materializations are invalidated.
3. Live queue items may recompute.
4. Saved investigations remain pinned to the original evidence snapshot.
5. Saved investigations display:

```text
Data has changed since this investigation.
[View updated comparison]
```

Reproducibility is preserved without hiding newer truth.

---

# 15. Missingness Is Signal

Missing health data is often endogenous.

Examples:

```text
patient disengages from logging
device is removed
care workflow stops collecting a measurement
manual entry frequency decreases
app synchronization fails
```

The system must not treat absence only as a confidence penalty.

It must model **measurement behavior** directly.

---

## 15.1 Measurement/engagement dimension family

Examples:

```text
context.measurement_frequency_delta
context.days_since_last_measurement
context.logging_frequency_delta
context.days_since_last_manual_entry
context.engagement_trend_7d
context.engagement_trend_28d
context.device_reporting_frequency_delta
context.source_availability
context.data_completeness
```

These dimensions belong alongside biological dimensions.

---

## 15.2 Biological difference vs measurement difference

The UI must distinguish:

### Health / behavior changed

```text
Recorded protein intake was lower.
```

from:

### Measurement changed

```text
Nutrition logging frequency decreased substantially.
```

When the second is true, the first may not be rankable.

---

# 16. Instrumentation Changes Are First-Class

Provider health data changes when instrumentation changes.

Examples:

```text
new device
different lab vendor
manual → automated measurement
wearable removed
new EHR feed
integration version changed
measurement protocol changed
```

These are queryable dimensions:

```text
source.provider
source.device
source.recording_method
source.changed
source.integration_version
measurement.protocol
```

An instrumentation change may explain an apparent clinical change.

The product must surface that possibility before ranking biological explanations.

---

# 17. Baselines

A baseline is an explicit comparison model.

“Normal” is not a universal concept.

Valid baselines include:

```text
personal historical
recent personal
phase-matched
treatment-cycle
cohort
matched-cohort
expected trajectory
seasonal
pre/post intervention
```

Every comparison must state which baseline was used.

---

# 18. Nonstationary Baselines

Health trajectories often drift.

Examples:

```text
recovery
pregnancy
medication titration
cancer treatment
physical therapy
aging
post-operative healing
```

A static trailing median may be incorrect.

Domain packs can specify:

```text
phase-aware baseline
cycle-aware baseline
detrended baseline
expected trajectory
```

Example:

```text
actual recovery slope
vs
expected recovery slope at post-op day 21
```

rather than:

```text
today
vs
last 28 days
```

---

# 19. Baseline Maturity

Every baseline receives a maturity state.

Example:

```text
immature
partial
mature
historically backfilled
cohort-prior
```

The UI must make this visible.

Example:

```text
Baseline maturity: Partial
17 days of usable personal history

Population prior used for:
sleep trajectory
```

---

# 20. Cold Start / Degraded Mode

The product must work before 90 days of perfect data exists.

## Day 1

Possible behavior:

```text
source health
latest observations
hard event chronology
cohort priors
existing EHR history
historical import
```

No unsupported personal trend claims.

---

## Day 14

Possible behavior:

```text
short-window personal trends
measurement behavior
initial baseline deviations
cohort-supported comparisons
```

---

## Day 45+

Possible behavior:

```text
personal baselines
cycle comparisons
phase comparisons
longitudinal trajectory analysis
```

Historical backfill is a high-priority onboarding feature.

---

# 21. Compare

A Comparison evaluates an affected set against a baseline set.

Examples:

```text
this patient this week
vs
same patient prior month
```

```text
current treatment cycle
vs
prior treatment cycles
```

```text
patients with trajectory change
vs
similar patients without change
```

```text
post-op recoveries requiring escalation
vs
recoveries without escalation
```

---

# 22. Unit of Analysis

Raw observations are not automatically independent samples.

The Comparison Engine must explicitly define the unit of analysis.

Possible units:

```text
patient
day
episode
treatment cycle
visit
week
hospitalization
```

This prevents hundreds of CGM readings from masquerading as hundreds of independent subjects.

Domain packs specify valid units per comparison.

---

# 23. Minimum Evidence Gates

Difference ranking occurs only when minimum evidence requirements are met.

Examples:

```text
minimum observations
minimum observed days
minimum affected units
minimum baseline units
minimum completeness
minimum variance
minimum cohort size
```

If not:

> **Not enough evidence to distinguish this period from baseline.**

This output is a feature.

---

# 24. Multiple Comparisons

The system will frequently evaluate dozens or hundreds of dimensions.

Naive effect-size ranking will generate spurious winners.

MVP discipline:

1. always show denominators,
2. require minimum absolute counts,
3. penalize low-n dimensions,
4. shrink extreme low-evidence effects toward no difference,
5. apply a multiple-testing correction where statistically appropriate,
6. never rank dimensions that fail evidence gates,
7. group correlated dimensions before presentation.

For larger cohort analyses, the methods layer can support FDR-style control.

For single-subject analysis, effect size and evidence strength should be emphasized over pseudo-precise p-values.

---

# 25. Autocorrelation

Adjacent time points are correlated.

The product should not imply:

```text
28 days = 28 independent observations
```

Strategies include:

- use natural episode/cycle units,
- aggregate to clinically meaningful time blocks,
- compare trajectories rather than individual samples,
- use block/bootstrap methods later where necessary,
- clearly state the analytical unit.

MVP should prefer understandable aggregation over sophisticated but opaque statistical machinery.

---

# 26. Denominators Always

A Difference may never display only:

```text
18% vs 1%
```

It must provide the underlying evidence:

```text
3 of 17 observed days
vs
0 of 28 observed days
```

or:

```text
12 of 47 patients
vs
3 of 126 patients
```

Percentage-only health comparisons are prohibited in the UI.

---

# 27. Difference

A Difference describes one dimension that varies between affected and baseline sets.

Example:

```text
Dimension:
sleep duration below phase baseline

Affected:
11 of 16 observed days

Baseline:
4 of 25 observed days

Effect:
higher frequency in affected period

Evidence:
moderate
```

Difference is descriptive.

It is not causal.

---

# 28. Findings / Difference Clusters

A Finding groups related Differences into a coherent pattern.

Example:

```text
Finding:
Measurement engagement changed

Differences:
- manual logging frequency ↓
- days since nutrition entry ↑
- symptom-entry frequency ↓
```

or:

```text
Finding:
Activity/recovery pattern changed

Differences:
- steps ↓
- strength sessions ↓
- sleep duration ↓
```

---

## 28.1 Why Findings matter

Without clustering, the system may rank several correlated dimensions as independent discoveries.

That creates false confidence.

Findings should:

- reduce redundancy,
- make results interpretable,
- preserve all component dimensions,
- and give the AI narrator a coherent evidence object.

---

## 28.2 Finding generation

MVP approaches:

- domain-pack-defined dimension groups,
- correlation-aware grouping,
- semantic grouping,
- manually authored clinical/operational families.

Later:

- unsupervised clustering,
- learned association structure,
- specialty-specific validated models.

Every Finding remains inspectable down to its individual Differences.

---

# 29. Evidence Strength

Every Difference and Finding receives an evidence-strength representation.

Inputs may include:

- sample size,
- completeness,
- baseline maturity,
- source quality,
- effect stability,
- multiple-comparison penalty,
- consistency across windows,
- instrumentation changes.

The output should be simple:

```text
insufficient
weak
moderate
strong
```

The exact calculation must be versioned and inspectable.

---

# 30. Evidence Language Ladder

This survives intact as a foundational product rule.

## Observation

> “Blood pressure variability increased.”

## Difference

> “Blood pressure variability was higher during the selected period.”

## Association

> “Higher blood pressure variability was more common in the affected cohort.”

## Hypothesis

> “Medication timing may be relevant to the observed change.”

## Causal claim

Reserved for explicitly validated models, established clinical knowledge applied transparently, or clinician-authored assertions.

These categories must not blur in UI copy.

---

# 31. The Ops Queue

The Ops Queue is the provider team's daily surface.

Example:

```text
──────────────────────────────────────────────────────────────────
PATIENT             SIGNAL                  TOP FINDING     EVIDENCE
──────────────────────────────────────────────────────────────────
A. Smith            Recovery slowed         Activity shift   Strong
J. Lee              BP variability ↑        Source changed   Strong
R. Jones            Data gap                Engagement ↓     Strong
M. Patel            A1c trajectory shift    Mixed            Moderate
K. Garcia           Device silent           Instrumentation  Strong
──────────────────────────────────────────────────────────────────
```

Additional fields:

```text
owner
status
program
last reviewed
severity / priority
data maturity
open actions
```

---

# 32. Queue Item Lifecycle

Conceptual states:

```text
new
triaged
investigating
waiting
resolved
dismissed
```

The healthcare organization defines workflow semantics.

A queue item can link outward to:

- EHR task,
- care-management platform,
- case-management system,
- provider note,
- ticket/workflow system.

We do not need to replace those systems.

---

# 33. Queue Scoring

Queue scoring must remain operational rather than diagnostic.

Inputs can include:

```text
signal severity
evidence strength
program priority
recent change magnitude
data completeness
time since review
customer-authored rules
```

Outputs:

```text
review priority
```

Not:

```text
medical severity diagnosis
```

Clinical risk scoring requires a separate validated strategy.

---

# 34. Precomputed Findings

To make the queue operationally useful, high-value contexts and comparisons should be precomputed.

Example:

```text
trajectory signal created
   ↓
context materialized
   ↓
default domain baseline selected
   ↓
difference analysis
   ↓
findings generated
   ↓
queue item shows top finding
```

This makes one-click investigation fast.

---

# 35. Investigation Workbench

The Workbench is the deep-dive surface.

Recommended layout:

## Left — Timeline

```text
clinical measurements
labs
medications
events
encounters
devices
care workflow
domain-specific signals
```

## Center — Comparison

```text
affected region
baseline selector
Difference Clusters
individual Differences
filters
```

## Right — Evidence Inspector

```text
source
denominator
raw records
algorithm
baseline
quality
provenance
version tuple
```

---

# 36. Investigation Flow

```text
Open queue item
   ↓
See default affected region
   ↓
See default baseline
   ↓
Review top Findings
   ↓
Open Finding
   ↓
Inspect Differences
   ↓
Change baseline or time window
   ↓
Filter
   ↓
Inspect raw evidence
   ↓
Save investigation / action
```

The provider can ask successive questions without leaving the investigation.

---

# 37. Saved Investigations

Saved investigations pin:

```text
question
affected set
baseline
context definition
comparison method
findings
filters
evidence snapshot
version tuple
created by
created at
notes
```

They do not silently rewrite themselves.

If source data changes, display:

```text
New data is available.
Original investigation remains reproducible.

[Compare with current data]
```

---

# 38. Hypothesis Tracking

Optional but strategically valuable.

A provider can record:

```text
Hypothesis:
"Reduced home monitoring may reflect disengagement rather than stable BP."
```

Statuses:

```text
open
supported
weakened
resolved
discarded
```

This is explicitly provider-authored reasoning.

The platform should never convert it into canonical fact automatically.

---

# 39. Cohort Explorer

The same mental model scales to populations.

Example:

```text
Population:
Adults enrolled in hypertension program

Affected:
Patients whose home BP variability increased materially

Baseline:
Matched patients without the change
```

The platform can surface Findings such as:

```text
Monitoring engagement changed
Medication-event pattern changed
Source/device mix changed
Visit cadence changed
Sleep/activity pattern changed
```

Each result drills to affected subjects.

---

# 40. Small Cohort Privacy

High-dimensional cohort analysis creates re-identification risk.

v0.3 introduces a configurable minimum group-size policy.

Example default concept:

```text
No population-level dimension breakdown below k subjects.
```

The exact value should be customer- and jurisdiction-configurable with counsel/privacy review.

Below the threshold, authorized users may still inspect an individual patient if their role permits it, but the system must not present pseudo-anonymous cohort output that effectively identifies them.

---

# 41. Natural-Language Querying

Natural language is an interface to the structured engine.

Example:

> “Show me post-op knee patients whose recovery slope slowed after week three and compare them with similar patients who stayed on trajectory.”

Pipeline:

```text
natural language
   ↓
structured cohort query
   ↓
affected set
   ↓
baseline/matched cohort
   ↓
context generation
   ↓
comparison
   ↓
Findings
   ↓
evidence packet
   ↓
narrative explanation
```

The model does not directly search raw health records and invent an explanation.

---

# 42. AI as Narrator, Not Oracle

This remains a core invariant.

```text
Structured comparison
   ↓
Findings
   ↓
Evidence packet
   ↓
AI summary
```

AI may:

- summarize findings,
- translate natural-language questions,
- describe evidence,
- propose investigative next steps,
- draft provider notes,
- summarize changes across an investigation.

AI may not:

- silently alter telemetry,
- silently create diagnoses,
- silently assign causal relationships,
- or become the only source of a finding.

---

# 43. AI Artifact Provenance

Store:

```text
model
model version
prompt/template version
input evidence IDs
comparison ID
finding IDs
generated at
generated by
organization
```

If the evidence changes, the generated artifact is not retroactively rewritten.

---

# 44. Monitor Philosophy

Monitors should detect conditions worthy of review.

Examples:

```text
trajectory changed
lab trend changed
device stopped reporting
measurement behavior changed
data source changed
expected recovery deviated
medication-access event
care gap
```

The output should be:

```text
Review recommended
Investigate →
```

not:

```text
Diagnosis:
Treatment recommendation:
```

---

# 45. Domain Packs

A Domain Pack defines specialty-specific semantics and default investigation behavior.

Each pack may contain:

```text
signal definitions
semantic conventions
derived signals
context definitions
baseline rules
unit-of-analysis rules
minimum evidence gates
Finding groups
monitors
queue templates
investigation templates
```

The platform core contains no disease-specific assumptions.

---

# 46. Example Domain Packs

Potential packs include:

```text
GLP-1 / obesity medicine
diabetes
hypertension
cardiology
oncology
post-op recovery
physical therapy
sleep medicine
nephrology
pregnancy
fertility
behavioral health
hospital-at-home
remote patient monitoring
```

The first commercial domain should be chosen based on workflow pain and data availability, not because the platform itself depends on it.

---

# 47. Example: Post-Operative Recovery Pack

This illustrates generality.

Signals:

```text
pain trajectory
mobility trajectory
activity
sleep
temperature
heart rate
wound observations
PT attendance
medication events
follow-up visits
```

Context:

```text
post-op day
procedure type
expected recovery phase
comorbidities
PT adherence
activity delta
pain delta
sleep delta
```

Baseline:

```text
phase-adjusted expected recovery trajectory
```

Queue signal:

```text
Recovery slope changed
```

Finding:

```text
Reduced rehabilitation activity
```

Evidence:

```text
PT sessions missed
daily steps lower
home-exercise reporting absent
```

Same platform. Different domain pack.

---

# 48. Example: Diabetes Pack

Signals:

```text
glucose
CGM variability
time in range
A1c
medications
meals
activity
sleep
device state
```

Potential Finding:

```text
Instrumentation change

Components:
- CGM device changed
- calibration pattern changed
- variability changed at same time
```

Again, the system distinguishes instrumentation from biology.

---

# 49. Data Acquisition Layer

The platform must ingest arbitrary health-domain data.

Potential source classes:

```text
EHR / FHIR
labs
claims
pharmacy
medication access
RPM platforms
wearables
device clouds
HealthKit
Health Connect
CGMs
smart scales
care-management systems
patient-reported data from upstream systems
CSV / batch feeds
customer event APIs
```

Not every deployment requires every source.

---

# 50. Data Acquisition Reality Map

Every domain pack must document data reality.

For each signal:

```text
signal
source
latency
completeness
recording method
expected failure modes
who/what records it
whether historical backfill exists
```

Example:

```text
blood pressure
→ connected cuff
→ near real-time
→ high completeness if device used
→ passive device measurement
→ failure: patient stops measuring / device offline
```

This prevents demos from depending on data that the actual customer cannot obtain.

---

# 51. Interoperability Boundary

FHIR is a primary clinical interoperability interface.

It is not the full internal analytical model.

The internal model must additionally support:

```text
high-frequency telemetry
late arrival
duplicates
source changes
derived lineage
context construction
baseline definitions
analytical windows
comparisons
Findings
```

FHIR resources can map into and out of canonical telemetry where appropriate.

---

# 52. Provider Data, Not Patient UI

The product must not depend on patients opening our application.

Patient-originated data can come from:

- EHR questionnaires,
- remote monitoring applications,
- device platforms,
- portal workflows,
- other care applications.

If we ever build a patient application, it is a separate product decision and regulatory review.

It is explicitly out of scope for v0.3.

---

# 53. Regulatory Design Strategy

The product is provider-facing and evidence-oriented.

The architecture must support an **independently reviewable basis** for every ranked finding.

That means a provider can inspect:

```text
exact input records
baseline
denominators
comparison method
data quality
source provenance
algorithm version
```

This is not merely a usability feature.

It is a core product and regulatory design requirement.

The final regulatory classification and permitted claims require specialized counsel.

---

# 54. Product Claims Discipline

Safe internal posture:

> “This system helps provider teams detect, organize, compare, and investigate longitudinal health data.”

Avoid unsupported claims such as:

```text
diagnoses disease
recommends treatment
determines cause
prevents hospitalization
improves outcomes
```

unless separately validated and reviewed.

---

# 55. Privacy / Security

Baseline posture:

```text
tenant isolation
least privilege
role-based access
encryption in transit
encryption at rest
PHI-aware logging
audit trails
source access controls
data-retention policies
deletion workflows
vendor controls
incident response
backup/restore
```

No PHI in ordinary application logs.

High-cardinality analytical dimensions must inherit privacy classification.

---

# 56. Core Architecture

Start with a modular monolith.

```text
                         Provider Web App
                               │
                               ▼
                        Application API
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
      Identity              Ingestion          Administration
      / Tenancy                │
                               ▼
                         Raw Evidence Store
                               │
                               ▼
                       Canonical Telemetry
                               │
                 ┌─────────────┼───────────────┐
                 │             │               │
                 ▼             ▼               ▼
             Derivations   Baselines        Episodes
                 │             │               │
                 └─────────────┼───────────────┘
                               ▼
                         Context Engine
                               │
                               ▼
                        Comparison Engine
                               │
                               ▼
                       Finding Generator
                               │
                   ┌───────────┼────────────┐
                   │           │            │
                   ▼           ▼            ▼
               Monitors     Ops Queue    Investigation
                                             │
                                             ▼
                                         Cohorts
```

---

# 57. Storage Strategy

Start with PostgreSQL as the system of record.

Conceptual tables:

```text
organizations
users
roles
subjects
sources
devices

raw_envelopes

observations
events
intervals

derived_signals
derived_signal_inputs

baseline_definitions
baseline_instances

context_definitions
contexts
context_values

comparison_definitions
comparisons
differences

finding_definitions
findings
finding_differences

monitor_definitions
monitor_evaluations

queue_items

investigations
investigation_snapshots
hypotheses

audit_events
```

Object storage handles raw payloads and large source artifacts.

Do not introduce a specialized analytics database until measured workload requires it.

---

# 58. Context Materialization Strategy

v0.3 assumes two context modes.

## 58.1 Operational/precomputed contexts

Used for:

```text
queue scoring
monitor evaluation
top Findings
common domain views
```

Characteristics:

```text
batch/incremental
predictable definitions
cached/materialized
cohort-wide
```

---

## 58.2 Interactive contexts

Used for:

```text
custom investigations
alternate baselines
custom time windows
ad-hoc cohorts
```

Characteristics:

```text
on-demand
higher cost
short-lived cache
power-user workflow
```

The same ContextDefinition machinery supports both.

---

# 59. Queue-First Performance Model

Because the queue is the daily product, the system should proactively compute enough information for common cases.

Example:

```text
canonical data updated
   ↓
derived signals updated
   ↓
monitor evaluates
   ↓
signal created
   ↓
default Context generated
   ↓
default baseline generated
   ↓
default Comparison computed
   ↓
top Findings cached
   ↓
queue item updated
```

Opening the Workbench should feel immediate.

---

# 60. Self-Observability

The platform itself must be deeply instrumented.

Technical OpenTelemetry:

```text
ingestion received
raw persisted
normalized
deduplicated
derived
context invalidated
context rebuilt
comparison executed
finding generated
queue updated
```

This is separate from health data.

Technical observability data must never leak PHI into logs/traces.

---

# 61. API Strategy

Potential APIs:

```text
POST /v1/telemetry
GET  /v1/subjects/:id/timeline

GET  /v1/signals
GET  /v1/queue

POST /v1/contexts
POST /v1/comparisons

GET  /v1/findings
POST /v1/investigations

POST /v1/cohorts/query

GET  /v1/sources/health
GET  /v1/data-quality

POST /v1/fhir/import
GET  /v1/fhir/export
```

Long-term, the telemetry API can support domain-neutral SDKs.

---

# 62. Semantic Conventions

The platform should define canonical health semantics without assuming a disease.

Namespaces may include:

```text
health.body.*
health.vital.*
health.activity.*
health.sleep.*
health.glucose.*
health.nutrition.*
health.hydration.*
health.medication.*
health.symptom.*
health.lab.*
health.encounter.*
health.procedure.*
health.device.*
health.recovery.*
health.care.*
health.access.*
health.measurement.*
health.context.*
```

Domain packs extend these.

---

# 63. Measurement Semantics

v0.3 explicitly adds a measurement namespace.

Examples:

```text
health.measurement.frequency
health.measurement.days_since_last
health.measurement.completeness
health.measurement.source_changed
health.measurement.manual_entry_frequency
health.measurement.device_reporting_frequency
```

This makes endogenous missingness observable.

---

# 64. Technical Invariants

All v0.2 invariants remain and are expanded.

1. Raw source truth is preserved.
2. Every canonical value has provenance.
3. Every derived value has exact lineage.
4. Contexts are reproducible from canonical data.
5. Context definitions are versioned.
6. Baselines are explicitly defined and versioned.
7. Comparisons are reproducible.
8. Difference ranking is explainable.
9. Missing data is visible.
10. Source changes are queryable dimensions.
11. Temporal association is not causation.
12. AI never becomes canonical truth.
13. Every displayed conclusion can be drilled into.
14. Patient/subject and tenant boundaries exist below the UI layer.
15. No PHI in ordinary application logs.
16. Measurement behavior is itself observable.
17. No Difference ranking without minimum evidence.
18. Denominators are always available.
19. Saved investigations pin an evidence snapshot.
20. A Finding may summarize Differences but never hide them.
21. Domain-specific assumptions remain below the domain-pack boundary.
22. The provider can independently review the basis for every surfaced Finding.

---

# 65. Trust Budget

A core product principle:

> **Every artifact-driven top finding spends trust.**

If the system repeatedly surfaces:

```text
protein changed
```

when the real event was:

```text
nutrition logging stopped
```

users will stop trusting Difference Explorer.

Therefore ranking quality is not merely a statistics concern.

It is a product-survival concern.

When evidence is weak, say so.

When the measurement changed, surface that.

When nothing distinguishes the affected set, say:

> **No reliable distinguishing pattern found.**

---

# 66. MVP Shape

The MVP should not attempt to be universal in data coverage.

It should prove the general platform through one domain.

Required platform features:

```text
canonical telemetry
provenance
measurement/missingness model
derived signals
Context Engine
Baseline Engine
Comparison Engine
Difference ranking
Finding clustering
Ops Queue
Investigation Workbench
saved evidence snapshot
```

One domain pack provides the actual signals.

---

# 67. MVP Domain Selection Criteria

Choose the first domain based on:

1. longitudinal data availability,
2. recurring provider investigation workflow,
3. measurable operational pain,
4. sufficiently high patient volume,
5. heterogeneous signals,
6. buyer willingness to pay,
7. realistic access to historical data,
8. clear provider-side action after investigation,
9. regulatory tractability,
10. portability of platform primitives.

GLP-1 remains one candidate.

It is no longer assumed to be the final answer.

---

# 68. Candidate Initial Domains

Potential candidates:

## GLP-1 / obesity medicine

Strengths:

```text
clear longitudinal trajectories
multiple interacting signals
medication cycles
high current interest
```

Risks:

```text
medication-access data difficulty
self-reported adherence
market turbulence
```

---

## Post-operative recovery

Strengths:

```text
clear phase-aware expected trajectory
provider-owned workflow
defined escalation process
high value of early deviation detection
```

---

## Hypertension RPM

Strengths:

```text
provider-side monitoring already exists
high measurement volume
device/instrumentation issues matter
care queue already familiar
```

---

## Diabetes

Strengths:

```text
rich continuous data
strong device ecosystem
clear longitudinal care model
```

Risks:

```text
higher clinical/regulatory complexity
crowded market
```

---

# 69. MVP Demo — Generalized

A provider opens the Ops Queue.

```text
18 cases need review.
```

One item:

```text
Trajectory changed
Evidence: Moderate
Top Finding: Measurement behavior changed
```

Open it.

Timeline:

```text
clinical trajectory shifts on Jul 18
```

Default comparison:

```text
affected period
vs
phase-matched baseline
```

Findings:

```text
1. Measurement engagement changed
2. Activity/recovery pattern changed
3. Source/device changed
```

The provider opens Finding #1.

Evidence:

```text
measurement frequency:
5.8 days/week → 2.1 days/week

manual reporting:
4 of 7 days → 1 of 7 days

device:
stopped reporting Jul 16
```

The apparent clinical anomaly may partly be an observability anomaly.

That is precisely what the product should reveal.

---

# 70. MVP Demo — With Rich Clinical Data

A second variant shows a genuine multi-signal pattern.

```text
Trajectory changed
```

Findings:

```text
1. Treatment-cycle pattern changed
2. Symptom/activity cluster changed
3. Data quality stable
```

The provider drills into the first Finding and sees:

```text
medication event timing changed
sleep pattern changed
activity changed
symptoms increased
```

Each result shows counts, source records, and confidence.

No unsupported causal conclusion is generated.

---

# 71. What the Product Does Not Do

v0.3 explicitly excludes:

- patient dashboards,
- patient coaching,
- consumer health tracking,
- direct-to-consumer wellness,
- prescribing,
- telehealth visits,
- diagnosis,
- dosing recommendations,
- autonomous medical triage,
- a proprietary wearable,
- a full EHR,
- insurance billing,
- pharmacy fulfillment.

These may be adjacent markets.

They are not the product.

---

# 72. Commercial Model

Likely pricing forms:

```text
platform fee
+
per monitored subject
+
domain-pack licensing
+
enterprise integrations
```

Enterprise pricing may incorporate:

```text
data volume
number of active subjects
number of domain packs
SLA
integration support
```

The customer buys provider workflow and observability infrastructure.

---

# 73. Defensibility

Weak moat:

```text
charts
wearable integrations
generic AI summaries
simple threshold alerts
```

Stronger moat:

```text
semantic conventions
+
provenance model
+
measurement/missingness model
+
Context Engine
+
baseline model
+
Comparison Engine
+
Difference Clusters
+
investigation workflow
+
domain packs
+
provider operational adoption
```

The company becomes valuable when provider organizations encode:

> **how they observe their patient populations**

inside this platform.

---

# 74. Strategic Acquisition Thesis

Potential acquirer classes:

```text
EHR vendors
care-management platforms
virtual-care platforms
population-health vendors
RPM vendors
device-data aggregators
payer/provider platforms
specialty-care platforms
cloud healthcare vendors
life-sciences / RWE platforms
```

The strategic asset is not:

> “a GLP-1 dashboard.”

It is:

> **a generalized investigation substrate for longitudinal health.**

---

# 75. Review-Driven Additions to the Artifact Plan

The next artifacts should be created in this order.

## 1. Buyer Hypothesis One-Pager

Answer:

```text
who buys
who uses
what queue they operate
what action follows a finding
what workflow we replace or accelerate
```

---

## 2. Statistical Methods Note

Specify:

```text
minimum evidence thresholds
units of analysis
missingness handling
multiple-comparison discipline
autocorrelation stance
Difference Cluster generation
evidence-strength model
denominators
```

---

## 3. Data Acquisition Reality Map

For one candidate domain:

```text
signal
source
latency
completeness
failure mode
historical availability
recording actor
```

---

## 4. Context Engine Specification

Specify:

```text
definition language
multi-window context
materialization
invalidation
late data
version tuple
cache strategy
operational vs interactive contexts
```

---

## 5. Baseline / Comparison Engine Specification

Specify:

```text
baseline types
phase-aware baselines
cold start
cohort priors
comparison methods
minimum evidence
```

---

## 6. Ops Queue UX Specification

The most important day-to-day product surface.

---

## 7. Investigation Workbench UX Specification

Timeline + Findings + evidence drilldown.

---

## 8. Domain Pack v0.1

Choose one initial domain only after buyer/data validation.

---

## 9. Regulatory Position Memo

With specialized counsel.

Focus on:

```text
provider-facing CDS boundary
ranking
monitors
claims language
independently reviewable basis
```

---

# 76. Open Questions for v0.4

## Buyer

- Which provider-side role owns the queue?
- What is the first organization type that will pay?
- What existing workflow does the queue replace?
- What action most commonly closes a case?

## Domain

- Which first domain provides the best combination of data and operational pain?
- Can that domain prove the platform without bespoke architecture?

## Statistics

- What is the minimum evidence model for single-subject analysis?
- How should Difference Clusters be ranked?
- When should the product decline to produce Findings?
- What cohort-matching strategy is adequate for MVP?

## Context

- Which contexts should be precomputed?
- Which dimensions should be materialized?
- Which dimensions should remain query-time?
- What context invalidation policy gives acceptable cost?

## Workflow

- Should a queue item always have a precomputed Finding?
- Can “insufficient evidence” itself be a useful queue reason?
- How should actions sync back into EHR/care systems?

## Privacy

- What group-size thresholds apply by output type?
- Which analytical dimensions need additional restrictions?
- How should cross-organization benchmarking work, if ever?

---

# 77. Final Product Positioning

The company is not building a personal health dashboard.

It is not building another disease app.

It is building:

# **Observability infrastructure for healthcare providers.**

The product monitors longitudinal health systems, surfaces meaningful changes, and gives provider teams the tools to investigate those changes with the same kind of rigor that modern software teams use to investigate production systems.

The provider should be able to move from:

```text
Something changed.
```

to:

```text
Here is what was different.
Here is how strong the evidence is.
Here is whether the measurement itself changed.
Here is the exact underlying data.
```

without reconstructing the story manually across disconnected systems.

That is the product.

---

# 78. Founding Principle

> **When something changes, show me what was different. Then show me the evidence.**

The rest of the architecture exists to make sure the evidence deserves the sentence.
