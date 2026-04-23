defmodule TTM.Projections do
  @moduledoc """
  Projection management.
  """

  @type projection :: module()

  @doc """
  Rebuild a projection by consuming the trace stream.
  """
  @spec rebuild(projection(), keyword()) :: :ok | {:error, term()}
  def rebuild(projection, opts \\ [])

  def rebuild(projection, opts) when is_atom(projection) do
    if function_exported?(projection, :apply, 1) do
      TTM.Trace.stream(opts)
      |> Enum.each(&projection.apply/1)

      if function_exported?(projection, :finalize, 0), do: projection.finalize()
      :ok
    else
      {:error, :invalid_projection}
    end
  end

  def rebuild(_, _opts), do: {:error, :invalid_projection}

  @doc """
  List available projections.
  """
  @spec list() :: [projection()]
  def list do
    []
  end
end
