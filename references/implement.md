# implement — execute the plan to green, hands off the oracle

The implementer's contract: everything needed is in `spec.md`, `plan.md`, and
the red tests. If it isn't, that's a finding about the plan, not a license to
improvise.

## Preconditions

- Stage is `approved` (`chunk-check.sh status`).
- **Pickup in a fresh session:** re-verify before building — confirm the
  branch, confirm `plan_approved_sha` is an ancestor of HEAD, and run the
  frozen oracle exactly as the harness does:
  `PYTEST_ADDOPTS=-rA bash -c "$(jq -r .oracle_cmd state.json)"` — it must
  still be red, and red for the right reason. Expected state at `approved` is:
  baseline suite green *except* this chunk's new tests. Anything else means
  the world moved since approval — stop and surface.
- Session choice is operational, not architectural: `small` chunks may
  implement in the same session as the plan; `standard` chunks get a fresh
  window. The checkpoints make both identical.

## Rules

1. **Never touch the oracle.** No edits to any file under `test_paths` — not
   fixes, not "improvements," not additions. If a test is wrong, **stop and
   surface**: it goes back through the plan gate as an adjustment, because a
   test change is a contract change. (The hash pin will catch you anyway;
   the rule exists so it never has to.)
2. **Stay inside declared scope.** Touch only the files `plan.md` names.
   Minor in-scope deviation from the plan's *steps* is fine — log it in
   `plan.md`'s Deviations section and in `state.json`'s `deviations` array.
   Needing a file outside declared scope is a **stop-and-surface**: human
   acks the scope change (recorded in spec + state) or the plan was wrong.
   A scope change means editing **both** `spec.md`'s `scope` block and
   `state.json`'s `scope_paths` — they are reconciled, and changing one alone
   fails the next check rather than silently widening what verify allows.

   Three things outside `scope_paths` are allowed without ceremony: the
   chunk's own directory, `test_paths`, and the feature's `feature.md` — the
   chunk queue is meant to be kept current, so updating it is not scope creep.
   A **sibling chunk's** directory is not on that list. Stamping `02-y` while
   `01-x` is in flight puts another review's diff inside this one; do it after
   the gate.
3. **Iterate to green.** Run the suite as you go; count red→green iterations
   honestly — the retro wants that number (it's the cheapest measure of how
   much the oracle actually worked).
4. **No commits.** Ever. The human commits after review. This is not a style
   preference; review-before-commit is the outer gate and auto-commit
   deletes it. `verify` now fails when commits exist since baseline and
   `gates.review` is not `approved`. That is a detector at verify time, not a
   preventer at commit time — the preventer is an optional `PreToolUse` hook
   (`hooks/chunk-no-commit.py`); without it, an agent that never runs
   `verify` never meets this check.
5. **No drive-by fixes.** Adjacent broken things you notice go in the
   handoff note as candidate chunks, not in this diff. One chunk, one
   diff, one review.
