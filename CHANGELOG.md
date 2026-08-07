# Changelog

This skill changes on field evidence only: an incident in a real feature run
becomes a failing case in `bin/test-chunk-check.sh`, then a mechanism or a
reference edit, in the session that earned it. Entries cite that evidence as
field-log entries `(date, repo)`. The field log itself is machine-local by
design (`templates/field-log.md` explains why it never travels with the
skill), so the citations here are the durable half of each story.

## 2026-08-07 — the first CI run found the install broken on Linux

The workflow added three entries below went red on its first execution, on the
leg that had never run. It was not a portability wrinkle in the suite, which is
what the entry predicted. It was the install command itself.

`rsync` does not create missing parent directories for its destination, and the
two rsyncs disagree about what that means: macOS's creates the whole path, GNU's
fails with "No such file or directory". So `rsync … ~/.claude/skills/feature-
chunker/` worked on the maintainer's machine and on the macOS runner, and
produced an **empty install** on ubuntu. The command was broken for precisely
the person it is written for — someone installing their first skill, on a
machine with no `~/.claude/skills` yet — and had been for as long as it existed,
in both documents, through the audit that read them and the remediation that
rewrote them. Three humans and one auditor read that line; the first machine to
*run* it found the bug in ninety seconds.

Both blocks now open with `mkdir -p ~/.claude/skills/feature-chunker`, and
`bin/test-docs.sh` asserts it stays. `--mkpath` would be tidier and needs rsync
3.2.3+, which is younger than plenty of installs.

The checker earned a second fix from the same failure: it ran the install with
output discarded, so the red CI log said only that the command "ran dirty" and
threw rsync's reason away. It now captures the output and prints it on failure.
A check that cannot say why it failed costs more than it saves — and this is the
repository that keeps arguing *where* it failed matters more than *whether*.

## 2026-08-07 — the script's two self-descriptions, held identical

`chunk-check.sh`'s line-3 usage comment listed eight ops. `usage()`, fifteen
lines below it, listed nine. `predict` landed on 2026-08-03 with the schema 9 →
10 migration and only `usage()` was updated (2026-08-05 audit, F7).

Trivial in effect — nothing reads the comment but a human, and the human who
calls the script wrong gets `usage()`'s correct list. Worth an entry for what it
demonstrates: the two lists sit eighteen lines apart in one file, which is as
close as two statements of a contract can be, and they still drifted for four
days. Proximity is not a comparator. `bin/test-docs.sh` extracts both lists and
asserts they are identical, which is the same answer this remediation reached
three other times today.

## 2026-08-07 — the streak-pooling caveat reaches the shipped seed

The 2026-08-03 entry records the operator-local field-log header gaining a
caveat: clean gates pooled across repos of different difficulty are not draws
from one distribution. It landed only there. `~/.claude/feature-chunker-field-
log.md` never travels — that is the design, and it is correct — so every install
since has stamped `templates/field-log.md` without the caveat, under the header
`references/setup.md` calls "the single authoritative copy" of the demotion
rule. The improvement went to the copy that cannot ship and not to the one that
does, which is the reverse of this repo's own canonical-flow rule.

It is now the third bullet under "worth not re-deriving later", and it argues
against the bullet above it: the n = 20 probability argument assumes twenty
draws from one process, and these are twenty draws from several, with no
randomization between them. The bias runs toward demoting — a stretch of
familiar work in a familiar repo accumulates the streak faster than the
arithmetic implies. Pooling is still the right call, because per-repo streaks
would never reach any n at all, but the number it produces is a prompt to look
rather than a result.

`bin/test-docs.sh` asserts the seed's demotion rule carries it. The
operator-local copy is not checked and should not be — it is machine-local
evidence, deliberately outside every repo. The shipped half is the half that
reaches new installs, and it was the half that was missing.

## 2026-08-07 — the one cheaply checkable number, measured instead of recalled

The README said the install was "sixteen files, ~150 KB". The 2026-08-05 audit
weighed it: 329 KB. The figure had been true before the fixture suite grew from
91 assertions to 273, and false ever since, in a document that stakes its
framework-comparison table on "numbers taken, not recalled".

