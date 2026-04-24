defmodule TTM.Trace.DetsStore do
  @moduledoc """
  Disk-backed append-only trace store based on DETS.

  This store persists records between BEAM restarts.
  """

  @behaviour TTM.Trace.Store

  @counter_key :__counter__

  @impl true
  def append(record) do
    with {:ok, table} <- open_table() do
      next = next_index(table)
      :ok = :dets.insert(table, [{@counter_key, next}, {{:record, next}, record}])
      close_table(table)
      :ok
    end
  end

  @impl true
  def stream(_opts \\ []) do
    case open_table() do
      {:ok, table} ->
        records =
          table
          |> :dets.match_object({{:record, :"$1"}, :"$2"})
          |> Enum.sort_by(fn {{:record, idx}, _record} -> idx end)
          |> Enum.map(fn {{:record, _idx}, record} -> record end)

        close_table(table)
        Stream.map(records, & &1)

      {:error, _reason} ->
        Stream.map([], & &1)
    end
  end

  @doc false
  def reset! do
    with {:ok, table} <- open_table() do
      :ok = :dets.delete_all_objects(table)
      close_table(table)
      :ok
    end
  end

  defp next_index(table) do
    case :dets.lookup(table, @counter_key) do
      [{@counter_key, idx}] -> idx + 1
      [] -> 1
    end
  end

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
    Application.get_env(:ttm, :trace_dets_path, Path.join(System.tmp_dir!(), "ttm_trace_store.dets"))
  end
end
