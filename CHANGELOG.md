# Changelog

This skill changes on field evidence only: an incident in a real feature run
becomes a failing case in `bin/test-chunk-check.sh`, then a mechanism or a
reference edit, in the session that earned it. Entries cite that evidence as
field-log entries `(date, repo)`. The field log itself is machine-local by
design (`templates/field-log.md` explains why it never travels with the
skill), so the citations here are the durable half of each story.

## 2026-08-04 — the collection-ERROR check: two defects, one of them a hole

`freeze` refuses a red run that reports collection or setup `ERROR`s — red for
the wrong reason. Freezing `supply-chain-ops-assistant`'s
`02-adjust-inventory-action` found the check wrong in both directions at once.

**False positive.** It matched bare `^ERROR`, which also matches a *captured log
record*: pytest's default log format is `%(levelname)-8s %(name)s:%(file)s:
%(line)d`, so a handler logging at ERROR level under a failing test prints
`ERROR    pkg.mod:mod.py:474 …`. That refused the freeze of a correctly-red
oracle whose code under test logs an error — which is normal behaviour, and in
this case was the behaviour the oracle asserted. The discriminator is now the
subject's **shape**: a collection error names a location (`::` or ending `.py`),
a log record names a logger. Not padding — `log_format` is configurable and the
shape is not.

**False negative, and the more serious one.** The check sat *inside* the
node-id-capture branch, so it ran only when node-ids were parsed from the
output. A module that fails to import produces none — meaning the run where
**nothing executed at all** was the one run the check never inspected. Case 27
had pinned the check since it was written, on a fixture whose `ERROR` line
happened to carry a node-id; that made the check reachable and the hole
invisible. This is exactly the "passes for the wrong reason" class this suite's
own header warns about, found again in the check that class was written for. The
check is now hoisted out and runs at every evidence tier.

Cases 27b (a log record must not read as a collection error) and 27c (a
collection error with no node-id is still one) in `bin/test-chunk-check.sh`.
Both mutation-tested: reverting the discriminator reddens 27b, re-nesting the
check under node-id capture reddens 27 and 27c.

## 2026-08-04 — the candidates ledger gets a read path

An independent review of the `inventory-action` feature found ten defects on a
branch where every gate was green (2026-08-04, supply-chain-ops-assistant,
chunks 01 and 02). The highest-leverage finding was not about any chunk. It was
about this repo.

`CANDIDATES.md` shipped 2026-08-03 carrying an entry, "Cross-chunk caller/seam
sweep at spec time or Track V", at three sightings, annotated in its own words
**"overdue for a mechanism"** under the escalation rule at the top of the same
file. One day later a chunk widened a shared module-global regex; the change
emptied the target list for every other consumer of it. That is the entry's
class exactly, and the entry was already written down when the chunk was
specified. Nothing read it.

So the ledger was never the problem — the write path worked three times. A
ledger nothing reads is a diary, and the escalation rule was prose depending on
someone happening to re-open the file.

Every entry now carries `Status: open|landed · Occurrences: N · Last: <date>
<repo> <chunk>`, and `chunk-check.sh log` prints the open entries that have
reached two sightings, at every chunk close, until they are built or rejected.
It warns and never fails: a mechanism cannot be built mid-chunk, and blocking
someone's chunk over a maintainer's backlog is the disproportion
non-negotiable #7 exists to prevent.

The counting is the other half, and it is prose because it is judgement:
`audit-implementation`'s retro reconciles each chafe line against the ledger, so
three sightings of one class become the number `3` rather than three unconnected
sentences in a 200-line log. `audit-readiness` reads the open entries while the
spec can still change, which is the only moment the knowledge is worth anything.

Case 69 in `bin/test-chunk-check.sh` (250). Mutation-tested three ways: deleting
the warning block, dropping the threshold to one sighting, and dropping the
open/landed discriminator each turn the suite red.

## 2026-08-04 — context packs: the chunk-time edit is a scratch capture

`audit-implementation`'s refresh rule tells the chunk that changed what a pack
describes to update that pack in the session holding the diff. It was written as
though the feature owns the pack. Often it does not: a pack may be generated and
maintained by a separate tool with its own review gate, and editing the live pack
directly bypasses that gate while nothing in the other tool's state records that
it happened.

Both `supply-chain-ops-assistant` chunks hit this (2026-08-04). Each found the
pack wrong rather than merely thin — chunk 02's action-safety reference claimed
"a new `ActionType` needs four registrations", true for a new action and wrong
for a new entity, which needed six plus a prefix. A pack that is confidently
wrong is worse than one with a hole, so the in-session repair is worth having.
What it is not is a durable write.

`references/feature-close.md` now names the full motion: **harvest** the
substance into the feature-close artifact, where release time can find it;
**restore** the live pack to what its owner last applied, running the pack's own
validator if it ships one; **hand off** the refresh that is now owed, saying what
it must fix that a hand-edit cannot — pinned permalinks and line ranges, since a
feature moves line numbers throughout the files a pack cites.

Restoring is frequently not byte-exact: a pack directory is often outside version
control, so there may be no baseline to diff against, and the applied-state
manifest this rule was earned on records hashes that match no live file. When the
restore is a reconstruction, the artifact says so. A reconstruction described as
a revert is a false claim about what is on disk.

## 2026-08-04 — `predict --one-pass`: a recovery that records instead of reconstructs

`predict` refuses a `predictions.md` filled in one pass, verdict included —
correctly, since that shape records a gate's outcome about a plan that did not
yet exist. But the refusal left exactly one route back to a stamp: blank the
verdict, stamp, restore it. That motion is byte-identical to what someone would
do to launder a prediction written *after* reading the plan, so the refusal
manufactured, as its own recovery, the act it exists to prevent — and the script
then had to take the reconstruction on trust, recording nothing.

Observed twice on `supply-chain-ops-assistant` (2026-08-04). Chunk
`01-inventory-patch-contract` paid the reconstruction and named it in its
field-log line as the harness's one real gap, with the fix already specified:
*"`predict` needs a recovery path for a one-pass fill that records what happened
instead of forcing a reconstruction the script must then take on trust."* Chunk
`02-adjust-inventory-action` hit it again the same day and built that.

`predict <dir> --one-pass` stamps the top half as it stands and records
`one_pass: true` plus `verdict_at_stamp`. Everything the stamp did prove it
still proves — the top half was filled at stamp time, and `freeze` still refuses
one that moved afterwards. What it drops is the ordering claim, which becomes
attested by the operator rather than observed by the script, and `freeze` and
`status` report that as its own tier rather than a clean pass. Three properties
keep it from becoming the habitual invocation: it is refused when the verdict is
still blank (the `--refreeze` principle — keep the honest case available and the
quiet one out of reach), the top-half hash binds exactly as on the strong path,
and the weaker claim lands in the record rather than in a comment.

Cases 68a–68e in `bin/test-chunk-check.sh` (223 → 241). All six new guarantees
were delete-a-check mutation-tested: the op-scope guard, the blank-verdict
refusal, both state fields, freeze's tier, and status's marker each turn the
suite red when removed.

## 2026-08-03 — remediating the first skill review

An independent review of the skill after the first full feature (2026-08-02)
found that all ten defects an independent whole-diff audit caught had shipped
through gate-approved chunks, and traced them to classes the lifecycle never
briefed against, lessons routed to the wrong stage, and one documented
integrity hole. The changes it earned:

- **The commit-preventer hook is a contract, not shipped content.** The README
  told a cloner to `cp hooks/chunk-no-commit.py` "from a clone of this
  repository," but `hooks/` was never tracked — the hook has always been
  user-level configuration living in `~/.claude/hooks/`, exactly as setup.md
  described. The README and references now say so, framing the hook the way
  feature-close already frames per-install mechanisms: the repository states
  the contract; each install wires its own.
- **Oracle-failure lessons routed to the stage that applies them.** plan.md's
  Track V gains a standing brief — the accumulated failure classes keyed on
  the oracle's *shape* (greps prose / suite lints tests / reads git state /
  deliverable is itself a check), not a flat checklist. The pre-freeze
  git-state calibration rule moved there from audit-implementation.md, which
  is read after the moment that can act on it. implement.md rule 8 no longer
  routes an in-flight oracle-bug fix through `block` (a detour `blocked`
  forces by cutting off `freeze --refreeze`); plan.md's Track P prices the
  oracle-run cadence to the chunk's shape.
- **`feature-close` named as the lifecycle's last stage**
  (references/feature-close.md): after the last chunk, before release, the
  cumulative diff gets one review by a reviewer that did not write the chunks,
  recorded as a repo artifact. A contract, not a tool — the mechanism is
  per-install, like the commit-preventer hook. Earned by the review itself:
  ten defects shipped through 24 frozen oracles and 24 human gates, and the
  independent whole-diff audit found them in minutes, because same-author
  oracles and a same-thread human cannot have uncorrelated blind spots with
  the implementation, and per-chunk scope discipline means no stage asserts
  the seams between chunks.
- **The demotion streak is computed, not hand-maintained.** `chunk-check.sh
  log` now derives the streak from the entries and prints it with every
  recorded line; the field-log header records only demotion events. The
  hand-maintained count went stale within days — 18 clean gated chunks under
  a header still reading "streak 0" — an instruction-to-remember at the heart
  of the one mechanism that adapts ceremony downward from data. Mutation-
  tested (case 67).
- **CANDIDATES.md**: maintainer-sized proposals get a queue in the versioned
  repo, seeded from the review's inventory, each entry citing field-log
  evidence by date and repo. The escalation rule the skill already followed
  implicitly is codified: second incident in a class → mechanism, in that
  session.
- **Two contracts stated honestly instead of aspirationally**: `chafe:` is
  one *record* (a parsing contract), not one sentence — overflow belongs in
  `retro.md` with a pointer; and `feature.md` queue rows are status plus a
  pointer, never a history (the script checks no markdown, so a fat row is
  unverified prose that reads as authority).
- **Portability pass over the feature's additions.** The evidence base is one
  repo and one operator, so rationale was checked against "would this
  sentence be true in a pytest repo?": the freeze_suite argument no longer
  borrows one feature's serialization constraint as if it were universal
  (the general fact: the chunk's own tests usually sit inside `suite_cmd`),
  and incident citations stay as worked examples rather than load-bearing
  premises. The operator-local field-log header gained the streak-pooling
  caveat: clean gates pooled across repos of different difficulty are not
  draws from one distribution.
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
