# Human Observability Platform
## Implementation Plan — v0.1
### Rails-First Provider Health Observability

**Status:** Pre-implementation / handoff-grade planning document  
**Date:** August 2026  
**Architecture:** Ruby on Rails modular monolith + PostgreSQL  
**Reference domain:** Hypertension remote monitoring  
**Product scope:** Domain-neutral B2B/provider-side longitudinal health observability  
**Primary daily surface:** Ops Queue  
**Primary deep-analysis surface:** Investigation Workbench  
**Patient-facing UX:** Explicitly out of scope

---

# 0. Why This Document Exists

This document is intended to be detailed enough to hand to another engineer or software-design agent for critique, decomposition, alternative proposals, implementation sequencing, and architectural review without requiring that reviewer to reconstruct the previous product discussion.

It consolidates and operationalizes the following companion documents:

1. `human-observability-design-v0.3-provider.md`
   - Product boundary
   - Provider-only/B2B posture
   - Context → Compare → Investigate model
   - Ops Queue as daily product
   - Domain packs
   - provenance/reproducibility invariants

2. `human-observability-signal-to-case-v0.1-rails.md`
   - Signals vs Cases
   - deterministic Case correlation
   - Case lifecycle
   - watch/reopen/resolution semantics
   - transactional outbox
   - Rails-first service/job boundaries
   - queue behavior

3. `human-observability-statistical-contract-v0.1.md`
   - missingness and measurement behavior
   - source/instrument compatibility
   - baseline maturity
   - minimum evidence gates
   - no p-value ranking for individual investigations
   - cohort FDR rules
   - Difference → Finding clustering
   - evidence-strength contract
   - reproducibility and simulation requirements

The implementation MUST preserve the contracts in those documents unless a deliberate design change is made, documented, versioned, and reviewed.

This is not merely a feature list.

It is the plan for implementing a product whose central promise is:

> **When something changes, show me what was different. Then show me the evidence.**

And whose statistical counterpart is:

> **The system does not owe the user an explanation. It owes the user an honest representation of the available evidence.**

---

# 1. Executive Summary

The Human Observability Platform is a provider-side operational system for teams that continuously monitor longitudinal health data across many patients.

The product is inspired by modern software observability—especially Honeycomb's exploratory investigation model—but the domain is healthcare rather than distributed software.

The platform receives longitudinal health telemetry from systems such as:

```text
EHR / FHIR
remote patient monitoring platforms
connected devices
device clouds
labs
pharmacy / medication systems
care-management systems
customer events
claims
historical batch imports
```

It normalizes those inputs into a canonical evidence-preserving model, derives reusable longitudinal signals, evaluates monitors, correlates machine-generated Signals into provider-facing Cases, precomputes contextual analysis, and surfaces a prioritized Ops Queue.

The user workflow is:

```text
Telemetry
    ↓
Canonical evidence
    ↓
Derived signals
    ↓
Monitors
    ↓
Signals
    ↓
Case correlation
    ↓
Cases
    ↓
Context
    ↓
Baseline
    ↓
Comparison
    ↓
Differences
    ↓
Findings
    ↓
Ops Queue / Quick Review
    ↓
Investigation Workbench
    ↓
Provider disposition / external action
```

The core distinction is:

> **A Signal says that software noticed something.**

> **A Case says that the organization may need to do something.**

The product should produce many Signals and relatively few Cases.

The primary commercial value is not “better charts.”

It is:

> **Reduce the clinical/operational effort required to identify which longitudinal changes deserve human attention and reconstruct what happened around them.**

---

# 2. Source-of-Truth Hierarchy

When implementation details conflict, use this precedence unless explicitly superseded:

```text
1. Safety / legal / regulatory requirements
2. Statistical Contract v0.1
3. Signal → Case Specification v0.1
4. Product & Architecture Design v0.3
5. This implementation plan
6. Convenience / framework convention
```

Rationale:

- statistical correctness outranks UI convenience;
- operational Case semantics outrank a shortcut in a controller;
- product invariants outrank optimization;
- framework conventions should be followed unless they violate a higher-level contract.

---

# 3. Hard Product Boundaries

## 3.1 This product IS

```text
provider-side
B2B
longitudinal
multi-source
evidence-preserving
investigation-oriented
queue-oriented
domain-neutral at platform level
specialty-aware through domain packs
```

## 3.2 This product IS NOT

```text
a patient app
a personal health dashboard
a coaching product
a telehealth platform
an EHR replacement
a prescribing system
a pharmacy
a billing system
an autonomous triage system
a diagnostic AI
a clinical risk-score generator
a causal-inference engine
```

## 3.3 External action boundary

The platform may:

```text
assign a Case
create a webhook
create an external task
create/update a FHIR Task
deep-link into another system
record that outreach/escalation occurred
```

It should not become a general care-management workflow engine in v0.1.

---

# 4. Reference Buyer and Operating Model

The reference customer is a provider organization running a centralized longitudinal-care operation.

Reference shape:

```text
4,500 monitored subjects
12 nurses / care managers
2 supervising clinicians
1 clinical operations director

Data:
connected devices
EHR/FHIR
medication records
encounters
care events
historical measurements
```

The user opens the product asking:

> **What needs human attention today?**

The user does not start from:

> “Show me Alice's dashboard.”

This drives the implementation:

```text
Ops Queue first
Quick Review second
Investigation Workbench third
Patient directory is secondary
```

---

# 5. Reference Domain

Hypertension remote monitoring is the engineering reference domain.

It is not a company-level product restriction.

It is chosen because it exercises:

```text
automatically generated longitudinal telemetry
provider-side monitoring
threshold signals
trajectory signals
measurement gaps
device/source changes
small-n comparisons
clear Case correlation
operational routing
```

Every platform-level abstraction must pass:

> **Would this still make sense if the reference domain became post-op recovery, diabetes, oncology, sleep medicine, or cardiology?**

If not, move the concept into the hypertension domain pack.

---

# 6. Technical Stack

## 6.1 Runtime

Recommended initial runtime:

```text
Ruby 3.4.x
Rails 8.1.x
```

At the time of this plan:

- Rails 8.1.3.1 is a current patched 8.1 release.
- Rails 8.1 supports Ruby 3.2+.
- Ruby 4 is available, but v0.1 intentionally chooses the more conservative Ruby 3.4 line to reduce major-version ecosystem risk.

Pin exact versions in:

```text
.ruby-version
Gemfile
Gemfile.lock
Dockerfile
CI
```

Upgrade deliberately rather than floating versions.

---

## 6.2 Database

Primary database:

```text
PostgreSQL
```

Target a currently supported managed PostgreSQL version.

Development/CI should track a modern supported release.

Do not introduce:

```text
ClickHouse
Cassandra
Kafka
Elasticsearch
Timescale
```

until measured workload demonstrates a need.

PostgreSQL remains:

```text
system of record
transaction coordinator
Case workflow store
canonical telemetry store
initial analytical store
```

---

## 6.3 Background jobs

Default:

```text
Active Job
+
Solid Queue
```

Reasoning:

- Rails-native
- durable
- PostgreSQL-backed
- avoids Redis as an initial requirement
- enough for v0.1 workload
- keeps domain logic adapter-independent

Prefer a separate queue database/connection in production-like environments so queue churn does not contend unnecessarily with health-data tables.

All jobs MUST be retry-safe.

The application MUST NOT rely on exactly-once delivery.

If measured workload later warrants Sidekiq or another adapter, domain services should not change.

---

## 6.4 Front end

Default:

```text
server-rendered Rails
Turbo
Turbo Frames
Turbo Streams where useful
Stimulus
```

No React SPA in v0.1.

Use JavaScript only for interactions that benefit from client state:

```text
timeline brushing
time-range selection
baseline switching
dimension filtering
evidence expansion
interactive plotting
```

Most business state remains server-owned.

---

## 6.5 Object storage

Use object storage for:

```text
raw source payloads
bulk imports
FHIR bundles
large evidence artifacts
exports
```

The relational database stores immutable metadata and object keys/hashes.

Active Storage is acceptable if it simplifies the first implementation, but raw evidence storage should remain conceptually independent from presentation-oriented attachment features.

---

## 6.6 Deployment reference

Reference deployment:

```text
containerized Rails web
containerized Rails job workers
managed PostgreSQL
object storage
managed load balancer / TLS
managed secrets
centralized technical logging
```

A likely production reference environment is AWS because it matches existing team experience, but the application architecture should not be AWS-specific.

Deployment/vendor compliance eligibility must be independently validated before processing real PHI.

---

# 7. Rails Architecture Style

Use a modular monolith.

Prefer ordinary Rails autoloading and Ruby namespaces rather than Rails Engines.

Recommended structure:

```text
app/
  models/
    identity/
    telemetry/
    monitoring/
    cases/
    analysis/
    findings/
    investigations/
    workflows/
    audit/

  services/
    ingestion/
    normalization/
    telemetry/
    monitoring/
    cases/
    context/
    baselines/
    comparisons/
    findings/
    investigations/
    workflows/

  jobs/
    ingestion/
    monitoring/
    cases/
    analysis/
    workflows/

  queries/
    ops/
    investigations/
    cohorts/

  controllers/
    ops/
    investigations/
    admin/
    api/v1/

  views/
    ops/
    investigations/
    admin/

  javascript/controllers/

  domain_packs/
    hypertension/

config/
  domain_packs/

spec/
  models/
  services/
  jobs/
  requests/
  system/
  support/
    synthetic_health/
```

Rationale:

- conventional Rails directories remain understandable;
- namespaces preserve domain boundaries;
- application logic does not accumulate in models/controllers;
- domain packs remain code/config, not independent deployments.

---

# 8. Core Architectural Invariants

The implementation must preserve these invariants.

## Evidence and provenance

1. Raw source truth is preserved.
2. Every canonical value has provenance.
3. Every derived value has exact lineage.
4. Every provider-facing Finding can be drilled into.
5. Every displayed statistical conclusion has an independently reviewable basis.

## Versioning and reproducibility

6. Normalizers are versioned.
7. semantic definitions are versioned.
8. derived-signal algorithms are versioned.
9. Context definitions are versioned.
10. Baseline definitions are versioned.
11. Comparison methods are versioned.
12. Finding definitions are versioned.
13. Saved Investigations pin evidence and versions.
14. New data never silently rewrites a saved Investigation.

## Measurement and statistics

15. Missing data remains visible.
16. Measurement behavior is itself observable.
17. Source changes are queryable dimensions.
18. No Difference ranking without minimum evidence.
19. Denominators are always available.
20. Repeated samples are not assumed independent.
21. individual investigations do not rank by p-value.
22. Correlated derivatives do not count as independent confirmations.
23. “No reliable distinguishing pattern found” is a successful output.

## Operations

24. Signals are append-only machine evidence.
25. Cases are stateful units of human work.
26. Case history is append-only/auditable.
27. Review Priority is independent from Evidence Strength.
28. Case correlation is deterministic in v0.1.
29. jobs are retry-safe.
30. important cross-step side effects use explicit transaction/outbox semantics.

## Security/product boundary

31. Tenant boundaries exist below the UI layer.
32. PHI is prohibited in ordinary technical logs/traces.
33. AI never becomes canonical truth.
34. temporal association is not causation.
35. platform code contains no disease-specific assumptions.

---

# 9. End-to-End Data Flow

```text
External source
    ↓
Ingestion adapter
    ↓
RawEnvelope persisted
    ↓
Raw payload stored
    ↓
Normalizer
    ↓
Canonical Observation / Event / Interval
    ↓
Provenance recorded
    ↓
DerivedSignal generation
    ↓
Monitor evaluation
    ↓
Signal
    ↓
Case correlation
    ↓
Case
    ↓
Context materialization
    ↓
Baseline resolution
    ↓
Comparison
    ↓
Differences
    ↓
Findings
    ↓
Case analysis pointer updated
    ↓
Ops Queue row updated
    ↓
Provider Quick Review
    ↓
Optional Investigation
    ↓
Disposition / workflow action
```

Each arrow should correspond to an explicit service/job boundary, not an ActiveRecord callback chain.

---

# 10. Identity, Tenancy, and Subject Boundary

## 10.1 Organization

`Organization` is the tenant root.

Every high-risk operational/health table should carry `organization_id` directly even if derivable through another association.

Benefits:

```text
tenant-safe indexes
simple audit queries
defense in depth
future RLS
less accidental cross-tenant joining
```

---

## 10.2 User and membership

Suggested model:

```text
users
organization_memberships
teams
team_memberships
```

Membership owns:

```text
organization
role
status
permissions/profile
```