The cost is not the number. It is that a reviewer who checks the single number
they *can* check finds it wrong, and then has no reason to extend credit to the
8.8–13.7× and 18–32× figures beside it, which nothing in the repository lets
them verify. One stale measurement discredits every honest one next to it.

`bin/test-docs.sh` now measures it: it runs the documented install command,
counts the files and weighs the bytes, and holds the README's sentence to the
result — 18 files, ~356 KB today, both moved by this remediation. The file count
is exact. The size is held to ±10 KB, which is what the "~" is worth: gating on
the byte would redden CI on every script edit and teach people to bump the
number without reading it, which is how a number stops being a measurement in
the first place.

## 2026-08-07 — the README summarises and links where it used to restate

Fixing the three divergences below treated instances. This treats the source.
The README carried second copies of SKILL.md's state tree and of every op's full
refusal contract, with no comparator between them — and the repository has a
demonstrated rate for that: two dedicated resync commits in two days, with three
divergences surviving both. Its own rule, from `references/plan.md`: "Two copies
of a rule is one too many."

The state tree is now drawn once, in SKILL.md, and the README links to it,
keeping only the part that is genuinely README-shaped — that the tree lives in
the working directory whether or not it is committed, and why a write under `~/`
is the silent-failure shape. The op table stays, because a table showing that
every guarantee is a refusal in executed code is the README's argument, but each
row is now one summarising line and the full contracts link to
SKILL.md § The deterministic backstop.

A summary that links cannot drift out of step with what it summarises. A second
copy always can — which is the same reasoning as `spec_cmp` hard-failing on
`spec.md`-versus-`state.json` divergence in either direction, applied at last to
the prose. The data half of this repo has never drifted; the prose half drifted
three ways in four days. The difference was the comparator.

`bin/test-docs.sh` counts the tree: drawn once in SKILL.md, zero times in the
README. It also asserts the repository-layout diagram names every script under
`bin/` — it listed two of three, having gone stale the moment `test-docs.sh`
was added by the entry two below this one. A layout diagram that silently omits
a file is the install command's failure class in a different costume.

## 2026-08-07 — three contracts the README stated without their exceptions

The README restates SKILL.md's non-negotiables and op semantics in parallel
prose, and the copies had drifted three ways. All three survived two dedicated
"bring the README in step" commits in two days (`22172db`, `91891a6`), which is
the argument for a comparator rather than a third resync.

**#7 dropped `--downgrade`.** It said `bypass` "refuses from any stage past
`ready`" flat, while the README's own op table eighteen lines later documented
`--downgrade` as the exit from exactly that. A reader who stopped at the
non-negotiable concluded a mis-sized frozen chunk had no way out, when the
correction is the designed one.

**#6 dropped the 2026-07-31 softening.** It presented predict-then-compare
unqualified after blind predictions had been narrowed to `standard` chunks.

**SKILL.md's `audit-readiness` row was stale in the other direction.** It told
the operator to run the suite by hand before `bypass`; the 2026-08-02 change
made `bypass` run `suite_cmd` itself and record the exit code in
`bypass_suite`, specifically so it would stop being a step someone was told to
remember. The routing surface was still asking for the manual motion.

All three are now checked in `bin/test-docs.sh` — as presence of the
qualification, never as matching prose. The two documents are deliberately
different lengths, and a text comparison would be a style gate, which is the
kind people learn to route around. What the checks refuse is one document
stating a rule while the other states its exception.

## 2026-08-07 — the checks run on push, not on remembering

There was no CI. The 278-assertion fixture suite ran when someone typed `bash
bin/test-chunk-check.sh`, and the delete-the-check mutation trial ran when
someone read the suite header describing it. Both were prose asking to be
remembered, in the repository whose entire argument is that prose asking to be
remembered is not a mechanism — structurally the same as the field-log append
that sat unwired for months. Named by the 2026-08-05 audit (F3), which is also
the audit that found two live defects a green suite had been keeping quiet.

`.github/workflows/checks.yml` runs both suites and shellcheck on every push and
pull request. Three things about how it is pitched:

**Both suites run even when the first goes red** (`if: ${{ !cancelled() }}`).
*Where* it failed is the distinction this repo keeps insisting matters more than
*whether* — a run that stops at the first failure returns a partial answer, and
the next push starts from that partial answer.

