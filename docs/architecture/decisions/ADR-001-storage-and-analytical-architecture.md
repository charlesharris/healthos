# ADR-001 — Storage & Analytical Architecture

> **Status:** Proposed — needs sign-off on §3 (Timescale) and §6 (JSONB projection)
> **Date:** 2026-08-08
> **Deciders:** Charles Harris
> **Related:** ADR-002 (wide-event artifact shape & partitioning)

## Citation convention

`STAT-001..044` and `S2C-001..025` are defined in handover §164–165 and
cited by ID. Document sections are cited as:

| Prefix | Document |
|---|---|
| `HO §n` | `docs/implementation/handover.md` |
| `SC §n` | `docs/statistics/statistical-contract-v0.1.md` |
| `S2C §n` | `docs/architecture/signal-to-case-v0.1.md` |
| `PD §n` | `docs/product/provider-observability-v0.3.md` |
| `INV-n` | handover §8 core architectural invariants |

## Context

The platform is "Honeycomb for healthcare data." The stack is pinned to
PostgreSQL, and S2C §76 ("What Not to Build Yet") explicitly lists
Kafka, ClickHouse and Elasticsearch as deferred, closing with: *"All
are possible later. None is required to prove the product."*

The question this ADR answers: **is a Postgres-only start an
architectural mistake that will have to be undone?** Specifically, does
declining a time-series database and a columnar store now force design
decisions that become expensive once investigative query performance
matters?

This is worth answering properly rather than deferring to the pin,
because the pinned stack is the *lowest* precedence rule in CLAUDE.md
("framework convention / convenience", rank 6). If the statistical
contract or the architecture demanded a columnar store, the pin would
lose.

## Decision

**Start and stay on PostgreSQL. Exclude Timescale's continuous
aggregates permanently on invariant grounds. Defer ClickHouse behind
written tripwires, and let Kafka arrive with it as CDC transport —
never in the ingestion path, where the transactional outbox is already
the stronger answer.**

The append-only guarantee is met by making the evidence tables
themselves non-mutable (privilege revocation) and the raw payload
bucket WORM, not by adding a streaming log beside mutable tables. See
§4 and ADR-002 Decision 4.

Additionally — and this is the load-bearing half — adopt five
structural commitments that keep a columnar store a *migration* rather
than a *rewrite*. See "Consequences → Seams we must build now."

## Rationale

### 1. We borrow Honeycomb's interaction model, not its storage model

PD §75 states the Honeycomb-shaped requirement directly: *"the system
must preserve rich context and high-cardinality dimensions rather than
reducing every patient to a fixed dashboard."*

But Honeycomb's *storage* thesis — never pre-aggregate, scan wide
events at read time — is the opposite of what these documents specify.
PD §58 defines two materialization modes (operational/precomputed for
queue scoring, monitor evaluation and top Findings; interactive for
ad-hoc investigation), and PD §59 "Queue-First Performance Model"
requires the system to *"proactively compute enough information for
common cases."* PD §34 is titled "Precomputed Findings."

The statistical contract makes read-time scanning impossible anyway:

- Saved Investigations pin evidence and are never rewritten. You cannot
  pin a read-time query result against a live store.
- Every derived value carries exact lineage (EvidenceSet). A scan
  result has no algorithm version and no digest.
- The eligibility pipeline (SC §8) — semantic compatibility (§9),
  source compatibility (§10–11), baseline requirements (§19–22),
  affected-window minimums (§23), completeness (§14–15), differential
  missingness (§16), autocorrelation (§27) — is a stateful gate chain,
  not a `BREAKDOWN`.
- Ranking is lexicographic and explicitly not a numeric score
  (SC §28, §35–36). There is no `ORDER BY` to push down.

So the architecture precomputes into versioned immutable artifacts and
queries *those*. What we borrow from Honeycomb is the investigative
*loop* — start broad, slice by dimension, drill to raw evidence — and
that loop is served by `differences` rows carrying dimension and family
metadata (SC §49–50), not by a scan engine.

**This is a deliberate design choice already present in the governing
documents, not an accident of the pinned stack.**

### 2. The volume is not a columnar workload

At the reference shape in epic 005-13 (~4,500 subjects), with SC §13's
example BP protocol (5 measurement days/week) and a generous 3
readings/day:

| Table | Est. rows/year @ 4.5k subjects |
|---|---|
| `observations` (systolic/diastolic/pulse per reading) | ~15M |
| measurement expectation rows (epic 002-01, incl. non-events) | ~3M |
| `derived_signals` (~6/subject/day) | ~10M |
| **Total core telemetry** | **~30M** |