Do not put one global `role` field directly on User.

A user may eventually belong to multiple organizations.

---

## 10.3 Subject

Use `Subject`, not `Patient`, as the core platform entity.

Why:

- domain-neutral;
- avoids implying our system owns the complete clinical Patient concept;
- maps cleanly to external Patient/member/person IDs.

Suggested split:

```text
subjects
subject_identities
subject_identifiers
```

`subjects`:

```text
id
public_id
organization_id
status
timezone
created_at
updated_at
```

`subject_identities`:

```text
subject_id
display_name
first_name
last_name
dob
other PHI fields
```

Identity fields should use application-level encryption where appropriate.

`subject_identifiers`:

```text
subject_id
system
value
source_id
```

Examples:

```text
FHIR Patient ID
MRN
RPM platform member ID
device platform member ID
```

Unique constraints are scoped by organization + system.

---

# 11. Authentication and Authorization

## v0.1

Support:

```text
secure web sessions
invitation-based organization membership
role-based authorization
```

Likely roles:

```text
organization_admin
clinical_ops
clinician
analyst
support_limited
```

Do not overbuild fine-grained permission matrices initially.

Use policy objects for authorization.

Every controller/query that touches subject health data should receive an explicit authorized Organization/member context.

---

## Pilot gate

Before real PHI:

```text
SSO strategy reviewed
MFA strategy reviewed
session/security settings reviewed
support access controls implemented
sensitive access audit implemented
```

Enterprise SAML/OIDC may be added when demanded by pilot customer.

---

# 12. Tenant Isolation Strategy

## Application layer

All tenant-facing queries require organization context.

Example conceptual query:

```ruby
Ops::CaseQuery.new(
  organization: Current.organization,
  user: Current.user
)
```

Avoid global unscoped health-data finders in controllers.

---

## Database layer

Use:

```text
NOT NULL organization_id
foreign keys
composite unique constraints
tenant-prefixed indexes
```

For pilot readiness, evaluate PostgreSQL Row-Level Security on the highest-risk tenant tables.

RLS should be a defense-in-depth mechanism, not a substitute for correct application authorization.

If implemented, use transaction-local tenant context and test connection-pool leakage explicitly.

---

# 13. Raw Ingestion Layer

## 13.1 RawEnvelope

Purpose:

> preserve source truth before transformation.

Suggested columns:

```text
id
public_id
organization_id
subject_id nullable until identity resolution
source_id

source_record_id
source_record_version

content_type
object_key
content_hash

observed_at nullable
source_modified_at nullable
received_at
ingested_at

adapter_key
adapter_version

metadata jsonb
created_at
```

Unique identity:

```text
organization_id
source_id
source_record_id
source_record_version
```

When a source lacks versions, derive stable semantic identity and content hash.

RawEnvelope records are append-only.

---

## 13.2 Sources

`sources` represent:

```text
FHIR endpoint
RPM vendor
device cloud
CSV import
customer API
manual/admin import
```

Columns:

```text
organization_id
key
source_type
display_name
status
configuration_encrypted
last_success_at
last_failure_at
```

Do not put credentials in ordinary JSON columns.

---

## 13.3 Initial ingestion APIs

Build in this order:

1. synthetic/internal JSON ingestion
2. CSV/batch import
3. simple customer telemetry/event API
4. FHIR import adapter
5. domain/vendor-specific adapters only when pilot requires them

Do not make integration count the MVP moat.

---

# 14. Ingestion Idempotency

Every inbound record must have a stable source identity.

Ingestion contract:

```text
receive
↓
authenticate source
↓
calculate identity/hash
↓
insert RawEnvelope if new
↓
enqueue normalization through outbox
```

Retries must not create duplicate canonical data.

Database constraints are the final authority.

---

# 15. Canonical Telemetry Model

Core entities:

```text
Observation
ObservationGroup
Event
Interval
DerivedSignal
Source
Device
RawEnvelope
```

---

# 16. Observation

Suggested columns:

```text
id
public_id
organization_id
subject_id

semantic_key
semantic_version

observation_group_id nullable

value_numeric nullable
value_text nullable
value_code nullable
unit nullable

observed_at
observed_end_at nullable
timezone_offset_minutes nullable

source_id
device_id nullable
raw_envelope_id

source_record_id
recording_method
measurement_protocol nullable

quality_state
quality_flags jsonb

source_modified_at nullable
ingested_at
normalized_at

normalizer_key
normalizer_version

created_at
```

Use a CHECK constraint so value representation is internally valid.

For v0.1, numeric telemetry can use PostgreSQL `numeric` for correctness and simplicity. Revisit storage representation only if high-frequency domains make it necessary.

---

# 17. ObservationGroup

Many measurements are naturally grouped:

```text
BP systolic + diastolic + pulse
lab panel
body composition measurement
```

Suggested:

```text
observation_groups
  id
  organization_id
  subject_id
  semantic_key
  observed_at
  source_id
  raw_envelope_id
```

This preserves joint-measurement semantics without requiring compound JSON values.

---

# 18. Event

Suggested columns:

```text
organization_id
subject_id
semantic_key
semantic_version

occurred_at
ended_at nullable

source_id
device_id nullable
raw_envelope_id

recording_method
attributes jsonb

normalizer_key
normalizer_version
```

Examples:

```text
medication ordered
visit occurred
device changed
PT session completed
refill delayed
```

---

# 19. Interval

Suggested columns:

```text
organization_id
subject_id
semantic_key
semantic_version

started_at
ended_at nullable

source_id
raw_envelope_id
attributes jsonb
```

Examples:

```text
hospitalization
sleep session
treatment cycle
travel period
recovery phase
```

---

# 20. Devices

Suggested columns:

```text
organization_id
subject_id nullable
source_id

external_id
manufacturer
model
device_type
firmware_version nullable

active_from
active_to nullable

metadata jsonb
```

Device/source transitions must be queryable.

---

# 21. Provenance

Provenance is not a text note.

Every canonical record must expose:

```text
raw source
source identity
device
recording method
normalizer
normalizer version
original timestamps
ingestion timestamp
```

Derived artifacts must expose their input lineage.

Do not create a provider-visible analytical object that cannot trace downward.

---

# 22. Generic Evidence Set

Introduce a generic evidence-reference abstraction early.

Suggested:

```text
evidence_sets
  id
  organization_id
  purpose
  as_of
  fingerprint
  created_at

evidence_items
  evidence_set_id
  organization_id
  record_type
  record_id
  role
  ordinal nullable
```

Potential purposes:

```text
derived_signal_inputs
context_inputs
baseline_inputs
comparison_affected_inputs
comparison_baseline_inputs
investigation_snapshot
```

This provides one consistent drilldown mechanism.

If polymorphic evidence references become difficult to enforce safely, split by canonical record class later.

For v0.1, correctness and inspectability outweigh perfect relational purity.

---

# 23. Semantic Registry

The platform needs versioned semantic definitions.

Initial implementation:

```text
code/YAML definitions
+
runtime registry
```

Do not begin with a user-editable semantic-definition database.

Each definition contains:

```text
key
version
kind
value type
unit semantics
privacy classification
aggregation rules
expected measurement model
source compatibility rules
effect-magnitude thresholds if domain-specific
semantic/source/derivation families
```

Example keys:

```text
health.vital.blood_pressure.systolic
health.vital.blood_pressure.diastolic
health.measurement.frequency
health.measurement.completeness
health.measurement.source_changed
```

Records store:

```text
semantic_key
semantic_version
```

Definitions MUST be immutable by version.

Behavior change means new version.

---

# 24. Domain Packs

Domain packs extend platform semantics.

Recommended structure:

```text
app/domain_packs/hypertension/
  definition.rb

  semantics/
    blood_pressure.yml
    measurement.yml

  derived_signals/
    daily_blood_pressure_summary.rb
    blood_pressure_variability.rb
    measurement_cadence.rb

  monitors/
    threshold_excursion.rb
    trajectory_change.rb
    variability_change.rb
    measurement_frequency_change.rb
    source_change.rb

  cases/
    case_types.yml
    correlation_rules.rb
    priority_policy.rb
    routing_policy.rb

  contexts/
    blood_pressure_change_context.rb

  baselines/
    personal_recent.rb

  comparisons/
    blood_pressure_shift.rb

  findings/
    blood_pressure_pattern.yml
    measurement_behavior.yml
    instrumentation.yml
```

Domain packs are in-process Ruby/config.

No engines.

No separate deployables.

---

# 25. Definition Identity

Every versioned definition should expose:

```ruby
key
version
digest
```

`digest` is generated from normalized definition/config content.

Persist:

```text
definition_key
definition_version
definition_digest
```

on generated analytical artifacts.

This catches accidental config changes without version bumps.

CI should fail if a versioned definition changes while retaining the same digest/version contract.

---

# 26. Derived Signals

A DerivedSignal is a canonical reproducible calculation.

Suggested table:

```text
derived_signals
  id
  organization_id
  subject_id

  semantic_key
  semantic_version

  window_started_at
  window_ended_at

  value_numeric nullable
  value_text nullable
  value_json nullable
  unit nullable

  algorithm_key
  algorithm_version
  algorithm_digest

  evidence_set_id

  computed_at
  as_of
  status
```

Identity should include:

```text
subject
semantic key/version
window
algorithm version
as_of/fingerprint
```

Do not overwrite a derived signal used by a pinned Investigation.

---

# 27. Measurement Expectation Model

The Statistical Contract requires expected measurement opportunities.

Introduce code-defined expectation models.

Examples:

```text
5 measurement days/week
continuous coverage
event-driven/no periodic expectation
per-care-plan schedule
```

Possible interface:

```ruby
module Measurement
  class Expectation
    def opportunities(subject:, window:, semantic:)
      # returns expected measurement opportunities
    end
  end
end
```

Output should distinguish:

```text
expected
not_expected
unknown
```

Expected opportunities are used to calculate completeness.

---

# 28. Missingness Taxonomy

The canonical/statistical layer must distinguish:

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

Do not use one generic `missing` boolean.

Do not zero-impute absent observations unless semantic contract explicitly guarantees that absence equals zero.

---

# 29. Measurement Behavior Derived Signals

Generic platform-derived dimensions include:

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

These are first-class evidence.

They are not merely data-quality annotations.

---

# 30. Monitor Engine

A Monitor:

```text
reads canonical/derived state
evaluates a versioned condition
produces zero or one/more immutable Signals
```

It does NOT create Cases.

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

---

# 31. Monitor Configuration

Separate:

```text
Monitor definition
```

from:

```text
Organization-specific monitor configuration
```

Suggested tables:

```text
monitor_configurations
  organization_id
  domain_key
  monitor_key
  monitor_version
  enabled
  parameters jsonb
  routing_parameters jsonb
```

This lets customer policy specify thresholds without changing code definition identity.

Clinical threshold defaults should not be invented by platform core.

For the synthetic hypertension pack, test values may be fixture-defined.

---

# 32. MonitorEvaluation

Persist monitor execution metadata where useful:

```text
monitor_evaluations
  organization_id
  subject_id
  monitor_key
  monitor_version
  window_started_at
  window_ended_at
  evaluated_at
  result
  input_fingerprint
  signal_id nullable
```

This is useful for debugging:

> Why did a Signal exist—or not exist?

Retention can later be tuned if evaluation volume becomes high.

---

# 33. Signal

Signals are immutable machine evidence.

Suggested table:

```text
signals
  id
  public_id
  organization_id
  subject_id

  monitor_key
  monitor_version
  monitor_digest

  signal_type
  domain_key

  detected_at
  window_started_at
  window_ended_at nullable

  severity
  attributes jsonb

  source_record_type nullable
  source_record_id nullable

  deduplication_key
  created_at
```

Unique:

```text
organization_id + deduplication_key
```

---

# 34. Signal Idempotency

Deduplication key should derive from:

```text
organization
subject
monitor key/version
evaluation window
semantic event identity
```

Monitor jobs may run repeatedly.

The second execution should return the existing Signal, not create a new one.

---

# 35. Case Correlation Scope

Before correlation, serialize work at:

```text
organization + subject + domain
```

Recommended v0.1 implementation:

```text
case_correlation_scopes
  organization_id
  subject_id
  domain_key
```

Unique index across the tuple.

`Cases::CorrelateSignal`:

```text
BEGIN
  find/create correlation scope
  SELECT ... FOR UPDATE
  re-read eligible Cases
  correlate
  attach / reopen / create
COMMIT
```

Why use a row lock instead of an in-process mutex:

- works across workers;
- survives multi-process deployment;
- visible/testable;
- no hash-collision concerns of homemade advisory-lock keys.

