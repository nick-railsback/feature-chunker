# audit-readiness — is this chunk fit to plan?

Run before any planning. Two jobs: reconcile recorded state with reality, and
gate the spec's quality so planning doesn't start from mush. The cheapest
place to kill a bad chunk is here, where nothing has been spent yet.

## Preconditions

- The chunk directory exists with at least `spec.md` and `state.json`
  (stamp from `templates/` if missing — that's part of this operation).
- You are on the branch the work belongs to.

**The harness runs commands from a file in the repo.** `suite_cmd` and
`oracle_cmd` are shell strings in `state.json`, executed with `bash -c` by
`readiness`, `freeze` and `verify`. On your own repos that is what you want. On
a cloned, contributed, or agent-authored chunk directory, read both values
before running any op — the first `readiness` is enough to execute them. This
is named rather than mitigated in code on purpose: sandboxing or allowlisting a
test-runner command line would break every legitimate use (`poetry run pytest
…`, `npm test --`, compound commands) to defend against a threat model —
running someone else's chunk directory — that this skill's user does not
have.

## Feature setup — once per feature, before chunk 01

Skip to the Procedure if `feature.md` already exists and its **Sources** table,
**Artifacts** line and **Context packs** table are filled. Otherwise ask the
human these three questions now, at the only moment where the answers are
cheap, and record every answer in files — an answer that lives in chat
scrollback doesn't exist next session.

**1. What is this feature derived from?** Fill `feature.md`'s **Sources**
table: the PRD, ADRs, tickets, design docs or transcripts this work comes from.
Each is classified `contract` or `implementation` by the same test the context
packs use, and the classification decides what the document is allowed to
become:

- A **PRD**, acceptance-criteria doc or API contract is `contract`. It is the
  natural source of acceptance criteria, and Track V may see it.
- An **ADR**, design doc or architecture note is `implementation`. It
  constrains the *plan*, never the spec. An ADR's decision appearing as an
  acceptance criterion is a defect, not a shortcut: the oracle would be
  asserting the design, and would stay green through a refactor that broke the
  feature.

**Sources are not context packs**, and the two tables are separate on purpose.
A context pack is standing knowledge, re-loaded every chunk. A source is read
once — to derive the chunk queue and the specs — and after that **`spec.md` is
authoritative**. Upstream documents drift, and a frozen contract that defers to
a moving one is not frozen. If the PRD changes later that is a spec change:
re-derive, then run `readiness --rebaseline`, which clears the freeze and sends
the chunk back through the plan gate. Collapsing the two tables would also make
you pay for the whole PRD on every chunk forever, which is the context cost
`untracked` mode exists to avoid, arriving from the other end.

Two things make the derivation reviewable rather than decorative:

- **Every acceptance criterion cites its source** — `spec.md` carries a
  `Source:` line per criterion. One that cannot be traced is either an invented
  requirement or a hole in the source document, and both are worth finding
  here, at reading cost.
- **Deriving is a human call.** There is deliberately no op that generates
  specs from a PRD. Extraction quality is exactly the judged, unvalidated
  grader this skill refuses everywhere else — the `Source:` line is what makes
  a human's extraction checkable instead of an act of faith.

Leave the table empty if the feature has no upstream document. An empty table
is a real answer: it says this spec is the origin, not a derivation.

**2. Are the chunk docs committed?** Neither answer is the safe default; the
wrong one for the repo is what kills adoption.

- `tracked` — the chunks directory is committed and reviewed like code. Right
  for a **team**: the specs are the shared artifact, PR reviewers read them, and
  the audit trail survives a fresh clone.
- `untracked` — the docs live in the working tree and never enter git. Right for
  **personal projects**, where committing every spec accumulates a directory of
  near-identical documents describing versions of the code that no longer exist.
  That's stale context, and stale context is trusted, so it is worse than
  missing. It is also the worst-shaped context for future retrieval in that
  repo: attention is similarity-driven, so material that *looks like* the answer
  bids hardest against it.

Nothing in the backstop depends on the answer. The oracle is hash-pinned over
`test_paths` — code, which stays tracked either way — and the scope check is
pinned to commit SHAs. `bin/test-chunk-check.sh` runs the full lifecycle with
the chunks directory excluded and asserts it reaches `done`, so this is a
demonstrated property rather than a claim.

Record it in `feature.md`'s **Artifacts** line *and* in each chunk's
`state.json` `artifacts` key. `readiness` reconciles the declaration against
git in both directions and hard-fails on a contradiction: declaring `untracked`
with nothing excluding the directory means the next `git add -A` commits it,
and declaring `tracked` with a rule that matches it means git is silently
dropping the docs you believe you are committing.

For `untracked`, put the rule in **`.git/info/exclude`, not `.gitignore`**:

```
docs/chunks/
```

`.git/info/exclude` is per-clone and never committed, so choosing the mode
leaves no trace in the repo — a `.gitignore` entry is itself a repo change you
would have to justify in a shared project. If the write is denied, surface that
rather than retrying variations.

Two costs to state out loud before the human picks `untracked`:

- **`git clean -fdx`, a fresh clone, or a new worktree destroys the chunk
  state** — including `oracle-red.log`, the only evidence the oracle was ever
  calibrated. State becomes machine-local.
- **Untracked docs survive a branch switch**, where tracked ones would have
  disappeared with it. So a chunk directory from another branch can sit there
  looking live. `readiness` pins `branch` and warns on drift; that warning is
  the one that matters most in this mode.

**Never move the artifacts outside the repo** to get the same effect. Two
independent blockers: `chunk-check.sh` refuses a chunk directory outside the
repo root by design, and an agent's write sandbox is typically the working
directory — a shell script writing `state.json` under `~/` gets denied, and a
denied write that looks like it worked is how state silently stops being kept.
In-repo-but-untracked is the only shape that works.

**3. What context should an agent load before planning here?** Fill
`feature.md`'s **Context packs** table: the project-context skills, reference
docs, or ecosystem notes that make an agent effective in this repo without
re-deriving them per chunk. Record **pointers, not contents** — a named skill
loads on demand and costs nothing until it matches; a pack pasted into a spec is
paid for on every read of that spec forever, and re-creates exactly the
similar-distractor problem `untracked` mode exists to avoid.

Each entry is classified **contract** or **implementation**, because Track V
only ever receives the first kind. The rule and the test for it are in the
template and in `plan.md`; the classification is a human judgement made once per
feature, not per chunk.

For a multi-repo ecosystem: the harness is single-repo by construction — one
`git rev-parse --show-toplevel`, one chunk tree. Cross-repo work means one
feature directory per repo, each `feature.md` naming its siblings in
**Constraints**, and a context pack that covers the ecosystem listed in both.

## Procedure

1. **Reconcile state vs disk.** Read `state.json`. Every claim it makes must
   be observable: files it names exist, recorded SHAs are real commits.
   Recorded state that disk contradicts is a finding, not a starting point —
   surface it before proceeding. Four of these are now mechanical, and run in
   **both** modes below because they only read:
   - `baseline_sha` resolves to a real commit — else `fail`.
   - **`spec.md` agrees with `state.json`** — else `fail`. `scope_paths`,
     `test_paths` and `size_class` each exist twice: once in the document the
     human reads and approves, once in the file the script enforces. `readiness`
     compares them and hard-fails in either direction. `oracle_cmd` is the
     fourth of these and is reconciled at `freeze` instead, because Track V is
     what sets it and Track V runs after this op. See **The spec contract**
     below.
   - `artifacts` matches what git is doing, in both directions — else `fail`.
     An undeclared mode warns and checks nothing; that is the signal to run
     Feature setup above.
   - `branch` matches HEAD — else `warn`, not `fail`. A branch rename or a
     deliberate move is legitimate, and the op that would block on it is the
     one you run to recover. What the warning buys is visibility of the
     untracked-docs footgun: a chunk directory that outlived a branch switch.
2. **Rerun the baseline.** Run `bin/chunk-check.sh readiness <chunk-dir>`.
   It has **three modes**, chosen from the recorded stage:
   - Stage `specified` / `ready` / `blocked` → **full readiness**: the
     reconciliation checks run, then the suite (`suite_cmd` in state) must be
     green, then `baseline_sha` and `branch` are pinned to HEAD and stage set
     `ready`. The pin doubles as the schema migration point: it materialises
     keys a newer schema added, renames keys a newer schema renamed, and stamps
     the version, so the "older schema" warning clears itself instead of
     nagging forever.
   - Stage `approved` / `verified` / `done` / `bypassed`, no flag →
     **reconcile-only**: every read-only check runs and prints, and **nothing
     is written**. Running `audit-readiness` on an in-flight chunk is
     therefore safe — it cannot move a baseline out from under a live freeze,
     which would leave `verify`'s scope check comparing against a HEAD that
     already contains the chunk's own diff.
   - `--rebaseline` from any stage → **full readiness, and it clears the
     freeze**: `test_hashes`, `oracle_red`, `oracle_green`, `gates.plan` and
     `plan_approved_sha` are reset, and the plan gate must run again. Moving
     the clock means restarting the chunk, not keeping its approval.

   The previous baseline is kept in `baseline_prev_sha` on every re-pin, so a
   rebaseline is auditable. Never skip the rerun because the last session
   recorded green — that record is a claim about a repo that may have moved.
3. **Gate the spec.** Load the feature's **contract** context packs first, and
   only those. Two of the five gates below are human judgement about domain
   semantics, and an agent that cannot tell what the project's own interfaces
   promise cannot tell a checkable criterion from a vague one — this step is
   otherwise making its most important call with nothing loaded.

   Implementation packs are illegal here, for the same reason they are illegal
   for Track V but arriving by a quieter route: **this step's output is
   `spec.md`, and `spec.md` is what Track V reads.** Architecture in the window
   while acceptance criteria are being written becomes architecture in the
   criteria, and the subagent boundary cannot catch what the spec already
   carries. The full load order is in `plan.md` § Context packs.

   Then read `spec.md` and hold it to this standard. Three of these five are
   **mechanically enforced** by `readiness` (it hard-fails without them); two
   remain human judgement, and saying so is the point — five bullets that read
   as equally enforced when only three are is exactly the drift this harness
   exists to remove.
   - **Goal** *(human judgement)* — one paragraph, states the user-visible
     outcome.
   - **Acceptance criteria** *(human judgement)* — each one binary and
     mechanically checkable. "Improve the error message" fails this gate;
     "`discover` with zero sources exits 2 and prints the registration hint"
     passes. A criterion you can't imagine a test asserting is not a criterion
     yet. Where the feature has sources, each criterion also carries a
     `Source:` line: an untraceable one is invented or reveals a hole upstream,
     and one traced to an `implementation` document is the ADR-as-criterion
     defect from question 1.
   - **Declared scope** *(enforced: `scope_paths` non-empty and equal to the
     spec's `scope` block)* — the file paths implementation may touch. Missing
     or "wherever needed" fails the gate.
   - **Test paths** *(enforced: `test_paths` non-empty and equal to the spec's
     `test-paths` block; `freeze` and `verify` additionally require each entry
     to resolve to tracked files)* — where the oracle will live.
   - **Size class** *(enforced: one of `trivial` / `small` / `standard`, and
     equal to the spec's `size-class` block)* — assigned honestly.

## The spec contract — why four fields are written twice

`spec.md` is what a human reads before approving. `state.json` is what
`chunk-check.sh` enforces. Both need the same four values, and for a long time
nothing compared them — which meant the enforced scope could drift away from the
approved one in total silence. A spec declaring `src/api/` beside a state
declaring `src/` prints `PASS all changes within declared scope` over a diff
touching `src/billing/`, and the human who approved the narrow version never
finds out.

So the four values live in `spec.md` as **fenced blocks with an info string**,
and the script parses and compares them:

| Block | Reconciled against | Checked by |
|---|---|---|
| `scope` | `scope_paths` | `readiness`, `freeze` |
| `test-paths` | `test_paths` | `readiness`, `freeze` |
| `size-class` | `size_class` | `readiness`, `freeze` |
| `oracle` | `oracle_cmd` | `freeze` only |

Fences rather than prose bullets because a block delimiter is unambiguous: no
nested lists, no inline commentary, no leftover `<placeholder>` text to mistake
for a value. Trailing slashes are normalised on both sides, because the scope
check already treats `src/` and `src` as the same path — a comparison stricter
than the enforcement it guards would fail on a difference that cannot matter.

Keeping them in step is not busywork: **a divergence is always a real question
about which one the human agreed to.** Fix the side that is wrong, don't paper
over the mismatch by editing whichever is closer to hand.

`oracle` sits out `readiness` because Track V sets `oracle_cmd`, and Track V
runs during `plan`. At readiness time the block is still the spec author's
intent; by `freeze` it has to be the command that actually ran red.
4. **Apply the sizing rule.** Ask: could an agent that has read nothing but
   `spec.md` and the eventual plan execute this inside one session? If the
   honest answer is no, the chunk is too big. Split it in `feature.md` now
   — two well-sized chunks cost less than one abandoned window.
5. **Apply the bypass rule.** If size class is `trivial` — no design
   decision, 1–2 files, trivially reversible — the lifecycle does not apply.
   Run `bin/chunk-check.sh bypass <chunk-dir> "<one line: what the work
   is>"`, do the work directly, and hand the diff to the human for review. The
   full ceremony on a two-minute change is how a harness teaches its user to
   stop using it. Two things the op enforces so the hatch cannot rot: it
   requires `size_class` to be exactly `trivial` (non-negotiable #7 is
   proportionality, not convenience) and it is illegal from any stage past
   `ready`, so a frozen chunk cannot be bypassed out of its own gate. It also
   prints the field-log line to append — a bypassed chunk still enters the
   evidence base, or "was the ceremony proportionate?" gets answered only by
   the chunks that already paid for it.
6. **Verdict.** Either stage is `ready` (script has pinned the baseline), or
   `bin/chunk-check.sh block <chunk-dir> "<reason>"` sets stage `blocked`
   and appends the reason to `state.json`'s `blockers` array. No planning
   happens in this operation under any outcome.

A bypassed chunk still exits through the human review gate:
`bin/chunk-check.sh gate <chunk-dir> approved` once the human has read the
diff. One verdict, one key, one check — which also means the commit
prohibition `verify` enforces covers bypassed chunks for free. It also needs
its field-log line and its `chunk-check.sh log` run before that gate will
close, exactly like a chunk that paid for the full lifecycle: a dataset made
only of ceremonious chunks can never answer whether the ceremony was
proportionate. The line `bypass` prints leaves `ceremony-ok:?` and `context:?`
for the human to answer, and `log` refuses the line while a `?` remains. There is no
`unblock` op: `readiness` already clears `blockers` and re-pins, and a second
route to the same state is a second thing to keep true.

## Stop-and-surface conditions

- Baseline suite red → the repo has a problem that predates this chunk.
  Fix that first, outside this lifecycle.
- Spec contradicts `feature.md` or reality → back to the human before a plan
  is built on a wrong contract.

## Failure modes

- **Trusting recorded green.** The suite passed last Tuesday in someone
  else's session. Rerun it.
- **Waving vague criteria through.** Every non-binary criterion becomes a
  judged check downstream — you are choosing an expensive, unvalidated grader
  over a cheap deterministic one, one lazy sentence at a time.
- **Planning anyway.** Readiness that ends in a plan wasn't an audit; it was
  the first half of an unchunked session.
