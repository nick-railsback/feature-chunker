# setup — installing the skill, the hook, and the field log

None of this is needed to run a chunk. It is the once-per-machine and
once-per-feature material that used to sit on the routing surface, where it was
paid for on every trigger and read on almost none of them.

## Install

**User-level is the default**, and the design already assumes it: the field log
lives outside both the skill directory and any repo because the evidence base
spans projects. One installation means one place improvements land and one
dataset the demotion rule can actually reach its n on. A copy per project forks
that — N drifting copies, each with a partial log, none of them accumulating.

A **project-level** copy is the team case, and it is a fork the moment the
user-level one improves. Take it deliberately, and move the field log into the
repo (see § The field log) — a per-developer log across a team is the same
small-sample failure in a different costume.

Copy this directory to `~/.claude/skills/feature-chunker/`:

```
rsync -a --exclude '.DS_Store' --exclude '.pytest_cache' --exclude '__pycache__' \
  <src>/ ~/.claude/skills/feature-chunker/
```

The excludes matter: a stray `.DS_Store` or cache directory riding along is
noise in an artifact whose whole argument is that nothing unexamined ships.

The field log is **not** part of this copy — it lives at
`~/.claude/feature-chunker-field-log.md` and survives reinstall untouched;
`templates/field-log.md` is only the seed to stamp when that file does not yet
exist. Self-contained otherwise; pairs with `agentic-patterns` and
`eval-patterns` but depends on neither.

## The commit-preventer hook

`verify` **detects** commits made before the review gate; it runs after the
commit already exists, and only if someone runs `verify`. The **preventer** is
`~/.claude/hooks/chunk-no-commit.py`, wired as a `PreToolUse` hook on `Bash` in
`settings.json`. It denies a `git commit` tool call while any chunk in the
project is at `ready`/`approved`/`verified` with `gates.review` not `approved`.

It lives outside the skill because hooks are user-level configuration, not skill
content — so the rsync above does not carry it and it has to be installed once,
separately. Neither the hook nor the check reaches the human's own terminal,
which is correct: the human committing is the design's intended exit, not the
threat.

**The hook has an oracle now, and it needed one.** `hooks/test_chunk_no_commit.py`
(run: `python3 -m pytest hooks/test_chunk_no_commit.py -q`) exists because a
2026-07 audit found this was the only hook in `~/.claude/hooks/` without a test
file, while the far less load-bearing gates beside it all had one. Probing it by
hand found four shapes that walked straight past: a commit message containing
`;` or `|` (the splitter cut the line into fragments before honouring quotes),
`sh -c 'git commit …'`, a wrapper word such as `env` or `nohup` in front of
`git`, and a program name held in a shell variable. The first is not an exotic
case — it is what happens when someone writes a normal commit message.

Two things worth keeping straight afterwards. The guarantee never failed open
entirely: `verify` still refused to stamp a chunk carrying unapproved commits,
so the failure degraded to detect-not-prevent. And the parser is still static,
so `eval`, `$(echo git)`, and a commit inside a script file are **not** caught —
those are pinned as known limits in the suite rather than implied away, because
a preventer that pattern-matched hard enough to catch them would start denying
legitimate commands, and a gate the operator fights is a gate the operator turns
off. `verify` is the backstop for that tail, by design.

## The field log

Default path `~/.claude/feature-chunker-field-log.md` — the `~/.claude` root,
**not** inside `skills/feature-chunker/`, so re-installing or re-exporting the
skill cannot overwrite accumulated evidence. Stamp it from
`templates/field-log.md` if it does not exist yet, and never the other way
round.

**Append with Write or Edit, never a shell `>>`.** The Bash sandbox denies
writes under `~/.claude`, and a denied append that looks like it worked is
exactly how a log silently stops being kept.

**The append is enforced, and it took an audit to notice it wasn't.** In
2026-07 this log was empty at every install path — zero entries, across the
current skill and its predecessor. The demotion rule could not reach its n, so
the plan gate could be neither retired nor defended, and "ceremony must be
proportionate" was a claim with no dataset behind it. The failure shape is the
one this skill names everywhere else: the append was the single lifecycle step
whose only backing was an instruction to remember.

So `chunk-check.sh log <dir>` reads the log, finds this chunk's line, checks it
is actually filled in, and records it in `state.json.field_log`; and `gate <dir>
approved` re-reads the file and refuses `done` if the line is gone. The script
**verifies but never writes** — the default path is under `~/.claude` where the
Bash sandbox denies writes and permits reads, so the split is forced by the
sandbox and correct anyway: the thing being checked should not be written by the
checker.

Only the `approved` verdict requires it. `changes-requested` and `rejected` do
not, because those chunks have not finished and a retro they cannot yet write
would be ceremony charged at the wrong moment.

**Team variant:** point the log at a repo-local path (`docs/chunks/field-log.md`)
and name that path in `feature.md`, and pass it once as `log --log-path
docs/chunks/field-log.md` — the path lands in `state.json` and every later op
finds the same file. The machine-local default across a team means N laptops
each accumulating a partial evidence base and a demotion streak that never
reaches its n.

The demotion rule and the current streak live in that file's **header**, which
is the single authoritative copy. Nothing in this skill restates it, so that
editing the header cannot leave a stale duplicate behind.

## Per-op reference for `bin/chunk-check.sh`

The stage references describe each op where it is used; this is the complete
argument surface in one place.

