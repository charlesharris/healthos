# Human Observability Platform
## Signal → Case Specification — v0.1
### Rails-First Reference Implementation

**Status:** Pre-implementation design  
**Reference domain:** Hypertension remote monitoring  
**Platform scope:** Domain-neutral provider health observability  
**Implementation assumption:** Ruby on Rails modular monolith, PostgreSQL, background jobs, server-rendered/Hotwire provider UI

---

# 1. Purpose

This document defines the boundary between **raw longitudinal health telemetry** and the **provider work represented in the Ops Queue**.

The central question is:

> **When should one or more machine-detected signals become one unit of human work?**

The platform must avoid reproducing the failure mode of traditional alerting systems, where every threshold crossing becomes a separate item that somebody must manually dismiss.

The intended flow is:

```text
Telemetry
   ↓
Derived Signals
   ↓
Monitors
   ↓
Signals
   ↓
Case Correlation
   ↓
Case
   ↓
Context / Baseline / Comparison
   ↓
Findings
   ↓
Ops Queue
   ↓
Provider disposition / action
```

A **Signal** is cheap and machine-generated.

A **Case** is expensive because it represents a potential unit of provider work.

The system should generate many Signals and relatively few Cases.

---

# 2. Rails-First Architecture Decision

The first implementation should be a Rails application, not a Rails frontend placed in front of a Go service.

## 2.1 Why Rails is the right v1 choice

The initial product is dominated by:

- relational domain modeling,
- workflow state,
- provider UX,
- auditability,
- background processing,
- business rules,
- tenant isolation,
- integrations,
- and rapid iteration with clinical users.

Those are all areas where Rails is unusually productive.

The early system is **not** dominated by:

- millions of events per second,
- sub-millisecond analytical queries,
- a globally distributed collector,
- or CPU-heavy numerical computation.

Therefore the default architecture should be:

```text
Rails
  +
PostgreSQL
  +
Background jobs
  +
Redis only where justified
  +
Object storage for immutable/raw payloads
  +
Hotwire / Turbo / Stimulus
```

If an individual subsystem later develops materially different scaling needs, it can be extracted behind an existing application boundary.

Potential future extraction candidates include:

```text
high-volume ingestion
context materialization
large cohort analytics
specialized statistical computation
external collector / SDK
```

But extraction is a response to measured load, not a prerequisite.

---

# 3. Application Shape

Use a **modular monolith**.

Conceptual namespaces:

```text
app/
  models/

  domains/
    telemetry/
    monitoring/
    cases/
    context/
    comparison/
    findings/
    investigations/
    cohorts/
    workflows/
    provenance/
    audit/

  jobs/

  controllers/
    ops/
    investigations/
    admin/

  views/
    ops/
    investigations/
    admin/

  javascript/
    controllers/

config/
  domain_packs/

lib/
  domain_packs/
```

Do not begin with Rails Engines.

Use ordinary Ruby namespaces and explicit public interfaces.

If package boundaries become difficult to maintain, introduce stronger dependency tooling later.

---

# 4. Foundational Terminology

## Observation

A measured or reported value.

```text
blood pressure
weight
glucose
temperature
pain score
```

## Event

A discrete occurrence.

```text
medication administered
visit completed
device changed
measurement missed
```

## DerivedSignal

A reproducible calculation from canonical telemetry.

```text
7-day systolic mean
28-day BP variability
measurement-frequency delta
recovery slope
```

## Monitor

A versioned rule that evaluates telemetry or derived signals.

```text
trajectory changed
measurement stopped
threshold crossed
source changed
```

## Signal

An immutable record that a Monitor observed something potentially meaningful.

## Case

A stateful provider-side work object representing one coherent issue or investigation.

## Finding

An evidence-backed, inspectable description of what differs within a Case.

## Investigation

A pinned analytical snapshot used to examine a Case in depth.

---

# 5. Architectural Invariant

> **Signals describe machine observations. Cases describe human work.**

This means:

- Signals are append-only.
- A Signal is never “edited into” a Case.
- Multiple Signals can belong to one Case.
- A Case can remain open while new Signals arrive.
- Case state can change.
- Case history is auditable.
- Closing a Case does not delete or rewrite its Signals.

---

# 6. Signal Model

A Signal should be immutable after creation except for operational metadata that does not change its meaning.

Conceptual Rails model:

```ruby
class Monitoring::Signal < ApplicationRecord
  belongs_to :organization
  belongs_to :subject
  belongs_to :monitor_definition
  belongs_to :source_record, polymorphic: true, optional: true

  has_many :case_signals,
    class_name: "Cases::CaseSignal",
    dependent: :restrict_with_exception

  has_many :cases,
    through: :case_signals

  enum :signal_type, {
    threshold_excursion: "threshold_excursion",
    trajectory_change: "trajectory_change",
    variability_change: "variability_change",
    measurement_change: "measurement_change",
    source_change: "source_change",
    workflow_event: "workflow_event",
    data_quality_change: "data_quality_change"
  }

  validates :detected_at, presence: true
  validates :window_started_at, presence: true
  validates :deduplication_key, presence: true, uniqueness: {
    scope: :organization_id
  }
end
```

---

# 7. Signal Fields

Minimum conceptual fields:

```text
id

organization_id
subject_id

monitor_definition_id
monitor_definition_version

signal_type
domain_key

detected_at

window_started_at
window_ended_at

severity
confidence/evidence metadata if applicable

source_record_type
source_record_id

deduplication_key

payload / structured attributes

created_at
```

The Signal's `payload` may be JSONB, but the meaning of fields is governed by the Monitor and domain pack.

Do not turn the Signal table into an unstructured junk drawer.

---

# 8. Signal Idempotency

Every monitor evaluation must produce a deterministic deduplication key.

Example:

```text
organization
subject
monitor definition
monitor version
evaluation window
semantic event identity
```

Conceptually:

```ruby
Digest::SHA256.hexdigest(
  [
    organization.id,
    subject.id,
    monitor.key,
    monitor.version,
    window.start.iso8601,
    window.finish.iso8601,
    semantic_identity
  ].join(":")
)
```

Repeated background jobs must not create duplicate Signals.

Database uniqueness is the final authority.

---

# 9. Signals Are Append-Only Evidence

If a monitor's logic changes:

```text
blood_pressure_trajectory.v1
→
blood_pressure_trajectory.v2
```

do not rewrite old Signals.

New evaluations produce Signals tied to v2.

A historical Case may therefore contain Signals produced by multiple Monitor versions.

This is acceptable and must remain inspectable.

---

# 10. Monitor Model

A Monitor is a versioned definition that decides whether a Signal should exist.

Conceptual interface:

```ruby
module Monitoring
  class Monitor
    Result = Data.define(
      :triggered,
      :signal_type,
      :window,
      :severity,
      :attributes,
      :semantic_identity
    )

    def evaluate(subject:, as_of:)
      raise NotImplementedError
    end
  end
end
```

A Monitor must not create Cases directly.

Its responsibility ends at:

```text
condition evaluated
→
Signal persisted
```

This separation is essential.

---

# 11. Monitor Categories

The platform should support at least four broad categories.

## Protocol monitors

Customer-authored or domain-defined deterministic rules.

```text
measurement above configured threshold
measurement below configured threshold
critical lab
expected event absent
```

## Trajectory monitors

Detect meaningful changes over time.

```text
BP mean shifted
recovery slope changed
weight velocity changed
glucose variability changed
```

## Observability monitors

Detect problems in how health is being measured.

```text
device stopped reporting
source changed
manual-entry rate changed
measurement frequency decreased
data completeness degraded
```

## Care-operation monitors

Detect care workflow changes.

```text
follow-up missed
medication-access event
care-plan event absent
refill delay
```

---

# 12. Monitor Execution

The MVP should not require a general stream-processing engine.

Use background jobs.

Typical flow:

```text
Canonical telemetry committed
        ↓
transactional outbox/event record
        ↓
MonitorEvaluationJob
        ↓
evaluate relevant monitor set
        ↓
persist Signals
        ↓
CaseCorrelationJob
```

Avoid running expensive monitor logic in HTTP request transactions.

---

# 13. Domain Pack Monitor Registry

Domain packs register monitors.

Example:

```ruby
module DomainPacks
  module Hypertension
    class Definition
      def monitors
        [
          Monitors::SystolicThreshold,
          Monitors::BloodPressureTrajectory,
          Monitors::BloodPressureVariability,
          Monitors::MeasurementFrequency,
          Monitors::MeasurementSourceChange
        ]
      end
    end
  end
end
```

The platform core should not know what systolic blood pressure means.

---

# 14. Case Model

A Case is the central unit of the Ops Queue.

Conceptual Rails model:

```ruby
class Cases::Case < ApplicationRecord
  belongs_to :organization
  belongs_to :subject
  belongs_to :owner, class_name: "User", optional: true

  has_many :case_signals,
    class_name: "Cases::CaseSignal",
    dependent: :restrict_with_exception

  has_many :signals,
    through: :case_signals,
    source: :signal

  has_many :case_events,
    class_name: "Cases::CaseEvent",
    dependent: :restrict_with_exception

  has_many :findings,
    class_name: "Findings::Finding",
    dependent: :restrict_with_exception

  enum :status, {
    new_case: "new",
    triaged: "triaged",
    investigating: "investigating",
    watching: "watching",
    waiting_external: "waiting_external",
    resolved: "resolved",
    dismissed: "dismissed"
  }

  enum :review_priority, {
    now: "now",
    today: "today",
    routine: "routine",
    watch: "watch"
  }
end
```

