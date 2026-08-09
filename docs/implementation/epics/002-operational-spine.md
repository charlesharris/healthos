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
- [x] 002-07 Threshold-excursion monitor (fixture thresholds,
      NON-CLINICAL)
- [x] 002-08 Variability-change monitor
- [x] 002-09 Measurement-frequency-change monitor (drop-only — see log)
- [x] 002-10 Source/method-change monitor
- [x] 002-11 Per-org monitor configuration honored (enable/disable,
      parameters) (§31)

### Case model completion (Milestone 4)
- [x] 002-12 Case types `monitoring_interruption`, `care_gap`;
      correlation compatibility rules per §42, in the domain pack
      (S2C-025)
- [x] 002-13 Contextual attachment: source-change Signal attaches to an
      active blood_pressure_change Case when it explains the same work
- [x] 002-14 Reopen logic with domain reopen horizon; history retained
      (S2C-016/017); spec: outside horizon → new Case
- [x] 002-15 Correlation explanation persisted per attachment (§158)
- [x] 002-16 Priority policy + `priority_reasons` (now/today/routine/
      watch); explanation surface (§43, §159, S2C-011/012)
- [x] 002-17 Deterministic routing policy (team/owner) (§44)

### Lifecycle + queue (Milestone 5)
- [x] 002-18 `Cases::Transition` with an explicit legality table;
      controllers never mutate Case state directly (S2C-013)
- [x] 002-19 Watch conditions + satisfaction predicates (§45) and the
      periodic evaluation sweep (Cases::WatchEvaluationJob, every 15m)
- [x] 002-20 Dispositions with §46 code list; resolution requires one
      (S2C-015)
- [x] 002-21 Ops Queue v1: tabs/counts, filters, sort (priority → age →
      detected_at), assignment, pagination, Turbo row refresh (§85–87)
- [x] 002-22 Quick Review shell: why-is-this-here, trigger Signals,
      timeline, owner, actions, disposition controls (§88)
- [x] 002-23 Case timeline query object merging observations/events/
      signals/case_events (§90)
- [~] 002-24 `audit_events` for view/assign/state/disposition (§92)
      — table created early alongside the admin UI (see epic 001 Decision
      Log, 2026-08-09). Case/investigation event types still to add here.
- [x] 002-25 Concurrency specs: resolution vs Signal arrival; watch
      firing vs manual triage (§120)

## Out of Scope

Context/Baseline/Comparison/Findings (Epic 003/004), analysis_status
consumers, cohorts, external workflow actions (Epic 005 — schema may
land), bulk clinical actions.

## Epic Gate

- [x] Demo seed grows to a small operable population incl. a
      monitoring interruption and a reopened Case
- [~] Team walkthrough: operate the queue end-to-end without touching
      the console — script written at
      `docs/implementation/walkthroughs/002-operate-the-queue.md`;
      needs a human to actually walk it
- [x] All §120 concurrency specs pass in CI loop
- [x] Do-not-ship list (§188) items re-checked: no Case duplication
      under concurrency, no hidden source changes

## Decision Log

### 2026-08-09 — the queue and Quick Review were unusable as rendered

Not a new requirement; the epic's own surfaces did not meet the
requirements already written. The stylesheet from 001-02 defined
`.tabs`, `.chip`, `.filters`, `.timeline` and `.page-header` and no view
used any of them, so every page rendered as unstyled HTML inside a
layout that was `<body><%= yield %></body>` — no navigation, no tenant
context, no way to sign out.

Three fixes were requirements rather than taste:

**HO §84 was inverted.** Twelve equal columns gave "baseline maturity"
the same visual budget as work reason, and three of them were `—`.
Priority, work reason and subject handle now carry the weight; the empty
analytical columns stay visible (nothing has been computed yet, and
hiding that would make the queue look more analysed than it is) but no
longer outrank the reason a Case exists.

**S2C-011 needed to survive contact with colour.** Priority is ordered
with a single-hue emphasis ramp — filled, outlined, neutral, recessive —
explicitly not a red→green severity ramp, because a heat map reads as
"how bad is this patient" rather than "how soon should someone look".
Evidence strength is rendered as a **monochrome four-tick meter** for
the mirror-image reason: it is support that a dimension differs, not
severity, and a colour ramp on it would be read as one within a day.
Both rules are written into `application.css` next to the rules
themselves, since that is where the next person will be tempted.

