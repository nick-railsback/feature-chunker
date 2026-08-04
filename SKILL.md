---
name: feature-chunker
description: >-
  Run feature work through a chunked delivery lifecycle with executable
  validation, frozen test oracles, and human gates before commit. Use whenever
  the user invokes /feature-chunker, wants to break a feature or epic into
  chunks, asks whether a chunk is ready to plan (audit-readiness), asks to
  plan a chunk, asks to implement a planned chunk, wants an implementation
  audited or verified before commit (audit-implementation), mentions the
  chunk harness or chunk lifecycle, or picks up documented feature work in
  a fresh session. Also reach for it when the user wants plan-then-implement
  discipline with tests written before code, even if they don't name the
  skill. This is for forward feature work; to work through an existing
  findings report or audit, use tdd-remediation instead.
---

# feature-chunker

Agile for agents: an epic's feature becomes documented **chunks**; each
chunk moves through staged, resumable checkpoints with deterministic
guarantees. State lives in files in the target repo, so any session — or any
agent — can pick up exactly where the last one stopped. Nothing here ever
runs `git commit`; the human commits. `verify` refuses to stamp a chunk that
has commits the review gate has not approved.

## Lifecycle

```
specified → ready → approved → verified → done
            (audit-readiness) (plan gate)  (audit-implementation → retro → human review)
```

There is no `implemented` stage. The only honest transition out of
implementation is the one `verify` makes, because that is the one backed by a
check — a stage whose sole content is an agent attesting to its own work is
exactly what this skill exists to refuse.

Side states: `blocked` (stop-and-surface fired — `chunk-check.sh block
<dir> "<reason>"`, or a `rejected` review verdict) and `bypassed` (trivial
work — `chunk-check.sh bypass <dir> "<what>"`, see the bypass rule; it still
exits through the same review gate). Stage lives in the chunk's
`state.json`; the deterministic transitions are made by
`bin/chunk-check.sh`, not by prose.

### Cadence — one arrival per chunk

Both gates stand, but steady-state they share a single human arrival: the
implement session exits with verify green, the review packet assembled, the
retro pre-filled, and the *next* chunk's plan drafted ahead — then stops, which
fires the notification. The arrival is: review the diff, gate, commit; pin and
freeze the next chunk (its questions answered, its plan gate run); clear the
window and leave it implementing. Drafting moves ahead of the commit; pinning
never does — the split, its contamination rules, and the `tracked`-mode caveat
are in `references/plan.md` § Draft-ahead. Adopted 2026-07-31: two gates
arriving as separate interruptions was ceremony chafe in five of the first
fourteen field-log entries.

## Non-negotiables

1. **The oracle is executable and written blind.** Validation = real test
   code derived from `spec.md` only, demonstrated **red** before
   implementation exists. A prose "validation plan" is not an oracle.
   `freeze` runs `oracle_cmd` and refuses a green oracle, a passing test, or a
   collection error — the calibration is executed, not attested.
2. **The oracle is frozen.** Test files are hash-pinned at plan approval and
   never touched during implement. A wrong test is a stop-and-surface back to
   the plan gate, not an edit.
3. **Verify, don't trust.** Session pickup re-derives state from disk and
   reruns checks; recorded green is a claim, not a fact.
4. **Plans are cold-executable.** If an agent that has read nothing else
   can't execute the plan, the chunk is too big — split it.
5. **Scope is declared, then enforced.** The diff must stay inside the
   declared paths (plus tests and chunk docs). Expansion is a
   stop-and-surface, not a judgment call.
6. **Two human gates, both instrumented.** Predict-then-compare on the plan
   (blind predictions for `standard` chunks; `small` chunks gate on
   read-and-verdict alone — softened 2026-07-31); review-before-commit on the
   diff. The blind half is instrumented in mechanism, not just vocabulary:
   `chunk-check.sh predict` stamps the filled predictions before the plan is
   read, and `freeze` requires the stamp on `standard` chunks. Gates earn
   their keep via the field log or get demoted — by data, not by mood.
7. **Ceremony must be proportionate.** Trivial work — no design decision,
   small blast radius, trivially reversible — bypasses the lifecycle: do it,
   human reviews the diff, record `bypassed`. The file count is a *proxy* for
   blast radius, not a gate: `git add` of a twenty-file directory is one
   reversible decision and is trivial; a two-line change to an auth check is
   not. **Before escalating out of `trivial` because an oracle is writable, ask
   whether the thing can regress** — assertable is not the same as worth
   asserting. `chunk-check.sh bypass` requires `size_class` to be exactly
   `trivial`, so the escape hatch cannot quietly become "skip the ceremony,
   I'm in a hurry"; correcting an over-escalation later needs `--downgrade`
   and is recorded.

