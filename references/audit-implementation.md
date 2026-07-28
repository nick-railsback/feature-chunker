# audit-implementation — honest green, human review, then the retro

Two halves. The first half proves the green is honest before any human time
is spent — machine checks run first precisely so review time is never spent
on a mechanically invalid result. The second half is why this skill gets
better: the chunk audits the process, not just the product.

**What this operation is, and is not.** It is deterministic verification,
packaging, and a retro. It is *not* an independent review: nothing here
requires a fresh session or a different agent, and step 1 re-runs the same
`verify` the implementer already ran at exit. The independence in this design
comes from two other places — the script, which is code and does not care who
is asking, and the human, who holds the original ask. If you want a third
source, run half 1 in a subagent given `spec.md`, the frozen tests, and the
diff, but *not* the implementation transcript. That buys immunity to context
poisoning and to the commitment pressure of having just written the code; it
does not buy uncorrelated blind spots, because it is the same model reading
the same artifacts.

## Half 1 — deterministic verification and review packet

1. Run `bin/chunk-check.sh verify <chunk-dir>`. It asserts, in order:
   - **Oracle integrity** — every hash-pinned test file byte-identical since
     freeze; no test files added or removed under `test_paths`. The map covers
     **tracked** files only (`git ls-files`), so `.gitignore`d build artifacts
     never enter it — and an *untracked* file appearing under `test_paths` is
     itself a failure, not an omission: an oracle that is not tracked cannot be
     frozen or reviewed. A mismatch is a hard stop: the green means nothing,
     route back to `implement` (or to the plan gate if the oracle itself is in
     dispute).
   - **Scope integrity** — every changed path (committed, staged, unstaged,
     untracked) since `baseline_sha` falls under declared scope, `test_paths`,
     the chunk's own docs directory, or the feature's top-level docs
     (`feature.md`, whose chunk queue is supposed to be kept current). A
     sibling chunk's directory is *not* covered: that is another review's diff.
   - **Oracle red→green** — the frozen `oracle_cmd` is re-run, must exit zero,
     and must be the *same string* pinned at freeze (a narrowed command cannot
     buy a green). Where node-ids were captured at freeze, every frozen red id
     must appear as `PASSED` in this run — a skip, a rename, or a test no
     longer collected fails here. The evidence tier lands in
     `state.json.oracle_green.evidence_tier`: `node-ids`, `exit-code`, or
     `legacy`.
   - **Suite green** — rerun now, not recalled.
   On full pass the script sets stage `verified`.
2. Assemble the **review packet** for the human — the diff summary
   (`git diff --stat <baseline_sha>`), the deviations log from `plan.md`,
   the verify output (the honest-green attestation), and any commits made
   since baseline (there should be none by the harness; human commits are
   theirs to explain — and note that commits since baseline are now a **hard
   verify failure** until `gates.review` is `approved`, not an observation for
   the packet). If `oracle_green.evidence_tier` is `legacy`, **say so in
   the packet**: that chunk was frozen by a pre-schema-2 script, so verify
   proved the oracle passes but not that it could ever fail. An `exit-code`
   tier is worth one sentence too — it means no per-test evidence was parsed.
3. **Present before commit.** The human reviews the actual diff with the
   packet beside it. Record their verdict with
   `bin/chunk-check.sh gate <chunk-dir> <verdict> [reason]`, which is what
   writes `state.json.gates.review` and moves the stage: `approved` (stage
   `done`; the human commits from here), `changes-requested` (back to
   `approved`, i.e. to `implement`, with the notes), or `rejected` (stage
   `blocked`, reason required and appended to `blockers`). The gate is legal
   only from `verified` or `bypassed` — it cannot be used to skip the
   verification it is supposed to follow.

   **`approved` additionally requires the field-log entry** (half 2 below, then
   `chunk-check.sh log <chunk-dir>`), and re-reads the log file rather than
   trusting what `state.json` recorded. Run the retro before the gate, not
   after: `done` is terminal, so it is the last moment the evidence can be asked
   for at all.
