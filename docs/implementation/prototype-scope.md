# Prototype Scope — "Serious Prototype"

> **Status:** Active
> **Date:** 2026-08-08
> **Decided by:** Charles Harris

## Intent

Build as if launching a business; build to learn from and replace.
Quality of thinking is not reduced — *surface area* is.

The handover already encodes this distinction: **HO §186 "Definition of
MVP"** vs **HO §187 "Definition of Pilot-Ready."** §186 explicitly
accepts "real/**synthetic** longitudinal data."

**Target: HO §186. Not HO §187.**

## Parameters

| Question | Answer | Consequence |
|---|---|---|
| Real PHI? | **Synthetic only, ever** | Largest scope reduction; see below |
| Audience | **Design partner / friendly provider** on synthetic data | Operator UX is first-class, not minimum |
| Deployment | **Local + CI only for now** | No hosted environment; stay deployable in shape |

## What migrates to v2 — invest disproportionately here

A throwaway prototype is only worth building if something survives it.
These do:

1. **`spec/support/synthetic_health/` and the HO §100–101 scenarios.**
   The crown jewel. It is the acceptance instrument for the entire
   statistical engine and it proves v2 correct on its first day. Epic
   003 already mandates building it *before* the engine (003-01).
   Treat scenario coverage as a deliverable, not test scaffolding.
2. **Definitions** — semantic registry, monitors, ContextDefinitions,
   BaselineDefinitions, FindingDefinitions. Code/config by design
   (HO §168), so they port directly.
3. **Schema design and ADR reasoning**, including which shapes proved
   wrong.
4. **Measured answers to the ADR-001 tripwires.** "Does PostgreSQL
   carry this?" is a question the prototype exists to answer. This
   makes performance instrumentation *more* relevant here, not less.

Rails plumbing, controllers, views and deployment are expected losses.

## In scope

- **Epics 001–004 in full**, to the HO §186 operator loop
- **005-06 workflow actions**, minimal — HO §186 requires "send an
  action outward"; a webhook adapter with idempotency keys is enough
- **005-13 / 005-14 instrumentation**, reduced to the ADR-001 T1–T8
  tripwire metrics and HO §128 operational metrics
- **HO §127 demo seed at full richness** — 100+ subjects and the three
  canonical scenarios. With a design partner this is the primary
  artifact they explore, so it moves earlier than its epic position
  suggests

## Out of scope (synthetic-only)

Deferred because no real PHI will exist, **not** because prototypes cut
corners:

- 005-09 RLS implementation. Schema stays RLS-compatible per HO §172:
  `organization_id NOT NULL` everywhere, explicit org scoping, no
  global unscoped finders. Only the RLS policies themselves are
  deferred.
- 005-10 SSO/MFA
- 005-11 security suite, reduced to cross-tenant specs only — those are
  a correctness property, not merely a security control, and are cheap
- 005-12 backup/restore drills
- 005-18 threat model / incident response
- HO §6.6 vendor and deployment compliance validation
- 005-05 FHIR import boundary
- 005-01/02 CSV import and historical backfill

## Kept despite throwaway status

Each is cheap now and is itself a hypothesis worth testing:

| Kept | Why |
|---|---|
| Transactional outbox (S2C-021) | Correctness at any scale; not a scale feature |
| `organization_id NOT NULL` everywhere | Brutal to retrofit, near-free now |
| Versioning + digest CI (HO §125) | Whether reproducibility discipline is *sustainable* is a core product question |
| Append-only grants (ADR-002 D5) | Same — tests whether the discipline holds under delivery pressure |
| Application-level encryption on `subject_identities` | ~Free in Rails 8; keeps the PHI-handling lesson real rather than theoretical |
| Pass IDs to jobs, never payloads | Good architecture independent of PHI |

## Constraints that do not relax

Throwaway status does not travel to anyone who sees the output.

- Domain effect thresholds stay labelled **NON-CLINICAL** (HO §175)
- If anyone begins making judgements from output, HO §174's
  false-positive review stops being deferrable
- HO §188 "Do Not Ship" conditions still gate any external
  demonstration — particularly "a Finding cannot show its evidence",
  "missing data becomes zero", and "all weak Differences produce a
  confident Top Finding"
- Temporal association is never described as causation (INV-34)

## Known tension to revisit

A design partner using the system, versus local-only deployment. Works
for scheduled sessions on a local instance; does not work if the
partner needs independent access over days. Expect to need one hosted
environment sooner than "local + CI only" implies — build to the HO §6.6
container shape so that stays a configuration change.