Avoid `type` as a column name because of Rails STI.

Use `case_type`.

---

# 15. Case Fields

Minimum conceptual fields:

```text
id

organization_id
subject_id

domain_key
case_type

title
summary

status
review_priority

owner_id

started_at
detected_at
last_signal_at

evidence_level
data_quality_state
baseline_maturity

active_context_id
active_comparison_id

last_reviewed_at
watch_until

resolved_at
resolution_code

lock_version

created_at
updated_at
```

`lock_version` enables optimistic locking for concurrent operator updates.

---

# 16. CaseSignal Join

Signals attach to Cases through an explicit join record.

```ruby
class Cases::CaseSignal < ApplicationRecord
  belongs_to :case,
    class_name: "Cases::Case"

  belongs_to :signal,
    class_name: "Monitoring::Signal"

  enum :relationship, {
    trigger: "trigger",
    supporting: "supporting",
    contextual: "contextual",
    reopening: "reopening"
  }
end
```

Unique constraint:

```text
case_id + signal_id
```

A Signal may attach to more than one Case only if a future domain genuinely requires it.

For MVP, prefer a single primary Case.

---

# 17. CaseEvent Audit Stream

Every meaningful Case transition should create an append-only CaseEvent.

Examples:

```text
case_created
signal_attached
priority_changed
assigned
triaged
investigation_started
watch_started
watch_condition_met
reopened
disposition_recorded
resolved
dismissed
external_action_created
```

Conceptual model:

```ruby
class Cases::CaseEvent < ApplicationRecord
  belongs_to :case,
    class_name: "Cases::Case"

  belongs_to :actor,
    polymorphic: true,
    optional: true

  validates :event_type, presence: true
  validates :occurred_at, presence: true
end
```

Payload may hold transition-specific details.

This is the authoritative operational timeline.

---

# 18. Do Not Use Callbacks for Core Workflow

Avoid:

```ruby
after_create :correlate_case
after_update :recompute_findings
```

for important domain workflows.

Use explicit command/service objects and transaction boundaries.

Example:

```ruby
Cases::AttachSignal.call(signal:)
```

or:

```ruby
Cases::CorrelateSignal.call(signal:)
```

Callbacks may support local model concerns but should not hide workflow orchestration.

---

# 19. Case Correlation

When a Signal arrives, the Case Correlation system answers:

> **Does this Signal represent new work, or is it evidence about work already in progress?**

MVP correlation must be deterministic.

No embeddings.

No LLM.

No unsupervised clustering.

---

# 20. Correlation Inputs

The correlation engine can consider:

```text
organization
subject
domain
signal family
case type compatibility
signal time window
active Case time window
Case status
domain-pack rule
```

It should not use arbitrary clinical inference.

---

# 21. Default Correlation Algorithm

```text
Signal arrives
      ↓
Find active Cases for same subject
      ↓
Filter same domain
      ↓
Filter statuses eligible for correlation
      ↓
Filter overlapping or nearby windows
      ↓
Apply domain-pack compatibility rules
      ↓
Exactly one compatible Case?
   /                  \
 yes                  no
  ↓                    ↓
attach             create Case
```

If several Cases are equally eligible, conservative behavior is:

```text
create a new Case
+
record correlation ambiguity
```

Do not silently merge unrelated work.

---

# 22. Correlation Window

Each case type may define a correlation window.

Example hypertension rules:

```text
blood_pressure_change:
  attach related BP signals occurring within
  the active Case window plus 72 hours

monitoring_interruption:
  attach device/measurement Signals within
  the same interruption episode
```

This belongs in the domain pack.

---

# 23. Correlation Rule Interface

Conceptual Ruby:

```ruby
module Cases
  class CorrelationRule
    Match = Data.define(:matches, :score, :reason)

    def match?(signal:, case_record:)
      raise NotImplementedError
    end
  end
end
```

For MVP, `score` can remain an ordinal deterministic value rather than an ML probability.

Example:

```text
exact
compatible
weak
none
```

Only `exact` or `compatible` auto-attach.

---

# 24. Hypertension Reference Correlation Rules

Domain:

```text
hypertension
```

Case types:

```text
blood_pressure_change
monitoring_interruption
care_gap
```

Compatible Signal mapping:

```text
blood_pressure_change

  threshold_excursion
  trajectory_change
  variability_change

monitoring_interruption

  measurement_change
  source_change
  data_quality_change

care_gap

  workflow_event
```

---

# 25. Correlated Observability Signals

Suppose a BP trajectory change and a source change occur simultaneously.

Do not necessarily create:

```text
Case 1: BP changed
Case 2: Device source changed
```

Instead the domain rule can attach source-change Signals as contextual evidence to the active BP-change Case.

Example:

```text
Case:
Blood-pressure trajectory changed

Signals:
- trajectory_change           trigger
- threshold_excursion         supporting
- source_change               contextual
```

The later Finding may say:

> Measurement method changed at the same time as the apparent trajectory shift.

This avoids duplicate work.

---

# 26. When to Keep Cases Separate

Separate Cases when they represent distinct provider workflows.

Example:

```text
Case:
Blood pressure trajectory changed
→ clinical team

Case:
Connected cuff offline
→ device support
```

If both require independent ownership or dispositions, they may remain separate even if temporally related.

This is a domain/workflow decision, not purely an analytical decision.

---

# 27. Case Creation

If no compatible active Case exists:

```ruby
Cases::CreateFromSignal.call(signal:)
```

Responsibilities:

1. determine case type,
2. determine initial title,
3. determine initial review priority,
4. create Case,
5. attach trigger Signal,
6. write CaseEvent,
7. enqueue Context/Comparison generation,
8. enqueue routing evaluation.

All database changes for Case + initial attachment + audit event occur in one transaction.

---

# 28. Concurrency Safety

Several Signals for the same subject may arrive simultaneously.

This must not create three Cases.

Use database-backed serialization for correlation.

Possible Rails/Postgres strategy:

```text
transaction
  ↓
obtain subject/domain advisory lock
  ↓
re-read active Cases
  ↓
correlate
  ↓
attach or create
commit
```

Alternatively lock an explicit subject-domain correlation row.

Do not rely only on Ruby mutexes.

The database is the source of truth.

---

# 29. Idempotent Correlation

`Cases::CorrelateSignal` must be safely retryable.

Before doing work:

```text
Does Signal already have its primary Case?
```

If yes:

```text
return existing Case
```

The job system may execute at least once.

Correctness cannot depend on exactly-once delivery.

---

# 30. Case Mutation From New Signals

A new Signal can change:

```text
last_signal_at
review priority
Case summary
data-quality state
context freshness
Finding freshness
```

It does not overwrite historical state.

Each change creates CaseEvents as appropriate.

Example:

```text
09:00 Case created — Routine
11:22 second threshold Signal attached
11:22 priority escalated — Today
```

---

# 31. Priority Is Policy, Not Evidence

`review_priority` and `evidence_level` are independent.

Example:

```text
Review priority:
NOW

Evidence:
WEAK
```

could be valid if a customer protocol requires immediate review of a particular measurement even without sufficient longitudinal context.

Conversely:

```text
Review priority:
ROUTINE

Evidence:
STRONG
```

may be valid for a nonurgent instrumentation change.

---

# 32. Priority Policy Interface

Conceptual Ruby:

```ruby
module Cases
  class PriorityPolicy
    def priority_for(case_record:, organization:)
      raise NotImplementedError
    end
  end
end
```

Policy inputs may include:

```text
customer protocol
case type
Signal severity
Case age
current state
program
```

Avoid opaque machine-learned “risk scores” in MVP.

Every priority should have explainable reasons.

Store those reasons.

---

# 33. Case Routing

Routing determines ownership or queue membership.

Inputs:

```text
domain
program
case type
organization
priority
care team
facility/location
customer rules
```

Outputs:

```text
queue
owner
team
external destination
```

Routing and clinical interpretation are separate.

---

# 34. Case Lifecycle

Recommended states:

```text
new
triaged
investigating
watching
waiting_external
resolved
dismissed
```

Do not create dozens of states initially.

Use CaseEvents and dispositions for detail.

---

# 35. State Transitions

Recommended transitions:

```text
new
 ├─→ triaged
 ├─→ watching
 ├─→ investigating
 └─→ dismissed

triaged
 ├─→ investigating
 ├─→ watching
 ├─→ waiting_external
 ├─→ resolved
 └─→ dismissed

investigating
 ├─→ watching
 ├─→ waiting_external
 ├─→ resolved
 └─→ dismissed

watching
 ├─→ triaged
 ├─→ investigating
 ├─→ resolved
 └─→ dismissed

waiting_external
 ├─→ triaged
 ├─→ investigating
 ├─→ resolved
 └─→ dismissed

resolved
 └─→ reopened through explicit workflow
```

---

# 36. Explicit Transition Objects

Do not spread state changes around controllers.

