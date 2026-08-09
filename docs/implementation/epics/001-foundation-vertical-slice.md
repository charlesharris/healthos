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
- [ ] Code/YAML-defined registry with key, version, kind, value type,
      unit, privacy class; immutable by version
- [ ] Keys: `health.vital.blood_pressure.systolic`, `.diastolic`,
      `health.vital.pulse`, plus `health.measurement.*` keys reserved
- [ ] `bin/definitions verify` digest tooling + CI check (§125)
- [ ] Spec: changing a definition without version bump fails verify

### 001-07 Canonical telemetry (BP path only)
- [ ] `observation_groups`, `observations` per §16–17 including
      semantic_key/version, quality_state, normalizer_key/version,
      CHECK constraint on value representation
- [ ] `events`, `intervals`, `devices` tables created (schema only —
      exercised in Epic 002)
- [ ] Missingness-taxonomy-ready fields present (STAT-010); full
      expectation model deferred to Epic 002

### 001-08 Normalizer + provenance
- [ ] Versioned normalizer interface; synthetic-BP-JSON normalizer v1
- [ ] Normalization job (thin wrapper), idempotent on
      RawEnvelope + normalizer version (§96)
- [ ] Admin provenance drilldown view: canonical BP → raw envelope →
      stored payload
- [ ] Specs: re-run normalization → no duplicate canonical rows;
      every observation traces to its envelope (STAT-006 gate fields
      populated; invariants 1–3)

### 001-09 Daily BP derived summary
- [ ] `derived_signals` table per §26 with algorithm key/version/digest
      and `evidence_set_id`
- [ ] `evidence_sets` / `evidence_items` generic tables (§22)
- [ ] Daily BP summary algorithm v1 with input lineage recorded
- [ ] Spec: recompute with same inputs → same identity, no duplicate;
      lineage resolves to exact input observations

### 001-10 One trajectory monitor → Signal
- [ ] Monitor interface (§30), `monitor_configurations`,
      `monitor_evaluations` (§31–32)
- [ ] Hypertension trajectory-change monitor v1 (threshold values are
      NON-CLINICAL fixtures — mark them as such)
- [ ] `signals` table per §33; dedup key per §34; unique
      (org, deduplication_key)
- [ ] Specs: monitor retry → same Signal returned, not duplicated
      (S2C-002); monitor never touches Case tables (S2C-003); Signal
      immutable (S2C-001)

### 001-11 Case correlation + Case
- [ ] `case_correlation_scopes` with unique (org, subject, domain);
      `Cases::CorrelateSignal` using SELECT ... FOR UPDATE (§35)
- [ ] `cases` per §36 (no STI), `case_signals` unique
      (case, signal), `case_events` append-only (§38–39)
- [ ] Correlation contract §40 for the single case type
      `blood_pressure_change`; ambiguity → new Case +
      `correlation_ambiguous` (S2C-008)
- [ ] Concurrency spec (must pass, §120): 3 near-simultaneous
      compatible Signals, 3 concurrent jobs → 1 Case, 3 CaseSignals,
      complete CaseEvent history (S2C-005/006/007)

### 001-12 Ops Queue row (read-only v0)
- [ ] `Ops::CaseQuery` (org + user context required)
- [ ] Minimal queue page: work reason primary, subject secondary,
      priority placeholder, status, age (§84)
- [ ] Indexes from §110 for cases/signals/case_signals/case_events
- [ ] System spec: log in → see the Case created by the slice

### 001-13 End-to-end slice spec + demo seed
- [ ] The Definition of Done system test, as one spec
- [ ] `bin/demo_seed` v0: a handful of synthetic subjects, one with a
      trajectory change
- [ ] `bin/replay_envelope` v0 stub that re-runs normalization for one
      envelope

## Out of Scope (resist the pull)

Context, Baseline, Comparison, Findings, priority policy, routing,
transitions beyond `new`, watch conditions, dispositions, Quick
Review, multiple monitors, FHIR, CSV import, RLS implementation
(schema must remain RLS-compatible), SSO/MFA.

## Test Plan (epic gate)

- [ ] CI green including `bin/definitions verify`
- [ ] Cross-tenant specs pass on every surface added
- [ ] Idempotency specs: envelope, normalization, derived signal,
      Signal, CaseSignal
- [ ] Concurrency correlation spec passes reliably (run 20x in CI loop)
- [ ] No PHI in logs spec (log scrubbing smoke test)
- [ ] Definition of Done system spec passes

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