PostgreSQL remains correctness authority.

---

# 36. Case

Suggested table:

```text
cases
  id
  public_id
  organization_id
  subject_id

  domain_key
  case_type

  title
  summary

  status
  review_priority
  priority_reasons jsonb

  owner_id nullable
  team_id nullable

  started_at
  detected_at
  last_signal_at

  evidence_level
  data_quality_state
  baseline_maturity

  analysis_status
  analysis_as_of nullable

  current_context_id nullable
  current_baseline_instance_id nullable
  current_comparison_id nullable
  top_finding_id nullable

  last_reviewed_at nullable
  watch_until nullable

  resolved_at nullable

  lock_version

  created_at
  updated_at
```

Avoid a Rails STI `type` column.

---

# 37. Case Status

Initial states:

```text
new
triaged
investigating
watching
waiting_external
resolved
dismissed
```

Do not add dozens of states to encode every workflow nuance.

Use:

```text
CaseEvent
Disposition
WorkflowAction
WatchCondition
```

for details.

---

# 38. CaseSignal

Suggested:

```text
case_signals
  organization_id
  case_id
  signal_id
  relationship
  attached_at
```

Relationships:

```text
trigger
supporting
contextual
reopening
```

Unique:

```text
case_id + signal_id
```

For v0.1, one primary Case per Signal.

---

# 39. CaseEvent

Append-only operational timeline.

Suggested fields:

```text
organization_id
case_id
event_type
actor_type
actor_id
occurred_at
payload jsonb
```

Events:

```text
case_created
signal_attached
priority_changed
assigned
triaged
investigation_started
watch_started
watch_condition_met
analysis_updated
analysis_failed
reopened
disposition_recorded
resolved
dismissed
external_action_created
```

This is the authoritative Case workflow history.

---

# 40. Case Correlation Contract

When a Signal arrives:

```text
1. check if already attached
2. lock correlation scope
3. find active Cases for same subject/domain
4. filter eligible statuses
5. check overlapping/nearby correlation windows
6. apply domain correlation rules
7. attach if exactly one compatible Case
8. otherwise check recently resolved Cases for reopen
9. otherwise create new Case
```

No:

```text
LLM correlation
embeddings
unsupervised clustering
```

in v0.1.

---

# 41. Correlation Ambiguity

If multiple active Cases are equally plausible:

```text
do not silently merge
```

Default:

```text
create new Case
record correlation_ambiguous event/metadata
```

A future operator-assisted merge capability may be added later.

---

# 42. Hypertension Correlation Rules

Reference case types:

```text
blood_pressure_change
monitoring_interruption
care_gap
```

Reference Signal compatibility:

```text
blood_pressure_change:
  threshold_excursion
  trajectory_change
  variability_change

monitoring_interruption:
  measurement_change
  source_change
  data_quality_change

care_gap:
  workflow_event
```

Source/measurement Signals may attach contextually to a `blood_pressure_change` Case when they help explain the same operational work.

Keep Cases separate when routing/action differs materially.

---

# 43. Case Priority

Priority is operational policy.

Values:

```text
now
today
routine
watch
```

Priority is NOT statistical evidence.

Implement:

```ruby
Cases::RecalculatePriority
Cases::PriorityPolicy
```

Store explanation reasons.

Never surface:

```text
AI Risk Score: 87
```

in v0.1.

---

# 44. Case Routing

Implement a deterministic routing policy.

Inputs:

```text
organization
domain
program
case_type
review_priority
care team
facility
customer routing config
```

Outputs:

```text
queue/team
owner optional
external destination optional
```

Routing is separate from clinical interpretation.

---

# 45. Watch Conditions

Suggested table:

```text
watch_conditions
  organization_id
  case_id

  condition_type
  parameters jsonb

  created_by
  created_at

  expires_at nullable
  satisfied_at nullable
```

v0.1 condition types:

```text
time_elapsed
new_observation_count
new_signal
threshold_crossed
```

Watching means:

> review occurred, but evidence does not justify closure or immediate action.

---

# 46. Dispositions

Use a separate record.

Suggested:

```text
case_dispositions
  organization_id
  case_id
  actor_id
  code
  notes
  action_type nullable
  external_reference nullable
  disposed_at
```

Initial codes:

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

Do not allow arbitrary customer disposition taxonomies until product reporting semantics are understood.

---

# 47. Reopening

Search order:

```text
active Case
↓
recently resolved Case inside domain reopen horizon
↓
new Case
```

Reopening:

```text
retains old disposition
adds reopening Signal relationship
adds CaseEvent
clears resolved_at
recomputes analysis
```

Old history remains immutable.

---

# 48. Transaction Boundaries

## Signal creation

```text
BEGIN
  insert Signal
  insert domain_event(signal_created)
COMMIT
```

## Case create/attach

```text
BEGIN
  lock correlation scope
  create/lock Case
  attach Signal
  update operational Case fields
  append CaseEvent
  insert domain_event(case_changed)
COMMIT
```

## State transition

```text
BEGIN
  lock Case
  validate transition
  update Case
  append CaseEvent
  create Disposition if applicable
  insert domain_event(case_changed)
COMMIT
```

External network calls MUST occur after commit.

---

# 49. Transactional Outbox

Suggested:

```text
domain_events
  id
  organization_id
  aggregate_type
  aggregate_id
  event_type
  payload jsonb
  occurred_at
  dispatched_at nullable
  attempts
  last_error nullable
```

Examples:

```text
telemetry.observation_created
monitoring.signal_created
cases.case_created
cases.signal_attached
cases.case_analysis_requested
cases.case_resolved
```

Dispatcher converts durable domain events into Active Jobs.

This protects against:

```text
DB committed
but enqueue failed
```

especially if job storage uses a separate database.

---

# 50. Analysis Artifacts Are Immutable Snapshots

A major implementation decision:

> completed Contexts, BaselineInstances, Comparisons, Differences, and Findings should be treated as immutable analytical artifacts.

When data changes:

```text
do not mutate old analysis rows
```

Instead:

```text
mark Case analysis stale
generate new analysis artifacts
move Case current_* pointers
```

Saved Investigations reference the prior immutable artifacts.

Benefits:

```text
reproducibility
auditability
easy diffing
late-data correctness
less temporal ambiguity
```

---

# 51. ContextDefinition

Code-defined and versioned.

Conceptual interface:

```ruby
module Context
  class Definition
    def key
    end

    def version
    end

    def dimensions
    end

    def dependency_window(anchor:)
    end

    def build(subject:, anchor:, as_of:)
    end
  end
end
```

Definitions specify:

```text
anchor
dimensions
time windows
source-selection rules
measurement dimensions
derived dimensions
minimum input expectations
```

---

# 52. Context

Suggested:

```text
contexts
  id
  organization_id
  subject_id
  case_id nullable

  definition_key
  definition_version
  definition_digest

  anchor_type
  anchor_id nullable

  window_started_at
  window_ended_at
  as_of

  status
  data_completeness
  input_evidence_set_id

  version_tuple jsonb
  fingerprint

  created_at
```

---

# 53. ContextValue

Use typed row-per-dimension representation initially.

Suggested:

```text
context_values
  organization_id
  context_id

  dimension_key
  dimension_version

  value_numeric nullable
  value_text nullable
  value_boolean nullable
  value_json nullable
  unit nullable

  window_started_at nullable
  window_ended_at nullable

  quality_state
  source_family
  semantic_family
  derivation_family

  evidence_set_id nullable
```

Unique:

```text
context_id + dimension_key
```

This is less “wide-row Honeycomb” physically, but gives Rails/Postgres a simple queryable v0.1 representation.

The Context concept remains logically wide.

A later analytical materialization can use actual wide/columnar storage if cohort workloads demand it.

---

# 54. Context Materialization Modes

## Operational

Precomputed for Cases:

```text
predictable
cached/persisted
default domain definition
```

## Interactive

Created on demand for:

```text
alternate time range
alternate baseline
custom investigation
```

Same definition framework.

Different caching/lifecycle.

---

# 55. Late Data Invalidation

When new canonical telemetry arrives:

```text
identify active Cases for subject/domain
whose analysis dependency windows overlap the observed time
```

v0.1 can intentionally over-invalidate.

Correctness beats minimal recomputation.

Flow:

```text
new late observation
↓
case analysis_status = stale
↓
append CaseEvent analysis_stale
↓
enqueue analysis coordinator
↓
new Context/Baseline/Comparison/Findings
↓
Case current pointers updated
```

Saved Investigations are untouched.

---

# 56. BaselineDefinition

Code/config-defined and versioned.

Fields conceptually:

```text
key
version
baseline_type

eligible range
minimum units
target units
minimum span
target span

phase alignment
cycle alignment
exclusion rules

source compatibility
aggregation rules

expected trajectory model optional
sensitivity definition
```

Baseline types:

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

There is no universal `normal`.

---

# 57. BaselineInstance

Suggested:

```text
baseline_instances
  id
  organization_id
  subject_id
  case_id nullable

  definition_key
  definition_version
  definition_digest

  baseline_type
  window_started_at
  window_ended_at
  as_of

  usable_units
  calendar_span_days
  completeness
  maturity

  source_summary jsonb
  evidence_set_id
  version_tuple jsonb
  fingerprint

  created_at
```

Maturity:

```text
immature
partial
mature
```

---

# 58. Statistical Contract Defaults

These defaults MUST be represented in code/config, not scattered through UI.

## Completeness

```text
< 40%
→ biological Difference suppressed

40–59%
→ maximum WEAK

60–79%
→ maximum MODERATE

>= 80%
→ potentially STRONG
```

Weaker side controls maximum evidence.

---

## Differential missingness

```text
absolute completeness delta >= 25 percentage points
```

creates an eligible Measurement Behavior Difference.

For behavior-dependent/manual signals, associated biological interpretation is capped at WEAK unless a domain method explicitly handles the missingness.

---

## Source/instrument change

If more than 30% of affected analytical units use materially different source/method:

```text
biological evidence max = WEAK
```

unless declared equivalent.

If more than 50%:

```text
suppress biological ranking
surface instrumentation Finding
```

---

## Generic day-based baseline defaults

```text
minimum usable baseline days: 10
target usable baseline days: 21

minimum baseline span: 14 calendar days
target baseline span: 28 calendar days
```

Domain pack should override with clinically meaningful values before production use.

---

## Generic affected window

```text
minimum usable affected days: 5
minimum calendar span: 7 days
```

A protocol Case may exist earlier while analysis returns `insufficient_evidence`.

---

## Cohort minimums

```text
affected subjects >= 20
baseline subjects >= 20
```

for provider-facing ranked Differences unless validated method says otherwise.

---

# 59. Comparison

Suggested table:

```text
comparisons
  id
  organization_id
  subject_id nullable
  case_id nullable

  context_id
  baseline_instance_id

  definition_key
  definition_version
  definition_digest

  analysis_mode
  unit_of_analysis

  method_key
  method_version
  method_digest

  status

  affected_summary jsonb
  baseline_summary jsonb

  evidence_metadata jsonb
  version_tuple jsonb

  as_of
  input_fingerprint
  created_at
```

Statuses:

```text
completed_with_findings
completed_no_reliable_findings
insufficient_evidence
invalid
failed
```

Do not conflate them.

---

# 60. Comparison Pipeline

Implement explicitly:

```text
semantic compatibility
↓
source/instrument compatibility
↓
baseline eligibility
↓
usable-unit minimums
↓
calendar-span minimums
↓
completeness
↓
differential missingness
↓
variance/information
↓
analysis-mode rules
↓
effect calculation
↓
sensitivity/stability
↓
Difference eligibility
↓
Finding generation
```

Each gate should produce structured reason codes.

---

# 61. EvidenceGate

Conceptual:

```ruby
class Comparisons::EvidenceGate
  Result = Data.define(
    :eligible,
    :maximum_evidence,
    :reasons
  )

  def evaluate(affected:, baseline:, definition:)
  end
end
```

Important design principle:

> “Can we say anything?” is evaluated separately from “what is the effect?”

---

# 62. Comparison Methods

Implement small explicit method classes.

Initial:

```text
Comparisons::Methods::RobustContinuousShift
Comparisons::Methods::BinaryProportionShift
Comparisons::Methods::TrajectoryDeviation
Comparisons::Methods::SingleEpisodeDeviation
```

Later cohort:

```text
Comparisons::Methods::CohortContinuousDifference
Comparisons::Methods::CohortBinaryDifference
Comparisons::Methods::BenjaminiHochberg
```

Do not build a generic statistics DSL.

---

# 63. Individual Investigation Statistics