Example:

```ruby
Cases::Transitions::StartWatching.call(
  case_record:,
  actor:,
  until_at:,
  reason:
)
```

Each transition object:

1. validates transition,
2. updates Case,
3. writes CaseEvent,
4. schedules any required work,
5. returns result.

---

# 37. Watch State

Watching means:

> Human review has occurred, but current evidence does not justify closure or immediate action.

A watch rule can define reevaluation triggers.

Example:

```text
Re-evaluate when:

3 additional measurements arrive
OR
trajectory deviation exceeds 20%
OR
72 hours elapse
```

Persist the watch condition.

---

# 38. Watch Rule Model

Conceptually:

```text
case_id
condition_type
condition_attributes
expires_at
created_by
created_at
satisfied_at
```

MVP can support a small set:

```text
time_elapsed
new_observation_count
new_signal
threshold_crossed
```

No general rules language needed yet.

---

# 39. Watch Reevaluation

Relevant new telemetry triggers:

```text
WatchEvaluationJob
```

When condition satisfied:

```text
Case:
watching → triaged
```

or:

```text
watching → new
```

depending on UX preference.

Write:

```text
watch_condition_met
```

CaseEvent.

---

# 40. Resolution

Resolution means the unit of work is complete.

Resolution should require a disposition code.

Example disposition categories:

```text
action_taken
expected_change
instrumentation_issue
data_quality_issue
already_known
not_actionable
insufficient_evidence
duplicate
false_positive
escalated_external
```

Keep category list customer-extensible only after we understand reporting requirements.

---

# 41. Disposition Model

Prefer a separate record over a few nullable Case columns.

```ruby
class Cases::Disposition < ApplicationRecord
  belongs_to :case,
    class_name: "Cases::Case"

  belongs_to :actor,
    class_name: "User"

  validates :code, presence: true
  validates :disposed_at, presence: true
end
```

Fields:

```text
code
notes
action_type
external_reference
disposed_at
```

The disposition becomes valuable product feedback.

---

# 42. Actions

The Human Observability Platform should not become a full care-management system.

Actions can include:

```text
assign internally
create external task
send webhook
create/update FHIR Task
deep-link into EHR
record "provider notified"
record "device support requested"
```

The Case tracks that an action occurred.

Execution may belong to an adapter.

---

# 43. Resolution Feedback Loop

Aggregate dispositions can measure monitor quality.

Example:

```text
Monitor:
bp_trajectory_change.v3

Cases:
1,240

Action taken:              58%
Expected/no action:        18%
Instrumentation issue:     11%
Insufficient evidence:      7%
False positive:             6%
```

This creates:

> **observability of the monitoring program itself.**

That is a major B2B value proposition.

---

# 44. Reopening

A resolved Case should not silently reopen whenever another similar Signal occurs.

Domain pack defines a reopening window.

Example:

```text
same BP-change Case
resolved 12 hours ago
new compatible trajectory Signal
→ reopen

same Case
resolved 30 days ago
→ create new Case
```

Reopening creates:

```text
CaseEvent: reopened
CaseSignal relationship: reopening
```

and clears `resolved_at`.

The previous disposition remains historical.

---

# 45. Case Correlation Across Resolved Cases

Search order:

```text
1. active Cases
2. recently resolved Cases eligible for reopening
3. create new Case
```

Do not search unlimited history.

The domain pack defines reopen horizon.

---

# 46. Context and Comparison Trigger

A Case should become useful quickly.

On creation or materially significant Signal attachment:

```text
Case
  ↓
ContextMaterializationJob
  ↓
DefaultBaselineJob
  ↓
ComparisonJob
  ↓
FindingGenerationJob
```

This chain should be asynchronous.

The Ops Queue can initially show:

```text
Evidence analysis pending…
```

rather than blocking Case creation.

---

# 47. Case Freshness

Store analysis freshness.

Example:

```text
analysis_status:
pending
current
stale
failed
insufficient
```

And:

```text
analysis_as_of
```

When new telemetry arrives:

```text
current → stale
```

A new computation returns it to:

```text
current
```

---

# 48. Findings Do Not Own Case Truth

Findings are analytical artifacts.

They can change as evidence changes.

The Case remains the operational unit.

Example:

```text
09:00
Top Finding:
Measurement source changed

15:00
Late source data arrives

Top Finding:
No instrumentation difference detected
```

The live Case updates.

A saved Investigation remains pinned.

---

# 49. Finding Association

Conceptual:

```ruby
class Findings::Finding < ApplicationRecord
  belongs_to :case,
    class_name: "Cases::Case"

  belongs_to :comparison

  has_many :finding_differences
  has_many :differences,
    through: :finding_differences
end
```

