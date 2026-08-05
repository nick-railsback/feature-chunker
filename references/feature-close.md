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
- **Context packs are harvested and then restored** — see below. This is the
  stage that hands pack maintenance back to whatever owns it.
- **Every chunk's field-log entry gets its `closed:` field resolved.** Each
  chunk in this feature was logged `closed:pending`; set it now to `clean` if
  the review found nothing against that chunk, or `defects(N)` for N findings
  attributable to it. Cite the artifact in the same edit.

  This is the only observation in the whole log written after the code has been
  read by someone who did not write it, and the demotion streak counts nothing
  else. Before it existed, a chunk's entry was final at its own review gate, so
  the 20th consecutive maximally-clean gated chunk was one that had shipped two
  regressions — and that was the chunk on which the demotion rule became
  eligible to fire. Resolving these is not bookkeeping; it is the entire input
  to the mechanism that decides how much ceremony to keep.

  Edit the log with Write or Edit, never a shell `>>` — the same constraint as
  the original append. One consequence to know rather than work around: each
  chunk's `state.json.field_log.line` still holds the pre-edit text, and is now
  stale. Nothing reads it after `gate approved` has stamped the chunk `done`,
  which is why this is named here instead of engineered around.

## Context packs: harvest, then restore

`audit-implementation`'s refresh rule tells the chunk that changed what a pack
describes to update that pack in the session holding the diff. That rule is
written as though the feature owns the pack. Often it does not: a pack may be
generated and maintained by a separate tool with its own review gate — the
`skill-engine` contextualizer flow (`DISCOVER`/`REFRESH` → `REVIEW` → `APPLY`)
is the case this was earned on. Editing the live pack directly bypasses that
gate, and nothing in the other tool's state records that it happened.

So the chunk-time edit is a **scratch capture, not a durable write**: valuable
because it is made while the diff is fresh and the reasoning is loaded, and
wrong to leave in place. Feature-close is where it is collected and undone.

1. **Harvest.** Diff each pack reference against what the owning tool last
   applied and fold the substance into the feature-close artifact — a section
   naming, per reference, what the feature made stale or false. This is the
   durable record, and it lives in the repo artifact where release time can
   find it, not inside a directory another tool will regenerate.
2. **Restore.** Revert every in-feature edit to the live pack, so the pack is
   again exactly what its owner last applied. Then run the pack's own validator
   if it ships one (`verify.sh` for a contextualizer) to confirm the restore
   left no dangling structure — a half-reverted cross-reference or table of
   contents entry is the failure mode here.
3. **Hand off.** State in the artifact which refresh is now owed and to whom
   (`/skill-engine:refresh <name>`, a colleague, a regeneration script). Say
   what the refresh must fix that a hand-edit *cannot* — pinned permalinks and
   line ranges are the usual answer, since a feature moves line numbers
   throughout the files a pack cites, and only a regeneration re-pins them.

**Restoring is not always byte-exact, and the artifact should say so when it
isn't.** A pack directory is frequently outside version control (a `.claude/`
tree is commonly gitignored), so there may be no baseline to diff against and
no way to prove the restore is exact. Its own applied-state manifest may not
help: the one this rule was earned on records per-file hashes that do not
correspond to the live files at all, so it detects nothing. When the restore is
a reconstruction, name it a reconstruction — the owning tool's next refresh
regenerates the content anyway, so an approximate restore is cheap, but a
reconstruction described as a revert is a false claim about what is on disk.

**Why not simply forbid the chunk-time edit?** Because the harvest is worth
having, and the moment to write it down is when the diff is in front of you.
Forbidding it moves the cost to feature-close, where whoever writes the artifact
has to re-derive from a cumulative diff what each chunk already knew. Allowing
it and reverting it keeps the information and returns the artifact. If the
install's packs are not owned by another tool, none of this applies — the
chunk-time edit is simply the update, and there is nothing to restore.

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
