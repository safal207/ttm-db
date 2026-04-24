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

  @type verification_status :: :verified | :unverified | :failed | :unknown

  @type envelope :: %{
          required(:record) => record(),
          required(:verification_status) => verification_status(),
          required(:verification_error) => term() | nil
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

  @allowed_stream_opts [:thread_id, :lane, :from_ts, :to_ts, :limit, :cursor, :verified]
  @verification_statuses [:verified, :unverified, :failed, :unknown]
  @unknown_verification_reasons [:verify_not_configured, :verify_unavailable, :not_implemented]

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

  Accepted query options: `:thread_id`, `:lane`, `:from_ts`, `:to_ts`,
  `:limit`, `:cursor`, and `:verified`.

  `:from_ts`, `:to_ts`, `:cursor`, and `:verified` are accepted for
  forward-compatible TraceQuery semantics and may be no-op depending on
  store support. Implementations MUST document whether `:verified` is
  enforced or ignored.
  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ [])

  def stream(opts) when is_list(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError, "stream options must be a keyword list"
    end

    :ok = validate_query_opts(opts)
    store().stream(opts)
  end

  def stream(_opts), do: raise(ArgumentError, "stream options must be a keyword list")

  @doc """
  Stream trace records wrapped with read-time verification status.

  This API never mutates stored trace records; verification metadata is
  derived at read time through the configured integrity adapter.
  """
  @spec stream_envelopes(keyword()) :: Enumerable.t()
  def stream_envelopes(opts \\ [])

  def stream_envelopes(opts) when is_list(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError, "stream options must be a keyword list"
    end

    :ok = validate_query_opts(opts)

    requested_status = Keyword.get(opts, :verified)

    stream(opts)
    |> Stream.map(fn record -> envelope_for(record, requested_status) end)
    |> maybe_filter_envelopes_by_status(requested_status)
  end

  def stream_envelopes(_opts), do: raise(ArgumentError, "stream options must be a keyword list")

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

  defp envelope_for(record, nil) do
    %{record: record, verification_status: :unverified, verification_error: nil}
  end

  defp envelope_for(record, _requested_status) do
    case verify(record.seal, record) do
      :ok ->
        %{record: record, verification_status: :verified, verification_error: nil}

      {:error, reason} when reason in @unknown_verification_reasons ->
        %{record: record, verification_status: :unknown, verification_error: nil}

      {:error, reason} ->
        %{record: record, verification_status: :failed, verification_error: reason}
    end
  end

  defp maybe_filter_envelopes_by_status(stream, nil), do: stream

  defp maybe_filter_envelopes_by_status(stream, requested_status) do
    Stream.filter(stream, &(&1.verification_status == requested_status))
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

  defp validate_query_opts(opts) do
    keys = Keyword.keys(opts)
    unknown_keys = Enum.reject(keys, &(&1 in @allowed_stream_opts))

    cond do
      unknown_keys != [] ->
        raise ArgumentError, "unknown stream options: #{inspect(unknown_keys)}"

      Keyword.has_key?(opts, :limit) and not valid_limit?(Keyword.get(opts, :limit)) ->
        raise ArgumentError, "invalid :limit option, expected non-negative integer"

      Keyword.has_key?(opts, :verified) and
          Keyword.get(opts, :verified) not in @verification_statuses ->
        raise ArgumentError,
              "invalid :verified option, expected one of #{inspect(@verification_statuses)}"

      true ->
        :ok
    end
  end

  defp valid_limit?(limit), do: is_integer(limit) and limit >= 0
end
