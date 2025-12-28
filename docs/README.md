# TTM DB

**Traces of Time and Meaning (TTM DB)** is an append-only **ground-truth trace substrate**.
It stores recognized transition traces; projections are derived, rebuildable views.

**One history. Many views. The past is never rewritten.**

## Architecture (at a glance)

Flow (present) → Trace (append-only) → Projections (derived)

## Boundary

- TTM DB stores traces.
- T-Trace defines integrity.
- Projections interpret.

The “right of transition” is expressed via admissibility on the trace record,
not via updates or mutation.

## Notes

If unsure, prefer omission over invention.