Thirty million rows/year is a well-indexed PostgreSQL table, not a
distributed analytics problem. At 100k subjects (a large commercial
outcome) it is ~660M rows/year, where partitioning becomes mandatory
and cohort scans genuinely hurt — but that is ~20x growth from pilot,
and it arrives at the Cohort Explorer milestone (M12), already deferred
beyond Epic 005.

**The columnar decision is correctly timed to M12.** Taking it now
means paying migration and operational cost years early, using
cardinality estimates we do not have.

### 3. Timescale: agree with the exclusion, disagree with the escape hatch

HO §6.2 already lists Timescale alongside ClickHouse, Cassandra, Kafka
and Elasticsearch under "Do not introduce … **until measured workload
demonstrates a need**."

This ADR agrees with the exclusion but argues the escape hatch is wrong
for Timescale specifically, because the objection is not about
workload.

Timescale's headline feature is **continuous aggregates**: rollups
maintained by the database. A continuous aggregate is mutable and
carries no algorithm version, no digest, no EvidenceSet and no lineage.
It therefore violates INV-3 ("every derived value has exact lineage")
and cannot be pinned by a saved Investigation (INV-13, INV-14,
STAT-040/041). No amount of measured workload makes that acceptable.

Our `derived_signals` table (HO §26; epic 001-09: algorithm key,
version, digest, `evidence_set_id`) **is** the replacement for
continuous aggregates, and it is the correct one — it is a continuous
aggregate that can prove where it came from.

**Refinement to HO §6.2, for sign-off:** Timescale's *continuous
aggregates* are permanently excluded on invariant grounds, not workload
grounds. Its hypertable partitioning and compression remain excludable
on the ordinary workload grounds §6.2 states — and native PostgreSQL
declarative partitioning covers both if a tripwire ever fires
(ADR-002).

### 4. Kafka is already solved, and the outbox is strictly better

Kafka would buy replay, fan-out and backpressure.

- **Replay** — `raw_envelopes` (append-only) + raw payloads in object
  storage + `bin/replay_envelope`. Raw source truth is never mutated,
  so replay is total.
- **Fan-out** — the transactional outbox: `domain_events` → dispatcher
  → jobs.
- **Backpressure** — Solid Queue's problem, and not yet a problem at
  this volume.

Critically, the outbox is *more correct* than naive Kafka here: it has
no dual-write problem, because the event is inserted in the same
transaction as the state change. The outbox and after-commit
external-call patterns are required **even if Kafka existed**. Building
the outbox in epic 001-03 is therefore not throwaway work — it is the
precondition for ever having a second consumer, columnar or otherwise.

#### Why a streaming log does not substitute for append-only tables

A reasonable objection: shouldn't raw evidence live in a real
append-only log rather than in PostgreSQL tables we merely *promise* not
to mutate?

The two concerns are orthogonal, and conflating them produces a weaker
system than either alone. Kafka provides append-only semantics for a
*stream*; it does nothing to prevent an `UPDATE` on `observations`.

This matters because of what gets read. INV-4, INV-5 and the §131
regulatory gate require that every provider-facing Finding drills down
to source records with an independently reviewable basis — and those
drilldowns query PostgreSQL. A streaming log alongside mutable evidence
tables would give an append-only record of data *adjacent to* the
evidence, leave the evidence itself mutable, and introduce two sources
of truth that can disagree — where the one on screen is the weaker one.

The correct responses are therefore:

- **Immutability of evidence tables** — enforced by privilege
  revocation, not by promise (ADR-002 Decision 4a)
- **A genuine append-only log for raw source truth** — `raw_envelopes`
  + object storage with WORM/Object Lock retention and `content_hash`
  verified on read (ADR-002 Decision 4b). This is *stronger* than
  Kafka, which has retention deletion and admin APIs
- **Tamper-evidence** — hash-chained `audit_events` and `case_events`
  (ADR-002 Decision 4c), which neither Kafka nor grants provide

#### When Kafka does arrive

**Decision: Kafka enters with ClickHouse at T1/T3, as the CDC transport
(Debezium → Kafka → ClickHouse), or not at all.**

That is its natural entry point. Before then it cannot improve
ingestion correctness: with the outbox in place, Kafka can only be an
*outbox consumer*, never a replacement for it — writing to Kafka
directly at ingestion reintroduces the dual-write problem the outbox
exists to eliminate. Its only remaining value is fan-out to a second
consumer, and there is no second consumer until the columnar store.

This is consistent with HO §6.2, which excludes Kafka "until measured
workload demonstrates a need"; T1/T3 is that measurement.

### 5. Two current defaults are columnar-hostile and must change

These are the substantive findings of this review. Both bite us *today*
in PostgreSQL, independent of any future migration.

#### 5a. Missingness must be materialized, never inferred from row absence

