# plan — red oracle + cold-executable plan + human gate

Two tracks, both derived from `spec.md` **only**. **The validation must not see
the plan** — writing the oracle after, or from, the implementation design is
tuning the check on the answer key.

That guarantee is now structural rather than aspirational: Track V runs
**first**, in a subagent, so there is no plan for it to see. The converse —
that the plan must not see the validation — is **not** claimed, because it is
not true. Track P is written by the parent, which has read Track V's summary.
That is the lesser risk by a wide margin: a plan shaped to satisfy the tests is
a plan doing its job, whereas a test shaped to confirm the plan is a
contaminated oracle. Eliminating it would need a second isolated agent and a
reconciliation protocol between two contexts that cannot see each other —
disproportionate here. Stating half a guarantee accurately beats stating a
symmetric one that only holds in one direction.

## Preconditions

- Stage is `ready` (`chunk-check.sh status` to confirm; if picking up cold,
  run `audit-readiness` first — verify, don't trust). That is now safe at any
  stage: above `ready`, `readiness` is reconcile-only and writes nothing, so it
  can no longer move a baseline out from under a live freeze and void the scope
  guarantee. Re-pinning above `ready` requires `--rebaseline`, which clears the
  freeze and sends the chunk back through the plan gate.

## Context packs — which stage may see what

Read `feature.md`'s **Context packs** table before dispatching anything. Each
entry is classified `contract` or `implementation`, and the classification is
load-bearing:

- **Contract packs → Track V and Track P.** Domain vocabulary, external
  interfaces, invariants a user can observe, fixture and runner conventions.
  These make the oracle *better*: a test-writer who knows what the project's
  own verifier checks, and what its artifact contract promises, writes sharper
  acceptance assertions than one inferring it from a spec paragraph.
- **Implementation packs → Track P only.** Architecture, internal module
  layout, the mechanism behind a workflow, "how we usually build things here."

The reason is non-negotiable #1 arriving through a new door. A project-context
skill that describes *how the system is built* turns a black-box oracle into a
white-box one: tests that assert the internals the plan was always going to
choose. That is a contaminated oracle even though no plan leaked — the design
leaked instead, from a pack rather than a transcript.

The same split governs `audit-readiness`, which is the stage that *writes*
`spec.md` — so it inherits Track V's restriction, because `spec.md` is exactly
what Track V reads:

| Stage | contract | implementation |
|---|---|---|
| `audit-readiness` — gates the spec | load | **never** |
| `plan` → Track V — writes the oracle | load | **never** |
| `plan` → Track P — writes the plan | load | load |

Implementation context first becomes legal at Track P. Loading it any earlier
does not *defeat* the subagent boundary — Track V gets a fresh context either
way — it gets **past** it, carried in the spec that readiness just wrote. A
guarantee enforced by isolation is only ever as good as the artifacts allowed
to cross it.

The test, for a pack the table hasn't classified yet: **if this system were
rewritten from scratch a different way, would this still be true?** Yes →
contract. No → implementation. When it is genuinely both, split the pack or
name the specific sections Track V may load; a whole pack waved through because
most of it is contract is how the door opens.

Load by pointer — invoke the skill, read the file. Never inline a pack's
contents into `spec.md` or `plan.md`: on-demand context that has been pasted
into a frozen artifact stops being on-demand, and starts being paid for on
every read of that chunk forever.

## Track V — the oracle (runs first, in a subagent)

**Dispatch Track V before writing a line of Track P.** Sequencing makes
contamination impossible rather than merely discouraged: there is no plan yet
to leak. The subagent's context is `spec.md`, the repo, and the feature's
**contract** context packs — **not** `plan.md`, not the planning transcript,
not this session's reasoning about approach, and not the implementation packs.
Its Write access is limited to the spec's declared `test_paths`, plus
`state.json`'s `oracle_cmd`.

The subagent's brief:

1. Translate each acceptance criterion in `spec.md` into executable test
   code, black-box against the contract: assert observable behavior, not
   internals the plan might choose.
2. Place tests under the spec's declared `test_paths`, and **`git add` them** —
   the freeze hash-pins tracked files only, and an untracked file under
   `test_paths` fails the freeze.
3. **Set `oracle_cmd` in `state.json`**, narrowed to `test_paths`: the shell
   command that runs this chunk's tests and nothing else. It must equal
   `spec.md`'s `oracle` block — `freeze` reconciles the two and hard-fails on a
   mismatch, because the spec is what the human approved. If the declared
   command turns out to be wrong, that is a **spec change**: stop and surface,
   don't edit one side into agreement. Run it, so the red demonstration happens
   inside the isolated context that wrote the tests. `freeze` will execute it
   again, require a **non-zero** exit, and write the run to
   `<chunk-dir>/oracle-red.log`. A test that passes in that run, or an `ERROR`
   line (a collection or fixture failure — red for the wrong reason), fails the
   freeze by name. None of this is caught by eye any more; the calibration is
   executed.
4. Prose acceptance criteria survive only as comments above the assertions
   they became.

**What it returns:** the red run's output and a one-paragraph summary of what
it asserted — **not** the test source. The parent's window carries the minimum
needed to plan against, and the tests stay unread by the thing planning around
them for as long as possible.

## Track P — the plan

0. Load the feature's context packs — **both** kinds; Track P is the track
   that is allowed to know how the system is built.
1. Write `plan.md`: approach, ordered steps, exact files to touch (must be
   ⊆ the spec's declared scope — if planning reveals the scope was wrong,
   that's a spec change, stop and surface), risks, and explicit
   stop-and-surface triggers for the implementer.
2. Hold it to the **cold-executable standard**: an agent that has read
   nothing but `spec.md`, `plan.md`, and the red tests can execute it. If the
   plan needs narrative context from this session to make sense, it isn't
   done — or the chunk is too big, in which case go split it.
3. Exploration during planning may dispatch **read-only subagents**
   (`Read`/`Glob`/`Grep`, no write, no shell). Findings land in the plan, not
   in the window — the plan is the artifact that crosses the session
   boundary; the exploration texture dies here, by design.

If the two tracks disagree — the plan can't satisfy a test, or a test asserts
something the spec doesn't actually require — **stop and surface**. Do not
quietly adapt either track; reconciliation is a spec decision and spec
decisions belong to the human. On a spec change, re-derive both tracks.

## The plan gate — predict-then-compare

1. Before the human reads `plan.md`, they fill the blanks in
   `predictions.md`: expected approach, expected files, biggest risk. Written
   predictions are the anti-anchoring device — if you read the plan first,
   the gate has nothing to teach. The honesty is on the human; the file just
   makes honesty cheap. `freeze` refuses to run while any `___` remains, so an
   untouched template can no longer stand in for a gate that happened.
2. Human reads the plan and the red tests, notes disagreements with their
   predictions, and records two lines in `predictions.md`:
   `Verdict: approve | adjust | reject` and `Adjusted: y|n`. Disagreement
   between prediction and plan is signal, not ceremony — it's where wrong
   directions get caught at reading cost instead of implementation cost.
   `Adjusted:` exists because an adjusted-then-approved plan is the gate's
   *modal success*: without that line it logs as a clean approval and the catch
   disappears from the demotion estimator. Both lines are parsed by `freeze`
   and land in `state.json.gates`.
3. On **approve**: run `bin/chunk-check.sh freeze <chunk-dir>`. It is legal
   from stage `ready` only. It reconciles all four spec blocks against
   `state.json`, executes `oracle_cmd` and requires a non-zero exit (writing
   `oracle-red.log`), refuses any test that passed in that run and any
   collection `ERROR`, hash-pins every **tracked** file under `test_paths`,
   records the red node-ids it could parse, pins `plan_approved_sha`, and sets
   stage `approved`. The oracle is now frozen — and, unlike before, provably
   calibrated.
4. On **adjust**: apply the adjustment, re-run the red demonstration if tests
   changed, gate again — and set `Adjusted: y`, which survives the re-gate even
   though the final `Verdict:` becomes `approve`. `freeze` refuses an `adjust`
   verdict outright: it records approvals, not open questions.

   **If the chunk was already frozen** and the gate then adjusted the tests,
   re-freezing needs `bin/chunk-check.sh freeze <chunk-dir> --refreeze`. The
   flag exists because re-freezing replaces a pin a plan gate already approved:
   legitimate after an adjustment, and the same motion an implementer would use
   to launder an edited test back into the map. Requiring it to be asked for
   keeps the honest case available and the quiet one out of reach. From any
   stage past `approved`, freeze refuses outright — `readiness --rebaseline` is
   the route back, and it restarts the chunk rather than preserving its
   approval.
5. On **reject**: run `bin/chunk-check.sh block <chunk-dir> "<reason>"` —
   stage `blocked`, reason appended to `state.json`'s `blockers`. The retro
   will want to know why.

**Demotion rule:** the gate defaults on, and only data retires it — a gate
nobody ever acts on is theater, but you prove that with evidence, not
impatience. The authoritative statement of the rule, and the current streak,
live in the header of `~/.claude/feature-chunker-field-log.md`. Two copies of a
rule is one too many.

## Failure modes

- **Prose oracle.** A "validation plan" an agent later judges is a same-model
  reviewer at the bottom of the independence ladder. The runner is the
  validator; write code.
- **Green-at-birth tests.** An oracle you never calibrated is an oracle you
  cannot show detects absence. `freeze` now refuses one: any test reported
  `PASSED` in the red run, and any `ERROR` line in it, fails the freeze by
  name. This is a gate, not a warning to be careful.
- **Validation written from the plan.** Contaminated oracle; it will confirm
  the plan's assumptions, including the wrong ones.
- **An implementation pack handed to Track V.** The same contamination without
  a plan in sight: the oracle now asserts the architecture rather than the
  contract, and it will still be green after a refactor that broke the feature.
- **An ADR's decision arriving as an acceptance criterion.** The same
  contamination one stage further upstream, and the hardest to see: the
  criterion *was* traceable — it was just traced to an architecture decision.
  By the time Track V reads it the spec is already the contaminated artifact,
  and no isolation downstream of that can help. `spec.md`'s `Source:` lines are
  where it shows: an `implementation` document cited on a criterion is the
  defect, sitting in the one place a human reads before approving.
- **Freezing early.** Freeze at approval, not at first draft — the gate may
  adjust the tests, and re-freezing is cheap but forgetting to is not.
