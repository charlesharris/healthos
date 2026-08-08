# Epic 005 — External Data + Pilot Hardening

> **ID:** 005-pilot-integration
> **Status:** Blocked by 004
> **Priority:** P0 (gates any real pilot)
> **Handover source:** §144–145 (Milestones 10–11), §183
> **Track:** D converging

## Goal

Leave the synthetic-only world and make the product suitable for a
controlled provider pilot. Several tasks here are decision/review
gates requiring Charles or external reviewers, not autonomous
Claude Code work — those are marked **[HUMAN GATE]**.

## Exit Criteria (handover §144–145, §187)

- Realistic external data enters the canonical pipeline; historical
  backfill matures baselines
- External workflow actions are idempotent; source failures visible
- Cross-tenant security tests pass; audit complete; backups restored
  in test
- Statistical simulation output reviewed **[HUMAN GATE]**
- Regulatory/claims review done **[HUMAN GATE]**
- Do-not-ship list (§188) fully clear

## Tasks

### External data (Milestone 10)
- [ ] 005-01 CSV/batch historical import through RawEnvelope path;
      late-arriving + duplicate handling verified at import scale
- [ ] 005-02 Historical backfill tooling; spec: backfill matures a
      previously immature baseline
- [ ] 005-03 Customer telemetry/event API v1 (§107) with
      org-scoped integration credentials, hashed secrets, source
      binding, rotation, audit (§108)
- [ ] 005-04 Cursor/time pagination + bounded ranges + allowed filter
      sets on telemetry endpoints (§109)
- [ ] 005-05 Minimal FHIR import boundary (map to canonical; FHIR does
      not dictate internal ontology)
- [ ] 005-06 Workflow actions (§91): webhook + FHIR Task adapters,
      async, idempotency keys, after-commit only (S2C-024);
      `Workflows::DispatchActionJob` retry-safe
- [ ] 005-07 Source-health admin view: status, failed envelopes,
      normalization replay (§157)
- [ ] 005-08 Data Acquisition Reality Map for the pilot domain (§106):
      per-signal source, latency, expected completeness, recording
      actor, failure modes **[HUMAN GATE — needs pilot customer facts]**

### Hardening (Milestone 11)
- [ ] 005-09 RLS implementation on highest-risk tenant tables:
      transaction-local context, connection-pool leakage specs,
      admin/service role tests (§12, §172)
- [ ] 005-10 SSO/MFA per pilot customer requirement **[HUMAN GATE —
      decision]**
- [ ] 005-11 Security test suite (§123): cross-tenant, enumeration,
      encrypted-field, PHI-leakage in jobs/logs, export permissions,
      credential scopes
- [ ] 005-12 Backup/restore exercised in a test environment; data
      retention config
- [ ] 005-13 Performance load profile at reference shape (~4,500
      subjects) on queue, ingestion, analysis paths; §111 metrics
      instrumented before any partitioning talk
- [ ] 005-14 Operational + product metrics (§128) and monitor-quality
      report v0 (§129, §151)
- [ ] 005-15 Support/admin tooling completion: replay, correlation
      explanation, analysis rebuild, version-tuple inspection, audited
      support access (§157)
- [ ] 005-16 Full statistical simulation suite as dedicated CI stage;
      results package for review (§102) **[HUMAN GATE — statistical
      reviewer + clinician sign-off, §174]**
- [ ] 005-17 Domain effect thresholds reviewed and promoted from
      NON-CLINICAL fixtures **[HUMAN GATE — §175]**
- [ ] 005-18 Threat model, incident response, secrets rotation docs;
      vendor/deployment compliance validation **[HUMAN GATE]**
- [ ] 005-19 Regulatory/privacy counsel review of product claims and
      CDS posture (independently-reviewable-basis evidence) **[HUMAN
      GATE — §130, §131]**
- [ ] 005-20 Pilot dashboards + pilot success metrics capture (§150)

## Pilot-Ready Checklist (§187) — final gate

- [ ] Customer data mapping documented
- [ ] Backfill tested / security review complete / tenant isolation
      tested / audit complete / backups restored
- [ ] Source failures observable / simulation reviewed / thresholds
      reviewed / claims reviewed
- [ ] Support & replay tooling available / workflow integration works
      / pilot metrics captured
- [ ] Every §188 do-not-ship condition verified false

## Decision Log

_(append here)_
