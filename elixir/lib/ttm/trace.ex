defmodule TTM.Trace do
  @moduledoc """
  Append-only trace API.
  """

  @type record :: map()

  @doc """
  Append a trace record to the store.
  """
  @spec append(record()) :: :ok | {:error, term()}
  def append(_record) do
    {:error, :not_implemented}
  end

  @doc """
  Stream trace records from the store.
  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(_opts \\ []) do
    Stream.empty()
  end
end