Fields:

```text
finding_type
title
summary
evidence_level
rank
analysis_as_of
definition_version
```

---

# 50. Ops Queue Query Model

The default Queue query should be straightforward SQL.

Primary filters:

```text
organization
queue/team
status
review priority
owner
domain
case type
evidence level
data quality
age
```

Sort defaults:

```text
review priority
then SLA/age
then detected_at
```

Do not rank the entire queue with opaque AI.

---

# 51. Queue Read Model

MVP can query the normalized Case tables directly.

If the queue later becomes expensive, introduce a denormalized read model:

```text
ops_queue_entries
```

materialized from Cases.

Do not begin there unless needed.

---

# 52. Rails Ops Queue UI

Use server-rendered Rails with Hotwire.

The initial queue needs:

```text
filter bar
tabs/state counts
case rows
quick assignment
status updates
watch
bulk operations where safe
live row refresh
```

Turbo Streams are a natural fit for:

```text
Case analysis completed
Case priority changed
Case assigned
new Case arrived
```

No SPA is required for v1.

---

# 53. Case Row

Conceptual row:

```text
RECOVERY TRAJECTORY CHANGED
A. Smith · Post-op knee · 2h

Priority: TODAY
Evidence: STRONG
Data: GOOD

Top Finding:
Rehab activity pattern changed

PT: 3/wk → 1/wk
Activity: -38%

[Quick review] [Investigate]
```

The work reason should be visually primary.

The subject is secondary.

---

# 54. Quick Review

Clicking a Case should first open a fast triage panel/page.

Sections:

```text
Why is this here?
Top Findings
Evidence strength
Data quality
Recent timeline
Current owner
Suggested/available workflow actions
```

Then:

```text
Investigate →
```

opens the full Investigation Workbench.

Most Cases should not require the workbench.

---

# 55. Investigation Workbench in Rails

Rails can still own this UI.

Recommended approach:

```text
Rails HTML
Turbo Frames
Stimulus controllers
small JSON endpoints only where visualization requires them
```

Use Stimulus for:

```text
time-range selection
timeline brushing
baseline switching
dimension filtering
evidence panels
```

Do not introduce React solely because the workbench is interactive.

If one visualization later becomes too complex, it can be isolated as a JavaScript component without converting the entire app.

---

# 56. Hypertension Reference Example A — Clinical Change

Input:

```text
BP baseline:
132/82

Affected:
151/95

Device:
unchanged

Measurement method:
unchanged

Measurement cadence:
slightly decreased
```

Signals:

```text
trajectory_change
threshold_excursion
measurement_change
```

Correlation:

```text
one Case:
blood_pressure_change
```

Findings:

```text
Blood-pressure pattern changed      STRONG
Measurement behavior changed        MODERATE
Instrumentation changed             evidence against
```

Queue route:

```text
clinical RPM team
```

---

# 57. Hypertension Reference Example B — Instrumentation

Input:

```text
BP:
132 → 165

same date:
connected cuff → manual entry
```

Signals:

```text
trajectory_change
source_change
recording_method_change
```

Correlation:

```text
one Case:
blood_pressure_change
```

Top Finding:

```text
Measurement method changed          STRONG
```

Possible route:

```text
monitoring/device support
```

depending on customer policy.

---

# 58. Hypertension Reference Example C — Insufficient Evidence

Input:

```text
affected period:
3 measurements

baseline:
2 usable measurements
```

Signal:

```text
possible trajectory_change
```

Case:

```text
possible_blood_pressure_change
```

Finding:

```text
No reliable distinguishing pattern
Evidence: INSUFFICIENT
```

Default disposition/state:

```text
watching
```

Watch condition:

```text
3 additional valid measurements
```

---

# 59. Rails Transaction Boundaries

Important operations should have explicit transactions.

## Signal creation

```text
persist Signal
persist outbox event
commit
```

## Case creation

```text
lock correlation scope
create Case
create CaseSignal
create CaseEvent
commit
```

## Signal attachment

```text
lock Case
create CaseSignal
update Case metadata
create CaseEvent
commit
```

## State transition

```text
lock Case
validate transition
update Case
create CaseEvent
optional Disposition
commit
```

External API calls occur **after commit**, from jobs.

Never hold a database transaction open while calling an EHR or webhook.

---

# 60. Transactional Outbox

Use a transactional outbox/event table for reliable internal side effects.

Conceptual:

```text
domain_events

id
organization_id
aggregate_type
aggregate_id
event_type
payload
occurred_at
processed_at
```

Example:

```text
monitoring.signal_created
cases.case_created
cases.signal_attached
cases.case_resolved
```

