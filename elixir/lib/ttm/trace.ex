defmodule TTM.Trace do
  @moduledoc """
  Append-only trace API.
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

  @doc """
  Append a trace record to the configured append-only store.
  """
  @spec append(record()) :: :ok | {:error, term()}
  def append(record) when is_map(record) do
    with :ok <- validate_required_fields(record),
         :ok <- validate_confidence(record),
         :ok <- validate_transition_uniqueness(record) do
      store().append(record)
    end
  end

  def append(_record), do: {:error, :invalid_record}

  @doc """
  Stream trace records from the configured store in append order.
  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    store().stream(opts)
  end

  @doc """
  Verify a record seal via the configured T-Trace integrity adapter.
  """
  @spec verify(term(), record()) :: :ok | {:error, term()}
  def verify(seal, record) when is_map(record) do
    integrity().verify(seal, record)
  end

  def verify(_seal, _record), do: {:error, :invalid_record}

  @doc false
  @spec reset!() :: :ok
  def reset! do
    if function_exported?(store(), :reset!, 0) do
      store().reset!()
    else
      :ok
    end
  end

  defp store do
    Application.get_env(:ttm, :trace_store, TTM.Trace.InMemoryStore)
  end

  defp integrity do
    Application.get_env(:ttm, :trace_integrity, TTM.Trace.NoopIntegrity)
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

  defp validate_transition_uniqueness(record) do
    key = transition_key(record)

    exists? =
      stream()
      |> Enum.any?(fn existing -> transition_key(existing) == key end)

    if exists?, do: {:error, {:duplicate_transition, key}}, else: :ok
  end

  defp transition_key(%{thread_id: thread_id, transition_id: transition_id}),
    do: {thread_id, transition_id}

end
