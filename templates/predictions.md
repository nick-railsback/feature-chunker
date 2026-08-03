# Chunk <nn>-<slug> — plan gate (predict-then-compare)

Fill every blank BEFORE opening plan.md. If you read the plan first, this gate
has nothing to teach. As soon as the blanks are filled — and while the Verdict
below is still blank — run `chunk-check.sh predict <chunk-dir>`: it stamps
this file's top half so `freeze` can check the order things happened in, not
just that the blanks are gone. On a `standard` chunk the stamp is required and
`chunk-check.sh freeze` also refuses to run while any unfilled blank remains,
so an untouched template cannot be mistaken for a gate that happened. On a `small` chunk the blanks are optional
(softened 2026-07-31) — skip them honestly or fill them honestly, but the
Verdict and Adjusted lines below are required at every size. (This sentence
deliberately does not spell the blank marker out: the check is a literal search
of this file, so an instruction quoting the marker would fail the check it
describes.)

- Expected approach: ___
- Expected files touched: ___
- Biggest risk: ___

---- read plan.md and the red tests only after the blanks are filled ----

## Disagreements noticed

- <where the plan differed from prediction, and whether that worries you>

## Verdict

Verdict: ___          (approve | adjust | reject)
Adjusted: ___         (y/n — was the plan changed as a result of this gate?)