**S2C-019 was legible only to someone who already knew.** `failed` and
`insufficient_evidence` now render differently by construction — failure
tinted as a problem, insufficient evidence as an ordinary result — so
STAT-036's honest answer cannot be mistaken for an incident.

Quick Review became a panel over the queue rather than a navigation
(HO §88: most Cases resolvable without the Workbench). It **pushes** the
queue instead of covering it, so ↑/↓ still moves between Cases while one
is open. `/ops/cases/:id` remains a real page — same action, same
authorization, same `case.viewed` audit — and renders standalone when
visited directly, which is what keeps the panel optional rather than
load-bearing. `spec/ops/quick_review_drawer_spec.rb` holds that down.

Deviation from the previous view comment: the queue no longer prints a
literal `—` in three columns per row. "Not started" plus an empty
evidence meter states the same fact and costs a third of the width.

### 2026-08-09 — the ground-truth spec needed no bucket (CI fix)

The demo ground-truth spec passed locally and failed in CI: the seed
reaches for `Storage::RawPayloadStore.instance` itself, and the `test`
job has no MinIO. Locally the container was simply up.

Fixed by giving the store a writable `instance` seam rather than adding
MinIO to the unit job. The unit suite deliberately runs without object
storage — the real round trip is exercised by the ingestion integrity
specs and by `bin/smoke`, and making every developer run a bucket to
test a statistical question puts an unrelated dependency in the way.
`InMemoryPayloadStore` reproduces content addressing and hash
verification faithfully rather than stubbing them, because a fake that
returned whatever it was given would make the integrity checks
untestable.

Verified by stopping MinIO and running the whole suite: 549 examples, 0
failures, 22 pending (the storage specs skipping as designed).

### 2026-08-09 — demo population, and a demo that checks itself

The epic gate asks for "a small operable population incl. a monitoring
interruption and a reopened Case". Two cohorts now, for two jobs: a
named cohort (DEMO-001…007) hand-authored with **stated ground truth**,
and a background cohort (`DEMO_POPULATION`, default 40) so that filters,
sort and pagination are exercised against something other than four
rows.

Four of the named subjects exist because of STAT-003 and STAT-035.
DEMO-005 stops reporting — the surviving readings average out unchanged,
so a system that only watches values sees nothing, and "the monitoring
stopped" is the thing a provider most needs told. DEMO-006 switches from
an automatic cuff to manual entry, which looks like improvement.
DEMO-007 has two readings, both high, and must produce nothing. A demo
containing only genuine physiology would quietly teach the opposite of
the contract.

**Ground truth is verified, not just printed** —
`spec/demo/seed_ground_truth_spec.rb`. A demo whose claims are never
checked drifts the first time a threshold moves, and it drifts in the
most damaging direction, because a demo is what someone is shown before
they decide to trust the system.

It immediately earned its place by catching two bugs, both in the seed:

- The DEMO-006 method switch started at day 9, which bled two days into
  the 21-day baseline window. `manual_entry` therefore appeared in both
  profiles, the monitor saw no *new* method, and the seed produced a
  trajectory Case with no instrumentation Signal beside it — STAT-035's
  exact failure, manufactured by the demo rather than caught by it.
- The reopen readings were stamped "now". Monitor windows are day-
  aligned and half-open, so the current incomplete day is deliberately
  outside them and no Signal fired at all. The seed printed "reopen NOT
  produced" rather than claiming success, which is the only reason it
  was visible.

A third came from S2C-002: re-evaluating the same monitor over the same
day-aligned window returns the EXISTING Signal, so the reopen attempt
reported `already_attached` and no reopen happened. The seed now picks a
subject with no excursion Signal yet.

**`demo:reset`.** Deleting the demo organization is not something the
application role can do, and that is the design working — append-only by
privilege revocation means the task fails with a permission error under
`healthos_app` and succeeds under `healthos_migrator`. Both verified.
Deletion order is derived from the schema's foreign keys rather than
hand-maintained, after a hand-written list failed halfway through as an
FK violation; `MigratorConnection.wipe_tenant_data!` does the same for
specs.

### 2026-08-09 — bin/smoke: CI now boots the application

