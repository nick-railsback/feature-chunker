# Chunk <nn>-<slug> — retro

Binary observations (see references/audit-implementation.md):

- Plan gate verdict: approve | adjust | reject | auto-pass | n/a (bypassed)
- Predictions meaningfully disagreed with plan: y/n
- Oracle caught a real defect: y/n  (red->green iterations: N)
- Oracle surfaced a defect with no red->green iteration: y/n  (where)
- Oracle violation attempted/detected: y/n
- Scope deviation: y/n  (logged in-scope / surfaced out-of-scope)
- Bypass used: y/n  (appropriate in hindsight: y/n)
- Ceremony proportionate: y/n
- Context pack loaded: <name | none>  (the plan needed something it didn't
  carry: y/n — the only observation that can retire a pack)
- Post-close outcome: pending  (always, here — feature-close resolves it to
  clean or defects(N) once someone who did not write the chunk has read it.
  The demotion streak counts nothing else)

Chafe (one line): <where the protocol got in the way or fell short>

Candidate skill change: <none | concrete edit to feature-chunker references>
  Reconcile this against CANDIDATES.md before moving on: another sighting of
  an open entry raises its Occurrences, a new maintainer-sized gap becomes a
  new entry. `log` warns while any open entry stands at two or more.

Then append the field-log line and run `bin/chunk-check.sh log <chunk-dir>`.
`gate <chunk-dir> approved` will not stamp `done` until it passes, and it
re-reads the log file rather than trusting what state.json recorded.
