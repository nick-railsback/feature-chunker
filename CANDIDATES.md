# Candidates — proposed changes awaiting a design decision

Process failures fixable in-session get fixed in-session (the incident→case→
fix loop; see CHANGELOG.md). Candidates are the remainder: changes that need
a maintainer's design decision before they can become mechanism. They used to
accumulate across three homes — a feature doc's open-decisions section, field-
log chafe lines, chunk retros — with no queue, no status, and no escalation
rule; anything maintainer-sized stalled there. This file is the queue, and it
lives in the versioned repo on purpose: candidates are proposed changes to the
shipped thing, and shipping known gaps is honest.

**The escalation rule, codified from the precedent the skill already set**
(`freeze_suite` was built on the second occurrence of its class):

> **Second incident in a class → mechanism, in that session.** One incident
> earns a ledger entry with its evidence. The second is the class announcing
> it recurs; build the fix while the incident is in the window.

Each entry cites its field-log evidence as `(date, repo, chunk)`. The field
log is machine-local and does not travel with the repo; the citations here
are the durable pointers into it.

## Open

### Bypass runs no suite after the work

`bypass` runs `suite_cmd` *before* the work and records `bypass_suite`;
nothing runs it after. `verify` refuses bypassed chunks (correctly — no
freeze happened) and `gate` re-reads the field log but not the suite, so a
trivial chunk's entire output is unmeasured while `bypass_suite: {exit: 0}`
reads next session like evidence about the shipped state. Real incident: a
bypassed chunk shipped a red doctrine check, caught only by hand
(2026-07-30, skill-engine, chunk 05). Recommended shape, already written down
at the incident: a record-only suite run in `gate` when closing a bypassed
chunk — record, never gate, same proportionality posture as `bypass_suite`.
One incident; second one builds it.

### Cross-chunk caller/seam sweep at spec time or Track V

When a spec declares scope over a function, flag, or file, nothing asks who
else consumes it. Three occurrences of the class in one feature, each via a
different mechanism: a sibling chunk's oracle hash-pinned a doc section this
chunk's spec needed to edit (2026-07-31, skill-engine, chunk 17); a second
consumer of a test-harness flag sat outside the declared scope until
mid-implement (2026-08-02, skill-engine, chunk 21); and the post-feature
audit found three shipped defects where every gate globbed one tree while
the consuming tree sat outside all of them. **By the second-occurrence rule
this is overdue for a mechanism** — it is still here because the mechanical
shape is genuinely undecided (a generic "grep for callers" needs to know what
a caller is, per repo). What exists now: `feature-close` (2026-08-03) catches
the class at feature scope; the per-chunk sweep — audit-readiness or Track V
grepping the repo for other users of everything the spec declares scope over
— is the open design. Chunk 21's chafe line names it.

### Recovery path for blockers discovered post-green

A blocker found after the oracle is green and the plan approved (chunk 17's
cross-chunk collision) fits neither `block` (the work is not stopping) nor
`readiness --rebaseline` (nothing about this chunk restarts). It was resolved
by hand-flipping the stage, which the state machine should not require.
One incident (2026-07-31, skill-engine, chunk 17); low urgency. Related:
implement.md rule 8 now covers the oracle-bug variant of late discovery.

### `deviate` op for bypassed chunks

A bypassed chunk has no `plan.md`, so its deviations have nowhere to live
except a hand-edit of the script-managed `state.json` — the one field
recording what the work did beyond its description is written by convention
and checked by nothing (2026-07-30, skill-engine, chunk 06). Low urgency by
its own retro's argument: `bypass_shipped` (built later the same week) now
records the actual paths at gate time, which covers most of what a deviation
note would say.

### `feature status` op — render the queue from state.json

`feature.md`'s queue table is dual bookkeeping nothing checks (the script
parses no markdown by design), and rows drift (one sat at `ready` for two
days after its chunk moved on — 2026-08-02 review, F4). The row diet
(templates/feature.md) is the prose half. The mechanical half would be a
`feature status` op that walks sibling chunk directories and prints
chunk/stage/size from each `state.json` — `print_handoff` already walks
siblings, so the design is mostly there. Its known limit is the same one
`print_handoff` documents: it can only see *stamped* chunks, so it
supplements the queue table rather than replacing it.

## Landed by the 2026-08-03 remediation — do not re-propose

`predict` op (was the oldest open decision, 2026-07-29, skill-engine,
chunk 04); Track V standing brief; implement.md rule 8's `block` detour fix;
Track P cadence pricing; `feature-close`; the computed demotion streak.
Details and evidence in CHANGELOG.md.
