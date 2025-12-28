# T-Trace Integration

This document defines how TTM DB integrates with T-Trace.

## Scope

- T-Trace is storage-agnostic.
- T-Trace defines the canonical trace encoding, seal computation, and verification procedure.
- TTM DB stores and streams traces; it does not define integrity rules.

## Requirements (MUST / MUST NOT)

- TTM DB MUST consume T-Trace as a dependency (preferred) or a pinned vendor/submodule.
- TTM DB MUST store `seal` verbatim as defined by T-Trace.
- `verify(seal, record)` MUST exist (MAY be a stub) and MUST conform to T-Trace.
- TTM DB MUST NOT define a new integrity scheme.
- TTM DB MUST NOT define projection logic inside T-Trace.
