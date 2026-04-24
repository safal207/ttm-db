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
  @string_fields [
    :thread_id,
    :transition_id,
    :ts,
    :from_state_ref,
    :to_state_ref,
    :admissibility,
    :lane
  ]

  @doc """
  Append a trace record to the configured append-only store.
  """
  @spec append(record()) :: :ok | {:error, term()}
  def append(record) when is_map(record) do
    with :ok <- validate_required_fields(record),
         :ok <- validate_string_fields(record),
         :ok <- validate_confidence(record) do
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
  @spec reset!() :: :ok | {:error, :reset_disabled}
  def reset! do
    if Application.get_env(:ttm, :allow_trace_reset, false) do
      configured_store = store()

      if function_exported?(configured_store, :reset!, 0) do
        configured_store.reset!()
      else
        :ok
      end
    else
      {:error, :reset_disabled}
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
      _ -> {:error, {:validation, {:missing_fields, missing}}}
    end
  end

  defp validate_string_fields(record) do
    invalid =
      Enum.filter(@string_fields, fn field ->
        value = Map.get(record, field)
        not (is_binary(value) and String.trim(value) != "")
      end)

    case invalid do
      [] -> :ok
      _ -> {:error, {:validation, {:invalid_string_fields, invalid}}}
    end
  end

  defp validate_confidence(%{confidence: confidence}) when is_number(confidence) do
    if confidence >= 0 and confidence <= 1,
      do: :ok,
      else: {:error, {:validation, {:invalid_confidence, confidence}}}
  end

  defp validate_confidence(_), do: {:error, {:validation, {:invalid_confidence, :missing}}}

end
