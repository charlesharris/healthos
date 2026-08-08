# Human Observability Platform

Provider-side B2B longitudinal health observability. Honeycomb-inspired
investigation model applied to healthcare telemetry. Reference domain:
hypertension remote monitoring (via domain pack — platform core is
domain-neutral). Patient-facing UX is out of scope.

Core promise: **"When something changes, show me what was different.
Then show me the evidence."**
Statistical counterpart: **"The system does not owe the user an
explanation. It owes the user an honest representation of the
available evidence."**

## Governing documents (read before deviating)

Precedence when anything conflicts (higher wins):

1. Safety / legal / regulatory requirements
2. `docs/statistics/statistical-contract-v0.1.md` (STAT-001..044)
3. `docs/architecture/signal-to-case-v0.1.md` (S2C-001..025)
4. `docs/product/provider-observability-v0.3.md`
5. `docs/implementation/implementation-plan-v0.1.md`
6. Framework convention / convenience

Requirement IDs (S2C-xxx, STAT-xxx) are cited in epics, commits, and
test descriptions. If a task references an ID, read that requirement
in the source doc before implementing.

## Stack (pinned — do not float or substitute)

- Ruby 3.4.x, Rails 8.1.x (pin exact versions in .ruby-version,
  Gemfile.lock, Dockerfile, CI)
- PostgreSQL — system of record, transaction coordinator, initial
  analytical store. No ClickHouse/Kafka/Redis/Elasticsearch/Timescale.
- Active Job + Solid Queue (separate queue DB/connection in
  production-like envs). Jobs must be retry-safe; never assume
  exactly-once delivery.
- Server-rendered Rails + Turbo + Stimulus. No React SPA. JSON only
  for data-heavy visualization endpoints.
- Object storage for raw payloads/imports; DB stores keys + hashes.
- RSpec.

## Architecture style

Modular monolith. Plain Ruby namespaces, no Rails Engines. Domain
packs are in-process code/config under `app/domain_packs/hypertension/`.

```
app/
  models/{identity,telemetry,monitoring,cases,analysis,findings,investigations,workflows,audit}/
  services/{ingestion,normalization,telemetry,monitoring,cases,context,baselines,comparisons,findings,investigations,workflows}/
  jobs/{ingestion,monitoring,cases,analysis,workflows}/
  queries/{ops,investigations,cohorts}/
  controllers/{ops,investigations,admin,api/v1}/
  domain_packs/hypertension/
spec/support/synthetic_health/
```

Every arrow in the pipeline (ingest → normalize → derive → monitor →
signal → correlate → analyze → publish) is an explicit service/job
boundary. Jobs are thin wrappers around services.

## Vocabulary (use these words exactly)

- **Subject**, never Patient, as the core entity.
- **Signal** = immutable, append-only machine evidence from a Monitor.
- **Case** = stateful unit of human work. Many Signals → few Cases.
- **Context / BaselineInstance / Comparison / Difference / Finding** =
  immutable analytical artifacts. A Difference is descriptive, never causal.
- **Evidence strength** ∈ insufficient|weak|moderate|strong — support
  that a dimension differs, NOT severity/causality/importance.
- **Review Priority** (now|today|routine|watch) is operational policy,
  independent from evidence strength (S2C-011).

## Non-negotiable invariants

Evidence & provenance:
- Raw source truth (RawEnvelope) is append-only; never mutated.
- Every canonical value has provenance; every derived value has exact
  lineage (EvidenceSet). Every provider-facing Finding drills down to
  source records.

Versioning & reproducibility:
- Normalizers, semantics, derived-signal algorithms, Context/Baseline/
  Comparison/Finding definitions are all versioned + digested. Behavior
  change ⇒ version bump. CI fails on digest drift (`bin/definitions verify`).
- Completed analytical artifacts are immutable snapshots. Late data ⇒
  mark Case analysis stale, build NEW artifacts, move `current_*`
  pointers. Saved Investigations pin versions + evidence and are never
  rewritten (STAT-040/041).

Statistics (see contract for full gates):
- Missing ≠ zero. Never zero-impute (STAT-002). Use the missingness
  taxonomy, not a boolean.
- Measurement behavior (frequency, completeness, source/method change)
  is first-class analyzable data (STAT-003), and measurement/
  instrumentation Findings take precedence over biological ones
  (STAT-035).
- No p-value ranking for individual (within-subject) investigations
  (STAT-019). Rank lexicographically: eligibility → evidence →
  effect-magnitude class → stability → quality → domain relevance.
  Never a single numeric "score" (STAT-024).
- Denominators always persisted and shown; analytical unit explicit;
  repeated readings are not independent n (STAT-004/005/021).
- Completeness gates: <40% suppress biology; 40–59 max WEAK; 60–79 max
  MODERATE; ≥80 STRONG possible (STAT-012). Source change >30% caps
  biology at WEAK; >50% suppresses it and surfaces an instrumentation
  Finding (STAT-008/009).