| Invocation | Legal from | Effect |
|---|---|---|
| `readiness <dir>` | `specified` / `ready` / `blocked` | Full: reconcile, gate declared fields, run the baseline suite, pin `baseline_sha` + `branch`, stage `ready` |
| `readiness <dir>` | any later stage | Reconcile-only; writes nothing |
| `readiness <dir> --rebaseline` | any stage | Full, **and clears the freeze**: resets `test_hashes`, `oracle_red`, `oracle_green`, `gates.plan`, `plan_approved_sha`, the `predict` stamp; the plan gate must run again. Previous baseline kept in `baseline_prev_sha` |
| `predict <dir>` | `ready` | Stamp the filled top half of `predictions.md` into `state.json.predict` (hash, timestamp, whether `plan.md` was on disk), refusing unfilled blanks or an already-recorded verdict. Re-running replaces the stamp with a warning — legal while the plan is unread |
| `freeze <dir>` | `ready` | Reconcile all four spec blocks, require an approved `predictions.md`, verify the `predict` stamp (required on `standard`; any existing stamp's hash is held to at every size), run `oracle_cmd` and require red, hash-pin tracked files under `test_paths`, pin `plan_approved_sha`, stage `approved`. Also runs `suite_cmd` once, **non-gating**, recorded as `freeze_suite` — see below |
| `freeze <dir> --refreeze` | `approved` | The same, replacing a pin a plan gate already approved. For re-freezing after the gate adjusted the tests |
| `verify <dir>` | any chunk that froze an oracle (needs a baseline and a freeze) | Oracle unchanged, frozen oracle green with the same node-ids, diff ⊆ scope, suite green, no unapproved commits → stage `verified`. Refuses outright while `bypass_note` is set — a bypassed chunk has no frozen oracle and its exit is the review gate. Keyed on the marker rather than on stage `bypassed`, so it still refuses after that chunk reaches `done`; `readiness --rebaseline` clears the marker and re-enables the op |
| `log <dir>` | `verified` / `bypassed` | Find this chunk's line in the field log (first three fields = date, repo, chunk), require a legal `gate:` verdict and no `?` left in any field, record it in `state.json.field_log`. Writes nothing to the log |
| `log <dir> --log-path <file>` | same | The same, against an explicit log file. The path is recorded, so a team pointing the log at `docs/chunks/field-log.md` states it once |
| `gate <dir> approved` | `verified` / `bypassed` | Re-read the field log, require the recorded entry to still be there → stage `done`; the human commits from here |
| `gate <dir> changes-requested [note]` | `verified` / `bypassed` | Back to `approved` (i.e. to `implement`) |
| `gate <dir> rejected <reason>` | `verified` / `bypassed` | Stage `blocked`; reason required, appended to `blockers` |
| `bypass <dir> "<what>"` | `specified` / `ready`, `size_class` = `trivial` | Stage `bypassed`; prints the field-log line to append |
| `bypass <dir> --downgrade "<why>"` | any stage before `done`, `size_class` ≠ `trivial` | Correct an over-escalation: sets `size_class` to `trivial`, records `size_class_corrected` (previous class, originating stage, reason), stage `bypassed`. Freeze evidence is kept; the field-log line carries the real `gates.plan` verdict, not `gate:none` |
| `block <dir> "<reason>"` | any | Stage `blocked`; reason appended to `blockers` |
| `status <dir>` | any | Print the chunk's state |

There is no `unblock`: `readiness` already clears `blockers` and re-pins, and a
second route to one state is a second thing to keep true.

**`freeze_suite` — why `freeze` runs the whole suite when it's expected to be
red.** `freeze` pins `oracle_cmd`, which is a narrow slice of `suite_cmd` —
and whenever the chunk's new tests are part of `suite_cmd`, which is the
common case, the *whole* suite is red from freeze until implementation goes
green, because the unimplemented oracle sits inside it. A red `suite_cmd` at
freeze time is therefore not news — but *why* it's red is: a lint, doctrine, or
schema break baked into the files just hash-pinned looks identical, exit-code-
wise, to the expected new-oracle red, and stayed invisible until implement's
first full-suite run. That cost two chunks in the same feature a stop-and-
surface each (skill-engine chunks 14 and 15: a stray path reference and a dead
shell variable, both inside the frozen oracle's own header/body, both
lint-only breaks unrelated to any test assertion) before `freeze` ran the
probe. It does not gate — a red baseline is expected and blocking freeze on it
would be the same disproportion non-negotiable #7 already refuses for
`bypass_suite` — it records the exit code and command in `state.json` and
prints the run's output so a human reading the freeze transcript can notice
"this died in shellcheck, not in my new test" immediately, at freeze time,
instead of one implementation session later.

**What `--downgrade` does and does not relax.** It relaxes the stage guard on
`bypass`, which existed so a frozen chunk could not be bypassed out of its own
gate. It does *not* relax the review gate: a downgraded chunk is `bypassed`, and
`bypassed` still exits through `gate`, which still re-reads the field log before
stamping `done`. What it genuinely skips is `verify` — so it is an explicit flag
that is never inferred, it requires a reason, and it records the stage it was
used from. Before it existed, a chunk escalated out of `trivial` by mistake had
no honest terminal state: `bypass` was illegal by the time the misjudgement was
visible, and `blocked` means unfinished work. The escalation error is the single
most valuable observation the proportionality dataset can hold, and it was the
one the state machine could not record. Correct `spec.md`'s `size-class` block
too, or the next `readiness` hard-fails on the divergence.

## Keeping the backstop honest

`bash bin/test-chunk-check.sh` builds throwaway repos in `$TMPDIR` and asserts
each guarantee. Run it after any edit to `chunk-check.sh`.

Green means "no fixture noticed", which is not the same as "the guarantee
holds". After adding a check, **delete that check in a scratch copy and confirm
the suite goes red** — the same red demonstration non-negotiable #1 requires of
every chunk, applied to the thing enforcing it. The suite's header carries the
exact commands, and the reason: a 2026-07 mutation trial across eight checks
found five that could be deleted with the suite still green, including both
halves of non-negotiable #1 and all three plan-gate parse failures.