## Operations — load only the stage in play

| Operation | When | Read |
|---|---|---|
| `audit-readiness` | Before planning: is this chunk fit to plan, is disk consistent with state, is baseline green? **Skip for `trivial` — run the suite and go straight to `bypass`** | `references/audit-readiness.md` |
| `plan` | Chunk is `ready`: write red tests + cold-executable plan, run the human plan gate, freeze the oracle | `references/plan.md` |
| `implement` | Chunk is `approved`: execute the plan to green without touching the oracle | `references/implement.md` |
| `audit-implementation` | Implementation done: deterministic verify, package for human review before commit, run the retro | `references/audit-implementation.md` |
| `feature-close` | The last chunk is `done`, before release: independent review of the cumulative diff by a reviewer that did not write the chunks, recorded as a repo artifact | `references/feature-close.md` |
| *(not a stage)* | Installing the skill or the commit-preventer hook, the field log's location and team variant, the full `chunk-check.sh` argument surface | `references/setup.md` |

**Sibling skill.** `tdd-remediation` covers the reactive case: a findings
report exists and each finding gets its own commit. The two carry opposite
commit law by design — do not load both. If a request is ambiguous, ask which
it is before starting. `feature-close`'s review artifact is the canonical
handoff from this skill to that one.

## Feature setup — three questions, asked once

Setting up a feature for the first time: copy `templates/feature.md` to
`docs/chunks/<feature>/feature.md` in the target repo, list the chunks, then
stamp each chunk directory from the templates as it comes up. Before chunk 01,
ask the human three things and record every answer **in files** — an answer that
lives in chat scrollback doesn't exist next session:

1. **What is this feature derived from?** Sources, each classified `contract`
   (can produce acceptance criteria) or `implementation` (constrains the plan,
   never the spec).
2. **Are the chunk docs committed?** `tracked` (team) or `untracked`
   (personal). `readiness` reconciles the answer against git in both directions.
3. **What context should an agent load before planning here?** Context packs,
   as pointers and never inlined, under the same classification.

The mechanics, the costs of each answer, and the contract/implementation test
are in `references/audit-readiness.md` § Feature setup and `references/plan.md`
§ Context packs.

**One classification, used at every stage.** `contract` vs `implementation`
decides what a source may become *and* what each stage may load.
`audit-readiness` gets contract context only — not because it is early, but
because it writes `spec.md`, and `spec.md` is what the blind oracle-writer
reads. Implementation context first becomes legal at Track P. The load-order
table is in `references/plan.md` § Context packs.

## State layout (in the target repo)

```
docs/chunks/<feature>/
  feature.md              # epic: goal, constraints, sources, artifacts mode,
                          #   context packs, chunk queue
  <nn>-<slug>/
    spec.md               # contract: goal, binary acceptance criteria (each
                          #   citing its source), declared scope, test paths,
                          #   size class
    plan.md               # cold-executable plan + deviations log
    predictions.md        # human's pre-read predictions (plan gate)
    retro.md              # audit-implementation findings
    state.json            # stage, SHAs, branch, artifacts mode, oracle
                          #   hashes + red evidence — script-managed
    oracle-red.log        # the freeze-time red run — script-written
    oracle-green.log      # the verify-time green run — script-written
```

This tree is **in the repo working directory** whether or not it is committed —
never outside it. `chunk-check.sh` refuses a chunk directory outside the
repo root, and an agent's write sandbox is typically the working directory, so
state written under `~/` gets denied. Untracked-but-in-repo is the only shape
that works.

## The deterministic backstop

`bin/chunk-check.sh <op> <chunk-dir> [args]` — bash + git + jq, no other deps.
Guarantees live in this script (executed code, zero attention cost), not in
prose asking anyone to be careful.

- `readiness` — reconcile recorded state against disk (`spec.md` against
  `state.json`, the declared `artifacts` mode against git, `branch` against
  HEAD, `baseline_sha` against history), gate the declared fields, run the
  baseline suite → pin `baseline_sha` + `branch`, stage `ready`