For:

```text
within-subject window
within-subject episode
single-episode contextual deviation
```

DO NOT rank by p-value.

Provider-facing analysis uses:

```text
effect magnitude
absolute values
denominators
completeness
baseline maturity
source compatibility
stability
evidence strength
```

---

# 64. Continuous Shift Method

Default general-purpose summary:

```text
affected median
baseline median
absolute difference
relative difference when meaningful
robust standardized difference when meaningful
```

Robust standardized difference:

```text
(affected median - baseline median) / baseline MAD
```

If MAD is zero/unstable:

```text
omit standardized value
```

Domain-specific metrics may define mean/slope/variance/time-in-range instead.

---

# 65. Binary/Categorical Shift Method

Persist:

```text
affected successes
affected denominator
baseline successes
baseline denominator
absolute proportion difference
relative ratio if stable
```

If either side has fewer than 3 positive events:

```text
do not headline relative ratio
```

Always expose counts.

---

# 66. Unit of Analysis

Every Comparison stores one.

Possible:

```text
subject
day
week
episode
treatment_cycle
encounter
hospitalization
```

Raw sample count, usable observation count, and analytical-unit count must remain distinguishable.

Example:

```text
42 BP readings
→ 12 valid measurement days
→ 12 analytical units
```

The provider must never be shown `n=42` as though 42 readings were independent daily samples.

---

# 67. Autocorrelation Strategy

v0.1:

```text
aggregate into meaningful units
require calendar span
avoid naive individual p-values
compare trajectory summaries
run sensitivity checks
```

Do not implement sophisticated time-series inference solely to look rigorous.

Opaque complexity is not automatically better evidence.

---

# 68. Difference

Suggested:

```text
differences
  id
  organization_id
  comparison_id

  dimension_key
  dimension_version

  status

  affected_summary jsonb
  baseline_summary jsonb
  effect jsonb
  effect_magnitude

  evidence_level
  evidence_reasons jsonb

  stability
  source_compatibility
  completeness_summary jsonb

  semantic_family
  source_family
  derivation_family

  rank nullable

  method_key
  method_version
```

A Difference is descriptive.

Not causal.

---

# 69. Evidence Strength

Values:

```text
insufficient
weak
moderate
strong
```

Meaning:

> support that the dimension differs under the declared comparison.

NOT:

```text
severity
causality
treatment importance
```

---

# 70. Evidence Level Rules

## INSUFFICIENT

Any hard failure:

```text
baseline below minimum
affected below minimum
<40% completeness
semantic incompatibility
material source change blocks interpretation
no usable variation
cohort minimum unmet
unreproducible comparison
```

Biological Difference not ranked.

Measurement/Data Quality Finding may still exist.

---

## WEAK

Examples:

```text
partial baseline
40–59% completeness
small sample
unstable sensitivity
missingness shift
source uncertainty
```

Weak Differences may appear in Investigation secondary details.

If all Findings are weak, queue summary should normally say:

> **No reliable distinguishing pattern found.**

---

## MODERATE

Requires:

```text
eligibility passed
affected/baseline minimums passed
>=60% completeness both sides
baseline at least partial
effect >= domain moderate threshold
no disqualifying source change
sensitivity does not reverse direction
```

---

## STRONG

Requires at minimum:

```text
all moderate requirements
>=80% completeness both sides
mature baseline
stable sensitivity direction
no unresolved material instrumentation change
no major differential missingness
adequate domain observation count
```

Strong still does not mean causal.

---

# 71. Sensitivity / Stability

Every MODERATE-or-higher within-subject Difference should run a domain-defined sensitivity check where possible.

Possible checks:

```text
alternate neighboring window
alternate reasonable baseline
leave-one-unit-out
alternate robust aggregation
```

Stability:

```text
stable
mixed
unstable
not_testable
```

Unstable cannot be STRONG.

---

# 72. Difference Ranking

Do not create one numerical magic score.

Order lexicographically by:

```text
1. eligibility
2. evidence strength
3. effect magnitude class
4. stability
5. data quality
6. domain-defined relevance
```

Do not expose:

```text
Finding Score = 92.7
```

in v0.1.

---

# 73. FindingDefinition

Domain-authored semantic clusters.

Conceptual:

```yaml
key: blood_pressure_pattern_changed
version: 1

candidate_dimensions:
  - blood_pressure.systolic_summary_delta
  - blood_pressure.diastolic_summary_delta
  - blood_pressure.variability_delta

minimum_support:
  moderate_differences: 1
```

Generic platform Findings:

```text
measurement_behavior_changed
instrumentation_changed
data_quality_degraded
```

---

# 74. Findings

Suggested:

```text
findings
  id
  organization_id
  comparison_id
  case_id

  definition_key
  definition_version
  definition_digest

  finding_type
  title
  summary

  evidence_level
  evidence_reasons jsonb
  stability

  rank
  analysis_as_of
  created_at
```

Join:

```text
finding_differences
  finding_id
  difference_id
  relationship
```

---

# 75. Finding Evidence Aggregation

Implement contract exactly:

1. Start with strongest component Difference.
2. Same source/derivation family does not increase evidence.
3. Independent supporting evidence may increase at most one level.
4. Never exceed STRONG.
5. Contradictory evidence may downgrade or mark mixed.
6. Several WEAK correlated Differences can never become STRONG.

Use input lineage + family metadata to detect redundant evidence.

---

# 76. Measurement Findings Take Precedence

When instrumentation/measurement changed materially:

```text
surface that before biological interpretation
```

Example:

```text
1. Measurement source changed       STRONG
2. Blood-pressure pattern changed   WEAK
```

This is a core differentiator.

---

# 77. Evidence Against Confounders

Permit structured “no material recorded change detected” support.

Example:

```text
Device unchanged
Recording method unchanged
Completeness stable
```

Do not phrase this as absolute proof.

Use as supporting context.

---

# 78. Negative Result

If no Finding reaches MODERATE:

```text
queue/quick-review summary:
No reliable distinguishing pattern found.
```

Weak exploratory Differences may remain available in the full Investigation.

This behavior MUST have dedicated tests.

---

# 79. Cohort Statistical Contract

Cohort Explorer is not required for the first operational vertical slice, but the schema/interfaces should not block it.

Default cohort unit:

```text
subject
```

not raw readings.

Ranked provider-facing cohort Differences require:

```text
>=20 affected subjects
>=20 baseline subjects
```

unless an explicit validated method overrides.

Formal hypothesis-testing mode:

```text
declare test family
compute effect
compute raw p
Benjamini-Hochberg FDR
store q
require effect threshold + q threshold + data quality
```

Default exploratory internal FDR threshold from contract:

```text
q <= 0.10
```

This is not a clinical threshold.

Do not expose causal language.

---

# 80. Analysis Version Tuple

Every Comparison/Investigation snapshot should capture:

```text
app revision
semantic convention versions
normalizer versions
derived signal algorithm versions
aggregation versions
ContextDefinition version
BaselineDefinition version
ComparisonDefinition version
comparison method version
FindingDefinition versions
source data as_of
```

Store as JSONB plus a deterministic fingerprint.

This is central, not optional metadata.

---

# 81. Saved Investigation

Suggested:

```text
investigations
  id
  public_id
  organization_id
  subject_id
  case_id
  created_by

  question nullable
  notes nullable

  affected_definition jsonb
  filters jsonb

  context_id
  baseline_instance_id
  comparison_id

  evidence_snapshot_set_id
  version_tuple jsonb

  created_at
```

The referenced analytical artifacts are immutable.

When current Case data changes:

```text
show:
New data is available since this investigation.
```

Offer explicit re-run.

---

# 82. Investigation Evidence Inspector

Every provider-visible Difference must be expandable to:

```text
Affected
  value/distribution
  raw count
  usable denominator
  calendar span
  completeness

Baseline
  value/distribution
  raw count
  usable denominator
  calendar span
  completeness

Effect
  absolute
  relative/standardized if appropriate

Evidence
  level
  structured reasons

Source
  source mix
  recording method
  device/protocol

Stability
  sensitivity result

Method
  method key/version

Inputs
  exact evidence records
```

If this cannot be built from persisted data, the statistical implementation is incomplete.

---

# 83. Evidence Reason Codes

Use structured codes:

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

Generate user-facing explanation deterministically from reason codes.

Do not use an LLM to explain why a statistical evidence grade exists.

---

# 84. Ops Queue

The queue is a Case list, not an alert list.

Default columns/content:

```text
work reason / Case title
subject
program/domain
review priority
status
age
owner/team
top Finding
evidence strength
data quality
baseline maturity
analysis freshness
```

Work reason should be visually primary.

Subject identity should be secondary.

---

# 85. Ops Queue Query

Create:

```ruby
Ops::CaseQuery
```

Inputs:

```text
organization
authorized user
team
status
priority
owner
domain
case type
evidence
data quality
age
```

Default sort:

```text
review priority
then SLA/age
then detected_at
```

Do not use AI queue ranking.

---

# 86. Ops Queue Performance

v0.1 queries normalized Case tables directly.

Required indexes:

```text
organization + status + review_priority + detected_at
organization + team + status + review_priority
organization + owner + status
organization + subject + domain + status
```

If performance later requires:

```text
ops_queue_entries
```

introduce an explicit read model.

Do not preemptively duplicate state.

---

# 87. Ops Queue UI

Rails/Hotwire.

Initial features:

```text
state tabs/counts
filters
sortable/paginated Case list
assignment
triage
watch
resolve/dismiss
analysis status
top Finding
live/near-live row refresh
```

Avoid bulk clinical actions until safety semantics are clear.

Bulk assignment/status changes may be allowed where low risk.

---

# 88. Quick Review

Most Cases should be resolvable without opening the full Workbench.

Quick Review contains:

```text
Why is this here?
Trigger Signals
Top Findings
Evidence strength
Data quality
Baseline maturity
Recent timeline
Source/instrumentation status
Current owner
Available actions
Disposition controls
Investigate →
```

Implement Quick Review before complex workbench interactivity.

---

# 89. Investigation Workbench

Recommended layout:

```text
LEFT:
longitudinal timeline

CENTER:
affected window
baseline selector
Findings
Differences
filters

RIGHT:
evidence inspector
provenance
counts
method/version
```

Rails HTML owns rendering.

Stimulus handles:

```text
range selection
baseline changes
filter state
panel coordination
```

Use JSON only for data-heavy visualization endpoints.

---

# 90. Timeline Data Model

Timeline merges:

```text
Observations
Events
Intervals
Signals
CaseEvents
Finding generation events
Workflow actions
Dispositions
```

Do not mutate historical timeline records.

Use a query object that returns typed timeline entries.

---

# 91. Workflow Actions

Suggested:

```text
workflow_actions
  organization_id
  case_id
  requested_by

  action_type
  status

  adapter_key
  idempotency_key

  request_payload jsonb
  external_reference nullable

  requested_at
  completed_at nullable
  failed_at nullable
  last_error nullable
```

Network actions occur asynchronously.

Examples:

```text
webhook
FHIR Task
external task
deep-link-only/no execution
```

---

# 92. Audit Events

Separate provider access audit from technical logging.

Suggested:

```text
audit_events
  organization_id
  actor_id
  event_type

  subject_id nullable
  case_id nullable
  investigation_id nullable

  occurred_at
  metadata jsonb
```

Audit:

```text
Case viewed
Investigation viewed
Evidence expanded
Subject identity viewed
Assignment changed
State changed
Disposition entered
External action initiated
Export performed
Admin configuration changed
```

Avoid raw PHI in audit metadata unless required.

---

# 93. Technical Logging

Technical logs may include:

```text
request ID
organization internal ID
Case internal/public opaque ID
job ID
source adapter key
semantic key
method key/version
duration
status
```

Do not include:

```text
patient name
MRN
DOB
raw measurement payloads
notes
free-form clinical text
```

---

# 94. Self-Observability

Instrument technical pipeline:

```text
ingestion received
raw persisted
normalized
derived
monitor evaluated
signal created
case correlated
case analysis requested
context built
baseline resolved
comparison executed
finding generated
queue updated
external action delivered
```

Use OpenTelemetry-compatible technical instrumentation where practical.

Health evidence itself is NOT technical tracing data.

---

# 95. Job Queues

Suggested logical queues:

```text
ingestion
normalization
monitoring
case_correlation
analysis
workflow
maintenance
default
```

Configure worker concurrency separately.

Do not pass PHI in job arguments.

Pass IDs.

---

# 96. Job Idempotency Matrix

## Normalize

Identity:

```text
RawEnvelope + normalizer version
```

## DerivedSignal

