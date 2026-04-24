defmodule TTM.ProjectionsTest do
  use ExUnit.Case, async: false

  defmodule CountingProjection do
    @moduledoc false

    def name, do: "counting"

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

  defmodule LaneProjection do
    @moduledoc false
    @behaviour TTM.Projection

    @impl true
    def name, do: "lanes"

    @impl true
    def init, do: %{}

    @impl true
    def apply(%{lane: lane}, state) do
      Map.update(state, lane, 1, &(&1 + 1))
    end

    @impl true
    def finalize(state), do: state
  end

  setup do
    Application.put_env(:ttm, :projections, [CountingProjection, LaneProjection])
    TTM.Trace.reset!()
    CountingProjection.reset!()

    :ok = TTM.Trace.append(record("t-1", "main"))
    :ok = TTM.Trace.append(record("t-2", "main"))
    :ok = TTM.Trace.append(record("t-3", "shadow"))

    on_exit(fn -> Application.delete_env(:ttm, :projections) end)
    :ok
  end

  test "rebuild consumes stream for legacy projections" do
    assert {:ok, :ok} = TTM.Projections.rebuild(CountingProjection)
    assert CountingProjection.count() == 3
  end

  test "rebuild supports stateful projections" do
    assert {:ok, result} = TTM.Projections.rebuild(LaneProjection)
    assert result == %{"main" => 2, "shadow" => 1}
  end

  test "rebuild can resolve projection by registered name" do
    assert {:ok, :ok} = TTM.Projections.rebuild("counting")
    assert CountingProjection.count() == 3
  end

  test "rebuild rejects unknown projection name" do
    assert {:error, :projection_not_found} = TTM.Projections.rebuild("unknown")
  end

  test "list returns registered name/module pairs" do
    assert TTM.Projections.list() == [
             {"counting", CountingProjection},
             {"lanes", LaneProjection}
           ]
  end

  defp record(transition_id, lane) do
    %{
      thread_id: "thread-1",
      transition_id: transition_id,
      ts: "2026-04-23T00:00:00Z",
      from_state_ref: "s1",
      to_state_ref: "s2",
      admissibility: "rule:v1",
      confidence: 0.8,
      lane: lane,
      seal: "seal-#{transition_id}"
    }
  end
end
