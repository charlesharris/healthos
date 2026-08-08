# ADR-002 — Wide-Event Shape, Deferred Partitioning & Append-Only Enforcement

> **Status:** Proposed — needs sign-off on Decisions 1, 3 and 4
> **Date:** 2026-08-08
> **Deciders:** Charles Harris
> **Related:** ADR-001 (storage & analytical architecture)

Citations as in ADR-001: `HO §n` = handover, `SC §n` = statistical
contract, `S2C §n` = signal-to-case spec, `PD §n` = provider design.

## Context

ADR-001 defers the columnar decision behind tripwires T1–T8. This ADR
handles the physical-schema questions that follow, and separates them
honestly into two groups:

- **Decided now**, because they are irreversible or nearly so
- **Pre-decided but not applied**, because HO §111 says not to build
  them yet and the trigger has not fired

> **Revision note.** An earlier draft of this ADR proposed partitioning
> every high-volume table in Epic 001. HO §111 ("No Partitioning Yet")
> is explicit: *"Do not partition canonical telemetry on day one …
> Partition when measured operations justify it. Hypertension-scale
> pilot data does not require premature sharding."* The handover
> outranks this ADR, **and it is right** — ADR-001 §2 independently
> concludes raw volume is the last thing to break. Decision 2 below is
> rewritten accordingly.

## Decision 1 — `differences` stays wide; add two denormalized keys

HO §68 already specifies a wide, self-contained Difference row:
`dimension_key`/`dimension_version`, `status`, `affected_summary`,
`baseline_summary`, `effect`, `effect_magnitude`, `evidence_level`,
`evidence_reasons`, `stability`, `source_compatibility`,
`completeness_summary`, `semantic_family`, `source_family`,
`derivation_family`, `rank`, `method_key`/`method_version`.

This is already the right shape, and the three family columns already
make correlated-family suppression (STAT-033, SC §49–50) a filter
rather than a join. Little needs changing.

**Proposed addition to HO §68:** denormalize `subject_id` and
`case_id` onto `differences`.

Today both are reachable only via `comparison_id`. Every cohort-shaped
question — "which subjects show a systolic shift at MODERATE+ evidence
in the last 30 days" — therefore pays a join to `comparisons` purely to
recover the subject. The columns are immutable once written (a
Difference belongs to exactly one Comparison, which belongs to exactly
one Subject and Case), so there is no drift risk, and adding them later
means backfilling the table that ADR-001 designates as the columnar
export target.

`contexts` and `context_values` stay exactly as HO §52–53 and §171
specify. See ADR-001 §6 — the JSONB projection is deferred to T1/T3.

Everything else — `cases`, `case_signals`, `case_events`,
`monitor_configurations`, identity, sources, workflow — stays normally
relational. These are operational, low-volume, and `cases` is genuinely
mutable (S2C §14). Do not widen them.

## Decision 2 — No partitioning now; partition keys pre-decided

**Per HO §111, Epic 001 ships unpartitioned tables and the HO §110
index plan as written.** No composite primary keys, no partition
management job, no BRIN indexes.

What this ADR adds is the *answer* for when T2/T7/T8 fires, because the
choice is constrained in a way that is not obvious under deadline
pressure.

### The constraint

PostgreSQL requires that **a unique index on a partitioned table
include the partition key**. Two idempotency invariants collide with
this:

| Invariant | Source | Collision with RANGE-by-time |
|---|---|---|
| `raw_envelopes` unique `(org, source, source_record_id, source_record_version)` | HO §13.1, §14 | the same envelope arriving in two months would create two rows — breaks S2C-020 |
| `signals` unique `(org, deduplication_key)` | HO §34, §110; S2C-002 | breaks the dedup guarantee |

S2C §8 / HO §34 make this sharper: the deduplication key is a single
SHA256 digest over `(org, subject, monitor key, monitor version, window
start, window finish, semantic identity)`. The window is hashed *inside*
the digest, so there is no time column to range-partition on, and S2C §8
states *"Database uniqueness is the final authority."*

### Pre-decided keys

Hash-partitioning on `organization_id` preserves both constraints,
because `organization_id` is already a member of each unique key. Range
partitioning does not.

| Table | Key when triggered | Reason |
|---|---|---|
| `observations`, `observation_groups` | RANGE by observed time, monthly | highest volume; analytics prune by time |
| `measurement_expectations` | RANGE by expected time, monthly | non-event rows (ADR-001 §5a) |
| `derived_signals` | RANGE by `window_ended_at`, monthly | matches HO §110 index |
| `differences`, `contexts` | RANGE by created time, monthly | columnar export targets |
| `audit_events` | RANGE by time, monthly | retention via DROP PARTITION |
| `domain_events` | RANGE by time, weekly | outbox churn; DROP PARTITION ≫ DELETE |
| `raw_envelopes` | **HASH by `organization_id`** | preserves the 4-column unique key |
| `signals` | **HASH by `organization_id`** | preserves `UNIQUE(org_id, deduplication_key)` |
| `cases`, `case_signals`, `case_events` | never | low volume; `cases` is mutable |

