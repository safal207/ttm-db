# Stream Envelope Specification

## Purpose

TTM DB remains an append-only, ground-truth trace substrate.
Verification metadata is derived at read time and MUST NOT rewrite stored trace records.

Core rule: **Verification is an interpretation of integrity at read time.**

## TraceEnvelope

A TraceEnvelope MUST contain:

- `record`
- `verification_status`
- `verification_error?`

### Envelope shape

```elixir
%{
  record: record,
  verification_status: :verified | :unverified | :failed | :unknown,
  verification_error: term() | nil
}
```

## Status semantics

- `record` MUST be the original stored trace record.
- `verification_status` MUST NOT be written back into the trace record.
- Verification MUST delegate to the configured T-Trace adapter.
- If verification is not attempted, status SHOULD be `:unverified`.
- If verifier is unavailable or not configured, status SHOULD be `:unknown`.
- If verifier returns an error, status MUST be `:failed`.

## Verification mapping

- `verify(seal, record) == :ok` → `:verified`
- `verify(seal, record) == {:error, reason}` caused by integrity failure → `:failed`
  with `verification_error = reason`
- Verifier missing / not configured / unavailable / not implemented → `:unknown`
- Verification not requested → `:unverified`

TTM DB MUST NOT invent cryptographic semantics. It only calls the configured T-Trace adapter.

## API boundaries

- `TTM.Trace.stream/1` MUST continue to return raw trace records.
- `TTM.Trace.stream_envelopes/1` returns trace envelopes.
- Verification status MUST be derived at read time.
- Verification status MUST NOT be persisted into trace storage.
