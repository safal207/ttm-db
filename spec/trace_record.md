# TraceRecord (canonical)

This document defines the canonical trace record for TTM DB.

## Principles

- The trace record is **append-only**.
- The trace stream is the **ground-truth history**.
- Projections are **derived, rebuildable** views.

## Record fields (MUST)

A TraceRecord MUST include:

- `thread_id`: continuity thread / life line identifier.
- `transition_id`: unique identifier for the transition instance.
- `ts`: logical or physical timestamp.
- `from_state_ref`: reference to the previous state.
- `to_state_ref`: reference to the next state.
- `admissibility`: rationale for recognition (why the transition is admitted).
- `confidence`: number in range 0..1.
- `lane`: domain or life line lane.
- `seal`: integrity field computed by T-Trace.

## Integrity (T-Trace)

- `seal` MUST be computed according to the T-Trace specification.
- `verify(seal, record)` MUST exist (may be a stub) and MUST conform to T-Trace.
- TTM DB MUST store `seal` verbatim.
- TTM DB MUST NOT invent integrity semantics.

## Semantics (MUST / MUST NOT)

- Records MUST be append-only.
- Records MUST NOT be updated or deleted.
- Projections MUST be rebuildable from the trace stream.
- Records are addressable by append order and/or seal; identifiers MUST be immutable.
- The pair (`thread_id`, `transition_id`) MUST be unique within the trace store.

## Notes

- This spec defines structure, not storage.
- If unsure, prefer omission over invention.