A dispatcher job reads unpublished events and enqueues downstream work.

This avoids subtle “database committed but job enqueue failed” states.

---

# 61. Background Job Strategy

The application needs durable jobs for:

```text
source ingestion
normalization
monitor evaluation
signal correlation
context materialization
baseline calculation
comparison
finding generation
watch evaluation
external workflow delivery
notification
```

The domain logic must remain callable independently of the job adapter.

Jobs should be thin wrappers.

Example:

```ruby
class Cases::CorrelateSignalJob < ApplicationJob
  def perform(signal_id)
    signal = Monitoring::Signal.find(signal_id)
    Cases::CorrelateSignal.call(signal:)
  end
end
```

---

# 62. Job Idempotency

Every job must tolerate retry.

Examples:

```text
normalization:
unique source identity

Signal:
deduplication_key

CaseSignal:
unique case + signal

Context:
definition/version/as-of identity

Comparison:
affected/baseline/method identity

external actions:
idempotency key
```

At-least-once execution is assumed everywhere.

---

# 63. Failure Handling

A failed analysis should not make the Case disappear.

Queue example:

```text
BP trajectory changed

Evidence analysis:
FAILED

Case remains:
TODAY

[Retry analysis]
```

Analysis failures are operationally distinct from insufficient evidence.

---

# 64. Database Constraints

Use PostgreSQL constraints aggressively.

Examples:

```text
foreign keys
not null
unique deduplication keys
check constraints for bounded enums where useful
unique case-signal links
unique active disposition where appropriate
```

Correctness should not live only in Rails validations.

---

# 65. Tenant Isolation

Every relevant table carries `organization_id` either directly or through an enforceable ownership chain.

For high-risk tables, carrying it directly simplifies:

```text
queries
indexes
audits
defense in depth
```

Application scopes must not be the only isolation mechanism.

A later deployment may add PostgreSQL row-level security after the access model is proven, but the schema should not make that difficult.

---

# 66. Provider Audit Requirements

Audit:

```text
Case viewed
Investigation viewed
Evidence expanded
Assignment changed
Status changed
Disposition entered
External action initiated
Sensitive export performed
```

Do not dump PHI into free-form technical logs.

Clinical access auditing is a separate domain from application logging.

---

# 67. Case Timeline

The provider-visible Case timeline combines:

```text
Signals
CaseEvents
Investigation creation
Findings updates
Actions
Disposition
```

Do not mutate historical timeline items.

---

# 68. Platform vs Domain Responsibilities

## Platform owns

```text
Signal persistence
Case lifecycle
Case correlation framework
queue
assignment
watching
dispositions
Context engine
Baseline engine
Comparison engine
Finding infrastructure
audit
workflow adapters
```

## Domain pack owns

```text
health semantics
monitor definitions
case types
correlation compatibility
correlation windows
reopening windows
context definitions
baseline defaults
Finding groups
minimum evidence
routing defaults
```

This boundary is critical to remaining a general health-observability platform.

---

# 69. Domain Pack Ruby Interface

Conceptual:

```ruby
module DomainPacks
  class Definition
    def key
      raise NotImplementedError
    end

    def monitors
      []
    end

    def case_types
      []
    end

    def correlation_rules
      []
    end

    def context_definitions
      []
    end

    def baseline_definitions
      []
    end

    def finding_definitions
      []
    end
  end
end
```

Registry:

```ruby
DomainPacks.register(
  DomainPacks::Hypertension::Definition.new
)
```

Do not make domain packs separate deployables initially.

---

# 70. Suggested Rails Service Objects

Likely core objects:

```text
Monitoring::EvaluateMonitors
Monitoring::CreateSignal

Cases::CorrelateSignal
Cases::CreateFromSignal
Cases::AttachSignal
Cases::RecalculatePriority
Cases::Route
Cases::Reopen

Cases::Transitions::Triage
Cases::Transitions::StartInvestigation
Cases::Transitions::StartWatching
Cases::Transitions::Resolve
Cases::Transitions::Dismiss

Context::Materialize
Baselines::ResolveDefault
Comparisons::Run
Findings::Generate

Workflows::DispatchAction
```

Each object should have a narrow, testable contract.

---

# 71. Testing Strategy

This product should have unusually strong domain tests.

## Unit tests

```text
monitor rules
correlation rules
priority policies
state transitions
watch conditions
baseline selection
Finding grouping
```

## Integration tests

```text
telemetry → Signal
Signal → Case
multiple Signals → one Case
concurrent Signals → one Case
Case → analysis
watch → reactivation
resolution → reopen
```

## Property/invariant tests

Useful invariants:

```text
Signal never loses provenance
Signal attaches idempotently
resolved Case history remains intact
saved Investigation never mutates
CaseEvent sequence is append-only
```

## System tests

Provider workflows through Rails UI.

---

# 72. Reference Acceptance Scenario

Given:

```text
Patient has stable BP measurements for 28 days.
```

When:

```text
5 elevated measurements arrive over 7 days,
measurement cadence decreases slightly,
device source remains unchanged.
```

Then:

```text
multiple Signals may be created
```

but:

```text
exactly one active blood_pressure_change Case exists.
```

And the Case:

```text
contains all compatible Signals,
has one provider-visible queue item,
has review priority determined by policy,
has evidence analysis generated asynchronously,
shows source stability as part of evidence,
can be watched, assigned, investigated, or resolved.
```

---

# 73. Reference Concurrency Scenario

Given:

```text
three Monitor jobs emit compatible Signals
within milliseconds.
```

When:

```text
all three correlation jobs execute concurrently.
```

Then:

```text
the database contains one Case,
three CaseSignal links,
and a complete CaseEvent history.
```

This is a must-pass implementation test.

---

# 74. Reference Reopening Scenario

Given:

```text
Case resolved yesterday:
expected_change
```

When:

```text
a compatible trajectory Signal arrives
within the domain reopening window.
```

Then:

```text
the Case reopens,
the Signal attaches with relationship=reopening,
the old disposition remains historically visible,
and a CaseEvent records the reopen.
```

---

# 75. Reference New-Episode Scenario

Given:

```text
a similar Case was resolved 45 days ago.
```

When:

```text
a new trajectory Signal arrives outside
the reopening horizon.
```

Then:

```text
a new Case is created.
```

The platform preserves longitudinal Case history without conflating separate episodes.

---

# 76. What Not to Build Yet

Do not build:

```text
ML Case correlation
LLM Case correlation
generic BPM/workflow engine
microservices
Kafka
ClickHouse
Elasticsearch for the queue
React SPA
custom event-stream platform
dynamic end-user rules language
automatic diagnosis
automatic clinical prioritization model
```

All are possible later.

None is required to prove the product.

---

# 77. First Implementation Slice

A very small vertical slice should prove:

```text
Rails app
   ↓
Organization + Subject
   ↓
BP Observation ingestion
   ↓
one DerivedSignal
   ↓
one Monitor
   ↓
Signal
   ↓
Case correlation
   ↓
Case
   ↓
Ops Queue row
```

No Context Engine yet.

No Difference Explorer yet.

This proves the operational spine.

---

# 78. Second Slice

Add:

```text
multiple monitors
multiple Signals
one correlated Case
priority policy
Case lifecycle
assignment
CaseEvent timeline
disposition
```

At this point we can manually operate a fake hypertension population.

---

# 79. Third Slice

Add:

```text
Context Engine
default baseline
Comparison
Difference
Finding
```

Queue rows begin showing:

```text
Top Finding
Evidence strength
Data quality
```

This is where the product begins differentiating from alert management.

---

# 80. Fourth Slice

Add:

```text
Quick Review
Investigation Workbench
baseline switching
evidence inspector
saved Investigation
```

Now the Honeycomb-inspired model is visible.

---

# 81. Fifth Slice

Add:

```text
FHIR/customer source adapter
historical import
real provider workflow action
pilot telemetry
```

This becomes pilot-capable.

---

# 82. Implementation Recommendation

Build the product as Rails until Rails gives us a measured reason not to.

The expected v1 architecture is:

```text
Rails modular monolith
PostgreSQL
Hotwire
background jobs
object storage
standard observability
```

The product's difficult work lies in:

```text
correct domain boundaries
Case semantics
trustworthy comparisons
provider workflow
reproducibility
```

not in choosing a systems language.

A future Go component should be introduced only when a particular subsystem benefits materially from:

```text
independent scaling
streaming throughput
lower memory usage
binary distribution
collector deployment
or specialized concurrency
```

If that day arrives, Rails should remain the product/control plane and the extracted service should sit behind a narrow interface.

---

# 83. Next Design Artifact

With Signal → Case defined, the next artifact should be:

# **Statistical Contract v0.1**

It should lock down the rules for:

```text
minimum evidence
unit of analysis
missingness
baseline maturity
small-n handling
multiple comparisons
autocorrelation
Difference ranking
Finding clustering
evidence-strength labels
```

Once that exists, the implementation plan can safely specify the Context, Comparison, and Finding subsystems without embedding statistically dangerous assumptions.

---

# 84. Final Principle

> **A Signal says that software noticed something.**

> **A Case says that the organization may need to do something.**

The entire Signal → Case subsystem exists to make the second statement rare, coherent, auditable, and useful.
