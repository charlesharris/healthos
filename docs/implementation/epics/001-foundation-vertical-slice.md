# Epic 001 — Foundation + First Vertical Slice

> **ID:** 001-foundation-vertical-slice
> **Status:** Ready
> **Priority:** P0
> **Handover source:** §134 (Milestone 0), §135 (Milestone 1), §179
> **Dependencies:** None

## Goal

A bootable, tenant-safe Rails application that ingests synthetic
blood-pressure JSON and carries it through the entire pipeline —
raw evidence → canonical telemetry → one derived signal → one monitor
→ Signal → exactly one Case → visible Ops Queue row. No
Context/Comparison/Findings yet. The point is to prove the pipeline
shape and the invariants (idempotency, provenance, tenancy, outbox)
on the thinnest possible path.

## Definition of Done (system test)

```
POST synthetic BP data (twice, identical payload)
→ one RawEnvelope (append-only, raw payload in object storage)
→ canonical BP ObservationGroup + Observations with provenance
→ daily BP derived summary with lineage
→ one trajectory Signal (retry does not duplicate)
→ exactly one blood_pressure_change Case (concurrent correlation safe)
→ CaseEvent timeline
→ authenticated operator sees the Case in the Ops Queue
```

## Contract References

S2C-001, S2C-002, S2C-003, S2C-005, S2C-006, S2C-007, S2C-020,
S2C-021, S2C-022; STAT-006, STAT-010 (taxonomy fields present, full
semantics in Epic 002); provenance invariants 1–3.

---

## Tasks

### 001-01 Bootstrap application
- [x] Rails 8.1.3.1 app, Ruby 3.4.4, pinned in `.ruby-version`,
      `Gemfile.lock`, `Dockerfile`, CI
- [x] PostgreSQL 18, UUIDv7 primary keys, Solid Queue with separate
      queue database config
- [x] Docker compose: postgres, object-store (MinIO) — web/worker
      deviation recorded below
- [x] RSpec, lint (rubocop), brakeman, bundler-audit wired into CI
- [x] `bin/setup`, `bin/dev`, `bin/test`, `bin/lint`, `bin/security`
- [x] Health endpoint + one passing request spec (CI green pending
      first push — verified locally)
- [x] Three database roles, privilege manifest and reconcile task
      (ADR-002 D5), with enforcement proven by spec

### 001-02 Identity & tenancy
- [x] `organizations`, `users`, `organization_memberships` (role on
      membership, NOT on user), `teams`, `team_memberships`
- [x] Session auth + invitation-based membership (minimal UI)
- [x] `Current` context (organization + membership); policy-object
      authorization skeleton
- [x] Every tenant-facing table from here on: NOT NULL
      `organization_id`, FK, tenant-prefixed indexes
- [x] Specs: cross-org access denied at controller and query level
- **Contract:** INV-31; S2C-022

### 001-03 Transactional outbox skeleton
- [x] `domain_events` table (§49 columns), `Outbox::DispatchJob`
      dispatcher converting durable events → Active Jobs
- [x] Helper for "insert domain_event inside the same transaction as
      the state change" (`Outbox.publish`)
- [x] Specs: commit + dispatcher crash → event redelivered; dispatch is
      idempotent (S2C-020, S2C-021)

### 001-04 Subject model
- [x] `subjects` (public_id, org, status, timezone) /
      `subject_identities` (PHI fields, application-level encryption) /
      `subject_identifiers` (system+value unique per org)
- [x] Spec: identity fields encrypted at rest; identifiers resolve a
      subject idempotently

### 001-05 Sources + RawEnvelope + object storage
- [x] `sources` (encrypted configuration, status, last_success/failure)
- [x] `raw_envelopes` per §13.1: unique
      (org, source, source_record_id, source_record_version);
      content_hash; payload in object storage, key+hash in DB
- [x] Append-only enforced by privilege revocation (ADR-002 D5) plus
      `readonly?`; both asserted by spec
- [x] Ingestion contract: authenticate source → identity/hash → insert
      if new → enqueue normalization via outbox
- [x] Spec: same record POSTed twice → one RawEnvelope, one
      normalization enqueue (S2C-020; §14)

### 001-06 Semantic registry v0
- [x] Code/YAML-defined registry with key, version, kind, value type,
      unit, privacy class; immutable by version
- [x] Keys: `health.vital.blood_pressure.systolic`, `.diastolic`,
      `health.vital.pulse`, plus `health.measurement.*` keys reserved
- [x] `bin/definitions verify` digest tooling + CI check (§125)
- [x] Spec: changing a definition without version bump fails verify

### 001-07 Canonical telemetry (BP path only)
- [x] `observation_groups`, `observations` per §16–17 including
      semantic_key/version, quality_state, normalizer_key/version,
      CHECK constraint on value representation
- [x] `events`, `intervals`, `devices` tables created (schema only —
      exercised in Epic 002)
- [x] Missingness-taxonomy-ready fields present (STAT-010); full
      expectation model deferred to Epic 002

### 001-08 Normalizer + provenance
- [x] Versioned normalizer interface; synthetic-BP-JSON normalizer v1
- [x] Normalization job (thin wrapper), idempotent on
      RawEnvelope + normalizer version (§96)
- [x] Admin provenance drilldown view: canonical BP → raw envelope →
      stored payload
- [x] Specs: re-run normalization → no duplicate canonical rows;
      every observation traces to its envelope (STAT-006 gate fields
      populated; invariants 1–3)

