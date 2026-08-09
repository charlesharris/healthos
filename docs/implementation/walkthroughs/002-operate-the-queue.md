# Walkthrough: operate the queue end to end

Epic 002 gate item. The test is not "does it work" — the specs answer
that. The test is whether a person can do a shift's work **without
opening a Rails console**, because every console step in a walkthrough
is a feature someone will need at 2am and will not have.

Read it with a pen. Anything you cannot do from the UI is a finding;
record it in the epic Decision Log rather than working around it.

## Setup

```
bin/setup                 # builds, migrates, seeds, leaves the stack up
```

Sign in at <http://localhost:3000> as `operator@demo.test` /
`healthos-demo-password`.

Credentials are fixed and public because prototype-scope.md records that
this system holds synthetic data only. Production accounts arrive by
invitation (HO §11).

To start over: `docker compose run --rm -e HEALTHOS_DB_USER=healthos_migrator
web bin/rails demo:reset` then `bin/demo_seed`. The migrator role is
required because Signals, CaseEvents and audit rows are append-only to
the application role — a reset that worked as `healthos_app` would mean
the append-only guarantee was not real.

## What the seed put there

The named cohort has stated ground truth, printed at the end of the
seed. The point of the walkthrough is partly to check it:

| Subject  | What was injected               | What should appear                        |
|----------|---------------------------------|-------------------------------------------|
| DEMO-001 | genuine rise, 122 → 145         | trajectory Case                            |
| DEMO-002 | stable                          | **nothing**                                |
| DEMO-003 | stable                          | **nothing**                                |
| DEMO-004 | genuine fall, 140 → 118         | trajectory Case                            |
| DEMO-005 | stops reporting 7 days ago      | *monitoring interruption*, not a BP Case   |
| DEMO-006 | cuff → manual entry mid-window  | source change **on the same Case** as the fall |
| DEMO-007 | two readings, both high         | **nothing** (completeness)                 |

A Case for DEMO-002, DEMO-003 or DEMO-007 is a false positive. Stop and
investigate rather than continuing the walkthrough.

## The walkthrough

**1. Read the queue as a shift lead.** Open `/`. Can you tell, without
clicking, what needs attention first and why? HO §84 says the work
reason is primary and subject identity secondary — check that the page
actually reads that way rather than as a list of people.

**2. Filter to unassigned work.** Unclaimed work is the question a shift
lead asks most often. Then filter to your own.

**3. Open DEMO-005.** The monitoring-interruption Case. Does Quick
Review tell you *why this is here* before it tells you anything else?
This is the Case that most tests the product claim: nothing about the
values changed.

**4. Open DEMO-006.** Both the trajectory Signal and the source-change
Signal should be on **one** Case. A clinician reading an apparent
improvement needs the cuff change in front of them, not filed
separately (STAT-035, and HO §42's contextual attachment).

**5. Assign a Case to yourself, then to the clinical team.** Check the
timeline records both, with who and when.

**6. Park a Case on a watch.** Pick something real and set a watch
condition. Confirm the Case leaves the active queue and that the
condition is visible on the Case — a watch you cannot see is
indistinguishable from having dropped the work.

**7. Force the watch to fire.** Rather than waiting 15 minutes for the
sweep, this is the one console step the walkthrough permits, and only
because time travel has no UI:

```
docker compose exec web bin/rails runner \
  'Cases::WatchEvaluationJob.perform_now'
```

Set a watch with a short expiry first. The Case should return to
`triaged` with a `watch_satisfied` event stating *why* it came back.

**8. Resolve a Case.** Note that you cannot resolve without a
disposition (S2C-015). That refusal is deliberate — a disposition the
system invented would corrupt the resolution feedback loop HO §43
depends on. Check the refusal reads as a reason, not as a validation
error.

**9. Find the reopened Case.** One Case in the seed was resolved and
then reopened by a genuinely new Signal. Its timeline should show
`resolved` → `reopened`, with the original disposition still visible
(S2C-016). Confirm the history was not rewritten.

**10. Check the audit trail.** Open `/admin` → Audit Events. Every Case
you *viewed* should be there. Note what is **not**: the watch firing in
step 7 wrote a CaseEvent and no audit row, because HO §92's audit
answers "who looked at what" about people, and a timer is not a person.

## What to record

For each step: could you do it from the UI, and did the screen tell you
what you needed without your knowing the schema? Both answers go in the
epic Decision Log. The second one matters more — a queue that only makes
sense to the person who built it has not passed this gate.