4. The harness never commits. Still. Even now. And `verify` refuses to stamp a
   chunk carrying commits the review gate has not approved — so the rule is
   checkable, not merely repeated. Two limits, stated because a half-enforced
   rule that reads as airtight is worse than an honest one: the in-script check
   is a *detector*, running after the commit already exists, and it only fires
   if someone runs `verify`. The *preventer* is the optional `PreToolUse` hook
   `hooks/chunk-no-commit.py`, which sits on the tool call itself. Neither
   reaches the human's own terminal, which is correct — the human committing is
   the design's intended exit, not the threat.

## Half 2 — the retro (this is how the skill stabilizes)

Fill `retro.md`'s binary observations — they are deliberately yes/no, named,
and boring, because a 1–7 "how did it go" score is dashboard soup nobody can
act on:

- Plan gate verdict was: approve / adjust / reject / auto-pass / n/a (bypassed)
  — the same word `state.json.gates.plan` holds, so the log, the retro and the
  state file never need translating between three spellings
- Predictions disagreed with the plan meaningfully: y/n
- Oracle caught a real implementation defect (any red→green iteration after
  the first honest attempt): y/n — and the iteration count
- Oracle violation attempted or detected (freeze tripped): y/n
- Scope deviation occurred: y/n (in-scope logged / out-of-scope surfaced)
- Bypass used: y/n — and, in hindsight, appropriately: y/n
- Ceremony proportionate to the work: y/n
- Context pack loaded: name or `none` — and whether the plan needed something
  the pack didn't carry: y/n. That second half is the only observation that can
  ever retire or repair a pack; "the pack was loaded" on its own is attendance,
  not evidence.

Then one line of free text: where the protocol chafed.

**Append one line to the field log** — by default
`~/.claude/feature-chunker-field-log.md`, or the repo-local path `feature.md`
names for a team. **Append it with Write or Edit, never a shell `>>`:** the Bash
sandbox denies writes under `~/.claude`, and a denied append can look like it
succeeded. If the file does not exist, stamp it from `templates/field-log.md`.

**Then run `bin/chunk-check.sh log <chunk-dir>`.** It finds the line whose first
three fields are the date, this repo and this chunk, refuses one whose `gate:`
verdict is missing or not legal (the demotion rule reads that field, so an entry
without it counts in neither direction), refuses one with any field still left
as `?`, and records it in `state.json.field_log`. Until that op passes, `gate
approved` will not stamp `done`.

This check exists because the append had none. A 2026-07 audit found the log
empty at every install path — the demotion rule could never fire, and the whole
stabilization loop was an instruction to remember, sitting in the one skill
whose argument is that instructions to remember are not mechanisms. If the op
refuses your line, fix the line; do not route around it by editing
`state.json`.
Why it lives where it does, and the team variant, are in `references/setup.md`.

Entry format is in the log's header, and it carries a `context:` field — read
that header's note on what the field can and cannot support before drawing
anything from it. Then apply the incident-to-case rule to the harness itself:

- Any process failure observed → a concrete candidate change to these
  reference files, made **in the session that earned it**, not deferred to a
  hypothetical cleanup pass.
- **Check the demotion rule against the log's header, which states it.** Read
  it there and apply it there; it is not restated here, because the log lives
  outside this skill directory and a copy in this file would silently disagree
  the first time the header is edited.

## Failure modes

- **Human review before machine verify.** Review time spent on a diff whose
  green was dishonest is the most expensive minute in the lifecycle.
- **Retro skipped because the chunk went fine.** Fine chunks are data
  too — the demotion rule runs on consecutive clean gates, which unlogged
  clean chunks don't count toward. Bypassed chunks need logging for the
  opposite reason: they are the only evidence that the ceremony was
  disproportionate, and they are invisible to a dataset made only of chunks
  that paid for it. This is the failure the `log` op now catches, and it is
  worth naming that it was named here for a long time before anything checked
  it: a documented failure mode with no mechanism behind it is a prediction,
  not a guard.
- **Verdicts without state.** A review that lives in chat scrollback doesn't
  exist next session. The gate result goes in `state.json` or it didn't
  happen — and there is now one mechanism that puts it there,
  `chunk-check.sh gate`, rather than an instruction to remember to.