SC §12 defines a **ten-state** taxonomy, not a boolean and not the
four-state summary in CLAUDE.md:

```
not_expected            observed              expected_but_missing
source_unavailable      device_not_reporting  manual_entry_absent
invalid_measurement     excluded_by_rule      late_not_yet_arrived
unknown
```

and states flatly: *"Do not collapse all missingness into `NULL`."*
SC §17 forbids zero-imputation.

If `expected_but_missing` is representable only as *"no row exists"*,
then every `GROUP BY` ever written against telemetry silently
zero-imputes. That is an SC §17 violation **by architecture rather than
by bug** — no code review catches it, because the offending code looks
correct. It also collapses ten distinguishable states into one, losing
`device_not_reporting` vs `manual_entry_absent` vs
`late_not_yet_arrived`, which SC §18 requires as analyzable
measurement-behavior dimensions.

**Requirement:** missingness state is an enumerated column on a
materialized row. Epic 002-01's expectation model generates rows for
non-events. Absence of a row must never carry analytical meaning.

This is also exactly what makes the data portable — a columnar store
computing `COUNT()` over sparse rows reproduces the same bug at larger
scale.

#### 5b. Denominators are stored, not computed

SC §3.6 makes denominators mandatory and SC §14 requires the UI to
expose *"both the ratio and denominator."* This ADR records the
architectural corollary: a stored denominator makes every analytical
artifact **readable without recomputation**, so it can be pinned by a
saved Investigation and exported to any store without carrying its
computation context.

Generalized: **analytical artifacts must be self-contained.** If
rendering a Finding requires re-deriving anything, the artifact is
under-specified.

Note SC §6 (raw sample count vs analytical unit count) and SC §15's
rule that *"the weaker side controls the maximum evidence level"* both
require storing affected-side and baseline-side denominators
separately, not a single ratio.

### 6. Row-per-dimension ContextValue — defer the projection (revised)

HO §171 already identifies this tension precisely, listing the cons of
row-per-dimension typed `context_values` as *"row explosion, cohort
query joins, less Honeycomb-like physical shape"*, naming both
alternatives (Context dimensions JSONB; later, a wide analytical
store), and recommending:

> *"choose correctness/inspectability first. Revisit physical
> representation after real cohort/query profiling."*

**An earlier draft of this ADR proposed adding a wide JSONB projection
to `contexts` on day one. That is withdrawn.** The justification for
building a seam early is irreversibility, and this seam is not
irreversible: because Contexts are immutable snapshots, the projection
is a pure function of rows that never change, so it can be backfilled
at any future date with no drift risk and no coordination. It is
therefore exactly the kind of physical-representation change HO §171
says to make *after* profiling.

**Decision: row-per-dimension only, per HO §171 and epic 003-03. Add
the JSONB projection when tripwire T1 or T3 fires.**

What we do commit to now, because these *are* irreversible:

- `context_values` carries the difference-family metadata columns
  (semantic / source / derivation) required by STAT-031 and SC §49–50,
  so family-correlation suppression never needs a schema change.
- Cohort reads go through `app/queries/`, so swapping the physical
  representation later touches one layer.
- Per PD §57, high-cardinality analytical dimensions inherit privacy
  classification — recorded here so that any future projection carries
  the privacy class forward rather than smuggling restricted dimensions
  into an unclassified blob.

## Tripwires — when to re-open the columnar decision

**HO §153 "Scale-Out Triggers" already defines this framework** — "only
consider service/storage extraction after measurement" — and names
three qualitative triggers for an analytical store:

> - cohort ContextValue queries dominate Postgres
> - index/storage growth becomes operationally painful
> - interactive cohort latency misses product targets

HO §111 separately lists what to instrument (table size, index size,
ingestion latency, query latency, vacuum behavior, maintenance cost).
Neither states a number. **T1–T8 below are the quantification of
HO §153's triggers against HO §111's metrics** — not a new framework.

Re-open this ADR when **any** of them is observed in production or at
load-test scale.

| # | Tripwire | HO §153 trigger | HO §111 metric |
|---|---|---|---|
| T1 | p95 cohort/BREAKDOWN-style query > 2s | interactive cohort latency | query latency |
| T2 | `observations` exceeds 500M live rows | index/storage growth | table size |
| T3 | `context_values` exceeds 1B live rows | cohort ContextValue queries dominate | table size |
| T4 | `differences` exceeds 250M live rows | index/storage growth | table size |
| T5 | Full-org baseline re-materialization exceeds a 1h window | operationally painful | maintenance cost |
| T6 | Ops Queue p95 render > 1s with the HO §110 indexes in place | — | query latency |
| T7 | Autovacuum cannot keep pace on any telemetry table | operationally painful | vacuum behavior |
| T8 | Ingestion p95 write latency > 250ms | (HO §153 ingestion-service trigger) | ingestion latency |

