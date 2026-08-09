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
- [ ] 002-12 Case types `monitoring_interruption`, `care_gap`;
      correlation compatibility rules per §42, in the domain pack
      (S2C-025)
- [ ] 002-13 Contextual attachment: source-change Signal attaches to an
      active blood_pressure_change Case when it explains the same work
- [ ] 002-14 Reopen logic with domain reopen horizon; history retained
      (S2C-016/017); spec: outside horizon → new Case
- [ ] 002-15 Correlation explanation persisted per attachment (§158)
- [x] 002-16 Priority policy + `priority_reasons` (now/today/routine/
      watch); explanation surface (§43, §159, S2C-011/012)
- [ ] 002-17 Deterministic routing policy (team/owner) (§44)

### Lifecycle + queue (Milestone 5)
- [x] 002-18 `Cases::Transition` with an explicit legality table;
      controllers never mutate Case state directly (S2C-013)
- [~] 002-19 Watch conditions + satisfaction predicates (§45); the
      periodic evaluation job lands with 002-21's queue work
- [x] 002-20 Dispositions with §46 code list; resolution requires one
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
