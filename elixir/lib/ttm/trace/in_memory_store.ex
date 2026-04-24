defmodule TTM.Trace.InMemoryStore do
  @moduledoc """
  In-memory append-only trace store for local/dev/test usage.
  """

  @behaviour TTM.Trace.Store

  @store __MODULE__.Agent

  @impl true
  def append(record) do
    ensure_started()

    Agent.get_and_update(@store, fn %{records: records, identities: identities} = state ->
      identity = transition_identity(record)

      if MapSet.member?(identities, identity) do
        {{:error, {:duplicate_transition, identity}}, state}
      else
        new_state = %{
          state
          | records: [record | records],
            identities: MapSet.put(identities, identity)
        }

        {:ok, new_state}
      end
    end)
  end

  @impl true
  def stream(_opts \\ []) do
    ensure_started()

    @store
    |> Agent.get(fn %{records: records} -> Enum.reverse(records) end)
    |> Stream.map(& &1)
  end

  @doc false
  def reset! do
    if Application.get_env(:ttm, :allow_trace_reset, false) do
      ensure_started()
      Agent.update(@store, fn _ -> initial_state() end)
    else
      {:error, :reset_disabled}
    end
  end

  defp transition_identity(%{thread_id: thread_id, transition_id: transition_id}),
    do: {thread_id, transition_id}

  defp ensure_started do
    case Process.whereis(@store) do
      nil ->
        case Agent.start_link(fn -> initial_state() end, name: @store) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

        :ok

      _pid ->
        :ok
    end
  end

  defp initial_state do
    %{records: [], identities: MapSet.new()}
  end
end