Two other HO §153 extraction candidates are **out of scope for this
ADR** and should not be conflated with the storage question:

- **Ingestion service** — triggered by throughput or a customer-side
  collector requirement, not by storage shape. T8 is the closest
  signal.
- **Specialized statistics service** — triggered by "methods require
  libraries unavailable/awkward in Ruby." Worth watching from Epic 003
  onward: median/MAD, robust standardized effect and leave-one-out
  sensitivity are all comfortable in Ruby, but if the domain ever needs
  methods that are not, that is a compute decision, not a storage one.
  HO §153: "Rails remains control plane unless proven otherwise."

T1 and T3 are the expected first movers, and both point at Cohort
Explorer (M12) rather than at the operational or investigative paths.
T2/T7/T8 point at partitioning (ADR-002), not at a columnar store —
they are different decisions with different triggers.

**Expected order of failure**, stated honestly so we recognize it early:

1. Cohort BREAKDOWN over EAV `context_values` — join-bound
2. Ops Queue sort/filter under load — fix with a denormalized queue
   projection table (S2C §51 already specifies a queue read model), not
   a new datastore
3. Baseline rebuild scanning `observations` — fix with partitioning +
   BRIN on time
4. Raw ingestion volume — last, likely years out

Only #1 argues for a columnar store. #2–#4 are PostgreSQL-internal.

## Consequences

### Seams we must build now (the real cost of this decision)

1. **Query-object gateway.** No controller or service issues raw
   ActiveRecord relations against telemetry or analytical artifacts.
   All analytical reads go through `app/queries/`. This is the swap
   seam; without it a future migration touches every call site.
2. **`differences` kept wide and self-contained.** HO §68 already
   specifies a wide row with family metadata as columns; ADR-002
   proposes one small addition. This is the future columnar export
   target.
3. **Materialized missingness and stored denominators** (§5a, §5b).
   The only genuinely irreversible items on this list — they change
   what data exists, not how it is stored.
4. **Replayable raw log** — `raw_envelopes` + object storage (epic
   001-05). This is what makes any future backfill into a second store
   possible at all.
5. **Partition-key strategy pre-decided but not applied.** Per HO §111
   we do not partition on day one; ADR-002 records which key each table
   must use *when* a tripwire fires, because the unique-constraint
   interaction constrains that choice non-obviously.

With those five in place, adopting ClickHouse later is "CDC two tables
and repoint some query objects," not "re-architect the platform."

### Accepted costs

- Cohort Explorer (M12) needs real profiling work and may be the
  feature that forces the columnar decision. Accepted — deferred and
  unscoped today.
- Expectation rows for non-events (§5a) add ~3M rows/year at reference
  shape. Accepted; this is the cost of STAT-002/010 being enforceable
  rather than aspirational.
- Cohort queries will be join-bound over `context_values` until T1/T3
  fires. Accepted per HO §171.

### Explicitly not decided here

- Whether Cohort Explorer ships on PostgreSQL or a columnar store —
  decided at M12 against T1/T3 evidence.
- When to partition — ADR-002, triggered by T2/T7/T8.
- Any read-replica or CQRS split. Not needed at reference shape.

## Deviations from governing documents

Per CLAUDE.md, this ADR is precedence rank 6 and yields to the handover
(rank 5) and the contracts (ranks 2–3). Two deliberate refinements
require sign-off:

| # | Section | Relationship to source |
|---|---|---|
| D1 | §3 Timescale | HO §6.2 excludes it "until measured workload demonstrates a need." This ADR argues continuous aggregates are excluded on **invariant** grounds (INV-3, INV-13/14) that workload can never satisfy. Strengthens §6.2; does not contradict it. |
| D2 | Tripwires | HO §153 defines the trigger framework qualitatively and HO §111 lists the metrics; neither states a number. T1–T8 quantify §153's triggers against §111's metrics. Additive, and weaker than it first appeared — the framework is the handover's, only the thresholds are ours. |
| D7 | §4 Kafka entry point | HO §6.2 excludes Kafka pending measured need. This ADR names T1/T3 as that measurement and fixes its role as CDC transport for the columnar migration, never as an ingestion-path component. Additive. |

An earlier draft also proposed a day-one JSONB projection on `contexts`
and day-one partitioning. Both are **withdrawn** as contradicting
HO §171 and HO §111 respectively. See §6 above and ADR-002.

## Documentation issue

CLAUDE.md's missingness summary is lossy — it describes a four-state
taxonomy where SC §12 and HO §28 define ten. Since the summary is what
gets read most often, correcting it is worthwhile.
