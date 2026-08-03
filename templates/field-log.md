# feature-chunker field log

One line per chunk, appended by `audit-implementation`, across all projects.
This log is the evidence base for changing the skill: incidents become edits to
the references in the session that earned them.

**Where this file belongs:** `~/.claude/feature-chunker-field-log.md` — the
`~/.claude` root, *not* inside `skills/feature-chunker/`. Re-installing or
re-exporting the skill therefore cannot overwrite the accumulated evidence.
This copy in `templates/` is the seed: stamp it to that absolute path if the
log does not exist yet, and never the other way round.

The cost of that choice, stated plainly: **the log does not travel with the
skill.** Copying `skills/feature-chunker/` to another machine carries an empty
evidence base and the demotion streak does not come along. That is the right
trade — this is machine-local evidence about how *this* operator's gates
behave. A streak of twenty clean gates here says nothing about a different
operator on a different repo, so carrying it across would import a conclusion
its own dataset cannot support. The skill directory stays purely the thing you
ship; this log stays purely the thing you learn from.

**Append with Write or Edit, not a shell `>>`.** The Bash sandbox denies writes
under `~/.claude`, and a denied append that looks like it worked is exactly how
a log silently stops being kept.

**Entries are machine-checked.** `chunk-check.sh log <chunk-dir>` reads this
file, finds the line whose first three fields are the date, the repo and the
chunk, and records it in `state.json`. `chunk-check.sh gate <chunk-dir>
approved` re-reads this file and refuses to stamp `done` if that line is not
still here. So the format below is load-bearing rather than decorative: the
first three fields are parsed, `gate:` must carry a legal verdict because the
demotion rule reads it, and no field may be left as `?`.

## Demotion rule

The plan gate defaults on. It may auto-pass for `small` chunks only when the
**last 20 consecutive gated chunks** in this log show **zero `adjust` and
zero `reject`** — twenty consecutive chunks in which the gate never changed
an outcome. `standard` chunks always gate; `trivial` chunks never reach the
gate. Entries with `gate:none` (bypassed) are logged but do **not** count
toward the streak in either direction — they were never gated, so they are
evidence about proportionality, not about the gate.

**The current streak is computed, never hand-maintained.** `chunk-check.sh
log` derives it from the entries below and prints it with every recorded
line. A running count written into this header was tried and went stale
within days — 18 clean gated chunks accumulated under a header still reading
"streak 0" — which put an instruction-to-remember at the heart of the one
mechanism that adapts ceremony downward from data. This header records only
demotion **events**: when demotion fires, write the date and the streak count
it fired at. Revoke on the first post-demotion incident a gated plan would
have caught — the computed streak restarts from the entries either way.

Two things worth not re-deriving later:

- **`adjust` counts, not just `reject`.** `adjust` is the modal success case
  for a predict-then-compare gate: the human read the plan, disagreed, and the
  plan changed before implementation cost was spent. Counting only rejections
  lets a run of ten chunks in which the human adjusted eight plans read as
  "zero rejections" — retiring the gate on the strength of its own catches. The
  rule measures whether the gate ever changed an outcome, and
  `predictions.md`'s `Adjusted: y|n` line is what makes that observable at all.
- **n = 20, not 10.** At a true catch rate of 10%, observing zero catches in
  ten trials has probability ≈0.35 — the rule would fire a third of the time on
  a gate that is working. Twenty roughly halves that. A gate that costs five
  minutes does not need an aggressive retirement schedule; "retire a working
  gate" versus "keep a useless one for another ten chunks" is not a close
  comparison.

**Demoted:** never.

## Entry format

`YYYY-MM-DD | repo | chunk | gate:approve|adjust|reject|auto-pass|none | oracle-caught:y/n(N) | freeze-trip:y/n | scope-dev:y/n | bypass:y/n | ceremony-ok:y/n | context:<pack|none> | chafe: <one line>`

`gate:none` marks a bypassed chunk: logged for the proportionality question,
excluded from the demotion streak.

**`chafe:` is one record, not one sentence.** The parser reads one line per
chunk, so a literal newline breaks the entry — but the field's length is
deliberately unbounded, because in practice it carries the retro's condensed
narrative and that is the most valuable free text in the log. When it
outgrows a paragraph, the overflow belongs in the chunk's `retro.md` and the
chafe line should summarize and point to it. "One line" is a parsing
contract, not a word budget.

## What `context:` is for, and what it cannot support

`context:` names the feature's contract context pack, or `none`. It exists to
answer one question, which is the only reason it is worth a token per entry:
**is this pack worth maintaining?** A context pack is a real cost — it drifts,
it needs refreshing, and a stale one is worse than none. The comparison that
answers it is `adjust` rate and red→green iteration count for packed chunks
versus unpacked ones, once there are enough of both to look at.

**This is observational, not an experiment.** Chunks are never randomized
between packed and unpacked, and the confound is obvious and unfixable: the
repo that has a context pack is also the repo you know best. So a difference
here is a reason to look, never a measured effect. It is enough to notice
something large; it cannot support a number. Do not quote it as one.

If, after a couple of dozen chunks, packed and unpacked look the same, that
is a finding: delete the pack rather than keep paying for it. That is the
action this field exists to enable — a field that could not change a decision
would be dashboard soup, which is what the rest of this log refuses to be.

---