Two consequences to expect at that point, recorded so they are not
surprises: RANGE-partitioned tables acquire composite primary keys
`(id, <time column>)`, and BRIN indexes on the time column become
worthwhile.

## Decision 3 — Two things Epic 001 should still change

These are independent of partitioning and are the genuinely
irreversible items.

### 3a. `structure.sql`, not `schema.rb`

Set `config.active_record.schema_format = :sql` in Epic 001-01, before
the first migration.

This is required by HO §112 alone, independent of ADR-001: *"Use
PostgreSQL constraints aggressively — foreign keys, NOT NULL, unique
source identities, unique Signal dedupe keys, unique CaseSignal link,
CHECK enum values, CHECK observed time ranges, CHECK value
representation."* `schema.rb` cannot faithfully represent CHECK
constraints, partial indexes (HO §110: *"use partial indexes for active
Case statuses"*), triggers, or — later — partitions. Epic 001-07 also
requires a CHECK constraint on value representation, which would be
silently lost from `schema.rb` on the first `db:schema:load`.

Retrofitting this after a schema exists produces a painful diff.

### 3b. UUIDv7, not UUIDv4

Epic 001-01 specifies UUID primary keys; the handover does not
constrain the version. Generate **UUIDv7** (time-ordered)
application-side for high-volume append-only tables.

Random v4 UUIDs on append-heavy tables cause index write amplification
and page splits, and they destroy the physical time-ordering that makes
BRIN viable if T2 ever fires. UUIDv7 costs nothing now and cannot be
changed later without rewriting every index.

## Decision 4 — Append-only enforced by privilege, not by trigger

Epic 001-05 explicitly leaves this open: *"DB trigger or `readonly?` —
prefer service-layer + spec; record decision below."*

The requirement is not in doubt. HO §112: *"Rails validations improve
UX. Database constraints protect correctness."* S2C §8: *"Database
uniqueness is the final authority."* S2C-022 puts critical correctness
*"in PostgreSQL, not only Ruby."* The same reasoning applies to
immutability (INV-1, INV-24, INV-26): a service-layer guard cannot
survive a console session, a bulk update, or a future developer.

The question is the **mechanism**.

### Options considered

| Mechanism | Verdict |
|---|---|
| ActiveRecord `readonly?` only | Insufficient — bypassed by console, bulk update, any non-AR path |
| `RAISE EXCEPTION` trigger on UPDATE/DELETE | Works, but procedural, per-row cost, hidden action-at-a-distance |
| `CREATE RULE … DO INSTEAD NOTHING` | **Rejected** — silently discards writes; silent data loss is worse than none |
| `REVOKE UPDATE, DELETE` from the app role | **Chosen** — declarative, zero per-row cost, no procedural code |

### 4a. Privilege revocation (chosen)

```sql
REVOKE UPDATE, DELETE ON <append-only tables> FROM healthos_app;
```

Classification below is reconciled against the full HO §167 schema
inventory, so that every table has an explicit verdict rather than an
implied one.

**Append-only** (revoke `UPDATE`, `DELETE`):

| Group | Tables | Basis |
|---|---|---|
| Raw evidence | `raw_envelopes` | HO §13.1 "RawEnvelope records are append-only"; INV-1 |
| Canonical telemetry | `observations`, `observation_groups`, `events`, `intervals`, `derived_signals` | INV-2/3; HO §154 "avoid rewriting raw evidence" |
| Evidence graph | `evidence_sets`, `evidence_items` | INV-3 lineage |
| Monitoring | `monitor_evaluations`, `signals` | S2C-001; HO §32 is a debugging record of what happened |
| Case history | `case_events`, `case_dispositions` | S2C-010, S2C-016 (reopen preserves prior disposition) |
| Analysis artifacts | `contexts`, `context_values`, `baseline_instances`, `comparisons`, `differences`, `findings`, `finding_differences` | HO §50 "completed … immutable analytical artifacts"; HO §119 |
| Governance | `audit_events` | HO §92 |
| Investigations | `investigations` | HO §188 lists "saved Investigations mutate" as a do-not-ship condition — see 4a-ii |

**Mutable** (no revocation), with the reason recorded so it is a
decision rather than an omission:

`organizations`, `users`, `organization_memberships`, `teams`,
`team_memberships`, `subjects`, `subject_identities`,
`subject_identifiers`, `sources` (status, last_success/failure),
`devices`, `monitor_configurations` (per-org enable/disable, HO §31),
`case_correlation_scopes` (lock row, HO §35), `cases` (the stateful
work unit, HO §36), `watch_conditions` (satisfied/cancelled, HO §45),
`workflow_actions` (retry state), `domain_events` (the outbox updates
dispatch state, HO §49), `integration_credentials` (rotation).

> **Correction.** An earlier draft of this ADR omitted `events`,
> `intervals`, `monitor_evaluations`, `baseline_instances`,
> `finding_differences`, `case_dispositions` and `investigations` from
> the append-only set. All seven are append-only under HO §50/§119.
> Reconciling against HO §167 rather than working from memory is why
> the CI assertion below matters.

### 4a-i. Grants require insert-complete artifacts

Revoking `UPDATE` forbids building a row progressively. Every
analytical artifact must be constructed in memory and inserted
complete.

This is not a new constraint — HO §99 already requires it: *"Build new
artifacts off to the side. Then transactionally publish pointers …
This avoids queue rows observing a half-built analysis."* Grants make
that discipline enforceable instead of conventional, which is precisely
the value.

### 4a-ii. Column-level grants where a row is partly annotatable

Two tables are historical records that nonetheless carry user-editable
prose: `investigations` (`question`, `notes` — HO §81) and
`case_dispositions` (`notes` — HO §46).

Table-level revocation is too blunt here; it would freeze the notes
field. PostgreSQL column-level privileges are the exact tool:

```sql
GRANT UPDATE (question, notes) ON investigations TO healthos_app;
GRANT UPDATE (notes) ON case_dispositions TO healthos_app;
```

The pinned columns — `context_id`, `baseline_instance_id`,
`comparison_id`, `evidence_snapshot_set_id`, `version_tuple` — remain
immutable, which is what HO §188 and STAT-040/041 actually require.
Annotation stays editable, evidence stays pinned, and it is still
declarative.

**Resolved 2026-08-08 (Charles): notes stay editable after save. Keep
the column-level grants.** The corresponding spec must assert both
directions — that `notes` is updatable *and* that every pinned column
is not — since a column-level grant is easy to widen by accident.

### 4a-v. Privileges are applied by a reconcile task, not by migrations

Because `structure.sql` cannot carry ACLs, and because a per-migration
`GRANT` is exactly the kind of thing that gets forgotten, privileges
are declared once and reconciled:

- `db/privileges.yml` — the single source of truth: `append_only`,
  `mutable`, and per-column exceptions
- `bin/rails db:privileges:apply` — idempotent reconcile, hooked into
  `db:migrate`, `db:schema:load` and `db:test:prepare`
- **Default-deny:** `ALTER DEFAULT PRIVILEGES … REVOKE ALL FROM
  healthos_app`, so a table missing from the manifest is un-writable
  rather than silently mutable. The failure mode for forgetting a table
  becomes a loud `INSERT` error in development, not a hole in
  production.

Three roles, which we need anyway:

| Role | Purpose |
|---|---|
| `healthos_app` | Rails runtime. `SELECT`/`INSERT` on append-only tables, full DML on mutable ones |
| `healthos_migrator` | Owns schema, runs migrations |
| `healthos_admin` | Retention and support operations; audited, never used by the app |

Why this beats a trigger:

- **Declarative.** A privilege manifest reconciled by an idempotent
  task, not procedural code hidden in a migration. Note that grants
  cannot live in `structure.sql`: ActiveRecord 8.1
  `PostgreSQLDatabaseTasks#structure_dump` hard-codes
  `["--schema-only", "--no-privileges", "--no-owner"]`, and `pg_dump`
  has no way to re-enable ACLs, so privileges must be applied as a
  separate step in every environment including test. See 4a-v.
- **Zero per-row cost.** Enforcement is in the privilege check, not an
  executed function on every write.
- **Unbypassable from the app.** The Rails console connects as
  `healthos_app` too, so it is covered by the same rule.
- **Shared infrastructure with RLS.** HO §172 and epic 005-09 already
  require role separation, transaction-local context, and admin/service
  role tests. Building append-only on grants means immutability and
  tenant isolation use one mechanism, not two.

Trade-off: a violation surfaces as a PostgreSQL permission error rather
than a domain error. Mitigated by keeping ActiveRecord `readonly?` in
front, which produces the clear error and the readable specs. Both
layers, neither of them a trigger.

### 4a-iii. Operations that need `healthos_admin`

Revoking `DELETE` moves several legitimate operations to the admin
role. Recording them now so they are designed rather than discovered:

- **Retention** — including `monitor_evaluations`, where HO §32 notes
  "retention can later be tuned if evaluation volume becomes high"
- **Superseded-artifact cleanup** — HO §155 keeps old derived artifacts
  "if referenced", implying unreferenced ones may eventually be
  collected
- **Reprocessing** (HO §155, `bin/rebuild_case_analysis`) — creates new
  artifacts and moves pointers, so it needs no deletes, but the
  tooling must run as `app`, not `admin`, to keep that property honest

HO §157 requires support access to be audited; admin-role operations
are the natural audit boundary.

### 4a-iv. Dev and test must use the same roles

If local development and CI connect as a superuser, the grants are
never exercised and the first real test of append-only enforcement is
production. `bin/setup` (HO §126) must create all three roles, and the
test suite must connect as `healthos_app`.

This also gives HO §119's invariant tests ("CaseEvent timeline
append-only", "analysis artifacts immutable after completion") a real
mechanism to assert against rather than a convention.

### 4b. The raw layer becomes a genuine append-only log

HO §13.1 already specifies `object_key` and `content_hash`, and HO §6.5
puts raw payloads in object storage. Two additions turn that into a
tamper-evident log:

- **Object Lock / WORM retention on the raw payload bucket.** This is
  immutability enforced by infrastructure, and it is stronger than a
  streaming log: S3 Object Lock in compliance mode cannot be deleted by
  anyone, including the account root, until retention expires. Kafka by
  contrast has retention deletion and admin APIs.
- **Verify `content_hash` on read, not only on write.** Tampering on
  either side then becomes detectable rather than merely discouraged.

Together with `bin/replay_envelope` (epic 001-13) this satisfies the
append-only-log requirement for raw source truth (INV-1) without adding
a distributed system to the ingestion path.

### 4c. Hash-chain the two audit-critical tables

`audit_events` and `case_events` each carry `prev_hash` and `row_hash`,
computed in application code — no triggers, no database extensions.

This makes mutation cryptographically detectable even by an actor with
superuser access, which neither grants nor Kafka provide. It directly
serves INV-26 (case history append-only/auditable) and the §131
independently-reviewable-basis gate, and gives epic 005-11's security
suite something concrete to assert.

**Scoped to these two tables only.** Chaining requires reading the
previous hash, which serializes inserts. That is acceptable at
CaseEvent and AuditEvent volume and unacceptable on `observations`,
where it would bottleneck the ingestion hot path for little benefit —
`observations` is covered by 4a plus the raw-layer hash in 4b.

## Consequences

- Epic 001-01 gains three tasks: `structure.sql` schema format, UUIDv7
  generation, and the three-role database setup (`healthos_app` /
  `healthos_migrator` / `healthos_admin`) with grants applied per
  migration. `bin/setup` creates all three; the test suite connects as
  `healthos_app` (Decision 4a-iv).
- HO §124's CI pipeline gains a privileges check alongside its existing
  "schema consistency" stage.
- HO §176's PR checklist question *"Does this mutate a historical
  artifact?"* becomes mechanically checkable rather than reviewer
  judgement — worth noting in the checklist itself.
- Epic 001-05's open decision is closed (Decision 4); record it in that
  epic's Decision Log. It also gains WORM/Object Lock configuration on
  the raw payload bucket, and `content_hash` verification on read.
- Epic 001-11 gains `prev_hash`/`row_hash` on `case_events`; epic
  002-24 gains the same on `audit_events`.
- Epic 005-09 (RLS) inherits the role separation from Decision 4a
  instead of introducing it — the two should be planned together.
- Epic 001 ships HO §110's index plan verbatim. No BRIN, no partitions,
  no composite keys.
- HO §68 gains two columns if Decision 1 is accepted.
- Every migration must now grant explicitly; a new table with default
  grants is a silent hole. Add a spec that asserts no app-role
  `UPDATE`/`DELETE` privilege exists on any append-only table, so the
  invariant is enforced by CI rather than by reviewer memory.

## Deviations from governing documents

| # | Decision | Relationship to source |
|---|---|---|
| D3 | Decision 1 | Proposes adding `subject_id`/`case_id` to HO §68's suggested `differences` columns. HO §68 says "Suggested", so this is a refinement, not a conflict. |
| D4 | Decision 3a/3b | Unaddressed by the handover. No conflict. |
| D5 | Decision 4a | Closes a decision HO/epic 001-05 explicitly delegates. Chooses privilege revocation over the trigger the epic names as one option, citing HO §112, S2C-022 and the role separation HO §172 already requires. |
| D6 | Decision 4b/4c | WORM retention and hash chaining are additive hardening, unaddressed by the handover. No conflict. |
| D8 | Decision 4a-ii | **Resolved 2026-08-08.** Notes stay editable after save, so column-level `UPDATE` on `investigations.question`/`notes` and `case_dispositions.notes` is retained. Pinned evidence columns stay immutable per HO §188. |

Decision 2 is now **aligned** with HO §111 rather than deviating from
it; the earlier draft's day-one partitioning is withdrawn.