### 001-09 Daily BP derived summary
- [x] `derived_signals` table per §26 with algorithm key/version/digest
      and `evidence_set_id`
- [x] `evidence_sets` / `evidence_items` generic tables (§22)
- [x] Daily BP summary algorithm v1 with input lineage recorded
- [x] Spec: recompute with same inputs → same identity, no duplicate;
      lineage resolves to exact input observations

### 001-10 One trajectory monitor → Signal
- [x] Monitor interface (§30), `monitor_configurations`,
      `monitor_evaluations` (§31–32)
- [x] Hypertension trajectory-change monitor v1 (threshold values are
      NON-CLINICAL fixtures — marked as such)
- [x] `signals` table per §33; dedup key per §34; unique
      (org, deduplication_key)
- [x] Specs: monitor retry → same Signal returned, not duplicated
      (S2C-002); monitor never touches Case tables (S2C-003); Signal
      immutable (S2C-001)

### 001-11 Case correlation + Case
- [x] `case_correlation_scopes` with unique (org, subject, domain);
      `Cases::CorrelateSignal` using SELECT ... FOR UPDATE (§35)
- [x] `cases` per §36 (no STI), `case_signals` unique
      (case, signal), `case_events` append-only (§38–39)
- [x] Correlation contract §40 for the single case type
      `blood_pressure_change`; ambiguity → new Case +
      `correlation_ambiguous` (S2C-008)
- [x] Concurrency spec (must pass, §120): 3 near-simultaneous
      compatible Signals, 3 concurrent jobs → 1 Case, 3 CaseSignals,
      complete CaseEvent history (S2C-005/006/007) — runs 20x in CI

### 001-12 Ops Queue row (read-only v0)
- [x] `Ops::CaseQuery` (org + user context required)
- [x] Minimal queue page: work reason primary, subject secondary,
      priority placeholder, status, age (§84)
- [x] Indexes from §110 for cases/signals/case_signals/case_events
- [x] System spec: log in → see the Case created by the slice

### 001-13 End-to-end slice spec + demo seed
- [x] The Definition of Done system test, as one spec
- [x] `bin/demo_seed` v0: a handful of synthetic subjects, one with a
      trajectory change
- [x] `bin/replay_envelope` v0 that re-runs normalization for one
      envelope

## Out of Scope (resist the pull)

Context, Baseline, Comparison, Findings, priority policy, routing,
transitions beyond `new`, watch conditions, dispositions, Quick
Review, multiple monitors, FHIR, CSV import, RLS implementation
(schema must remain RLS-compatible), SSO/MFA.

## Test Plan (epic gate)

- [x] CI green including `bin/definitions verify`
- [x] Cross-tenant specs pass on every surface added
- [x] Idempotency specs: envelope, normalization, derived signal,
      Signal, CaseSignal
- [x] Concurrency correlation spec passes reliably (runs 20x in CI loop)
- [ ] No PHI in logs spec (log scrubbing smoke test) — **not done**, see
      Decision Log
- [x] Definition of Done system spec passes

## Decision Log

### 2026-08-08 — 001-01 bootstrap

**PostgreSQL 18 chosen specifically for native `uuidv7()`.**
ADR-002 Decision 3b specified UUIDv7 generated *application-side*. PG 18
provides `uuidv7()` in-database, so the column default generates them
instead. Strictly better: raw SQL insert paths (imports, backfills,
`bin/replay_envelope`) get time-ordered keys too, rather than only
ActiveRecord paths. Verified: server 18.4, `uuidv7()` present, spec
asserts lexical ordering matches insertion order and the version nibble
is 7. _ADR-002 D4 refined._

