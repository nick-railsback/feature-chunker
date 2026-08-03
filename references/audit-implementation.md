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

**When each half runs.** Under the one-arrival cadence (SKILL.md § Cadence)
this operation is split across the session boundary rather than run as one
block: the implement session performs Half 1 steps 1–2 and pre-fills Half 2's
derivable observations *before it stops* — the stop is what fires the human's
notification, so it must mean "review is ready", not "ops remain". The
arrival then spends human time only on human calls, in this order: read the
diff with the packet, answer `ceremony-ok` and `chafe`, run `log`, run `gate`,
commit — then pin and freeze the next chunk, whose plan was drafted ahead
(`references/plan.md` § Draft-ahead), and leave it implementing. Picking up
cold instead (no packet on disk), run both halves here as written.

## Half 1 — deterministic verification and review packet

1. Run `bin/chunk-check.sh verify <chunk-dir>`. **Skip this step entirely for a
   bypassed chunk** — it never froze an oracle, so there is nothing here to
   assert, and `verify` now refuses from that stage rather than running the
   whole suite to report the intended state of the world as failures. Go
   straight to the review packet and the gate. Otherwise it asserts, in order:
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
   - **Suite green** — rerun now, not recalled. **`suite_cmd` is usually a
     subset of what CI runs**, so a green here is evidence about the suites it
     names and nothing else: a repo whose CI is several workflows — a lint
     workflow plus a separate security or scan workflow — has gates `verify`
     never executes. Name that gap in the review packet rather than letting
     "suite green" be read as "CI green", and if the chunk touched anything
     those other workflows scan, run them by hand before the gate.
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

   **`approved` prints the handoff — relay it, don't retype it.** The op names
   the next chunk and emits a pasteable resume prompt, and on a bypassed chunk
   also prints and records what shipped. Both are the script's output rather
   than your reconstruction: `done` is terminal for the chunk and was a dead end
   for the session, and a resume prompt composed from memory is the scrollback
   dependency non-negotiable #3 exists to remove. If the queue says the next
   chunk is blocked on an open fork, say so alongside it — the script reads
   stages, not `feature.md`'s prose.

   **When the next chunk was drafted ahead, the handoff is work, not just a
   prompt.** The human has committed; the tree the next chunk will be built on
   now exists. Run its `readiness` (full mode — the pin needs this HEAD),
   surface its `## Questions`, then run its plan gate per `references/plan.md`
   — for a `standard` chunk, predictions before the plan is shown — and freeze
   on approval. The human leaves one arrival with the previous chunk committed
   and the next one implementing. On `changes-requested` instead, none of this
   runs: the draft gets revised alongside the rework, and the arrival that
   approves the rework picks it up.
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

- Plan gate verdict was: approve / adjust / reject / auto-pass / n/a (bypassed).
  **Not simply the word `state.json.gates.plan` holds** — `freeze` *refuses* the
  verdict `adjust` ("apply it and re-gate; freeze records approval only"), so
  `gates.plan` can never hold it and the adjustment survives only in
  `gates.plan_adjusted`. Log `adjust` whenever that boolean is true, and `none`
  for a bypassed chunk whose `gates.plan` reads `n/a`. Transcribing `gates.plan`
  instead makes `gate:adjust` unreachable, which silently retires the demotion
  rule's `adjust` clause: every plan the human changed would count *toward*
  retiring the gate that changed it. `chunk-check.sh log` now derives the
  expected value and refuses a line that disagrees, so this is a check rather
  than a convention — added 2026-07-29 after the convention and the rule were
  found to have been written from the same analysis and implemented against
  different halves of it (skill-engine 04-eval-corpus-split, retro candidate 4).
- Predictions disagreed with the plan meaningfully: y/n
- Oracle caught a real implementation defect (any red→green iteration after
  the first honest attempt): y/n — and the iteration count
- Oracle surfaced a defect with **no** red→green iteration: y/n — and where.
  The question above counts only defects found by implementation going red,
  which is the *narrowest* way a blind oracle pays. It also pays at freeze time
  (a criterion that turns out to be unassertable, non-portable, or a
  transcription of the design rather than the outcome) and by collision (the
  oracle trips an unrelated lint, hook or CI rule that was already broken).
  Both are invisible to the iteration count, so without this line the evidence
  base systematically understates blind-oracle value — in the one skill whose
  central claim is that writing validation blind is worth the ceremony. Added
  2026-07-29 after a chunk logged `n(1)` for an oracle that had caught two real
  things.
- Oracle violation attempted or detected (freeze tripped): y/n
- Scope deviation occurred: y/n (in-scope logged / out-of-scope surfaced)
- Bypass used: y/n — and, in hindsight, appropriately: y/n
- Ceremony proportionate to the work: y/n
- Context pack loaded: name or `none` — and whether the plan needed something
  the pack didn't carry: y/n. That second half is the only observation that can
  ever retire or repair a pack; "the pack was loaded" on its own is attendance,
  not evidence.

Then one line of free text: where the protocol chafed.

**The chunk that changes what a pack describes owes the pack an update.**
Check the diff against each pack's `Covers` globs in `feature.md`'s Context
packs table. On overlap, either update the pack in this session — the one with
the diff in its window, per the incident-to-case rule — or state in the review
packet that it still holds and why. This is the refresh half of pack
maintenance; the retro line above only ever catches gaps. It is a
review-packet catch rather than a script check, the same posture as
tracked-cites-untracked: `chunk-check.sh` parses no markdown, and the retro
line's `context:` data will show if this prose gets skipped in practice —
that evidence is what would earn the mechanism. The asymmetry that makes the
cost bearable: contract packs rarely drift (the rewritten-from-scratch test
selects for stability), so the update burden falls on implementation packs,
which only Track P reads — a mid-feature refresh can never contaminate an
oracle.

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
- **An oracle that reasons about repository state, calibrated only in the
  working tree.** `verify` runs pre-commit, in a full local clone, with HEAD at
  the last commit — which is not the state the oracle will live in. An
  assertion *about* HEAD is evaluated in the one state that never persists:
  recording a value that names HEAD is itself the commit that falsifies it, so
  the oracle is correct exactly once. An assertion that reads history, or blobs
  at an older sha, assumes a clone depth the default CI checkout does not
  fetch. An assertion about tracked-ness assumes staging the runner never
  performs. Whenever an oracle touches git history, HEAD, or tracked-ness,
  calibrate it twice more before freeze: once against a shallow clone (`git
  clone --depth 1`), and once with HEAD detached at a synthetic merge commit,
  which is what `actions/checkout` builds for a pull request. Both are seconds
  of work, both fail loudly, and either would have caught this class. Earned
  2026-08-02 by `24-dogfood-corpus-refresh`, which drew all three variants at
  once; see the field log's post-merge addendum for that entry.
