# feature-close — independent review of the cumulative diff

The lifecycle's last stage, and the only one that runs once per feature
rather than once per chunk: after the last chunk's review gate, before the
feature is released or merged, the cumulative diff gets one review by a
reviewer that did not write the chunks.

## Why per-chunk green cannot stand in for it

Two structural gaps, both measured on the first full feature this skill ran —
24 chunks, every oracle frozen and red-calibrated, every review gate passed,
and ten real defects still shipped, found afterward in minutes by one
independent whole-diff review:

- **The independence ladder.** A same-author oracle and a same-thread human
  review buy real things — executable validation, anti-anchoring, scope
  enforcement — but uncorrelated blind spots are not one of them: the oracle
  was derived from the same spec by the same author, and the human read the
  code in the same conversation that produced it. A reviewer that did not
  write the chunks sits on a different rung, and its misses are uncorrelated
  with the author's. That is a property no amount of per-chunk ceremony can
  reach, because it is about *who is looking*, not how carefully.
- **Seam blindness.** Per-chunk scope discipline actively narrows attention:
  each gate examines one chunk's diff against one chunk's declared scope, and
  no stage asserts anything about the union. What ships through that gap is
  exactly what no single chunk owns — a consumer outside every chunk's scope,
  a contract two specs each half-assumed, a check whose glob covers the tree
  it was written in and not the tree that uses it. Three of the ten defects
  above were one glob pattern short in precisely this way.

## The contract

- **When:** after the last chunk reaches `done`, before release.
- **Who:** anyone or anything that did not write the chunks. The mechanism is
  per-install, the same pattern as the commit-preventer hook: a code-review
  workflow, a colleague, an agent with a fresh context and none of the
  feature's transcripts. Independence from the author is what makes it count
  — the tool is whatever the install has.
- **What:** the cumulative diff, first chunk's baseline to last chunk's gate,
  read as one change. The reviewer's questions are the ones per-chunk gates
  structurally cannot ask: do the seams between chunks hold, does every
  checker actually fail on what it forbids, who else consumes what this
  feature changed.
- **Recorded as an artifact in the repo** — one file, findings cited by path
  and line, the `docs/audits/` shape. An answer living in chat scrollback
  does not exist next session (non-negotiable #3), and the artifact is also
  what release time can look for.
- **Findings feed a findings-remediation workflow**, worked test-first with
  one commit per finding — `tdd-remediation` is the example shape, not a
  dependency. What matters is that findings become tracked work rather than
  a read-once report.

## What this stage is not

- Not a re-run of the per-chunk gates — nothing here re-executes oracles or
  re-opens `done` chunks. Defects it finds are new work.
- Not a script-enforced gate. `chunk-check.sh` is per-chunk by design and
  reads no feature-level state, so this contract is prose — the one kind of
  guarantee this skill treats with suspicion, kept prose deliberately because
  the mechanism differs per install and the stage runs once per feature. The
  honest consequence is stated rather than hidden: skipping feature-close is
  a decision someone can see was made (no `docs/audits/` artifact for the
  feature), not an accident nothing records.
