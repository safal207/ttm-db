# Architecture

TTM DB is an append-only **ground-truth trace substrate**. It records recognized transitions.
Projections are derived views that can be rebuilt at any time.

```
┌─────────────┐     append-only     ┌────────────┐     rebuildable     ┌──────────────┐
│   Flow      │  ───────────────▶  │   Trace    │  ───────────────▶  │ Projections  │
│ (present)   │                    │ (history)  │                    │   (views)    │
└─────────────┘                    └────────────┘                    └──────────────┘
```

## Concepts

- **Flow (present):** live events or transitions as they happen.
- **Trace (append-only):** a stream of recognized transitions stored immutably.
- **Projections (derived):** rebuildable views computed from the trace stream.
- **Life Line / Continuity thread:** a continuity channel identified by `thread_id`.
  TTM DB does not own life lines; it only records recognized transitions along them.

## Integrity Boundary

- **T-Trace** defines seal computation and verification.
- **TTM DB** stores seals verbatim and does not define integrity rules.

## Immutability & Addressing

- Trace records **MUST** be append-only and never updated or deleted.
- Trace records are addressable by append order and/or seal; identifiers **MUST** be immutable.
- Projections **MUST NOT** mutate trace records; they only interpret them.
