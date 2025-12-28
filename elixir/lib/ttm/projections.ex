defmodule TTM.Projections do
  @moduledoc """
  Projection management.
  """

  @type projection :: module()

  @doc """
  Rebuild a projection by consuming the trace stream.
  """
  @spec rebuild(projection(), keyword()) :: :ok | {:error, term()}
  def rebuild(_projection, _opts \\ []) do
    {:error, :not_implemented}
  end

  @doc """
  List available projections.
  """
  @spec list() :: [projection()]
  def list do
    []
  end
end