```text
subject + semantic + window + algorithm version + input fingerprint
```

## Signal

```text
deduplication_key
```

## CaseSignal

```text
case + signal
```

## Context

```text
subject + anchor + definition/version + as_of + input fingerprint
```

## Baseline

```text
subject + definition/version + as_of + input fingerprint
```

## Comparison

```text
affected/context + baseline + definition/method version + input fingerprint
```

## Workflow action

```text
action-specific idempotency key
```

---

# 97. Failure Handling

Operational Cases remain visible even when analysis fails.

Example queue state:

```text
Blood-pressure trajectory changed

Priority:
TODAY

Analysis:
FAILED

[Retry analysis]
```

Distinguish:

```text
failed
```

from:

```text
insufficient_evidence
```

A statistical refusal is not an infrastructure failure.

---

# 98. Analysis Coordinator

Introduce a small explicit orchestration service/job.

Conceptual:

```ruby
Analysis::BuildCaseAnalysis.call(case_record:, as_of:)
```

Flow:

```text
Context::Materialize
↓
Baselines::ResolveDefault
↓
Comparisons::Run
↓
Findings::Generate
↓
Cases::PublishCurrentAnalysis
```

Each stage can be independently retried.

Do not require one giant transaction.

Case points to analysis only after a coherent completed set exists.

---

# 99. Analysis Publication

Build new artifacts off to the side.

Then transactionally publish pointers:

```text
current_context_id
current_baseline_instance_id
current_comparison_id
top_finding_id
evidence_level
data_quality_state
baseline_maturity
analysis_status=current
analysis_as_of
```

Append:

```text
CaseEvent: analysis_updated
```

This avoids queue rows observing a half-built analysis.

---

# 100. Statistical Simulation Harness

Create:

```text
spec/support/synthetic_health/
```

Components:

```text
SyntheticSubject
SyntheticSource
TimelineBuilder
MissingnessPattern
SourceSwitchScenario
TrajectoryScenario
CorrelatedDimensionsScenario
```

Deterministic seeds.

Required scenario families:

```text
stable/null
true level shift
gradual trend
source-switch artifact
missingness artifact
random sparse outliers
high autocorrelation
phase drift
correlated Difference families
```

---

# 101. Statistical Acceptance Behaviors

Required assertions include:

## Stable/null

```text
no reliable Finding
```

## Source switch

```text
instrumentation Finding outranks biological Finding
```

## Missingness collapse

```text
measurement-behavior Finding surfaces
biological interpretation suppressed/limited
```

## Small count

```text
Case may exist
Comparison returns insufficient evidence
```

## Correlated derivatives

```text
three related moderate Differences
do not become STRONG solely through redundancy
```

## Independent corroboration

```text
second meaningfully independent evidence family
may increase Finding one level
```

## Late data

```text
new live analysis may change evidence
saved Investigation remains unchanged
```

---

# 102. False-Positive Budget

Before pilot:

- run default domain comparisons against synthetic null scenarios;
- inspect whether engine “always finds something”;
- inspect low-n ranking behavior;
- inspect artifact amplification.

Do not invent a numeric false-positive target in engineering without statistical review.

The contract-level requirement is behavioral:

> Null-like data should frequently produce **No reliable distinguishing pattern found.**

---

# 103. Changes Requiring Statistical Review

Treat these as governed configuration/code:

```text
minimum evidence thresholds
completeness gates
source-change suppression
effect thresholds
evidence label rules
FDR threshold
baseline minimums
Finding aggregation
cohort minimums
```

Changing them requires:

```text
written rationale
version bump
simulation/regression update
appropriate statistical/clinical review
```

Do not bury these values in feature flags or controller params.

---

# 104. Hypertension Domain Pack v0.1

The pack exists to exercise the platform.

## Semantics

```text
health.vital.blood_pressure.systolic
health.vital.blood_pressure.diastolic
health.vital.pulse optional

health.measurement.frequency
health.measurement.completeness
health.measurement.source_changed
health.measurement.recording_method_changed
```

## Derived signals

```text
daily BP summary
short-window BP summary
baseline BP summary
BP variability
measurement cadence
measurement completeness
```

## Monitors

```text
threshold excursion
trajectory change
variability change
measurement frequency change
source/method change
```

## Case types

```text
blood_pressure_change
monitoring_interruption
care_gap
```

## Findings

```text
blood_pressure_pattern_changed
measurement_behavior_changed
instrumentation_changed
no_reliable_distinguishing_pattern
```

Clinical threshold values are configuration/test fixtures until reviewed for real deployment.

---

# 105. Hypertension Synthetic Demo Scenarios

## Scenario A — likely real pattern change

```text
stable baseline
→ several elevated measurement days
→ same device
→ same recording method
→ adequate completeness
```

Expected:

```text
one blood_pressure_change Case
BP pattern Finding MODERATE/STRONG depending rules
measurement change maybe secondary
instrumentation stable evidence
```

---

## Scenario B — instrumentation artifact

```text
apparent BP jump
same date connected cuff → manual entry
```

Expected:

```text
one Case
Instrumentation Finding STRONG
biological BP Difference WEAK/suppressed
```

---

## Scenario C — insufficient data

```text
3 affected measurement days
6 baseline days
```

Expected:

```text
Case may exist because monitor/policy fired
analysis = insufficient_evidence
watch condition for additional data
```

---

# 106. Data Acquisition Reality Map

Before integrating a real customer, create a domain-specific document/table for every required signal:

```text
semantic key
source
latency
expected completeness
recording actor
historical availability
known failure modes
source-change behavior
normalization mapping
```

The reference domain must not rely on data that the pilot customer cannot actually provide.

---

# 107. API Surface v0.1

Internal/customer APIs should be versioned.

Suggested:

```text
POST /api/v1/telemetry
POST /api/v1/events
POST /api/v1/imports

GET  /api/v1/subjects/:id/timeline

GET  /api/v1/cases
GET  /api/v1/cases/:id

POST /api/v1/cases/:id/watch
POST /api/v1/cases/:id/resolve

POST /api/v1/cases/:id/investigations
POST /api/v1/comparisons

GET  /api/v1/sources
GET  /api/v1/data_quality
```

FHIR endpoints/adapters arrive after canonical API works.

---

# 108. API Authentication

For machine ingestion:

```text
organization-scoped integration credentials
hashed API secrets
source binding
least privilege
rotation
audit
```

Do not reuse human session authentication for ingestion.

---

# 109. Pagination and Query Safety

Health telemetry endpoints can become large.

Use:

```text
cursor/time-based pagination
bounded default date ranges
server-enforced maximum ranges
explicit allowed filter sets
```

Do not expose arbitrary SQL-like filters in v0.1.

---

# 110. Database Index Plan

Initial important indexes:

## Observations

```text
(org_id, subject_id, semantic_key, observed_at DESC)
(org_id, source_id, source_record_id)
(raw_envelope_id)
(observation_group_id)
```

## Events/Intervals

```text
(org_id, subject_id, semantic_key, occurred_at/start_at DESC)
```

## Derived signals

```text
(org_id, subject_id, semantic_key, window_ended_at DESC)
```

## Signals

```text
UNIQUE(org_id, deduplication_key)
(org_id, subject_id, domain_key, detected_at DESC)
```

## Cases

```text
(org_id, status, review_priority, detected_at)
(org_id, team_id, status, review_priority)
(org_id, owner_id, status)
(org_id, subject_id, domain_key, status)
```

Use partial indexes for active Case statuses if query plans justify.

## CaseSignals

```text
UNIQUE(case_id, signal_id)
(signal_id)
```

## CaseEvents

```text
(case_id, occurred_at)
```

## ContextValues

```text
(context_id, dimension_key)
```

Add cross-context analytical indexes only when cohort queries require them.

---

# 111. No Partitioning Yet

Do not partition canonical telemetry on day one.

Instrument:

```text
table size
index size
ingestion latency
query latency
vacuum behavior
maintenance cost
```

Partition when measured operations justify it.

Hypertension-scale pilot data does not require premature sharding.

---

# 112. Database Constraints

Use PostgreSQL constraints aggressively:

```text
foreign keys
NOT NULL
unique source identities
unique Signal dedupe keys
unique CaseSignal link
CHECK enum values where appropriate
CHECK observed time ranges
CHECK value representation
```

Rails validations improve UX.

Database constraints protect correctness.

---

# 113. Ruby Service-Object Map

## Ingestion

```text
Ingestion::Receive
Ingestion::PersistRawEnvelope
Normalization::NormalizeEnvelope
Identity::ResolveSubject
```

## Telemetry

```text
Telemetry::CreateObservation
Telemetry::CreateEvent
Telemetry::CreateInterval
Telemetry::ComputeDerivedSignals
```

## Monitoring

```text
Monitoring::EvaluateMonitors
Monitoring::CreateSignal
```

## Cases

```text
Cases::CorrelateSignal
Cases::CreateFromSignal
Cases::AttachSignal
Cases::Reopen
Cases::RecalculatePriority
Cases::Route

Cases::Transitions::Triage
Cases::Transitions::StartInvestigation
Cases::Transitions::StartWatching
Cases::Transitions::Resolve
Cases::Transitions::Dismiss
```

## Analysis

```text
Analysis::BuildCaseAnalysis
Context::Materialize
Baselines::ResolveDefault
Comparisons::Run
Comparisons::EvidenceGate
Findings::Generate
Cases::PublishCurrentAnalysis
```

## Workflows

```text
Workflows::DispatchAction
```

---

# 114. Job Map

```text
Ingestion::NormalizeEnvelopeJob
Telemetry::DeriveJob

Monitoring::EvaluateSubjectJob
Cases::CorrelateSignalJob

Analysis::BuildCaseAnalysisJob
Analysis::InvalidateSubjectCasesJob

Cases::EvaluateWatchConditionsJob

Workflows::DispatchActionJob
Outbox::DispatchJob

Maintenance::ReprocessDefinitionJob
Maintenance::AuditConsistencyJob
```

Jobs are thin wrappers around services.

---

# 115. Avoid Hidden Workflow

Do NOT use core-model callbacks for:

```text
normalization
Signal creation
Case correlation
analysis generation
workflow delivery
```

Forbidden style:

```ruby
after_create :create_signal
after_update :rebuild_case
```

Prefer explicit orchestration and events.

Callbacks may enforce local, non-orchestrating model behavior only.

---

# 116. Testing Framework Strategy

Use one primary Ruby test framework consistently.

RSpec is a reasonable recommendation for this project because:

```text
domain behavior is complex
shared examples/invariants are valuable
scenario-style specs fit well
```

But test framework choice is not architectural.

Required test categories matter more.

---

# 117. Unit Tests

Required:

```text
normalizer rules
semantic definitions
expected measurement calculations
derived signals
monitor rules
correlation rules
priority policies
routing
Case transition rules
watch conditions
baseline selection
EvidenceGate rules
comparison methods
Finding grouping
evidence aggregation
```

---

# 118. Integration Tests

Required:

```text
raw → canonical
canonical → DerivedSignal
telemetry → Signal
Signal → Case
multiple Signals → one Case
concurrent Signals → one Case
Case → analysis
late data → stale/reanalysis
watch → reactivation
resolution → reopen
workflow action idempotency
```

---

# 119. Invariant / Property Tests

Required invariants:

```text
RawEnvelope never mutates source truth
canonical record always has provenance
Signal never loses provenance
Signal dedupe is idempotent
CaseSignal attachment is idempotent
CaseEvent timeline append-only
resolved Case history retained
saved Investigation immutable
analysis artifacts immutable after completion
Difference denominator always available
Finding never hides component Differences
```

---

# 120. Concurrency Tests

Must-pass test:

```text
three compatible Signals created nearly simultaneously
three correlation jobs execute concurrently
```

Expected:

```text
one Case
three CaseSignal rows
complete CaseEvent history
```

Also test:

```text
same Signal job retry
Case resolution concurrent with Signal arrival
watch condition firing concurrent with manual triage
analysis publication concurrent with late-data invalidation
```

---

# 121. Statistical Regression Tests

Every statistical rule needs direct tests for:

```text
empty data
minimum thresholds
completeness
differential missingness
source changes
zero variance
extreme values
duplicate data
late data
timezone boundaries
small denominators
sensitivity reversal
baseline maturity
cohort minimums
```

---

# 122. System Tests

Provider workflows:

```text
log in
open Ops Queue
filter/assign Case
Quick Review
watch Case
resolve Case
open Investigation
expand Difference evidence
view original source/provenance
save Investigation
view stale-data indicator
```

---

# 123. Security Tests

Before pilot:

