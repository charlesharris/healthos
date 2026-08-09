# Epic 002x — Exploratory Surfaces

> **ID:** 002x-exploratory-surfaces
> **Status:** In progress — shipped increments listed under "Landed"
> **Priority:** P1
> **Relates to:** HO §84–88 (queue, Quick Review); SC §20–25, §62–68
> **Deliberately NOT:** Epic 004's Investigation Workbench

## Why this exists as its own epic

The Ops Queue and Quick Review are Epic 002. The exploratory layer built on
top of them — distribution charts, drag-to-select, dimension drill-down,
cohort Explore — arrived ahead of the epic plan and does not belong to any
of them cleanly. It is Epic 004's investigative loop in shape, but built
**descriptive-only** because Epic 003's artifacts do not exist yet.

That constraint is the whole design and must not erode:

| This epic may | This epic may not |
|---|---|
| Count, share, denominate, median | Assign evidence strength |
| Show what is in the database | Rank Differences or Findings |
| Name the baseline it used | Persist an analytical artifact |
| Refuse to compare | Apply an evidence gate |

Anything in the right column is Epic 003/004 work. If a task here starts to
need it, the task is misfiled — say so rather than building a second,
ungoverned copy of the statistical core inside a view.

**That happened once, and this is the record of it.** 002x-02 needed
per-subject baselines, which are Epic 003 artifacts. Rather than approximate
one inside a view, the materializer was built as 003 work
(`Baselines::Materialize`, logged against 003-08) and these surfaces only
READ what it wrote. The rule holds: nothing in `app/queries/ops` or
`app/views/ops` creates an artifact.

---

## Landed

- Distribution chart: program density + subject marks, explicit missingness
  (STAT-002), monochrome evidence meter, table-view twin
- Drag-to-select as a URL; value-bounded selections flagged as conditioned on
  the outcome
- Dimension strip ordered by contract precedence, never by effect size
  (STAT-019/024, STAT-035)
- Drill-down into any dimension value; scope chips; `where` whitelist
- Cohort Explore with small multiples (shared colour scale always, shared
  value axis only within one measure)
- Baseline named with SC §21 maturity; comparison refused when either side is
  below its governed minimum (SC §22/§23)
- SC §64 fallback: an unstated baseline falls back to the cohort prior when
  the personal record is immature, and says so — the dead-end "Not enough to
  compare" screen is gone

---

## Closed defect

### D1 — the cohort prior used the wrong analysis unit (SC §66) — CLOSED

**SC §66:** *"Default cohort analysis unit: `subject`, not individual
observations. Subject-level features are computed first… This prevents
patients with dense telemetry from dominating the sample."*

`TelemetryProfileQuery#cohort_prior_scope` pooled **raw readings** across
subjects. A subject measuring four times a day contributed eight times the
weight of one measuring daily, and "1% of readings are manual entry" is not
the same claim as "1 subject in 47 uses manual entry" — the second is the one
a provider can act on.

A correctness defect in shipped code, not a missing feature. It also meant
the cohort prior was not yet the thing review asked for: "comparing against
other patients' baselines".

**Not silently fixable.** Changing the unit changes what every cohort bar
means, so it needed the UI to say which unit is in use — done in 002x-01,
which puts a `per subject` / `per reading` chip on the baseline bar.

---

## Tasks

### Cohort comparison that means something (the review's point)

- [x] **002x-01 Subject-level cohort features (SC §66).** Compute a
      per-subject summary over the range first, then compare distributions.
      The dimension strip in cohort mode reports **share of subjects**, and
      says so; reading-level shares remain available but are labelled as a
      different question. Fixes D1.
- [x] **002x-02 Compare against other subjects' baselines, not their raw
      readings.** The subject-level feature that matters is each subject's
      own baseline level over the window. "Where does this subject's
      selection sit in the distribution of program baselines" is the question
      review actually asked for, and it is a different question from "where
      does this reading sit among all readings".
      _Resolved by materializing BaselineInstance rows — see the decision log._
- [ ] **002x-03 SC §25 cohort minimums.** Provider-facing Difference ranking
      needs ≥20 affected and ≥20 baseline subjects. We do not rank, so
      "descriptive aggregate display" applies — but the surface must state
      which side it is on rather than leaving the reader to assume ranking
      strength it never had.
- [ ] **002x-04 SC §67 matched cohorts.** Unmatched descriptive comparison is
      what v0.1 supports; explicit rule-based stratification is optional.
      Whichever is in use, *"if cohort groups differ materially on known
      matching dimensions, the UI must disclose that."* Today we disclose
      nothing because we match on nothing — that is itself the disclosure to
      make.
