# Changelog

This skill changes on field evidence only: an incident in a real feature run
becomes a failing case in `bin/test-chunk-check.sh`, then a mechanism or a
reference edit, in the session that earned it. Entries cite that evidence as
field-log entries `(date, repo)`. The field log itself is machine-local by
design (`templates/field-log.md` explains why it never travels with the
skill), so the citations here are the durable half of each story.

## 2026-08-03 — remediating the first skill review

An independent review of the skill after the first full feature (2026-08-02)
found that all ten defects an independent whole-diff audit caught had shipped
through gate-approved chunks, and traced them to classes the lifecycle never
briefed against, lessons routed to the wrong stage, and one documented
integrity hole. The changes it earned:

- **Oracle-failure lessons routed to the stage that applies them.** plan.md's
  Track V gains a standing brief — the accumulated failure classes keyed on
  the oracle's *shape* (greps prose / suite lints tests / reads git state /
  deliverable is itself a check), not a flat checklist. The pre-freeze
  git-state calibration rule moved there from audit-implementation.md, which
  is read after the moment that can act on it. implement.md rule 8 no longer
  routes an in-flight oracle-bug fix through `block` (a detour `blocked`
  forces by cutting off `freeze --refreeze`); plan.md's Track P prices the
  oracle-run cadence to the chunk's shape.
- **`predict` op** (schema 9 → 10): the blind half of predict-then-compare
  becomes a mechanism. `predict` stamps the filled top half of
  `predictions.md` into `state.json` while the verdict is still blank —
  refusing the one-pass fill that motivated it (2026-07-29, a gate outcome
  recorded about a plan that did not yet exist) — and records whether a plan
  draft was on disk. `freeze` requires the stamp on `standard` chunks and
  refuses a stamped top half that later changed, at every size. Deliberately
  keyed on recorded absence/presence rather than the originally designed
  mtime comparison: draft-ahead makes a pre-existing plan legitimate, and
  recording the condition honestly beats gating on a clock. Six mutation
  trials pinned (suite 197 → 217 assertions).

## 2026-08-02 — catch-up sync after the first full feature

The first end-to-end feature run (skill-engine, 24 chunks,
2026-07-29 → 2026-08-02) earned every change below. Each was applied to the
live install in the session its incident occurred and mutation-tested against
the backstop suite; this sync brings the repo up to date and makes it
canonical. Net effect: state schema 5 → 9, backstop suite 91 → 197
assertions, ~1,400 changed lines.

### The bypass path became evidence-bearing

- **`bypass` runs `suite_cmd` before the stamp and records `bypass_suite`**
  (recorded, never gated — a red baseline predates the chunk). The suite run
  was prose that nothing executed; a bypassed chunk then shipped red doctrine
  that was caught only by hand (entries 2026-07-29 and 2026-07-30,
  skill-engine chunks 03 and 05).
- **`verify` refuses bypassed chunks** instead of reporting the intended state
  of the world as a wall of failures (2026-07-29, chunk 02). Keyed on
  `bypass_note`, not stage, so it still refuses after `done`.
- **`gate approved` on a bypassed chunk records `bypass_shipped`** — the
  changed paths measured from `baseline_sha` or the new `bypass_base` anchor.
  A bypassed chunk's work previously appeared in no state field at all; a
  maintainer closing one asked "don't we have to implement this chunk?" while
  the work sat approved on disk.
- **The printed field-log line no longer pre-fills `chafe:`** with the work
  description — a plausible wrong value in the one field carrying qualitative
  evidence — and `log` now refuses an unanswered `chafe:` (2026-07-29,
  chunk 03).

### The escalation error became recordable

- **`bypass --downgrade`** corrects an over-escalation from any pre-`done`
  stage: sets `size_class` to `trivial`, records `size_class_corrected`
  (previous class, originating stage, reason), keeps the freeze evidence as
  the receipt for what the over-escalation cost, and still exits through the
  review gate. Earned by the first chunk in the log (2026-07-29, chunk 01):
  an agent escalated a `git add` to the full lifecycle because an oracle was
  *writable*, and the oracle was deleted at review as a tautology. The
  escalation test is now stated where it applies: **"can this regress?", not
  "can this be asserted?"** — and the file count is documented as a proxy for
  blast radius, not a gate.

### The demotion streak became check-backed