6. **New files need `git add` before the oracle can see them as tracked.**
   An oracle check that walks `git ls-files` (e.g. "does `references/`
   contain a tracked Markdown file") does not see a file that only exists on
   disk — it will read as absent even though `ls` shows it. Stage new files
   with `git add` (never commit) as you create them if the plan's criteria
   depend on git-tracked state; don't wait until the run before `verify` to
   discover this. Added 2026-07-30 after skill-engine chunk 11 lost an
   iteration to this on a from-scratch file split whose oracle asserted
   tracked-ness through the repo's own doctrine script.
7. **A regex-based in-body check can fail on a line wrap, not just on
   content.** `grep -qiE` (no `-z`) matches within a single line only. If a
   check greps for a multi-word phrase (e.g. "no write ... no shell") and
   your hand-typed prose happens to wrap the editor's line between two of
   those words, the check fails even though the words are all present and a
   human reading the file would say the rule is clearly stated. After typing
   prose meant to satisfy a specific grep, re-run the check itself — don't
   eyeball the rendered text — and if it fails on a line-wrap technicality,
   reflow the sentence rather than assume the wording is wrong. Added
   2026-07-30 after skill-engine chunk 11 lost an iteration to this exact
   trap.
8. **A frozen oracle can have a bug that only surfaces once implementation is
   otherwise complete — and by then, a normal `freeze --refreeze` can't prove
   the fix isn't vacuous.** Rule 1 still holds: never edit the oracle to make
   it pass. Stop and surface — **in conversation, not with `chunk-check.sh
   block`**: the chunk stays `approved`, which is the one stage
   `freeze --refreeze` is legal from. `block` marks work that is genuinely
   stopping, and an oracle fix being approved in the same breath it was found
   is not stopped work — `blocked` also cuts off `--refreeze`, forcing a
   `readiness`-then-`freeze` detour that re-runs the whole readiness gate to
   undo a stage transition nothing needed (2026-08-02, skill-engine 23; the
   three earlier oracle-bug chunks — 14, 15, 19 — stayed `approved` and
   re-froze directly). Get the fix approved
   like any other plan-gate adjustment, then re-freeze it — but `freeze`'s
   non-negotiable-1 check requires `oracle_cmd` to exit non-zero
   unconditionally, including under `--refreeze`. If implementation is done,
   the *fixed* oracle is usually fully green, and a normal freeze rejects that
   green run outright ("a green oracle was never calibrated"), regardless of
   how real the fix is. Forcing the check through `readiness --rebaseline`
   (a full plan-gate restart) is disproportionate to a one-line test fix.
   Instead: temporarily add a throwaway file elsewhere in the tree (never
   `git add`ed) that reintroduces the exact condition the fixed check is
   supposed to catch, confirm the oracle goes red **only** on that one
   assertion, run `freeze` while it's present (genuine, non-vacuous
   red-evidence gets pinned), then delete the scratch file and confirm the
   oracle is green before `verify`. This mirrors the technique an oracle often
   already uses internally (synthetic fixtures for a check that can't safely
   be demonstrated against the real repo) one level up, applied to freeze's
   own red-requirement instead of to the check itself. Added 2026-07-31 after
   skill-engine chunk 19's oracle turned out to grep its own source for the
   string it was checking for absence of, discovered only after all 8 real
   implementation files were already correct.

## Exit

The session ends when the human's arrival needs nothing but the human. The
system notification that fires when this session stops is the signal to come
review — so everything mechanical that review depends on happens now, not at
the arrival (one-arrival cadence: SKILL.md § Cadence).

1. Suite green, including the previously-red chunk tests.
2. Run `bin/chunk-check.sh verify <chunk-dir>` — oracle unchanged, diff
   within scope, suite green. Fix any failure *within these rules* before
   handing off; an implementer handing off a failed verify is handing off
   its own unfinished work.
3. Write a short handoff note at the bottom of `plan.md`: what was built,
   deviations taken, anything observed for the retro.
4. Assemble the review packet and pre-fill the retro
   (`references/audit-implementation.md` Half 1 step 2 and Half 2): every
   observation derivable from the run — iteration counts, gate verdicts, scope
   deviations — filled now, so the arrival asks the human only for the two
   answers that are theirs (`ceremony-ok`, `chafe`) and the verdict.
5. Draft ahead: if the queue has a next chunk, draft its plan per
   `references/plan.md` § Draft-ahead — spec gating and the Track V sketch in
   fresh-context subagents, Track P in this window, open decisions queued in
   the draft's `## Questions` section. Skip in `tracked` artifacts mode (the
   draft would land inside this chunk's scope check) and say so in the packet.

## Failure modes

- **Weakening a test to pass.** The canonical reward hack — satisfying the
  check without satisfying the user. The freeze exists because this failure
  is attractive precisely when you're closest to done.
- **Silent scope creep.** "It was easier to also change X" is how a
  reviewable diff becomes an unreviewable one.
- **Trusting the approval-time world.** The plan was approved against a SHA.
  If you skipped the pickup re-verify and the repo moved, you're building on
  assumptions nobody checked.
