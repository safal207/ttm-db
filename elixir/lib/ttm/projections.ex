defmodule TTM.Projections do
  @moduledoc """
  Projection management.
  """

  @type projection :: module()
  @type projection_name :: String.t()

  @doc """
  Rebuild a projection by consuming the trace stream.

  Supports two contracts:
  - modern stateful callback set: `name/0`, `init/0`, `apply/2`, `finalize/1`
  - legacy callback set: `name/0`, `apply/1`, optional `finalize/0`

  The projection can be passed as module or by registered name.
  """
  @spec rebuild(projection() | projection_name(), keyword()) :: {:ok, term()} | {:error, term()}
  def rebuild(projection_or_name, opts \\ [])

  def rebuild(projection_or_name, opts) do
    with {:ok, projection} <- resolve_projection(projection_or_name),
         :ok <- validate_name_callback(projection) do
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
  end

  @doc """
  List configured projections as `{name, module}` pairs.
  """
  @spec list() :: [{projection_name(), projection()}]
  def list do
    configured_projections()
    |> Enum.filter(&function_exported?(&1, :name, 0))
    |> Enum.map(fn projection -> {projection.name(), projection} end)
  end

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

  defp resolve_projection(projection) when is_atom(projection), do: {:ok, projection}

  defp resolve_projection(name) when is_binary(name) do
    case Enum.find(list(), fn {projection_name, _module} -> projection_name == name end) do
      {_name, module} -> {:ok, module}
      nil -> {:error, :projection_not_found}
    end
  end

  defp resolve_projection(_), do: {:error, :invalid_projection}

  defp validate_name_callback(projection) do
    if function_exported?(projection, :name, 0), do: :ok, else: {:error, :invalid_projection}
  end

  defp configured_projections do
    Application.get_env(:ttm, :projections, [])
  end
end
