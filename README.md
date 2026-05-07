# TTM DB — Traces of Time and Meaning

TTM DB is an append-only causal memory substrate for preserving irreversible transitions and their meaning over time.

It stores ground-truth trace records without interpretation, optimization, or mutation. Derived views, projections, verification envelopes, and analysis results live outside the immutable trace boundary.

```text
flow -> append-only trace -> read-time envelopes -> derived projections -> reviewer/audit views
```

## Core claim

TTM DB is not a general-purpose database and not an analytics engine. It is a ground-truth trace substrate for systems that need to preserve what happened, when it happened, and why a transition qualified as meaningful.

## Why this exists

AI-agent and adaptive systems often need more than current state. They need a durable record of transitions:

- which thread of continuity an event belongs to,
- what transition occurred,
- what state reference changed,
- why the transition was admissible,
- what confidence was attached,
- which lane/context it belonged to,
- and whether its seal can be verified later.

TTM DB keeps that record append-only so downstream tools can reconstruct, verify, and analyze history without mutating the ground truth.

## Design boundary

The most important boundary is:

```text
Trace is ground truth.
Projection is interpretation.
Verification envelope is read-time metadata.
```

TTM DB should not rewrite trace records to add later interpretations. If a verifier checks a seal at read time, the verification result is returned as an envelope around the record, not written back into the record.

## Current record shape

A TTM trace record is centered around transition continuity:

```text
thread_id
transition_id
ts
from_state_ref
to_state_ref
admissibility
confidence
lane
seal
metadata
```

The exact implementation may evolve, but the architectural rule stays stable: append raw transition records first; derive interpretations later.

## Reviewer path

The repository currently includes Rust and Elixir scaffolding for the trace substrate.

Rust validation path:

```bash
cd rust
cargo test
```

Elixir validation path:

```bash
cd elixir
mix test
```

## Implemented concepts

- Append-only trace API direction.
- Trace record shape for transition continuity.
- Query/filter surface for streaming trace records.
- Projection/rebuild direction.
- Verification-aware stream envelopes.
- Read-time verification metadata that does not mutate stored records.
- Rust and Elixir implementation scaffolding.

## Relationship to the Liminal Evidence Stack

TTM DB is a lower-level substrate than the current application/product layers.

- **TTM DB:** preserves immutable ground-truth transition traces.
- **LiminalDB:** stores reactive/adaptive state, timelines, snapshots, and evidence views.
- **DRP:** records decisions and supersession relationships.
- **LTP:** inspects and replays agent execution traces.
- **CML:** audits causal validity and responsibility lineage.
- **PythiaLabs:** gates high-risk agent actions before tools are called.

Short version:

```text
TTM DB stores the irreversible trace.
LiminalDB stores adaptive timelines and projections.
LTP replays traces.
CML audits causal validity.
DRP records decisions.
PythiaLabs gates actions.
```

## Non-claims

TTM DB currently does not claim:

- production database maturity,
- distributed consensus,
- full query engine capabilities,
- universal event-store replacement,
- cryptographic semantics by itself,
- production compliance guarantees,
- automatic truth validation,
- complete AI memory solution.

The narrower current claim is stronger:

```text
TTM DB is an append-only substrate for preserving transition traces without mutating ground truth.
```

## Grant / reviewer evidence

See [`docs/GRANT_EVIDENCE.md`](docs/GRANT_EVIDENCE.md) for the reviewer-facing evidence package, current limitations, roadmap, and relationship to the broader Liminal Evidence Stack.

## License

MIT.