```text
cross-tenant access tests
authorization tests
ID enumeration tests
encrypted PHI field tests
audit event tests
job/log PHI leakage checks
export permissions
integration credential scopes
```

If RLS enabled:

```text
connection reuse cannot leak tenant context
admin/service roles explicitly tested
```

---

# 124. CI Pipeline

Minimum:

```text
bundle install with lockfile
lint/style
unit/integration tests
system tests
security scanner
dependency audit
migration check
schema consistency
definition-digest check
synthetic statistical scenarios
```

Do not require slow full simulation suites on every tiny commit if they become expensive; run full statistical regression in a dedicated CI stage.

---

# 125. Definition-Digest CI Check

Write tooling:

```text
bin/definitions verify
```

For each versioned definition:

```text
semantic
normalizer
derived signal
monitor
Context
Baseline
Comparison
Finding
```

CI compares current digest with recorded expected digest.

If code/config changed without version bump:

```text
FAIL
```

This prevents silent reproducibility breakage.

---

# 126. Developer Tooling

Provide:

```text
bin/setup
bin/dev
bin/test
bin/lint
bin/security
bin/definitions
bin/demo_seed
bin/replay_envelope
bin/rebuild_case_analysis
```

Make it easy to:

```text
replay one source record
inspect lineage
rerun one monitor
rerun one Case analysis
generate synthetic population
```

Debuggability is a product requirement for this system.

---

# 127. Demo Seed Environment

Seed synthetic data with:

```text
100+ subjects
stable measurements
trajectory changes
instrumentation changes
missingness
false alarms
insufficient-evidence cases
resolved/reopened Cases
watching Cases
```

The demo should always contain the three canonical examples:

```text
real pattern
measurement artifact
we do not know yet
```

---

# 128. Operational Metrics

Track technical/product metrics separately.

## Technical

```text
ingestion latency
normalization failures
job lag
monitor evaluation duration
case correlation duration
analysis duration
analysis failure rate
database latency
```

## Product/ops

```text
Signals generated
Cases created
Signals per Case
Cases reviewed
median time-to-review
median review duration
Case dispositions
false-positive disposition rate
instrumentation issue rate
insufficient-evidence rate
monitor yield
```

Do not include PHI in metric labels.

---

# 129. “Observability of Observability” Reports

Later in MVP/pilot:

```text
monitor
Signals
Cases
action_taken %
expected/no_action %
instrumentation %
insufficient %
false_positive %
median review duration
```

This gives Clinical Ops leadership a way to tune their monitoring program.

---

# 130. Security / Compliance Engineering Gate

Before real PHI:

- threat model completed;
- vendor/deployment review completed;
- encryption at rest/in transit verified;
- identity-field encryption strategy implemented;
- least-privilege roles reviewed;
- tenant isolation penetration tests;
- audit access events implemented;
- backup/restore tested;
- incident response documented;
- log scrubbing verified;
- secrets rotation documented;
- external regulatory/privacy counsel engaged for product claims/CDS boundary.

This plan does not claim that these steps alone establish compliance.

---

# 131. Regulatory Product Gate

Every ranked Finding must expose:

```text
exact input evidence
baseline
denominators
comparison method
data quality
source provenance
algorithm/definition versions
```

This independently reviewable basis is a hard UI/API requirement.

Do not ship ranking that can only say:

```text
The model thinks...
```

---

# 132. AI Scope

No AI is required for core MVP.

The product must be compelling without an LLM.

Later AI may:

```text
translate provider natural language into structured query
summarize already-computed Findings
summarize evidence
draft provider notes
suggest next dimensions to inspect
```

AI may not:

```text
change evidence level
invent Differences
choose hidden baselines
zero-impute missingness
declare causality
be the sole basis of a Finding
```

If AI is introduced, persist artifact provenance.

---

# 133. Milestone Strategy

Build vertical slices.

Do not complete every backend abstraction before showing the Ops Queue.

Each milestone must end in visible or executable behavior.

---

# 134. Milestone 0 — Repository and Platform Skeleton

**Goal:** bootable secure Rails application with conventions fixed.

Work:

```text
Rails app
Ruby/Rails/Postgres pinning
Docker/dev environment
Solid Queue
CI
lint/security baseline
Organization/User/Membership
Current context
basic authorization
encrypted credentials/secrets
domain event/outbox skeleton
technical logging rules
```

Exit criteria:

```text
user can authenticate
user belongs to one organization
cross-org access tests exist
job executes through Active Job
outbox event can dispatch a job
CI green
```

Contract references:

```text
INV-31 tenant boundaries
S2C transaction/outbox requirements
```

---

# 135. Milestone 1 — Raw Evidence + Canonical Telemetry

**Goal:** ingest and preserve synthetic health telemetry.

Work:

```text
Source
RawEnvelope
object storage
Subject
SubjectIdentifier
ObservationGroup
Observation
Event
Interval
semantic registry v0
normalizer interface/versioning
ingestion idempotency
provenance drilldown admin view
```

Reference input:

```text
synthetic BP JSON
```

Exit criteria:

```text
same source record twice → one canonical result
raw source is preserved
canonical BP systolic/diastolic linked to raw evidence
recording method/device retained
normalizer version visible
```

---

# 136. Milestone 2 — Measurement Semantics + Derived Signals

**Goal:** make observation quality/availability itself observable.

Work:

```text
expected measurement model
missingness taxonomy
measurement opportunities
completeness
source-change derivation
measurement-frequency derivation
daily BP aggregation
short-window BP summary
variability
DerivedSignal lineage
```

Exit criteria:

```text
system distinguishes:
observed
expected-but-missing
device-not-reporting
not-expected

system computes completeness with denominator

system can show:
measurement cadence changed
source changed
```

Statistical references:

```text
STAT missingness
STAT completeness
STAT source compatibility
```

---

# 137. Milestone 3 — Monitors + Signals

**Goal:** machine-detect conditions without creating provider work directly.

Work:

```text
Monitor interface
Monitor configuration
Monitor evaluation persistence
Signal model
Signal idempotency
outbox → monitor job
hypertension monitor pack:
  threshold
  trajectory
  variability
  measurement frequency
  source change
```

Exit criteria:

```text
monitor retry does not duplicate Signal
Signal immutable
Signal shows monitor key/version
Signal points to evidence
monitor never creates Case directly
```

---

# 138. Milestone 4 — Signal → Case Operational Spine

**Goal:** one coherent provider Case from many Signals.

Work:

```text
Case
CaseSignal
CaseEvent
correlation scope
deterministic correlation rules
Case creation
Signal attachment
Case reopen logic
priority policy
routing
concurrency safety
```

Exit criteria:

```text
3 compatible concurrent Signals → exactly one Case
source-change Signal can attach contextually
ambiguous match does not silently merge
recent resolved Case can reopen
old Case outside horizon stays closed/new Case created
```

This milestone is the first major implementation of the Signal → Case Contract.

---

# 139. Milestone 5 — Ops Queue v1 + Case Lifecycle

**Goal:** product becomes operable as a provider work queue.

Work:

```text
Ops::CaseQuery
queue page
filters
assignment
statuses
transition services
watch conditions
dispositions
Case timeline
Quick Review shell
priority explanation
audit events
```

Exit criteria:

```text
operator can:
see why Case exists
assign it
triage it
watch it
resolve/dismiss it
view Signal history

queue reason is primary, subject secondary
priority reason is explainable
```

At this milestone the system is already useful as a superior alert/case manager even before Difference Explorer.

---

# 140. Milestone 6 — Context + Baseline Foundation

**Goal:** produce reproducible analysis inputs.

Work:

```text
EvidenceSet/EvidenceItem
ContextDefinition
Context
ContextValue
Context materializer
BaselineDefinition
BaselineInstance
baseline maturity
version tuple
input fingerprints
analysis artifact immutability
late-data invalidation
```

Hypertension default:

```text
blood_pressure_change Context
personal_recent baseline
```

Exit criteria:

```text
Context can be reproduced
exact evidence inputs inspectable
baseline shows maturity
new late data generates new analysis instead of mutating old
```

---

# 141. Milestone 7 — Statistical Comparison Engine

**Goal:** implement Statistical Contract v0.1 core.

Work:

```text
ComparisonDefinition
Comparison
EvidenceGate
RobustContinuousShift
BinaryProportionShift
TrajectoryDeviation
Difference
completeness gates
source-change gates
minimum unit/span gates
effect magnitude
sensitivity checks
stability
structured evidence reasons
negative-result state
```

Exit criteria:

```text
no individual p-value ranking
denominators always persisted
<40% completeness suppresses biology
source switch can suppress biology
small count → insufficient
moderate/strong require contract gates
“No reliable distinguishing pattern found” works
```

This milestone must not be considered complete until synthetic statistical contract scenarios pass.

---

# 142. Milestone 8 — Findings + Evidence-Backed Queue

**Goal:** transform raw Differences into coherent provider Findings.

Work:

```text
FindingDefinition
Finding
FindingDifference
semantic/source/derivation family metadata
redundancy handling
evidence aggregation
generic measurement Findings
top Finding publication
queue evidence columns
Quick Review findings
```

Exit criteria:

```text
correlated derivatives do not double-count
independent source can increase support max one level
measurement Finding outranks confounded biological Finding
all-weak result does not become fake Top Finding
```

This is the milestone where the product stops being “good alert management” and becomes Human Observability.

---

# 143. Milestone 9 — Investigation Workbench v1

**Goal:** expose the Honeycomb-inspired investigative loop.

Work:

```text
timeline
affected window
default baseline
allowed alternate baseline
Findings panel
Differences panel
Evidence Inspector
provenance drilldown
save Investigation
stale-data indicator
```

Interaction:

```text
Open Case
→ inspect default Findings
→ change allowed window/baseline
→ rerun Comparison
→ inspect evidence
→ save Investigation
```

Exit criteria:

```text
provider can independently review basis of every Finding
saved Investigation is immutable
new data does not rewrite saved Investigation
```

---

# 144. Milestone 10 — External Data + Workflow Integration

**Goal:** leave synthetic-only world.

Work:

```text
CSV historical import
customer API adapter
FHIR import boundary
historical backfill
workflow webhook/FHIR Task adapter
integration credential rotation
source-health admin view
```

Exit criteria:

```text
realistic external data enters canonical pipeline
historical backfill can mature baseline
external action is idempotent
source failures visible
```

Do not add a large integration catalog.

Add what the pilot requires.

---

# 145. Milestone 11 — Pilot Hardening

**Goal:** make product suitable for a controlled provider pilot.

Work:

```text
security review
RLS decision/implementation
SSO/MFA decision
audit completion
backup/restore
data retention
access/export controls
performance testing
statistical simulation suite
monitor-quality reports
data acquisition reality map
regulatory counsel review
support/admin tooling
```

Exit criteria:

```text
pilot data sources documented
statistical null/artifact scenarios pass
cross-tenant security tests pass
provider evidence basis fully inspectable
Case operations measurable
```

---

# 146. Milestone 12 — Cohort Explorer (Post-Spine / Optional for First Pilot)

**Goal:** extend same model to population investigation.

Work:

```text
cohort definitions
subject-level feature materialization
cohort comparison
minimum group size
privacy suppression
BH FDR
effect + q eligibility
Finding clustering
patient drilldown
```

Do not block first queue/workbench pilot on cohort analytics unless buyer requires it.

---

# 147. Milestone 13 — AI Narrator (Optional, After Core Trust)

Only after evidence model is trusted.

Work:

```text
EvidencePacket
AIArtifact
prompt/template versioning
summary generation
note drafting
natural-language query translation
```

Core invariant:

```text
AI summarizes computed evidence
AI does not generate canonical evidence
```

---

# 148. Critical Path

The implementation critical path is:

```text
tenancy
↓
canonical telemetry
↓
measurement/provenance
↓
derived signals
↓
monitors
↓
Signals
↓
Case correlation
↓
Ops Queue
↓
Context/Baseline
↓
Comparison
↓
Findings
↓
Quick Review
↓
Investigation
```

Cohorts and AI are not on the first critical path.

---

# 149. Work That Can Run in Parallel

Once core schema conventions exist:

## Track A — Operational spine

```text
Signal
Case
Queue
Lifecycle
Routing
Actions
```

## Track B — Evidence/analysis

```text
Context
Baseline
Comparison
Difference
Finding
```

## Track C — Domain pack

```text
Hypertension semantics
Derived signals
Monitors
Correlation rules
FindingDefinitions
Synthetic fixtures
```

## Track D — Platform/security

```text
tenancy
audit
integration credentials
deployment
observability
```

These converge at Milestone 8.