**Two runners.** The maintainer develops on macOS, so ubuntu is the leg covering
the platform nothing was ever tested on, and the pair is what holds the suite to
its own claim of running "anywhere git and jq do". `fail-fast: false`, because a
one-platform failure is the interesting one and cancelling the other leg hides
which platform it was.

**shellcheck gates at `--severity=warning`.** Both scripts carry info-level
findings deliberately: SC2016 fires on every single-quoted jq filter, where
non-expansion is the entire point, and SC2015 on the `[ test ] && pass || fail`
idiom used throughout. Gating on info would mean papering over real advice with
disable directives, or rewriting correct code to please a linter. A gate people
route around is worse than one pitched where it can hold.

`bin/test-docs.sh` now asserts that every `bin/test-*.sh` appears in the
workflow. Adding a checker and wiring it into nothing is precisely the failure
this entry is about, and it would otherwise be silent — the same silence F2 was.

**Not yet verified on Linux.** The workflow parses, and every command in it
passes on macOS, but the ubuntu leg has never run: no container was available to
rehearse it locally. The first push is the first evidence. If it goes red, the
thing to expect is BSD-versus-GNU divergence in `awk`, `sed`, `sort` or `ls`,
not a real defect in the checks.

## 2026-08-07 — one install command, and it ships the ledger

There were two documented install commands with two different results. The
README's excluded `CANDIDATES.md`; `references/setup.md`'s shipped it, along
with four repo-only files. `chunk-check.sh` resolves the ledger relative to the
installed script, and `candidates_overdue` opens with `[ -f "$1" ] || return 0`
— correct behaviour, and indistinguishable from an empty backlog. So every
install made from the README had the escalation warning wired to a file that was
not there, and nothing said so. That mechanism was built on 2026-08-04 in
response to an entry that sat "overdue" at three sightings while the class it
described shipped two regressions; it has not been able to fire in a documented
install since the day it was written.

It was invisible in the one environment that exercised it. The maintainer's
install at `~/.claude/skills/feature-chunker/` is a git clone — it carries
`CANDIDATES.md` because it carries everything — so it followed neither command
and could not show the difference.

Both documents now state one command, and it **names what ships instead of
excluding what does not**. That half is not cosmetic. An exclude list is a
denylist, so the README's "and nothing else" sentence decayed every time
anything appeared at the repo root without anyone editing the sentence: by
2026-08-07 the command shipped a `.claude/` directory and a stray untracked
`docs/` tree while still claiming otherwise. A denylist cannot hold a "nothing
else" claim; only an allowlist can.

**`bin/test-docs.sh` is new** — the reconciliation this repo had for its data
and not for its prose. It extracts the install block from both documents,
asserts they are byte-identical, runs the README's verbatim with `HOME`
redirected at a scratch dir, and compares the resulting tree against the
sentence that describes it. The documentation is the subject rather than a
paraphrase of it: restating the command inside the checker would have been a
third copy of the contract, drifting the way the first two did.

Case 69b in `bin/test-chunk-check.sh` pins the resolution itself. All nine of
case 69's assertions override `CHUNK_CHECK_CANDIDATES`, so the `SKILL_ROOT`
branch every real install takes had no case at all — and this suite runs from
the repo, where the ledger is always present, which is exactly how the breakage
stayed green. 69b runs `log` from a scratch skill root instead. Mutation-tested:
deleting the `SKILL_ROOT` default leaves all nine of case 69's assertions
passing and reddens only 69b. Its second half asserts the *silence* when the
ledger is absent, which is what makes the install checks load-bearing rather
than decorative — nothing else would notice the mechanism gone.

## 2026-08-07 — the green-at-birth refusal, hoisted the way the ERROR check was

The 2026-08-04 entry below hoisted the collection-ERROR check out of the
node-id-capture branch. The `PASSED` scan six lines further down was left where
it was. A codebase health audit reproduced the consequence live (2026-08-05):
an oracle printing `PASSED tests/chunk/t.py::test_a`, `PASSED …::test_b` and
exiting 1 — a wrapper whose trailing non-test step fails, or a runner exiting
non-zero for a non-assertion reason — reached `stage=approved`. Both tests were
green before the feature existed, so the oracle asserted nothing about the
feature's absence, and `freeze` certified it as calibrated anyway. That is the
precise failure non-negotiable #1 exists to refuse.

