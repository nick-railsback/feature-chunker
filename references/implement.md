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

## Exit

1. Suite green, including the previously-red chunk tests.
2. Run `bin/chunk-check.sh verify <chunk-dir>` — oracle unchanged, diff
   within scope, suite green. Fix any failure *within these rules* before
   handing off; an implementer handing off a failed verify is handing off
   its own unfinished work.
3. Write a short handoff note at the bottom of `plan.md`: what was built,
   deviations taken, anything observed for the retro.

## Failure modes

- **Weakening a test to pass.** The canonical reward hack — satisfying the
  check without satisfying the user. The freeze exists because this failure
  is attractive precisely when you're closest to done.
- **Silent scope creep.** "It was easier to also change X" is how a
  reviewable diff becomes an unreviewable one.
- **Trusting the approval-time world.** The plan was approved against a SHA.
  If you skipped the pickup re-verify and the repo moved, you're building on
  assumptions nobody checked.