The Solid Queue bug deserves a post-mortem, because the interesting part
is not the bug. `bin/dev` died on its first request with `relation
"solid_queue_processes" does not exist` while CI was green — and CI was
*right* to be green, in the sense that every check it ran passed. Lint,
two security scans, digest verification, 500-odd specs and a production
image build, and not one of them started the application. The gap was
not a missing assertion; it was a missing category of assertion.

`bin/smoke` boots the full compose stack and checks only things that
require a running system: the web process answers, the stylesheet
Propshaft resolves is actually served, sign-in works with the seeded
credentials, the queue renders real seeded Cases, the recurring schedule
is registered in the queue database, and a job enqueued on the web
connection is executed by the separate worker process. Anything provable
in a spec stays in a spec.

Verified by discrimination rather than by passing: removing
`config.solid_queue.connects_to` reproduces the original bug, and
`bin/smoke` exits 1 naming both failing checks ("recurring schedule
registered: unreachable", "the worker executes an enqueued job: no").
Restoring the line returns it to green. That exercise also found a flaw
in the script itself — `set -e` was aborting before the summary printed,
which is exactly backwards when the thing being diagnosed is "why will
this not boot".

### 2026-08-09 — 002-19 watch sweep, 002-25 §120 races

**A watch that never fires is worse than no watch.** Quick Review could
park a Case with a stated condition for coming back; nothing brought it
back. That is the same failure the platform exists to surface in patient
data — monitoring that silently stopped — and having it in the tool
itself was not defensible. `Cases::WatchEvaluationJob` sweeps every 15
minutes; `Cases::EvaluateWatchConditions` fires the due ones.

A sweep rather than `perform_later(wait_until: expires_at)`. The
per-Case wakeup is cheaper but only works for timers —
`new_observation_count` and `new_signal` have no due date — and a queue
restart or a job pruned as stale would drop the wakeup with nothing to
notice it. A sweep re-derives what is due from the database every run,
so a missed tick delays a Case rather than losing it.

**The machine reports; the human decides.** A satisfied condition
returns a Case to `triaged` only if it is still `watching`. If a
clinician already moved it on, the condition is closed out and the
timeline records that it fired, but the state is left alone. This is
§120's "watch firing concurrent with manual triage": the answer is not
a lock, it is that the sweep has no authority to override a person.

**System transitions are not provider access.** `Cases::Transition` now
takes `actor_type:`, and a `system` transition writes the CaseEvent but
no `audit_events` row. HO §92's audit answers "who looked at what" about
*people*; logging a timer as a provider access would dilute the trail
someone reads during an access review. Same reasoning as
`Cases::RouteCase`. `actor_type` is explicit rather than inferred from
`actor.nil?`, which is also true of a deleted user.

**§120's resolution-vs-Signal race found a real bug.** The dangerous
interleaving is not the obvious one. Correlation takes the scope lock
and reads a Case as active; a clinician resolves it a moment later;
correlation then writes. What actually happened: the correlation lost
the optimistic-lock race, raised `StaleObjectError`, and the Signal
survived only because the job would be retried — an error where there
should have been an ordinary attach or reopen.

The fix is that `Cases::Transition` takes the *same* scope lock when
closing. Closing is the one transition that changes what correlation
sees: a Signal at an active Case attaches, the same Signal at a resolved
Case reopens it (S2C-016), and which is correct turns on a status read.
Locking only closing transitions keeps routine queue movement
(new→triaged, watching→investigating) out of correlation's way, and the
lock is per organization+subject+domain, so unrelated subjects still
close in parallel — asserted, not assumed.

**Known gap, deliberately not closed here.** If correlation wins the
race, the Signal attaches and the clinician's resolution then commits
over evidence their screen never showed. The state is coherent and the
timeline reads correctly (`signal_attached` strictly before `resolved`),
so this is UI staleness, not a data-integrity defect — the same class as
any two-operator race. Closing it properly means optimistic concurrency
in Quick Review: the form carries what the operator saw, and the close
is refused if the Case moved underneath them. That belongs with the
Workbench in epic 004, not bolted onto Transition, and refusing closes
on a `last_reviewed_at` heuristic instead would strand Cases with no way
to close them at all.

### 2026-08-09 — styling, and a seeded operator account

**"No CSS frameworks, function over polish" was half right.** The
no-framework part stands — this is dense tabular data read under time
pressure, and a framework's opinions would fight that. The "no polish"
part did not: `application.css` contained nothing but a comment block,
so every screen including sign-in was raw unstyled HTML. The prototype
charter names a design partner as the audience for exactly these
surfaces, so unstyled was never going to hold.

Now one hand-written stylesheet, ~250 lines, no dependencies. Two
choices carry product meaning rather than taste:

- **Priority chips are not a red-to-green severity ramp.** A heat map
  reads as "how bad is this patient", which is precisely the conflation
  S2C-011 forbids — priority is how soon someone should look, not how
  strong the evidence is. Weight and a single accent carry the ordering.
- **HO §84's primary/secondary hierarchy is expressed in type weight and
  colour**, not layout, so it survives a table growing more columns as
  epics 003 and 004 add analytical ones.

**A seeded operator account.** Credentials existed only as an accident
of testing, so `bin/setup` produced a system nobody could log into.
`demo:seed` now creates `operator@demo.test` as organization_admin and
platform staff, prints the credentials, and `bin/setup` runs it. Fixed
and public on purpose: prototype-scope.md records synthetic data only,
and a demo you cannot open is not a demo. Production accounts come
through invitations (HO §11).

### 2026-08-09 — 002-21/22 Ops Queue v1 and Quick Review

Built by a sub-agent against the existing patterns; verified here. 73
ops examples, 505 in the suite.

**A real authorization gap, flagged rather than silently widened.** The
v0 queue authorized on `OrganizationPolicy#show?` — any active
membership, including `support_limited`. But the queue IS health data: a
Case names a subject, says why the system thinks something changed, and
links to the readings behind it. HO §11 defines `support_limited`
precisely so support can exist without clinical visibility, and
`CLINICAL_ROLES` already excluded it. Admitting it to the queue would
have made that distinction decorative.

Closed with a `CasePolicy` whose `show?` delegates to
`membership.clinical_access?` — one definition of clinical access rather
than two that can drift, asserted by a spec that walks every role and
compares the two answers. Until 005-15 builds a genuinely provider-safe
support surface, support staff do not read the queue.

**Action controls are generated FROM `Cases::Transition::ALLOWED`**, so
the UI cannot offer a transition the service will refuse. A hand-written
button list is a second source of truth that drifts silently.

**Analytical columns render as `—`, not hidden.** Top Finding, evidence
strength, data quality and baseline maturity have no producers until
epics 003/004. An empty analytical column is information — hiding it
would make the queue look complete when it is not.

**Sort options carry a human explanation each**, and a spec asserts no
ORDER BY references `evidence_level` or any `score`/`weight`/`rank`
token (S2C-011, S2C-023). Evidence strength is *displayed* per HO §84
but never sorted or coloured by.

**`id ASC` as final sort tiebreak.** Without a unique tiebreak, offset
pagination silently duplicates and skips rows — a queue that loses work
between pages is worse than one that is slow.

Deviation: `app/services/cases/assign.rb` was added outside the
directories the sub-agent was given. Justified — assignment mutates a
Case and controllers may not, `Cases::Transition` is a status legality
table and assignment is not a status, and `RouteCase` is automatic and
team-only. It refuses assignment on resolved or dismissed Cases, since
reassigning closed work reads like reopening, which only a new
compatible Signal may do (S2C-016).

Still open: 002-19's periodic watch-evaluation job (Quick Review can
start a watch; nothing yet fires it) and 002-25's concurrency specs.