The mechanism is the same as the ERROR case and so is the reason it hid.
`red_ids` is built from `FAILED` and `ERROR` only, so a run where every
reporting test passed parsed no red ids, took the `else` branch, and was never
inspected. Case 26 could not reach the shape: `birth.sh` always leaves a
`FAILED` id behind, which is exactly what made the branch reachable and the hole
invisible — the "passes for the wrong reason" class again, found this time in
the remediation for the previous instance of itself.

The `PASSED` scan now runs unconditionally, before the id capture. The
exit-code-tier warning that fired in this shape was false in the bargain — it
announced "no per-test node-ids in the oracle output" with two node-ids printed
directly above it — so it now speaks to the absence of *red* ids when ids
parsed, and keeps its original wording only when none did. Absence of red ids is
not absence of ids, and the difference is the evidence tier.

Case 26b in `bin/test-chunk-check.sh`, on a new `allpass.sh` fixture oracle.
Mutation-tested twice: re-nesting the scan reddens all five of 26b's assertions,
and dropping only the warning's new branch reddens exactly the one that names
it. One of 26b's assertions was itself written wrong first — matching the bare
node-id, which the oracle echoes into the same captured output, so it passed
against the unfixed script; it now matches with the refusal's own indent. Case
21's tracked-oracle count moved 6 → 7 with the new fixture script.

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

## 2026-08-04 — a missing feature-close becomes something the harness says

`feature-close` was prose and optional by omission. It was also the only stage
that caught anything on the feature this remediation comes from: two instrumented
gates, 78 oracle assertions across two chunks and a 295-test CI-equivalent suite
found **none** of seven correctness defects that one independent reviewer found
in one pass. A stage with that record should not be reachable only by remembering
it exists.

When `gate approved` finds no unfinished chunk directory left under the feature,
it now prints that a feature-close is owed, what it is, who may do it, and that
it is what resolves every `closed:pending` in the field log. That is the last
moment anything in the harness prints about the feature, which makes it the only
place the absence can be named.

It does not attempt to detect whether the review happened. Probing for a
`docs/audits/` artifact would mean parsing `feature.md` for a path, and
`chunk-check.sh` parses no markdown beyond `spec.md`'s fenced blocks and the
field log — a design property worth more than a guess would be. The line also
says outright that nothing checks it, because a reminder that implies enforcement
it does not have is worse than silence. What changed is that skipping the stage
is now a decision rather than an omission.

Case 58b2 in `bin/test-chunk-check.sh` (267 → 273), including the negative half:
a gate with a next chunk still queued must not print it, since a reminder that
fires every chunk is one nobody reads. Mutation-tested by deleting the lines.

## 2026-08-04 — the demotion streak counts shipped quality, not gate verdicts

The streak was wrong in both directions at once, which means it was not a
quality measure at all — and it had just reached n=20, the threshold at which
the demotion rule becomes eligible to retire the plan gate.

**It overcounted the chunk.** The 20th consecutive clean gated chunk logged
`gate:approve · oracle-caught:n(0) · freeze-trip:n · scope-dev:n ·
ceremony-ok:y` — as clean as an entry gets — and had shipped two regressions,
one of which executed an unattended inventory-zeroing path. Nothing in the entry
is written after the code is exercised by anyone but its author, so nothing
could have said so.

