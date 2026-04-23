defmodule TTM.Trace do
  @moduledoc """
  Append-only trace API.

  Initial implementation keeps records in an in-memory `Agent`.
  """

  @type record :: %{
          required(:thread_id) => String.t(),
          required(:transition_id) => String.t(),
          required(:ts) => String.t(),
          required(:from_state_ref) => String.t(),
          required(:to_state_ref) => String.t(),
          required(:admissibility) => String.t(),
          required(:confidence) => number(),
          required(:lane) => String.t(),
          required(:seal) => term(),
          optional(atom() | String.t()) => term()
        }

  @required_fields [
    :thread_id,
    :transition_id,
    :ts,
    :from_state_ref,
    :to_state_ref,
    :admissibility,
    :confidence,
    :lane,
    :seal
  ]

  @store __MODULE__.Store

  @doc """
  Append a trace record to the store.

  Records are immutable once appended.
  """
  @spec append(record()) :: :ok | {:error, term()}
  def append(record) when is_map(record) do
    with :ok <- validate_required_fields(record),
         :ok <- validate_confidence(record) do
      ensure_store_started()
      Agent.update(@store, fn records -> [record | records] end)
      :ok
    end
  end

  def append(_record), do: {:error, :invalid_record}

  @doc """
  Stream trace records from the store in append order.
  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(_opts \\ []) do
    ensure_store_started()

    @store
    |> Agent.get(&Enum.reverse/1)
    |> Stream.map(& &1)
  end

  @doc """
  Verify a record seal via T-Trace integration.

  Stub for future integration.
  """
  @spec verify(term(), record()) :: {:error, :not_implemented}
  def verify(_seal, _record), do: {:error, :not_implemented}

  @doc false
  @spec reset!() :: :ok
  def reset! do
    ensure_store_started()
    Agent.update(@store, fn _ -> [] end)
  end

  defp ensure_store_started do
    case Process.whereis(@store) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> [] end, name: @store)
        :ok

      _pid ->
        :ok
    end
  end

  defp validate_required_fields(record) do
    missing = Enum.filter(@required_fields, &(!Map.has_key?(record, &1)))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_fields, missing}}
    end
  end

  defp validate_confidence(%{confidence: confidence}) when is_number(confidence) do
    if confidence >= 0 and confidence <= 1,
      do: :ok,
      else: {:error, {:invalid_confidence, confidence}}
  end

  defp validate_confidence(_), do: {:error, {:invalid_confidence, :missing}}
end
