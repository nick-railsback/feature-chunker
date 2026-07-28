# Chunk <nn>-<slug> — plan gate (predict-then-compare)

Fill every blank BEFORE opening plan.md. If you read the plan first, this gate
has nothing to teach. `chunk-check.sh freeze` refuses to run while any unfilled
blank remains, so an untouched template cannot be mistaken for a gate that
happened. (This sentence deliberately does not spell the blank marker out: the
check is a literal search of this file, so an instruction quoting the marker
would fail the check it describes.)

- Expected approach: ___
- Expected files touched: ___
- Biggest risk: ___

---- read plan.md and the red tests only after the blanks are filled ----

## Disagreements noticed

- <where the plan differed from prediction, and whether that worries you>

## Verdict

Verdict: ___          (approve | adjust | reject)
Adjusted: ___         (y/n — was the plan changed as a result of this gate?)
