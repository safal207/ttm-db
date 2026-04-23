defmodule TTM.TraceTest do
  use ExUnit.Case, async: false

  setup do
    TTM.Trace.reset!()
    :ok
  end

  test "append adds records and stream preserves append order" do
    first = record("t-1", "s1", "s2")
    second = record("t-2", "s2", "s3")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)

    assert Enum.to_list(TTM.Trace.stream()) == [first, second]
  end

  test "append validates required fields" do
    assert {:error, {:missing_fields, missing}} =
             TTM.Trace.append(%{thread_id: "thread-1", transition_id: "t-1"})

    assert :ts in missing
    assert :seal in missing
  end

  test "append validates confidence in range 0..1" do
    assert {:error, {:invalid_confidence, 1.5}} =
             TTM.Trace.append(record("t-1", "s1", "s2", confidence: 1.5))
  end

  test "verify exists as T-Trace integration stub" do
    assert {:error, :not_implemented} =
             TTM.Trace.verify("some-seal", record("t-1", "s1", "s2"))
  end

  defp record(transition_id, from_state_ref, to_state_ref, extra \\ []) do
    base = %{
      thread_id: "thread-1",
      transition_id: transition_id,
      ts: "2026-04-23T00:00:00Z",
      from_state_ref: from_state_ref,
      to_state_ref: to_state_ref,
      admissibility: "rule:v1",
      confidence: 0.9,
      lane: "main",
      seal: "seal-#{transition_id}"
    }

    Enum.into(extra, base)
  end
end