### 2026-08-09 — 002-12..15, 002-17, 002-23, 002-24

002-12 through 002-15 were already satisfied by the 001-11 correlation
work (case types, contextual attachment, reopen horizon, persisted
explanations) — verified against their specs rather than re-implemented.

**Routing assigns a TEAM, never a person.** Auto-assigning an owner
looks helpful and is not: it manufactures the appearance of ownership
without anyone accepting it, and work that is nominally owned is easier
to overlook than work that is visibly unassigned. Routing also never
overrides a human — re-routing work an operator has claimed is how a
queue loses people's trust.

**An unroutable Case stays visible and says why.** A missing configured
team leaves the Case unassigned with a `team_missing` reason, rather
than silently falling through to some default team where nobody is
looking for it.

**System routing writes NO audit row, deliberately.** HO §92 is a
*provider access* audit — "who looked at what" — and every row names an
accountable person, which is why `actor_id` is NOT NULL. Automatic
routing has no person, and relaxing the column to admit one system row
would weaken the guarantee for every other row in the table. The
assignment is still recorded as workflow history on the CaseEvent, which
is where it belongs.

**CaseEvent and AuditEvent are kept apart on purpose.** CaseEvent is
product — an operator reads it. AuditEvent is compliance — it is not
rendered anywhere. The clearest illustration: *viewing* a Case writes an
audit row and no case event, because a timeline filling with "Dr X
looked at this" would drown the workflow history it exists to show, and
would leak who is reviewing whom to everyone with queue access.

