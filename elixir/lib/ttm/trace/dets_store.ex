defmodule TTM.Trace.DetsStore do
  @moduledoc """
  Disk-backed append-only trace store based on DETS.

  This store persists records between BEAM restarts.
  It is an experimental/dev adapter and MUST NOT be treated as
  canonical TTM DB storage.
  """

  @behaviour TTM.Trace.Store

  @counter_key :__counter__

  @impl true
  def append(record) do
    with {:ok, table} <- open_table() do
      identity = transition_identity(record)

      case :dets.insert_new(table, {{:identity, identity}, true}) do
        true ->
          next = next_index(table)
          :ok = :dets.insert(table, [{@counter_key, next}, {{:record, next}, record}])
          close_table(table)
          :ok

        false ->
          close_table(table)
          {:error, {:duplicate_transition, identity}}
      end
    end
  end

  @impl true
  def stream(opts \\ []) do
    case open_table() do
      {:ok, table} ->
        records =
          table
          |> :dets.match_object({{:record, :"$1"}, :"$2"})
          |> Enum.sort_by(fn {{:record, idx}, _record} -> idx end)
          |> Enum.map(fn {{:record, _idx}, record} -> record end)
          |> filter_records(opts)
          |> apply_limit(opts)

        close_table(table)
        Stream.map(records, & &1)

      {:error, reason} ->
        raise "failed to open DETS trace store: #{inspect(reason)}"
    end
  end

  @doc false
  def reset! do
    if Application.get_env(:ttm, :allow_trace_reset, false) do
      with {:ok, table} <- open_table() do
        :ok = :dets.delete_all_objects(table)
        close_table(table)
        :ok
      end
    else
      {:error, :reset_disabled}
    end
  end

  defp next_index(table) do
    case :dets.lookup(table, @counter_key) do
      [{@counter_key, idx}] -> idx + 1
      [] -> 1
    end
  end

  defp transition_identity(%{thread_id: thread_id, transition_id: transition_id}),
    do: {thread_id, transition_id}

  defp open_table do
    path = table_path()

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    case :dets.open_file(__MODULE__, type: :set, file: String.to_charlist(path)) do
      {:ok, table} -> {:ok, table}
      {:error, reason} -> {:error, reason}
    end
  end

  defp close_table(table) do
    :ok = :dets.sync(table)
    :ok = :dets.close(table)
  end

  defp table_path do
    Application.get_env(
      :ttm,
      :trace_dets_path,
      Path.join(System.tmp_dir!(), "ttm_trace_store.dets")
    )
  end

  defp filter_records(records, opts) do
    records
    |> maybe_filter_thread_id(opts)
    |> maybe_filter_lane(opts)
  end

  defp maybe_filter_thread_id(records, opts) do
    case Keyword.get(opts, :thread_id) do
      nil -> records
      thread_id -> Enum.filter(records, &(&1.thread_id == thread_id))
    end
  end

  defp maybe_filter_lane(records, opts) do
    case Keyword.get(opts, :lane) do
      nil -> records
      lane -> Enum.filter(records, &(&1.lane == lane))
    end
  end

  defp apply_limit(records, opts) do
    case Keyword.get(opts, :limit) do
      nil -> records
      limit -> Enum.take(records, limit)
    end
  end
end
