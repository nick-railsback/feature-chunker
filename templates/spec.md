# Chunk <nn>-<slug> — spec

**Goal:** <one paragraph: the observable outcome when this chunk is done>

## Acceptance criteria

Each criterion is binary and mechanically checkable — if you can't imagine a
test asserting it, rewrite it until you can.

Each also cites the `contract` source it came from, or `none` if this spec is
the origin. A criterion that can't be traced is either an invented requirement
or a hole in the source document. An `implementation` source (an ADR, a design
doc) must never appear here: a criterion traced to an architecture decision
asserts the design rather than the contract, and the oracle built from it stays
green through a refactor that broke the feature.

1. <e.g. `cmd --flag` with no config exits 2 and prints the setup hint>
   Source: <PRD §3.2 | none>
2. <...>
   Source: <...>

---

The four fenced blocks below are **reconciled against `state.json`** by
`chunk-check.sh`: `readiness` checks `scope`, `test-paths` and `size-class`;
`freeze` checks all four. A mismatch is a hard failure in either direction.

That is the point of the fences. This document is what a human reads and
approves; `state.json` is what the script enforces. A contract that lived in
only one of them would let the enforced scope drift away from the approved one
silently — a spec declaring `src/api/` while state declares `src/` passes the
scope check on a diff the human never agreed to.

Keep the info strings exactly as written. One value per line, no commentary
inside a block, no placeholder text left behind.

## Declared scope

Files/dirs implementation may touch (enforced by `chunk-check.sh verify`):

```scope
<path/>
<path/file>
```

## Test paths

Where the oracle lives (frozen at plan approval):

```test-paths
<tests/...>
```

## Oracle command

The shell command that runs **only** these tests. `freeze` executes it and
requires a non-zero exit; `verify` executes it and requires zero, and refuses a
command that changed since freeze. Narrow it to the test paths above: a command
wider than the oracle cannot show this chunk's tests going red→green.

Track V fills this in and copies it into `state.json`'s `oracle_cmd`. If Track V
concludes a different command is needed, that is a spec change — stop and
surface; don't edit one side.

```oracle
<e.g. pytest tests/chunk-03 -q>
```

## Size class

`trivial` = no design decision, 1–2 files, reversible → bypass the lifecycle.

```size-class
<trivial | small | standard>
```

## Out of scope

<!--
`readiness` reads the section below and hard-fails on an exclusion that asserts
something about existing behaviour -- the words it looks for are the obvious
ones: already, pre-existing, inherits, inherited from, unchanged from, existing
behaviour -- unless that entry either cites a test in backticks or marks itself
(unverified).

Acceptance criteria get an executable oracle; exclusions get nothing, and they
decide what never gets built, which is where a wrong belief is most expensive
and least visible. The check cannot tell whether a claim is true. It insists
you say which, and (unverified) is a complete answer.

This guidance is an HTML comment on purpose: written as ordinary prose it would
sit inside the very section the checker scans, and the shipped template would
trip -- or quietly satisfy -- its own rule. Same class as an oracle grepping a
tree for a string its own source must contain.
-->

<adjacent things this chunk deliberately does not do>