**Auditing lives in the transition service, not the controller.**
S2C-013 already routes every state change through `Cases::Transition`,
so auditing there means a caller cannot forget. HO §157 wants the trail
complete, not merely conventional.

### 2026-08-09 — one window convention: half-open, day-aligned

Day-aligning the monitor windows so the shared frequency algorithm could
be reused, as asked. Reuse immediately exposed something worse than the
duplication it removed.

**`Frequency#window_days` counted dates inclusively while every monitor
window is half-open.** So a 21-day baseline measured as 22 days, a 7-day
recent window as 8, and the two sides of a before/after ratio were
scaled by different factors — a permanent, silent bias in exactly the
comparison the monitor exists to make. The sub-agent had avoided this by
keeping a private denominator; reusing the algorithm is what made the
mismatch visible.

**Half-open `[start, finish)` is now the single convention**, stated in
`MonitorWindows`, `Frequency#window_days` and
`Expectation#local_dates`. A mixture of conventions is how a 21-day
window becomes 22 days, and how two adjacent windows both count the same
boundary reading. Windows also align to LOCAL midnight, not UTC:
otherwise a window's length changes silently across a DST transition
(HO §121).

**Two duplicate implementations removed.** The trajectory monitor
carried its own private `window_ending`; it now includes
`MonitorWindows`. The unaligned helper was deleted rather than left
available, because dead code that still looks usable is a trap.

**A spec fixture now encodes the DST case explicitly**: the completeness
window ends at 04:00 UTC rather than 05:00, because local midnight on
9 March 2026 moves an hour earlier in UTC terms. That is HO §121's
required regression case sitting in a fixture where it will be noticed.

### 2026-08-09 — 002-07 to 002-11 monitor pack

Built by a sub-agent against the trajectory monitor as reference;
reviewed and verified here before commit. 62 monitoring examples.

**The STAT-044 guard is now mechanical and provably discriminating.**
Two specs read the pack's source with comments stripped and fail on
(a) any of the contract's evidence bands — 0.3, 0.5, 0.25, 25, 30, 40,
50, 60, 80 — and (b) any comparison against a bare number, so every
threshold must be a named parameter that lands in the monitor digest.
Verified by deliberately injecting both violations into a monitor and
confirming both specs fail, then restoring. A guard that cannot be shown
to fail is not a guard.

**The `SourceChangeMonitor`'s fixture share sits deliberately below both
SC §11 bands.** Surfacing a candidate for a human to look at and rating
statistical evidence are different jobs in different places; a monitor
that fired exactly at 30% would blur them and put a governed value in
the wrong file.

**RESOLVED 2026-08-09 (Charles): monitor windows are now day-aligned and
the algorithm is reused.** Doing it surfaced a deeper problem — see the
window-convention entry above. Original note follows.

**A cadence-denominator bug avoided, worth recording.** The obvious move
was to reuse `Derivation::MeasurementBehavior::Frequency` for the
recent-versus-baseline rate. Its `window_days` counts calendar dates
touched, which is right for a day-aligned derived signal but wrong for
the monitors' rolling windows ending mid-day: a 7×24h recent window
touches 8 dates and a 21-day baseline touches 22, so the two sides get
scaled by different factors and the ratio is distorted. The monitor
divides by its configured span instead. **Open question for review:**
day-aligning monitor windows would let the algorithm be reused and
remove the duplication — worth deciding before more monitors arrive.

**Frequency fires on drops only.** 002-09 is named
"measurement-frequency-change", but the work it correlates into is
`monitoring_interruption` (HO §42), which a cadence *increase* is not.
Direction is still part of the dedup identity, so adding the other
direction later cannot collapse two events onto one key, and a spec
asserts silence on a rise.