- **`log` derives the expected `gate:` value** (`expected_field_log_gate`:
  `adjust` whenever `gates.plan_adjusted` is true) **and refuses a line that
  disagrees.** The recording convention used to say "log the word
  `gates.plan` holds" — but `freeze` refuses the verdict `adjust`, so that
  word can never be `adjust`, which made `gate:adjust` unreachable in exactly
  the field the demotion rule reads: every plan the human changed counted
  *toward* retiring the gate that changed it (2026-07-29, chunk 04 — the rule
  and the convention had been written from the same analysis and implemented
  against different halves of it).

### Freeze probes the whole suite; predictions priced to the chunk

- **`freeze` runs `suite_cmd` once, non-gating, recorded as `freeze_suite`**
  (schema 8 → 9). A lint or doctrine break baked into the freshly hash-pinned
  oracle file is exit-code-identical to the expected new-oracle red and used
  to stay invisible until implement's first full-suite run; it cost two
  chunks a stop-and-surface each before the probe existed (2026-07-31,
  chunks 14 and 15 — a stray path reference and a dead shell variable, both
  inside the frozen oracle's own text).
- **Blind predictions narrowed to `standard` chunks** (operator decision,
  2026-07-31): entries 07–12 showed the blanks degrading on smaller chunks —
  four chunks of unfilled placeholders, then boilerplate. `freeze` still
  refuses unfilled blanks on `standard`; the Verdict/Adjusted lines stay
  mandatory at every size, so the demotion rule keeps its input.

### The premature-commit deadlock

- **`verify` records an early commit as `gates.review = premature` instead of
  hard-failing**, and `gate approved` then requires an explicit
  acknowledgment note. A bundled human commit that landed before verify had
  ever passed left the chunk stuck at `approved` with no legal op that could
  move it — the premature-commit check was itself what blocked reaching the
  only op that can acknowledge a premature commit (2026-07-31, chunk 12).

### The session got a handoff; the cadence got named

- **`gate approved` prints a handoff**: the next chunk (first sibling
  directory whose `state.json` is not `done` — no markdown parsed) and a
  pasteable resume prompt. `done` was terminal for the chunk and a dead end
  for the session.
- **One-arrival cadence + draft-ahead** (SKILL.md § Cadence,
  `references/plan.md` § Draft-ahead, adopted 2026-07-31): both gates stand
  but share a single human arrival; chunk N's plan is drafted — never pinned —
  while the human reviews chunk N−1. Two gates arriving as separate
  interruptions was ceremony chafe in five of the first fourteen entries.

### Reference rules earned by lost iterations

- **implement.md rule 6**: new files need `git add` before a tracked-ness
  oracle can see them (2026-07-30, chunk 11).
- **implement.md rule 7**: a single-line grep can fail on a line wrap, not
  just on content — re-run the check, reflow the sentence (2026-07-30,
  chunk 11; repeated as the only red on chunks 16 and 18).
- **implement.md rule 8**: the recipe for an oracle bug found after
  implementation is otherwise complete — surface it, get the fix approved,
  then prove the re-freeze non-vacuous with a throwaway never-staged fixture,
  because the fixed oracle is green and `freeze` requires red evidence
  (2026-07-31, chunk 19: an oracle that grepped its own source for the string
  it checked the absence of).
- **plan.md Track V rule 4**: tracked test files must state invariants, never
  cite untracked chunk docs — being tracked is what makes the vocabulary a
  defect (2026-07-29, chunk 04, caught by the human at the plan gate).
- **Retro line added**: "oracle surfaced a defect with **no** red→green
  iteration" — freeze-time catches and collisions are invisible to the
  iteration count, so the evidence base was systematically understating
  blind-oracle value (added 2026-07-29 after a chunk logged `n(1)` for an
  oracle that had caught two real things).
- **audit-implementation.md failure modes**: `suite_cmd ⊆ CI` — "suite green"
  is not "CI green"; and any oracle that reads git history, HEAD, or
  tracked-ness gets calibrated against a shallow clone and a detached
  synthetic merge before freeze (2026-08-02, chunk 24's post-merge addendum:
  three shipped oracle defects, all living exactly where the pre-commit
  working tree differs from a CI checkout).
- **Context packs grew a `Covers` column** (templates/feature.md): the path
  globs a pack describes are its refresh trigger — a chunk whose diff touches
  them owes the pack an update or an explicit "still holds" in its review
  packet.

### Housekeeping

- Dropped the committed `feature-chunker.zip`: exports are built from the
  repo, not stored in it. The zip predated every change above, so any export
  made from it shipped the stale snapshot by construction.