- Correlated same-family Differences never inflate evidence; independent
  support raises a Finding at most one level (STAT-033/034).
- "No reliable distinguishing pattern found" is a SUCCESSFUL output
  (STAT-036) and must render as such, not as an error.
- Statistical thresholds/rules live in versioned code/config
  (governed, STAT-044) — never in feature flags or controller params.

Operations:
- Monitors create Signals, never Cases (S2C-003). Case correlation is
  deterministic rule-based, serialized per org+subject+domain via
  `case_correlation_scopes` row lock (S2C-006/007). Ambiguity ⇒ new
  Case + `correlation_ambiguous` event, never silent merge (S2C-008).
- CaseEvent timeline is append-only (S2C-010). Resolution requires a
  Disposition (S2C-015). Reopen preserves history (S2C-016).
- Cross-step side effects go through the transactional outbox
  (`domain_events` → dispatcher → jobs) (S2C-021). External network
  calls (webhooks, FHIR Task) happen AFTER commit, never inside a
  transaction (S2C-024).
- Critical uniqueness/concurrency is enforced in PostgreSQL constraints,
  not just Ruby validations (S2C-022).
- Analysis failure never hides an operational Case (S2C-019).
  `failed` ≠ `insufficient_evidence` — never conflate.

Security & boundary:
- Every tenant-facing table carries NOT NULL `organization_id`; every
  query receives explicit authorized org context. No global unscoped
  health-data finders. Schema designed for RLS from day one.
- No PHI in technical logs, job arguments, metric labels, or error
  reports. Pass IDs to jobs, never payloads. Subject identity fields
  use application-level encryption.
- Provider access audit (`audit_events`) is separate from technical
  logging.
- AI never becomes canonical truth. No AI in core MVP at all.
- Temporal association is not causation — in code, UI copy, and docs.
- Platform core contains zero disease-specific assumptions. Anything
  hypertension-shaped lives in the domain pack. Test: "would this
  still make sense for post-op recovery or oncology?"

## Forbidden patterns

- ActiveRecord callbacks for orchestration (`after_create :create_signal`,
  `after_update :rebuild_case`). Callbacks may enforce local model
  behavior only.
- Rails STI `type` column on `cases`.
- One global `role` field on User (roles live on OrganizationMembership).
- Credentials in plain JSON columns.
- Mutating a historical timeline record, analytical artifact, Signal,
  or RawEnvelope.
- Exposing "AI Risk Score: 87" or any opaque numeric importance score.
- `n=42` from 42 readings — show usable analytical units and raw counts
  separately.
- LLM correlation, embeddings, ML clustering, causal inference,
  microservices, ClickHouse, Kafka, React SPA, patient app — all
  explicitly deferred.

## Testing requirements

- Unit specs for every normalizer, monitor, correlation rule, transition,
  EvidenceGate rule, comparison method, and evidence-aggregation rule.
- Concurrency specs: 3 near-simultaneous compatible Signals → exactly
  1 Case, 3 CaseSignals, complete CaseEvent history. Retried jobs never
  duplicate Signals/attachments.
- Statistical regression specs against `spec/support/synthetic_health/`
  scenarios (deterministic seeds): null, level shift, trend,
  source-switch artifact, missingness artifact, sparse outliers,
  autocorrelation, correlated families. Null data must frequently
  produce "no reliable pattern."
- Invariant specs: append-only tables stay append-only, provenance
  always present, saved Investigations immutable, denominators present.
- Cross-tenant access specs on every new tenant-facing surface.
- CI: lint, security scan, dependency audit, migration/schema check,
  `bin/definitions verify` digest check, tests. Full statistical
  simulation suite may run as a dedicated CI stage.

## Working agreements for Claude Code sessions

1. Work one task at a time from the current epic file in
   `docs/implementation/epics/`. Read the epic's Contract References
   first.
2. Red → green: write the failing spec for the contract requirement
   before the implementation where practical. Name specs after
   requirement IDs (e.g. `describe "S2C-007 correlation serialization"`).
3. Check the epic checkbox and note deviations in the epic file's
   Decision Log section in the same commit.
4. Never "fix" a statistical threshold, gate, or evidence rule to make
   a test pass — those changes require a version bump and human review
   (STAT-044). Stop and ask.
5. Migrations touching tenant health tables: call out locking, index
   build strategy, backfill volume, and rollback in the PR description.
6. When any instruction here conflicts with something you infer from
   the codebase, this file and the governing documents win.
7. If a task seems to require breaking an invariant, do not improvise —
   surface the conflict and stop.

## Commands

- `bin/setup` `bin/dev` `bin/test` `bin/lint` `bin/security`
- `bin/definitions verify` — digest check for versioned definitions
- `bin/demo_seed` — synthetic population
- `bin/replay_envelope` / `bin/rebuild_case_analysis` — reprocessing
  (Build these in Epic 001/002 as stubs; keep them working thereafter.)
