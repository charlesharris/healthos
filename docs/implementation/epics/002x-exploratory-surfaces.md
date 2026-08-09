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

## Open defect (found 2026-08-09, blocks 002x-01)

### D1 — the cohort prior uses the wrong analysis unit (SC §66)

**SC §66:** *"Default cohort analysis unit: `subject`, not individual
observations. Subject-level features are computed first… This prevents
patients with dense telemetry from dominating the sample."*

`TelemetryProfileQuery#cohort_prior_scope` pools **raw readings** across
subjects. A subject measuring four times a day currently contributes eight
times the weight of one measuring daily, and "1% of readings are manual
entry" is not the same claim as "1 subject in 47 uses manual entry" — the
second is the one a provider can act on.

This is a correctness defect in shipped code, not a missing feature. It also
means the current cohort prior is not yet the thing review asked for:
"comparing against other patients' baselines".

**Not silently fixable.** Changing the unit changes what every cohort bar
means, so it needs the UI to say which unit is in use — which is 002x-01.

---

## Tasks

### Cohort comparison that means something (the review's point)

- [ ] **002x-01 Subject-level cohort features (SC §66).** Compute a
      per-subject summary over the range first, then compare distributions.
      The dimension strip in cohort mode reports **share of subjects**, and
      says so; reading-level shares remain available but are labelled as a
      different question. Fixes D1.
- [ ] **002x-02 Compare against other subjects' baselines, not their raw
      readings.** The subject-level feature that matters is each subject's
      own baseline level over the window. "Where does this subject's
      selection sit in the distribution of program baselines" is the question
      review actually asked for, and it is a different question from "where
      does this reading sit among all readings".
      _Depends on per-subject baselines being computable in bulk — see Risks._
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

**002x-02 may not be affordable live.** Computing `Baselines::PersonalRecent`
for 47 subjects on each request is 47 baseline builds per page. If it is not
fast enough, the honest answers are materialized `BaselineInstance` rows
(Epic 003-09+) or a stated staleness — not a cheaper approximation that keeps
the label "baseline".

**Changing the cohort unit changes published numbers.** Anyone who has read a
cohort percentage from this surface has read a reading-level share. The
change must be visible in the UI, not just correct in the query.

---

## Gate

- [ ] Cohort comparison states its analysis unit, and that unit is `subject`
      (SC §66)
- [ ] No surface in this epic emits evidence strength, a rank, or a persisted
      artifact
- [ ] Every cap, fold and refusal on these surfaces announces itself
- [ ] The exploration loop is completable from the keyboard

## Decision Log

### 2026-08-09 — opened

Split out of Epic 002's decision log, which had accumulated five entries of
exploratory-UI work that was not really the operational spine. Opened with
D1 outstanding: review pointed at the "Not enough to compare" dead end, and
the underlying cause turned out to be the analysis unit rather than the
message.
