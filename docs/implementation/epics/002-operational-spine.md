# Epic 002 — Measurement Semantics + Operational Spine

> **ID:** 002-operational-spine
> **Status:** Blocked by 001
> **Priority:** P0
> **Handover source:** §136–139 (Milestones 2–5), §180
> **Tracks:** A (spine) + C (domain pack) + slice of B (measurement)

## Goal

Make measurement behavior itself observable, broaden the hypertension
monitor pack, and complete the Case lifecycle so a team can manually
operate a synthetic hypertension population from the Ops Queue. At
epic gate the product is already a superior alert/case manager —
before any Difference Explorer exists.

## Exit Criteria (handover §136–139)

- System distinguishes observed / expected-but-missing /
  device-not-reporting / not-expected, and computes completeness with
  an explicit denominator (STAT-011)
- System can show "measurement cadence changed" and "source changed"
  as derived signals (STAT-003)
- Multiple compatible Signals correlate into one Case; source-change
  Signals attach contextually; reopen works inside domain horizon
- Operator can: see why a Case exists, assign, triage, watch,
  resolve/dismiss with disposition, view Signal history — Quick Review
  shell included
- Priority has stored reasons; no unexplained ranking (S2C-012)

## Contract References

STAT-002/003/010/011/012/013 (gates recorded; enforcement lands in
Epic 003); S2C-004→017, S2C-023, S2C-025.

## Tasks

### Measurement semantics (Milestone 2)
- [x] 002-01 Expected-measurement model (`Measurement::Expectation`,
      §27): expected / not_expected / unknown opportunities
- [x] 002-02 Full missingness taxonomy on observation pipeline (§28);
      spec: no path zero-imputes (STAT-002) — taxonomy landed in 001-07's
      CHECK constraint; completeness now reports by state
- [~] 002-03 Completeness with explicit denominators (STAT-011) —
      `Measurement::Completeness` done; completeness_delta derived
      signal lands with 002-04's derivation batch
- [x] 002-04 Measurement-frequency, days_since_last,
      manual_entry_frequency derived signals (§29)
- [x] 002-05 Source-change + recording-method-change derivation using
      `devices` transitions (§20, STAT-003)
- [x] 002-06 BP variability derived signal (short-window BP summary is
      the 001-09 daily summary over a narrower window — no new algorithm)

### Monitor pack breadth (Milestone 3)
- [ ] 002-07 Threshold-excursion monitor (fixture thresholds,
      NON-CLINICAL)
- [ ] 002-08 Variability-change monitor
- [ ] 002-09 Measurement-frequency-change monitor
- [ ] 002-10 Source/method-change monitor
- [ ] 002-11 Per-org monitor configuration honored (enable/disable,
      parameters) (§31)

### Case model completion (Milestone 4)
- [ ] 002-12 Case types `monitoring_interruption`, `care_gap`;
      correlation compatibility rules per §42, in the domain pack
      (S2C-025)
- [ ] 002-13 Contextual attachment: source-change Signal attaches to an
      active blood_pressure_change Case when it explains the same work
- [ ] 002-14 Reopen logic with domain reopen horizon; history retained
      (S2C-016/017); spec: outside horizon → new Case
- [ ] 002-15 Correlation explanation persisted per attachment (§158)
- [ ] 002-16 Priority policy + `priority_reasons` (now/today/routine/
      watch); explanation surface (§43, §159, S2C-011/012)
- [ ] 002-17 Deterministic routing policy (team/owner) (§44)

### Lifecycle + queue (Milestone 5)
- [ ] 002-18 Transition services (Triage / StartInvestigation /
      StartWatching / Resolve / Dismiss); controllers never mutate Case
      state directly (S2C-013)
- [ ] 002-19 Watch conditions (time_elapsed, new_observation_count,
      new_signal, threshold_crossed) + evaluation job (§45)
- [ ] 002-20 Dispositions with §46 code list; resolution requires one
      (S2C-015)
- [ ] 002-21 Ops Queue v1: tabs/counts, filters, sort (priority → age →
      detected_at), assignment, pagination, Turbo row refresh (§85–87)
- [ ] 002-22 Quick Review shell: why-is-this-here, trigger Signals,
      timeline, owner, actions, disposition controls (§88)
- [ ] 002-23 Case timeline query object merging observations/events/
      signals/case_events (§90)
