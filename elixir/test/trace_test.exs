defmodule TTM.TraceTest do
  use ExUnit.Case, async: false

  defmodule CapturingStore do
    @moduledoc false

    @agent __MODULE__.Agent

    def append(record) do
      ensure_started()
      Agent.update(@agent, fn records -> [record | records] end)
      :ok
    end

    def stream(_opts) do
      ensure_started()
      @agent |> Agent.get(&Enum.reverse/1) |> Stream.map(& &1)
    end

    def reset! do
      ensure_started()
      Agent.update(@agent, fn _ -> [] end)
      :ok
    end

    defp ensure_started do
      case Process.whereis(@agent) do
        nil -> Agent.start_link(fn -> [] end, name: @agent)
        _ -> :ok
      end

      :ok
    end
  end

  setup do
    Application.put_env(:ttm, :trace_store, TTM.Trace.InMemoryStore)
    TTM.Trace.reset!()
    on_exit(fn -> Application.delete_env(:ttm, :trace_store) end)
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

  test "trace delegates to configured store" do
    Application.put_env(:ttm, :trace_store, CapturingStore)
    CapturingStore.reset!()

    entry = record("t-custom", "x", "y")

    assert :ok = TTM.Trace.append(entry)
    assert Enum.to_list(TTM.Trace.stream()) == [entry]
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