**What each monitor refuses to claim** is documented in its own
docstring — the variability monitor cannot distinguish a subject whose
spread widened from a new cuff, a different arm, or a different
operator; the frequency monitor cannot distinguish a broken device from
a holiday. Saying so in the file is what keeps a Signal a reason to look
rather than a finding.

An org-level parameter override deliberately does **not** move the
monitor digest, which is HO §31's "customer policy without changing code
definition identity", asserted by spec.

### 2026-08-09 — PHI leakage test (epic 001 gate item, now closed)

**The test found a real leak, and it reversed a documented decision.**

`subject_identifiers.value` was deliberately left unencrypted in 001-04,
reasoned as: an MRN is an identifier rather than clinical content, it
must be indexed for resolution, and the uniqueness constraint that makes
identity resolution idempotent has to operate on it.

That reasoning was wrong on the facts. **Deterministic encryption
produces stable ciphertext, so equality lookup and the unique index both
keep working** — it is exactly the trade already accepted for
`contact_email`. And what the reasoning missed is that ActiveRecord logs
SQL: an unencrypted MRN appears in plaintext in every INSERT and SELECT
touching the table. HO §93's list of what technical logs may contain
does not include external identifiers, and an MRN is a direct handle on
a person.

Now `encrypts :value, deterministic: true`. Verified: ciphertext at
rest, plaintext through the model, identity resolution and its
idempotency specs unchanged, demo seed still produces exactly the two
expected Cases.

This is the clearest case yet for why "the architecture supports it" is
not the same as a test. Every structural precaution was already in place
— jobs take ids, `technical_label` exists, audit is a separate table —
and the leak was somewhere none of them looked.

**What the spec actually does:** drives a real ingest → normalize →
dispatch cycle with deliberately unusual PHI values, captures the Rails
log at DEBUG, and greps it. It also asserts the log is *not empty*, so
the other assertions cannot pass vacuously by the pipeline logging
nothing. Error paths are covered too, since an exception message is the
classic leak — it is built from whatever was in scope and travels to
aggregators.

Note for whoever runs this next: development data seeded before this
change holds plaintext MRNs and will not decrypt
(`support_unencrypted_data = false`). Re-run `bin/demo_seed` after
clearing.

### 2026-08-09 — 002-16, 002-18 to 002-20 case lifecycle

**Priority deliberately cannot see evidence.** S2C-011 says priority is
operational policy, not statistical evidence, and the easiest way to
violate it is to reach for `evidence_level` when deciding urgency. A
STRONG Difference does not make a Case urgent and a WEAK one does not
make it ignorable — urgency is how soon a human should look, which
depends on the kind of work and how long it has waited. A spec greps
`priority_policy.rb` and fails on `evidence_level`, `STRONG` or
`MODERATE`, because coupling the two axes is how you end up with the
"AI Risk Score: 87" that HO §43 and CLAUDE.md both forbid.

**A policy bug found by spec, and it was a naming lie.** The rule was
called `aged_unreviewed` but only checked age. So a Case an operator had
already reviewed and parked would be escalated for the crime of still
existing — and worse, an `insufficient_evidence` Case being watched for
more data ages *by design*, so the rule punished exactly the honest
answer STAT-036 asks for and pushed toward closing Cases to keep the
queue quiet. Now checks `last_reviewed_at.nil?`, and the
insufficient-evidence branch is evaluated first.

**Reopening is not a transition.** `resolved` and `dismissed` have empty
allowed-transition lists, so a manual resolved→investigating is refused
with a message pointing at S2C-016. Reopening requires a new compatible
Signal and therefore belongs to correlation — allowing it here would
reopen a Case with no evidence behind it.

**Dispositions are refused, never defaulted** (S2C-015). A disposition
the system invented would corrupt HO §43's resolution feedback loop:
every "action taken" that nobody took makes monitor quality look better
than it is. Codes are constrained at the database, per HO §46's warning
against arbitrary customer taxonomies.

**Disposition is a record, not a column**, so a reopened Case keeps its
prior one visible (S2C-016). A column would be overwritten on the second
resolution.

**`threshold_crossed` watch conditions deliberately never self-satisfy.**
Evaluating the threshold here would duplicate a governed value that
already belongs to a monitor. The condition records the intent; the
monitor owns the number.

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
