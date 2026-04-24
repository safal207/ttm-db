# TraceQuery Specification

`TraceQuery` defines a canonical **read-only** filter over the append-only trace stream.

## Purpose

TTM DB is an append-only ground-truth trace substrate. Querying history is allowed; rewriting history is not.

`TraceQuery` provides deterministic filtering semantics for stream consumers and projection rebuilds.

## Query shape

All fields are optional.

- `thread_id?` — continuity thread filter.
- `lane?` — domain / life-line lane filter.
- `from_ts?` — inclusive lower timestamp bound.
- `to_ts?` — exclusive upper timestamp bound.
- `limit?` — maximum number of records to return.
- `cursor?` — opaque continuation cursor.
- `verified?` — verification status filter.

## Verification-aware stream statuses

The query model recognizes these verification statuses:

- `verified` — seal verified by the T-Trace adapter.
- `unverified` — verification not attempted.
- `failed` — verification attempted and failed.
- `unknown` — verification status unavailable.

Boundary conditions:

- TTM DB **MAY** expose verification status.
- TTM DB **MUST NOT** invent integrity rules.
- Verification **MUST** delegate to the T-Trace adapter.
- Append policy is out of scope for this specification.

## Normative rules

- `TraceQuery` **MUST NOT** mutate trace records.
- `TraceQuery` **MUST** preserve append order unless explicitly stated otherwise.
- `TraceQuery` **MUST** be deterministic for the same trace store state.
- `cursor` **MUST** be opaque.
- Filtering **MUST NOT** change ground truth.
- Empty result **MUST** mean “no matching records,” not “storage error.”

## Notes

- `from_ts`, `to_ts`, `cursor`, and `verified` can be accepted as forward-compatible fields before full execution support is implemented.
- Full cursor pagination is out of scope for the current phase.
