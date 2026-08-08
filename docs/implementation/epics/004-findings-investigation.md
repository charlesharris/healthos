# Epic 004 — Findings + Investigation Workbench

> **ID:** 004-findings-investigation
> **Status:** Blocked by 003
> **Priority:** P0
> **Handover source:** §142–143 (Milestones 8–9), §182
> **Tracks:** B converging with A

## Goal

Cluster Differences into domain-authored Findings with conservative
evidence aggregation, publish them to the queue and Quick Review, and
expose the Honeycomb-style investigative loop in the Workbench. This
is where the product stops being good alert management and becomes
Human Observability.

## Exit Criteria (handover §142–143)

- Correlated same-family derivatives never double-count (STAT-033);
  independent support raises a Finding at most one level (STAT-034)
- Measurement/instrumentation Finding outranks a confounded biological
  Finding (STAT-035) — the Scenario B demo works
- All-weak result does not produce a fake Top Finding; queue shows
  "No reliable distinguishing pattern found"
- Provider can independently review the basis of every Finding down to
  source records (§82, §131)
- Saved Investigations are immutable; new data shows a stale indicator
  and offers explicit re-run (STAT-040/041)

## Contract References

STAT-031→036, STAT-040/042; regulatory gate §131.

## Tasks

### Findings (Milestone 8)
- [ ] 004-01 FindingDefinition YAML model + versioning/digest (§73):
      hypertension `blood_pressure_pattern_changed` + generic
      `measurement_behavior_changed`, `instrumentation_changed`,
      `data_quality_degraded`
- [ ] 004-02 `findings` + `finding_differences` (§74)
- [ ] 004-03 Evidence aggregation exactly per §75: strongest component
      start; same family never boosts; independent support max +1;
      never exceed STRONG; contradiction downgrades/marks mixed;
      several WEAK correlated can never reach STRONG
- [ ] 004-04 Measurement-Finding precedence in ranking (§76, STAT-035)
- [ ] 004-05 Evidence-against-confounders support ("device unchanged,
      method unchanged, completeness stable") as supporting context,
      never proof (§77)
- [ ] 004-06 Top-Finding publication onto Case pointers via analysis
      coordinator; queue columns: top Finding, evidence strength, data
      quality, baseline maturity, analysis freshness (§84)
- [ ] 004-07 Quick Review upgrade: top Findings + evidence strength +
      source/instrumentation status (§88)
- [ ] 004-08 Deterministic reason-code → user-facing explanation
      rendering; no LLM anywhere in this path (§83)

### Investigation Workbench (Milestone 9)
- [ ] 004-09 Timeline component (left): observations, events, signals,
      case events, finding generation, dispositions (§89–90);
      Stimulus range selection
- [ ] 004-10 Center: affected window, default + allowed alternate
      baseline selector, Findings panel, Differences panel, filters;
      rerun Comparison on change (interactive materialization mode)
- [ ] 004-11 Evidence Inspector (right) rendering the full §82
      checklist: affected/baseline values, raw counts, usable
      denominators, spans, completeness, effect, evidence reasons,
      source mix, stability, method+version, exact input records.
      _If any field can't be rendered from persisted data, the Epic
      003 implementation is incomplete — file a defect, don't patch
      around it._
- [ ] 004-12 Saved Investigations (§81): pinned artifacts + version
      tuple + evidence snapshot set; immutability specs
- [ ] 004-13 Stale-data indicator + explicit re-run (never silent)
- [ ] 004-14 Provenance drilldown from any Difference to RawEnvelope
- [ ] 004-15 Audit events: investigation viewed, evidence expanded,
      identity viewed (§92)

### Demo scenarios (gate instrument)
- [ ] 004-16 §105 scenarios in demo seed + system specs:
      A (real pattern → MODERATE/STRONG BP Finding, instrumentation
      stable), B (cuff→manual same-day → instrumentation STRONG,
      biology WEAK/suppressed), C (3 affected days → Case exists,
      insufficient_evidence, watch condition for more data)

## Epic Gate

- [ ] All three §189 north-star outputs demonstrable from seed data
- [ ] §188 do-not-ship checks: no Finding without evidence drilldown,
      no confident Top Finding from all-weak, saved Investigations
      immutable
- [ ] System specs for full provider workflow (§122)

## Decision Log

_(append here)_
