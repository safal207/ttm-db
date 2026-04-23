defmodule TTM.Projections do
  @moduledoc """
  Projection management.
  """

  @type projection :: module()

  @doc """
  Rebuild a projection by consuming the trace stream.

  Supports two contracts:
  - modern stateful callback set: `init/0`, `apply/2`, `finalize/1`
  - legacy callback set: `apply/1`, optional `finalize/0`
  """
  @spec rebuild(projection(), keyword()) :: {:ok, term()} | {:error, term()}
  def rebuild(projection, opts \\ [])

  def rebuild(projection, opts) when is_atom(projection) do
    cond do
      function_exported?(projection, :init, 0) and function_exported?(projection, :apply, 2) ->
        projection
        |> run_stateful(opts)
        |> then(&{:ok, &1})

      function_exported?(projection, :apply, 1) ->
        run_legacy(projection, opts)

      true ->
        {:error, :invalid_projection}
    end
  end

  def rebuild(_, _opts), do: {:error, :invalid_projection}

  @doc """
  List available projections.
  """
  @spec list() :: [projection()]
  def list, do: []

  defp run_stateful(projection, opts) do
    final_state =
      Enum.reduce(TTM.Trace.stream(opts), projection.init(), fn record, state ->
        projection.apply(record, state)
      end)

    if function_exported?(projection, :finalize, 1),
      do: projection.finalize(final_state),
      else: final_state
  end

  defp run_legacy(projection, opts) do
    TTM.Trace.stream(opts)
    |> Enum.each(&projection.apply/1)

    result =
      if function_exported?(projection, :finalize, 0),
        do: projection.finalize(),
        else: :ok

    {:ok, result}
  end
end