---

# 150. Pilot Success Metrics

Do not initially promise clinical outcome improvement.

Measure workflow.

Possible:

```text
median time to triage
median review duration
Cases reviewed per operator
systems/screens opened per review
Case action rate
false-positive disposition rate
instrumentation/data issue rate
insufficient-evidence rate
time from Signal to disposition
```

Also measure:

```text
provider agreement with top Finding
provider usefulness rating
Cases requiring full Workbench
Cases resolved from Quick Review
```

---

# 151. Product Feedback Loop

Provider dispositions become monitoring-program telemetry.

Example:

```text
monitor:
hypertension.trajectory.v1

Cases:
500

action_taken:
55%

expected/no_action:
17%

instrumentation:
14%

insufficient:
8%

false_positive:
6%
```

This informs future monitor tuning.

Do not automatically retrain or alter statistical rules.

---

# 152. What We Explicitly Defer

Do not build during core v0.1:

```text
microservices
Kafka
ClickHouse
Elasticsearch
generic workflow engine
patient app
React SPA
LLM Case correlation
ML Finding clustering
causal inference
digital twin
propensity scoring
automatic treatment recommendations
clinical risk score
cross-customer benchmarking
domain-pack marketplace
hundreds of integrations
user-authored statistics DSL
user-authored arbitrary monitor language
```

---

# 153. Scale-Out Triggers

Only consider service/storage extraction after measurement.

Potential triggers:

## Ingestion service

```text
web/job fleet cannot absorb source throughput
independent autoscaling clearly valuable
collector must run customer-side
```

## Analytical store

```text
cohort ContextValue queries dominate Postgres
index/storage growth becomes operationally painful
interactive cohort latency misses product targets
```

## Specialized stats service

```text
methods require libraries unavailable/awkward in Ruby
CPU workloads materially block Rails workers
independent reproducibility runtime is useful
```

Rails remains control plane unless proven otherwise.

---

# 154. Migration Discipline

Health evidence schema changes require care.

Rules:

```text
backward-compatible deploys where possible
add columns before consuming
avoid rewriting raw evidence
version semantics rather than silently reinterpret
reprocessing creates new derived artifacts
large backfills use explicit jobs
```

Every migration involving tenant health tables should be reviewed for:

```text
locking
index build behavior
backfill volume
rollback/recovery
```

---

# 155. Data Reprocessing

Implement explicit reprocess tooling.

Examples:

```text
re-normalize RawEnvelope with normalizer v2
recompute DerivedSignal algorithm v3
rebuild active Cases under ContextDefinition v2
```

Reprocessing rules:

```text
raw remains unchanged
old derived artifacts remain if referenced
new artifacts get new versions
saved Investigations remain pinned
live Cases may move to new current analysis after policy-approved rebuild
```

---

# 156. Definition Upgrade Policy

When a definition version changes:

```text
code deploy
↓
registry sees new version
↓
new incoming work uses new version
↓
optional explicit reprocess task for live Cases
```

Do not globally rewrite history by default.

---

# 157. Admin / Support Tooling

Need provider-safe internal tools for:

```text
source status
failed envelopes
normalization replay
Signal inspection
Case correlation explanation
analysis rebuild
version tuple inspection
workflow-action retry
audit lookup
```

Support access must itself be audited.

---

# 158. Correlation Explanation

For every CaseSignal attachment, persist enough reason to answer:

> Why was this Signal attached to this Case?

Example:

```text
same subject
same hypertension domain
signal type compatible with blood_pressure_change
window overlaps active Case by 18h
rule hypertension.bp_change.v1
```

This is operational provenance.

---

# 159. Priority Explanation

Likewise:

```text
Review Priority: TODAY

Reasons:
customer policy hypertension.bp_change
Case open > 4h
latest Signal severity = configured-high
```

No unexplained ranking.

---

# 160. Analysis Explanation

For every Case:

```text
Why is this Finding shown?
Why this baseline?
Why this evidence level?
What was excluded?
What changed in measurement?
```

If an answer requires reading code, provider inspectability is incomplete.

---

# 161. Privacy for Cohort Analytics

Before cohort drilldown:

```text
minimum group-size policy
role permissions
suppression behavior
export restrictions
```

Do not allow high-cardinality “anonymous” cohort output that trivially identifies a subject.

Exact threshold is a privacy/policy decision, not an arbitrary engineering constant.

---

# 162. Current Technical Version References

At time of writing:

- Rails 8.1.3.1 release:
  https://rubyonrails.org/2026/7/29/Rails-Versions-7-2-3-2-8-0-5-1-and-8-1-3-1-have-been-released

- Rails upgrade guide / Ruby compatibility:
  https://guides.rubyonrails.org/upgrading_ruby_on_rails.html

- Active Job / Solid Queue:
  https://guides.rubyonrails.org/active_job_basics.html

- Rails 8.0 Solid Queue overview:
  https://guides.rubyonrails.org/8_0_release_notes.html

- Turbo:
  https://turbo.hotwired.dev/handbook/introduction

- Stimulus:
  https://stimulus.hotwired.dev/handbook/introduction

- PostgreSQL RLS:
  https://www.postgresql.org/docs/current/ddl-rowsecurity.html

These are implementation references, not product validation sources.

---

# 163. Companion Contract References

Keep these files beside this document in the repo:

```text
docs/product/provider-observability-v0.3.md
docs/architecture/signal-to-case-v0.1.md
docs/statistics/statistical-contract-v0.1.md
docs/implementation/implementation-plan-v0.1.md
```

Recommended repo move:

```text
human-observability-design-v0.3-provider.md
→ docs/product/provider-observability-v0.3.md

human-observability-signal-to-case-v0.1-rails.md
→ docs/architecture/signal-to-case-v0.1.md

human-observability-statistical-contract-v0.1.md
→ docs/statistics/statistical-contract-v0.1.md
```

---

# 164. Contract Requirement IDs — Signal → Case

The following IDs are intended to be referenced from tickets/PRs/tests.

## S2C-001 — Signal immutability

Signals are append-only machine evidence.

## S2C-002 — Signal idempotency

Monitor retry cannot duplicate semantic Signal.

## S2C-003 — Monitor boundary

Monitor may create Signal, never Case.

## S2C-004 — Case is unit of human work

Ops Queue contains Cases, not raw Signals.

## S2C-005 — Many Signals → few Cases

Compatible Signals correlate into one Case.

## S2C-006 — Deterministic correlation

v0.1 correlation is rule-based.

## S2C-007 — Correlation serialization

Concurrent compatible Signals cannot create duplicate Cases.

## S2C-008 — Correlation ambiguity conservative

Ambiguous matches do not silently merge.

## S2C-009 — CaseSignal explicit relation

Every Signal attachment is represented explicitly.

## S2C-010 — CaseEvent append-only

Workflow history is not overwritten.

## S2C-011 — Priority independent from evidence

Operational urgency cannot be inferred from statistical evidence alone.

## S2C-012 — Explain priority

Store why a Case has its priority.

## S2C-013 — Explicit state transitions

Controllers do not directly mutate arbitrary Case state.

## S2C-014 — Watching first-class

Watch includes explicit reevaluation condition.

## S2C-015 — Resolution requires disposition

Closing work records what happened.

## S2C-016 — Reopen preserves history

Prior disposition remains visible.

## S2C-017 — Reopen horizon domain-defined

Old unrelated episodes become new Cases.

## S2C-018 — Findings do not own Case truth

Analytical artifacts may change; operational Case persists.

## S2C-019 — Analysis failure does not hide Case

Failed analysis remains operationally visible.

## S2C-020 — At-least-once jobs

All workflows tolerate retries.

## S2C-021 — Transactional outbox

Durable state change and downstream job intent cannot silently diverge.

## S2C-022 — Database correctness

Critical uniqueness/concurrency belongs in PostgreSQL, not only Ruby.

## S2C-023 — Queue is explainable SQL/policy

No opaque AI queue ordering.

## S2C-024 — External action after commit

Never call EHR/webhook in DB transaction.

## S2C-025 — Domain boundary

Correlation windows/types/rules belong in domain pack.

---

# 165. Contract Requirement IDs — Statistical Contract

## STAT-001 — Difference is not cause

No causal wording from descriptive comparison.

## STAT-002 — Missing != zero

No silent zero imputation.

## STAT-003 — Measurement behavior is data

Logging/device/reporting changes are analyzable dimensions.

## STAT-004 — Analytical unit explicit

Every Comparison declares unit.

## STAT-005 — Raw sample count != n

Never inflate sample through repeated readings.

## STAT-006 — Semantic compatibility gate

Only comparable semantics are analyzed.

## STAT-007 — Instrumentation gate

Source/method changes evaluated before biology.

## STAT-008 — >30% source-change cap

Unless equivalent, biological evidence max WEAK.

## STAT-009 — >50% source-change suppression

Suppress biological ranking; surface instrumentation.

## STAT-010 — Missingness taxonomy

Missing states remain distinguishable.

## STAT-011 — Expected denominator

Completeness requires explicit expected opportunity.

## STAT-012 — Completeness gates

<40 suppress; 40–59 weak max; 60–79 moderate max; >=80 strong possible.

## STAT-013 — Differential missingness

>=25 percentage-point completeness shift is eligible measurement Finding.

## STAT-014 — Versioned baseline

No implicit baseline.

## STAT-015 — Baseline maturity

Immature / partial / mature visible.

## STAT-016 — Generic baseline minimum

10 usable days / 14-day span unless domain overrides.

## STAT-017 — Generic baseline target

21 usable days / 28-day span unless domain overrides.

## STAT-018 — Generic affected minimum

5 usable days / 7-day span unless domain overrides.

## STAT-019 — Individual no p-value ranking

Within-subject ranking is descriptive/evidence-gated.

## STAT-020 — Robust continuous summary

Median/absolute shift + robust standardized effect when valid.

## STAT-021 — Binary denominators

Persist successes and denominators.

## STAT-022 — Rare-event ratio suppression

Do not headline relative ratio when either side has <3 positive events.

## STAT-023 — Effect thresholds domain-owned

Core does not invent medical effect-size thresholds.

## STAT-024 — No magic importance score

Rank lexicographically.

## STAT-025 — Evidence levels

INSUFFICIENT / WEAK / MODERATE / STRONG.

## STAT-026 — Strong sensitivity requirement

STRONG requires stable sensitivity when testable.

## STAT-027 — Individual multiplicity operational

Gates/clustering, not p-value significance.

## STAT-028 — Cohort FDR

Formal cohort families use declared multiple-testing control.

## STAT-029 — Cohort effect threshold

Significance alone is insufficient.

## STAT-030 — Cohort minimum

20/20 subjects for ranked output unless explicit override.

## STAT-031 — Difference families

semantic/source/derivation families are persisted.

## STAT-032 — Domain-authored Findings first

No learned clustering in v0.1.

## STAT-033 — No redundant evidence inflation

Same source/derivation family cannot boost evidence.

## STAT-034 — Independent support max +1 level

Finding aggregation is conservative.

## STAT-035 — Measurement Finding precedence

Confounder/measurement changes surface before biological interpretation.

## STAT-036 — Negative result valid

No reliable pattern is successful output.

## STAT-037 — Quality != evidence

Persist independently.

## STAT-038 — Nonstationary baseline support

Phase/cycle/expected trajectory available by domain.

## STAT-039 — Cohort prior limits individual strength

Cohort-prior-driven individual result cannot be STRONG in v0.1.

## STAT-040 — Saved analysis reproducible

Pin inputs and method versions.

## STAT-041 — Late data recomputes live only

Saved Investigation unchanged.

## STAT-042 — Evidence reason codes

Provider explanation derives from deterministic structured reasons.

## STAT-043 — Simulation suite

Artifact/missingness/null scenarios required before pilot.

## STAT-044 — Statistical rules governed

Threshold/method changes require version + review.

---

# 166. Requirements → Milestone Matrix

```text
Milestone 0:
S2C-020, S2C-021, S2C-022

Milestone 1:
STAT-006, STAT-010
provenance invariants

Milestone 2:
STAT-002, STAT-003, STAT-011, STAT-012, STAT-013

Milestone 3:
S2C-001, S2C-002, S2C-003

Milestone 4:
S2C-004 through S2C-012
S2C-016, S2C-017, S2C-025

Milestone 5:
S2C-013 through S2C-015
S2C-023

Milestone 6:
STAT-014 through STAT-018
STAT-040, STAT-041

Milestone 7:
STAT-001
STAT-004 through STAT-009
STAT-019 through STAT-030
STAT-036, STAT-037, STAT-042

Milestone 8:
STAT-031 through STAT-035

Milestone 9:
STAT-040, STAT-042
independent review basis

Milestone 11:
STAT-043, STAT-044
security/pilot gates
```

