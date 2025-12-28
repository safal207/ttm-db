# Projection Contract (minimal)

This document defines a minimal contract for projections.

## Requirements

- A projection MUST accept trace records as input.
- A projection MUST NOT mutate or rewrite the trace stream.
- A projection MUST be rebuildable from the trace stream.
- Projection outputs MAY be deleted or replaced without affecting ground truth.

## Interface (conceptual)

- `name`: stable projection identifier.
- `apply(record)`: consume a TraceRecord.
- `finalize()`: optional hook after stream consumption.