**It undercounts the gate.** On that same chunk, the plan gate prevented a real
shippable defect (an id-width trap that passes all 51 frozen tests and fails the
repo's own fixtures) via plan prose — no `adjust`, no red→green iteration. A
gate that catches something that way is indistinguishable from a gate that did
nothing, and it pushes the streak *toward* retiring itself.

Both halves get treated, differently, because only one is mechanisable.

The undercount is named rather than fixed: the log header now says plainly that
the number measures **"did the human change the plan at the gate"** — a
reasonable proxy for "is the gate changing outcomes" and no proxy whatsoever for
"is the work good." A plan that was right the first time *because* the gate
forced the analysis leaves the same trace as one that was right by luck, and no
field can separate them.

The overcount is fixed. Entries carry `closed:pending|clean|defects(N)`, placed
before `context:` (it has to precede `chafe:`, which is last and free text and
is where the parser stops). `audit-implementation` writes `pending` and `log`
*requires* it — optional-by-omission is precisely how the streak came to count
unreviewed chunks. `feature-close` resolves it. `field_log_streak` counts only
`closed:clean`; `defects(N)` resets alongside `adjust`/`reject`; `pending` and
absent are unknowns that neither extend nor reset.

**The honest cost, since it is a real one:** no existing entry has the field, so
the streak reads `0` the day this lands and stays near zero until features start
closing. That retires a 20-chunk streak by assertion rather than by evidence.
It is the right trade only because of what the streak turned out to be measuring
— but it is a reset, and the log header records it as one rather than letting
the number quietly restart.

Cases 67b and 67c in `bin/test-chunk-check.sh` (260 → 267). Mutation-tested
three ways: dropping the `closed:` requirement, making `defects` stop resetting,
and letting any outcome extend the streak each turn the suite red.

## 2026-08-04 — exclusions get checked, because nothing else checks them

Non-negotiable #1 puts an executable oracle behind every acceptance criterion.
Exclusions get nothing — and an exclusion decides what *never gets built*, which
is where a wrong belief is most expensive and least visible.

A spec excluded a whole defect class on this reasoning: the new action type
"inherits this from every existing action type; it is pre-existing behaviour."
False in the way that mattered. The two sibling action types each inject a field
at dispatch, so neither is ever a no-op; the new one injects nothing, making it
the only action whose path is a pure no-op that still reports success. The
exclusion was reasoned from a false premise, and no part of the harness could
have noticed (2026-08-04, supply-chain-ops-assistant, chunks 01 and 02).

`readiness` now reads `## Out of scope` and hard-fails on an entry asserting
something about existing behaviour — *already, pre-existing, inherits, inherited
from, unchanged from, existing behaviour* — unless it cites a test in backticks
or marks itself `(unverified)`. Entries are bullets and paragraphs rather than
lines, so a citation on the second line of a wrapped bullet counts and one in
the *next* bullet does not.

**It fails rather than warns, and the reason is the escape hatch.** The check
cannot know whether a claim is true. It requires the claim to be *marked*, which
makes the fix one word — and where the honest fix is that cheap, a warning would
only accumulate.

Two notes on getting it right, both earned during the change itself. The rule
belongs in `templates/spec.md`, which puts explanatory prose *inside the section
the checker scans* — the shipped template would trip its own check, or quietly
satisfy it. Guidance is now an HTML comment and the checker skips comments,
which is honest anyway: a comment is not an exclusion. And the first version of
the test for that skip quoted the rule verbatim, marker included, so it passed
whether or not comments were skipped. The delete-the-check trial caught it; the
fixture now carries a claim phrase and neither escape hatch. Both are the
skill-engine 19 class — a check whose own source contains what it looks for.

Cases 70a–70g in `bin/test-chunk-check.sh` (250 → 260). Mutation-tested five
ways: removing the call, either escape hatch, the bullet-level entry split, and
the comment skip each turn the suite red.

## 2026-08-04 — two things a binary criterion is structurally bad at

Both land as sub-rules under the spec gate's two *judgement* bullets rather than
as new peer bullets. That file argues, correctly, that five bullets reading as
equally enforced when only three are is the drift the harness exists to remove;
adding two more unenforced ones would have made the argument and broken it in
the same edit.

**Enumerated sides are checkable only against themselves.** A criterion read
"handles `INV-` targets on **both** sides, the validator and the dispatcher."
There were three. The risk floor was the third, it was in no enumeration, and
nothing in spec, plan or oracle ever asked about it — both named sides were
wired correctly, the criterion was satisfied exactly as written, and the outcome
was an unattended mutation path. A criterion quantifying over sides now states
the invariant as an *outcome* and lists the sides as explicitly non-exhaustive
examples. That is not a wording preference: under the old phrasing, a Track V
that went looking at an unnamed third side would have read as exceeding the spec
rather than fulfilling it.

**Binary criteria are blind to reviewability.** "The targets are exactly the
rows carrying an inventory id" was satisfied precisely — and the gate it fed was
unusable, because 50 targets rendered as 50 opaque ids with no surface showing
the human-meaningful field. The feature's stated goal named "a human
confirmation gate" as its core safety property, and no criterion asked whether a
human could exercise it. When a goal names a human control, at least one
criterion is now about the information available *at* that control, not only the
correctness of what reaches it.

Earned 2026-08-04, supply-chain-ops-assistant 02-adjust-inventory-action.

## 2026-08-04 — two oracle classes from one defect the oracle already ran

The worst defect this harness has shipped was executed by its own oracle, in a
test written correctly, blind, from the spec. Two classes come out of it, both
two paragraphs of Track V brief, and between them they cover it twice.

**A bypass-flag test needs a no-flag sibling.** A test named for the property
"what the validator admits is what the dispatcher routes" drove exactly the path
that became unguarded — and passed `confirmed=True` to get there, because
otherwise the confirmation gate stopped it. The flag that let the test reach its
assertion is the flag that made the defect invisible. Any test passing
`confirmed=`, `force=`, `skip_validation=` or an equivalent has, by
construction, blinded itself to whatever that flag disables; it now owes a
sibling asserting the control fires when the flag is absent.

**A semantic class needs its mechanisms enumerated.** The criterion said "no
inventory adjustment grades `low`" — semantic. The code keyed on
`action_type in {…, ADJUST_INVENTORY}` — syntactic. All 15 parametrized cases
constructed proposals with that enum member, so the oracle asserted the narrower
set, and a bulk update carrying an inventory target — an inventory adjustment by
any reading of the criterion, and not an `ADJUST_INVENTORY` — went through
unattended.

That second one is the uncomfortable half, because the control that should have
caught it is the blind oracle. Track V wrote those tests from `spec.md` with no
plan in context, exactly as designed. **Blindness protects against anchoring on
the plan, not against anchoring on the type system** — the author still reached
for the codebase's enum to express a claim the spec had made about a class of
behavior. So: enumerate the mechanisms that can produce a member of the class
before writing the test. If the class is expressible only by naming one enum
member, the code and the spec disagree about what the class is, and that
disagreement is the finding.

Earned 2026-08-04, supply-chain-ops-assistant 02-adjust-inventory-action.

## 2026-08-04 — who else reads this symbol? (the seam sweep, finally)

The oldest open entry in `CANDIDATES.md`, closed on its fourth sighting — the
one that shipped a regression.

A chunk widened a shared module-global entity-id regex so it would match a new
entity prefix. Its scope discipline was perfect: four files, exactly the declared
paths, no creep, `verify` clean. All 13 acceptance criteria concerned the new
entity. All 51 oracle assertions concerned the new entity. Four other action
types read that same regex, and the widened match silently emptied their target
lists — a query naming an inventory id returned no shipments where the same
query without it returned two.

The sentence this earns: **declared scope governs which files may change, never
which behaviors must be preserved.** Scope makes a diff reviewable. It says
nothing about blast radius. The harness had been asking one of those questions
and reading the answer as though it covered both. Do not fix this by loosening
scope — scope discipline was the part that worked.

Two changes, both human judgement and marked as such. `audit-readiness` § step 3
names the consumers of every shared symbol the declared scope touches, and asks
what would break for them if its meaning widened. `plan.md` § The standing brief
gains a fifth class: an oracle for such a chunk carries at least one
*preservation* assertion per consumer class — not "the new behavior is right"
but "what was true for the existing callers still is." That is the one assertion
a spec-shaped blind spot cannot delete, because it is not derived from what the
chunk is adding.

**Why not a check.** A fifth fenced `consumers` block in `spec.md`, reconciled
like the other four, was considered and rejected: it can verify the list was
filled in, never that it is complete, and a consumer nobody thought of is what
produced all four sightings. `CANDIDATES.md` records the rejection with its
reasoning. This fix is a prediction rather than a guard, by this skill's own
standard — what changed is that occurrence five will announce itself at every
chunk close instead of waiting to be re-read.

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
