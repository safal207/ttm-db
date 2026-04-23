defmodule TTM.Trace.InMemoryStore do
  @moduledoc """
  In-memory append-only trace store for local/dev/test usage.
  """

  @behaviour TTM.Trace.Store

  @store __MODULE__.Agent

  @impl true
  def append(record) do
    ensure_started()
    Agent.update(@store, fn records -> [record | records] end)
  end

  @impl true
  def stream(_opts \\ []) do
    ensure_started()

    @store
    |> Agent.get(&Enum.reverse/1)
    |> Stream.map(& &1)
  end

  @doc false
  def reset! do
    ensure_started()
    Agent.update(@store, fn _ -> [] end)
  end

  defp ensure_started do
    case Process.whereis(@store) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> [] end, name: @store)
        :ok

      _pid ->
        :ok
    end
  end
end