- `predict` — stamp the filled top half of `predictions.md` into `state.json`
  while the verdict is still blank (refusing unfilled blanks and a
  pre-recorded verdict), noting whether a plan draft was on disk. This makes
  "the predictions were blind" a checkable claim rather than a remembered
  order of operations. `--one-pass` is the recovery for a file already filled
  in one pass: it stamps the top half anyway and **records that it happened
  that way**, because the refusal's only other exit — blank the verdict, stamp,
  restore it — is the same motion as laundering a prediction written after the
  plan, leaving the script to take a reconstruction on trust. The flag is
  refused when the verdict is still blank, so it cannot replace the strong path;
  what it drops is the ordering claim, stated in the record rather than in a
  comment, and `freeze` and `status` report the weaker tier
- `freeze` — the plan gate happened and approved, all four spec blocks agree
  with state, `oracle_cmd` runs **red** with no test green at birth and no
  collection error → hash-pin every tracked file under `test_paths`, stage
  `approved`. Requires the predict stamp on `standard` chunks and refuses a
  top half that moved since it was stamped, at every size
- `verify` — oracle unchanged, the frozen oracle re-run and green with the same
  node-ids, diff ⊆ declared scope, suite green, no commits the review gate has
  not approved → stage `verified`. Refuses on any bypassed chunk: no freeze
  happened, so there is nothing here to check and the review gate is its exit
- `log` — the retro's field-log line is really in the log file, carries a legal
  `gate:` verdict and has no field left as `?` → record it in `state.json`
- `gate <verdict>` — record the human's review verdict; from `verified` or
  `bypassed` only → `done`, back to `approved`, or `blocked`. `approved`
  re-reads the field log and refuses without the entry, then **hands off**: it
  names the next chunk (first sibling directory whose `state.json` is not
  `done` — no markdown parsed) and prints a pasteable resume prompt, because
  `done` is terminal for the chunk and used to be a dead end for the session.
  On a *bypassed* chunk it also records what actually shipped into
  `bypass_shipped`, since such a chunk has no `implement` op and no `verify`
  run, so its work otherwise appears in no state field at all
- `bypass "<what>"` — `trivial` chunks only, from `specified` or `ready` →
  stage `bypassed`. Runs `suite_cmd` before the stamp and records the exit code
  in `bypass_suite`, so the trivial path's baseline evidence is a fact on disk
  rather than a step someone was told to remember; it does not *gate* on the
  result, because a red baseline predates the chunk. `--downgrade` is the
  correction for an over-escalation spotted later: legal from any pre-`done`
  stage, sets `size_class` to `trivial` and records the correction. It skips
  `verify`, never the review gate
- `block "<reason>"` — stage `blocked`
- `status` — print the chunk's state

Each stage reference describes the op it uses; the complete argument surface,
including `--rebaseline` and `--refreeze`, is in `references/setup.md`.

**The backstop has its own oracle, held to non-negotiable #1.** `bash
bin/test-chunk-check.sh` builds throwaway repos in `$TMPDIR` and asserts each
guarantee. Run it after any edit to `chunk-check.sh` — and after *adding* a
check, delete that check in a scratch copy and confirm the suite goes red.
Green only means no fixture noticed: a 2026-07 mutation trial found five
checks the suite did not hold, including both halves of non-negotiable #1.
The suite's header carries the commands.

## Stabilization loop

After every chunk, `audit-implementation` appends one line of binary
observations to the field log — by default
`~/.claude/feature-chunker-field-log.md`, **outside** this skill's directory, so
re-installing the skill cannot overwrite the accumulated evidence. Append it
with **Write or Edit, not a shell `>>`**: the Bash sandbox denies writes under
`~/.claude`, and a denied append that looks like it worked is how a log silently
stops being kept.

**The append is checked, because for a long time it wasn't.** A 2026-07 audit
found the log empty at every install path: zero entries, so the demotion rule
could never reach its n and every proportionality claim here was unfalsified
rather than validated. The append was the one step in the lifecycle backed by
nothing but an instruction to remember — in a skill whose whole argument is that
an agent attesting to its own work is not evidence. `chunk-check.sh log` now
verifies the entry is on disk and records it, and `gate approved` re-reads the
file and refuses to stamp `done` without it. The script never writes the log:
the default path is under `~/.claude` where the Bash sandbox denies writes, so
the append stays a Write/Edit and this is the check that it happened.

Observed process failures become changes to these references in the session that
earned them — the skill improves the same way it asks code to: incident → case →
fix. The plan gate's demotion rule and the current streak live in the log's
header, which is the only copy. Location, the team variant, and installation:
`references/setup.md`.