**Append-only enforced by privilege revocation, not triggers.**
Closes the open choice in 001-05 ("DB trigger or `readonly?` — prefer
service-layer + spec; record decision below"). Implemented per ADR-002
Decision 4a: `db/privileges.yml` manifest, idempotent
`db:privileges:apply` hooked into migrate/schema:load/test:prepare, and
three roles from `db/roles.sql`. Proven end-to-end in
`spec/database/privileges_spec.rb` against a real table — `DELETE` and
non-granted-column `UPDATE` raise `permission denied`; the D8 annotation
columns remain updatable. _S2C-022; ADR-002 D5/D8._

**The test suite runs as `healthos_app`, so `maintain_test_schema!`
had to go.** It repairs schema drift in-process, which needs `CREATE` on
schema public — precisely what the app role must not have (ADR-002
4a-iv). Replaced in `spec/rails_helper.rb` with
`check_all_pending!`, which verifies without repairing and points the
developer at `bin/test`. `bin/test` prepares the schema as
`healthos_migrator` first. This is the enforcement working, not a
workaround: if the test role could create tables it could also rewrite
evidence, and the guarantee would go untested until production.

**Rails internal tables are created explicitly by the migrator.** With
zero migrations, `structure.sql` is empty and `schema_migrations` never
gets created, so the app role failed to boot with a confusing privilege
error. `apply_to_env!` now creates `schema_migrations` and
`ar_internal_metadata` as migrator, idempotently.

**Deviation: docker compose does not run web/worker.** 001-01 asks for
web and worker services. The prototype scope is local + CI only, the
generated Dockerfile targets production, and native `bin/dev` (which
runs Puma and `bin/jobs` together) is what we will actually use. Rather
than declare compose services nobody runs, CI builds the production
image on every commit so the Dockerfile cannot rot. Verified building
locally. _Revisit if a hosted environment appears — see
prototype-scope.md "Known tension"._

**Local `pg_dump` is a hard dependency of `schema_format = :sql`.**
Installed Homebrew `libpq` (18.4, matching the server; a client older
than the server refuses to dump). It is keg-only, so
`config/initializers/postgres_client_path.rb` prepends it to `PATH` in
dev/test rather than editing the developer's shell profile. CI installs
`postgresql-client-18` from PGDG for the same reason — the runner image
ships an older client.

**Separate queue database in every environment**, not just
production-like ones (HO §6.3 says "prefer"). Keeping dev and test on
the same two-connection shape means the split is exercised rather than
merely configured. The queue database gets blanket DML: it is Solid
Queue's job state, gem-managed, and no health evidence lives there.

**Postgres 18 images changed the data volume path** to
`/var/lib/postgresql` (from `/var/lib/postgresql/data`). Mounting the
old path fails at startup with a pg_upgrade warning.

Not yet verified: **CI green**. The workflow cannot run until the branch
is pushed. Every job was reproduced locally (rubocop clean, brakeman 0
warnings, bundler-audit clean, 14 examples 0 failures, image builds,
`structure.sql` stable across re-migrate).

### 2026-08-09 — CI feedback on 001-01

First push: 4 of 5 jobs green. The PGDG `postgresql-client-18` install
and role creation in the service container both worked first time. The
`test` job failed at the schema step, and the cause was not drift.

`DatabaseTasks#initialize_database` decides whether a database is
initialized by `schema_migration.table_exists?`. With no migrations in
the app, `schema_migrations` never existed, so Rails concluded "not
initialized" on every run, re-loaded `structure.sql`, and collided with
the `ar_internal_metadata` the previous load had created. Reproduced
locally against clean databases — not CI-specific; the earlier local
runs simply never started from empty.

**Zero migrations plus `schema_format = :sql` is not a supported
state.** Two attempted workarounds were withdrawn: creating the
internal tables from the privileges task (it desynchronises
`schema_sha1`, and caused the collision), and an empty `structure.sql`
(then `check_all_pending!` fails trying to create `schema_migrations`
as `healthos_app`, which correctly lacks `CREATE`). The fix is the
first real migration, delivered by 001-02.

**Found in passing: `db/queue_structure.sql` contained one table
instead of Solid Queue's thirteen.** Solid Queue ships
`db/queue_schema.rb` in Ruby format, which `schema_format = :sql`
ignores in favour of a `.sql` file that was being generated
defectively — so the queue database had none of its job tables. This
had nothing to do with CI and would have surfaced in epic 001-03 as
jobs silently failing when the outbox dispatcher first ran.
Regenerated from `queue_schema.rb`. **Regenerate it again whenever
Solid Queue is upgraded** — nothing automatic keeps the two in sync.

### 2026-08-09 — 001-02 identity & tenancy

**Rails 8.1's `authentication` generator was used as the base** for
sessions, giving `Session`, `Current`, and the sign-in flow. `User` was
then rewritten: no `role` column (HO §10.2 forbids a global role on
User) and no `organization_id`, since §10.2 anticipates a user
belonging to several organizations.

**`Current` holds membership, and `organization` derives from it**
rather than being stored alongside, so the two cannot disagree. The
membership is re-resolved from the database on every request rather
than trusted from the cookie, so suspending a membership takes effect
on the next request instead of whenever the session expires. Covered by
a spec.

**Deviation: `invitations` is not in the HO §167 schema inventory.**
Added because HO §11 requires invitation-based membership and the
inventory names no table for it. Only a SHA-256 digest of the token is
stored, following the HO §108 reasoning for integration credentials, so
a database disclosure does not permit accepting outstanding
invitations. Classified `mutable` in `db/privileges.yml`
(`accepted_at` is set on acceptance); the access audit trail belongs to
`audit_events`, not to this table.

**`Tenanted::Query` takes organization as a required constructor
argument and never reads `Current`.** Reading ambient tenancy inside a
query object is invisible in the signature and reintroduces exactly
what HO §12 exists to prevent. It also refuses a membership from a
different organization rather than silently narrowing, since that
combination is always a caller bug. This is simultaneously the ADR-001
query-object seam.

**The privilege completeness guard earned itself.** `sessions` and
`invitations` were left unclassified on purpose to check it; the suite
failed with "Unclassified tables: sessions, invitations" before they
were added to the manifest.

**A cross-tenant hole was found by spec, not by review.**
`ApplicationPolicy#guard_same_tenant!` duck-typed on `organization_id`,
which `Organization` does not have — its own `id` is the tenant key —
so the guard silently skipped the single most important record type.
Now handled explicitly in `tenant_id_for`.

Cross-tenant references render 404 rather than 403, so a response never
confirms that a record exists in another organization (HO §123 lists ID
enumeration as a required security test).

### 2026-08-09 — 001-03 transactional outbox

**Delivery is at-least-once, by choice, and the ordering is the whole
argument.** The enqueue targets the queue database while `dispatched_at`
targets the primary (HO §6.3), so they cannot share a transaction —
this is the dual-write the outbox exists to survive, reappearing one
level down. Given the two available orderings:

- enqueue then mark — a crash between them redelivers, so a handler may
  run twice
- mark then enqueue — a crash between them loses the event entirely

we enqueue first. Losing an event is unrecoverable; running a handler
twice is something S2C-020 already obliges every job to tolerate.
Both branches are covered by spec.

**Rows are claimed with `FOR UPDATE SKIP LOCKED`** so several
dispatchers can run without double-claiming or blocking. The spec
asserts the clause reaches SQL; genuine parallel contention is exercised
by the HO §120 concurrency specs in 001-11, which have real contention
to create.

**`Outbox.publish` refuses to run outside a transaction.** Publishing
outside one still writes a row but silently provides none of the S2C-021
guarantee, which is worse than failing. Proving this needs transactional
fixtures disabled — otherwise the surrounding test transaction satisfies
the guard trivially — so it lives in its own spec file. A first attempt
kept it as a nested context, which committed the shared organization and
broke ten sibling examples on a unique-slug violation.

**Event types are enumerated, and handlers are registered explicitly.**
A typo becomes a raised error rather than an event nothing listens for.
`Outbox::Registry` starts empty on purpose: the skeleton lands before
anything it will carry, and each epic registers its own consumer. Reading
the registry then tells you every consequence an event can have, which is
the visibility HO §115 asks for when it warns against hidden workflow.

**Only the event id crosses the job boundary**, never the payload
(CLAUDE.md: "Pass IDs to jobs, never payloads"). Job arguments are
serialized into the queue database and surface in job introspection.
A spec asserts the payload contents do not appear in the enqueued
arguments. `last_error` is truncated to 500 characters for the same
reason — it is written to a tenant-facing table.

**A failing event cannot block the batch.** Attempt counters are bumped
in a nested transaction so one poisoned event does not roll back its
peers, and events stop being selected after `MAX_ATTEMPTS` rather than
starving newer ones. Dead events are retained, never deleted, so support
can still see them (HO §157).

### 2026-08-09 — CI schema drift was a toolchain mismatch

Second CI failure on "Check schema is up to date", this time genuine
drift — but not in the schema. Every hunk was a CHECK constraint
rendered two ways:

```
(ARRAY['active'::character varying, ...])::text[]      # local, pg_dump 18.4
ARRAY[('active'::character varying)::text, ...]        # CI
```

Cause: the step named "Install PostgreSQL 18 client" installed the
package but did not put it on PATH. The runner image already ships
`postgresql-client-16`, which stayed ahead of it, so `pg_dump --version`
reported 16.14 throughout — the step had been passing while doing
nothing useful. Two clients, two renderings, phantom drift.

Fixed by prepending `/usr/lib/postgresql/18/bin` to `GITHUB_PATH`, plus
a step that asserts the major version and fails loudly. A step that
silently does nothing is worse than one that is missing, because it
reads as covered.

**Also: `postgres:18-alpine` was a floating tag**, which CLAUDE.md's
stack section forbids ("pinned — do not float or substitute"). Both
compose and CI now pin `postgres:18.4-alpine`. This was not the cause
here — both happened to resolve to 18.4 — but it is the same class of
problem and would eventually have produced drift that looked like a
code change.

### 2026-08-09 — text, not varchar (schema round-trip)

The remaining CI drift was not a version mismatch after all, and the
pg_dump fix above — while correct on its own terms — did not change the
diff at all.

**A CHECK constraint on a `character varying` column is not round-trip
stable.** PostgreSQL normalizes `status IN ('a','b')` on a varchar
column to

```
(status)::text = ANY ((ARRAY['a'::character varying, ...])::text[])
```

and re-parsing that dumped text produces a *different* internal
expression, which dumps as

```
(status)::text = ANY (ARRAY[('a'::character varying)::text, ...])
```

So a database built by running migrations and one built by loading
`structure.sql` yield different dumps. Locally the schema came from
migrations; in CI `db:prepare` loads the dump. Same schema, different
text, and a diff that reads like a schema change.

On a `text` column the same constraint renders as
`status = ANY (ARRAY['a'::text, 'b'::text])`, which is a fixed point.
Verified directly against the server before changing anything.

All migrations now use `t.text`. PostgreSQL's documentation notes there
is no performance difference between the two types, and `text` is the
idiomatic choice; the only reason `t.string` was there is that it is the
Rails default.

`spec/database/schema_conventions_spec.rb` now guards this, along with
uuidv7 primary-key defaults and NOT NULL `organization_id` on every
tenant-facing table. Diagnosing this took three CI rounds, so the guard
earns its place: the failure surfaces far from its cause, and looks like
a schema change rather than a type choice.

Note also that `db:migrate` on an empty database does not run migrations
— `initialize_database` loads `structure.sql` instead. Building a schema
genuinely from migrations requires the dump to be absent.

### 2026-08-09 — Platform admin UI (out-of-band addition)

Not an epic 001 task. Added on request for a *system administrator*
surface, distinct from the provider-facing UI.

**DEVIATION: the governing documents describe no system-administrator
actor.** HO §11's roles, `support_limited` included, are
OrganizationMembership roles scoped to one tenant. HO §157 requires
"provider-safe internal tools" and says "support access must itself be
audited", but never says who may use them. A `staff_members` table
introduces that actor — a separate table rather than a flag on `users`,
since CLAUDE.md forbids a global role field on User and a table also
records who granted access and when.

**Administrate**, chosen over Avo and ActiveAdmin because the governing
constraint here is restriction, not features: it generates controllers
and views we own and can strip. RailsAdmin was rejected outright —
auto-discovering every model is precisely wrong for this schema.

Scope is **config and identity only**: organizations, users,
memberships, teams, invitations, sessions, staff members, plus
read-only audit and domain events. Health evidence is absent by
design and gets the task-shaped tooling HO §157 enumerates instead
(001-08 provenance drilldown, 005-15 support tooling).

Three things keep the cross-tenant exception to INV-31 honest:

1. Access requires an active StaffMember, not an organization role. An
   `organization_admin` — the most privileged tenant user — gets 404.
2. Every mutation writes an `audit_events` row (HO §92 "Admin
   configuration changed", HO §157). Field *names* only, never values.
3. It runs as `healthos_app`, **not** `healthos_admin`. Append-only
   grants therefore still apply, so no admin screen can mutate evidence
   even if a dashboard were added by mistake. A spec asserts the
   connection role.

`spec/admin/admin_scope_spec.rb` guards the boundary by listing every
forbidden resource and failing if a dashboard, controller or route
appears for one. This matters because re-running `administrate:install`
generates a dashboard for every model it finds — the day `subjects` or
`observations` exists, a careless regeneration would otherwise expose
health evidence through generic CRUD.

Read-only enforcement needed two hooks, found by reading the gem rather
than guessing: `authorized_action?` (Administrate's documented
authorization hook, which gates the New/Edit/Destroy links) and a
`before_action` that refuses the request. Hiding a control is
presentation; refusing it is the control.

**`audit_events` pulled forward from 002-24.** Shipping admin writes
before the audit table would have made them unauditable by
construction. The table is per HO §92 as written, with one deviation:
`organization_id` is nullable, because platform-level staff actions
genuinely have no tenant — editing a User, global by HO §10.2, is the
clearest case. 002-24 extends it with the case and investigation event
types.

Side effect: `audit_events` is the first append-only table, so the two
privilege specs that had been skipping since 001-01 now run for real.

### 2026-08-09 — 001-04 subject model

**Encryption keys come from the environment, not Rails credentials.** The
default (credentials + `config/master.key`) would require
`RAILS_MASTER_KEY` as a CI repository secret. Environment keys keep CI
green without one and make rotation an infrastructure concern rather
than a commit. Development and test defaults are fixed and public, which
is safe *only* because prototype-scope.md records synthetic data
exclusively; production raises on boot if the keys are absent.

**Identity is split from `subjects`** so that telemetry, monitoring and
analysis never join against a table containing PHI. Reading identity
becomes a deliberate act, which is also what makes HO §92's "Subject
identity viewed" a meaningful audit event.

**Deterministic encryption only where lookup is required** —
`contact_email` and `contact_phone`. It is weaker (equal plaintexts give
equal ciphertexts, so frequency analysis is possible), so names and date
of birth are non-deterministic and consequently unsearchable. A spec
asserts identical plaintext yields different ciphertext, so the
distinction cannot be quietly erased later.

**`public_id` is random, not derived.** Internal ids are UUIDv7 and
encode creation time; a public handle that did the same would leak
enrolment order and timing in URLs and exports (HO §123).

**Identity resolution is idempotent via the database, not a
check-then-insert.** Under concurrent ingestion the check-then-insert
race is exactly what the unique index exists to lose, so
`Identity::ResolveSubject` rescues `RecordNotUnique` and adopts the
winner. This matters because ingestion is at-least-once (S2C-020).

**Subject-local day boundaries.** `Subject#local_date` resolves the day
in the subject's own timezone. Completeness denominators are day-based
(SC §13–14) and HO §121 lists timezone boundaries as a required
regression case, so a UTC day boundary would misattribute readings and
corrupt the denominators. Specced with a 03:00 UTC reading that belongs
to the previous day in New York.

`subject_identifiers.source_id` exists but its association is commented
out until `Source` arrives in 001-05.

### 2026-08-09 — 001-05 sources, raw envelopes, object storage

**`NULLS NOT DISTINCT` on the identity index.** HO §13.1's unique key
includes `source_record_version`, which is nullable. PostgreSQL treats
NULLs as distinct in a unique index by default, so a versionless record
would have inserted on every retry — idempotency silently absent for
exactly the sources HO §13.1 warns about ("when a source lacks
versions"). Specced directly.

**Payload written to object storage before the row is inserted.** If the
insert then loses the idempotency race we get an orphaned object rather
than a row pointing at bytes that were never stored. Content-addressed
keys make the orphan harmless: identical bytes always land on the same
key, so the winning row already references it. That also means two
envelopes citing the same payload share one object, which is specced.

**Content hashes are verified on read, not merely written.** A hash that
is never checked proves nothing. `RawEnvelope#payload` re-hashes and
raises on mismatch, so a provenance drilldown surfaces altered evidence
as an error rather than as plausible-looking bytes (INV-4, INV-5,
HO §131).

**Object locking is verified against real MinIO**, not a double.
`spec/storage/raw_payload_store_spec.rb` asserts
`object_lock_enabled == "Enabled"`. Object lock can only be set at
bucket creation, so a mistake is unrecoverable without recreating the
bucket — worth catching now rather than at pilot. The spec skips with an
explicit message when MinIO is not running, and CI does not run MinIO
today, so this is a local and pre-deploy check. **If it begins skipping
everywhere, the WORM guarantee is unverified.**

**First table where append-only is proven end to end.** The specs assert
`ReadOnlyRecord` from ActiveRecord *and* `permission denied` from
PostgreSQL for both UPDATE and DELETE — the belt and the braces
separately.

Ingestion follows HO §14's order exactly, and the envelope row commits
in the same transaction as its outbox event (HO §48), so normalization
can never be enqueued for evidence that rolled back.

Restored the `SubjectIdentifier#source` association that 001-04 left
commented out.

**Also fixed:** the 001-04 encryption initializer raised outside
dev/test, which broke `assets:precompile` in the Docker image build
(tests were green; `build_image` caught it). It now honours
`SECRET_KEY_BASE_DUMMY`, the signal Rails uses for that build context.

### 2026-08-09 — 001-06 semantic registry and digest gate

**The digest is computed over normalized content, not raw text.** Keys
sorted, symbols and strings unified, integral floats collapsed,
formatting discarded. A digest over raw bytes would fail CI when someone
reindents a YAML file, which trains people to bump versions reflexively
— and a version bump that means nothing destroys exactly the signal
HO §125 depends on. Array order is preserved, since for allowed-value
lists and rule pipelines order can be semantic.

**Three distinct failure modes, deliberately not collapsed into one:**

- `CHANGED` — content moved while the version stayed put. The case the
  gate exists for: every artifact already computed under that
  key@version now means something subtly different, breaking INV-6..12
  invisibly.
- `REMOVED` — historical artifacts reference a version forever, so
  deleting one makes them unreproducible.
- `ADDED` — legitimate; the lockfile just has to move in the same
  commit. Reported separately and does not count as drift, because
  conflating "you added a definition" with "you silently changed one"
  would make the alarming case unremarkable.

**Verified against a real edit, not only in spec.** Changing
`aggregation: median` to `mean` in the hypertension pack without a
version bump makes `bin/definitions verify` exit 1 and name all four
affected definitions. Wired into CI ahead of the test run.

**Difference-family metadata lives on the definition** (SC §49–50).
Systolic and diastolic share a semantic family, so a shift in both is
one finding rather than two confirmations (STAT-033); pulse sits in a
different family, so it is genuine independent support and may raise
evidence at most one level (STAT-034); a daily summary shares a
derivation family with its inputs, so it is correlated with them rather
than confirmatory. Putting this on the definition means the epic 003/004
aggregation rules never need a schema change to enforce it.

**Domain neutrality is asserted, not assumed.** A spec reads
`config/semantics/core.yml` directly and fails if any core key is
anything other than `health.measurement.*` — blood pressure would not
survive CLAUDE.md's "would this make sense for post-op recovery or
oncology?" test, so it lives in the domain pack (INV-35).

Definitions are frozen at construction and the digest is computed
eagerly — memoizing it later mutates a frozen object, and a definition
that cannot be digested should fail at load rather than at first use.

Zeitwerk note: `app/definitions/` is its own autoload root, so
`Definitions::Registry` had to move to `app/services/definitions/`.

### 2026-08-09 — 001-07 canonical telemetry

**The value-representation CHECK makes STAT-002 structural.** HO §16 asks
for a constraint "so value representation is internally valid"; the one
written here does more than that. An `observed` row must carry exactly
one of numeric/text/code, and a non-observed row must carry none — so
there is no way to store `expected_but_missing` with a value of 0.
Zero-imputation becomes impossible at the storage layer rather than
discouraged in review. Specced explicitly, including the zero case.

**Ten quality states, not a boolean** (HO §28, STAT-010). The
distinction that earns its keep is `device_not_reporting` versus
`manual_entry_absent`: one is an instrumentation finding, the other
behavioural (STAT-003). Also `not_expected` is absent but *not* a gap —
a lab that is not due today is not missing — so it is in `MISSING_STATES`
but deliberately not in `EXPECTED_BUT_ABSENT_STATES`, which is what
feeds the completeness shortfall in SC §14.

**`decimal`, never `float`.** A BP of 142 must not come back as
141.99999999999997. Binary floating point has no place in clinical
evidence, and the spec asserts exact round-tripping.

**`timezone_offset_minutes` is stored alongside `observed_at`** because
the subject's offset at the moment of measurement is not recoverable
from a UTC timestamp plus a current timezone — DST and relocation both
break that reconstruction. HO §121 makes timezone boundaries a required
regression case.

**Normalization idempotency is keyed on
`(raw_envelope, semantic_key, semantic_version, normalizer_version,
observed_at)`.** Including the versions is deliberate: re-running the
*same* normalizer must not duplicate (§96), while reprocessing under a
*new* version must produce new rows alongside the old ones, which is
what HO §155 requires. Both directions specced.

`t.references` already creates an index, so the redundant `add_index`
calls aborted the first migration — caught because the table simply did
not exist afterwards. Migrations are transactional in PostgreSQL, so it
rolled back cleanly.

Three spec-construction mistakes worth noting, since each masked the
assertion: a failed statement aborts the surrounding transaction (so
UPDATE and DELETE need separate examples), `save!(validate: false)`
skips the `before_validation` that assigns `public_id`, and a row with a
value *and* a non-observed state trips the value-representation CHECK
before the quality-state one.

### 2026-08-09 — 001-08 normalizer and provenance

**A null reading is recorded, never dropped.** When the payload contains
`"pulse": null`, the normalizer emits an `invalid_measurement`
observation carrying no value rather than skipping the field. Dropping
it would make the gap invisible, and an invisible gap is
indistinguishable from a measurement that was never expected — exactly
the collapse STAT-002 and STAT-010 forbid. A non-numeric value is
handled the same way rather than coerced. Absent-from-payload is
different again and *is* skipped: whether that constitutes a gap is the
expectation model's decision in 002-01, not the normalizer's.

**Normalizers return intents, they do not write rows.** The coordinator
owns the transaction and the idempotency, which keeps a normalizer a
pure function of its payload and lets mapping logic be specced without
touching the database.

**Adapter resolution is an explicit lazy map, not self-registration.**
The first implementation registered each normalizer at the bottom of its
own file. Under Zeitwerk a class nothing has referenced has not been
loaded, so that registry is empty until something happens to touch the
file — behaviour that depends on autoload order. Replaced with an
explicit `ADAPTERS` constant resolved by `constantize`, matching
`Outbox::Registry`. The failure surfaced immediately as "no normalizer
registered for adapter", which is the good version of this mistake.

**The payload is re-verified before it becomes canonical.**
Normalization reads through the store's hash check (ADR-002 4b), so a
tampered payload raises rather than producing observations. Specced:
after tampering, `Observation.count` is zero.

**The provenance drilldown is deliberately not an Administrate
dashboard.** Health evidence is excluded from generic CRUD by
`spec/admin/admin_scope_spec.rb`, and "where did this number come from"
is a task-shaped question a resource index cannot express. It is
read-only, behind the same staff gate, and writes an
`admin.provenance.viewed` audit event (HO §92, §157).

**Integrity failure is shown, not hidden.** If the stored bytes no
longer hash to the recorded value the view renders the failure and
withholds the payload, because a drilldown that silently displayed
altered evidence would be worse than one that errors (INV-4, INV-5,
HO §131). Specced in both directions.

An adapter-key mismatch (`synthetic_json` in the ingestion default
versus `synthetic_bp_json` in the normalizer) failed 16 specs at once —
worth noting only because it is the kind of thing that would have been
a silent no-op had the registry defaulted instead of raising.

### 2026-08-09 — 001-09 derived signals and evidence sets

**`derived_signals` is the table that replaces a continuous aggregate**,
and the concrete reason ADR-001 rejects Timescale rather than merely
deferring it. Every row names the algorithm key, version and digest that
produced it and points at the exact inputs it consumed. A Timescale
continuous aggregate is mutable and carries none of that, so it cannot
satisfy INV-3 or be pinned by a saved Investigation.

**Median, not mean.** SC §29 prefers robust continuous summaries, and a
single mis-cuffed reading of 220 would drag a mean far enough to look
like a genuine trajectory shift. The semantic definition already
declares `aggregation: median`, so algorithm and registry agree rather
than drifting.

**Lineage records what produced the value; the denominator records what
was considered.** A day with one usable reading and one
`device_not_reporting` has an evidence set of one and a denominator of
`{usable: 1, raw: 2}`. Conflating those would misrepresent the
evidence — either by implying the gap contributed, or by hiding that it
existed. Both directions specced.

**`MINIMUM_READINGS` is deliberately not a statistical gate.** It is 1,
and exists only so an empty day yields `insufficient_input` rather than
a null-valued row. Deciding whether a day's readings are *enough* is the
evidence gate's job in epic 003; putting that decision inside a
derivation would hide a gate where nobody would look for it. Flagged
NON-CLINICAL and included in the algorithm digest.

**The value-representation CHECK repeats at the derived layer.** A
non-`computed` signal cannot carry a value, so "zero readings, therefore
zero mmHg" is unrepresentable — STAT-002 enforced twice, once per layer,
rather than assumed to hold downstream.

**Windows are the subject's local day.** Specced with a reading at
2026-03-16 01:00 UTC belonging to 2026-03-15 in New York, and another at
05:00 UTC correctly excluded. Completeness denominators are day-based
(SC §13–14), so a UTC window would silently misattribute readings.

**`EvidenceItem` restricts `record_type` to canonical evidence classes.**
An unconstrained polymorphic column would let anything in, and INV-4's
"drill down to source records" would stop meaning anything specific.

Zeitwerk: domain pack subdirectories are HO §24 organizational
categories, not namespaces, so `app/domain_packs/*/*` is collapsed —
`Hypertension::DailyBloodPressureSummary`, not
`Hypertension::DerivedSignals::DailyBloodPressureSummary`.

### 2026-08-09 — 001-10 monitor and Signal

**`Signal` had to be namespaced: it is a Ruby core module.** A
top-level `Signal < ApplicationRecord` never takes the constant —
references silently resolve to `::Signal` (the one with `Signal.trap`)
and fail as `NoMethodError` on the model's own class methods. Moved to
`Monitoring::Signal` in `app/models/monitoring/`, which is where
CLAUDE.md's architecture said models should live anyway.

**Deviation, recorded rather than fixed in flight:** CLAUDE.md specifies
`app/models/{identity,telemetry,monitoring,cases,...}/`, and the models
written before this point are flat (`Observation`, `Subject`,
`RawEnvelope`, …). Namespacing them all is the right call but is a
wide-touching rename; doing it mid-epic risks breaking work in progress
for no functional gain. Worth one focused refactor later.

**S2C-003 is guarded by a source-level spec**, not only by convention:
it strips comments and then fails if any monitor file mentions Cases or
correlation at all. Comments are stripped because the monitors discuss
Cases at length in prose precisely to explain the boundary — matching
that would make the guard fire on its own documentation.

**Every threshold is a NON-CLINICAL fixture and says so** (HO §175).
The monitor's docstring states plainly what it does and does not claim:
it observes that a recent median differs from a preceding one by more
than a fixture amount and says a human may want to look. It does not
claim the difference is real, meaningful, or biological — that is the
evidence-gated comparison engine's job in epic 003. A Signal is a reason
to look, never a finding.

**`minimum_recent_points` / `minimum_baseline_points` are deliberately
low and are not sufficiency gates.** The real gates are STAT-012/016/018
in epic 003. Duplicating them here would put a statistical threshold in
a place no statistical review would ever look, which is the same trap
001-09's `MINIMUM_READINGS` avoided.

**Platform core ships no threshold defaults at all** (HO §31: "clinical
threshold defaults should not be invented by platform core"). A spec
asserts `Monitoring::Monitor.default_parameters == {}` while the domain
pack carries the real values, so the rule is enforced rather than
intended.

**Direction is part of the dedup semantic identity** (HO §34), so a
reversal is a genuinely new event rather than a duplicate of the
original rise.

One spec had to be rewritten because it tried to `delete_all` derived
signals to reshape a scenario — the append-only grants refused it,
correctly. Replaced with a second subject.

### 2026-08-09 — 001-11 case correlation

**The concurrency spec found a real bug, which is the entire reason
HO §120 makes it must-pass.** Under contention two threads race to
create the same `case_correlation_scope`; one loses on the unique index,
and in PostgreSQL **a failed statement aborts the whole enclosing
transaction**. The `rescue RecordNotUnique` therefore could not recover
— every subsequent statement failed with `InFailedSqlTransaction` and
the correlation died outright. Fixed by wrapping the create in
`transaction(requires_new: true)` so only a SAVEPOINT rolls back.

This is worth dwelling on: the sequential suite passed perfectly
throughout. Nothing short of genuinely concurrent threads would have
surfaced it, and in production it would have appeared as intermittent
correlation failures under load.

**The spec uses real threads on real connections**, with transactional
fixtures off and a `Queue` barrier so all three threads enter the
critical section together. Without the barrier they serialize naturally,
the lock is never contended, and the spec passes while proving nothing.
CI runs it 20 times (`CORRELATION_LOOP_RUNS`), because a lock bug is
intermittent by nature.

**A second hash-chain bug, also found rather than reasoned about.**
`CaseEvent.chain_intact?` returned false immediately, because the digest
was computed before the database round trip: JSONB does not preserve key
order, and PostgreSQL `timestamp(6)` *truncates* microseconds while
Ruby's `iso8601(6)` *rounds*. Both fixed by canonicalizing the payload
and formatting with `%6N`. A chain that always reports itself broken is
worse than no chain — it makes real tampering indistinguishable from
noise.

**`Cases::CaseRecord`, not `Case`.** `case` is a Ruby keyword and
`Cases::Case` reads badly; the table stays `cases`, which is what the
handover and every index reference. Same class of problem as
`Monitoring::Signal`.

**Ambiguity creates a new Case and records why** (S2C-008, HO §41). A
silent merge would attach evidence to a Case it may not belong to and
leave no trace that a choice was made. The `correlation_ambiguous` event
carries the candidate case ids and the resolution.

**Priority is defaulted with a stated reason**, not silently assigned.
The real policy is 002-16; until then `priority_reasons` records
`default_pending_priority_policy` so no Case ever carries an unexplained
ranking (S2C-011/012).

**Domain boundary is spec-enforced** (S2C-025): a spec strips comments
from `app/services/cases/**` and fails on any occurrence of
`blood_pressure`, `hypertension`, `mmHg`, or a hard-coded window. The
rules object is injected, so platform core carries no disease
vocabulary.

### 2026-08-09 — 001-12 and 001-13, epic 001 closed

**The Definition of Done passes as one spec**
(`spec/system/vertical_slice_spec.rb`), unmocked between stages. The
point of a vertical slice is that the seams hold, and every stage
boundary is somewhere an invariant could quietly fail — mocking any of
them would test the mock.

**The demo seed states its own ground truth.** Four subjects, two with a
genuine change and two stable, each labelled in the source. The task
prints what it expects: "a Case for DEMO-002 or DEMO-003 would be a
false positive worth investigating." A demo you cannot check is a demo
that can drift into lying. Verified: exactly two Cases,
DEMO-001 (+21 mmHg) and DEMO-004 (−20 mmHg), and nothing for the stable
pair.

Seeding is deterministic — per-subject-per-day seeds derived from the
MRN — so re-running reproduces the same population rather than a
different one each time.

**Queue ordering is an explicit SQL CASE expression**, not a numeric
column (S2C-023, STAT-024). A rank integer invites arithmetic on it, and
review priority is a policy label rather than a magnitude. A support
engineer reading the query sees the ordering.

**The queue shows `subject.public_id`, never a name.** HO §84 wants work
reason primary and identity secondary; identity is also PHI, and reading
it should be a deliberate, audited act (HO §92). The slice spec asserts
the MRN does not appear in the rendered page.

**Analysis status is displayed but never hides a Case** (S2C-019).
`failed` and `insufficient_evidence` are distinct values and both stay
visible and actionable.

### Epic 001 gate — outstanding

**`No PHI in logs` spec is NOT done.** It is the one item on the epic's
Test Plan still open. The architecture supports it — jobs take ids, not
payloads; `SubjectIdentity#technical_label` exists precisely for this;
audit is separate from technical logging — but the smoke test that would
*prove* it does not exist. Deferred to epic 002 alongside 002-24's audit
work, where there will be more log surface worth asserting against.
Recorded rather than quietly checked off.

Also carried forward: the flat model namespacing deviation (CLAUDE.md
specifies `app/models/{identity,telemetry,monitoring,cases,...}/`, and
only `Monitoring::Signal` and the `Cases::*` models follow it, because
those two were forced by constant collisions).