---

# 167. Draft Schema Inventory

Identity:

```text
organizations
users
organization_memberships
teams
team_memberships
subjects
subject_identities
subject_identifiers
```

Sources/evidence:

```text
sources
devices
raw_envelopes
evidence_sets
evidence_items
```

Canonical telemetry:

```text
observation_groups
observations
events
intervals
derived_signals
```

Monitoring:

```text
monitor_configurations
monitor_evaluations
signals
```

Cases:

```text
case_correlation_scopes
cases
case_signals
case_events
watch_conditions
case_dispositions
workflow_actions
```

Analysis:

```text
contexts
context_values
baseline_instances
comparisons
differences
findings
finding_differences
investigations
```

Infrastructure/governance:

```text
domain_events
audit_events
integration_credentials
```

Definitions primarily live in code/config rather than DB in v0.1.

---

# 168. Open Schema Question — Definition Tables

Possible alternative:

```text
semantic_definitions
monitor_definitions
context_definitions
baseline_definitions
comparison_definitions
finding_definitions
```

Recommendation for v0.1:

> keep definitions in versioned code/config, but optionally mirror registry metadata into a read-only `definition_registry_entries` table for administration/inspection.

Reason:

- code review governs behavior;
- easy reproducibility;
- avoids dynamic user-editable algorithm definitions;
- DB metadata can still power admin UI.

Reviewer should challenge this if dynamic enterprise configuration requires more.

---

# 169. Open Schema Question — Evidence References

The generic polymorphic EvidenceSet approach is convenient but weakens relational FK enforcement.

Alternatives:

1. generic polymorphic evidence items;
2. explicit input tables per artifact;
3. typed evidence edge table with constrained record kind;
4. JSON list of IDs—not recommended.

Current recommendation:

> use generic EvidenceSet for product-wide drilldown, but maintain explicit strong input tables for especially important derived calculations if needed.

This is an area worth critical review before migrations freeze.

---

# 170. Open Architecture Question — Solid Queue vs Sidekiq

Current recommendation:

```text
Solid Queue first
```

because:

```text
fewer services
Rails-native
job logic adapter-independent
Postgres-first architecture
```

Reasons to choose Sidekiq instead from day one:

```text
team operational familiarity
known high background throughput
mature queue observability expectations
Redis already required for other reasons
```

This decision is reversible if jobs are thin.

Reviewer should evaluate whether Solid Queue workload on health-ingestion + analysis is likely to become a distraction.

---

# 171. Open Architecture Question — ContextValue Storage

Current recommendation:

```text
row-per-dimension typed ContextValue
```

Pros:

```text
simple Rails objects
queryable
easy evidence association
easy versioning
```

Cons:

```text
row explosion
cohort query joins
less Honeycomb-like physical shape
```

Alternative:

```text
Context dimensions JSONB
```

or later:

```text
wide analytical store
```

Recommendation:

> choose correctness/inspectability first. Revisit physical representation after real cohort/query profiling.

---

# 172. Open Architecture Question — RLS Timing

Options:

## A. RLS from beginning

Pros:

```text
strong defense in depth
tenant leaks caught early
```

Cons:

```text
development complexity
background/admin role complexity
connection-context mistakes
```

## B. RLS before pilot

Pros:

```text
faster synthetic MVP
security hardened before PHI
```

Current recommendation:

> design schema for RLS from day one; implement and exercise it before real PHI pilot unless security review chooses another equivalent control.

---

# 173. Open Product Question — First Pilot Domain

Engineering reference:

```text
hypertension
```

Commercial pilot could still be:

```text
hypertension
post-op
GLP-1
other longitudinal specialty
```

The platform must not require hypertension-specific migrations outside the domain pack.

---

# 174. Open Statistical Question — Numeric False-Positive Budget

The contract requires null-data behavior but does not define a universal numeric false-positive target for exploratory individual analysis.

Do not invent one casually.

Before pilot:

```text
statistical reviewer
+
domain clinician
```

should review simulation output and define acceptable behavior.

---

# 175. Open Statistical Question — Effect Thresholds

Platform core defines evidence mechanics.

Domain packs must define clinically/domain-meaningful:

```text
small
moderate
large
```

effect thresholds.

For synthetic hypertension implementation:

```text
use fixture/test thresholds clearly marked NON-CLINICAL
```

Do not ship those as clinical defaults.

---

# 176. PR Review Checklist

Every feature touching health evidence should answer:

```text
What is the source?
What is the semantic key/version?
What is the provenance?
Can this retry safely?
What is the tenant boundary?
Does this introduce PHI into logs?
Does this mutate a historical artifact?
What definition/method version is recorded?
Could late data change this?
Can a provider drill down to evidence?
Does this conflate priority with evidence?
Does this imply causation?
```

---

# 177. Statistical PR Checklist

For Comparison/Finding changes:

```text
What is the analytical unit?
What are minimum denominators?
How is missingness handled?
What is the source compatibility rule?
What baseline is used?
What is baseline maturity?
What is the effect measure?
What is evidence maximum?
What sensitivity check runs?
Does this add another multiplicity dimension?
Could this double-count same-source derivatives?
What is the negative-result behavior?
What version changes?
Which simulations cover it?
```

---

# 178. Case PR Checklist

For Signal/Case changes:

```text
Can duplicate jobs duplicate a Signal?
Can concurrent Signals duplicate a Case?
Does this create a new unit of work or attach evidence?
What is the correlation rule?
What is the correlation window?
What is the reopen horizon?
Who owns/routs the Case?
What event is appended?
Can this be explained to operator?
What happens on retry/failure?
```

---

# 179. First Concrete Vertical Slice Ticket Set

A useful first epic can be decomposed into:

1. Bootstrap Rails/Postgres/Solid Queue.
2. Organization/User/Membership.
3. Subject + encrypted identity.
4. Source + RawEnvelope.
5. semantic registry with BP keys.
6. BP ObservationGroup + Observations.
7. synthetic ingestion endpoint.
8. normalization + provenance.
9. daily BP derived summary.
10. one trajectory Monitor.
11. Signal persistence/idempotency.
12. Case correlation scope.
13. blood_pressure_change Case creation.
14. CaseEvent timeline.
15. Ops Queue row.
16. system test from JSON ingest → Queue.

Definition of done:

```text
POST synthetic BP data
→ persistent raw evidence
→ canonical BP
→ derived trajectory
→ Signal
→ exactly one Case
→ visible Queue row
```

No Context/Comparison required yet.

---

# 180. Second Epic Ticket Set

1. Multiple hypertension monitors.
2. measurement-frequency monitor.
3. source-change monitor.
4. multiple Signals → one Case.
5. Case routing.
6. priority policy/reasons.
7. assignment.
8. state transition services.
9. watching.
10. dispositions.
11. reopen.
12. concurrent correlation specs.
13. Quick Review shell.

At completion:

> the team can manually operate a synthetic hypertension population.

---

# 181. Third Epic Ticket Set — Statistical Core

1. expected measurement opportunities.
2. completeness.
3. missingness taxonomy.
4. ContextDefinition.
5. ContextValue.
6. BaselineDefinition/Instance.
7. baseline maturity.
8. EvidenceGate.
9. robust continuous comparison.
10. binary comparison.
11. source compatibility.
12. affected/baseline minimums.
13. sensitivity/stability.
14. Difference persistence.
15. evidence reason codes.
16. no-reliable-pattern outcome.
17. simulation fixtures.

This epic should be reviewed against every STAT requirement before merge.

---

# 182. Fourth Epic Ticket Set — Findings/Investigation

1. family metadata.
2. FindingDefinition.
3. Finding generation.
4. redundancy suppression.
5. evidence aggregation.
6. measurement Finding precedence.
7. publish top Finding to Case.
8. queue Finding display.
9. Quick Review evidence.
10. Investigation Workbench.
11. saved Investigation.
12. stale-data indicator.
13. evidence inspector.

---

# 183. Fifth Epic Ticket Set — Pilot Integration

1. CSV import.
2. historical backfill.
3. FHIR adapter minimum.
4. workflow webhook/task.
5. source-health UI.
6. provider access audit.
7. SSO/MFA as required.
8. RLS/security gate.
9. performance load profile.
10. data acquisition reality map.
11. pilot dashboards.
12. monitor-quality report.

---

# 184. Agent Review Prompts

When handing this document to another architecture/review agent, explicitly ask it to challenge:

## Rails

- Is Rails/Postgres sufficient for Context/Comparison workload at pilot scale?
- Is Solid Queue a good initial choice or would Sidekiq reduce risk?
- Are service boundaries too granular or too implicit?

## Schema

- Is generic EvidenceSet the correct provenance primitive?
- Is typed row-per-dimension ContextValue the right v0.1 storage model?
- Should analysis artifacts be append-only snapshots?
- Is direct `organization_id` duplication appropriate?

## Case model

- Are Case correlation rules safe enough?
- Is correlation-scope row locking preferable to advisory locks?
- Are Case status/disposition semantics too complex or too simple?

## Statistics

- Are completeness thresholds sensible as engineering defaults?
- Is evidence grading too categorical?
- Is MAD-based robust shift the right generic continuous default?
- Does the source-change suppression rule need a different structure?
- Is Finding evidence aggregation sufficiently conservative?
- Which rules need a statistician before implementation rather than before pilot?

## Product

- Is Ops Queue truly the primary surface?
- Can Quick Review resolve enough Cases to justify the product?
- Are we accidentally rebuilding care management?
- Which first domain best validates the platform?

## Security/regulatory

- Which data should receive field-level encryption?
- Should RLS be mandatory from first migration?
- Does the independently-reviewable evidence model adequately support the intended CDS posture?
- What must be completed before any real PHI enters the system?

---

# 185. Review Outcomes to Capture

Do not silently incorporate outside review.

Create:

```text
docs/reviews/<date>-implementation-plan-review.md
```

For each recommendation:

```text
Recommendation
Accepted / Rejected / Deferred
Reason
Affected requirement IDs
Affected definition versions
Follow-up
```

This project benefits from explicit design history.

---

# 186. Definition of MVP

The MVP is complete when a provider-side operator can:

```text
receive real/synthetic longitudinal data
see Cases rather than alerts
understand why each Case exists
see measurement/source issues distinctly
see a conservative evidence-backed top Finding when justified
see “no reliable distinguishing pattern” when not justified
Quick Review most Cases
open Investigation for deeper exploration
drill every Finding down to source evidence
assign/watch/resolve the Case
send an action outward
```

And the system can:

```text
reproduce the analysis
survive duplicate jobs
survive concurrent Signals
handle late data
preserve historical Investigations
respect tenant boundaries
avoid PHI in technical observability
```

---

# 187. Definition of Pilot-Ready

Pilot-ready is stricter than feature-complete.

Required:

```text
real customer data mapping documented
historical backfill tested
security review completed
tenant isolation tested
audit completed
backups restored in test
source failures observable
statistical simulation reviewed
domain thresholds reviewed
regulatory/product claims reviewed
support/replay tooling available
workflow integration works
pilot metrics captured
```

---

# 188. Definition of “Do Not Ship”

Do not pilot if any of the following is true:

```text
a Finding cannot show its evidence
Case correlation can duplicate Cases under concurrency
saved Investigations mutate
missing data becomes zero
source changes are hidden
all weak Differences produce a confident Top Finding
individual comparisons use naive p-value ranking
cross-tenant tests fail
PHI appears in ordinary logs
analysis failure removes operational Case
```

---

# 189. Architectural North Star

The system is successful if it can turn:

```text
“BP is weird.”
```

into one of:

```text
“The longitudinal pattern appears different,
with moderate evidence,
and measurement behavior/source are stable.”

“The measurement method changed at the same time,
so the biological interpretation is weak.”

“We do not have enough evidence yet.
The Case is watching for three more valid measurements.”
```

All three are valuable provider outputs.

---

# 190. Final Implementation Principle

The platform should be boring where boring protects trust:

```text
Rails
PostgreSQL
explicit transactions
deterministic rules
immutable evidence
versioned methods
plain SQL
server-rendered workflows
```

and novel only where novelty creates the product:

```text
Context
Compare
Findings
measurement observability
evidence-backed provider Cases
```

The implementation goal is not to build the cleverest health-data architecture.

It is to build the most inspectable, reproducible, operationally useful system for answering:

> **What changed?**

> **What was different?**

> **How sure are we?**

> **Was the measurement itself different?**

> **Show me the evidence.**
