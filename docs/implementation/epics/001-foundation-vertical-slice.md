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
- [ ] `organizations`, `users`, `organization_memberships` (role on
      membership, NOT on user), `teams`, `team_memberships`
- [ ] Session auth + invitation-based membership (minimal UI)
- [ ] `Current` context (organization + membership); policy-object
      authorization skeleton
- [ ] Every tenant-facing table from here on: NOT NULL
      `organization_id`, FK, tenant-prefixed indexes
- [ ] Specs: cross-org access denied at controller and query level
- **Contract:** INV-31; S2C-022

### 001-03 Transactional outbox skeleton
- [ ] `domain_events` table (§49 columns), `Outbox::DispatchJob`
      dispatcher converting durable events → Active Jobs
- [ ] Helper for "insert domain_event inside the same transaction as
      the state change"
- [ ] Specs: commit + dispatcher crash → event redelivered; dispatch is
      idempotent (S2C-020, S2C-021)

### 001-04 Subject model
- [ ] `subjects` (public_id, org, status, timezone) /
      `subject_identities` (PHI fields, application-level encryption) /
      `subject_identifiers` (system+value unique per org)
- [ ] Spec: identity fields encrypted at rest; identifiers resolve a
      subject idempotently

### 001-05 Sources + RawEnvelope + object storage
- [ ] `sources` (encrypted configuration, status, last_success/failure)
- [ ] `raw_envelopes` per §13.1: unique
      (org, source, source_record_id, source_record_version);
      content_hash; payload in object storage, key+hash in DB
- [ ] Append-only enforced (no update/destroy paths; DB trigger or
      readonly? — prefer service-layer + spec; record decision below)
- [ ] Ingestion contract: authenticate source → identity/hash → insert
      if new → enqueue normalization via outbox
- [ ] Spec: same record POSTed twice → one RawEnvelope, one
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
