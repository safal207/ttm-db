defmodule TTM.ProjectionsTest do
  use ExUnit.Case, async: false

  defmodule CountingProjection do
    @moduledoc false

    def apply(_record) do
      Agent.update(__MODULE__, &(&1 + 1))
    end

    def finalize do
      :ok
    end

    def count do
      Agent.get(__MODULE__, & &1)
    end

    def reset! do
      case Process.whereis(__MODULE__) do
        nil -> Agent.start_link(fn -> 0 end, name: __MODULE__)
        _pid -> Agent.update(__MODULE__, fn _ -> 0 end)
      end

      :ok
    end
  end

  setup do
    TTM.Trace.reset!()
    CountingProjection.reset!()

    :ok = TTM.Trace.append(record("t-1"))
    :ok = TTM.Trace.append(record("t-2"))
    :ok
  end

  test "rebuild consumes stream" do
    assert :ok = TTM.Projections.rebuild(CountingProjection)
    assert CountingProjection.count() == 2
  end

  test "rebuild rejects invalid projection" do
    assert {:error, :invalid_projection} = TTM.Projections.rebuild(:dummy)
  end

  test "list returns projections" do
    assert TTM.Projections.list() == []
  end

  defp record(transition_id) do
    %{
      thread_id: "thread-1",
      transition_id: transition_id,
      ts: "2026-04-23T00:00:00Z",
      from_state_ref: "s1",
      to_state_ref: "s2",
      admissibility: "rule:v1",
      confidence: 0.8,
      lane: "main",
      seal: "seal-#{transition_id}"
    }
  end
end