- [~] 002-24 `audit_events` for view/assign/state/disposition (§92)
      — table created early alongside the admin UI (see epic 001 Decision
      Log, 2026-08-09). Case/investigation event types still to add here.
- [ ] 002-25 Concurrency specs: resolution vs Signal arrival; watch
      firing vs manual triage (§120)

## Out of Scope

Context/Baseline/Comparison/Findings (Epic 003/004), analysis_status
consumers, cohorts, external workflow actions (Epic 005 — schema may
land), bulk clinical actions.

## Epic Gate

- [ ] Demo seed grows to a small operable population incl. a
      monitoring interruption and a reopened Case
- [ ] Team walkthrough: operate the queue end-to-end without touching
      the console
- [ ] All §120 concurrency specs pass in CI loop
- [ ] Do-not-ship list (§188) items re-checked: no Case duplication
      under concurrency, no hidden source changes

## Decision Log

### 2026-08-09 — 002-04 to 002-06 measurement-behaviour signals

**`SourceProfile` reports the source MIX, never a boolean.** "The source
changed" cannot feed SC §11, whose thresholds are *proportions* — 30%
caps biological evidence at WEAK, 50% suppresses it. A true/false would
throw away exactly the number the gate needs, so the derived signal
carries `changed_share` alongside the boolean.

**And it encodes no threshold of its own.** A spec reads
`source_profile.rb`, strips comments, and fails on any occurrence of
`0.3`, `0.5`, `30` or `50`. The 30/50 boundaries are SC §11's and belong
to the evidence gate in 003-15. This is the fourth time a governed value
could have been buried in a derivation; the spec makes it the last.

**An empty window is indeterminate, not "no change".** A false "source
stable" would let a biological reading through unqualified, which is
precisely what STAT-007's instrumentation-before-biology ordering exists
to prevent.

**`days_since_last` returns `insufficient_input`, never a large number**,
when nothing was recorded. "Infinity days since last" is a different
claim from "no reading in this window", and a numeric stand-in would be
zero-imputation's cousin (STAT-002).

**MAD rather than standard deviation** for variability (SC §29). Specced
against readings whose SD is ~43 and whose MAD is 2 — the outlier moves
one by an order of magnitude and barely touches the other.

**002-06 needed no new algorithm.** A "short-window BP summary" is the
001-09 daily summary evaluated over a narrower window; adding a second
algorithm would have meant two versioned digests computing the same
thing, and reproducibility gets worse rather than better.

Two of my own arithmetic errors are worth noting since both were in
specs rather than code: a MAD I computed as 4 that is actually 2, and a
frequency I expected unrounded when the algorithm rounds to 4dp.

### 2026-08-09 — 002-01 to 002-03 measurement semantics

**Three states, and `unknown` is not folded into either neighbour.**
HO §27 asks for expected / not_expected / unknown, and the distinction
carries weight: treating `unknown` as `not_expected` silently inflates
completeness, while treating it as `expected` fabricates gaps that may
not exist. A dimension with no declared expectation model returns
`Indeterminate`, and completeness over it reports **no ratio at all**
rather than 0 or 1 — both of which would be assertions we cannot make.

**Completeness counts distinct expected DAYS, not observations**
(STAT-005). Three readings on one day are one day's worth; counting
observations would let a single enthusiastic day mask a week of silence.

**The denominator is part of the value, not a footnote.** `Result#to_s`
renders "71.4% (5/7)" because SC §14 requires both and 70% of ten days
is not the same evidence as 70% of a hundred.

**No evidence-ceiling helpers on the result object.** It would have been
convenient to add `weak?`/`strong?` reading STAT-012's bands, and
deliberately is not: mapping completeness to an evidence ceiling is the
gate's job in 003-14, and scattering a governed threshold into a
calculation object is how it stops being reviewable.

**Missingness is reported by state, not as a total.** An instrumentation
gap and a behavioural one reduce completeness identically but mean
different things (STAT-003), so `missing_by_state` preserves the
ten-state taxonomy all the way into the completeness report.

**A DST bug in my own spec, worth recording.** The first window ran
02:00 UTC to 04:59 UTC across 8 March 2026 — the US DST transition — and
silently spanned eight local days instead of seven, so a weekday count
came out 6 rather than 5. My expectation was wrong, not the code. This
is precisely the class of error HO §121 makes a required regression
case, and it appeared within an hour of writing the first completeness
window.