- [ ] **002x-05 Baseline type selector beyond two modes.** SC §20 names eight
      types; two exist. `pre_intervention` and `phase_matched` are the ones
      SC §62 says should replace trailing baselines for non-stationary
      processes. Requires Epic 003 definitions — surface the ones that exist
      and name the ones that do not, rather than implying the list is closed.

### One query, many views

- [ ] **002x-06 View tabs over one selection.** Honeycomb's Results /
      BubbleUp / Traces / Raw Data. Ours: Distribution, Breakdown, Subjects,
      Readings. Same selection, same scope, same URL — only the rendering
      changes. Today each of these is either a separate surface or a
      `<details>` toggle.
- [ ] **002x-07 The query spec as editable chips.** Measure, range, scope,
      selection, baseline and split are all in the URL and only some are
      visible. One row that states the whole query and lets any part of it be
      changed or removed — the thing that makes Honeycomb feel like a query
      tool rather than a dashboard.
- [ ] **002x-08 Keyboard path through the loop.** `/` to focus the query row,
      arrows to move the selection, `Enter` to drill. Drag is a mouse
      accelerator; the loop should be completable without one.

### Debt

- [ ] **002x-09 Extract a value-formatting type.** Enum values and opaque
      identifiers have now shared a `tr("_", " ")` path three times
      (row labels, scope chips, and nearly the panel titles). Formatting
      belongs to the value, not to each call site.
- [ ] **002x-10 Panel count is capped at 6 with no statement.** Every other
      cap on these surfaces announces itself; this one does not.

---

## Risks

**~~002x-02 may not be affordable live.~~** Settled: materialized
`BaselineInstance` rows. The surface reads artifacts and states their `as_of`;
nothing computes a baseline during a page render.

**Changing the cohort unit changes published numbers.** Anyone who has read a
cohort percentage from this surface has read a reading-level share. The
change must be visible in the UI, not just correct in the query.

---

## Gate

- [x] Cohort comparison states its analysis unit, and that unit is `subject`
      (SC §66)
- [ ] No surface in this epic emits evidence strength, a rank, or a persisted
      artifact
- [ ] Every cap, fold and refusal on these surfaces announces itself
- [ ] The exploration loop is completable from the keyboard

## Decision Log

### 2026-08-10 — 002x-01/02: the cohort unit is now the subject

`baseline_instances` existed since 003-07 and **nothing had ever written a
row**. `PersonalRecent` could build a baseline; nothing persisted one. That
was tolerable while baselines were only ever needed for the subject on
screen, and stopped being tolerable the moment a cohort question was asked —
"where does this subject sit among the program's baselines" is 47 baseline
builds per page load, which is not a read.

So: `Baselines::Materialize` (idempotent on HO §26 identity, immutable,
records its inputs as an EvidenceSet per INV-3), `MaterializeCohort` for a
whole organization, and a job. Demo seed materializes them, so a fresh demo
does not show an empty cohort and look like a bug.

**The table could not say what it was a baseline OF.** No semantic key — so
"this subject's systolic baseline" was not a query it could answer — and no
centre or scale, so SC §29's robust standardized effect had nothing to
compute from. `Result` has carried all four since 003-08; the table never
learned them. Added by migration; the table was empty in every environment,
so the NOT NULLs went in outright.

**D1 closed.** The cohort comparison now counts subjects. A subject is
assigned their *dominant* value in each window, because that partitions —
every subject lands in one bucket and the shares sum to a whole. "Used manual
entry at least once" is a real question too, and a different one; it would
need its own card rather than quietly changing what these bars mean.

The analysis unit is named on the baseline bar (`per subject` / `per
reading`), because "1% of readings are manual entry" and "1 subject in 47 uses
manual entry" are different claims and the bars look identical.

**002x-02** reports the distribution of other subjects' baseline centres —
median, IQR, range — with the subject's own selection placed in it as a
percentile and an inside/outside-the-middle-half flag. A percentile rather
than a z-score, because a z-score implies a shape nobody has checked; SC §29
uses a robust scale for the same reason. The card states subject coverage
(how many have a baseline out of how many have readings), the maturity mix,
the `as_of`, and SC §25's 20-subject ranking floor when the cohort is below
it.

Verification note: this session's browser checks were unreliable for a while
because **two application instances were bound to :3000** — a Docker container
and a native puma — and only one had the migration. Both answered `/up` with
200, so requests round-robined between them. The rspec suite was the honest
gate throughout. Duplicate listeners now stopped.

### 2026-08-09 — opened

Split out of Epic 002's decision log, which had accumulated five entries of
exploratory-UI work that was not really the operational spine. Opened with
D1 outstanding: review pointed at the "Not enough to compare" dead end, and
the underlying cause turned out to be the analysis unit rather than the
message.
