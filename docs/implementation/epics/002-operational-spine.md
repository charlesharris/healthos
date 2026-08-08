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
- [ ] 002-01 Expected-measurement model (`Measurement::Expectation`,
      §27): expected / not_expected / unknown opportunities
- [ ] 002-02 Full missingness taxonomy on observation pipeline (§28);
      spec: no path zero-imputes (STAT-002)
- [ ] 002-03 Completeness + completeness_delta derived signals with
      explicit denominators (STAT-011)
- [ ] 002-04 Measurement-frequency, days_since_last,
      manual_entry_frequency derived signals (§29)
- [ ] 002-05 Source-change + recording-method-change derivation using
      `devices` transitions (§20, STAT-003)
- [ ] 002-06 Short-window BP summary + BP variability derived signals

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
- [ ] 002-24 `audit_events` for view/assign/state/disposition (§92)
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

_(append here)_
