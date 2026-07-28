# Feature: <name>

**Goal:** <the user-visible outcome this feature delivers, one paragraph>

**Constraints:** <hard boundaries: compat, perf, style, non-goals>

**Artifacts:** tracked | untracked — whether this feature's chunk docs are
committed. Set once, here, and mirrored into each chunk's `state.json`
`artifacts` key, where `readiness` reconciles it against what git is actually
doing. See references/audit-readiness.md § Feature setup.

## Sources

What this feature is derived from — PRD, ADRs, tickets, design docs.
**Pointers only.** Kind decides what a document is allowed to become:
`contract` documents can produce acceptance criteria and may reach Track V;
`implementation` documents constrain the plan and never the spec.

| Document | Kind | Derived into |
|---|---|---|
| `<path or URL to the PRD>` | contract | chunks 01–03 acceptance criteria |
| `<path to ADR-004>` | implementation | plan constraints, chunk 02 |

Once the specs are derived, **`spec.md` is authoritative.** These documents
drift and the frozen contract does not follow them. A change upstream is a spec
change: re-derive, then `readiness --rebaseline` — which clears the freeze and
sends the chunk back through the plan gate, because a contract that moved
without re-approval was never frozen.

This is not the Context packs table below. A source is read **once**, to derive
the queue and the specs; a context pack is standing knowledge re-loaded every
chunk. Listing a PRD as a context pack means paying for it on every chunk
forever.

Leave empty if there is no upstream document. An empty table is a real answer:
it says these specs are the origin, not a derivation.

## Context packs

What an agent should load before planning a chunk here, and which track may
see it. **Pointers only — never paste a pack's contents into a spec.**

| Pack | Kind | Loaded by |
|---|---|---|
| `<skill-name or path>` | contract | Track V + Track P |
| `<skill-name or path>` | implementation | Track P only |

**Kind is the whole point of this table.** Track V writes the oracle blind, so
it may see *contract* context (domain vocabulary, external interfaces,
observable invariants, how to run the tests) and never *implementation* context
(architecture, internal layout, how we usually build things here). The test:
**if this system were rewritten from scratch a different way, would this still
be true?** Yes → contract. No → implementation. Getting it wrong produces an
oracle that asserts the design instead of the contract — non-negotiable #1
failing through a new door.

Leave the table empty if there is no pack. An empty table is a real answer.

## Chunk queue

| # | Chunk | Size | Status | Notes |
|---|---|---|---|---|
| 01 | <slug> | standard | specified | |
| 02 | <slug> | small | specified | |

Statuses: specified · ready · approved · verified · done · blocked ·
bypassed — the same set `state.json` can hold, deliberately. Keep this table
current: it is the feature's state of record, and chunk state.json files are
the per-chunk detail.
